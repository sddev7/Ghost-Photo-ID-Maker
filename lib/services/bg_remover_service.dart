import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:image_background_remover/image_background_remover.dart';

class BgRemoverService {
  BgRemoverService._();
  static final BgRemoverService instance = BgRemoverService._();

  bool _initialized = false;

  /// Warm up the ONNX model. Call once early (e.g., in splash/home).
  Future<void> initialize() async {
    if (_initialized) return;
    await BackgroundRemover.instance.initializeOrt();
    _initialized = true;
  }

  /// Remove background from image bytes.
  /// Returns a [ui.Image] with transparent background on success.
  /// Throws on failure.
  Future<ui.Image> removeBg(Uint8List imageBytes, {double threshold = 0.65}) async {
    if (!_initialized) await initialize();
    final result = await BackgroundRemover.instance.removeBg(
      imageBytes,
      threshold: threshold,
    );
    return result;
  }

  /// Remove background and return PNG bytes directly.
  Future<Uint8List> removeBgToBytes(Uint8List imageBytes, {double threshold = 0.65}) async {
    final uiImage = await removeBg(imageBytes, threshold: threshold);
    final byteData = await uiImage.toByteData(
      format: ui.ImageByteFormat.png,
    );
    if (byteData == null) throw Exception('Failed to encode image to PNG');
    return byteData.buffer.asUint8List();
  }
}