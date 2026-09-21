import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../theme/app_theme.dart';

class CameraScreen extends StatefulWidget {
  final CameraDescription camera;
  const CameraScreen({super.key, required this.camera});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  bool _initialized = false;
  bool _capturing = false;
  bool _frontCamera = true;
  List<CameraDescription>? _allCameras;

  @override
  void initState() {
    super.initState();
    _initCamera(widget.camera);
    availableCameras().then((cams) => _allCameras = cams);
  }

  Future<void> _initCamera(CameraDescription cam) async {
    _controller = CameraController(
      cam,
      ResolutionPreset.high,
      enableAudio: false,
    );
    try {
      await _controller.initialize();
      if (mounted) setState(() => _initialized = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Camera error: $e')));
      }
    }
  }

  Future<void> _flipCamera() async {
    if (_allCameras == null) return;
    _frontCamera = !_frontCamera;
    final dir = _frontCamera
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    final cam = _allCameras!.firstWhere(
      (c) => c.lensDirection == dir,
      orElse: () => _allCameras!.first,
    );
    await _controller.dispose();
    setState(() => _initialized = false);
    await _initCamera(cam);
  }

  Future<void> _capture() async {
    if (_capturing) return;
    setState(() => _capturing = true);
    try {
      final file = await _controller.takePicture();
      final bytes = await file.readAsBytes();
      if (mounted) Navigator.pop(context, bytes);
    } catch (e) {
      setState(() => _capturing = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Capture error: $e')));
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (_initialized)
              Positioned.fill(
                child: CameraPreview(_controller),
              )
            else
              const Center(
                child: CircularProgressIndicator(color: AppTheme.primary),
              ),
            // Guide oval
            if (_initialized)
              Center(
                child: Container(
                  width: 220,
                  height: 280,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: AppTheme.primary.withOpacity(0.7),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(110),
                  ),
                ),
              ),
            // Guide text
            Positioned(
              bottom: 140,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Align face within the guide',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              ),
            ),
            // Controls
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Back
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded, size: 28),
                    color: Colors.white,
                  ),
                  // Capture
                  GestureDetector(
                    onTap: _capture,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        color: _capturing
                            ? AppTheme.primary
                            : Colors.white.withOpacity(0.15),
                      ),
                      child: _capturing
                          ? const CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            )
                          : const Icon(
                              Icons.camera_rounded,
                              size: 32,
                              color: Colors.white,
                            ),
                    ),
                  ),
                  // Flip
                  IconButton(
                    onPressed: _flipCamera,
                    icon: const Icon(Icons.flip_camera_ios_rounded, size: 28),
                    color: Colors.white,
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
