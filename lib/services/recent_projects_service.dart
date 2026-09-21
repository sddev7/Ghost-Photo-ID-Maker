import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../models/passport_size.dart';
import '../models/bg_option.dart';
import '../models/editor_layer.dart';
import '../models/recent_project.dart';

class RecentProjectsService {
  RecentProjectsService._();
  static final RecentProjectsService instance = RecentProjectsService._();

  Future<String> _getDirPath() async {
    final docDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${docDir.path}/recent_projects');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  static String _alignmentToString(AlignmentGeometry? alignment) {
    if (alignment == null) return 'topLeft';
    if (alignment is Alignment) {
      return '${alignment.x},${alignment.y}';
    }
    return 'topLeft';
  }

  static AlignmentGeometry _stringToAlignment(String str) {
    final parts = str.split(',');
    if (parts.length == 2) {
      final x = double.tryParse(parts[0]) ?? 0.0;
      final y = double.tryParse(parts[1]) ?? 0.0;
      return Alignment(x, y);
    }
    return Alignment.topLeft;
  }

  Future<void> saveProject(RecentProject project) async {
    try {
      final dirPath = await _getDirPath();
      
      // Save image bytes
      final imgFile = File('$dirPath/image_${project.id}.png');
      await imgFile.writeAsBytes(project.bgRemovedBytes);

      // Save original image bytes
      final origFile = File('$dirPath/original_${project.id}.png');
      await origFile.writeAsBytes(project.originalImageBytes);

      // Save thumbnail bytes if present
      if (project.thumbnailBytes != null) {
        final thumbFile = File('$dirPath/thumbnail_${project.id}.png');
        await thumbFile.writeAsBytes(project.thumbnailBytes!);
      }

      // Save background image bytes if present
      if (project.bgOption.type == BgType.image && project.bgOption.imageBytes != null) {
        final bgFile = File('$dirPath/bg_${project.id}.png');
        await bgFile.writeAsBytes(project.bgOption.imageBytes!);
      }

      // Save JSON metadata
      final metadataFile = File('$dirPath/metadata_${project.id}.json');
      final metadata = {
        'id': project.id,
        'lastSaved': project.lastSaved.toIso8601String(),
        'selectedSize': {
          'id': project.selectedSize.id,
          'label': project.selectedSize.label,
          'country': project.selectedSize.country,
          'width': project.selectedSize.width,
          'height': project.selectedSize.height,
          'unit': project.selectedSize.unit.name,
          'emoji': project.selectedSize.emoji,
        },
        'bgOption': {
          'type': project.bgOption.type.name,
          'solidColor': project.bgOption.solidColor?.value,
          'gradientColors': project.bgOption.gradientColors?.map((c) => c.value).toList(),
          'gradientBegin': _alignmentToString(project.bgOption.gradientBegin),
          'gradientEnd': _alignmentToString(project.bgOption.gradientEnd),
          'brightness': project.bgOption.brightness,
          'contrast': project.bgOption.contrast,
          'exposure': project.bgOption.exposure,
          'colorHub': project.bgOption.colorHub,
          'hue': project.bgOption.hue,
          'tintOpacity': project.bgOption.tintOpacity,
          'offsetX': project.bgOption.offset.dx,
          'offsetY': project.bgOption.offset.dy,
          'scale': project.bgOption.scale,
          'rotation': project.bgOption.rotation,
        },
        'layers': project.layers.map((l) => {
          'id': l.id,
          'type': l.type.name,
          'name': l.name,
          'isVisible': l.isVisible,
          'offsetX': l.offset.dx,
          'offsetY': l.offset.dy,
          'scale': l.scale,
          'rotation': l.rotation,
          'text': l.text,
          'color': l.color?.value,
          'fontSize': l.fontSize,
          'fontFamily': l.fontFamily,
          'isBold': l.isBold,
          'isItalic': l.isItalic,
          'shapeType': l.shapeType?.name,
          'fillColor': l.fillColor?.value,
          'strokeColor': l.strokeColor?.value,
          'strokeWidth': l.strokeWidth,
          'clothingAssetPath': l.clothingAssetPath,
          'brightness': l.brightness,
          'contrast': l.contrast,
          'exposure': l.exposure,
          'colorHub': l.colorHub,
          'hue': l.hue,
          'tintOpacity': l.tintOpacity,
          'brushStrokes': l.brushStrokes.map((bs) => bs.toJson()).toList(),
        }).toList(),
      };
      
      await metadataFile.writeAsString(jsonEncode(metadata));
    } catch (e) {
      debugPrint('Error saving project: $e');
    }
  }

  Future<List<RecentProject>> getRecentProjects() async {
    try {
      final dirPath = await _getDirPath();
      final dir = Directory(dirPath);
      if (!await dir.exists()) return [];

      final files = dir.listSync();
      final List<RecentProject> projects = [];
      
      for (final file in files) {
        if (file is File && file.path.endsWith('.json')) {
          try {
            final content = await file.readAsString();
            final metadata = jsonDecode(content);
            final id = metadata['id'];
            
            final imgFile = File('$dirPath/image_$id.png');
            final origFile = File('$dirPath/original_$id.png');
            final thumbFile = File('$dirPath/thumbnail_$id.png');
            if (!await imgFile.exists() || !await origFile.exists()) continue;
            final imgBytes = await imgFile.readAsBytes();
            final origBytes = await origFile.readAsBytes();

            Uint8List? thumbBytes;
            if (await thumbFile.exists()) {
              thumbBytes = await thumbFile.readAsBytes();
            }
            
            // Parse size
            final sizeMap = metadata['selectedSize'];
            final selectedSize = PassportSize(
              id: sizeMap['id'],
              label: sizeMap['label'],
              country: sizeMap['country'],
              width: (sizeMap['width'] as num).toDouble(),
              height: (sizeMap['height'] as num).toDouble(),
              unit: SizeUnit.values.firstWhere((e) => e.name == sizeMap['unit']),
              emoji: sizeMap['emoji'],
            );

            // Parse bgOption
            final bgMap = metadata['bgOption'];
            final bgType = BgType.values.firstWhere((e) => e.name == bgMap['type']);
            BgOption bgOption;
            if (bgType == BgType.transparent) {
              bgOption = BgOption.transparent();
            } else if (bgType == BgType.solid) {
              bgOption = BgOption.solid(Color(bgMap['solidColor']));
            } else if (bgType == BgType.gradient) {
              final colors = (bgMap['gradientColors'] as List).map((c) => Color(c as int)).toList();
              bgOption = BgOption.gradient(
                colors: colors,
                begin: _stringToAlignment(bgMap['gradientBegin']),
                end: _stringToAlignment(bgMap['gradientEnd']),
              );
            } else if (bgType == BgType.image) {
              final bgImgFile = File('$dirPath/bg_$id.png');
              Uint8List? bgBytes;
              if (await bgImgFile.exists()) {
                bgBytes = await bgImgFile.readAsBytes();
              }
              bgOption = BgOption.image(
                bgBytes ?? Uint8List(0),
                brightness: (bgMap['brightness'] as num?)?.toDouble() ?? 0.0,
                contrast: (bgMap['contrast'] as num?)?.toDouble() ?? 0.0,
                exposure: (bgMap['exposure'] as num?)?.toDouble() ?? 0.0,
                colorHub: bgMap['colorHub'] as String? ?? 'normal',
                hue: (bgMap['hue'] as num?)?.toDouble() ?? 0.0,
                tintOpacity: (bgMap['tintOpacity'] as num?)?.toDouble() ?? 0.0,
              );
            } else {
              bgOption = BgOption.transparent();
            }

            bgOption = bgOption.copyWith(
              offset: Offset(
                (bgMap['offsetX'] as num?)?.toDouble() ?? 0.0,
                (bgMap['offsetY'] as num?)?.toDouble() ?? 0.0,
              ),
              scale: (bgMap['scale'] as num?)?.toDouble() ?? 1.0,
              rotation: (bgMap['rotation'] as num?)?.toDouble() ?? 0.0,
            );

            // Parse layers
            final layersList = metadata['layers'] as List;
            final layers = layersList.map((l) => EditorLayer(
              id: l['id'],
              type: LayerType.values.firstWhere((e) => e.name == l['type']),
              name: l['name'],
              isVisible: l['isVisible'] ?? true,
              offset: Offset((l['offsetX'] as num).toDouble(), (l['offsetY'] as num).toDouble()),
              scale: (l['scale'] as num).toDouble(),
              rotation: (l['rotation'] as num).toDouble(),
              text: l['text'],
              color: l['color'] != null ? Color(l['color']) : null,
              fontSize: (l['fontSize'] as num?)?.toDouble(),
              fontFamily: l['fontFamily'],
              isBold: l['isBold'],
              isItalic: l['isItalic'],
              shapeType: l['shapeType'] != null ? ShapeType.values.firstWhere((e) => e.name == l['shapeType']) : null,
              fillColor: l['fillColor'] != null ? Color(l['fillColor']) : null,
              strokeColor: l['strokeColor'] != null ? Color(l['strokeColor']) : null,
              strokeWidth: (l['strokeWidth'] as num?)?.toDouble(),
              clothingAssetPath: l['clothingAssetPath'],
              brightness: (l['brightness'] as num?)?.toDouble() ?? 0.0,
              contrast: (l['contrast'] as num?)?.toDouble() ?? 0.0,
              exposure: (l['exposure'] as num?)?.toDouble() ?? 0.0,
              colorHub: l['colorHub'] as String? ?? 'normal',
              hue: (l['hue'] as num?)?.toDouble() ?? 0.0,
              tintOpacity: (l['tintOpacity'] as num?)?.toDouble() ?? 0.0,
              brushStrokes: l['brushStrokes'] != null
                  ? (l['brushStrokes'] as List)
                      .map((bs) => BrushStroke.fromJson(bs))
                      .toList()
                  : const [],
            )).toList();

            projects.add(RecentProject(
              id: id,
              selectedSize: selectedSize,
              bgOption: bgOption,
              layers: layers,
              originalImageBytes: origBytes,
              bgRemovedBytes: imgBytes,
              thumbnailBytes: thumbBytes,
              lastSaved: DateTime.parse(metadata['lastSaved']),
            ));
          } catch (e) {
            debugPrint('Error parsing project file ${file.path}: $e');
          }
        }
      }
      
      // Sort by lastSaved descending
      projects.sort((a, b) => b.lastSaved.compareTo(a.lastSaved));
      return projects;
    } catch (e) {
      debugPrint('Error getting recent projects: $e');
      return [];
    }
  }

  Future<void> deleteProject(String id) async {
    try {
      final dirPath = await _getDirPath();
      final imgFile = File('$dirPath/image_$id.png');
      final origFile = File('$dirPath/original_$id.png');
      final thumbnailFile = File('$dirPath/thumbnail_$id.png');
      final bgFile = File('$dirPath/bg_$id.png');
      final metadataFile = File('$dirPath/metadata_$id.json');
      if (await imgFile.exists()) await imgFile.delete();
      if (await origFile.exists()) await origFile.delete();
      if (await thumbnailFile.exists()) await thumbnailFile.delete();
      if (await bgFile.exists()) await bgFile.delete();
      if (await metadataFile.exists()) await metadataFile.delete();
    } catch (e) {
      debugPrint('Error deleting project: $e');
    }
  }
}
