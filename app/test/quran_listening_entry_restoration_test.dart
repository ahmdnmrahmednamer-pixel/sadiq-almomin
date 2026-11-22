import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/audio/fast_audio_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/services/quran_repository.dart';
import 'package:almomin/core/ui/portal_category_card.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/features/audio/audio_screen.dart';
import 'package:almomin/features/mushaf/quran_hub_screen.dart';
import 'zero_delay_owner_audit_test.dart' show RecordingPlayer;

class ListeningProbePlayer extends RecordingPlayer {
  bool active = false;
  @override
  bool get playing => active;
  @override
  Future<void> play() async {
    active = true;
    await super.play();
  }

  @override
  Future<void> stop() async {
    await super.stop();
    active = false;
  }

  @override
  Future<void> pause() async {
    active = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final engine = FastAudioService.instance;

  setUpAll(() async {
    directory = Directory.systemTemp.createTempSync('quran-listening-entry-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => directory.path,
    );
    for (final family in ['Cairo', 'Amiri']) {
      await (FontLoader(family)
            ..addFont(Future.value(ByteData.sublistView(
                File('assets/fonts/$family-Regular.ttf').readAsBytesSync()))))
          .load();
    }
    const icons = String.fromEnvironment('MATERIAL_ICONS_FONT');
    if (icons.isNotEmpty) {
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(
                ByteData.sublistView(File(icons).readAsBytesSync()))))
          .load();
    }
    await QuranRepository.loadSurahs();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init(forceReload: true);
    engine.resetForTesting();
  });
  tearDown(engine.resetForTesting);
  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    directory.deleteSync(recursive: true);
  });

  Finder listeningCard() => find.byWidgetPredicate((widget) =>
      widget is PortalCategoryCard && widget.title == 'القرآن المسموع');

  Future<void> showListeningCard(WidgetTester tester) async {
    await tester.scrollUntilVisible(listeningCard(), 220,
        scrollable: find.byType(Scrollable).first, maxScrolls: 30);
    await tester.ensureVisible(listeningCard());
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    const dir = String.fromEnvironment('QURAN_LISTENING_REVIEW_DIR');
    if (dir.isEmpty) return;
    final boundary = tester
            .renderObject(find.byKey(const ValueKey('quran-listening-pixels')))
        as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(dir).createSync(recursive: true);
      File('$dir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> mount(WidgetTester tester, GoRouter router,
      {double width = 360, double scale = 1, bool dark = false}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(RepaintBoundary(
      key: const ValueKey('quran-listening-pixels'),
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child:
              Directionality(textDirection: TextDirection.rtl, child: child!),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 360.0, 412.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final dark in [false, true]) {
        testWidgets('listening entry is reachable at $width/$scale dark=$dark',
            (tester) async {
          final semantics = tester.ensureSemantics();
          final router = GoRouter(initialLocation: '/mushaf', routes: [
            GoRoute(
                path: '/mushaf', builder: (_, __) => const QuranHubScreen()),
            GoRoute(
                path: '/audio',
                builder: (_, __) =>
                    const Scaffold(body: Text('LISTENING_ROUTE'))),
          ]);
          try {
            await mount(tester, router, width: width, scale: scale, dark: dark);
            if (width == 360 && scale == 2 && !dark) {
              await capture(tester, 'hub-entry-before-scroll');
            }
            await showListeningCard(tester);
            final rect = tester.getRect(listeningCard());
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(width));
            expect(rect.top, greaterThanOrEqualTo(0));
            expect(rect.bottom, lessThanOrEqualTo(900));
            expect(rect.height, greaterThanOrEqualTo(48));
            expect(tester.takeException(), isNull);
            if (scale == 2 && width == 360) {
              await capture(
                  tester, 'hub-listening-${dark ? 'dark' : 'light'}-2x');
            }
            final node = tester.getSemantics(listeningCard());
            expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
                isTrue);
            tester.binding.pipelineOwner.semanticsOwner!
                .performAction(node.id, ui.SemanticsAction.tap);
            await tester.pumpAndSettle();
            expect(find.text('LISTENING_ROUTE'), findsOneWidget);
            expect(
                GoRouterState.of(tester.element(find.text('LISTENING_ROUTE')))
                    .uri
                    .path,
                '/audio');
            router.pop();
            await tester.pumpAndSettle();
            await showListeningCard(tester);
            await tester.tap(listeningCard());
            await tester.pumpAndSettle();
            expect(find.text('LISTENING_ROUTE'), findsOneWidget);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox());
            semantics.dispose();
            router.dispose();
          }
        });
      }
    }
  }

  for (final id in ['minshawi_murattal', 'husary', 'abdulbasit_murattal']) {
    for (final semanticTap in [false, true]) {
      testWidgets(
          'hub to whole-surah autoplay uses saved $id semantic=$semanticTap',
          (tester) async {
        await SettingsService.instance.setSelectedReciter(id);
        final player = ListeningProbePlayer();
        final requested = <(String, String)>[];
        final semantics = tester.ensureSemantics();
        final router = GoRouter(initialLocation: '/mushaf', routes: [
          GoRoute(path: '/mushaf', builder: (_, __) => const QuranHubScreen()),
          GoRoute(
            path: '/audio',
            builder: (_, __) => AudioScreen(
              player: player,
              loadSource: (url, key) async {
                requested.add((url, key));
                return AudioSource.uri(Uri.parse(url));
              },
            ),
          ),
        ]);
        try {
          await mount(tester, router, scale: 2, dark: true);
          await showListeningCard(tester);
          await tester.tap(listeningCard());
          await tester.pumpAndSettle();
          expect(find.byType(AudioScreen), findsOneWidget);
          expect(requested, isEmpty,
              reason: 'Opening listening must not start an unselected surah');
          expect(SettingsService.instance.currentReciter.id, id);
          final target = find.text('سورة الفاتحة');
          await tester.scrollUntilVisible(target, 220,
              scrollable: find.byType(Scrollable).first, maxScrolls: 30);
          await tester.ensureVisible(target);
          await tester.pumpAndSettle();
          if (semanticTap) {
            final node = tester.getSemantics(find.ancestor(
              of: target,
              matching: find.byType(ListTile),
            ));
            expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
                isTrue);
            tester.binding.pipelineOwner.semanticsOwner!
                .performAction(node.id, ui.SemanticsAction.tap);
          } else {
            await tester.tap(target);
          }
          await tester.pumpAndSettle();
          expect(requested, [
            (SettingsService.instance.getSurahAudioUrl(1, id), 'surah_${id}_1')
          ]);
          expect(requested.single.$1, endsWith('/001.mp3'));
          expect(player.sourceAssignments, 1);
          expect(player.starts, 1,
              reason:
                  'One surah activation must start the full recording without a second play action');
          expect(find.byType(BottomSheet), findsNothing);
          expect(find.byTooltip('إيقاف التلاوة'), findsOneWidget);
          expect(tester.takeException(), isNull);
          if (id == 'minshawi_murattal' && !semanticTap) {
            await tester.pump(const Duration(seconds: 3));
            await tester.pumpAndSettle();
            await capture(tester, 'listening-autoplay-dark-2x');
          }
          final longSurah = find.text('سورة البقرة');
          await tester.scrollUntilVisible(longSurah, 220,
              scrollable: find.byType(Scrollable).first, maxScrolls: 30);
          await tester.ensureVisible(longSurah);
          await tester.pumpAndSettle();
          if (semanticTap) {
            final node = tester.getSemantics(find.ancestor(
              of: longSurah,
              matching: find.byType(ListTile),
            ));
            expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
                isTrue);
            tester.binding.pipelineOwner.semanticsOwner!
                .performAction(node.id, ui.SemanticsAction.tap);
          } else {
            await tester.tap(longSurah);
          }
          await tester.pumpAndSettle();
          expect(requested.last, (
            SettingsService.instance.getSurahAudioUrl(2, id),
            'surah_${id}_2'
          ));
          expect(requested.last.$1, endsWith('/002.mp3'));
          expect(requested, hasLength(2));
          expect(player.sourceAssignments, 2);
          expect(player.starts, 2);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
          semantics.dispose();
          router.dispose();
        }
      });
    }
  }
}
