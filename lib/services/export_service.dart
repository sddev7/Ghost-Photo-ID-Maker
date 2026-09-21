import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

enum ExportFormat { png, jpeg }

class ExportResult {
  final bool success;
  final String? filePath;
  final String? error;

  const ExportResult({
    required this.success,
    this.filePath,
    this.error,
  });
}

class ExportService {
  ExportService._();
  static final ExportService instance = ExportService._();

  /// Capture a RepaintBoundary by its GlobalKey and return raw PNG bytes.
  Future<Uint8List?> captureWidget({
    required RenderRepaintBoundary boundary,
    double pixelRatio = 3.0,
  }) async {
    final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return byteData?.buffer.asUint8List();
  }

  /// Save bytes to a temp file and then to gallery.
  Future<ExportResult> saveToGallery({
    required Uint8List bytes,
    ExportFormat format = ExportFormat.png,
    String albumName = 'Passport Maker',
  }) async {
    try {
      // Check / request permission
      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        final granted = await Gal.requestAccess(toAlbum: true);
        if (!granted) {
          return const ExportResult(
            success: false,
            error: 'Gallery permission denied',
          );
        }
      }

      // Write to temp file
      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ext = format == ExportFormat.jpeg ? 'jpg' : 'png';
      final fileName = 'passport_$ts.$ext';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);

      // Save to gallery album
      await Gal.putImage(file.path, album: albumName);

      // Clean up temp file
      await file.delete();

      return ExportResult(success: true, filePath: fileName);
    } catch (e) {
      return ExportResult(success: false, error: e.toString());
    }
  }

  /// Full pipeline: capture → save.
  Future<ExportResult> captureAndSave({
    required RenderRepaintBoundary boundary,
    double pixelRatio = 3.0,
    ExportFormat format = ExportFormat.png,
  }) async {
    final bytes = await captureWidget(
      boundary: boundary,
      pixelRatio: pixelRatio,
    );
    if (bytes == null) {
      return const ExportResult(success: false, error: 'Capture failed');
    }
    return saveToGallery(bytes: bytes, format: format);
  }
}