import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import 'package:camera/camera.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../models/passport_size.dart';
import '../models/recent_project.dart';
import '../models/editor_layer.dart';
import '../services/recent_projects_service.dart';
import 'camera_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'crop_rotate_screen.dart';
import 'editor_screen.dart';
import 'settings_screen.dart';
import '../widgets/follow_us_dialog.dart';
import '../services/responsive_helper.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin
    implements RouteAware {
  late TabController _tabController;
  List<RecentProject> _recentProjects = [];
  bool _loadingProjects = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadRecentProjects();
    // Refresh projects list when switching to Recent tab
    _tabController.addListener(() {
      if (_tabController.index == 1) {
        _loadRecentProjects();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FollowUsDialog.checkAndPrompt(context);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to route events so we know when this screen comes back into view
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  /// Called when a route above this one was popped (i.e., user pressed Back
  /// from EditorScreen, ShareScreen, etc.)
  @override
  void didPopNext() {
    _loadRecentProjects();
  }

  @override
  void didPush() {}

  @override
  void didPushNext() {}

  @override
  void didPop() {}

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRecentProjects() async {
    setState(() => _loadingProjects = true);
    final projects = await RecentProjectsService.instance.getRecentProjects();
    if (mounted) {
      setState(() {
        _recentProjects = projects;
        _loadingProjects = false;
      });
    }
  }

  Future<void> _deleteProject(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Project?'),
        content: const Text(
          'Are you sure you want to permanently delete this project?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await RecentProjectsService.instance.deleteProject(id);
      _loadRecentProjects();
    }
  }

  bool _isFlagEmoji(String? emoji) {
    if (emoji == null || emoji.isEmpty) return false;
    final runes = emoji.runes;
    for (final rune in runes) {
      if (rune >= 0x1F1E6 && rune <= 0x1F1FF) {
        return true;
      }
    }
    return false;
  }

  String _getProjectTitle(RecentProject project, int index) {
    final textLayers = project.layers
        .where((l) => l.type == LayerType.text)
        .toList();
    if (textLayers.isNotEmpty) {
      final firstText = textLayers.first.text;
      if (firstText != null && firstText.trim().isNotEmpty) {
        return firstText;
      }
    }
    return '${project.selectedSize.label} ${_recentProjects.length - index}';
  }

  void _selectPhotoSource(PassportSize size) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _isFlagEmoji(size.emoji)
                    ? const Icon(
                        Icons.portrait_rounded,
                        size: 24,
                        color: AppTheme.accent,
                      )
                    : Text(
                        size.emoji ?? '📷',
                        style: const TextStyle(fontSize: 20),
                      ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        size.label,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        '${size.dimensionLabel} · ${size.country}',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 16),
            Text(
              'CHOOSE PHOTO SOURCE',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.muted,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  color: AppTheme.accent,
                ),
              ),
              title: Text(
                'Take a Photo',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              subtitle: Text(
                'Use front camera with guides',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _openCamera(size);
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.photo_library_rounded,
                  color: AppTheme.primary,
                ),
              ),
              title: Text(
                'Select from Gallery',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              subtitle: Text(
                'Choose an existing picture',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _openGallery(size);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _openCamera(PassportSize size) async {
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      final frontCam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final result = await Navigator.push<Uint8List>(
        context,
        MaterialPageRoute(builder: (_) => CameraScreen(camera: frontCam)),
      );
      if (result != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                CropRotateScreen(imageBytes: result, targetSize: size),
          ),
        ).then((_) => _loadRecentProjects());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Camera error: $e')));
      }
    }
  }

  Future<void> _openGallery(PassportSize size) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image != null && mounted) {
        final bytes = await image.readAsBytes();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CropRotateScreen(imageBytes: bytes, targetSize: size),
          ),
        ).then((_) => _loadRecentProjects());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gallery error: $e')),
        );
      }
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
          child: Scaffold(
            body: Container(
              decoration: BoxDecoration(gradient: AppTheme.bgGradient),
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    _buildTabBar(),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [_buildSizesTab(), _buildRecentTab()],
                      ),
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

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Center(
              child: Text(
                "👻",
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Photo ID Maker',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  'Create instant photos ID on hand.',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // Follow Us Button
          if (!context.isWatch) ...[
            InkWell(
              onTap: () => FollowUsDialog.show(context),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppTheme.primary.withOpacity(0.25),
                    width: 0.5,
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.hub_rounded,
                      color: AppTheme.primary,
                      size: 15,
                    ),
                    SizedBox(width: 5),
                    Text(
                      'Follow Us',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          const SizedBox(width: 6),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ).then((_) {
                if (mounted) setState(() {});
              });
            },
            icon: const Icon(Icons.settings_rounded),
            color: AppTheme.textPrimary,
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: 48,
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: AppTheme.primary,
          borderRadius: BorderRadius.circular(10),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Colors.white,
        unselectedLabelColor: AppTheme.textSecondary,
        labelStyle: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        dividerColor: Colors.transparent,
        tabs: const [
          Tab(text: 'Photo Sizes'),
          Tab(text: 'Recent Projects'),
        ],
      ),
    );
  }

  Widget _buildSizesTab() {
    final grouped = PassportSizes.homepageGrouped;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: grouped.keys.length,
      itemBuilder: (context, index) {
        final category = grouped.keys.elementAt(index);
        final sizes = grouped[category]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
              child: Text(
                category.toUpperCase(),
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accent,
                  letterSpacing: 1.0,
                ),
              ),
            ),
            ...sizes.map((size) => _buildSizeCard(size)),
          ],
        );
      },
    );
  }

  Widget _buildSizeCard(PassportSize size) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: AppTheme.glassCard,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _selectPhotoSource(size),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.cardElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border, width: 0.5),
                  ),
                  child: Center(
                    child: _isFlagEmoji(size.emoji)
                        ? const Icon(
                            Icons.portrait_rounded,
                            size: 24,
                            color: AppTheme.accent,
                          )
                        : Text(
                            size.emoji ?? '📷',
                            style: const TextStyle(fontSize: 22),
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    size.label,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
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

  Widget _buildRecentTab() {
    if (_loadingProjects) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    if (_recentProjects.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.border, width: 0.5),
                ),
                child: Icon(
                  Icons.folder_open_rounded,
                  size: 40,
                  color: AppTheme.muted,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'No recent projects',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Projects you edit will appear here so you can continue editing later.',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _recentProjects.length,
      itemBuilder: (context, index) {
        final project = _recentProjects[index];
        final size = project.selectedSize;
        final formattedDate = DateFormat(
          'MMM dd, yyyy · hh:mm a',
        ).format(project.lastSaved);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: AppTheme.glassCard,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EditorScreen(loadedProject: project),
                    ),
                  ).then(
                    (_) => _loadRecentProjects(),
                  ); // Refresh list when returning
                },
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      // Preview image of project
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: AppTheme.cardElevated,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppTheme.border,
                            width: 0.5,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: AspectRatio(
                            aspectRatio: size.aspectRatio,
                            child: Image.memory(
                              project.thumbnailBytes ?? project.bgRemovedBytes,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      // Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getProjectTitle(project, index),
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${size.dimensionLabel} · ${size.country}',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 11,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              formattedDate,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 10,
                                color: AppTheme.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Delete action
                      IconButton(
                        onPressed: () => _deleteProject(project.id),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: AppTheme.error,
                          size: 20,
                        ),
                        tooltip: 'Delete Project',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
