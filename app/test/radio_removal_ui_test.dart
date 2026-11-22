import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/core/ui/adaptive_screen_layouts.dart';
import 'package:almomin/features/egypt/egyptian_heritage_screen.dart';
import 'package:almomin/features/egypt/widgets/egypt_adaptive_hub_view.dart';
import 'package:almomin/features/home/widgets/home_shortcuts_list.dart';
import 'package:almomin/features/home/screens/app_screen_directory_screen.dart';
import 'package:almomin/app/widgets/app_navigation_drawer.dart';

Future<void> capture(WidgetTester t, GlobalKey key, String name) async {
  const directory = String.fromEnvironment('RADIO_REMOVAL_PIXELS');
  if (directory.isEmpty) return;
  await t.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
            .toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(directory).createSync(recursive: true);
    await File('$directory/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final family in ['Cairo', 'Amiri']) {
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
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(
                ByteData.sublistView(File(icons).readAsBytesSync()))))
          .load();
    }
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'app_language': 'ar', 'notif_master_enabled': false});
    await SettingsService.instance.init(forceReload: true);
  });

  Future<GlobalKey> mount(
      WidgetTester t, Widget page, AppThemeMode mode, double scale) async {
    t.view.physicalSize = const Size(360, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.of(mode),
          builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: Directionality(
                  textDirection: TextDirection.rtl, child: child!)),
          home: page,
        )));
    await t.pumpAndSettle();
    return key;
  }

  for (final mode in AppThemeMode.values) {
    testWidgets(
        'retained heritage has three tabs and no radio at 2x ${mode.name}',
        (t) async {
      final semantics = t.ensureSemantics();
      try {
        final key = await mount(t, const EgyptianHeritageScreen(), mode, 2);
        expect(find.byType(Tab), findsNWidgets(3));
        expect(find.text('إذاعة القرآن الكريم'), findsNothing);
        expect(find.text('التراث المصري'), findsOneWidget);
        expect(find.text('الابتهالات والشعراوي'), findsOneWidget);
        expect(t.takeException(), isNull);
        await capture(t, key, 'heritage-${mode.name}-2x');
        await t.tap(find.byTooltip('عرض البوابة المهيكلة'));
        await t.pumpAndSettle();
        final collection = t.widget<AdaptiveStructuredCollectionView>(
            find.byType(AdaptiveStructuredCollectionView));
        expect(collection.items.map((e) => e.id),
            ['eg_hub_ibtihalat', 'eg_hub_mosques', 'eg_hub_fatwas']);
        expect(t.takeException(), isNull);
        await capture(t, key, 'heritage-overview-${mode.name}-2x');
      } finally {
        semantics.dispose();
      }
    });
  }

  for (final mode in AppThemeMode.values) {
    testWidgets(
        'all retained tabs scroll into view with selected semantics in empty favorites at 2x ${mode.name}',
        (t) async {
      final handle = t.ensureSemantics();
      try {
        final key = await mount(t, const EgyptianHeritageScreen(), mode, 2);
        // Empty favorites isolates navigation from unchanged content-card layout.
        await t.tap(find.byTooltip('المفضلة فقط'));
        await t.pumpAndSettle();
        const labels = [
          'الابتهالات والشعراوي',
          'مساجد مصر التاريخية',
          'فتاوى دار الإفتاء'
        ];
        for (var index = 0; index < labels.length; index++) {
          final label = labels[index];
          final target = find.text(label);
          var rect = t.getRect(target);
          for (var attempt = 0;
              attempt < 8 && (rect.left < 0 || rect.right > 360);
              attempt++) {
            // A real drag on the horizontally scrollable RTL tab strip, not
            // direct controller selection or programmatic ensureVisible.
            await t.drag(
                find.byType(TabBar), Offset(rect.left < 0 ? 140 : -140, 0));
            await t.pumpAndSettle();
            rect = t.getRect(target);
          }
          expect(rect.left, greaterThanOrEqualTo(0),
              reason: '$label must be fully reachable');
          expect(rect.right, lessThanOrEqualTo(360),
              reason: '$label must be fully reachable');
          await t.tap(target);
          await t.pumpAndSettle();
          expect(
              t.widget<TabBar>(find.byType(TabBar)).controller!.index, index);
          final matching = <SemanticsNode>[];
          void visit(SemanticsNode node) {
            if (node.getSemanticsData().label.contains(label)) { matching.add(node); }
            node.visitChildren((child) {
              visit(child);
              return true;
            });
          }

          visit(t.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
          expect(
              matching.any((n) =>
                  n.getSemanticsData().hasFlag(ui.SemanticsFlag.isSelected)),
              isTrue,
              reason: '$label must expose selected semantics after activation');
          expect(t.takeException(), isNull);
          await capture(t, key, 'tab-$index-${mode.name}-2x-empty-favorites');
        }
      } finally {
        handle.dispose();
      }
    });
  }

  for (final mode in ScreenStructureMode.values) {
    testWidgets(
        'remaining heritage hub maps each item to its shifted tab ${mode.name}',
        (t) async {
      final selected = <int>[];
      await mount(
          t,
          Scaffold(
              body: SingleChildScrollView(
                  child: EgyptAdaptiveHubView(
                      mode: mode, onSelectTab: selected.add))),
          AppThemeMode.light,
          1);
      final items = t
          .widget<AdaptiveStructuredCollectionView>(
              find.byType(AdaptiveStructuredCollectionView))
          .items;
      expect(items.length, 3);
      for (final item in items) {
        item.onTap();
      }
      expect(selected, [0, 1, 2]);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets(
      'home no longer advertises radio and retains heritage at normal scale',
      (t) async {
    final key = await mount(
        t,
        const Scaffold(
            body: SingleChildScrollView(
                child: HomeShortcutsList(prayerData: null))),
        AppThemeMode.dark,
        1);
    expect(find.byKey(const Key('home_islamic_radio_banner_semantics')),
        findsNothing);
    expect(find.text('التراث المصري'), findsOneWidget);
    expect(t.takeException(), isNull);
    await capture(t, key, 'home-dark-normal');
  });

  testWidgets('directory has no radio results but retains searchable heritage',
      (t) async {
    final key =
        await mount(t, const AppScreenDirectoryScreen(), AppThemeMode.light, 1);
    await t.enterText(find.byType(TextField), 'إذاعات');
    await t.pumpAndSettle();
    expect(find.text('إذاعات القرآن الكريم (MP3Quran)'), findsNothing);
    await capture(t, key, 'directory-no-radio');
    await t.enterText(find.byType(TextField), 'التراث');
    await t.pumpAndSettle();
    expect(find.text('التراث المصري'), findsOneWidget);
    expect(t.takeException(), isNull);
    await capture(t, key, 'directory-heritage');
  });

  testWidgets('drawer removes live-radio destination and retains heritage',
      (t) async {
    final key = await mount(
        t,
        const Scaffold(drawer: AppNavigationDrawer(), body: Text('الرئيسية')),
        AppThemeMode.light,
        1);
    t.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'تراث');
    await t.pumpAndSettle();
    expect(find.text('الإذاعة'), findsNothing);
    expect(find.text('التراث المصري'), findsOneWidget);
    expect(t.takeException(), isNull);
    await capture(t, key, 'drawer-heritage');
  });
}
