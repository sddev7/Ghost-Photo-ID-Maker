import 'package:flutter/services.dart';

class GalleryService {
  GalleryService._();
  static final GalleryService instance = GalleryService._();

  static const MethodChannel _channel = MethodChannel('in.sddev.passport_maker/gallery');

  /// Toggle screenshot secure window mode.
  Future<void> setSecure(bool secure) async {
    try {
      await _channel.invokeMethod<void>('setSecure', {
        'secure': secure,
      });
    } on PlatformException catch (_) {
      // Ignored on non-supported platforms
    }
  }
}