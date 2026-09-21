import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/image_utils.dart';
import '../models/passport_size.dart';
import 'editor_screen.dart';

// Top-level isolate helpers — compute() requires top-level or static functions
Uint8List? _rotateIsolate(_RotateParams p) => ImageUtils.rotateBytes(p.bytes, p.angle);
Uint8List? _flipHIsolate(Uint8List bytes) => ImageUtils.flipHorizontal(bytes);
Uint8List? _flipVIsolate(Uint8List bytes) => ImageUtils.flipVertical(bytes);

class _RotateParams {
  final Uint8List bytes;
  final int angle;
  const _RotateParams(this.bytes, this.angle);
}

class CropRotateScreen extends StatefulWidget {
  final Uint8List imageBytes;
  final PassportSize targetSize;
  const CropRotateScreen({
    super.key,
    required this.imageBytes,
    required this.targetSize,
  });

  @override
  State<CropRotateScreen> createState() => _CropRotateScreenState();
}

class _CropRotateScreenState extends State<CropRotateScreen> {
  Uint8List? _currentBytes;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _currentBytes = widget.imageBytes;
  }

  Future<void> _runImageOp(Future<Uint8List?> Function() op) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final result = await op();
      if (mounted && result != null) {
        setState(() => _currentBytes = result);
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _rotateLeft() => _runImageOp(
        () => compute(_rotateIsolate, _RotateParams(_currentBytes!, 270)),
      );

  Future<void> _rotateRight() => _runImageOp(
        () => compute(_rotateIsolate, _RotateParams(_currentBytes!, 90)),
      );

  Future<void> _flipH() => _runImageOp(
        () => compute(_flipHIsolate, _currentBytes!),
      );

  Future<void> _flipV() => _runImageOp(
        () => compute(_flipVIsolate, _currentBytes!),
      );

  void _next() {
    if (_currentBytes == null) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => EditorScreen(
          imageBytes: _currentBytes!,
          targetSize: widget.targetSize,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            Expanded(child: _buildCropArea()),
            _buildToolbar(),
            _buildNextButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded),
            color: Colors.white,
          ),
          const Expanded(
            child: Text(
              'Rotate & Flip',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (_isProcessing)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.primary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCropArea() {
    if (_currentBytes == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Image.memory(
          _currentBytes!,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      color: const Color(0xFF111111),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ToolbarButton(
            icon: Icons.rotate_left_rounded,
            label: 'Rotate Left',
            onTap: _isProcessing ? null : _rotateLeft,
          ),
          _ToolbarButton(
            icon: Icons.rotate_right_rounded,
            label: 'Rotate Right',
            onTap: _isProcessing ? null : _rotateRight,
          ),
          _ToolbarButton(
            icon: Icons.flip_rounded,
            label: 'Flip H',
            onTap: _isProcessing ? null : _flipH,
          ),
          _ToolbarButton(
            icon: Icons.flip_rounded,
            label: 'Flip V',
            onTap: _isProcessing ? null : _flipV,
            rotated: true,
          ),
        ],
      ),
    );
  }

  Widget _buildNextButton() {
    return Container(
      color: const Color(0xFF111111),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _isProcessing ? null : _next,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.accent,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: const Icon(Icons.arrow_forward_rounded),
          label: const Text(
            'Next →',
            style: TextStyle(
              fontSize: 16,
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool rotated;

  const _ToolbarButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.rotated = false,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.4 : 1.0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RotatedBox(
                quarterTurns: rotated ? 1 : 0,
                child: Icon(icon, color: Colors.white, size: 26),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}