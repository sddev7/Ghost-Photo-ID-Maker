import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import '../theme/app_theme.dart';
import '../models/passport_size.dart';

class ShareScreen extends StatelessWidget {
  final Uint8List imageBytes;
  final String fileName;
  final PassportSize size;

  const ShareScreen({
    super.key,
    required this.imageBytes,
    required this.fileName,
    required this.size,
  });

  String _getFileSizeString() {
    final kb = imageBytes.lengthInBytes / 1024;
    if (kb > 1024) {
      return '${(kb / 1024).toStringAsFixed(1)} MB';
    }
    return '${kb.toStringAsFixed(0)} KB';
  }

  Future<void> _sharePhoto(BuildContext context) async {
    try {
      final xFile = XFile.fromData(
        imageBytes,
        name: fileName.split('/').last,
        mimeType: 'image/png',
      );
      await Share.shareXFiles([xFile], text: 'My passport photo');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to share: $e')),
        );
      }
    }
  }

  int _calculateMaxPhotosPerPage() {
    final double minMargin = 5.0 * PdfPageFormat.mm;
    final double gap = 4.0 * PdfPageFormat.mm;

    final double usableWidth = PdfPageFormat.a4.width - (2 * minMargin);
    final double usableHeight = PdfPageFormat.a4.height - (2 * minMargin);

    final double itemWidth = size.unit == SizeUnit.mm ? size.width : (size.width / 300 * 25.4);
    final double itemHeight = size.unit == SizeUnit.mm ? size.height : (size.height / 300 * 25.4);

    final double photoWidthPoints = (itemWidth > 0 ? itemWidth : 35.0) * PdfPageFormat.mm;
    final double photoHeightPoints = (itemHeight > 0 ? itemHeight : 45.0) * PdfPageFormat.mm;

    int cols = ((usableWidth + gap) / (photoWidthPoints + gap)).floor();
    int rows = ((usableHeight + gap) / (photoHeightPoints + gap)).floor();

    if (cols <= 0) cols = 1;
    if (rows <= 0) rows = 1;

    return cols * rows;
  }

  Future<int?> _showPhotoCountDialog(BuildContext context, int maxPhotos) async {
    int count = 8.clamp(1, maxPhotos);
    return showDialog<int>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: AppTheme.card,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(
                'Number of Photos',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Select how many copies you want on the A4 page.',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: count > 1
                            ? () => setState(() => count--)
                            : null,
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                        iconSize: 32,
                        color: AppTheme.primary,
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTheme.border),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: count < maxPhotos
                            ? () => setState(() => count++)
                            : null,
                        icon: const Icon(Icons.add_circle_outline_rounded),
                        iconSize: 32,
                        color: AppTheme.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: {1, 4, 8, 12, 16, 24, 32, maxPhotos}.map((preset) {
                      if (preset > maxPhotos) return const SizedBox.shrink();
                      final isSelected = count == preset;
                      return ChoiceChip(
                        label: Text(preset == maxPhotos ? 'Max ($preset)' : '$preset'),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => count = preset);
                          }
                        },
                        selectedColor: AppTheme.primary.withOpacity(0.2),
                        labelStyle: TextStyle(
                          color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: Text('Cancel', style: TextStyle(color: AppTheme.muted)),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, count),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Confirm'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _generateAndProcessPdf(
    BuildContext context, {
    required int photoCount,
    required bool isPrintAction,
  }) async {
    try {
      final pdf = pw.Document();
      final image = pw.MemoryImage(imageBytes);

      final double minMargin = 5.0 * PdfPageFormat.mm;
      final double gap = 4.0 * PdfPageFormat.mm;

      final double itemWidth = size.unit == SizeUnit.mm ? size.width : (size.width / 300 * 25.4);
      final double itemHeight = size.unit == SizeUnit.mm ? size.height : (size.height / 300 * 25.4);

      final double photoWidthPoints = (itemWidth > 0 ? itemWidth : 35.0) * PdfPageFormat.mm;
      final double photoHeightPoints = (itemHeight > 0 ? itemHeight : 45.0) * PdfPageFormat.mm;

      final double usableWidth = PdfPageFormat.a4.width - (2 * minMargin);
      final double usableHeight = PdfPageFormat.a4.height - (2 * minMargin);

      int cols = ((usableWidth + gap) / (photoWidthPoints + gap)).floor();
      int rows = ((usableHeight + gap) / (photoHeightPoints + gap)).floor();
      if (cols <= 0) cols = 1;
      if (rows <= 0) rows = 1;
      final int maxFit = cols * rows;

      // Calculate dynamic margins to center the photo grid
      final double gridWidth = (cols * photoWidthPoints) + ((cols - 1) * gap);
      final double gridHeight = (rows * photoHeightPoints) + ((rows - 1) * gap);

      final double leftRightMargin = (PdfPageFormat.a4.width - gridWidth) / 2;
      final double topBottomMargin = (PdfPageFormat.a4.height - gridHeight) / 2;

      int remaining = photoCount;
      while (remaining > 0) {
        final pageCount = remaining > maxFit ? maxFit : remaining;
        remaining -= pageCount;

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: pw.EdgeInsets.symmetric(
              horizontal: leftRightMargin,
              vertical: topBottomMargin,
            ),
            build: (pw.Context context) {
              return pw.Wrap(
                spacing: gap,
                runSpacing: gap,
                children: List.generate(
                  pageCount,
                  (index) => pw.Container(
                    width: photoWidthPoints,
                    height: photoHeightPoints,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                        color: PdfColors.black,
                        width: 3,
                      ),
                    ),
                    child: pw.Image(image, fit: pw.BoxFit.fill),
                  ),
                ),
              );
            },
          ),
        );
      }

      if (isPrintAction) {
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => pdf.save(),
          name: fileName.split('/').last.replaceAll('.png', '').replaceAll('.jpg', ''),
        );
      } else {
        final output = await getTemporaryDirectory();
        final pdfPath = '${output.path}/passport_photo_${DateTime.now().millisecondsSinceEpoch}.pdf';
        final file = File(pdfPath);
        await file.writeAsBytes(await pdf.save());

        final xFile = XFile(
          file.path,
          name: fileName.split('/').last.replaceAll('.png', '.pdf').replaceAll('.jpg', '.pdf'),
          mimeType: 'application/pdf',
        );
        await Share.shareXFiles([xFile], text: 'My passport photo PDF (A4)');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to process PDF: $e')),
        );
      }
    }
  }

  Future<void> _handlePdfAction(BuildContext context, {required bool isPrint}) async {
    final maxPhotos = _calculateMaxPhotosPerPage();
    final count = await _showPhotoCountDialog(context, maxPhotos);
    if (count != null && context.mounted) {
      await _generateAndProcessPdf(context, photoCount: count, isPrintAction: isPrint);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.bgGradient),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(context),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      _buildSuccessHeader(context),
                      const SizedBox(height: 24),
                      _buildPreviewCard(context),
                      const SizedBox(height: 28),
                      _buildInfoSection(context),
                      const SizedBox(height: 32),
                      _buildActionButtons(context),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Export Successful',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          IconButton(
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            icon: Icon(Icons.close_rounded, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessHeader(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.success.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_rounded,
            color: AppTheme.success,
            size: 48,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Saved to Gallery!',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Your biometric photo is ready to use.',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewCard(BuildContext context) {
    final aspect = size.aspectRatio;
    return Center(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.35,
          maxWidth: MediaQuery.of(context).size.width * 0.65,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: aspect,
            child: Image.memory(
              imageBytes,
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.surfaceDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Document Details',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              Text(
                size.emoji ?? '📷',
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
          _buildInfoRow('Name', size.label),
          _buildInfoRow('Region', size.country),
          _buildInfoRow('Dimensions', size.dimensionLabel),
          _buildInfoRow('File Size', _getFileSizeString()),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              color: AppTheme.textSecondary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _sharePhoto(context),
            icon: const Icon(Icons.share_rounded, size: 20),
            label: const Text('Share Photo'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _handlePdfAction(context, isPrint: false),
            icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
            label: const Text('Share as PDF (A4)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _handlePdfAction(context, isPrint: true),
            icon: const Icon(Icons.print_rounded, size: 20),
            label: const Text('Print Photo(s)'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () {
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
          child: const Text(
            'Go back to Home',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              color: AppTheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}
