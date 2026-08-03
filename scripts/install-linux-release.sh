#!/usr/bin/env bash
# Build a Flutter Linux release and install it for the current user (or a
# chosen prefix), including a GNOME/XDG .desktop entry for system launchers.
#
# Usage:
#   ./scripts/install-linux-release.sh [options]
#
# Options:
#   --prefix DIR     Install prefix for the app bundle (default: ~/.local/opt/clipshow)
#   --skip-build     Reuse an existing release bundle under build/linux/
#   --icon PATH      PNG/SVG to install as the launcher icon (optional)
#   --desktop-dir D  Where to write the .desktop file
#                    (default: ~/.local/share/applications)
#   -h, --help       Show this help
#
# Examples:
#   ./scripts/install-linux-release.sh
#   ./scripts/install-linux-release.sh --prefix "$HOME/apps/clipshow"
#   sudo ./scripts/install-linux-release.sh --prefix /opt/clipshow \
#     --desktop-dir /usr/local/share/applications

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PREFIX="${HOME}/.local/opt/clipshow"
DESKTOP_DIR="${HOME}/.local/share/applications"
ICON_SRC=""
SKIP_BUILD=0
APP_NAME="clipshow"
DESKTOP_ID="com.shootingsportsanalyst.clipshow"
DESKTOP_TEMPLATE="${REPO_ROOT}/linux/packaging/clipshow.desktop.in"

usage() {
  sed -n '2,22p' "$0" | sed 's/^# \?//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      PREFIX="${2:?--prefix requires a directory}"
      shift 2
      ;;
    --desktop-dir)
      DESKTOP_DIR="${2:?--desktop-dir requires a directory}"
      shift 2
      ;;
    --icon)
      ICON_SRC="${2:?--icon requires a path}"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "${DESKTOP_TEMPLATE}" ]]; then
  echo "Missing desktop template: ${DESKTOP_TEMPLATE}" >&2
  exit 1
fi

cd "${REPO_ROOT}"

if [[ "${SKIP_BUILD}" -eq 0 ]]; then
  echo "==> flutter pub get"
  flutter pub get
  echo "==> flutter build linux --release"
  flutter build linux --release
else
  echo "==> Skipping build (--skip-build)"
fi

BUNDLE=""
for candidate in \
  "${REPO_ROOT}/build/linux/x64/release/bundle" \
  "${REPO_ROOT}/build/linux/arm64/release/bundle"
do
  if [[ -x "${candidate}/${APP_NAME}" ]]; then
    BUNDLE="${candidate}"
    break
  fi
done

if [[ -z "${BUNDLE}" ]]; then
  echo "No release bundle found under build/linux/*/release/bundle/${APP_NAME}" >&2
  echo "Run without --skip-build, or build with: flutter build linux --release" >&2
  exit 1
fi

echo "==> Installing bundle from ${BUNDLE}"
echo "    -> ${PREFIX}"
mkdir -p "${PREFIX}"
# Replace contents so stale lib/data from older builds do not linger.
rsync -a --delete "${BUNDLE}/" "${PREFIX}/"
chmod +x "${PREFIX}/${APP_NAME}"

EXEC_PATH="${PREFIX}/${APP_NAME}"
ICON_NAME="video-x-generic"

if [[ -n "${ICON_SRC}" ]]; then
  if [[ ! -f "${ICON_SRC}" ]]; then
    echo "Icon not found: ${ICON_SRC}" >&2
    exit 1
  fi
  case "${DESKTOP_DIR}" in
    /usr/*|/usr/local/*)
      ICONS_ROOT="$(dirname "${DESKTOP_DIR}")/icons/hicolor"
      ;;
    *)
      ICONS_ROOT="${HOME}/.local/share/icons/hicolor"
      ;;
  esac
  case "${ICON_SRC}" in
    *.svg)
      ICON_DIR="${ICONS_ROOT}/scalable/apps"
      ICON_DEST="${ICON_DIR}/${DESKTOP_ID}.svg"
      ;;
    *)
      ICON_DIR="${ICONS_ROOT}/256x256/apps"
      ICON_DEST="${ICON_DIR}/${DESKTOP_ID}.png"
      ;;
  esac
  mkdir -p "${ICON_DIR}"
  cp -f "${ICON_SRC}" "${ICON_DEST}"
  ICON_NAME="${DESKTOP_ID}"
  echo "==> Installed icon ${ICON_DEST}"
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t "${ICONS_ROOT}" 2>/dev/null || true
  fi
fi

mkdir -p "${DESKTOP_DIR}"
DESKTOP_OUT="${DESKTOP_DIR}/${DESKTOP_ID}.desktop"
sed \
  -e "s|@EXEC@|${EXEC_PATH}|g" \
  -e "s|@ICON@|${ICON_NAME}|g" \
  "${DESKTOP_TEMPLATE}" > "${DESKTOP_OUT}"
chmod 644 "${DESKTOP_OUT}"
echo "==> Wrote ${DESKTOP_OUT}"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "${DESKTOP_DIR}" 2>/dev/null || true
fi

echo
echo "Installed Clipshow."
echo "  Binary:  ${EXEC_PATH}"
echo "  Launcher: ${DESKTOP_OUT}"
echo "Search for \"Clipshow\" in Activities / your app menu, or run:"
echo "  ${EXEC_PATH}"
