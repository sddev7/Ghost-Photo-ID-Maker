
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../theme/app_theme.dart';
import '../models/bg_option.dart';
import 'package:image_picker/image_picker.dart';

class BgPanel extends StatefulWidget {
  final BgOption selected;
  final ValueChanged<BgOption> onChanged;

  const BgPanel({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  State<BgPanel> createState() => _BgPanelState();
}

class _BgPanelState extends State<BgPanel> with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    // Sync to current bg type
    switch (widget.selected.type) {
      case BgType.transparent:
        _tabs.index = 0;
        break;
      case BgType.solid:
        _tabs.index = 1;
        break;
      case BgType.gradient:
        _tabs.index = 2;
        break;
      case BgType.image:
        _tabs.index = 3;
        break;
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Sub-tabs
          TabBar(
            controller: _tabs,
            isScrollable: false,
            indicatorColor: AppTheme.accent,
            indicatorWeight: 2,
            labelColor: AppTheme.accent,
            unselectedLabelColor: AppTheme.muted,
            labelStyle: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            tabs: const [
              Tab(text: 'None'),
              Tab(text: 'Solid'),
              Tab(text: 'Gradient'),
              Tab(text: 'Image'),
            ],
          ),
          SizedBox(
            height: 130,
            child: TabBarView(
              controller: _tabs,
              children: [
                _TransparentTab(
                  isSelected: widget.selected.isTransparent,
                  onSelect: () => widget.onChanged(BgOption.transparent()),
                ),
                _SolidTab(
                  selected: widget.selected,
                  onChanged: widget.onChanged,
                ),
                _GradientTab(
                  selected: widget.selected,
                  onChanged: widget.onChanged,
                ),
                _ImageTab(
                  selected: widget.selected,
                  onChanged: widget.onChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Transparent Tab ──────────────────────────────────────────────────────────

class _TransparentTab extends StatelessWidget {
  final bool isSelected;
  final VoidCallback onSelect;
  const _TransparentTab({required this.isSelected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: onSelect,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primary.withOpacity(0.15)
                : AppTheme.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? AppTheme.primary : AppTheme.border,
              width: isSelected ? 1.5 : 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.layers_clear_rounded,
                  color: AppTheme.primary, size: 20),
              const SizedBox(width: 10),
              Text(
                'Transparent Background',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 8),
                const Icon(Icons.check_circle_rounded,
                    color: AppTheme.primary, size: 18),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Solid Tab ────────────────────────────────────────────────────────────────

class _SolidTab extends StatelessWidget {
  final BgOption selected;
  final ValueChanged<BgOption> onChanged;
  const _SolidTab({required this.selected, required this.onChanged});

  void _showColorPicker(BuildContext context) {
    Color pickerColor = selected.solidColor ?? Colors.white;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text('Pick a color',
            style: TextStyle(color: AppTheme.textPrimary, fontFamily: 'Poppins')),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pickerColor,
            onColorChanged: (c) => pickerColor = c,
            enableAlpha: false,
            hexInputBar: true,
            labelTypes: const [],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: TextStyle(color: AppTheme.muted)),
          ),
          ElevatedButton(
            onPressed: () {
              onChanged(BgOption.solid(pickerColor));
              Navigator.pop(ctx);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Custom color
          GestureDetector(
            onTap: () => _showColorPicker(context),
            child: _ColorSwatch(
              child: const Icon(Icons.colorize_rounded,
                  color: Colors.white, size: 20),
              isSelected: false,
              label: 'Custom',
            ),
          ),
          const SizedBox(width: 8),
          ...BgPresets.solidColors.map((color) {
            final isSelected =
                selected.isSolid && selected.solidColor?.value == color.value;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => onChanged(BgOption.solid(color)),
                child: _ColorSwatch(
                  color: color,
                  isSelected: isSelected,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─── Gradient Tab ─────────────────────────────────────────────────────────────

class _GradientTab extends StatelessWidget {
  final BgOption selected;
  final ValueChanged<BgOption> onChanged;
  const _GradientTab({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: BgPresets.gradients.asMap().entries.map((e) {
          final bg = e.value;
          final isSelected = selected.isGradient &&
              selected.gradientColors?.first.value ==
                  bg.gradientColors?.first.value;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onChanged(bg),
              child: _ColorSwatch(
                gradient: LinearGradient(
                  colors: bg.gradientColors!,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                isSelected: isSelected,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Image Tab ────────────────────────────────────────────────────────────────

class _ImageTab extends StatelessWidget {
  final BgOption selected;
  final ValueChanged<BgOption> onChanged;
  const _ImageTab({required this.selected, required this.onChanged});

  Future<void> _pickImage(BuildContext context) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        final bytes = await image.readAsBytes();
        onChanged(BgOption.image(bytes));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking background image: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: () => _pickImage(context),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: BoxDecoration(
            color: selected.isImage
                ? AppTheme.primary.withOpacity(0.15)
                : AppTheme.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected.isImage ? AppTheme.primary : AppTheme.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected.isImage && selected.imageBytes != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.memory(
                    selected.imageBytes!,
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 12),
              ] else ...[
                const Icon(Icons.image_rounded,
                    color: AppTheme.primary, size: 20),
                const SizedBox(width: 10),
              ],
              Text(
                selected.isImage ? 'Change Image' : 'Pick from Gallery',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// ─── Shared swatch widget ─────────────────────────────────────────────────────

class _ColorSwatch extends StatelessWidget {
  final Color? color;
  final Gradient? gradient;
  final Widget? child;
  final bool isSelected;
  final String? label;

  const _ColorSwatch({
    this.color,
    this.gradient,
    this.child,
    required this.isSelected,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color,
            gradient: gradient,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppTheme.primary : AppTheme.border,
              width: isSelected ? 2.5 : 0.5,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppTheme.primary.withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: child != null
              ? Center(child: child)
              : isSelected
                  ? const Center(
                      child: Icon(Icons.check_rounded,
                          color: Colors.white, size: 20),
                    )
                  : null,
        ),
        if (label != null) ...[
          const SizedBox(height: 4),
          Text(
            label!,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              color: AppTheme.muted,
            ),
          ),
        ],
      ],
    );
  }
}
