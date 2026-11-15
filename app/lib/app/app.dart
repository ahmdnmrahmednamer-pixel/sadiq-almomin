import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../core/services/settings_service.dart';
import '../core/services/prayer_service.dart';
import '../core/localization/app_localizations.dart';
import 'router.dart';

class AlMominApp extends ConsumerStatefulWidget {
  const AlMominApp({super.key});

  @override
  ConsumerState<AlMominApp> createState() => _AlMominAppState();
}

class _AlMominAppState extends ConsumerState<AlMominApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PrayerService.instance.checkAndUpdateLocationOnResume();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      PrayerService.instance.checkAndUpdateLocationOnResume();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SettingsService.instance,
      builder: (context, _) {
        final s = SettingsService.instance;
        final mode = s.themeMode;
        ThemeMode themeMode;
        ThemeData lightThemeData = AppTheme.lightTheme;
        ThemeData darkThemeData = AppTheme.darkTheme;

        switch (mode) {
          case 'light':
            themeMode = ThemeMode.light;
            break;
          case 'sepia':
            themeMode = ThemeMode.light;
            lightThemeData = AppTheme.sepiaTheme;
            darkThemeData = AppTheme.sepiaTheme;
            break;
          case 'dark':
            themeMode = ThemeMode.dark;
            darkThemeData = AppTheme.darkTheme;
            break;
          case 'oled':
            themeMode = ThemeMode.dark;
            lightThemeData = AppTheme.oledTheme;
            darkThemeData = AppTheme.oledTheme;
            break;
          case 'system':
          default:
            themeMode = ThemeMode.system;
            darkThemeData = AppTheme.darkTheme;
            break;
        }

        return MaterialApp.router(
          title: 'صديق المؤمن',
          debugShowCheckedModeBanner: false,
          theme: lightThemeData,
          darkTheme: darkThemeData,
          themeMode: themeMode,
          routerConfig: appRouter,
          locale: s.currentLocale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) {
            return Directionality(
              textDirection: s.textDirection,
              child: child ?? const SizedBox.shrink(),
            );
          },
        );
      },
    );
  }
}
