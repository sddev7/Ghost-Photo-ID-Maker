
import 'dart:typed_data';
import 'package:flutter/material.dart';

enum BgType { transparent, solid, gradient, image }

class BgOption {
  final BgType type;
  final Color? solidColor;
  final List<Color>? gradientColors;
  final AlignmentGeometry? gradientBegin;
  final AlignmentGeometry? gradientEnd;
  final Uint8List? imageBytes;

  // Lighting properties (only applicable if type == BgType.image)
  final double brightness;
  final double contrast;
  final double exposure;
  final String colorHub; // 'normal', 'warm', 'cold'
  final double hue; // 0.0 to 360.0
  final double tintOpacity; // 0.0 to 1.0

  // Transform properties
  final Offset offset;
  final double scale;
  final double rotation;

  const BgOption._({
    required this.type,
    this.solidColor,
    this.gradientColors,
    this.gradientBegin,
    this.gradientEnd,
    this.imageBytes,
    this.brightness = 0.0,
    this.contrast = 0.0,
    this.exposure = 0.0,
    this.colorHub = 'normal',
    this.hue = 0.0,
    this.tintOpacity = 0.0,
    this.offset = Offset.zero,
    this.scale = 1.0,
    this.rotation = 0.0,
  });

  factory BgOption.transparent() => const BgOption._(type: BgType.transparent);

  factory BgOption.solid(Color color) => BgOption._(
        type: BgType.solid,
        solidColor: color,
      );

  factory BgOption.gradient({
    required List<Color> colors,
    AlignmentGeometry begin = Alignment.topLeft,
    AlignmentGeometry end = Alignment.bottomRight,
  }) =>
      BgOption._(
        type: BgType.gradient,
        gradientColors: colors,
        gradientBegin: begin,
        gradientEnd: end,
      );

  factory BgOption.image(
    Uint8List bytes, {
    double brightness = 0.0,
    double contrast = 0.0,
    double exposure = 0.0,
    String colorHub = 'normal',
    double hue = 0.0,
    double tintOpacity = 0.0,
    Offset offset = Offset.zero,
    double scale = 1.0,
    double rotation = 0.0,
  }) =>
      BgOption._(
        type: BgType.image,
        imageBytes: bytes,
        brightness: brightness,
        contrast: contrast,
        exposure: exposure,
        colorHub: colorHub,
        hue: hue,
        tintOpacity: tintOpacity,
        offset: offset,
        scale: scale,
        rotation: rotation,
      );

  bool get isTransparent => type == BgType.transparent;
  bool get isSolid => type == BgType.solid;
  bool get isGradient => type == BgType.gradient;
  bool get isImage => type == BgType.image;

  BgOption copyWith({
    BgType? type,
    Color? solidColor,
    List<Color>? gradientColors,
    AlignmentGeometry? gradientBegin,
    AlignmentGeometry? gradientEnd,
    Uint8List? imageBytes,
    double? brightness,
    double? contrast,
    double? exposure,
    String? colorHub,
    double? hue,
    double? tintOpacity,
    Offset? offset,
    double? scale,
    double? rotation,
  }) {
    return BgOption._(
      type: type ?? this.type,
      solidColor: solidColor ?? this.solidColor,
      gradientColors: gradientColors ?? this.gradientColors,
      gradientBegin: gradientBegin ?? this.gradientBegin,
      gradientEnd: gradientEnd ?? this.gradientEnd,
      imageBytes: imageBytes ?? this.imageBytes,
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      exposure: exposure ?? this.exposure,
      colorHub: colorHub ?? this.colorHub,
      hue: hue ?? this.hue,
      tintOpacity: tintOpacity ?? this.tintOpacity,
      offset: offset ?? this.offset,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
    );
  }
}

/// Preset gradient options shown in the BG panel
class BgPresets {
  static final List<BgOption> gradients = [
    BgOption.gradient(colors: [const Color(0xFFFFFFFF), const Color(0xFFE8E8E8)]),
    BgOption.gradient(colors: [const Color(0xFFE8F4FD), const Color(0xFFBBD6F0)]),
    BgOption.gradient(colors: [const Color(0xFF667EEA), const Color(0xFF764BA2)]),
    BgOption.gradient(colors: [const Color(0xFFF093FB), const Color(0xFFF5576C)]),
    BgOption.gradient(colors: [const Color(0xFF4FACFE), const Color(0xFF00F2FE)]),
    BgOption.gradient(colors: [const Color(0xFF43E97B), const Color(0xFF38F9D7)]),
    BgOption.gradient(colors: [const Color(0xFFFFA726), const Color(0xFFFF7043)]),
    BgOption.gradient(colors: [const Color(0xFF0D9488), const Color(0xFF14B8A6)]),
    BgOption.gradient(colors: [const Color(0xFF1A2540), const Color(0xFF0A0F1E)]),
    BgOption.gradient(
      colors: [const Color(0xFF6366F1), const Color(0xFF8B5CF6)],
    ),
    BgOption.gradient(
      colors: [const Color(0xFFEC4899), const Color(0xFFF472B6)],
    ),
    BgOption.gradient(
      colors: [const Color(0xFF10B981), const Color(0xFF34D399)],
    ),
  ];

  static final List<Color> solidColors = [
    Colors.white,
    const Color(0xFFF8FAFC),
    const Color(0xFFE2E8F0),
    const Color(0xFFCBD5E1),
    const Color(0xFFBFDCFF),
    const Color(0xFFD1FAE5),
    const Color(0xFFFEF3C7),
    const Color(0xFFFCE7F3),
    const Color(0xFF0D9488),
    const Color(0xFF2563EB),
    const Color(0xFF7C3AED),
    const Color(0xFFDC2626),
    const Color(0xFF16A34A),
    const Color(0xFFD97706),
    Colors.black,
    const Color(0xFF0A0F1E),
  ];
}