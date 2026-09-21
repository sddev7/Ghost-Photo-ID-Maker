import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passport_maker/models/editor_layer.dart';

void main() {
  group('Clothing Layer tests', () {
    test('Create EditorLayer with LayerType.clothing and path', () {
      const layer = EditorLayer(
        id: 'test_clothing_1',
        type: LayerType.clothing,
        name: 'Black Suit',
        clothingAssetPath: 'assets/clothes/man_suit_black.png',
        scale: 1.2,
        rotation: 0.15,
        offset: Offset(10, 20),
      );

      expect(layer.type, LayerType.clothing);
      expect(layer.clothingAssetPath, 'assets/clothes/man_suit_black.png');
      expect(layer.scale, 1.2);
      expect(layer.rotation, 0.15);
      expect(layer.offset, const Offset(10, 20));
    });

    test('EditorLayer.copyWith updates clothingAssetPath', () {
      const layer = EditorLayer(
        id: 'test_clothing_2',
        type: LayerType.clothing,
        name: 'Black Suit',
        clothingAssetPath: 'assets/clothes/man_suit_black.png',
      );

      final updated = layer.copyWith(
        name: 'Navy Suit',
        clothingAssetPath: 'assets/clothes/man_suit_blue.png',
        scale: 1.5,
      );

      expect(updated.id, 'test_clothing_2'); // Should not change
      expect(updated.name, 'Navy Suit');
      expect(updated.clothingAssetPath, 'assets/clothes/man_suit_blue.png');
      expect(updated.scale, 1.5);
    });
  });
}
