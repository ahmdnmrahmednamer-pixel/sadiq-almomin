import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/app/router.dart';
import 'package:almomin/app/widgets/app_navigation_drawer.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/services/backup_restore_service.dart';
import 'package:almomin/core/services/prayer_service.dart';
import 'package:almomin/core/services/prayer_tracker_service.dart';
import 'package:almomin/core/services/daily_wird_service.dart';
import 'package:almomin/core/services/sunan_rawatib_service.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/core/services/scholars_lectures_service.dart';
import 'package:almomin/core/services/unified_library_search_service.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/core/ui/adaptive_screen_layouts.dart';
import 'package:almomin/features/audio/audio_screen.dart';
import 'package:almomin/features/audio/scholars_audio_library_screen.dart';
import 'package:almomin/features/home/widgets/home_quick_sections_grid.dart';
import 'package:almomin/features/home/widgets/home_shortcuts_list.dart';
import 'package:almomin/features/home/screens/app_screen_directory_screen.dart';
import 'package:almomin/features/library/islamic_library_screen.dart';
import 'package:almomin/features/library/widgets/comprehensive_libraries_portal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final search = UnifiedLibrarySearchService.instance;

  Future<void> capture(
      WidgetTester tester, GlobalKey boundary, String name) async {
    const dir = String.fromEnvironment('RETIREMENT_PIXELS_DIR');
    if (dir.isEmpty) return;
    await tester.runAsync(() async {
      final image = await (boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(dir).createSync(recursive: true);
      File('$dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> mount(WidgetTester tester, Widget child,
      {double scale = 1,
      Size size = const Size(360, 800),
      GlobalKey? boundary}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child:
                Directionality(textDirection: TextDirection.rtl, child: child!),
          ),
          home: child,
        )));
    await tester.pumpAndSettle();
  }

  void absentScholars(WidgetTester tester) {
    expect(find.byType(ScholarsAudioLibraryScreen), findsNothing);
    expect(find.textContaining('مجالس العلماء'), findsNothing);
    expect(find.textContaining('كبار العلماء'), findsNothing);
    expect(find.byTooltip('موسوعة دروس ومحاضرات الشيوخ والعلماء (١١٥ شيخاً)'),
        findsNothing);
    for (final node in tester.semantics.simulatedAccessibilityTraversal()) {
      final label = node.getSemanticsData().label;
      expect(label.contains('مجالس العلماء') || label.contains('كبار العلماء'),
          isFalse);
    }
  }

  setUpAll(() async {
    for (final family in ['Amiri', 'Cairo']) {
      final loader = FontLoader(family);
      for (final weight in ['Regular', 'Bold']) {
        final file = File('assets/fonts/$family-$weight.ttf');
        if (file.existsSync()) {
          loader.addFont(
              Future.value(ByteData.sublistView(file.readAsBytesSync())));
        }
      }
      await loader.load();
    }
    const icons = String.fromEnvironment('MATERIAL_ICONS_FONT');
    if (icons.isNotEmpty) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(
            Future.value(ByteData.sublistView(File(icons).readAsBytesSync())));
      await loader.load();
    }
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'has_completed_onboarding': true, 'show_tutorial_screens': false});
    await SettingsService.instance.init(forceReload: true);
    await PrayerTrackerService.instance.init(forceReload: true);
    await DailyWirdService.instance.init(forceReload: true);
    await SunanRawatibService.instance.init(forceReload: true);
    IslamicAudioService.instance.disableNativePlayerForTesting = true;
    await IslamicAudioService.instance.stop();
  });
  tearDown(() async {
    PrayerService.instance.stopLiveTicker();
    await IslamicAudioService.instance.stop();
  });

  test(
      'retired lecture provider and filter cannot expose content, remaining libraries stay searchable',
      () async {
    await ScholarsLecturesService.instance.init();
    expect(ScholarsLecturesService.instance.allLectures, isNotEmpty);
    expect(UnifiedLibrarySearchService.libraryFilters, orderedEquals([
      'الكل', 'الفقه الميسر', 'علوم القرآن', 'غريب القرآن',
      'أسماء الله والشمائل', 'التاريخ والسيرة', 'التراث المصري',
      'قصص الأنبياء', 'التجويد ومواضيع القرآن', 'صيدلية القلوب',
    ]));
    expect(UnifiedLibrarySearchService.libraryFilters,
        isNot(contains('مجالس العلماء والدروس')));
    for (final query in ['سمير مصطفى', 'الصلاة', 'الإخلاص']) {
      final results = search.searchAllLibraries(query);
      expect(results.where((r) => r.id.startsWith('scholar_lec_')), isEmpty);
      expect(
          search.searchAllLibraries(query,
              selectedLibrary: 'مجالس العلماء والدروس'),
          isEmpty);
    }
    expect(
        search.searchAllLibraries('الإخلاص', selectedLibrary: 'رياض الصالحين'),
        isEmpty);
    expect(search.searchAllLibraries('الصمد', selectedLibrary: 'غريب القرآن'),
        isNotEmpty);
  });

  testWidgets(
      'old links redirect to retained library without constructing retired screen or clearing saved data',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'scholars_last_played_lecture', 'samir_mustafa_seerah_01');
    await prefs.setStringList('scholars_fav_profiles', ['samir_mustafa']);
    await prefs
        .setStringList('scholars_fav_lectures', ['samir_mustafa_seerah_01']);
    await ScholarsLecturesService.instance.init(forceReload: true);
    final libraryPixels = GlobalKey();
    appRouter.go('/scholars-audio');
    await tester.pumpWidget(RepaintBoundary(
        key: libraryPixels,
        child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            routerConfig: appRouter)));
    await tester.pumpAndSettle();
    expect(appRouter.routeInformationProvider.value.uri.path, '/library');
    expect(find.byType(IslamicLibraryScreen), findsOneWidget);
    expect(find.byType(ScholarsAudioLibraryScreen), findsNothing);
    expect(prefs.getString('scholars_last_played_lecture'),
        'samir_mustafa_seerah_01');
    expect(prefs.getStringList('scholars_fav_profiles'), ['samir_mustafa']);
    expect(prefs.getStringList('scholars_fav_lectures'),
        ['samir_mustafa_seerah_01']);
    expect(ScholarsLecturesService.instance.favoriteScholarIds,
        contains('samir_mustafa'));
    expect(ScholarsLecturesService.instance.favoriteLectureIds,
        contains('samir_mustafa_seerah_01'));
    final backup = (await tester
        .runAsync(() => BackupRestoreService.instance.exportBackupJson()))!;
    final validation = BackupRestoreService.instance.validateBackup(backup);
    expect(validation.isValid, isTrue);
    expect(backup, contains('scholars_fav_profiles'));
    expect(backup, contains('scholars_fav_lectures'));
    await capture(tester, libraryPixels, 'redirect_library_800_1x');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    appRouter.go('/momen-duaa');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Home grid and audio retain accessible alternatives at narrow and 2x sizes',
      (tester) async {
    final semantics = tester.ensureSemantics();
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in [
      const Size(320, 640),
      const Size(360, 800),
      const Size(412, 915)
    ]) {
      for (final scale in [1.0, 2.0]) {
        final home = GlobalKey();
        await mount(
            tester,
            const Scaffold(
                body: SingleChildScrollView(
                    padding: EdgeInsets.all(16),
                    child: HomeQuickSectionsGrid())),
            size: size,
            scale: scale,
            boundary: home);
        absentScholars(tester);
        expect(find.text('المصحف الشريف'), findsOneWidget);
        expect(find.text('ختمة القرآن'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture(
            tester, home, 'home_${size.width.toInt()}_${scale.toInt()}x');
        await tester.pumpWidget(const SizedBox());
        final audio = GlobalKey();
        await mount(tester, const AudioScreen(),
            size: size, scale: scale, boundary: audio);
        absentScholars(tester);
        expect(find.byTooltip('مؤقت النوم'), findsOneWidget);
        expect(find.byTooltip('التنزيلات'), findsOneWidget);
        expect(find.byTooltip('الأذكار والأدعية الصوتية'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture(
            tester, audio, 'audio_${size.width.toInt()}_${scale.toInt()}x');
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    }
    semantics.dispose();
  });

  testWidgets(
      'drawer and directory remove exact retired entry but retain radio heritage and Quran destinations',
      (tester) async {
    final semantics = tester.ensureSemantics();
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await mount(
        tester, const Scaffold(drawer: AppNavigationDrawer(), body: SizedBox()),
        size: const Size(800, 1400), boundary: key);
    tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.text('إذاعات القرآن الكريم (MP3Quran)'), 240,
        scrollable: find.byType(Scrollable).last);
    absentScholars(tester);
    expect(find.text('إذاعات القرآن الكريم (MP3Quran)'), findsOneWidget);
    await capture(tester, key, 'drawer_800_1x');
    await tester.pumpWidget(const SizedBox());
    final directory = GlobalKey();
    await mount(tester, const AppScreenDirectoryScreen(),
        size: const Size(800, 1400), boundary: directory);
    await capture(tester, directory, 'directory_800_1x');
    await tester.enterText(find.byType(TextField), 'علماء');
    await tester.pumpAndSettle();
    absentScholars(tester);
    expect(find.textContaining('مجالس كبار العلماء'), findsNothing);
    await tester.enterText(find.byType(TextField), 'مواريث');
    await tester.pumpAndSettle();
    expect(find.text('ميزان الفرائض والمواريث الشرعية'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'legacy shortcut and comprehensive portal do not reintroduce retired library',
      (tester) async {
    final semantics = tester.ensureSemantics();
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(
        tester,
        const Scaffold(
            body: SingleChildScrollView(
                child: HomeShortcutsList(prayerData: null))),
        size: const Size(1080, 2400));
    absentScholars(tester);
    expect(find.text('إذاعات القرآن الكريم'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await mount(
        tester,
        Scaffold(
            body: ComprehensiveLibrariesPortal(
                layoutMode: ScreenStructureMode.values.first,
                onModeChanged: (_) {})),
        size: const Size(1080, 2400));
    absentScholars(tester);
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });
}
