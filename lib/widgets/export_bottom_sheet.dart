import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/export_service.dart';
import '../services/responsive_helper.dart';

class ExportBottomSheet extends StatefulWidget {
  final Uint8List previewBytes;
  final bool hasClothes;
  final double aspectRatio;
  final void Function({
    required bool enhance,
    required int scale,
    required ExportFormat format,
    required bool removeWatermark,
  }) onExport;

  const ExportBottomSheet({
    super.key,
    required this.previewBytes,
    required this.hasClothes,
    required this.aspectRatio,
    required this.onExport,
  });

  @override
  State<ExportBottomSheet> createState() => _ExportBottomSheetState();
}

class _ExportBottomSheetState extends State<ExportBottomSheet> {
  bool _enhance = true;
  int _scale = 2;
  ExportFormat _format = ExportFormat.png;
  bool _removeWatermark = true;

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark;
    final isWatch = context.isWatch;
    final isTv = context.isTV;

    final sheetWidth = isWatch
        ? 260.0
        : context.isMobile
            ? double.infinity
            : isTv
                ? 560.0
                : 480.0;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: sheetWidth),
        child: SafeArea(
          top: true,
          bottom: false,
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(isWatch ? 16 : 24),
              ),
            ),
            padding: EdgeInsets.fromLTRB(
              isWatch ? 12 : 20,
              isWatch ? 10 : 16,
              isWatch ? 12 : 20,
              MediaQuery.of(context).viewInsets.bottom +
                  MediaQuery.of(context).padding.bottom +
                  (isWatch ? 12 : 24),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: EdgeInsets.only(bottom: isWatch ? 10 : 16),
                      decoration: BoxDecoration(
                        color: AppTheme.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Header with badge
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Export Image',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: isWatch ? 15 : 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          if (!isWatch)
                            Text(
                              'High resolution & print ready',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 11,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.success.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.success.withOpacity(0.3),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.check_circle_outline_rounded,
                              color: AppTheme.success,
                              size: 13,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Free & Open Source',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.success,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: isWatch ? 10 : 16),

                  // Image Preview Section
                  Center(
                    child: Container(
                      height: isWatch ? 100 : 150,
                      decoration: BoxDecoration(
                        color: AppTheme.card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.border, width: 0.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: AspectRatio(
                        aspectRatio: widget.aspectRatio,
                        child: Image.memory(
                          widget.previewBytes,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: isWatch ? 10 : 16),

                  // AI Enhancement options
                  _OptionCard(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _enhance
                                ? AppTheme.primary.withOpacity(0.15)
                                : AppTheme.card,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.auto_awesome_rounded,
                            color: _enhance ? AppTheme.primary : AppTheme.muted,
                            size: isWatch ? 16 : 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'AI Detail Enhancement',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: isWatch ? 12 : 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              Text(
                                'Super resolution upscaling (Free)',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: isWatch ? 9.5 : 11,
                                  color: AppTheme.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch.adaptive(
                          value: _enhance,
                          onChanged: (v) => setState(() => _enhance = v),
                          activeColor: AppTheme.primary,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Upscale Factor selection
                  if (_enhance) ...[
                    _OptionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Upscale Factor',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: isWatch ? 11 : 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _ScaleChip(
                                label: '2×',
                                selected: _scale == 2,
                                onTap: () => setState(() => _scale = 2),
                              ),
                              const SizedBox(width: 8),
                              _ScaleChip(
                                label: '4× Ultra HD',
                                selected: _scale == 4,
                                onTap: () => setState(() => _scale = 4),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Watermark removal option
                  _OptionCard(
                    child: Row(
                      children: [
                        Checkbox(
                          value: _removeWatermark,
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _removeWatermark = v);
                            }
                          },
                          activeColor: AppTheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Clean Export (No Watermark)',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: isWatch ? 11.5 : 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              Text(
                                'Official, pristine ID photo without branding',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: isWatch ? 9 : 10,
                                  color: AppTheme.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Format selector
                  _OptionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'File Format',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: isWatch ? 11 : 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _FormatChip(
                                label: 'PNG',
                                subtitle: 'Lossless quality',
                                icon: Icons.layers_rounded,
                                selected: _format == ExportFormat.png,
                                onTap: () => setState(() => _format = ExportFormat.png),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _FormatChip(
                                label: 'JPEG',
                                subtitle: 'Compact standard',
                                icon: Icons.image_rounded,
                                selected: _format == ExportFormat.jpeg,
                                onTap: () => setState(() => _format = ExportFormat.jpeg),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: isWatch ? 14 : 20),

                  // CTA Button
                  SizedBox(
                    width: double.infinity,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withOpacity(0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: () {
                          widget.onExport(
                            enhance: _enhance,
                            scale: _scale,
                            format: _format,
                            removeWatermark: _removeWatermark,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: EdgeInsets.symmetric(
                            vertical: isWatch ? 10 : 15,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.download_rounded, size: 20),
                        label: Text(
                          'Export Photo',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: isWatch ? 13 : 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final Widget child;
  const _OptionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: child,
    );
  }
}

class _ScaleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ScaleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primary.withOpacity(0.12)
                : AppTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppTheme.primary : AppTheme.border,
              width: selected ? 1.5 : 0.5,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              color: selected ? AppTheme.primary : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _FormatChip extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _FormatChip({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withOpacity(0.12)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.border,
            width: selected ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? AppTheme.primary : AppTheme.muted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                      color: selected ? AppTheme.primary : AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 9,
                      color: AppTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
