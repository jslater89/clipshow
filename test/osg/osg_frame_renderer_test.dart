import "dart:typed_data";
import "dart:ui" as ui;

import "package:flutter_test/flutter_test.dart";

import "package:obs_clipshow/src/osg/osg_bake_models.dart";
import "package:obs_clipshow/src/osg/osg_frame_renderer.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";

Future<ui.Image> _decodePng(Uint8List bytes) async {
  final ui.Codec codec = await ui.instantiateImageCodec(bytes);
  final ui.FrameInfo frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

Future<bool> _hasVisiblePixels(ui.Image image) async {
  final ByteData? data = await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  );
  if (data == null) {
    return false;
  }
  for (int i = 3; i < data.lengthInBytes; i += 4) {
    if (data.getUint8(i) != 0) {
      return true;
    }
  }
  return false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("OsgFrameRenderer", () {
    const int outW = 320;
    const int outH = 180;

    OsgFrameRenderer buildRenderer() {
      final OsgPreset solidPreset = OsgPreset.empty().copyWith(
        enabled: true,
        templateSolidArgb: 0xFF2255AA,
        slots: <OsgSlot>[
          const OsgSlot(
            textSource: OsgTextSource.fixed,
            fixedText: "Hello Bake",
            box: OsgNormRect(x: 0.05, y: 0.1, width: 0.9, height: 0.8),
            fontSizeNorm: 0.4,
          ),
        ],
      );
      final List<OsgPreset> presets = <OsgPreset>[
        solidPreset,
        OsgPreset.empty(),
        OsgPreset.empty(),
        OsgPreset.empty(),
        OsgPreset.empty(),
      ];
      return OsgFrameRenderer(
        presets: presets,
        cues: const <OsgBakeCue>[
          OsgBakeCue(
            slot: OsgPresetSlot.preset1,
            start: OsgBakeAnchor.clipStart(),
            end: OsgBakeAnchor.absoluteMs(4000),
          ),
        ],
        clipDurationMs: 10000,
        outputWidthPx: outW,
        outputHeightPx: outH,
        semanticTextByTypeId: const <int, String>{},
        annotationsText: "",
        workspaceRoot: "",
      );
    }

    test(
      "frame inside cue window has content; outside is fully transparent",
      () async {
        final OsgFrameRenderer renderer = buildRenderer();
        await renderer.loadAssets();
        try {
          // t=2000: inside window, fully entered (enter duration 240 ms).
          final Uint8List inside = await renderer.renderFramePng(2000);
          // t=6000: well past the cue's end plus its exit transition.
          final Uint8List outside = await renderer.renderFramePng(6000);

          final ui.Image insideImage = await _decodePng(inside);
          final ui.Image outsideImage = await _decodePng(outside);
          expect(insideImage.width, outW);
          expect(insideImage.height, outH);
          expect(outsideImage.width, outW);
          expect(outsideImage.height, outH);

          expect(await _hasVisiblePixels(insideImage), isTrue);
          expect(await _hasVisiblePixels(outsideImage), isFalse);

          insideImage.dispose();
          outsideImage.dispose();
        } finally {
          renderer.dispose();
        }
      },
    );

    test(
      "cue starting at clip start skips the intro transition entirely",
      () async {
        final OsgFrameRenderer renderer = buildRenderer();
        await renderer.loadAssets();
        try {
          // t=0: with a clip-start cue, the enter lead-in falls before t=0
          // and is never sampled, so the OSG is already fully visible.
          final Uint8List atZero = await renderer.renderFramePng(0);
          final ui.Image image = await _decodePng(atZero);
          expect(await _hasVisiblePixels(image), isTrue);
          image.dispose();
        } finally {
          renderer.dispose();
        }
      },
    );

    test("mid-enter frame renders with partial opacity content", () async {
      final OsgFrameRenderer renderer = OsgFrameRenderer(
        presets: <OsgPreset>[
          OsgPreset.empty().copyWith(
            enabled: true,
            templateSolidArgb: 0xFF2255AA,
            slots: <OsgSlot>[
              const OsgSlot(
                textSource: OsgTextSource.fixed,
                fixedText: "Hello Bake",
                box: OsgNormRect(x: 0.05, y: 0.1, width: 0.9, height: 0.8),
                fontSizeNorm: 0.4,
              ),
            ],
          ),
          OsgPreset.empty(),
          OsgPreset.empty(),
          OsgPreset.empty(),
          OsgPreset.empty(),
        ],
        cues: const <OsgBakeCue>[
          // Starts mid-clip so the 240 ms enter lead-in is fully sampled.
          OsgBakeCue(
            slot: OsgPresetSlot.preset1,
            start: OsgBakeAnchor.absoluteMs(2000),
            end: OsgBakeAnchor.absoluteMs(6000),
          ),
        ],
        clipDurationMs: 10000,
        outputWidthPx: outW,
        outputHeightPx: outH,
        semanticTextByTypeId: const <int, String>{},
        annotationsText: "",
        workspaceRoot: "",
      );
      await renderer.loadAssets();
      try {
        // t=1880: halfway through the 240 ms enter lead-in (1760..2000).
        final Uint8List midEnter = await renderer.renderFramePng(1880);
        final ui.Image image = await _decodePng(midEnter);
        expect(await _hasVisiblePixels(image), isTrue);
        image.dispose();
      } finally {
        renderer.dispose();
      }
    });
  });
}
