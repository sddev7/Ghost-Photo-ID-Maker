import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';

// Global ValueNotifier for ThemeMode
final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

// Global RouteObserver so screens can detect when they come back into view
final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientation
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Load saved theme mode from SharedPreferences
  ThemeMode savedThemeMode = ThemeMode.system;
  try {
    final prefs = await SharedPreferences.getInstance();
    final modeString = prefs.getString('theme_mode');
    if (modeString != null) {
      savedThemeMode = ThemeMode.values.firstWhere(
        (e) => e.toString() == modeString,
        orElse: () => ThemeMode.system,
      );
    }
  } catch (e) {
    debugPrint('Error loading theme mode: $e');
  }
  themeModeNotifier.value = savedThemeMode;

  runApp(const PassportMakerApp());
}

class PassportMakerApp extends StatefulWidget {
  const PassportMakerApp({super.key});

  @override
  State<PassportMakerApp> createState() => _PassportMakerAppState();
}

class _PassportMakerAppState extends State<PassportMakerApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, themeMode, _) {
        final Brightness systemBrightness =
            WidgetsBinding.instance.platformDispatcher.platformBrightness;

        if (themeMode == ThemeMode.system) {
          AppTheme.isDark = systemBrightness == Brightness.dark;
        } else {
          AppTheme.isDark = themeMode == ThemeMode.dark;
        }

        final isThemeDark = AppTheme.isDark;
        SystemChrome.setSystemUIOverlayStyle(
          SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness:
                isThemeDark ? Brightness.light : Brightness.dark,
            systemNavigationBarColor: isThemeDark
                ? const Color(0xFF0A0F1E)
                : const Color(0xFFF8FAFC),
            systemNavigationBarIconBrightness:
                isThemeDark ? Brightness.light : Brightness.dark,
          ),
        );

        return MaterialApp(
          title: 'Passport Maker',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          navigatorObservers: [routeObserver],
          home: const HomeScreen(),
        );
      },
    );
  }
}
