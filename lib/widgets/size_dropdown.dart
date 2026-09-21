
import 'package:flutter/material.dart';
import '../models/passport_size.dart';
import '../theme/app_theme.dart';

class SizeDropdown extends StatelessWidget {
  final PassportSize selectedSize;
  final ValueChanged<PassportSize> onChanged;

  const SizeDropdown({
    super.key,
    required this.selectedSize,
    required this.onChanged,
  });

  void _showPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SizePickerSheet(
        selected: selectedSize,
        onChanged: (size) {
          if (size.id == 'custom') {
            _showCustomDialog(context);
          } else {
            onChanged(size);
          }
        },
      ),
    );
  }

  void _showCustomDialog(BuildContext context) {
    final wCtrl = TextEditingController(
      text: selectedSize.width.toString(),
    );
    final hCtrl = TextEditingController(
      text: selectedSize.height.toString(),
    );
    SizeUnit unit = selectedSize.unit;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: AppTheme.card,
          title: Text(
            'Custom Size',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: AppTheme.textPrimary,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _NumField(
                      label: 'Width',
                      controller: wCtrl,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NumField(
                      label: 'Height',
                      controller: hCtrl,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('Unit:',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontFamily: 'Inter')),
                  const SizedBox(width: 12),
                  _UnitChip(
                    label: 'mm',
                    selected: unit == SizeUnit.mm,
                    onTap: () => setState(() => unit = SizeUnit.mm),
                  ),
                  const SizedBox(width: 8),
                  _UnitChip(
                    label: 'px',
                    selected: unit == SizeUnit.px,
                    onTap: () => setState(() => unit = SizeUnit.px),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: TextStyle(color: AppTheme.muted)),
            ),
            ElevatedButton(
              onPressed: () {
                final w = double.tryParse(wCtrl.text) ?? 35;
                final h = double.tryParse(hCtrl.text) ?? 45;
                onChanged(PassportSize(
                  id: 'custom',
                  label: 'Custom',
                  country: 'Custom',
                  width: w,
                  height: h,
                  unit: unit,
                  emoji: '✏️',
                ));
                Navigator.pop(ctx);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showPicker(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            Text(
              selectedSize.emoji ?? '📷',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selectedSize.label,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    selectedSize.dimensionLabel,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      color: AppTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppTheme.muted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _SizePickerSheet extends StatelessWidget {
  final PassportSize selected;
  final ValueChanged<PassportSize> onChanged;

  const _SizePickerSheet({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final groups = PassportSizes.grouped;
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      builder: (ctx, scroll) {
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Select Size',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: groups.entries.map((entry) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            entry.key,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.muted,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        ...entry.value.map((size) {
                          final isSelected = size.id == selected.id;
                          return GestureDetector(
                            onTap: () {
                              onChanged(size);
                              Navigator.pop(ctx);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppTheme.primary.withOpacity(0.15)
                                    : AppTheme.card,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? AppTheme.primary
                                      : AppTheme.border,
                                  width: isSelected ? 1.5 : 0.5,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    size.emoji ?? '📷',
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      size.label,
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 13,
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        color: isSelected
                                            ? AppTheme.primary
                                            : AppTheme.textPrimary,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    size.dimensionLabel,
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 11,
                                      color: AppTheme.muted,
                                    ),
                                  ),
                                  if (isSelected)
                                    const Padding(
                                      padding: EdgeInsets.only(left: 8),
                                      child: Icon(Icons.check_rounded,
                                          color: AppTheme.primary, size: 18),
                                    ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NumField extends StatelessWidget {
  final String label;
  final TextEditingController controller;

  const _NumField({required this.label, required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(color: AppTheme.textPrimary, fontFamily: 'Inter'),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppTheme.muted, fontSize: 12),
        filled: true,
        fillColor: AppTheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.primary),
        ),
      ),
    );
  }
}

class _UnitChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _UnitChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : AppTheme.card,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppTheme.muted,
          ),
        ),
      ),
    );
  }
}
