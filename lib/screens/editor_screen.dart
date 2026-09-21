import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../theme/app_theme.dart';
import '../models/passport_size.dart';
import '../models/bg_option.dart';
import '../models/editor_layer.dart';
import '../models/recent_project.dart';
import '../services/recent_projects_service.dart';
import 'share_screen.dart';
import '../services/export_service.dart';
import '../widgets/canvas_widget.dart';
import '../widgets/bg_panel.dart';
import '../widgets/size_dropdown.dart';
import '../widgets/export_bottom_sheet.dart';
import '../widgets/bg_remove_dialog.dart';
import '../services/bg_remover_service.dart';
import '../utils/image_utils.dart';
import '../services/gallery_service.dart';
import '../utils/manifest_utils.dart';
import '../widgets/gradient_slider_track.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../services/super_resolution_service.dart';

class _FinalExportParams {
  final Uint8List bytes;
  final ExportFormat format;
  _FinalExportParams({
    required this.bytes,
    required this.format,
  });
}

Uint8List _processFinalExport(_FinalExportParams params) {
  final image = img.decodeImage(params.bytes);
  if (image == null) return params.bytes;

  if (params.format == ExportFormat.png) {
    return Uint8List.fromList(img.encodePng(image, level: 3));
  } else {
    return Uint8List.fromList(img.encodeJpg(image, quality: 95));
  }
}

enum _EditorTab {
  size,
  background,
  smooth,
  brush,
  transform,
  light,
  clothes,
  layers,
}

class EditorScreen extends StatefulWidget {
  final Uint8List? imageBytes;
  final RecentProject? loadedProject;
  final PassportSize? targetSize;

  const EditorScreen({
    super.key,
    this.imageBytes,
    this.loadedProject,
    this.targetSize,
  });

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  bool _isSavingAndExiting = false;
  // Canvas state
  final _repaintKey = GlobalKey();
  ui.Image? _bgRemovedImage;
  Uint8List? _bgRemovedBytes;
  PassportSize _selectedSize = PassportSizes.defaultSize;
  BgOption _bgOption = BgOption.solid(Colors.white);

  // Brush state
  BrushMode _brushMode = BrushMode.erase;
  double _brushRadius = 25.0;
  double _brushOffset = 40.0;
  ui.Image? _originalImage;

  // History system for undo/redo
  final List<EditorHistoryState> _undoStack = [];
  final List<EditorHistoryState> _redoStack = [];

  // Toggle checkerboard background mode
  bool _useLightCheckerboard = false;
  bool _showWatermark = false;
  String _appName = 'Passport Maker';

  void _saveToHistory() {
    _undoStack.add(
      EditorHistoryState(
        selectedSize: _selectedSize,
        bgOption: _bgOption,
        layers: List.from(_layers),
        selectedLayerId: _selectedLayerId,
        userHasManuallyResized: _userHasManuallyResized,
        bgRemovedBytes: _bgRemovedBytes,
        bgRemovedImage: _bgRemovedImage,
        bgThreshold: _bgThreshold,
        foregroundBounds: _foregroundBounds,
      ),
    );
    _redoStack.clear();
    if (_undoStack.length > 50) {
      _undoStack.removeAt(0);
    }
    _triggerAutoSave();
  }

  bool get _canUndo => _undoStack.isNotEmpty;
  bool get _canRedo => _redoStack.isNotEmpty;

  void _undo() {
    if (!_canUndo) return;
    setState(() {
      _redoStack.add(
        EditorHistoryState(
          selectedSize: _selectedSize,
          bgOption: _bgOption,
          layers: List.from(_layers),
          selectedLayerId: _selectedLayerId,
          userHasManuallyResized: _userHasManuallyResized,
          bgRemovedBytes: _bgRemovedBytes,
          bgRemovedImage: _bgRemovedImage,
          bgThreshold: _bgThreshold,
          foregroundBounds: _foregroundBounds,
        ),
      );
      final previous = _undoStack.removeLast();
      _selectedSize = previous.selectedSize;
      _bgOption = previous.bgOption;
      _layers = previous.layers;
      _selectedLayerId = previous.selectedLayerId;
      _userHasManuallyResized = previous.userHasManuallyResized;
      _bgRemovedBytes = previous.bgRemovedBytes;
      _bgRemovedImage = previous.bgRemovedImage;
      _bgThreshold = previous.bgThreshold;
      _foregroundBounds = previous.foregroundBounds;
    });
    _triggerAutoSave();
  }

  void _redo() {
    if (!_canRedo) return;
    setState(() {
      _undoStack.add(
        EditorHistoryState(
          selectedSize: _selectedSize,
          bgOption: _bgOption,
          layers: List.from(_layers),
          selectedLayerId: _selectedLayerId,
          userHasManuallyResized: _userHasManuallyResized,
          bgRemovedBytes: _bgRemovedBytes,
          bgRemovedImage: _bgRemovedImage,
          bgThreshold: _bgThreshold,
          foregroundBounds: _foregroundBounds,
        ),
      );
      final next = _redoStack.removeLast();
      _selectedSize = next.selectedSize;
      _bgOption = next.bgOption;
      _layers = next.layers;
      _selectedLayerId = next.selectedLayerId;
      _userHasManuallyResized = next.userHasManuallyResized;
      _bgRemovedBytes = next.bgRemovedBytes;
      _bgRemovedImage = next.bgRemovedImage;
      _bgThreshold = next.bgThreshold;
      _foregroundBounds = next.foregroundBounds;
    });
    _triggerAutoSave();
  }

  // Layer system state
  List<EditorLayer> _layers = [];
  String? _selectedLayerId;

  // Background removal threshold state
  double _bgThreshold = 6.5;
  bool _isProcessingBg = false;
  Timer? _debounceTimer;

  // Auto-fit state
  Rect? _foregroundBounds;
  Size? _lastCanvasSize;
  String? _lastSelectedSizeId;
  bool _pendingAutoFit = false;

  // UI state
  _EditorTab? _activeTab;
  String _clothCategory = 'man';
  bool _userHasManuallyResized = false;
  bool _bgRemovalDone = false;
  bool _isExporting = false;
  bool _showLayerSettingsTab = false;
  String _selectedLightTarget = 'photo'; // 'photo' or 'background'

  void _onTabChanged() {
    if (_activeTab == _EditorTab.background) {
      if (_bgOption.isImage) {
        _selectedLayerId = 'background';
      } else {
        _selectedLayerId = null;
      }
    } else if (_activeTab == _EditorTab.transform) {
      _selectedLayerId = 'photo';
    } else if (_activeTab == _EditorTab.clothes) {
      final clothIndex = _layers.indexWhere((l) => l.type == LayerType.clothing);
      if (clothIndex != -1) {
        _selectedLayerId = _layers[clothIndex].id;
      }
    } else if (_activeTab == null) {
      _selectedLayerId = null;
    }
  }

  late TabController _tabController;

  late String _projectId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Prevent screen capture on Editor Screen
    GalleryService.instance.setSecure(true);
    _loadAppName();

    _projectId =
        widget.loadedProject?.id ??
        DateTime.now().millisecondsSinceEpoch.toString();
    _tabController = TabController(length: 8, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _activeTab = _EditorTab.values[_tabController.index];
          _onTabChanged();
        });
      }
    });

    if (widget.loadedProject != null) {
      final project = widget.loadedProject!;
      _bgRemovedBytes = project.bgRemovedBytes;
      _selectedSize = project.selectedSize;
      _bgOption = project.bgOption;
      _layers = List.from(project.layers);
      _bgRemovalDone = true;
      _userHasManuallyResized = true;
      _selectedLayerId = _layers.isNotEmpty ? _layers.first.id : null;
    } else {
      if (widget.targetSize != null) {
        _selectedSize = widget.targetSize!;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startBgRemovalFlow();
      });
    }
    _decodeImages();
  }

  Future<void> _checkShowInstructions() async {
    final prefs = await SharedPreferences.getInstance();
    final showInstructions = prefs.getBool('show_editor_instructions') ?? true;
    if (showInstructions) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showInstructionsDialog(autoShow: true);
        }
      });
    }
  }

  void _showInstructionsDialog({required bool autoShow}) {
    bool dontShowAgain = false;
    showDialog(
      context: context,
      barrierDismissible: !autoShow,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: AppTheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: AppTheme.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Editor Guide',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Learn how to use the editor to customize your biometric photo.',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildGuideItem(
                        icon: Icons.zoom_out_map_rounded,
                        title: 'Move & Scale Canvas',
                        description:
                            'Drag with 1 finger to move. Pinch with 2 fingers to zoom or rotate the photo layers.',
                      ),
                      _buildGuideItem(
                        icon: Icons.aspect_ratio_rounded,
                        title: 'Perfect Dimensions',
                        description:
                            'Select standard country passport, visa or custom sizes in the "Size" tab.',
                      ),
                      _buildGuideItem(
                        icon: Icons.brush_rounded,
                        title: 'Erase / Restore edges',
                        description:
                            'Fine-tune background removal manually. Zoom in and pan automatically in the "Brush" tab.',
                      ),
                      _buildGuideItem(
                        icon: Icons.checkroom_rounded,
                        title: 'Professional Clothes Swap',
                        description:
                            'Swap your current outfit with clean suits or templates automatically.',
                      ),
                      _buildGuideItem(
                        icon: Icons.tune_rounded,
                        title: 'Adjustments & Lighting',
                        description:
                            'Refine image brightness, exposure, contrast, temperature and details.',
                      ),
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 8),
                      Theme(
                        data: ThemeData(unselectedWidgetColor: AppTheme.muted),
                        child: CheckboxListTile(
                          value: dontShowAgain,
                          onChanged: (val) {
                            setState(() {
                              dontShowAgain = val ?? false;
                            });
                          },
                          title: Text(
                            "Don't show this guide again",
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          activeColor: AppTheme.primary,
                          dense: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (dontShowAgain) {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('show_editor_instructions', false);
                      }
                      if (context.mounted) {
                        Navigator.pop(ctx);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Got it!'),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildGuideItem({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.cardElevated,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _decodeImages() async {
    final origBytes =
        widget.imageBytes ?? widget.loadedProject?.originalImageBytes;
    if (origBytes != null) {
      final codec = await ui.instantiateImageCodec(origBytes);
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() {
          _originalImage = frame.image;
        });
      }
    }

    if (_bgRemovedBytes != null && _bgRemovedImage == null) {
      final codec = await ui.instantiateImageCodec(_bgRemovedBytes!);
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() {
          _bgRemovedImage = frame.image;
        });
      }
    }
  }

  Future<void> _loadAppName() async {
    final name = await ManifestUtils.getAppName();
    if (mounted) {
      setState(() {
        _appName = name;
      });
    }
  }

  Timer? _autoSaveTimer;
  void _triggerAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 1), () {
      _autoSaveProject();
    });
  }

  Future<void> _autoSaveProject() async {
    if (!_bgRemovalDone || _bgRemovedBytes == null) return;
    final originalBytes =
        widget.imageBytes ?? widget.loadedProject?.originalImageBytes;
    if (originalBytes == null) return;

    // Capture thumbnail from repaint boundary
    Uint8List? thumbnailBytes;
    final boundary =
        _repaintKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;

    if (boundary != null) {
      try {
        thumbnailBytes = await ExportService.instance.captureWidget(
          boundary: boundary,
          pixelRatio: 0.5,
        );
      } catch (e) {
        debugPrint('Error capturing thumbnail: $e');
      }
    }

    final project = RecentProject(
      id: _projectId,
      selectedSize: _selectedSize,
      bgOption: _bgOption,
      layers: _layers,
      originalImageBytes: originalBytes,
      bgRemovedBytes: _bgRemovedBytes!,
      thumbnailBytes: thumbnailBytes,
      lastSaved: DateTime.now(),
    );
    await RecentProjectsService.instance.saveProject(project);
  }

  Future<void> _startBgRemovalFlow() async {
    if (widget.imageBytes == null) return;
    final result = await showDialog<BgRemovalResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BgRemoveDialog(imageBytes: widget.imageBytes!),
    );

    if (result != null && mounted) {
      if (result.error != null) {
        setState(() {
          _bgRemovedBytes = widget.imageBytes;
          _foregroundBounds = null;
          _bgRemovalDone = true;
          _pendingAutoFit = true;

          // Set up initial photo layer
          _layers = [
            const EditorLayer(
              id: 'photo',
              type: LayerType.photo,
              name: 'Photo',
              scale: 1.0,
              rotation: 0.0,
              offset: Offset.zero,
            ),
          ];
          _selectedLayerId = 'photo';
        });
        _triggerAutoSave();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('BG removal failed, using original: ${result.error}'),
            backgroundColor: AppTheme.error,
          ),
        );
      } else {
        setState(() {
          _bgRemovedImage = result.image;
          _bgRemovedBytes = result.bytes;
          _foregroundBounds = result.foregroundBounds;
          _bgRemovalDone = true;
          _pendingAutoFit = true;

          // Set up initial photo layer
          _layers = [
            const EditorLayer(
              id: 'photo',
              type: LayerType.photo,
              name: 'Photo',
              scale: 1.0,
              rotation: 0.0,
              offset: Offset.zero,
            ),
          ];
          _selectedLayerId = 'photo';
        });
        _triggerAutoSave();
        _checkShowInstructions();
      }
    }
  }

  void _onThresholdChanged(double value) {
    setState(() {
      _bgThreshold = value;
    });
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      _updateBgCutout(value / 10.0);
    });
  }

  BuildContext? _refiningDialogContext;

  Future<void> _updateBgCutout(double threshold) async {
    final origBytes =
        widget.imageBytes ?? widget.loadedProject?.originalImageBytes;
    if (origBytes == null) return;

    setState(() {
      _isProcessingBg = true;
    });

    // Show non-dismissible dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        _refiningDialogContext = ctx;
        return PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: AppTheme.card,
            content: Row(
              children: [
                CircularProgressIndicator(color: AppTheme.primary),
                const SizedBox(width: 20),
                Text(
                  'Refining edges...',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    try {
      final uiImage = await BgRemoverService.instance.removeBg(
        origBytes,
        threshold: threshold,
      );
      final bytes = await ImageUtils.uiImageToBytes(uiImage);
      Rect? bounds;
      if (bytes != null) {
        bounds = await ImageUtils.getForegroundBounds(bytes);
      }

      if (mounted) {
        setState(() {
          _bgRemovedImage = uiImage;
          _bgRemovedBytes = bytes;
          _foregroundBounds = bounds;
          _isProcessingBg = false;
        });
        _triggerAutoSave();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessingBg = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('BG removal failed: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (_refiningDialogContext != null && mounted) {
        Navigator.of(_refiningDialogContext!).pop();
        _refiningDialogContext = null;
      }
    }
  }

  void _autoFitImage(Size canvasSize) {
    if (_userHasManuallyResized) return;
    if (_bgRemovedBytes == null || _layers.isEmpty) return;

    final imgWidth = _bgRemovedImage?.width.toDouble() ?? 0.0;
    final imgHeight = _bgRemovedImage?.height.toDouble() ?? 0.0;
    if (imgWidth == 0 || imgHeight == 0) return;

    final bounds =
        _foregroundBounds ?? Rect.fromLTWH(0, 0, imgWidth, imgHeight);

    final w_p = bounds.width;
    final h_p = bounds.height;
    if (w_p == 0 || h_p == 0) return;

    // Standard passport fit: person height should occupy 70% of canvas height
    double scale = (canvasSize.height * 0.70) / h_p;

    // Ensure the width doesn't exceed 80% of canvas width
    double maxWScale = (canvasSize.width * 0.80) / w_p;
    if (scale > maxWScale) {
      scale = maxWScale;
    }

    scale = scale.clamp(0.3, 3.0);

    // Center the person in the canvas.
    final imageCenter = Offset(imgWidth / 2, imgHeight / 2);
    final offset = (imageCenter - bounds.center) * scale;

    setState(() {
      _layers = _layers.map((l) {
        if (l.id == 'photo') {
          return l.copyWith(scale: scale, offset: offset, rotation: 0.0);
        }
        return l;
      }).toList();
    });
  }

  Future<void> _export({
    required bool enhance,
    required int scale,
    required ExportFormat format,
    required bool removeWatermark,
  }) async {
    if (_bgRemovedBytes == null) return;

    // Hide selection borders and checkerboard pattern
    setState(() {
      _showWatermark = !removeWatermark;
      _isExporting = true;
    });

    // Wait for the widgets to render without the editor's visual aids
    await WidgetsBinding.instance.endOfFrame;

    final boundary =
        _repaintKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) {
      setState(() {
        _isExporting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Export failed: canvas not ready')),
      );
      return;
    }

    // For AI enhance: capture at 1× — the ONNX model provides the quality
    // boost. For standard export: capture at scale× for resolution.
    // If it's totally for free, capture at 1× to decrease the resolution/level.
    final captureRatio = (enhance ? scale.toDouble() : 1.0);
    Uint8List? rawBytes = await ExportService.instance.captureWidget(
      boundary: boundary,
      pixelRatio: captureRatio,
    );

    if (rawBytes == null) {
      setState(() {
        _isExporting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Export failed: capture failed')),
      );
      return;
    }

    // Show loading dialog with dynamic text using ValueNotifiers
    final statusNotifier = ValueNotifier<String>('AI Detail Enhancing...');
    final subTextNotifier = ValueNotifier<String>(
      'Applying super-resolution upscaling',
    );
    final progressNotifier = ValueNotifier<double>(0.0);

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ExportingDialog(
        statusNotifier: statusNotifier,
        subTextNotifier: subTextNotifier,
        progressNotifier: progressNotifier,
      ),
    );

    try {
      if (enhance) {
        statusNotifier.value = 'Preparing Image...';
        subTextNotifier.value = 'Reducing quality before AI enhance...';

        // final lowQualityBytes = await compute(
        //   _decreaseQualityBeforeEnhance,
        //   _PreEnhanceParams(bytes: rawBytes),
        // );

        final upscaler = SuperResolutionService(tileSize: 128, overlap: 8);
        await upscaler.initializeModel('assets/models/realesrgan.onnx');

        final codec = await ui.instantiateImageCodec(
          rawBytes,
        ); // use rawBytes directly

        final fi = await codec.getNextFrame();
        ui.Image currentImage = fi.image;

        try {
          statusNotifier.value = 'AI Detail Enhancing...';
          subTextNotifier.value = 'Applying super-resolution upscaling';

          final img1 = await upscaler.upscaleImage(
            currentImage,
            scale,
            enhanceIntensity: 0.9,
            onProgress: (p, msg) {
              progressNotifier.value = p;
              subTextNotifier.value = msg;
            },
          );
          currentImage.dispose();
          currentImage = img1!;

          final pngData = await currentImage.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (pngData != null) {
            rawBytes = pngData.buffer.asUint8List();
          }
        } finally {
          currentImage.dispose();
          upscaler.dispose();
        }
      } else {
        statusNotifier.value = 'Saving to Gallery...';
        subTextNotifier.value = 'This may take a moment';
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // Guard: if rawBytes is somehow null at this point, bail out safely
      if (rawBytes == null) {
        if (mounted) {
          Navigator.pop(context); // dismiss loading dialog
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Export failed: image data lost')),
          );
        }
        return;
      }

      statusNotifier.value = 'Optimizing Image...';
      subTextNotifier.value = 'Encoding and processing final image...';

      final Uint8List safeRawBytes = rawBytes;
      final finalBytes = await compute(
        _processFinalExport,
        _FinalExportParams(
          bytes: safeRawBytes,
          format: format,
        ),
      );
      final ExportFormat finalFormat = format;

      final result = await ExportService.instance.saveToGallery(
        bytes: finalBytes,
        format: finalFormat,
      );

      if (!mounted) return;
      Navigator.pop(context); // dismiss loading dialog

      if (result.success) {
        // Save project state one last time to capture the latest state
        await _autoSaveProject();

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ShareScreen(
                imageBytes: finalBytes,
                fileName: result.filePath ?? 'passport_photo.png',
                size: _selectedSize,
              ),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: ${result.error}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        print(e);
        Navigator.pop(context); // dismiss loading dialog
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _showWatermark = false;
          _isExporting = false;
        });
      }
    }
  }

  void _showExportSheet() async {
    if (_bgRemovedBytes == null) return;

    // Capture original high resolution canvas preview (clean without visual aids)
    setState(() {
      _isExporting = true;
    });

    // Wait for the widgets to render without the editor's visual aids
    await WidgetsBinding.instance.endOfFrame;

    final boundary =
        _repaintKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) {
      setState(() {
        _isExporting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preview generation failed: canvas not ready'),
        ),
      );
      return;
    }

    final previewBytes = await ExportService.instance.captureWidget(
      boundary: boundary,
      pixelRatio: 1.0,
    );

    setState(() {
      _isExporting = false;
    });

    if (previewBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preview generation failed')),
      );
      return;
    }

    final bool hasClothes = _layers.any((l) => l.type == LayerType.clothing);
    final double aspectRatio = _selectedSize.width / _selectedSize.height;

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight:
            MediaQuery.of(context).size.height -
            MediaQuery.of(context).padding.top -
            16.0,
      ),
      backgroundColor: Colors.transparent,
      builder: (_) => ExportBottomSheet(
        previewBytes: previewBytes,
        hasClothes: hasClothes,
        aspectRatio: aspectRatio,
        onExport:
            ({
              required enhance,
              required scale,
              required format,
              required removeWatermark,
            }) {
              Navigator.pop(context);
              _export(
                enhance: enhance,
                scale: scale,
                format: format,
                removeWatermark: removeWatermark,
              );
            },
      ),
    );
  }

  @override
  void dispose() {
    // Restore screenshot/screen capture capabilities
    GalleryService.instance.setSecure(false);

    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    _bgRemovedImage?.dispose();
    _debounceTimer?.cancel();
    _autoSaveTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _autoSaveProject();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, themeMode, _) {
        final isThemeDark = AppTheme.isDark;
        final systemOverlayStyle = SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isThemeDark
              ? Brightness.light
              : Brightness.dark,
          statusBarBrightness: isThemeDark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: isThemeDark
              ? const Color(0xFF0A0F1E)
              : const Color(0xFFF8FAFC),
          systemNavigationBarIconBrightness: isThemeDark
              ? Brightness.light
              : Brightness.dark,
        );
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: systemOverlayStyle,
          child: PopScope(
            canPop: false,
            onPopInvoked: (didPop) async {
              if (didPop) return;
              if (_isSavingAndExiting) return; // prevent double-invoke
              _isSavingAndExiting = true;
              await _autoSaveProject();
              _isSavingAndExiting = false;
              if (mounted) {
                Navigator.of(context).pop();
              }
            },
            child: Scaffold(
              backgroundColor: AppTheme.background,
              body: SafeArea(
                child: Stack(
                  children: [
                    Column(
                      children: [
                        _buildAppBar(),
                        Expanded(child: _buildCanvasArea()),
                        _buildPanelArea(),
                        _buildTabBar(),
                      ],
                    ),
                    if (_activeTab == _EditorTab.brush)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 96,
                        child: _buildFloatingBrushPanel(),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              if (navigator.canPop()) {
                await navigator.maybePop();
              }
            },
            icon: const Icon(Icons.arrow_back_rounded),
            style: IconButton.styleFrom(backgroundColor: AppTheme.card),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Edit Photo',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          if (_bgRemovalDone) ...[
            // Undo button
            IconButton(
              onPressed: _canUndo ? _undo : null,
              icon: const Icon(Icons.undo_rounded),
              style: IconButton.styleFrom(
                backgroundColor: AppTheme.card,
                disabledBackgroundColor: AppTheme.card.withOpacity(0.3),
              ),
              color: _canUndo
                  ? AppTheme.textPrimary
                  : AppTheme.muted.withOpacity(0.5),
              iconSize: 20,
            ),
            const SizedBox(width: 8),
            // Redo button
            IconButton(
              onPressed: _canRedo ? _redo : null,
              icon: const Icon(Icons.redo_rounded),
              style: IconButton.styleFrom(
                backgroundColor: AppTheme.card,
                disabledBackgroundColor: AppTheme.card.withOpacity(0.3),
              ),
              color: _canRedo
                  ? AppTheme.textPrimary
                  : AppTheme.muted.withOpacity(0.5),
              iconSize: 20,
                ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () => _showInstructionsDialog(autoShow: false),
              icon: const Icon(Icons.help_outline_rounded),
              style: IconButton.styleFrom(backgroundColor: AppTheme.card),
              color: AppTheme.textPrimary,
              iconSize: 20,
            ),
            const SizedBox(width: 12),
          ],
          // Export FAB
          Container(
            decoration: BoxDecoration(
              gradient: AppTheme.accentGradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.accent.withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _bgRemovalDone ? _showExportSheet : null,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.download_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Export',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _bgRemovalDone ? Colors.white : Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _addBrushStroke(BrushStroke stroke) {
    _saveToHistory();
    setState(() {
      _layers = _layers.map((l) {
        if (l.id == 'photo') {
          return l.copyWith(
            brushStrokes: List<BrushStroke>.from(l.brushStrokes)..add(stroke),
          );
        }
        return l;
      }).toList();
    });
    _triggerAutoSave();
  }

  Widget _buildCanvasArea() {
    if (!_bgRemovalDone || _bgRemovedBytes == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        // Subtract 70 to leave room for label and footer instruction text
        final maxH = (constraints.maxHeight - 70).clamp(
          40.0,
          constraints.maxHeight,
        );
        final aspect = _selectedSize.aspectRatio;

        double w, h;
        if (maxW / maxH > aspect) {
          h = maxH;
          w = h * aspect;
        } else {
          w = maxW;
          h = w / aspect;
        }
        final canvasSize = Size(w.clamp(40, maxW), h.clamp(40, maxH));

        final sizeChanged = _selectedSize.id != _lastSelectedSizeId;
        final canvasResized =
            _lastCanvasSize != null && canvasSize != _lastCanvasSize;

        if (_pendingAutoFit || sizeChanged || canvasResized) {
          if (canvasResized && !sizeChanged && !_pendingAutoFit) {
            final scaleFactor = canvasSize.width / _lastCanvasSize!.width;
            if (scaleFactor != 1.0 &&
                !scaleFactor.isNaN &&
                !scaleFactor.isInfinite) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                setState(() {
                  _layers = _layers.map((l) {
                    return l.copyWith(
                      offset: l.offset * scaleFactor,
                      scale: l.scale * scaleFactor,
                    );
                  }).toList();
                });
              });
            }
          } else if (sizeChanged || _pendingAutoFit) {
            _userHasManuallyResized = false;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _autoFitImage(canvasSize);
            });
          }

          _lastCanvasSize = canvasSize;
          _lastSelectedSizeId = _selectedSize.id;
          _pendingAutoFit = false;
        }

        final double scale = 1.0;
        final Offset translation = Offset.zero;
        final duration = _isExporting
            ? Duration.zero
            : const Duration(milliseconds: 300);

        return AnimatedContainer(
          duration: duration,
          curve: Curves.easeInOut,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          transformAlignment: Alignment.center,
          transform: Matrix4.identity()
            ..translate(translation.dx, translation.dy)
            ..scale(scale),
          child: CanvasWidget(
            repaintKey: _repaintKey,
            imageBytes: _bgRemovedBytes,
            originalImage: _originalImage,
            bgRemovedImage: _bgRemovedImage,
            passportSize: _selectedSize,
            bgOption: _bgOption,
            layers: _layers,
            selectedLayerId: _selectedLayerId,
            isExporting: _isExporting,
            showWatermark: _showWatermark,
            watermarkText: "sddev.in/s/photo-id",
            useLightCheckerboard: _useLightCheckerboard,
            isBrushModeActive: _activeTab == _EditorTab.brush,
            brushMode: _brushMode,
            brushRadius: _brushRadius,
            brushOffset: _brushOffset,
            onAddBrushStroke: _addBrushStroke,
            onToggleCheckerboard: () {
              if (_bgOption.isSolid) {
                setState(() {
                  _saveToHistory();
                  if (_bgOption.solidColor == Colors.white) {
                    _bgOption = BgOption.solid(Colors.black);
                  } else {
                    _bgOption = BgOption.solid(Colors.white);
                  }
                });
              } else {
                setState(() {
                  _useLightCheckerboard = !_useLightCheckerboard;
                });
              }
            },
            onLayerTransformStart: () {
              _saveToHistory();
            },
            onLayerTransform: (id, offset, scale, rotation) {
              setState(() {
                if (id == 'photo') {
                  _userHasManuallyResized = true;
                }
                if (id == 'background') {
                  _bgOption = _bgOption.copyWith(
                    offset: offset,
                    scale: scale,
                    rotation: rotation,
                  );
                } else {
                  _layers = _layers.map((l) {
                    if (l.id == id) {
                      return l.copyWith(
                        offset: offset,
                        scale: scale,
                        rotation: rotation,
                      );
                    }
                    return l;
                  }).toList();
                }
              });
            },
            onSelectLayer: (id) {
              setState(() {
                _selectedLayerId = id.isEmpty ? null : id;
              });
            },
          ),
        );
      },
    );
  }

  Widget _buildTabBar() {
    final activeIndex = _activeTab == null ? -1 : _tabController.index;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildCustomTabItem(
                0,
                Icons.aspect_ratio_rounded,
                'Size',
                activeIndex == 0,
              ),
              _buildCustomTabItem(
                1,
                Icons.palette_outlined,
                'Background',
                activeIndex == 1,
              ),
              _buildCustomTabItem(
                2,
                Icons.blur_on_rounded,
                'Smooth',
                activeIndex == 2,
              ),
              _buildCustomTabItem(
                3,
                Icons.brush_rounded,
                'Brush',
                activeIndex == 3,
              ),
              _buildCustomTabItem(
                4,
                Icons.tune_rounded,
                'Transform',
                activeIndex == 4,
              ),
              _buildCustomTabItem(
                5,
                Icons.wb_sunny_rounded,
                'Light',
                activeIndex == 5,
              ),
              _buildCustomTabItem(
                6,
                Icons.checkroom_rounded,
                'Clothes',
                activeIndex == 6,
              ),
              _buildCustomTabItem(
                7,
                Icons.layers_rounded,
                'Layers',
                activeIndex == 7,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomTabItem(
    int index,
    IconData icon,
    String label,
    bool isActive,
  ) {
    return SizedBox(
      width: 72,
      child: GestureDetector(
        onTap: () {
          setState(() {
            if (_activeTab == _EditorTab.values[index]) {
              _activeTab = null;
            } else {
              _tabController.index = index;
              _activeTab = _EditorTab.values[index];
            }
            _onTabChanged();
          });
        },
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: isActive
                ? AppTheme.primary.withOpacity(0.12)
                : Colors.transparent,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: isActive ? 1.15 : 1.0,
                duration: const Duration(milliseconds: 150),
                child: Icon(
                  icon,
                  size: 20,
                  color: isActive ? AppTheme.primary : AppTheme.muted,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  color: isActive ? AppTheme.primary : AppTheme.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPanelArea() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: _buildActivePanel(),
    );
  }

  Widget _buildActivePanel() {
    if (_activeTab == null) return const SizedBox.shrink();
    switch (_activeTab!) {
      case _EditorTab.size:
        return _buildSizePanel();
      case _EditorTab.background:
        return _buildBgPanel();
      case _EditorTab.smooth:
        return _buildSmoothPanel();
      case _EditorTab.brush:
        return const SizedBox.shrink(); // Handled as floating overlay
      case _EditorTab.transform:
        return _buildTransformPanel();
      case _EditorTab.light:
        return _buildLightPanel();
      case _EditorTab.layers:
        return _buildLayersPanel();
      case _EditorTab.clothes:
        return _buildClothPanel();
    }
  }

  Widget _buildFloatingBrushPanel() {
    final photoIndex = _layers.indexWhere((l) => l.id == 'photo');
    if (photoIndex == -1) {
      return Card(
        key: const ValueKey('brush_floating'),
        color: AppTheme.surface.withOpacity(0.9),
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppTheme.border, width: 0.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Photo layer not found',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: AppTheme.textSecondary,
            ),
          ),
        ),
      );
    }

    return Card(
      key: const ValueKey('brush_floating'),
      color: AppTheme.surface.withOpacity(0.85),
      elevation: 8,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppTheme.border, width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Manual Remove / Restore',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    if (_layers[photoIndex].brushStrokes.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          _saveToHistory();
                          setState(() {
                            _layers[photoIndex] = _layers[photoIndex].copyWith(
                              brushStrokes: const [],
                            );
                          });
                          _triggerAutoSave();
                        },
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(40, 24),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Clear All',
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'Poppins',
                            color: AppTheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildBrushToolButton(
                      mode: BrushMode.erase,
                      icon: Icons.cleaning_services_rounded,
                      label: 'Erase',
                      isSelected: _brushMode == BrushMode.erase,
                    ),
                    const SizedBox(width: 16),
                    _buildBrushToolButton(
                      mode: BrushMode.restore,
                      icon: Icons.brush_rounded,
                      label: 'Restore',
                      isSelected: _brushMode == BrushMode.restore,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Brush Size',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    Text(
                      '${_brushRadius.toInt()} px',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                SizedBox(
                  height: 30,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      activeTrackColor: AppTheme.primary,
                      inactiveTrackColor: AppTheme.border,
                      thumbColor: AppTheme.primary,
                      overlayColor: AppTheme.primary.withOpacity(0.2),
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                    ),
                    child: Slider(
                      value: _brushRadius,
                      min: 5.0,
                      max: 80.0,
                      divisions: 75,
                      onChanged: (val) {
                        setState(() {
                          _brushRadius = val;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Touch Offset',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    Text(
                      '${_brushOffset.toInt()} px',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                SizedBox(
                  height: 30,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      activeTrackColor: AppTheme.primary,
                      inactiveTrackColor: AppTheme.border,
                      thumbColor: AppTheme.primary,
                      overlayColor: AppTheme.primary.withOpacity(0.2),
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                    ),
                    child: Slider(
                      value: _brushOffset,
                      min: 0.0,
                      max: 100.0,
                      divisions: 100,
                      onChanged: (val) {
                        setState(() {
                          _brushOffset = val;
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrushToolButton({
    required BrushMode mode,
    required IconData icon,
    required String label,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _brushMode = mode;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 80,
        height: 68,
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withOpacity(0.12)
              : AppTheme.cardElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.border,
            width: isSelected ? 2.0 : 0.8,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primary.withOpacity(0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSizePanel() {
    return Container(
      key: const ValueKey('size'),
      color: AppTheme.surface,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Passport Size',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          SizeDropdown(
            selectedSize: _selectedSize,
            onChanged: (size) {
              _saveToHistory();
              setState(() {
                _selectedSize = size;
                _userHasManuallyResized = false;
              });
            },
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  color: AppTheme.primary,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Export at 300 DPI: ${_selectedSize.exportSizePx.width.toInt()} × ${_selectedSize.exportSizePx.height.toInt()} px',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLightPanel() {
    final photoIndex = _layers.indexWhere((l) => l.id == 'photo');
    if (photoIndex == -1) {
      return Container(
        key: const ValueKey('light'),
        color: AppTheme.surface,
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        child: Text(
          'Photo layer not found',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            color: AppTheme.textSecondary,
          ),
        ),
      );
    }

    final photoLayer = _layers[photoIndex];
    final isBgImage = _bgOption.type == BgType.image;
    final isTargetPhoto = !isBgImage || _selectedLightTarget == 'photo';

    return Container(
      key: const ValueKey('light'),
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Light & Color Adjustments',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              TextButton(
                onPressed: () {
                  _saveToHistory();
                  setState(() {
                    if (isTargetPhoto) {
                      _layers[photoIndex] = photoLayer.copyWith(
                        brightness: 0.0,
                        contrast: 0.0,
                        exposure: 0.0,
                        colorHub: 'normal',
                        hue: 0.0,
                        tintOpacity: 0.0,
                      );
                    } else {
                      _bgOption = _bgOption.copyWith(
                        brightness: 0.0,
                        contrast: 0.0,
                        exposure: 0.0,
                        colorHub: 'normal',
                        hue: 0.0,
                        tintOpacity: 0.0,
                      );
                    }
                  });
                  _triggerAutoSave();
                },
                child: const Text(
                  'Reset All',
                  style: TextStyle(fontSize: 12, fontFamily: 'Poppins'),
                ),
              ),
            ],
          ),
          if (isBgImage) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              decoration: BoxDecoration(
                color: AppTheme.cardElevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border, width: 0.5),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedLightTarget = 'photo';
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _selectedLightTarget == 'photo'
                              ? AppTheme.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '👤 Person Photo',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _selectedLightTarget == 'photo'
                                ? Colors.white
                                : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedLightTarget = 'background';
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _selectedLightTarget == 'background'
                              ? AppTheme.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '🖼 Background Image',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _selectedLightTarget == 'background'
                                ? Colors.white
                                : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ] else ...[
            const SizedBox(height: 8),
          ],
          _SliderRow(
            key: ValueKey('${_selectedLightTarget}_brightness'),
            label: 'Brightness',
            value: isTargetPhoto ? photoLayer.brightness : _bgOption.brightness,
            min: -1.0,
            max: 1.0,
            divisions: 40,
            displayValue:
                (isTargetPhoto
                        ? photoLayer.brightness
                        : _bgOption.brightness) ==
                    0.0
                ? 'Original'
                : '${(isTargetPhoto ? photoLayer.brightness : _bgOption.brightness) > 0 ? '+' : ''}${(isTargetPhoto ? photoLayer.brightness : _bgOption.brightness).toStringAsFixed(2)}',
            onChangeStart: () => _saveToHistory(),
            onChanged: (val) {
              setState(() {
                if (isTargetPhoto) {
                  _layers[photoIndex] = photoLayer.copyWith(brightness: val);
                } else {
                  _bgOption = _bgOption.copyWith(brightness: val);
                }
              });
              _triggerAutoSave();
            },
            onReset: () {
              _saveToHistory();
              setState(() {
                if (isTargetPhoto) {
                  _layers[photoIndex] = photoLayer.copyWith(brightness: 0.0);
                } else {
                  _bgOption = _bgOption.copyWith(brightness: 0.0);
                }
              });
              _triggerAutoSave();
            },
          ),
          const SizedBox(height: 8),
          _SliderRow(
            key: ValueKey('${_selectedLightTarget}_contrast'),
            label: 'Contrast',
            value: isTargetPhoto ? photoLayer.contrast : _bgOption.contrast,
            min: -1.0,
            max: 1.0,
            divisions: 40,
            displayValue:
                (isTargetPhoto ? photoLayer.contrast : _bgOption.contrast) ==
                    0.0
                ? 'Original'
                : '${(isTargetPhoto ? photoLayer.contrast : _bgOption.contrast) > 0 ? '+' : ''}${(isTargetPhoto ? photoLayer.contrast : _bgOption.contrast).toStringAsFixed(2)}',
            onChangeStart: () => _saveToHistory(),
            onChanged: (val) {
              setState(() {
                if (isTargetPhoto) {
                  _layers[photoIndex] = photoLayer.copyWith(contrast: val);
                } else {
                  _bgOption = _bgOption.copyWith(contrast: val);
                }
              });
              _triggerAutoSave();
            },
            onReset: () {
              _saveToHistory();
              setState(() {
                if (isTargetPhoto) {
                  _layers[photoIndex] = photoLayer.copyWith(contrast: 0.0);
                } else {
                  _bgOption = _bgOption.copyWith(contrast: 0.0);
                }
              });
              _triggerAutoSave();
            },
          ),
          const SizedBox(height: 8),
          _SliderRow(
            key: ValueKey('${_selectedLightTarget}_exposure'),
            label: 'Exposure',
            value: isTargetPhoto ? photoLayer.exposure : _bgOption.exposure,
            min: -1.0,
            max: 1.0,
            divisions: 40,
            displayValue:
                (isTargetPhoto ? photoLayer.exposure : _bgOption.exposure) ==
                    0.0
                ? 'Original'
                : '${(isTargetPhoto ? photoLayer.exposure : _bgOption.exposure) > 0 ? '+' : ''}${(isTargetPhoto ? photoLayer.exposure : _bgOption.exposure).toStringAsFixed(2)}',
            onChangeStart: () => _saveToHistory(),
            onChanged: (val) {
              setState(() {
                if (isTargetPhoto) {
                  _layers[photoIndex] = photoLayer.copyWith(exposure: val);
                } else {
                  _bgOption = _bgOption.copyWith(exposure: val);
                }
              });
              _triggerAutoSave();
            },
            onReset: () {
              _saveToHistory();
              setState(() {
                if (isTargetPhoto) {
                  _layers[photoIndex] = photoLayer.copyWith(exposure: 0.0);
                } else {
                  _bgOption = _bgOption.copyWith(exposure: 0.0);
                }
              });
              _triggerAutoSave();
            },
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 72,
                child: Text(
                  'Color Hub',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: ['normal', 'warm', 'cold'].map((hub) {
                    final isSelected =
                        (isTargetPhoto
                            ? photoLayer.colorHub
                            : _bgOption.colorHub) ==
                        hub;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text(
                            hub[0].toUpperCase() + hub.substring(1),
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'Poppins',
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: isSelected
                                  ? Colors.white
                                  : AppTheme.textSecondary,
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: AppTheme.primary,
                          backgroundColor: AppTheme.card,
                          checkmarkColor: Colors.white,
                          onSelected: (selected) {
                            if (selected) {
                              _saveToHistory();
                              setState(() {
                                if (isTargetPhoto) {
                                  _layers[photoIndex] = photoLayer.copyWith(
                                    colorHub: hub,
                                  );
                                } else {
                                  _bgOption = _bgOption.copyWith(colorHub: hub);
                                }
                              });
                              _triggerAutoSave();
                            }
                          },
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 72,
                child: Text(
                  'Tint Hue',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 10,
                    trackShape: const GradientSliderTrackShape(),
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 8,
                    ),
                    overlayColor: Colors.white.withOpacity(0.1),
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    value: isTargetPhoto ? photoLayer.hue : _bgOption.hue,
                    min: 0.0,
                    max: 360.0,
                    onChangeStart: (_) => _saveToHistory(),
                    onChanged: (val) {
                      setState(() {
                        if (isTargetPhoto) {
                          final double newOpacity =
                              photoLayer.tintOpacity == 0.0
                              ? 0.20
                              : photoLayer.tintOpacity;
                          _layers[photoIndex] = photoLayer.copyWith(
                            hue: val,
                            tintOpacity: newOpacity,
                          );
                        } else {
                          final double newOpacity = _bgOption.tintOpacity == 0.0
                              ? 0.20
                              : _bgOption.tintOpacity;
                          _bgOption = _bgOption.copyWith(
                            hue: val,
                            tintOpacity: newOpacity,
                          );
                        }
                      });
                      _triggerAutoSave();
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      (isTargetPhoto
                              ? photoLayer.tintOpacity
                              : _bgOption.tintOpacity) >
                          0.0
                      ? HSVColor.fromAHSV(
                          1.0,
                          isTargetPhoto ? photoLayer.hue : _bgOption.hue,
                          1.0,
                          1.0,
                        ).toColor()
                      : Colors.transparent,
                  border: Border.all(color: AppTheme.border, width: 1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _SliderRow(
            key: ValueKey('${_selectedLightTarget}_tint_intensity'),
            label: 'Tint Level',
            value: isTargetPhoto
                ? photoLayer.tintOpacity
                : _bgOption.tintOpacity,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            displayValue:
                '${((isTargetPhoto ? photoLayer.tintOpacity : _bgOption.tintOpacity) * 100).toInt()}%',
            onChangeStart: () => _saveToHistory(),
            onChanged: (val) {
              setState(() {
                if (isTargetPhoto) {
                  _layers[photoIndex] = photoLayer.copyWith(tintOpacity: val);
                } else {
                  _bgOption = _bgOption.copyWith(tintOpacity: val);
                }
              });
              _triggerAutoSave();
            },
            onReset: () {
              _saveToHistory();
              setState(() {
                if (isTargetPhoto) {
                  _layers[photoIndex] = photoLayer.copyWith(tintOpacity: 0.0);
                } else {
                  _bgOption = _bgOption.copyWith(tintOpacity: 0.0);
                }
              });
              _triggerAutoSave();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBgPanel() {
    return BgPanel(
      key: const ValueKey('bg'),
      selected: _bgOption,
      onChanged: (bg) {
        _saveToHistory();
        setState(() {
          _bgOption = bg;
          if (bg.type != BgType.image) {
            _selectedLightTarget = 'photo';
            if (_selectedLayerId == 'background') {
              _selectedLayerId = null;
            }
          } else {
            _selectedLayerId = 'background';
          }
        });
      },
    );
  }

  Widget _buildSmoothPanel() {
    return Container(
      key: const ValueKey('smooth'),
      color: AppTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Background Cutout Smoothness',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Adjust this slider to refine the background removal edges.',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              color: AppTheme.muted,
            ),
          ),
          const SizedBox(height: 16),
          _SliderRow(
            label: 'Smooth',
            value: _bgThreshold,
            min: 1.0,
            max: 10.0,
            divisions: 90,
            displayValue: _bgThreshold.toStringAsFixed(1),
            onChangeStart: () => _saveToHistory(),
            onChanged: _onThresholdChanged,
            onReset: () {
              _saveToHistory();
              _onThresholdChanged(6.5);
            },
          ),
          if (_isProcessingBg)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Center(
                child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTransformPanel() {
    if (_selectedLayerId == null) {
      return Container(
        key: const ValueKey('transform'),
        color: AppTheme.surface,
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        child: Text(
          'Select a layer first to transform it',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            color: AppTheme.textSecondary,
          ),
        ),
      );
    }

    final layerIndex = _layers.indexWhere((l) => l.id == _selectedLayerId);
    if (layerIndex == -1) return const SizedBox.shrink();
    final selectedLayer = _layers[layerIndex];

    return Container(
      key: const ValueKey('transform'),
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Scale
          _SliderRow(
            key: ValueKey('scale_${selectedLayer.id}'),
            label: 'Scale',
            value: selectedLayer.scale,
            min: 0.1,
            max: 5.0,
            divisions: 98,
            displayValue: '${(selectedLayer.scale * 100).toInt()}%',
            onChangeStart: () => _saveToHistory(),
            onChanged: (v) {
              setState(() {
                if (selectedLayer.id == 'photo') {
                  _userHasManuallyResized = true;
                }
                _layers[layerIndex] = selectedLayer.copyWith(scale: v);
              });
            },
            onReset: () {
              _saveToHistory();
              setState(() {
                if (selectedLayer.id == 'photo') {
                  _userHasManuallyResized = true;
                }
                _layers[layerIndex] = selectedLayer.copyWith(scale: 1.0);
              });
            },
          ),
          const SizedBox(height: 12),
          // Rotation
          _SliderRow(
            key: ValueKey('rot_${selectedLayer.id}'),
            label: 'Rotation',
            value: selectedLayer.rotation,
            min: -180,
            max: 180,
            divisions: 360,
            displayValue: '${selectedLayer.rotation.toInt()}°',
            onChangeStart: () => _saveToHistory(),
            onChanged: (v) {
              setState(() {
                if (selectedLayer.id == 'photo') {
                  _userHasManuallyResized = true;
                }
                _layers[layerIndex] = selectedLayer.copyWith(rotation: v);
              });
            },
            onReset: () {
              _saveToHistory();
              setState(() {
                if (selectedLayer.id == 'photo') {
                  _userHasManuallyResized = true;
                }
                _layers[layerIndex] = selectedLayer.copyWith(rotation: 0.0);
              });
            },
          ),
          const SizedBox(height: 12),
          // Reset all
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                _saveToHistory();
                setState(() {
                  if (selectedLayer.id == 'photo') {
                    _userHasManuallyResized = true;
                  }
                  _layers[layerIndex] = selectedLayer.copyWith(
                    scale: 1.0,
                    rotation: 0.0,
                    offset: Offset.zero,
                  );
                });
              },
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Reset Transform'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.muted,
                side: BorderSide(color: AppTheme.border),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLayersPanel() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 500;
        return Container(
          key: const ValueKey('layers'),
          color: AppTheme.surface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          constraints: const BoxConstraints(maxHeight: 280),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Row with Add buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _addTextLayer,
                      icon: const Icon(Icons.text_fields_rounded, size: 18),
                      label: const Text('Add Text'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        backgroundColor: AppTheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _addShapeLayer,
                      icon: const Icon(Icons.category_rounded, size: 18),
                      label: const Text('Add Shape'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        backgroundColor: AppTheme.accent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              if (isMobile) ...[
                // Custom mobile toggle tab bar
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _showLayerSettingsTab = false),
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: !_showLayerSettingsTab
                                    ? AppTheme.primary
                                    : Colors.transparent,
                                width: 2.0,
                              ),
                            ),
                          ),
                          child: Text(
                            'Layers List (${_layers.length})',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              fontWeight: !_showLayerSettingsTab
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: !_showLayerSettingsTab
                                  ? AppTheme.primary
                                  : AppTheme.muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _showLayerSettingsTab = true),
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: _showLayerSettingsTab
                                    ? AppTheme.primary
                                    : Colors.transparent,
                                width: 2.0,
                              ),
                            ),
                          ),
                          child: Text(
                            'Layer Settings',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              fontWeight: _showLayerSettingsTab
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: _showLayerSettingsTab
                                  ? AppTheme.primary
                                  : AppTheme.muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ] else ...[
                const Divider(),
                const SizedBox(height: 8),
              ],

              Expanded(
                child: isMobile
                    ? (_showLayerSettingsTab
                          ? SingleChildScrollView(
                              child: _buildSelectedLayerProperties(),
                            )
                          : _buildLayersList())
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 11, child: _buildLayersList()),
                          const SizedBox(width: 12),
                          const VerticalDivider(),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 9,
                            child: SingleChildScrollView(
                              child: _buildSelectedLayerProperties(),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLayersList() {
    return ListView.builder(
      itemCount: _layers.length,
      itemBuilder: (ctx, index) {
        final reverseIndex = _layers.length - 1 - index;
        final layer = _layers[reverseIndex];
        final isSelected = layer.id == _selectedLayerId;

        IconData icon;
        switch (layer.type) {
          case LayerType.photo:
            icon = Icons.image_rounded;
            break;
          case LayerType.text:
            icon = Icons.title_rounded;
            break;
          case LayerType.shape:
            icon = Icons.interests_rounded;
            break;
          case LayerType.clothing:
            icon = Icons.checkroom_rounded;
            break;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primary.withOpacity(0.15)
                : AppTheme.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? AppTheme.primary : AppTheme.border,
              width: isSelected ? 1.5 : 0.5,
            ),
          ),
          child: ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 0,
            ),
            leading: Icon(
              icon,
              color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
              size: 18,
            ),
            title: Text(
              layer.name,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? AppTheme.primary : AppTheme.textPrimary,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_upward_rounded, size: 14),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: reverseIndex < _layers.length - 1
                      ? () => _moveLayer(reverseIndex, reverseIndex + 1)
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_downward_rounded, size: 14),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: reverseIndex > 0
                      ? () => _moveLayer(reverseIndex, reverseIndex - 1)
                      : null,
                ),
                IconButton(
                  icon: Icon(
                    layer.isVisible
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    size: 14,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    _saveToHistory();
                    setState(() {
                      _layers[reverseIndex] = layer.copyWith(
                        isVisible: !layer.isVisible,
                      );
                    });
                  },
                ),
                if (layer.type != LayerType.photo)
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      size: 14,
                      color: AppTheme.error,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _deleteLayer(layer.id),
                  ),
              ],
            ),
            onTap: () {
              setState(() {
                _selectedLayerId = layer.id;
                _showLayerSettingsTab = true;
              });
            },
          ),
        );
      },
    );
  }

  Widget _buildSelectedLayerProperties() {
    if (_selectedLayerId == null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.only(top: 24),
          child: Text(
            'Select a layer to edit properties',
            style: TextStyle(
              fontSize: 11,
              color: AppTheme.muted,
              fontFamily: 'Inter',
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final layerIndex = _layers.indexWhere((l) => l.id == _selectedLayerId);
    if (layerIndex == -1) return const SizedBox.shrink();
    final layer = _layers[layerIndex];

    switch (layer.type) {
      case LayerType.photo:
        return Center(child: Text("Nothing to do."));

      case LayerType.text:
        return _TextPropertiesPanel(
          layer: layer,
          onStartEdit: () => _saveToHistory(),
          onChanged: (updated) {
            setState(() {
              _layers[layerIndex] = updated;
            });
          },
        );

      case LayerType.shape:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Shape Settings',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
                fontFamily: 'Poppins',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Shape Type',
              style: TextStyle(
                fontSize: 10,
                color: AppTheme.muted,
                fontFamily: 'Inter',
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.border),
                borderRadius: BorderRadius.circular(4),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<ShapeType>(
                  value: layer.shapeType ?? ShapeType.rectangle,
                  isExpanded: true,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textPrimary,
                    fontFamily: 'Inter',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: ShapeType.rectangle,
                      child: Text('Rectangle'),
                    ),
                    DropdownMenuItem(
                      value: ShapeType.circle,
                      child: Text('Circle'),
                    ),
                    DropdownMenuItem(
                      value: ShapeType.oval,
                      child: Text('Oval'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      _saveToHistory();
                      setState(() {
                        _layers[layerIndex] = layer.copyWith(shapeType: val);
                      });
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Hollow (Border only)',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'Inter',
                    color: AppTheme.textPrimary,
                  ),
                ),
                Switch(
                  value: layer.fillColor == Colors.transparent,
                  activeColor: AppTheme.primary,
                  onChanged: (isHollow) {
                    _saveToHistory();
                    setState(() {
                      if (isHollow) {
                        _layers[layerIndex] = layer.copyWith(
                          fillColor: Colors.transparent,
                          strokeColor:
                              (layer.strokeColor == Colors.transparent ||
                                  layer.strokeColor == null)
                              ? AppTheme.primary
                              : layer.strokeColor,
                          strokeWidth:
                              (layer.strokeWidth == null ||
                                  layer.strokeWidth == 0.0)
                              ? 2.0
                              : layer.strokeWidth,
                        );
                      } else {
                        _layers[layerIndex] = layer.copyWith(
                          fillColor: AppTheme.primary,
                        );
                      }
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (layer.fillColor != Colors.transparent) ...[
              Text(
                'Fill Color',
                style: TextStyle(
                  fontSize: 10,
                  color: AppTheme.muted,
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(height: 4),
              _buildPresetColorsRow((color) {
                _saveToHistory();
                setState(() {
                  _layers[layerIndex] = layer.copyWith(fillColor: color);
                });
              }, layer.fillColor ?? AppTheme.primary),
              const SizedBox(height: 8),
            ],
            Text(
              'Border Color',
              style: TextStyle(
                fontSize: 10,
                color: AppTheme.muted,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 4),
            _buildPresetColorsRow(
              (color) {
                _saveToHistory();
                setState(() {
                  _layers[layerIndex] = layer.copyWith(strokeColor: color);
                });
              },
              layer.strokeColor ?? Colors.transparent,
              includeTransparent: true,
            ),
            const SizedBox(height: 8),
            Text(
              'Border Width',
              style: TextStyle(
                fontSize: 10,
                color: AppTheme.muted,
                fontFamily: 'Inter',
              ),
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: layer.strokeWidth ?? 2.0,
                min: 0.0,
                max: 15.0,
                divisions: 30,
                onChangeStart: (val) {
                  _saveToHistory();
                },
                onChanged: (val) {
                  setState(() {
                    _layers[layerIndex] = layer.copyWith(strokeWidth: val);
                  });
                },
              ),
            ),
          ],
        );

      case LayerType.clothing:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Clothing Layer Settings',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
                fontFamily: 'Poppins',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Select "Transform" tab to scale, rotate, or reposition this outfit to fit your photo.',
              style: TextStyle(
                fontSize: 10,
                color: AppTheme.muted,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _deleteLayer(layer.id),
                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                label: const Text('Remove Clothing'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.error,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        );
    }
  }

  Widget _buildPresetColorsRow(
    ValueChanged<Color> onSelected,
    Color selectedColor, {
    bool includeTransparent = false,
  }) {
    final colors = [
      if (includeTransparent) Colors.transparent,
      Colors.white,
      Colors.black,
      Colors.red,
      Colors.orange,
      Colors.yellow,
      Colors.green,
      Colors.blue,
      Colors.purple,
      AppTheme.primary,
      AppTheme.accent,
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: colors.map((color) {
          final isSelected = color == selectedColor;
          final isTransparent = color == Colors.transparent;

          return GestureDetector(
            onTap: () => onSelected(color),
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: isTransparent ? Colors.transparent : color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? AppTheme.primary
                      : (isTransparent ? Colors.grey : Colors.white24),
                  width: isSelected ? 2.0 : 1.0,
                ),
              ),
              child: isTransparent
                  ? const Center(
                      child: Icon(Icons.close, size: 10, color: Colors.grey),
                    )
                  : null,
            ),
          );
        }).toList(),
      ),
    );
  }

  void _addTextLayer() {
    _saveToHistory();
    setState(() {
      final id = 'text_${DateTime.now().millisecondsSinceEpoch}';
      final count = _layers.where((l) => l.type == LayerType.text).length + 1;
      _layers.add(
        EditorLayer(
          id: id,
          type: LayerType.text,
          name: 'Text $count',
          text: 'Text $count',
          color: Colors.white,
          fontSize: 22.0,
          fontFamily: 'Poppins',
          scale: 1.0,
          rotation: 0.0,
          offset: Offset.zero,
        ),
      );
      _selectedLayerId = id;
      _showLayerSettingsTab = true;
    });
  }

  void _addShapeLayer() {
    _saveToHistory();
    setState(() {
      final id = 'shape_${DateTime.now().millisecondsSinceEpoch}';
      final count = _layers.where((l) => l.type == LayerType.shape).length + 1;
      _layers.add(
        EditorLayer(
          id: id,
          type: LayerType.shape,
          name: 'Shape $count',
          shapeType: ShapeType.rectangle,
          fillColor: AppTheme.primary,
          strokeColor: Colors.transparent,
          strokeWidth: 2.0,
          scale: 1.0,
          rotation: 0.0,
          offset: Offset.zero,
        ),
      );
      _selectedLayerId = id;
      _showLayerSettingsTab = true;
    });
  }

  void _moveLayer(int fromIndex, int toIndex) {
    if (fromIndex < 0 || fromIndex >= _layers.length) return;
    if (toIndex < 0 || toIndex >= _layers.length) return;

    _saveToHistory();
    setState(() {
      final layer = _layers.removeAt(fromIndex);
      _layers.insert(toIndex, layer);
    });
  }

  void _deleteLayer(String layerId) {
    if (layerId == 'photo') return;

    _saveToHistory();
    setState(() {
      _layers.removeWhere((l) => l.id == layerId);
      if (_selectedLayerId == layerId) {
        _selectedLayerId = _layers.isNotEmpty ? _layers.first.id : null;
      }
    });
  }

  void _addClothLayer(String assetPath, String name) {
    _saveToHistory();
    setState(() {
      final clothIndex = _layers.indexWhere(
        (l) => l.type == LayerType.clothing,
      );

      double initialScale = 1.0;
      Offset initialOffset = const Offset(0, 80);

      final photoIndex = _layers.indexWhere((l) => l.type == LayerType.photo);
      if (photoIndex != -1 &&
          _foregroundBounds != null &&
          _bgRemovedImage != null) {
        final photoLayer = _layers[photoIndex];
        final bounds = _foregroundBounds!;
        final imgWidth = _bgRemovedImage!.width.toDouble();
        final imgHeight = _bgRemovedImage!.height.toDouble();

        if (imgWidth > 0 && imgHeight > 0 && bounds.width > 0) {
          // Calculate neck/shoulder point in image center-relative space.
          // The neckline is roughly 65% down the person's detected bounding box.
          final neckXRelative = bounds.center.dx - (imgWidth / 2);
          final neckYRelative =
              bounds.top + (bounds.height * 0.65) - (imgHeight / 2);

          // Convert the neck/shoulder point to canvas space using the active photo's scale and offset
          final neckCanvasX =
              neckXRelative * photoLayer.scale + photoLayer.offset.dx;
          final neckCanvasY =
              neckYRelative * photoLayer.scale + photoLayer.offset.dy;

          // Size the clothing relative to the person's bounding box width.
          // Base width of the clothing widget is 250.0.
          initialScale = (bounds.width * photoLayer.scale) / 250.0 * 1.10;
          initialScale = initialScale.clamp(0.4, 3.0);

          // Place the center of the clothing layer just below the neckline
          initialOffset = Offset(
            neckCanvasX,
            neckCanvasY + (85.0 * initialScale),
          );
        }
      } else {
        final canvasHeight = _lastCanvasSize?.height ?? 300.0;
        initialOffset = Offset(0, canvasHeight * 0.22);
      }

      if (clothIndex != -1) {
        // Replace existing clothing asset, keeping the scale, rotation, and offset!
        _layers[clothIndex] = _layers[clothIndex].copyWith(
          name: name,
          clothingAssetPath: assetPath,
        );
        _selectedLayerId = _layers[clothIndex].id;
      } else {
        // Add a new clothing layer
        final id = 'cloth_${DateTime.now().millisecondsSinceEpoch}';
        _layers.add(
          EditorLayer(
            id: id,
            type: LayerType.clothing,
            name: name,
            clothingAssetPath: assetPath,
            scale: initialScale,
            rotation: 0.0,
            offset: initialOffset,
          ),
        );
        _selectedLayerId = id;
      }
      _showLayerSettingsTab = true;
    });
  }

  Widget _buildClothPanel() {
    final catalog = {
      'man': [
        _ClothingItem('Student White Shirt', 'assets/clothes/man_student_white.png'),
        _ClothingItem('Student Blue Shirt', 'assets/clothes/man_student_blue.png'),
        _ClothingItem('Student Blazer', 'assets/clothes/man_student_blazer.png'),
        _ClothingItem('Black Suit', 'assets/clothes/man_suit_black.png'),
        _ClothingItem('Navy Suit', 'assets/clothes/man_suit_blue.png'),
        _ClothingItem('White Shirt', 'assets/clothes/man_shirt_white.png'),
        _ClothingItem('Grey Suit', 'assets/clothes/man_suit_grey.png'),
      ],
      'woman': [
        _ClothingItem('Student White Blouse', 'assets/clothes/woman_student_white.png'),
        _ClothingItem('Student Blue Blouse', 'assets/clothes/woman_student_blue.png'),
        _ClothingItem('Student Blazer', 'assets/clothes/woman_student_blazer.png'),
        _ClothingItem('Black Blazer', 'assets/clothes/woman_suit_black.png'),
        _ClothingItem('Navy Blazer', 'assets/clothes/woman_suit_blue.png'),
        _ClothingItem('White Blouse', 'assets/clothes/woman_shirt_white.png'),
        _ClothingItem('Red Blazer', 'assets/clothes/woman_blazer_red.png'),
      ],
      'child': [
        _ClothingItem('Black Suit', 'assets/clothes/child_suit_black.png'),
        _ClothingItem('Blue Uniform', 'assets/clothes/child_uniform_blue.png'),
        _ClothingItem('Grey Vest', 'assets/clothes/child_suit_grey.png'),
        _ClothingItem('Pink Blouse', 'assets/clothes/child_dress_pink.png'),
      ],
    };

    final items = catalog[_clothCategory] ?? [];

    return Container(
      key: const ValueKey('clothes'),
      color: AppTheme.surface,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Change Clothing',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              Row(
                children: ['man', 'woman', 'child'].map((category) {
                  final isSelected = _clothCategory == category;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _clothCategory = category;
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.primary : AppTheme.card,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.primary
                              : AppTheme.border,
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        category[0].toUpperCase() + category.substring(1),
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: isSelected
                              ? Colors.white
                              : AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              itemBuilder: (ctx, index) {
                final item = items[index];
                final isAdded = _layers.any(
                  (l) =>
                      l.type == LayerType.clothing &&
                      l.clothingAssetPath == item.assetPath,
                );

                return GestureDetector(
                  onTap: () => _addClothLayer(item.assetPath, item.name),
                  child: Container(
                    width: 80,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isAdded ? AppTheme.primary : AppTheme.border,
                        width: isAdded ? 2.0 : 0.5,
                      ),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        Expanded(
                          child: Image.asset(
                            item.assetPath,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.name,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 9,
                            fontWeight: isAdded
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: isAdded
                                ? AppTheme.primary
                                : AppTheme.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String displayValue;
  final ValueChanged<double> onChanged;
  final VoidCallback onReset;
  final VoidCallback? onChangeStart;

  const _SliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.displayValue,
    required this.onChanged,
    required this.onReset,
    this.onChangeStart,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(trackHeight: 3),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChangeStart: onChangeStart != null
                  ? (_) => onChangeStart!()
                  : null,
              onChanged: onChanged,
            ),
          ),
        ),
        GestureDetector(
          onTap: onReset,
          child: Container(
            width: 52,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              displayValue,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                color: AppTheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ExportingDialog extends StatelessWidget {
  final ValueNotifier<String> statusNotifier;
  final ValueNotifier<String> subTextNotifier;
  final ValueNotifier<double> progressNotifier;

  const _ExportingDialog({
    required this.statusNotifier,
    required this.subTextNotifier,
    required this.progressNotifier,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Title ──────────────────────────────────────────────────
              ValueListenableBuilder<String>(
                valueListenable: statusNotifier,
                builder: (context, status, _) => Text(
                  status,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 20),
              // ── Progress bar + % ───────────────────────────────────────
              ValueListenableBuilder<double>(
                valueListenable: progressNotifier,
                builder: (context, progress, _) {
                  final pct = (progress * 100).round();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: progress > 0 ? progress : null,
                          minHeight: 8,
                          backgroundColor: AppTheme.muted.withValues(
                            alpha: 0.2,
                          ),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppTheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          progress > 0 ? '$pct%' : 'Starting…',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
              // ── Sub-text (tile info) ───────────────────────────────────
              ValueListenableBuilder<String>(
                valueListenable: subTextNotifier,
                builder: (context, sub, _) => Text(
                  sub,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    color: AppTheme.muted,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextPropertiesPanel extends StatefulWidget {
  final EditorLayer layer;
  final ValueChanged<EditorLayer> onChanged;
  final VoidCallback? onStartEdit;

  const _TextPropertiesPanel({
    required this.layer,
    required this.onChanged,
    this.onStartEdit,
  });

  @override
  State<_TextPropertiesPanel> createState() => _TextPropertiesPanelState();
}

class _TextPropertiesPanelState extends State<_TextPropertiesPanel> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.layer.text);
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        widget.onStartEdit?.call();
      }
    });
  }

  @override
  void didUpdateWidget(covariant _TextPropertiesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.layer.id != oldWidget.layer.id) {
      _controller.text = widget.layer.text ?? '';
    } else if (widget.layer.text != _controller.text) {
      final selection = _controller.selection;
      _controller.text = widget.layer.text ?? '';
      _controller.selection = selection;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Text Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
            fontFamily: 'Poppins',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          style: const TextStyle(fontSize: 12, fontFamily: 'Inter'),
          decoration: const InputDecoration(
            labelText: 'Edit Text',
            labelStyle: TextStyle(fontSize: 11),
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          ),
          onChanged: (val) {
            widget.onChanged(widget.layer.copyWith(text: val));
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Size',
          style: TextStyle(
            fontSize: 10,
            color: AppTheme.muted,
            fontFamily: 'Inter',
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: Slider(
            value: widget.layer.fontSize ?? 22.0,
            min: 8.0,
            max: 72.0,
            divisions: 64,
            onChangeStart: (val) {
              widget.onStartEdit?.call();
            },
            onChanged: (val) {
              widget.onChanged(widget.layer.copyWith(fontSize: val));
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Font Family',
          style: TextStyle(
            fontSize: 10,
            color: AppTheme.muted,
            fontFamily: 'Inter',
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.border),
            borderRadius: BorderRadius.circular(4),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: widget.layer.fontFamily ?? 'Poppins',
              isExpanded: true,
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.textPrimary,
                fontFamily: 'Inter',
              ),
              items: const [
                DropdownMenuItem(value: 'Poppins', child: Text('Poppins')),
                DropdownMenuItem(value: 'Roboto', child: Text('Roboto')),
                DropdownMenuItem(value: 'Inter', child: Text('Inter')),
                DropdownMenuItem(
                  value: 'Georgia',
                  child: Text('Georgia (Serif)'),
                ),
                DropdownMenuItem(
                  value: 'Courier',
                  child: Text('Courier (Typewriter)'),
                ),
                DropdownMenuItem(value: 'Arial', child: Text('Arial (Sans)')),
                DropdownMenuItem(value: 'cursive', child: Text('Cursive')),
                DropdownMenuItem(value: 'monospace', child: Text('Monospace')),
              ],
              onChanged: (val) {
                if (val != null) {
                  widget.onStartEdit?.call();
                  widget.onChanged(widget.layer.copyWith(fontFamily: val));
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Color',
          style: TextStyle(
            fontSize: 10,
            color: AppTheme.muted,
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(height: 4),
        _buildPresetColorsRow((color) {
          widget.onStartEdit?.call();
          widget.onChanged(widget.layer.copyWith(color: color));
        }, widget.layer.color ?? Colors.white),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ChoiceChip(
                label: const Text(
                  'B',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
                selected: widget.layer.isBold ?? false,
                onSelected: (selected) {
                  widget.onStartEdit?.call();
                  widget.onChanged(widget.layer.copyWith(isBold: selected));
                },
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: ChoiceChip(
                label: const Text(
                  'I',
                  style: TextStyle(fontStyle: FontStyle.italic, fontSize: 11),
                ),
                selected: widget.layer.isItalic ?? false,
                onSelected: (selected) {
                  widget.onStartEdit?.call();
                  widget.onChanged(widget.layer.copyWith(isItalic: selected));
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPresetColorsRow(
    ValueChanged<Color> onSelected,
    Color selectedColor, {
    bool includeTransparent = false,
  }) {
    final colors = [
      if (includeTransparent) Colors.transparent,
      Colors.white,
      Colors.black,
      Colors.red,
      Colors.orange,
      Colors.yellow,
      Colors.green,
      Colors.blue,
      Colors.purple,
      AppTheme.primary,
      AppTheme.accent,
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: colors.map((color) {
          final isSelected = color == selectedColor;
          final isTransparent = color == Colors.transparent;

          return GestureDetector(
            onTap: () => onSelected(color),
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: isTransparent ? Colors.transparent : color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? AppTheme.primary
                      : (isTransparent ? Colors.grey : Colors.white24),
                  width: isSelected ? 2.0 : 1.0,
                ),
              ),
              child: isTransparent
                  ? const Center(
                      child: Icon(Icons.close, size: 10, color: Colors.grey),
                    )
                  : null,
            ),
          );
        }).toList(),
      ),
    );
  }
}

class EditorHistoryState {
  final PassportSize selectedSize;
  final BgOption bgOption;
  final List<EditorLayer> layers;
  final String? selectedLayerId;
  final bool userHasManuallyResized;
  final Uint8List? bgRemovedBytes;
  final ui.Image? bgRemovedImage;
  final double bgThreshold;
  final Rect? foregroundBounds;

  EditorHistoryState({
    required this.selectedSize,
    required this.bgOption,
    required this.layers,
    required this.selectedLayerId,
    required this.userHasManuallyResized,
    required this.bgRemovedBytes,
    required this.bgRemovedImage,
    required this.bgThreshold,
    required this.foregroundBounds,
  });
}

class _ClothingItem {
  final String name;
  final String assetPath;
  _ClothingItem(this.name, this.assetPath);
}
