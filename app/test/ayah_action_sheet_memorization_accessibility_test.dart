import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/models/surah.dart';
import 'package:almomin/core/models/ayah.dart';
import 'package:almomin/core/models/memorization_item.dart';
import 'package:almomin/core/services/memorization_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/services/quran_repository.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/features/mushaf/memorization_screen.dart';
import 'package:almomin/features/mushaf/surah_reader_screen.dart';
import 'package:almomin/features/mushaf/widgets/ayah_action_sheet.dart';

const String _kPixelDir =
    r'C:\Users\Dell\.gemini\antigravity\brain\aaa5e77e-874d-485e-8088-962b9e3f1086\repair21_fixed_pixels';
const String _kMaterialIcons =
    r'D:\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf';

final GlobalKey _kRepaintKey = GlobalKey();

Future<void> _loadRealFonts() async {
  final fontFile = File('assets/fonts/Cairo-Regular.ttf');
  if (fontFile.existsSync()) {
    final bytes = fontFile.readAsBytesSync();
    for (final family in const ['Cairo', 'Roboto']) {
      final loader = FontLoader(family);
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
    }
  }
  final amiri = FontLoader('Amiri');
  for (final path in const [
    'assets/fonts/Amiri-Regular.ttf',
    'assets/fonts/Amiri-Bold.ttf'
  ]) {
    final file = File(path);
    if (file.existsSync()) {
      amiri.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
    }
  }
  await amiri.load();

  for (final path in [
    _kMaterialIcons,
    r'D:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
    'assets/fonts/MaterialIcons-Regular.otf',
  ]) {
    final file = File(path);
    if (file.existsSync()) {
      final loader = FontLoader('MaterialIcons');
      loader.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
      await loader.load();
      break;
    }
  }
}

Future<void> _capturePng(WidgetTester tester, String fileName, {double pixelRatio = 1.0}) async {
  await tester.runAsync(() async {
    final boundary =
        _kRepaintKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    Directory(_kPixelDir).createSync(recursive: true);
    File('$_kPixelDir/$fileName').writeAsBytesSync(byteData!.buffer.asUint8List());
  });
}

Widget _buildModalHost({
  required Surah surah,
  required Ayah ayah,
  required double scale,
  bool isDark = false,
}) {
  return RepaintBoundary(
    key: _kRepaintKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: isDark ? AppTheme.darkTheme : AppTheme.lightTheme,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(scale),
            accessibleNavigation: true,
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          ),
        );
      },
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => AyahActionSheet.show(
                ctx,
                surah: surah,
                ayah: ayah,
              ),
              child: const Text('OPEN_ACTION_SHEET'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text('OPEN_ACTION_SHEET'));
  await tester.pumpAndSettle();
  expect(find.byType(AyahActionSheet), findsOneWidget);
}

Future<void> _dismissSheet(WidgetTester tester) async {
  final closeFinder = find.byIcon(Icons.close_rounded);
  expect(closeFinder, findsOneWidget);
  await tester.tap(closeFinder);
  await tester.pumpAndSettle();
  expect(find.byType(AyahActionSheet), findsNothing);
}

Rect _actualSheetScrollClip(WidgetTester tester) {
  final sheetFinder = find.byType(AyahActionSheet);
  expect(sheetFinder, findsOneWidget);
  Rect clip = tester.getRect(sheetFinder);

  final scrollFinder = find.descendant(
    of: sheetFinder,
    matching: find.byType(SingleChildScrollView),
  );
  if (scrollFinder.evaluate().isNotEmpty) {
    final scrollBox = tester.renderObject(scrollFinder.first) as RenderBox;
    final topLeft = scrollBox.localToGlobal(Offset.zero);
    clip = clip.intersect(topLeft & scrollBox.size);
  }
  return clip;
}

void _assertButtonFullyInsideSheetClip(
  WidgetTester tester,
  Finder buttonFinder,
  String actionLabel,
) {
  expect(buttonFinder, findsOneWidget, reason: '$actionLabel button must exist');
  final rect = tester.getRect(buttonFinder);
  final clip = _actualSheetScrollClip(tester);

  expect(clip.isEmpty, isFalse, reason: 'Sheet scroll clip must be non-empty');
  expect(
    rect.left,
    greaterThanOrEqualTo(clip.left - 0.5),
    reason: '$actionLabel left ${rect.left} clipped by ${clip.left}',
  );
  expect(
    rect.right,
    lessThanOrEqualTo(clip.right + 0.5),
    reason: '$actionLabel right ${rect.right} clipped by ${clip.right}',
  );
  expect(
    rect.top,
    greaterThanOrEqualTo(clip.top - 0.5),
    reason: '$actionLabel top ${rect.top} clipped by ${clip.top}',
  );
  expect(
    rect.bottom,
    lessThanOrEqualTo(clip.bottom + 0.5),
    reason: '$actionLabel bottom ${rect.bottom} clipped by ${clip.bottom}',
  );
}

SemanticsNode _findActionNode(WidgetTester tester, String labelSubstring) {
  SemanticsNode? found;
  void visit(SemanticsNode n) {
    final d = n.getSemanticsData();
    if (d.label.contains(labelSubstring) && d.hasAction(SemanticsAction.tap)) {
      found = n;
      return;
    }
    n.visitChildren((c) {
      visit(c);
      return found == null;
    });
  }

  visit(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
  expect(
    found,
    isNotNull,
    reason: 'Expected tappable SemanticsNode containing "$labelSubstring"',
  );
  return found!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Surah fatiha;
  late List<Ayah> fatihaAyahs;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init();
    await MemorizationService.instance.init();
    await _loadRealFonts();

    final surah = await QuranRepository.getSurahById(1);
    expect(surah, isNotNull);
    fatiha = surah!;
    fatihaAyahs = await QuranRepository.getAyahsForSurah(1);
    expect(fatihaAyahs.length, equals(7));
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await MemorizationService.instance.init(forceReload: true);
    await MemorizationService.instance.clearAll();
  });

  tearDown(() async {
    await MemorizationService.instance.clearAll();
  });

  group('Repair 21 — AyahActionSheet Contextual Memorization Status Actions Tests', () {
    testWidgets(
      'Test 1: Contextual reinforcement (تثبيت) via actual modal route: showOnScreen, non-hidden, fully-inside scroll clip, semantic dispatch, right verse, prefs JSON reload, no navigation, clean dismiss',
      (tester) async {
        final ayah2 = fatihaAyahs[1]; // Ayah 2
        final handle = tester.ensureSemantics();
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(_buildModalHost(
          surah: fatiha,
          ayah: ayah2,
          scale: 1.0,
        ));
        await tester.pumpAndSettle();

        // Open actual modal route
        await _openSheet(tester);

        // 1. Initial state
        expect(MemorizationService.instance.hasItem(1, 2), isFalse);

        // 2. Locate "تثبيت" node
        var node = _findActionNode(tester, 'تثبيت');

        // 3. showOnScreen
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          node.id,
          SemanticsAction.showOnScreen,
        );
        await tester.pumpAndSettle();

        // 4. Re-query non-hidden
        node = _findActionNode(tester, 'تثبيت');
        expect(node.getSemanticsData().hasFlag(SemanticsFlag.isHidden), isFalse);

        // 5. Assert real button rect is fully inside sheet scroll clip
        final btnFinder = find.ancestor(
          of: find.text('تثبيت'),
          matching: find.byType(InkWell),
        ).first;
        _assertButtonFullyInsideSheetClip(tester, btnFinder, 'تثبيت');

        // 6. Semantic dispatch
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          node.id,
          SemanticsAction.tap,
        );
        await tester.pumpAndSettle();

        // 7. Assert outcome & right verse
        expect(find.byType(MemorizationScreen), findsNothing, reason: 'NO navigation to MemorizationScreen');
        expect(find.byType(AyahActionSheet), findsOneWidget, reason: 'Modal sheet remains in view');
        expect(find.text('تم تحديد الآية: تحتاج تثبيت ومراجعة'), findsOneWidget);

        final item = MemorizationService.instance.getItem(1, 2);
        expect(item, isNotNull);
        expect(item!.surahId, equals(1));
        expect(item.ayahNumber, equals(2));
        expect(item.lastRating, equals(MemorizationRating.hard));

        // 8. Assert prefs JSON reload
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        final rawJson = prefs.getString('memorization_items_v1');
        expect(rawJson, isNotNull);
        final List decoded = jsonDecode(rawJson!);
        final match = decoded.firstWhere(
          (e) => e['surah_id'] == 1 && e['ayah_number'] == 2,
          orElse: () => null,
        );
        expect(match, isNotNull);
        expect(match['last_rating'], equals(MemorizationRating.hard.name));

        // 9. Clean dismiss
        await _dismissSheet(tester);
        expect(find.text('OPEN_ACTION_SHEET'), findsOneWidget);

        handle.dispose();
      },
    );

    testWidgets(
      'Test 2: Contextual forgotten (نسيت) via actual modal route: showOnScreen, non-hidden, fully-inside scroll clip, semantic dispatch, right verse, prefs JSON reload, no navigation, clean dismiss',
      (tester) async {
        final ayah3 = fatihaAyahs[2]; // Ayah 3
        final handle = tester.ensureSemantics();
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(_buildModalHost(
          surah: fatiha,
          ayah: ayah3,
          scale: 1.0,
        ));
        await tester.pumpAndSettle();

        // Open actual modal route
        await _openSheet(tester);

        // 1. Initial state
        expect(MemorizationService.instance.hasItem(1, 3), isFalse);

        // 2. Locate "نسيت" node
        var node = _findActionNode(tester, 'نسيت');

        // 3. showOnScreen
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          node.id,
          SemanticsAction.showOnScreen,
        );
        await tester.pumpAndSettle();

        // 4. Re-query non-hidden
        node = _findActionNode(tester, 'نسيت');
        expect(node.getSemanticsData().hasFlag(SemanticsFlag.isHidden), isFalse);

        // 5. Assert real button rect is fully inside sheet scroll clip
        final btnFinder = find.ancestor(
          of: find.text('نسيت'),
          matching: find.byType(InkWell),
        ).first;
        _assertButtonFullyInsideSheetClip(tester, btnFinder, 'نسيت');

        // 6. Semantic dispatch
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          node.id,
          SemanticsAction.tap,
        );
        await tester.pumpAndSettle();

        // 7. Assert outcome & right verse
        expect(find.byType(MemorizationScreen), findsNothing);
        expect(find.byType(AyahActionSheet), findsOneWidget);
        expect(find.text('تم تحديد الآية: نسيتها وتحتاج إعادة حفظ'), findsOneWidget);

        final item = MemorizationService.instance.getItem(1, 3);
        expect(item, isNotNull);
        expect(item!.surahId, equals(1));
        expect(item.ayahNumber, equals(3));
        expect(item.lastRating, equals(MemorizationRating.forgot));
        expect(item.leitnerBox, equals(1));

        // 8. Assert prefs JSON reload
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        final rawJson = prefs.getString('memorization_items_v1');
        expect(rawJson, isNotNull);
        final List decoded = jsonDecode(rawJson!);
        final match = decoded.firstWhere(
          (e) => e['surah_id'] == 1 && e['ayah_number'] == 3,
          orElse: () => null,
        );
        expect(match, isNotNull);
        expect(match['last_rating'], equals(MemorizationRating.forgot.name));
        expect(match['leitner_box'], equals(1));

        // 9. Clean dismiss
        await _dismissSheet(tester);
        expect(find.text('OPEN_ACTION_SHEET'), findsOneWidget);

        handle.dispose();
      },
    );

    testWidgets(
      'Test 3: Study route retention: "تحفيظ وتكرار" navigates to MemorizationScreen as intended',
      (tester) async {
        final ayah1 = fatihaAyahs[0];
        final handle = tester.ensureSemantics();
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(_buildModalHost(
          surah: fatiha,
          ayah: ayah1,
          scale: 1.0,
        ));
        await tester.pumpAndSettle();

        await _openSheet(tester);

        var node = _findActionNode(tester, 'تحفيظ وتكرار');
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          node.id,
          SemanticsAction.showOnScreen,
        );
        await tester.pumpAndSettle();

        node = _findActionNode(tester, 'تحفيظ وتكرار');
        final btnFinder = find.ancestor(
          of: find.text('تحفيظ وتكرار'),
          matching: find.byType(InkWell),
        ).first;
        _assertButtonFullyInsideSheetClip(tester, btnFinder, 'تحفيظ وتكرار');

        // Tap "تحفيظ وتكرار"
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          node.id,
          SemanticsAction.tap,
        );
        await tester.pumpAndSettle();

        // Verify study route retention: MemorizationScreen is pushed
        expect(find.byType(MemorizationScreen), findsOneWidget);

        handle.dispose();
      },
    );

    testWidgets(
      'Test 4: Reader integration & clean dismissal: longPress in SurahReaderScreen opens sheet, status is set, and dismissal cleanly returns to verse node',
      (tester) async {
        final handle = tester.ensureSemantics();
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, child) {
            return MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 800),
                textScaler: TextScaler.linear(1.0),
                accessibleNavigation: true,
              ),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: child!,
              ),
            );
          },
          home: SurahReaderScreen(surah: fatiha),
        ));

        // Settle reader
        for (int i = 0; i < 15; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
        }
        await tester.pumpAndSettle();

        // Find Ayah 1 semantics node
        SemanticsNode? a1Node;
        void findA1(SemanticsNode n) {
          if (n.getSemanticsData().label.endsWith(' 1')) {
            a1Node = n;
            return;
          }
          n.visitChildren((c) {
            findA1(c);
            return a1Node == null;
          });
        }
        findA1(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
        expect(a1Node, isNotNull);

        // Long press on Ayah 1 to open AyahActionSheet
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          a1Node!.id,
          SemanticsAction.longPress,
        );
        await tester.pumpAndSettle();
        expect(find.byType(AyahActionSheet), findsOneWidget);

        // Tap "تثبيت" contextually inside the sheet
        var reinforceNode = _findActionNode(tester, 'تثبيت');
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          reinforceNode.id,
          SemanticsAction.showOnScreen,
        );
        await tester.pumpAndSettle();

        reinforceNode = _findActionNode(tester, 'تثبيت');
        expect(reinforceNode.getSemanticsData().hasFlag(SemanticsFlag.isHidden), isFalse);

        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          reinforceNode.id,
          SemanticsAction.tap,
        );
        await tester.pumpAndSettle();

        // Verify status recorded and NO navigation
        expect(MemorizationService.instance.getItem(1, 1)?.lastRating, equals(MemorizationRating.hard));
        expect(find.byType(MemorizationScreen), findsNothing);
        expect(find.byType(AyahActionSheet), findsOneWidget);

        // Dismiss sheet cleanly via close button
        final closeIcon = find.byIcon(Icons.close_rounded);
        expect(closeIcon, findsOneWidget);
        await tester.tap(closeIcon);
        await tester.pumpAndSettle();

        // Verify clean dismissal: sheet is closed, reader is intact
        expect(find.byType(AyahActionSheet), findsNothing);
        expect(find.byType(SurahReaderScreen), findsOneWidget);

        // Re-find Ayah 1 node in reader
        a1Node = null;
        findA1(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
        expect(a1Node, isNotNull, reason: 'Ayah 1 node must remain accessible and clean in reader');

        handle.dispose();
      },
    );

    testWidgets(
      'Test 5: Responsive matrix across 360/412 @ 1x/2x view physicalSize+DPR/reset: actual AyahActionSheet.show route, BOTH new actions showOnScreen, non-hidden, fully-inside scroll clip, zero overflow, and REAL pixel captures',
      (tester) async {
        final ayah2 = fatihaAyahs[1];
        final handle = tester.ensureSemantics();

        final scenarios = [
          (
            id: '360x800_1x',
            size: const Size(360, 800),
            dpr: 1.0,
            scale: 1.0,
            captureName: 'action_sheet_360x800_1x.png',
          ),
          (
            id: '360x800_2x',
            size: const Size(360, 800),
            dpr: 2.0,
            scale: 2.0,
            captureName: 'action_sheet_360x800_2x.png',
          ),
          (
            id: '412x915_1x',
            size: const Size(412, 915),
            dpr: 1.0,
            scale: 1.0,
            captureName: 'action_sheet_412x915_1x.png',
          ),
          (
            id: '412x915_2x',
            size: const Size(412, 915),
            dpr: 2.0,
            scale: 2.0,
            captureName: 'action_sheet_412x915_2x.png',
          ),
        ];

        try {
          for (final sc in scenarios) {
            tester.view.devicePixelRatio = sc.dpr;
            tester.view.physicalSize = Size(sc.size.width * sc.dpr, sc.size.height * sc.dpr);

            await tester.pumpWidget(_buildModalHost(
              surah: fatiha,
              ayah: ayah2,
              scale: sc.scale,
            ));
            await tester.pumpAndSettle();

            // Open actual modal route
            await _openSheet(tester);

            // Assert zero overflow
            expect(tester.takeException(), isNull, reason: 'Zero overflow on ${sc.id}');

            // Verify BOTH new actions showOnScreen, nonhidden, and fully inside sheet scroll clip
            // 1. Action: تثبيت
            var rNode = _findActionNode(tester, 'تثبيت');
            tester.binding.pipelineOwner.semanticsOwner!.performAction(
              rNode.id,
              SemanticsAction.showOnScreen,
            );
            await tester.pumpAndSettle();

            rNode = _findActionNode(tester, 'تثبيت');
            expect(rNode.getSemanticsData().hasFlag(SemanticsFlag.isHidden), isFalse);
            final rBtn = find.ancestor(
              of: find.text('تثبيت'),
              matching: find.byType(InkWell),
            ).first;
            _assertButtonFullyInsideSheetClip(tester, rBtn, '${sc.id} تثبيت');

            // 2. Action: نسيت
            var fNode = _findActionNode(tester, 'نسيت');
            tester.binding.pipelineOwner.semanticsOwner!.performAction(
              fNode.id,
              SemanticsAction.showOnScreen,
            );
            await tester.pumpAndSettle();

            fNode = _findActionNode(tester, 'نسيت');
            expect(fNode.getSemanticsData().hasFlag(SemanticsFlag.isHidden), isFalse);
            final fBtn = find.ancestor(
              of: find.text('نسيت'),
              matching: find.byType(InkWell),
            ).first;
            _assertButtonFullyInsideSheetClip(tester, fBtn, '${sc.id} نسيت');

            // Capture real pixel PNG with DPR
            await _capturePng(tester, sc.captureName, pixelRatio: sc.dpr);

            // Clean dismiss
            await _dismissSheet(tester);
          }
        } finally {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        }

        handle.dispose();
      },
    );
  });
}
