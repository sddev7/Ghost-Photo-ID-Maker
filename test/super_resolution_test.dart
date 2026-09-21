import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:passport_maker/services/super_resolution_service.dart';

Future<ui.Image> createDummyImage(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF00FF00),
  );
  final picture = recorder.endRecording();
  final img = await picture.toImage(width, height);
  picture.dispose();
  return img;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SuperResolutionService inference test', () async {
    print('Starting SuperResolutionService test...');
    final service = SuperResolutionService(tileSize: 128, overlap: 8);
    
    // Load the model file directly from assets
    final modelPath = 'assets/models/realesrgan.onnx';
    print('Initializing model from: $modelPath');
    await service.initializeModelFromFile(modelPath);
    print('Model initialized successfully.');

    final dummyImage = await createDummyImage(128, 128);
    print('Created dummy image of size 128x128.');

    try {
      print('Running upscaleImage...');
      final result = await service.upscaleImage(
        dummyImage,
        4,
        enhanceIntensity: 0.60,
        onProgress: (progress, message) {
          print('Progress: ${(progress * 100).toStringAsFixed(1)}% - $message');
        },
      );
      print('Upscale completed. Result: $result');
      if (result != null) {
        print('Result size: ${result.width}x${result.height}');
      }
    } catch (e, stackTrace) {
      print('EXCEPTION CAUGHT IN TEST:');
      print(e);
      print(stackTrace);
      rethrow;
    }
  });
}
