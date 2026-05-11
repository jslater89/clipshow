import "dart:io";
import "dart:typed_data";
import "dart:ui" as ui;

/// Reads template image pixel width / height from [file] (async).
Future<double?> osgReadTemplatePixelAspect(File file) async {
  try {
    final Uint8List bytes = await file.readAsBytes();
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo fi = await codec.getNextFrame();
    final int w = fi.image.width;
    final int h = fi.image.height;
    fi.image.dispose();
    if (h <= 0) {
      return null;
    }
    return w / h;
  } catch (_) {
    return null;
  }
}
