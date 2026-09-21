
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class ImageUtils {
  ImageUtils._();

  /// Convert ui.Image to PNG Uint8List.
  static Future<Uint8List?> uiImageToBytes(ui.Image image) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  /// Convert PNG bytes to ui.Image.
  static Future<ui.Image> bytesToUiImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  /// Resize image bytes to given width/height using the `image` package.
  static Uint8List? resizeBytes({
    required Uint8List bytes,
    required int width,
    required int height,
  }) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final resized = img.copyResize(decoded, width: width, height: height);
    return Uint8List.fromList(img.encodePng(resized));
  }

  /// Flip image horizontally.
  static Uint8List? flipHorizontal(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final flipped = img.flipHorizontal(decoded);
    return Uint8List.fromList(img.encodePng(flipped));
  }

  /// Flip image vertically.
  static Uint8List? flipVertical(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final flipped = img.flipVertical(decoded);
    return Uint8List.fromList(img.encodePng(flipped));
  }

  /// Rotate image by angle (90, 180, 270 degrees).
  static Uint8List? rotateBytes(Uint8List bytes, int angleDegrees) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final rotated = img.copyRotate(decoded, angle: angleDegrees.toDouble());
    return Uint8List.fromList(img.encodePng(rotated));
  }

  /// Get image dimensions without decoding full image.
  static Future<Size?> getImageSize(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final size = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
      return size;
    } catch (_) {
      return null;
    }
  }

  /// Find the bounding box of non-transparent pixels (alpha > 10).
  static Future<Rect> getForegroundBounds(Uint8List bytes) async {
    return Future.microtask(() {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        return const Rect.fromLTWH(0, 0, 0, 0);
      }

      int minX = decoded.width;
      int maxX = 0;
      int minY = decoded.height;
      int maxY = 0;
      bool found = false;

      for (int y = 0; y < decoded.height; y++) {
        for (int x = 0; x < decoded.width; x++) {
          final pixel = decoded.getPixel(x, y);
          // Check alpha channel
          if (pixel.a > 10) {
            found = true;
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
          }
        }
      }

      if (!found) {
        return Rect.fromLTWH(0, 0, decoded.width.toDouble(), decoded.height.toDouble());
      }

      return Rect.fromLTRB(
        minX.toDouble(),
        minY.toDouble(),
        maxX.toDouble(),
        maxY.toDouble(),
      );
    });
  }

  /// Create a checkerboard pattern image for transparency preview.
  static Widget checkerboardWidget({
    double tileSize = 16,
    Color color1 = const Color(0xFF2A2A2A),
    Color color2 = const Color(0xFF3A3A3A),
  }) {
    return CustomPaint(
      painter: _CheckerboardPainter(
        tileSize: tileSize,
        color1: color1,
        color2: color2,
      ),
    );
  }
}

class _CheckerboardPainter extends CustomPainter {
  final double tileSize;
  final Color color1;
  final Color color2;

  _CheckerboardPainter({
    required this.tileSize,
    required this.color1,
    required this.color2,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint1 = Paint()..color = color1;
    final paint2 = Paint()..color = color2;

    final cols = (size.width / tileSize).ceil();
    final rows = (size.height / tileSize).ceil();

    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final isEven = (row + col) % 2 == 0;
        final rect = Rect.fromLTWH(
          col * tileSize,
          row * tileSize,
          tileSize,
          tileSize,
        );
        canvas.drawRect(rect, isEven ? paint1 : paint2);
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerboardPainter old) =>
      old.tileSize != tileSize ||
      old.color1 != color1 ||
      old.color2 != color2;
}