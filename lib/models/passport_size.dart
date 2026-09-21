
import 'package:flutter/material.dart';

enum SizeUnit { mm, px }

class PassportSize {
  final String id;
  final String label;
  final String country;
  final double width;  // mm or px depending on unit
  final double height;
  final SizeUnit unit;
  final String? emoji;
  final String? category;
  final String? description;

  const PassportSize({
    required this.id,
    required this.label,
    required this.country,
    required this.width,
    required this.height,
    this.unit = SizeUnit.mm,
    this.emoji,
    this.category,
    this.description,
  });

  double get aspectRatio => width / height;

  /// Convert mm to pixels at 300 DPI for export
  Size get exportSizePx {
    if (unit == SizeUnit.px) return Size(width, height);
    const dpi = 300.0;
    const mmPerInch = 25.4;
    return Size(width / mmPerInch * dpi, height / mmPerInch * dpi);
  }

  String get dimensionLabel {
    if (unit == SizeUnit.px) {
      return '${width.toInt()}×${height.toInt()} px';
    }
    return '${width % 1 == 0 ? width.toInt() : width}×${height % 1 == 0 ? height.toInt() : height} mm';
  }

  @override
  String toString() => label;
}

class PassportSizes {
  static const List<PassportSize> all = [
    // ── Americas ──────────────────────────────────────────────────────────
    PassportSize(
      id: 'us_passport',
      label: 'US Passport / Visa',
      country: 'United States',
      width: 51,
      height: 51,
      emoji: '🇺🇸',
    ),
    PassportSize(
      id: 'ca_passport',
      label: 'Canada Passport',
      country: 'Canada',
      width: 50,
      height: 70,
      emoji: '🇨🇦',
    ),
    PassportSize(
      id: 'br_passport',
      label: 'Brazil Passport',
      country: 'Brazil',
      width: 30,
      height: 40,
      emoji: '🇧🇷',
    ),
    PassportSize(
      id: 'mx_passport',
      label: 'Mexico Passport',
      country: 'Mexico',
      width: 35,
      height: 45,
      emoji: '🇲🇽',
    ),
    PassportSize(
      id: 'ar_passport',
      label: 'Argentina Passport',
      country: 'Argentina',
      width: 40,
      height: 40,
      emoji: '🇦🇷',
    ),

    // ── Europe ────────────────────────────────────────────────────────────
    PassportSize(
      id: 'uk_passport',
      label: 'UK Passport',
      country: 'United Kingdom',
      width: 35,
      height: 45,
      emoji: '🇬🇧',
    ),
    PassportSize(
      id: 'eu_schengen',
      label: 'EU / Schengen',
      country: 'European Union',
      width: 35,
      height: 45,
      emoji: '🇪🇺',
    ),
    PassportSize(
      id: 'de_passport',
      label: 'Germany Passport',
      country: 'Germany',
      width: 35,
      height: 45,
      emoji: '🇩🇪',
    ),
    PassportSize(
      id: 'fr_passport',
      label: 'France Passport',
      country: 'France',
      width: 35,
      height: 45,
      emoji: '🇫🇷',
    ),
    PassportSize(
      id: 'ru_passport',
      label: 'Russia Passport',
      country: 'Russia',
      width: 35,
      height: 45,
      emoji: '🇷🇺',
    ),

    // ── Asia ──────────────────────────────────────────────────────────────
    PassportSize(
      id: 'in_passport',
      label: 'India Passport (35×45)',
      country: 'India',
      width: 35,
      height: 45,
      emoji: '🇮🇳',
    ),
    PassportSize(
      id: 'in_visa',
      label: 'India Visa (51×51)',
      country: 'India',
      width: 51,
      height: 51,
      emoji: '🇮🇳',
    ),
    PassportSize(
      id: 'cn_passport',
      label: 'China Passport',
      country: 'China',
      width: 33,
      height: 48,
      emoji: '🇨🇳',
    ),
    PassportSize(
      id: 'jp_passport',
      label: 'Japan Passport',
      country: 'Japan',
      width: 35,
      height: 45,
      emoji: '🇯🇵',
    ),
    PassportSize(
      id: 'kr_passport',
      label: 'South Korea Passport',
      country: 'South Korea',
      width: 35,
      height: 45,
      emoji: '🇰🇷',
    ),
    PassportSize(
      id: 'pk_passport',
      label: 'Pakistan Passport',
      country: 'Pakistan',
      width: 35,
      height: 45,
      emoji: '🇵🇰',
    ),
    PassportSize(
      id: 'bd_passport',
      label: 'Bangladesh Passport',
      country: 'Bangladesh',
      width: 45,
      height: 55,
      emoji: '🇧🇩',
    ),
    PassportSize(
      id: 'au_passport',
      label: 'Australia Passport',
      country: 'Australia',
      width: 35,
      height: 45,
      emoji: '🇦🇺',
    ),

    // ── Middle East ───────────────────────────────────────────────────────
    PassportSize(
      id: 'uae_passport',
      label: 'UAE / Saudi Passport',
      country: 'UAE / Saudi Arabia',
      width: 40,
      height: 60,
      emoji: '🇦🇪',
    ),

    // ── Africa ────────────────────────────────────────────────────────────
    PassportSize(
      id: 'ng_passport',
      label: 'Nigeria Passport',
      country: 'Nigeria',
      width: 35,
      height: 40,
      emoji: '🇳🇬',
    ),
    PassportSize(
      id: 'ke_passport',
      label: 'Kenya Passport',
      country: 'Kenya',
      width: 35,
      height: 45,
      emoji: '🇰🇪',
    ),
    PassportSize(
      id: 'za_passport',
      label: 'South Africa Passport',
      country: 'South Africa',
      width: 35,
      height: 45,
      emoji: '🇿🇦',
    ),

    // ── Prints & Special ──────────────────────────────────────────────────
    PassportSize(
      id: 'postcard_4r',
      label: 'Postcard 4R',
      country: 'Print',
      width: 102,
      height: 152,
      emoji: '🖼',
    ),
    PassportSize(
      id: 'postcard_5r',
      label: 'Postcard 5R',
      country: 'Print',
      width: 127,
      height: 178,
      emoji: '🖼',
    ),
    PassportSize(
      id: 'postcard_a6',
      label: 'Postcard A6',
      country: 'Print',
      width: 105,
      height: 148,
      emoji: '🖼',
    ),
    PassportSize(
      id: 'wallet_id',
      label: 'Wallet / ID Card',
      country: 'Standard',
      width: 54,
      height: 86,
      emoji: '💳',
    ),
    PassportSize(
      id: 'instagram_sq',
      label: 'Square (Instagram)',
      country: 'Social Media',
      width: 1080,
      height: 1080,
      unit: SizeUnit.px,
      emoji: '📱',
    ),
    PassportSize(
      id: 'custom',
      label: 'Custom…',
      country: 'Custom',
      width: 35,
      height: 45,
      emoji: '✏️',
    ),
  ];

  static PassportSize get defaultSize =>
      all.firstWhere((s) => s.id == 'in_passport');

  static PassportSize? findById(String id) {
    try {
      return all.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  static const List<PassportSize> homepageSizes = [
    // Standard Biometric Documents
    PassportSize(
      id: 'in_passport',
      label: 'Passport Photo',
      country: 'India',
      width: 35,
      height: 45,
      emoji: '🇮🇳',
      category: 'Standard Biometric Documents',
      description: 'Standard passport photo',
    ),
    PassportSize(
      id: 'in_visa',
      label: 'Visa Photo',
      country: 'India',
      width: 51,
      height: 51,
      emoji: '🇮🇳',
      category: 'Standard Biometric Documents',
      description: 'Standard visa photo',
    ),
    PassportSize(
      id: 'national_id_std',
      label: 'National ID Card',
      country: 'India',
      width: 35,
      height: 45,
      emoji: '🇮🇳',
      category: 'Standard Biometric Documents',
      description: 'Standard identity card photo',
    ),
    PassportSize(
      id: 'driving_license_in_35',
      label: 'Driving License',
      country: 'India',
      width: 35,
      height: 35,
      emoji: '🇮🇳',
      category: 'Standard Biometric Documents',
      description: 'Standard driving license photo',
    ),

    // Specialized or Larger Formats
    PassportSize(
      id: 'pan_card',
      label: 'PAN Card',
      country: 'India',
      width: 25,
      height: 35,
      emoji: '🇮🇳',
      category: 'Specialized or Larger Formats',
      description: 'PAN card photo',
    ),
    PassportSize(
      id: 'postcard_size',
      label: 'Postcard Size',
      country: 'India',
      width: 101.6,
      height: 152.4,
      emoji: '🖼',
      category: 'Specialized or Larger Formats',
      description: 'Postcard size photo',
    ),
    PassportSize(
      id: 'police_mugshot_4x6',
      label: 'Police Mugshot',
      country: 'Standard',
      width: 101.6,
      height: 152.4,
      emoji: '👮',
      category: 'Specialized or Larger Formats',
      description: 'Standard police photo',
    ),

    // Institutional Identification
    PassportSize(
      id: 'student_id_physical',
      label: 'Student ID',
      country: 'India',
      width: 25,
      height: 35,
      emoji: '🇮🇳',
      category: 'Institutional Identification',
      description: 'Student ID card photo',
    ),
  ];

  static Map<String, List<PassportSize>> get homepageGrouped {
    final Map<String, List<PassportSize>> map = {};
    for (final s in homepageSizes) {
      final cat = s.category ?? 'Other';
      map.putIfAbsent(cat, () => []).add(s);
    }
    return map;
  }

  /// Grouped for dropdown display
  static Map<String, List<PassportSize>> get grouped => {
        'Americas': all.where((s) => ['us_passport', 'ca_passport', 'br_passport', 'mx_passport', 'ar_passport'].contains(s.id)).toList(),
        'Europe': all.where((s) => ['uk_passport', 'eu_schengen', 'de_passport', 'fr_passport', 'ru_passport'].contains(s.id)).toList(),
        'Asia & Pacific': all.where((s) => ['in_passport', 'in_visa', 'cn_passport', 'jp_passport', 'kr_passport', 'pk_passport', 'bd_passport', 'au_passport'].contains(s.id)).toList(),
        'Middle East & Africa': all.where((s) => ['uae_passport', 'ng_passport', 'ke_passport', 'za_passport'].contains(s.id)).toList(),
        'Prints & Special': all.where((s) => ['postcard_4r', 'postcard_5r', 'postcard_a6', 'wallet_id', 'instagram_sq', 'custom'].contains(s.id)).toList(),
      };
}