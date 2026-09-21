
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/image_utils.dart';
import '../services/bg_remover_service.dart';

class BgRemovalResult {
  final ui.Image? image;
  final Uint8List? bytes;
  final Rect? foregroundBounds;
  final String? error;

  BgRemovalResult({this.image, this.bytes, this.foregroundBounds, this.error});
}

class BgRemoveDialog extends StatefulWidget {
  final Uint8List imageBytes;
  const BgRemoveDialog({super.key, required this.imageBytes});

  @override
  State<BgRemoveDialog> createState() => _BgRemoveDialogState();
}

class _BgRemoveDialogState extends State<BgRemoveDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  final List<String> _steps = [
    'Analyzing image…',
    'Detecting subject…',
    'Removing background…',
    'Refining edges…',
    'Finalizing…',
  ];
  int _stepIndex = 0;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _cycleSteps();
    _runBgRemoval();
  }

  Future<void> _runBgRemoval() async {
    try {
      final uiImage =
          await BgRemoverService.instance.removeBg(widget.imageBytes);
      final bytes = await ImageUtils.uiImageToBytes(uiImage);
      Rect? bounds;
      if (bytes != null) {
        bounds = await ImageUtils.getForegroundBounds(bytes);
      }
      if (mounted) {
        Navigator.of(context).pop(BgRemovalResult(
          image: uiImage,
          bytes: bytes,
          foregroundBounds: bounds,
        ));
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(BgRemovalResult(error: e.toString()));
      }
    }
  }

  void _cycleSteps() async {
    for (int i = 0; i < _steps.length; i++) {
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) setState(() => _stepIndex = i);
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // AI Icon with pulse
              ScaleTransition(
                scale: _pulse,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withOpacity(0.4),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.auto_fix_high_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Removing Background',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Powered by on-device AI',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: AppTheme.muted,
                ),
              ),
              const SizedBox(height: 24),
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (_stepIndex + 1) / _steps.length,
                  minHeight: 5,
                  backgroundColor: AppTheme.border,
                  valueColor: const AlwaysStoppedAnimation(AppTheme.primary),
                ),
              ),
              const SizedBox(height: 14),
              // Step label
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  _steps[_stepIndex],
                  key: ValueKey(_stepIndex),
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Please wait — this runs on-device',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  color: AppTheme.muted.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
