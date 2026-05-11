import "package:flutter_test/flutter_test.dart";

import "package:obs_clipshow/src/widgets/rgba_color_picker.dart";

void main() {
  group("tryParseHexArgb", () {
    test("parses 6-digit with implicit opaque alpha", () {
      expect(tryParseHexArgb("#FFCC00"), 0xFFFFCC00);
      expect(tryParseHexArgb("00FF00"), 0xFF00FF00);
    });
    test("parses 8-digit AARRGGBB", () {
      expect(tryParseHexArgb("#80FF0000"), 0x80FF0000);
    });
    test("rejects bad input", () {
      expect(tryParseHexArgb("#FFF"), isNull);
      expect(tryParseHexArgb(""), isNull);
    });
  });

  group("formatHexArgb", () {
    test("pads to 8 hex digits", () {
      expect(formatHexArgb(0xFF010203), "#FF010203");
    });
  });
}
