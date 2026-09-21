/// Custom super-resolution service using [flutter_onnxruntime] directly.
///
/// Both this service and `image_background_remover` share the same
/// `libonnxruntime.so` via `flutter_onnxruntime`, eliminating the JNI
/// namespace conflict that caused `MissingPluginException` crashes.
///
/// Tiling strategy (avoids ORT_INVALID_ARGUMENT):
///   • Every tile fed to the model is EXACTLY [tileSize]×[tileSize], where
///     [tileSize] is auto-detected from the model's input shape if the
///     model declares a fixed (non-dynamic) spatial dimension. This is the
///     #1 cause of ORT_INVALID_ARGUMENT ("Got invalid dimensions") — feeding
///     a 128×128 tile to a model exported for, say, 256×256.
///   • Input dtype (float32 vs uint8) is also auto-detected from the model
///     to avoid ORT_INVALID_INPUT ("Unexpected input data type").
///   • Boundary tiles are zero-padded; the model output is then cropped.
///   • Adjacent tiles overlap by [overlap] pixels and are feather-blended.
///
/// Performance / GPU notes:
///   • CUDA and WEB_GPU providers are dropped on mobile — they are
///     irrelevant on Android/iOS and some ORT builds throw during session
///     creation just from probing them, which can itself surface as
///     ORT_INVALID_ARGUMENT-style errors unrelated to the actual tensors.
///   • A single warm-up inference is run once after session creation to
///     decide hardware-accelerated (NNAPI/CoreML) vs CPU execution, instead
///     of re-creating the session on every failing tile.
///   • intraOpNumThreads scales with the device's core count.
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/services.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

/// Callback for progress updates: (0.0–1.0, human-readable message).
typedef ProgressCallback = void Function(double progress, String message);

/// Tensor element type the model expects for its input.
enum _InputDType { float32, uint8 }

class SuperResolutionService {
  // ── Configuration ────────────────────────────────────────────────────────

  /// Default/fallback side-length of each input tile fed to the model
  /// (pixels). Overridden at session-load time if the model declares a
  /// fixed spatial input dimension.
  final int tileSize;

  /// Overlap strip on each side of a tile (pixels) used for feather blending.
  final int overlap;

  /// Input is downscaled to at most this dimension before tiling.
  final int maxInputSize;

  // ── Private state ─────────────────────────────────────────────────────────

  OrtSession? _session;
  String? _modelPath;
  String? _assetPath;

  /// Tile size actually used for inference. Defaults to [tileSize] but is
  /// overridden by [_detectModelSpec] if the model's input shape declares a
  /// fixed (non-dynamic) height/width.
  int _effectiveTileSize = 0;

  /// Input element type the model expects. Defaults to float32.
  _InputDType _inputDType = _InputDType.float32;

  /// Number of intra-op threads to use, derived from device core count.
  late final int _threads;

  // ── Constructor ───────────────────────────────────────────────────────────

  SuperResolutionService({
    this.tileSize = 128,
    this.overlap = 8,
    this.maxInputSize = 512,
  }) {
    _effectiveTileSize = tileSize;
    final cores = Platform.numberOfProcessors;
    _threads = math.max(1, math.min(8, cores));
  }

  // ── Session lifecycle ─────────────────────────────────────────────────────

  /// Providers relevant to this platform. CUDA/WEB_GPU are intentionally
  /// excluded on mobile: they don't exist on Android/iOS hardware and
  /// probing them can throw during session creation on some ORT builds.
  List<OrtProvider> _platformProviders() {
    if (kIsWeb) {
      return [OrtProvider.WEB_GPU, OrtProvider.CPU];
    }
    return [OrtProvider.NNAPI, OrtProvider.CORE_ML, OrtProvider.CPU];
  }

  Future<void> initializeModelFromFile(String filePath) async {
    await _closeSession();
    _modelPath = filePath;
    _assetPath = null;

    final opts = OrtSessionOptions(
      providers: _platformProviders(),
      intraOpNumThreads: _threads,
    );
    _session = await OnnxRuntime().createSession(filePath, options: opts);

    debugPrint(
      '[SR] Loaded model. inputs=${_session!.inputNames} outputs=${_session!.outputNames}',
    );

    await _detectModelSpec(_session!);
    await _warmUpAndPickProviders(filePath, isAsset: false);
  }

  Future<void> initializeModel(String assetPath) async {
    await _closeSession();
    _assetPath = assetPath;
    _modelPath = null;

    final opts = OrtSessionOptions(
      providers: [OrtProvider.CPU],
      intraOpNumThreads: math.max(1, math.min(8, Platform.numberOfProcessors)),
    );
    _session = await OnnxRuntime().createSessionFromAsset(
      assetPath,
      options: opts,
    );

    debugPrint(
      '[SR] Loaded asset model. inputs=${_session!.inputNames} outputs=${_session!.outputNames}',
    );
    _effectiveTileSize = 128;
    _inputDType = _InputDType.float32;
  }

  /// Inspects the model's declared input shape/dtype to:
  ///   • set [_effectiveTileSize] if the model has a fixed spatial dim
  ///     (fixes ORT_INVALID_ARGUMENT from wrong tile size), and
  ///   • set [_inputDType] (fixes ORT_INVALID_INPUT from wrong tensor dtype).
  ///
  /// Falls back silently to defaults (configured [tileSize], float32) if the
  /// installed flutter_onnxruntime version doesn't expose input introspection
  /// — the rest of the pipeline still works, just without auto-correction.
  Future<void> _detectModelSpec(OrtSession session) async {
    try {
      final dynamic infos = await (session as dynamic).getInputInfo();
      if (infos is List && infos.isNotEmpty) {
        final dynamic first = infos.first;
        final dynamic shape = first.shape;
        final dynamic type = first.type;

        if (shape is List && shape.length == 4) {
          // Try both NCHW ([N, C, H, W]) and NHWC ([N, H, W, C]) layouts.
          // A "fixed" dim is a positive int (dynamic dims are usually -1
          // or 0 in the reported shape).
          final dynamic h = shape[2];
          final dynamic w = shape[3];
          if (h is int && w is int && h > 0 && w > 0 && h == w) {
            _effectiveTileSize = h;
            debugPrint(
              '[SR] Detected fixed model tile size: $_effectiveTileSize',
            );
          }
        }

        if (type != null) {
          final typeStr = type.toString().toLowerCase();
          if (typeStr.contains('uint8') || typeStr.contains('uint_8')) {
            _inputDType = _InputDType.uint8;
            debugPrint('[SR] Detected model input dtype: uint8');
          } else {
            _inputDType = _InputDType.float32;
            debugPrint('[SR] Detected model input dtype: float32');
          }
        }
      }
    } catch (e) {
      debugPrint('[SR] Input introspection unavailable, using defaults: $e');
    }
  }

  /// Runs a single dummy inference using the hardware-accelerated providers.
  /// If it throws, the session is recreated once with CPU-only providers and
  /// all subsequent tiles use CPU — avoiding per-tile session recreation,
  /// which was the previous (slow) fallback strategy.
  Future<void> _warmUpAndPickProviders(
    String path, {
    required bool isAsset,
  }) async {
    if (_session == null) return;

    final inputName = _session!.inputNames.isNotEmpty
        ? _session!.inputNames.first
        : 'image';

    try {
      final dummy = _zeroTile(_effectiveTileSize, _inputDType);
      final shape = [1, 3, _effectiveTileSize, _effectiveTileSize];
      final inputTensor = await _makeInputTensor(dummy, shape);

      final outputs = await _session!.run({inputName: inputTensor});
      for (final v in outputs.values) {
        await v?.dispose();
      }
      await inputTensor.dispose();
      debugPrint('[SR] Warm-up succeeded with hardware providers.');
    } catch (e) {
      debugPrint(
        '[SR] Warm-up failed on hardware providers ($e); falling back to CPU.',
      );
      try {
        await _session!.close();
      } catch (_) {}

      final cpuOpts = OrtSessionOptions(
        providers: [OrtProvider.CPU],
        intraOpNumThreads: _threads,
      );
      _session = isAsset
          ? await OnnxRuntime().createSessionFromAsset(path, options: cpuOpts)
          : await OnnxRuntime().createSession(path, options: cpuOpts);
    }
  }

  /// Builds an all-zero tile in the dtype the model expects, used only for
  /// the warm-up inference.
  dynamic _zeroTile(int size, _InputDType dtype) {
    final n = 3 * size * size;
    return dtype == _InputDType.uint8 ? Uint8List(n) : Float32List(n);
  }

  /// Creates an [OrtValue] from raw tile data, respecting [_inputDType].
  Future<OrtValue> _makeInputTensor(dynamic data, List<int> shape) async {
    if (_inputDType == _InputDType.uint8) {
      final Uint8List u8 = data is Uint8List
          ? data
          : Uint8List.fromList((data as List).cast<int>());
      return OrtValue.fromList(u8, shape);
    }
    final Float32List f32 = data is Float32List
        ? data
        : Float32List.fromList((data as List).cast<double>());
    return OrtValue.fromList(f32, shape);
  }

  // ── Public API ────────────────────────────────────────────────────────────

  Future<ui.Image?> upscaleImage(
    ui.Image sourceImage,
    int scale, {
    double enhanceIntensity =
        0.60, // 60% AI details, 40% original details to prevent over-enhancing/plastic artifacts
    ProgressCallback? onProgress,
  }) async {
    if (_modelPath == null && _assetPath == null) {
      throw StateError(
        'Model not initialised. Call initializeModelFromFile first.',
      );
    }

    onProgress?.call(0.0, 'Reading source image…');

    // 1. Decode to raw RGBA on main thread (Flutter Engine API)
    final byteData = await sourceImage.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (byteData == null) throw StateError('Failed to decode source image.');

    int srcW = sourceImage.width;
    int srcH = sourceImage.height;
    final originalRawRgba = byteData.buffer.asUint8List();
    Uint8List rawRgba = originalRawRgba;

    // 2. Optional downscale on main thread (so tiling stays reasonable)
    if (srcW > maxInputSize || srcH > maxInputSize) {
      final factor = math.min(maxInputSize / srcW, maxInputSize / srcH);
      final newW = (srcW * factor).round();
      final newH = (srcH * factor).round();
      rawRgba = await _resizeRgba(rawRgba, srcW, srcH, newW, newH);
      srcW = newW;
      srcH = newH;
      onProgress?.call(0.05, 'Pre-scaled to $srcW×$srcH…');
    }

    // Close session on main isolate to free RAM before spawning background isolate
    await _closeSession();

    // 3. Spawn background isolate to run tiling, ONNX inference, and blending
    final receivePort = ReceivePort();
    final completer = Completer<Map<String, dynamic>>();

    receivePort.listen((message) {
      if (message is Map<String, dynamic>) {
        final status = message['status'];
        if (status == 'progress') {
          final p = message['progress'] as double;
          final msg = message['message'] as String;
          onProgress?.call(p, msg);
        } else if (status == 'success') {
          completer.complete(message);
          receivePort.close();
        } else if (status == 'error') {
          completer.completeError(StateError(message['error'] as String));
          receivePort.close();
        }
      }
    });

    final String path = _modelPath ?? _assetPath!;
    final bool isAsset = _assetPath != null;

    final rootToken = RootIsolateToken.instance!;
    await Isolate.spawn(_isolateUpscaleEntry, [
      receivePort.sendPort,
      path,
      isAsset,
      rawRgba,
      srcW,
      srcH,
      _effectiveTileSize,
      overlap,
      _inputDType == _InputDType.uint8,
      _threads,
      _providerNamesOrDefault(null),
      rootToken,
    ]);

    final result = await completer.future;
    final rgbaOut = result['rgbaOut'] as Uint8List;
    final finalOutW = result['width'] as int;
    final finalOutH = result['height'] as int;

    // 4. Resize back to caller's requested scale × original on main thread
    final targetW = sourceImage.width * scale;
    final targetH = sourceImage.height * scale;
    Uint8List finalRgba = rgbaOut;
    int fw = finalOutW, fh = finalOutH;
    if (fw != targetW || fh != targetH) {
      onProgress?.call(0.97, 'Rescaling to final size…');
      finalRgba = await _resizeRgba(
        rgbaOut,
        finalOutW,
        finalOutH,
        targetW,
        targetH,
      );
      fw = targetW;
      fh = targetH;
    }

    // 5. Blend AI-enhanced details with the original image to prevent over-enhancing/plastic artifacts
    if (enhanceIntensity < 1.0) {
      onProgress?.call(0.99, 'Blending original details…');
      final resizedOrigRgba = await _resizeRgba(
        originalRawRgba,
        sourceImage.width,
        sourceImage.height,
        targetW,
        targetH,
      );
      final blendedRgba = Uint8List(fw * fh * 4);
      final double w1 = enhanceIntensity;
      final double w2 = 1.0 - enhanceIntensity;
      final int len = fw * fh * 4;
      for (int i = 0; i < len; i += 4) {
        final r = (finalRgba[i] * w1 + resizedOrigRgba[i] * w2).toInt();
        final g = (finalRgba[i + 1] * w1 + resizedOrigRgba[i + 1] * w2).toInt();
        final b = (finalRgba[i + 2] * w1 + resizedOrigRgba[i + 2] * w2).toInt();

        blendedRgba[i] = r < 0 ? 0 : (r > 255 ? 255 : r);
        blendedRgba[i + 1] = g < 0 ? 0 : (g > 255 ? 255 : g);
        blendedRgba[i + 2] = b < 0 ? 0 : (b > 255 ? 255 : b);
        blendedRgba[i + 3] = 255;
      }
      finalRgba = blendedRgba;
    }

    onProgress?.call(1.0, 'Done!');
    return _rgbaToUiImage(finalRgba, fw, fh);
  }

  /// Best-effort extraction of provider names from a closed session; falls
  /// back to platform defaults if unavailable. Used so the isolate opens its
  /// session with the same providers that were warm-up-tested on the main
  /// isolate, avoiding a second cold-start fallback.
  List<String> _providerNamesOrDefault(dynamic providers) {
    try {
      if (providers is List) {
        return providers.map((p) => p.toString()).toList();
      }
    } catch (_) {}
    return kIsWeb ? ['WEB_GPU', 'CPU'] : ['NNAPI', 'CORE_ML', 'CPU'];
  }

  /// Entry point for the background isolate to execute ONNX super-resolution.
  static void _isolateUpscaleEntry(List<dynamic> args) async {
    final SendPort sendPort = args[0];
    final String modelPath = args[1];
    final bool isAsset = args[2];
    final Uint8List rawRgba = args[3];
    final int srcW = args[4];
    final int srcH = args[5];
    final int tileSize = args[6];
    final int overlap = args[7];
    final bool useUint8Input = args[8];
    final int threads = args[9];
    final List<String> providerNames = (args[10] as List).cast<String>();
    final RootIsolateToken rootToken = args[11];
    BackgroundIsolateBinaryMessenger.ensureInitialized(rootToken);

    OrtSession? session;

    try {
      final providers = _resolveProviders(providerNames);

      try {
        final opts = OrtSessionOptions(
          providers: [OrtProvider.CPU],
          intraOpNumThreads: threads,
        );
        session = isAsset
            ? await OnnxRuntime().createSessionFromAsset(
                modelPath,
                options: opts,
              )
            : await OnnxRuntime().createSession(modelPath, options: opts);
      } catch (e) {
        // Hardware providers failed at session-creation time in the isolate
        // (different process/thread than the main-isolate warm-up) — fall
        // back to CPU once.
        debugPrint(
          '[SR] Isolate session creation failed on $providers ($e); using CPU.',
        );
        final opts = OrtSessionOptions(
          providers: [OrtProvider.CPU],
          intraOpNumThreads: threads,
        );
        session = isAsset
            ? await OnnxRuntime().createSessionFromAsset(
                modelPath,
                options: opts,
              )
            : await OnnxRuntime().createSession(modelPath, options: opts);
      }

      final String inputName = session.inputNames.isNotEmpty
          ? session.inputNames.first
          : 'image';
      final String outputName = session.outputNames.isNotEmpty
          ? session.outputNames.first
          : 'upscaled_image';

      final step = tileSize - overlap * 2;
      if (step <= 0) {
        throw ArgumentError(
          'overlap ($overlap) is too large for tileSize ($tileSize).',
        );
      }

      int nX = 0, nY = 0;
      for (int x = 0; x < srcW; x += step) {
        nX++;
      }
      for (int y = 0; y < srcH; y += step) {
        nY++;
      }
      final totalTiles = nX * nY;
      int doneTiles = 0;

      int? outW, outH;
      int modelScale = 4;
      Float32List? accumR, accumG, accumB;
      Float32List? wt;
      Float32List? precomputedWeights;

      for (int ty = 0; ty < srcH; ty += step) {
        for (int tx = 0; tx < srcW; tx += step) {
          final srcX0 = tx - overlap;
          final srcY0 = ty - overlap;

          final shape = [1, 3, tileSize, tileSize];
          final inputTensor = useUint8Input
              ? await OrtValue.fromList(
                  _extractPaddedTileCHWIsolateUint8(
                    rawRgba,
                    srcW,
                    srcH,
                    srcX0,
                    srcY0,
                    tileSize,
                    tileSize,
                  ),
                  shape,
                )
              : await OrtValue.fromList(
                  _extractPaddedTileCHWIsolateFloat32(
                    rawRgba,
                    srcW,
                    srcH,
                    srcX0,
                    srcY0,
                    tileSize,
                    tileSize,
                  ),
                  shape,
                );

          final outputs = await session.run({inputName: inputTensor});
          await inputTensor.dispose();

          final outTensor = outputs[outputName];
          if (outTensor == null) {
            for (final v in outputs.values) {
              await v?.dispose();
            }
            throw StateError('Model returned no output tensor.');
          }

          if (outW == null) {
            final outShape = outTensor.shape;
            if (outShape.length >= 4) {
              modelScale = outShape[2] ~/ tileSize;
              if (modelScale < 1) {
                modelScale = 4;
              }
            }
            outW = srcW * modelScale;
            outH = srcH * modelScale;
            accumR = Float32List(outH * outW);
            accumG = Float32List(outH * outW);
            accumB = Float32List(outH * outW);
            wt = Float32List(outH * outW);
          }

          final rawFlatList = await outTensor.asFlattenedList();
          await outTensor.dispose();
          for (final v in outputs.values) {
            if (!identical(v, outTensor)) {
              await v?.dispose();
            }
          }

          final Float32List flatList;
          if (rawFlatList is Float32List) {
            flatList = rawFlatList;
          } else if (useUint8Input && rawFlatList is Uint8List) {
            // Some models output uint8 too — normalize to 0-1 for the
            // shared accumulation/blend code below.
            flatList = Float32List(rawFlatList.length);
            for (int i = 0; i < rawFlatList.length; i++) {
              flatList[i] = rawFlatList[i] / 255.0;
            }
          } else {
            flatList = Float32List.fromList(
              (rawFlatList as List).cast<double>(),
            );
          }

          final outTileH = tileSize * modelScale;
          final outTileW = tileSize * modelScale;
          final planeSize = outTileH * outTileW;

          final dstX0 = srcX0 * modelScale;
          final dstY0 = srcY0 * modelScale;
          final feather = overlap * modelScale;

          // 1. Precompute weights matrix once per scale/size
          if (precomputedWeights == null) {
            precomputedWeights = Float32List(outTileH * outTileW);
            for (int r = 0; r < outTileH; r++) {
              double wy = 1.0;
              if (r < feather) {
                wy = (r + 1) / (feather + 1.0);
              } else if (r >= outTileH - feather) {
                wy = (outTileH - r) / (feather + 1.0);
              }
              final int rOutTileW = r * outTileW;
              for (int c = 0; c < outTileW; c++) {
                double wx = 1.0;
                if (c < feather) {
                  wx = (c + 1) / (feather + 1.0);
                } else if (c >= outTileW - feather) {
                  wx = (outTileW - c) / (feather + 1.0);
                }
                precomputedWeights[rOutTileW + c] = wx * wy;
              }
            }
          }

          // 2. Feather-blend into accumulator
          final int rMin = math.max(0, -dstY0);
          final int rMax = math.min(outTileH, outH! - dstY0);
          final int cMin = math.max(0, -dstX0);
          final int cMax = math.min(outTileW, outW - dstX0);

          for (int r = rMin; r < rMax; r++) {
            final gy = dstY0 + r;
            final int rOutTileW = r * outTileW;
            final int gyOutW = gy * outW;

            for (int c = cMin; c < cMax; c++) {
              final gx = dstX0 + c;
              final int li = rOutTileW + c;
              final double w = precomputedWeights[li];
              final int gi = gyOutW + gx;

              accumR![gi] += flatList[li].clamp(0.0, 1.0) * w;
              accumG![gi] += flatList[planeSize + li].clamp(0.0, 1.0) * w;
              accumB![gi] += flatList[planeSize * 2 + li].clamp(0.0, 1.0) * w;
              wt![gi] += w;
            }
          }

          doneTiles++;
          sendPort.send({
            'status': 'progress',
            'progress': 0.05 + 0.88 * (doneTiles / totalTiles),
            'message': 'Wait a While....',
          });
        }
      }

      sendPort.send({
        'status': 'progress',
        'progress': 0.95,
        'message': 'Stitching output…',
      });

      final finalOutW = outW ?? srcW * modelScale;
      final finalOutH = outH ?? srcH * modelScale;

      final rgbaOut = Uint8List(finalOutW * finalOutH * 4);

      final int len = finalOutW * finalOutH;
      for (int i = 0; i < len; i++) {
        final double w = (wt != null && wt[i] > 0.0) ? wt[i] : 1.0;
        final double invW = 255.0 / w;
        final int idx = i * 4;

        final r = (accumR![i] * invW).toInt();
        final g = (accumG![i] * invW).toInt();
        final b = (accumB![i] * invW).toInt();

        rgbaOut[idx] = r < 0 ? 0 : (r > 255 ? 255 : r);
        rgbaOut[idx + 1] = g < 0 ? 0 : (g > 255 ? 255 : g);
        rgbaOut[idx + 2] = b < 0 ? 0 : (b > 255 ? 255 : b);
        rgbaOut[idx + 3] = 255;
      }

      sendPort.send({
        'status': 'success',
        'rgbaOut': rgbaOut,
        'width': finalOutW,
        'height': finalOutH,
      });
    } catch (e, stackTrace) {
      sendPort.send({
        'status': 'error',
        'error': 'Upscaling failed: $e\n$stackTrace',
      });
    } finally {
      if (session != null) {
        try {
          await session.close();
        } catch (_) {}
      }
    }
  }

  /// Maps provider name strings back to [OrtProvider] enum values, dropping
  /// any that aren't relevant in the isolate's context (CUDA/WEB_GPU are
  /// never used on mobile isolates).
  static List<OrtProvider> _resolveProviders(List<String> names) {
    final result = <OrtProvider>[];
    for (final n in names) {
      final upper = n.toUpperCase();
      if (upper.contains('NNAPI')) {
        result.add(OrtProvider.NNAPI);
      } else if (upper.contains('CORE_ML') || upper.contains('COREML')) {
        result.add(OrtProvider.CORE_ML);
      } else if (upper.contains('CPU')) {
        result.add(OrtProvider.CPU);
      }
      // CUDA / WEB_GPU intentionally ignored on mobile isolates.
    }
    if (!result.contains(OrtProvider.CPU)) {
      result.add(OrtProvider.CPU);
    }
    return result;
  }

  /// Extract a [tw]×[th] window starting at ([srcX0],[srcY0]) from [rawRgba],
  /// zero-padding any out-of-bounds pixels. Returns CHW Float32 (0-1).
  static Float32List _extractPaddedTileCHWIsolateFloat32(
    Uint8List rawRgba,
    int imgW,
    int imgH,
    int srcX0,
    int srcY0,
    int tw,
    int th,
  ) {
    final n = tw * th;
    final out = Float32List(3 * n);
    const double inv255 = 1.0 / 255.0;

    final int rMin = math.max(0, -srcY0);
    final int rMax = math.min(th, imgH - srcY0);
    final int cMin = math.max(0, -srcX0);
    final int cMax = math.min(tw, imgW - srcX0);

    for (int row = rMin; row < rMax; row++) {
      final sy = srcY0 + row;
      final int rowTw = row * tw;
      final int syImgW = sy * imgW;

      for (int col = cMin; col < cMax; col++) {
        final sx = srcX0 + col;
        final srcPx = (syImgW + sx) * 4;
        final dstPx = rowTw + col;

        out[dstPx] = rawRgba[srcPx] * inv255;
        out[n + dstPx] = rawRgba[srcPx + 1] * inv255;
        out[2 * n + dstPx] = rawRgba[srcPx + 2] * inv255;
      }
    }
    return out;
  }

  /// Same as [_extractPaddedTileCHWIsolateFloat32] but returns raw 0-255
  /// uint8 values, for models with a uint8 input tensor.
  static Uint8List _extractPaddedTileCHWIsolateUint8(
    Uint8List rawRgba,
    int imgW,
    int imgH,
    int srcX0,
    int srcY0,
    int tw,
    int th,
  ) {
    final n = tw * th;
    final out = Uint8List(3 * n);

    final int rMin = math.max(0, -srcY0);
    final int rMax = math.min(th, imgH - srcY0);
    final int cMin = math.max(0, -srcX0);
    final int cMax = math.min(tw, imgW - srcX0);

    for (int row = rMin; row < rMax; row++) {
      final sy = srcY0 + row;
      final int rowTw = row * tw;
      final int syImgW = sy * imgW;

      for (int col = cMin; col < cMax; col++) {
        final sx = srcX0 + col;
        final srcPx = (syImgW + sx) * 4;
        final dstPx = rowTw + col;

        out[dstPx] = rawRgba[srcPx];
        out[n + dstPx] = rawRgba[srcPx + 1];
        out[2 * n + dstPx] = rawRgba[srcPx + 2];
      }
    }
    return out;
  }

  void dispose() {
    _closeSession();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<void> _closeSession() async {
    if (_session != null) {
      try {
        await _session!.close();
      } catch (_) {}
      _session = null;
    }
  }

  Future<Uint8List> _resizeRgba(
    Uint8List src,
    int srcW,
    int srcH,
    int dstW,
    int dstH,
  ) async {
    final c1 = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      src,
      srcW,
      srcH,
      ui.PixelFormat.rgba8888,
      c1.complete,
    );
    final srcImg = await c1.future;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      srcImg,
      ui.Rect.fromLTWH(0, 0, srcW.toDouble(), srcH.toDouble()),
      ui.Rect.fromLTWH(0, 0, dstW.toDouble(), dstH.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    srcImg.dispose();

    final picture = recorder.endRecording();
    final dstImg = await picture.toImage(dstW, dstH);
    picture.dispose();

    final bd = await dstImg.toByteData(format: ui.ImageByteFormat.rawRgba);
    dstImg.dispose();
    return bd!.buffer.asUint8List();
  }

  Future<ui.Image> _rgbaToUiImage(Uint8List rgba, int w, int h) {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
  }
}
