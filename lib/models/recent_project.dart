import 'dart:typed_data';
import 'passport_size.dart';
import 'bg_option.dart';
import 'editor_layer.dart';

class RecentProject {
  final String id;
  final PassportSize selectedSize;
  final BgOption bgOption;
  final List<EditorLayer> layers;
  final Uint8List originalImageBytes;
  final Uint8List bgRemovedBytes;
  final Uint8List? thumbnailBytes;
  final DateTime lastSaved;

  RecentProject({
    required this.id,
    required this.selectedSize,
    required this.bgOption,
    required this.layers,
    required this.originalImageBytes,
    required this.bgRemovedBytes,
    this.thumbnailBytes,
    required this.lastSaved,
  });
}
