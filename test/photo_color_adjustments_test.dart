import 'package:flutter_test/flutter_test.dart';
import 'package:passport_maker/models/editor_layer.dart';

void main() {
  group('Photo Color Adjustments tests', () {
    test('Create EditorLayer with default color parameters', () {
      const layer = EditorLayer(
        id: 'photo',
        type: LayerType.photo,
        name: 'Photo',
      );

      expect(layer.colorHub, 'normal');
      expect(layer.hue, 0.0);
      expect(layer.tintOpacity, 0.0);
    });

    test('EditorLayer.copyWith updates colorHub, hue, and tintOpacity', () {
      const layer = EditorLayer(
        id: 'photo',
        type: LayerType.photo,
        name: 'Photo',
      );

      final updated = layer.copyWith(
        colorHub: 'warm',
        hue: 180.0,
        tintOpacity: 0.25,
      );

      expect(updated.colorHub, 'warm');
      expect(updated.hue, 180.0);
      expect(updated.tintOpacity, 0.25);

      final updated2 = updated.copyWith(
        colorHub: 'cold',
      );
      expect(updated2.colorHub, 'cold');
      expect(updated2.hue, 180.0); // Preserved
      expect(updated2.tintOpacity, 0.25); // Preserved
    });
  });
}
