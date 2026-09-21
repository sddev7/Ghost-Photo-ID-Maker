import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/passport_size.dart';
import '../models/bg_option.dart';
import '../models/editor_layer.dart';
import '../theme/app_theme.dart';
import '../utils/image_utils.dart';

class CanvasWidget extends StatefulWidget {
  final GlobalKey repaintKey;
  final Uint8List? imageBytes; // The background-removed foreground image bytes
  final ui.Image? originalImage;
  final ui.Image? bgRemovedImage;
  final PassportSize passportSize;
  final BgOption bgOption;
  final List<EditorLayer> layers;
  final String? selectedLayerId;
  final bool isExporting;
  final void Function(String id, Offset offset, double scale, double rotation)
  onLayerTransform;
  final void Function(String id) onSelectLayer;
  final VoidCallback? onLayerTransformStart;
  final bool useLightCheckerboard;
  final VoidCallback onToggleCheckerboard;

  final bool showWatermark;
  final String watermarkText;

  // Brush settings
  final bool isBrushModeActive;
  final BrushMode brushMode;
  final double brushRadius;
  final double brushOffset;
  final void Function(BrushStroke stroke) onAddBrushStroke;

  const CanvasWidget({
    super.key,
    required this.repaintKey,
    required this.imageBytes,
    this.originalImage,
    this.bgRemovedImage,
    required this.passportSize,
    required this.bgOption,
    required this.layers,
    required this.selectedLayerId,
    required this.onLayerTransform,
    required this.onSelectLayer,
    required this.useLightCheckerboard,
    required this.onToggleCheckerboard,
    this.onLayerTransformStart,
    this.isExporting = false,
    this.showWatermark = false,
    this.watermarkText = 'Passport Maker',
    this.isBrushModeActive = false,
    this.brushMode = BrushMode.erase,
    this.brushRadius = 25.0,
    this.brushOffset = 40.0,
    required this.onAddBrushStroke,
  });

  @override
  State<CanvasWidget> createState() => _CanvasWidgetState();
}

class _CanvasWidgetState extends State<CanvasWidget> {
  double _baseScale = 1.0;
  double _baseRotation = 0.0;
  Offset _baseOffset = Offset.zero;
  Offset _gestureStartOffset = Offset.zero;

  // Brush state
  BrushStroke? _currentStroke;
  Offset? _brushCursorPoint;

  Offset _rotateOffset(Offset offset, double angleDegrees) {
    final double radians = angleDegrees * math.pi / 180;
    final double cos = math.cos(radians);
    final double sin = math.sin(radians);
    return Offset(
      offset.dx * cos - offset.dy * sin,
      offset.dx * sin + offset.dy * cos,
    );
  }

  Offset _getLocalPoint(Offset canvasTouchPoint, Size canvasSize, EditorLayer photoLayer) {
    final canvasCenter = Offset(canvasSize.width / 2, canvasSize.height / 2);
    final relativeToCenter = canvasTouchPoint - canvasCenter;
    final afterOffset = relativeToCenter - photoLayer.offset;
    final afterRotation = _rotateOffset(afterOffset, -photoLayer.rotation);
    return afterRotation / photoLayer.scale;
  }

  void _onBrushStart(DragStartDetails details, Size canvasSize) {
    final photoIndex = widget.layers.indexWhere((l) => l.id == 'photo');
    if (photoIndex == -1) return;
    final photoLayer = widget.layers[photoIndex];

    final localPt = _getLocalPoint(details.localPosition, canvasSize, photoLayer);
    setState(() {
      _brushCursorPoint = details.localPosition;
      _currentStroke = BrushStroke(
        points: [localPt],
        mode: widget.brushMode,
        radius: widget.brushRadius / photoLayer.scale,
      );
    });
  }

  void _onBrushUpdate(DragUpdateDetails details, Size canvasSize) {
    final photoIndex = widget.layers.indexWhere((l) => l.id == 'photo');
    if (photoIndex == -1) return;
    final photoLayer = widget.layers[photoIndex];

    final localPt = _getLocalPoint(details.localPosition, canvasSize, photoLayer);
    setState(() {
      _brushCursorPoint = details.localPosition;
      if (_currentStroke != null) {
        final updatedPoints = List<Offset>.from(_currentStroke!.points)..add(localPt);
        _currentStroke = BrushStroke(
          points: updatedPoints,
          mode: _currentStroke!.mode,
          radius: _currentStroke!.radius,
        );
      }
    });
  }

  void _onBrushEnd(DragEndDetails details) {
    if (_currentStroke != null) {
      widget.onAddBrushStroke(_currentStroke!);
    }
    setState(() {
      _currentStroke = null;
      _brushCursorPoint = null;
    });
  }

  // Viewport zoom and pan state for Brush mode
  double _viewportScale = 1.0;
  Offset _viewportOffset = Offset.zero;
  double _baseViewportScale = 1.0;
  Offset _baseViewportOffset = Offset.zero;
  bool _isViewportPanningZooming = false;
  DateTime? _lastViewportPanZoomEndTime;

  @override
  void initState() {
    super.initState();
    if (widget.isBrushModeActive) {
      _viewportScale = 1.35;
      _viewportOffset = const Offset(0, -35.0);
    }
  }

  @override
  void didUpdateWidget(CanvasWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isBrushModeActive != oldWidget.isBrushModeActive) {
      setState(() {
        if (widget.isBrushModeActive) {
          _viewportScale = 1.35;
          _viewportOffset = const Offset(0, -35.0);
        } else {
          _viewportScale = 1.0;
          _viewportOffset = Offset.zero;
        }
        _isViewportPanningZooming = false;
      });
    }
  }

  void _onScaleStartBrush(ScaleStartDetails details, Size canvasSize) {
    if (details.pointerCount >= 2) {
      _isViewportPanningZooming = true;
      _baseViewportScale = _viewportScale;
      _baseViewportOffset = _viewportOffset;
      _gestureStartOffset = details.localFocalPoint;
      
      // Cancel/end brush stroke if active so we don't draw lines while panning
      if (_currentStroke != null) {
        setState(() {
          _currentStroke = null;
          _brushCursorPoint = null;
        });
      }
    } else {
      if (_lastViewportPanZoomEndTime != null &&
          DateTime.now().difference(_lastViewportPanZoomEndTime!).inMilliseconds < 300) {
        return;
      }
      _isViewportPanningZooming = false;
      final canvasCenter = Offset(canvasSize.width / 2, canvasSize.height / 2);
      
      // Apply offset to finger position in screen space (moving it upwards)
      final offsetFocalPoint = details.localFocalPoint + Offset(0, -widget.brushOffset);
      
      // Translate to canvas space
      final P_canvas = canvasCenter + (offsetFocalPoint - canvasCenter - _viewportOffset) / _viewportScale;
      
      final photoIndex = widget.layers.indexWhere((l) => l.id == 'photo');
      if (photoIndex == -1) return;
      final photoLayer = widget.layers[photoIndex];

      final localPt = _getLocalPoint(P_canvas, canvasSize, photoLayer);
      setState(() {
        _brushCursorPoint = P_canvas;
        _currentStroke = BrushStroke(
          points: [localPt],
          mode: widget.brushMode,
          radius: widget.brushRadius / photoLayer.scale,
        );
      });
    }
  }

  void _onScaleUpdateBrush(ScaleUpdateDetails details, Size canvasSize) {
    if (details.pointerCount >= 2) {
      if (!_isViewportPanningZooming) {
        // Second finger touched down. Switch to viewport pan/zoom.
        _isViewportPanningZooming = true;
        _baseViewportScale = _viewportScale;
        _baseViewportOffset = _viewportOffset;
        _gestureStartOffset = details.localFocalPoint;
        
        // Discard any brush stroke in progress
        setState(() {
          _currentStroke = null;
          _brushCursorPoint = null;
        });
        return;
      }
      
      setState(() {
        _viewportScale = (_baseViewportScale * details.scale).clamp(0.5, 10.0);
        final panDelta = details.localFocalPoint - _gestureStartOffset;
        _viewportOffset = _baseViewportOffset + panDelta;
      });
    } else {
      // 1-finger drawing
      if (_isViewportPanningZooming) {
        // If we are currently in viewport zoom/pan mode, ignore drawing until all fingers are lifted
        return;
      }
      if (_lastViewportPanZoomEndTime != null &&
          DateTime.now().difference(_lastViewportPanZoomEndTime!).inMilliseconds < 300) {
        return;
      }
      
      final canvasCenter = Offset(canvasSize.width / 2, canvasSize.height / 2);
      
      // Apply offset to finger position in screen space
      final offsetFocalPoint = details.localFocalPoint + Offset(0, -widget.brushOffset);
      
      // Translate to canvas space
      final P_canvas = canvasCenter + (offsetFocalPoint - canvasCenter - _viewportOffset) / _viewportScale;
      
      final photoIndex = widget.layers.indexWhere((l) => l.id == 'photo');
      if (photoIndex == -1) return;
      final photoLayer = widget.layers[photoIndex];

      final localPt = _getLocalPoint(P_canvas, canvasSize, photoLayer);
      setState(() {
        _brushCursorPoint = P_canvas;
        if (_currentStroke != null) {
          final updatedPoints = List<Offset>.from(_currentStroke!.points)..add(localPt);
          _currentStroke = BrushStroke(
            points: updatedPoints,
            mode: _currentStroke!.mode,
            radius: _currentStroke!.radius,
          );
        }
      });
    }
  }

  void _onScaleEndBrush(ScaleEndDetails details) {
    if (_isViewportPanningZooming) {
      _isViewportPanningZooming = false;
      _lastViewportPanZoomEndTime = DateTime.now();
    } else {
      _onBrushEnd(DragEndDetails());
    }
  }

  void _onScaleStart(ScaleStartDetails d) {
    if (widget.selectedLayerId == null) return;
    if (widget.selectedLayerId == 'background') {
      _baseScale = widget.bgOption.scale;
      _baseRotation = widget.bgOption.rotation;
      _baseOffset = widget.bgOption.offset;
      _gestureStartOffset = d.focalPoint;
      if (widget.onLayerTransformStart != null) {
        widget.onLayerTransformStart!();
      }
      return;
    }
    final index = widget.layers.indexWhere(
      (l) => l.id == widget.selectedLayerId,
    );
    if (index == -1) return;
    final layer = widget.layers[index];

    _baseScale = layer.scale;
    _baseRotation = layer.rotation;
    _baseOffset = layer.offset;
    _gestureStartOffset = d.focalPoint;

    if (widget.onLayerTransformStart != null) {
      widget.onLayerTransformStart!();
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (widget.selectedLayerId == null) return;
    if (widget.selectedLayerId == 'background') {
      final newScale = (_baseScale * d.scale).clamp(0.1, 10.0);
      final rotDelta = d.rotation * 180 / math.pi;
      final panDelta = d.focalPoint - _gestureStartOffset;

      widget.onLayerTransform(
        'background',
        _baseOffset + panDelta,
        newScale,
        _baseRotation + rotDelta,
      );
      return;
    }
    final index = widget.layers.indexWhere(
      (l) => l.id == widget.selectedLayerId,
    );
    if (index == -1) return;

    final newScale = (_baseScale * d.scale).clamp(0.1, 10.0);
    final rotDelta = d.rotation * 180 / math.pi;
    final panDelta = d.focalPoint - _gestureStartOffset;

    widget.onLayerTransform(
      widget.selectedLayerId!,
      _baseOffset + panDelta,
      newScale,
      _baseRotation + rotDelta,
    );
  }

  Size _canvasSize(BoxConstraints constraints) {
    final maxW = constraints.maxWidth;
    // Subtract 70 to leave room for label and footer instruction text
    final maxH = (constraints.maxHeight - 70).clamp(
      40.0,
      constraints.maxHeight,
    );
    final aspect = widget.passportSize.aspectRatio;

    double w, h;
    if (maxW / maxH > aspect) {
      h = maxH;
      w = h * aspect;
    } else {
      w = maxW;
      h = w / aspect;
    }
    return Size(w.clamp(40, maxW), h.clamp(40, maxH));
  }

  Widget _buildLayerWidget(EditorLayer layer) {
    if (!layer.isVisible) return const SizedBox.shrink();

    Widget content;
    switch (layer.type) {
      case LayerType.photo:
        if (widget.bgRemovedImage != null && widget.originalImage != null) {
          final double b = layer.brightness;
          final double c = layer.contrast + 1.0;
          final double e = layer.exposure + 1.0;

          final double scale = e * c;
          final double translate = 128.0 * (1.0 - c) + b * 255.0;

          final imgWidth = widget.bgRemovedImage!.width.toDouble();
          final imgHeight = widget.bgRemovedImage!.height.toDouble();

          final strokesToPaint = List<BrushStroke>.from(layer.brushStrokes);
          if (_currentStroke != null) {
            strokesToPaint.add(_currentStroke!);
          }

          Widget imageWidget = SizedBox(
            width: imgWidth,
            height: imgHeight,
            child: CustomPaint(
              painter: PhotoBrushPainter(
                originalImage: widget.originalImage!,
                bgRemovedImage: widget.bgRemovedImage!,
                brushStrokes: strokesToPaint,
              ),
            ),
          );

          // Color Hub tinting
          if (layer.colorHub == 'warm') {
            imageWidget = ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.orange.withOpacity(0.15),
                BlendMode.srcATop,
              ),
              child: imageWidget,
            );
          } else if (layer.colorHub == 'cold') {
            imageWidget = ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.blue.withOpacity(0.15),
                BlendMode.srcATop,
              ),
              child: imageWidget,
            );
          }

          // Direct Hue tinting
          if (layer.tintOpacity > 0.0) {
            final tintColor = HSVColor.fromAHSV(
              1.0,
              layer.hue,
              1.0,
              1.0,
            ).toColor();
            imageWidget = ColorFiltered(
              colorFilter: ColorFilter.mode(
                tintColor.withOpacity(layer.tintOpacity),
                BlendMode.srcATop,
              ),
              child: imageWidget,
            );
          }

          final double translateNormalized = translate / 255.0;

          content = ColorFiltered(
            colorFilter: ColorFilter.matrix([
              scale,
              0,
              0,
              translateNormalized,
              0,
              0,
              scale,
              0,
              translateNormalized,
              0,
              0,
              0,
              scale,
              translateNormalized,
              0,
              0,
              0,
              0,
              1,
              0,
            ]),
            child: imageWidget,
          );
        } else if (widget.imageBytes != null) {
          final double b = layer.brightness;
          final double c = layer.contrast + 1.0;
          final double e = layer.exposure + 1.0;

          final double scale = e * c;
          final double translate = 128.0 * (1.0 - c) + b * 255.0;

          Widget imageWidget = Image.memory(
            widget.imageBytes!,
            fit: BoxFit.contain,
          );

          // Color Hub tinting
          if (layer.colorHub == 'warm') {
            imageWidget = ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.orange.withOpacity(0.15),
                BlendMode.srcATop,
              ),
              child: imageWidget,
            );
          } else if (layer.colorHub == 'cold') {
            imageWidget = ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.blue.withOpacity(0.15),
                BlendMode.srcATop,
              ),
              child: imageWidget,
            );
          }

          // Direct Hue tinting
          if (layer.tintOpacity > 0.0) {
            final tintColor = HSVColor.fromAHSV(
              1.0,
              layer.hue,
              1.0,
              1.0,
            ).toColor();
            imageWidget = ColorFiltered(
              colorFilter: ColorFilter.mode(
                tintColor.withOpacity(layer.tintOpacity),
                BlendMode.srcATop,
              ),
              child: imageWidget,
            );
          }

          final double translateNormalized = translate / 255.0;

          content = ColorFiltered(
            colorFilter: ColorFilter.matrix([
              scale,
              0,
              0,
              translateNormalized,
              0,
              0,
              scale,
              0,
              translateNormalized,
              0,
              0,
              0,
              scale,
              translateNormalized,
              0,
              0,
              0,
              0,
              1,
              0,
            ]),
            child: imageWidget,
          );
        } else {
          content = const SizedBox.shrink();
        }
        break;

      case LayerType.text:
        content = Text(
          layer.text ?? '',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: layer.color ?? Colors.white,
            fontSize: layer.fontSize ?? 20.0,
            fontFamily: layer.fontFamily,
            fontWeight: (layer.isBold ?? false)
                ? FontWeight.bold
                : FontWeight.normal,
            fontStyle: (layer.isItalic ?? false)
                ? FontStyle.italic
                : FontStyle.normal,
          ),
        );
        break;

      case LayerType.shape:
        content = CustomPaint(
          size: const Size(100, 100),
          painter: _ShapePainter(
            shapeType: layer.shapeType ?? ShapeType.rectangle,
            fillColor: layer.fillColor ?? Colors.blue,
            strokeColor: layer.strokeColor ?? Colors.transparent,
            strokeWidth: layer.strokeWidth ?? 2.0,
          ),
        );
        break;

      case LayerType.clothing:
        content = layer.clothingAssetPath != null
            ? SizedBox(
                width: 250.0,
                child: Image.asset(
                  layer.clothingAssetPath!,
                  fit: BoxFit.contain,
                ),
              )
            : const SizedBox.shrink();
        break;
    }

    final isSelected = layer.id == widget.selectedLayerId;
    return OverflowBox(
      minWidth: 0.0,
      minHeight: 0.0,
      maxWidth: double.infinity,
      maxHeight: double.infinity,
      child: Transform.translate(
        offset: layer.offset,
        child: Transform.rotate(
          angle: layer.rotation * math.pi / 180,
          child: Transform.scale(
            scale: layer.scale,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                widget.onSelectLayer(layer.id);
              },
              onScaleStart: isSelected ? _onScaleStart : null,
              onScaleUpdate: isSelected ? _onScaleUpdate : null,
              child: Container(
                padding: isSelected && !widget.isExporting
                    ? const EdgeInsets.all(6)
                    : EdgeInsets.zero,
                child: isSelected && !widget.isExporting
                    ? CustomPaint(
                        foregroundPainter: DashedBorderPainter(
                          color: AppTheme.primary,
                          strokeWidth: 1.5,
                          gap: 4.0,
                        ),
                        child: content,
                      )
                    : content,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final canvas = _canvasSize(constraints);
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [

              if (!widget.isExporting) ...[
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Center(child: _SizeLabel(size: widget.passportSize)),
                    Positioned(
                      right: 0,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: widget.onToggleCheckerboard,
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppTheme.card,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: AppTheme.border,
                                width: 0.5,
                              ),
                            ),
                            child: Builder(
                              builder: (context) {
                                final bool isLight;
                                if (widget.bgOption.isSolid) {
                                  isLight = widget.bgOption.solidColor == Colors.white;
                                } else {
                                  isLight = widget.useLightCheckerboard;
                                }
                                return Icon(
                                  isLight ? Icons.wb_sunny_rounded : Icons.nightlight_round,
                                  size: 16,
                                  color: isLight ? Colors.orangeAccent : AppTheme.textSecondary,
                                );
                              }
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              ClipRect(
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: canvas.width,
                  height: canvas.height,
                  child: RepaintBoundary(
                    key: widget.repaintKey,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        widget.isExporting ? 0 : 6,
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: Stack(
                      fit: StackFit.expand,
                      children: [
                         AnimatedContainer(
                          duration: widget.isBrushModeActive && !_isViewportPanningZooming
                              ? const Duration(milliseconds: 250)
                              : Duration.zero,
                          curve: Curves.easeInOut,
                          transformAlignment: Alignment.center,
                          transform: widget.isExporting
                              ? Matrix4.identity()
                              : (Matrix4.identity()
                                  ..translate(_viewportOffset.dx, _viewportOffset.dy)
                                  ..scale(_viewportScale)),
                          child: ClipRect(
                            clipBehavior: Clip.hardEdge,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                // Checkerboard pattern (only if not exporting)
                                if (!widget.isExporting)
                                  Positioned.fill(
                                    child: GestureDetector(
                                      onTap: () => widget.onSelectLayer(
                                        '',
                                      ), // tap bg to deselect
                                      child: ImageUtils.checkerboardWidget(
                                        color1: widget.useLightCheckerboard
                                            ? const Color(0xFFE0E0E0)
                                            : const Color(0xFF2A2A2A),
                                        color2: widget.useLightCheckerboard
                                            ? const Color(0xFFF5F5F5)
                                            : const Color(0xFF3A3A3A),
                                      ),
                                    ),
                                  ),
                                // Background color/gradient/image
                                Positioned.fill(
                                  child: GestureDetector(
                                    onTap: () {
                                      if (widget.bgOption.isImage) {
                                        widget.onSelectLayer('background');
                                      } else {
                                        widget.onSelectLayer('');
                                      }
                                    },
                                    onScaleStart: widget.selectedLayerId == 'background' && widget.bgOption.isImage
                                        ? _onScaleStart
                                        : null,
                                    onScaleUpdate: widget.selectedLayerId == 'background' && widget.bgOption.isImage
                                        ? _onScaleUpdate
                                        : null,
                                    child: ClipRect(
                                      clipBehavior: Clip.hardEdge,
                                      child: Transform.translate(
                                        offset: widget.bgOption.isImage ? widget.bgOption.offset : Offset.zero,
                                        child: Transform.rotate(
                                          angle: widget.bgOption.isImage ? widget.bgOption.rotation * math.pi / 180 : 0.0,
                                          child: Transform.scale(
                                            scale: widget.bgOption.isImage ? widget.bgOption.scale : 1.0,
                                            child: Container(
                                              decoration: widget.selectedLayerId == 'background' && widget.bgOption.isImage && !widget.isExporting
                                                  ? BoxDecoration(
                                                      border: Border.all(
                                                        color: AppTheme.primary,
                                                        width: 1.5,
                                                      ),
                                                    )
                                                  : null,
                                              child: _BackgroundLayer(bgOption: widget.bgOption),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                // Layer elements stacked bottom to top
                                ...widget.layers.map(
                                  (layer) => _buildLayerWidget(layer),
                                ),
                                if (widget.showWatermark)
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: CustomPaint(
                                        painter: WatermarkPainter(text: widget.watermarkText),
                                      ),
                                    ),
                                  ),
                                if (widget.isBrushModeActive && _brushCursorPoint != null)
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: CustomPaint(
                                        painter: BrushCursorPainter(
                                          cursorPoint: _brushCursorPoint,
                                          radius: widget.brushRadius,
                                          mode: widget.brushMode,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (widget.isBrushModeActive && !widget.isExporting)
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onScaleStart: (details) => _onScaleStartBrush(details, canvas),
                              onScaleUpdate: (details) => _onScaleUpdateBrush(details, canvas),
                              onScaleEnd: (details) => _onScaleEndBrush(details),
                              onDoubleTap: () {
                                setState(() {
                                  _viewportScale = 1.0;
                                  _viewportOffset = Offset.zero;
                                  _isViewportPanningZooming = false;
                                });
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
              if (!widget.isExporting) ...[
                const SizedBox(height: 8),
                Text(
                  widget.isBrushModeActive
                      ? 'Draw with 1 finger • Move/Zoom with 2 fingers • Double tap to reset view'
                      : 'Drag to move • Pinch to scale • Twist to rotate',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    color: AppTheme.muted,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SizeLabel extends StatelessWidget {
  final PassportSize size;
  const _SizeLabel({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(size.emoji ?? '📷', style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
          Text(
            '${size.label} · ${size.dimensionLabel}',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              color: AppTheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _BackgroundLayer extends StatelessWidget {
  final BgOption bgOption;
  const _BackgroundLayer({required this.bgOption});

  @override
  Widget build(BuildContext context) {
    switch (bgOption.type) {
      case BgType.transparent:
        return const SizedBox.shrink();
      case BgType.solid:
        return Container(color: bgOption.solidColor);
      case BgType.gradient:
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: bgOption.gradientColors!,
              begin: bgOption.gradientBegin ?? Alignment.topLeft,
              end: bgOption.gradientEnd ?? Alignment.bottomRight,
            ),
          ),
        );
      case BgType.image:
        if (bgOption.imageBytes != null) {
          final double b = bgOption.brightness;
          final double c = bgOption.contrast + 1.0;
          final double e = bgOption.exposure + 1.0;

          final double scale = e * c;
          final double translate = 128.0 * (1.0 - c) + b * 255.0;

          Widget imageWidget = Image.memory(
            bgOption.imageBytes!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          );

          // Color Hub tinting
          if (bgOption.colorHub == 'warm') {
            imageWidget = ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.orange.withOpacity(0.15),
                BlendMode.srcATop,
              ),
              child: imageWidget,
            );
          } else if (bgOption.colorHub == 'cold') {
            imageWidget = ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.blue.withOpacity(0.15),
                BlendMode.srcATop,
              ),
              child: imageWidget,
            );
          }

          // Direct Hue tinting
          if (bgOption.tintOpacity > 0.0) {
            final tintColor = HSVColor.fromAHSV(
              1.0,
              bgOption.hue,
              1.0,
              1.0,
            ).toColor();
            imageWidget = ColorFiltered(
              colorFilter: ColorFilter.mode(
                tintColor.withOpacity(bgOption.tintOpacity),
                BlendMode.srcATop,
              ),
              child: imageWidget,
            );
          }

          final double translateNormalized = translate / 255.0;

          return ColorFiltered(
            colorFilter: ColorFilter.matrix([
              scale,
              0,
              0,
              translateNormalized,
              0,
              0,
              scale,
              0,
              translateNormalized,
              0,
              0,
              0,
              scale,
              translateNormalized,
              0,
              0,
              0,
              0,
              1,
              0,
            ]),
            child: imageWidget,
          );
        }
        return const SizedBox.shrink();
    }
  }
}

class _ShapePainter extends CustomPainter {
  final ShapeType shapeType;
  final Color fillColor;
  final Color strokeColor;
  final double strokeWidth;

  _ShapePainter({
    required this.shapeType,
    required this.fillColor,
    required this.strokeColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    switch (shapeType) {
      case ShapeType.rectangle:
        canvas.drawRect(rect, fillPaint);
        if (strokeColor != Colors.transparent && strokeWidth > 0) {
          canvas.drawRect(rect, strokePaint);
        }
        break;
      case ShapeType.circle:
        final radius = math.min(size.width, size.height) / 2;
        final center = Offset(size.width / 2, size.height / 2);
        canvas.drawCircle(center, radius, fillPaint);
        if (strokeColor != Colors.transparent && strokeWidth > 0) {
          canvas.drawCircle(center, radius, strokePaint);
        }
        break;
      case ShapeType.oval:
        canvas.drawOval(rect, fillPaint);
        if (strokeColor != Colors.transparent && strokeWidth > 0) {
          canvas.drawOval(rect, strokePaint);
        }
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _ShapePainter oldDelegate) {
    return oldDelegate.shapeType != shapeType ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.strokeColor != strokeColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

class DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double gap;

  DashedBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.gap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final dashedPath = _buildDashedPath(path, gap);
    canvas.drawPath(dashedPath, paint);
  }

  Path _buildDashedPath(Path source, double gap) {
    final Path dest = Path();
    for (final PathMetric metric in source.computeMetrics()) {
      double distance = 0.0;
      bool draw = true;
      while (distance < metric.length) {
        final double len = gap;
        if (draw) {
          dest.addPath(
            metric.extractPath(
              distance,
              math.min(distance + len, metric.length),
            ),
            Offset.zero,
          );
        }
        distance += len;
        draw = !draw;
      }
    }
    return dest;
  }

  @override
  bool shouldRepaint(covariant DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.gap != gap;
  }
}

class WatermarkPainter extends CustomPainter {
  final String text;
  const WatermarkPainter({required this.text});

  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // Set styling for the watermark - subtle and transparent but visible with shadow
    final textStyle = TextStyle(
      color: Colors.white.withOpacity(0.35),
      fontSize: 18,
      fontWeight: FontWeight.bold,
      fontFamily: 'Poppins',
      letterSpacing: 1.5,
      shadows: [
        Shadow(
          blurRadius: 1.2,
          color: Colors.black.withOpacity(0.4),
          offset: const Offset(0.8, 0.8),
        ),
      ],
    );

    textPainter.text = TextSpan(text: text, style: textStyle);
    textPainter.layout();

    // Calculate grid spacing dynamically based on text size to prevent overlap
    final double stepX = textPainter.width + 100;
    final double stepY = textPainter.height + 80;

    canvas.save();
    // Rotate canvas diagonally
    canvas.rotate(-0.35); // Approx -20 degrees

    // Cover the canvas with repeated text
    for (double x = -size.width; x < size.width * 2; x += stepX) {
      for (double y = -size.height; y < size.height * 2; y += stepY) {
        textPainter.paint(canvas, Offset(x, y));
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant WatermarkPainter oldDelegate) {
    return oldDelegate.text != text;
  }
}

class BrushCursorPainter extends CustomPainter {
  final Offset? cursorPoint;
  final double radius;
  final BrushMode mode;

  BrushCursorPainter({
    required this.cursorPoint,
    required this.radius,
    required this.mode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (cursorPoint == null) return;

    final drawRadius = radius / 2.0;

    if (mode == BrushMode.erase) {
      // Semi-transparent red filled circle (opacity 0.5)
      final fillPaint = Paint()
        ..color = Colors.red.withOpacity(0.5)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(cursorPoint!, drawRadius, fillPaint);

      final strokePaint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawCircle(cursorPoint!, drawRadius, strokePaint);

      canvas.drawCircle(cursorPoint!, 2.0, Paint()..color = Colors.red..style = PaintingStyle.fill);
    } else {
      // Green outline circle for restore
      final paint = Paint()
        ..color = Colors.green.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      canvas.drawCircle(cursorPoint!, drawRadius, paint);
      canvas.drawCircle(cursorPoint!, 2.0, paint..style = PaintingStyle.fill);
    }
  }

  @override
  bool shouldRepaint(covariant BrushCursorPainter oldDelegate) {
    return oldDelegate.cursorPoint != cursorPoint ||
        oldDelegate.radius != radius ||
        oldDelegate.mode != mode;
  }
}

class PhotoBrushPainter extends CustomPainter {
  final ui.Image originalImage;
  final ui.Image bgRemovedImage;
  final List<BrushStroke> brushStrokes;

  PhotoBrushPainter({
    required this.originalImage,
    required this.bgRemovedImage,
    required this.brushStrokes,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());

    // 1. Draw the background-removed image
    canvas.drawImageRect(
      bgRemovedImage,
      Rect.fromLTWH(0, 0, bgRemovedImage.width.toDouble(), bgRemovedImage.height.toDouble()),
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint(),
    );

    // Group consecutive strokes of the same mode
    List<List<BrushStroke>> groups = [];
    if (brushStrokes.isNotEmpty) {
      List<BrushStroke> currentGroup = [brushStrokes.first];
      for (int i = 1; i < brushStrokes.length; i++) {
        if (brushStrokes[i].mode == currentGroup.last.mode) {
          currentGroup.add(brushStrokes[i]);
        } else {
          groups.add(currentGroup);
          currentGroup = [brushStrokes[i]];
        }
      }
      groups.add(currentGroup);
    }

    // 2. Draw brush strokes in chronological order
    for (final group in groups) {
      final mode = group.first.mode;
      if (mode == BrushMode.erase) {
        for (final stroke in group) {
          final path = Path();
          if (stroke.points.isNotEmpty) {
            final startPoint = stroke.points.first + Offset(size.width / 2, size.height / 2);
            path.moveTo(startPoint.dx, startPoint.dy);
            for (int i = 1; i < stroke.points.length; i++) {
              final pt = stroke.points[i] + Offset(size.width / 2, size.height / 2);
              path.lineTo(pt.dx, pt.dy);
            }
          }
          final erasePaint = Paint()
            ..blendMode = BlendMode.clear
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke.radius
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round;
          canvas.drawPath(path, erasePaint);
        }
      } else {
        canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());
        for (final stroke in group) {
          final path = Path();
          if (stroke.points.isNotEmpty) {
            final startPoint = stroke.points.first + Offset(size.width / 2, size.height / 2);
            path.moveTo(startPoint.dx, startPoint.dy);
            for (int i = 1; i < stroke.points.length; i++) {
              final pt = stroke.points[i] + Offset(size.width / 2, size.height / 2);
              path.lineTo(pt.dx, pt.dy);
            }
          }
          final strokePaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke.radius
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = Colors.white;
          canvas.drawPath(path, strokePaint);
        }
        final srcInPaint = Paint()..blendMode = BlendMode.srcIn;
        canvas.drawImageRect(
          originalImage,
          Rect.fromLTWH(0, 0, originalImage.width.toDouble(), originalImage.height.toDouble()),
          Rect.fromLTWH(0, 0, size.width, size.height),
          srcInPaint,
        );
        canvas.restore();
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant PhotoBrushPainter oldDelegate) {
    return oldDelegate.originalImage != originalImage ||
        oldDelegate.bgRemovedImage != bgRemovedImage ||
        oldDelegate.brushStrokes != brushStrokes;
  }
}
