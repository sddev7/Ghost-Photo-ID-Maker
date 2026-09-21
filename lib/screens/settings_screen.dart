import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_theme.dart';
import '../utils/manifest_utils.dart';
import '../main.dart';
import '../config/app_urls.dart';
import '../widgets/follow_us_dialog.dart';
import '../services/responsive_helper.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _appName = 'Ghost Photo ID Maker';
  final String _appVersion = '1.3.0';
  bool _loadingAppName = true;

  @override
  void initState() {
    super.initState();
    _loadAppName();
  }

  Future<void> _loadAppName() async {
    final name = await ManifestUtils.getAppName();
    if (mounted) {
      setState(() {
        _appName = name;
        _loadingAppName = false;
      });
    }
  }

  Future<void> _updateTheme(ThemeMode mode) async {
    themeModeNotifier.value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('theme_mode', mode.toString());
    } catch (e) {
      debugPrint('Error saving theme mode: $e');
    }
    setState(() {});
  }

  Future<void> _openUrl(String urlString) async {
    final uri = Uri.parse(urlString);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open $urlString'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWatch = context.isWatch;
    final isTv = context.isTV;

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, currentMode, _) {
        final isThemeDark = AppTheme.isDark;
        final systemOverlayStyle = SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isThemeDark
              ? Brightness.light
              : Brightness.dark,
          statusBarBrightness: isThemeDark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: AppTheme.background,
          systemNavigationBarIconBrightness: isThemeDark
              ? Brightness.light
              : Brightness.dark,
        );

        final contentWidth = isWatch
            ? 280.0
            : context.isMobile
                ? double.infinity
                : isTv
                    ? 680.0
                    : 560.0;

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: systemOverlayStyle,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Settings'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            body: Container(
              decoration: BoxDecoration(gradient: AppTheme.bgGradient),
              child: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: contentWidth),
                    child: ListView(
                      padding: EdgeInsets.symmetric(
                        horizontal: isWatch ? 12 : 20,
                        vertical: isWatch ? 10 : 16,
                      ),
                      children: [
                        _buildSectionHeader('THEME MODE'),
                        const SizedBox(height: 12),
                        _buildThemeCard(),
                        const SizedBox(height: 24),
                        _buildSectionHeader('COMMUNITY & OPEN SOURCE'),
                        const SizedBox(height: 12),
                        _buildCommunityCard(),
                        const SizedBox(height: 24),
                        _buildSectionHeader('SUPPORT & LEGAL'),
                        const SizedBox(height: 12),
                        _buildActionCard(),
                        const SizedBox(height: 32),
                        _buildAboutSection(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontFamily: 'Poppins',
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppTheme.accent,
        letterSpacing: 1.0,
      ),
    );
  }

  Widget _buildThemeCard() {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, currentMode, _) {
        return Container(
          decoration: AppTheme.glassCard,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose how the application looks on your device.',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildThemeOption(
                      mode: ThemeMode.system,
                      icon: Icons.brightness_auto_rounded,
                      label: 'System',
                      isSelected: currentMode == ThemeMode.system,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildThemeOption(
                      mode: ThemeMode.light,
                      icon: Icons.light_mode_rounded,
                      label: 'Light',
                      isSelected: currentMode == ThemeMode.light,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildThemeOption(
                      mode: ThemeMode.dark,
                      icon: Icons.dark_mode_rounded,
                      label: 'Dark',
                      isSelected: currentMode == ThemeMode.dark,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildThemeOption({
    required ThemeMode mode,
    required IconData icon,
    required String label,
    required bool isSelected,
  }) {
    final selectedColor = AppTheme.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _updateTheme(mode),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected
                ? selectedColor.withOpacity(0.15)
                : AppTheme.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? selectedColor : AppTheme.border,
              width: isSelected ? 1.5 : 0.5,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? selectedColor : AppTheme.textSecondary,
                size: 20,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? selectedColor : AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCommunityCard() {
    return Container(
      decoration: AppTheme.glassCard,
      child: Column(
        children: [
          _buildActionTile(
            icon: Icons.hub_rounded,
            title: 'Follow Us',
            subtitle: 'We are open-source. Join Ghost Ecosystem',
            onTap: () => FollowUsDialog.show(context),
          ),
          const Divider(height: 1),
          _buildActionTile(
            icon: Icons.code_rounded,
            title: 'GitHub Repository',
            subtitle: 'Star and explore our codebase on GitHub',
            onTap: () => _openUrl(AppUrls.githubRepo),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard() {
    return Container(
      decoration: AppTheme.glassCard,
      child: Column(
        children: [
          _buildActionTile(
            icon: Icons.star_rate_rounded,
            title: 'Rate Us',
            subtitle: 'Show your love on the Google Play Store',
            onTap: () => _openUrl(AppUrls.playStoreApp),
          ),
          const Divider(height: 1),
          _buildActionTile(
            icon: Icons.share_rounded,
            title: 'Share App',
            subtitle: 'Share Ghost Photo ID Maker with friends & family',
            onTap: () {
              Share.share(
                'Create professional passport, visa, and ID photos for free with Ghost Photo ID Maker:\n${AppUrls.playStoreApp}',
                subject: 'Ghost Photo ID Maker',
              );
            },
          ),
          const Divider(height: 1),
          _buildActionTile(
            icon: Icons.privacy_tip_rounded,
            title: 'Privacy Policy',
            subtitle: 'Read our privacy policy online',
            onTap: () => _openUrl(AppUrls.privacyPolicy),
          ),
          const Divider(height: 1),
          _buildActionTile(
            icon: Icons.contact_support_rounded,
            title: 'Report Problem',
            subtitle: 'Facing problems? Talk to our developer',
            onTap: () => _openUrl(AppUrls.feedbackReport),
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: AppTheme.primary, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          color: AppTheme.textSecondary,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: AppTheme.textSecondary,
        size: 20,
      ),
      onTap: onTap,
    );
  }

  Widget _buildAboutSection() {
    return Column(
      children: [
        if (_loadingAppName)
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          Text(
            _appName,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
        const SizedBox(height: 4),
        Text(
          'Version $_appVersion · Ghost Series Ecosystem',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}
