import 'package:flutter/material.dart';

enum BrushMode { erase, restore }

class BrushStroke {
  final List<Offset> points;
  final BrushMode mode;
  final double radius;

  const BrushStroke({
    required this.points,
    required this.mode,
    required this.radius,
  });

  Map<String, dynamic> toJson() {
    return {
      'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
      'mode': mode.name,
      'radius': radius,
    };
  }

  factory BrushStroke.fromJson(Map<String, dynamic> json) {
    final modeName = json['mode'] as String? ?? 'erase';
    final mode = BrushMode.values.firstWhere(
      (e) => e.name == modeName,
      orElse: () => BrushMode.erase,
    );
    final pointsList = json['points'] as List? ?? [];
    final points = pointsList
        .map((p) => Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble()))
        .toList();
    return BrushStroke(
      points: points,
      mode: mode,
      radius: (json['radius'] as num?)?.toDouble() ?? 20.0,
    );
  }
}

enum LayerType { photo, text, shape, clothing }

enum ShapeType { rectangle, circle, oval }

class EditorLayer {
  final String id;
  final LayerType type;
  final String name;
  final bool isVisible;
  
  // Transform properties
  final Offset offset;
  final double scale;
  final double rotation;

  // Text specific properties
  final String? text;
  final Color? color;
  final double? fontSize;
  final String? fontFamily;
  final bool? isBold;
  final bool? isItalic;

  // Shape specific properties
  final ShapeType? shapeType;
  final Color? fillColor;
  final Color? strokeColor;
  final double? strokeWidth;

  // Clothing specific properties
  final String? clothingAssetPath;

  // Lighting specific properties
  final double brightness;
  final double contrast;
  final double exposure;

  // Color specific properties
  final String colorHub; // 'normal', 'warm', 'cold'
  final double hue; // 0.0 to 360.0
  final double tintOpacity; // 0.0 to 1.0

  // Brush strokes specific to photo layer
  final List<BrushStroke> brushStrokes;

  const EditorLayer({
    required this.id,
    required this.type,
    required this.name,
    this.isVisible = true,
    this.offset = Offset.zero,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.text,
    this.color,
    this.fontSize,
    this.fontFamily,
    this.isBold,
    this.isItalic,
    this.shapeType,
    this.fillColor,
    this.strokeColor,
    this.strokeWidth,
    this.clothingAssetPath,
    this.brightness = 0.0,
    this.contrast = 0.0,
    this.exposure = 0.0,
    this.colorHub = 'normal',
    this.hue = 0.0,
    this.tintOpacity = 0.0,
    this.brushStrokes = const [],
  });

  EditorLayer copyWith({
    String? name,
    bool? isVisible,
    Offset? offset,
    double? scale,
    double? rotation,
    String? text,
    Color? color,
    double? fontSize,
    String? fontFamily,
    bool? isBold,
    bool? isItalic,
    ShapeType? shapeType,
    Color? fillColor,
    Color? strokeColor,
    double? strokeWidth,
    String? clothingAssetPath,
    double? brightness,
    double? contrast,
    double? exposure,
    String? colorHub,
    double? hue,
    double? tintOpacity,
    List<BrushStroke>? brushStrokes,
  }) {
    return EditorLayer(
      id: id,
      type: type,
      name: name ?? this.name,
      isVisible: isVisible ?? this.isVisible,
      offset: offset ?? this.offset,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      text: text ?? this.text,
      color: color ?? this.color,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      isBold: isBold ?? this.isBold,
      isItalic: isItalic ?? this.isItalic,
      shapeType: shapeType ?? this.shapeType,
      fillColor: fillColor ?? this.fillColor,
      strokeColor: strokeColor ?? this.strokeColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      clothingAssetPath: clothingAssetPath ?? this.clothingAssetPath,
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      exposure: exposure ?? this.exposure,
      colorHub: colorHub ?? this.colorHub,
      hue: hue ?? this.hue,
      tintOpacity: tintOpacity ?? this.tintOpacity,
      brushStrokes: brushStrokes ?? this.brushStrokes,
    );
  }
}
