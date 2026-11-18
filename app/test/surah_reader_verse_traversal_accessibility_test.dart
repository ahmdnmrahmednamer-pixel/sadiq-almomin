import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/app/theme/app_theme.dart';
import 'package:almomin/core/audio/ayah_audio_player.dart';
import 'package:almomin/core/models/surah.dart';
import 'package:almomin/core/services/quran_repository.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/features/mushaf/surah_reader_screen.dart';
import 'package:almomin/features/mushaf/widgets/ayah_action_sheet.dart';
import 'package:almomin/features/mushaf/widgets/tafsir_viewer_sheet.dart';
import 'package:almomin/features/mushaf/widgets/ayah_linguistics_sheet.dart';
import 'package:almomin/features/mushaf/widgets/ayah_card_share_sheet.dart';

const String _kPixelDir =
    r'C:\Users\Dell\.gemini\antigravity\brain\aaa5e77e-874d-485e-8088-962b9e3f1086\repair20_fixed_pixels';
const String _kMaterialIcons =
    r'D:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf';

final GlobalKey _kBoundaryKey = GlobalKey();

Future<void> _loadRealFonts() async {
  final cairo = File('assets/fonts/Cairo-Regular.ttf');
  if (cairo.existsSync()) {
    final bytes = cairo.readAsBytesSync();
    for (final family in const ['Cairo', 'Roboto']) {
      final loader = FontLoader(family);
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
    }
  }
  final amiri = FontLoader('Amiri');
  for (final path in const ['assets/fonts/Amiri-Regular.ttf', 'assets/fonts/Amiri-Bold.ttf']) {
    final file = File(path);
    if (file.existsSync()) {
      amiri.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
    }
  }
  await amiri.load();

  final matFile = File(_kMaterialIcons);
  if (matFile.existsSync()) {
    final loader = FontLoader('MaterialIcons');
    loader.addFont(Future.value(ByteData.view(matFile.readAsBytesSync().buffer)));
    await loader.load();
  }
}

Future<void> _settleReader(WidgetTester tester) async {
  for (int i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
  }
  await tester.pumpAndSettle();
}

Future<void> _capturePng(WidgetTester tester, String fileName) async {
  await tester.runAsync(() async {
    final boundary =
        _kBoundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    Directory(_kPixelDir).createSync(recursive: true);
    File('$_kPixelDir/$fileName').writeAsBytesSync(byteData!.buffer.asUint8List());
  });
}

Widget _buildHost({
  required Surah surah,
  required Size size,
  required double scale,
  required bool accessibleNav,
  bool isDark = false,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: isDark ? AppTheme.darkTheme : AppTheme.lightTheme,
    builder: (context, child) {
      final mq = MediaQuery.of(context);
      return MediaQuery(
        data: mq.copyWith(
          size: size,
          textScaler: TextScaler.linear(scale),
          accessibleNavigation: accessibleNav,
          padding: const EdgeInsets.only(top: 24, bottom: 16),
        ),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        ),
      );
    },
    home: RepaintBoundary(
      key: _kBoundaryKey,
      child: SurahReaderScreen(surah: surah),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Surah fatiha;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'reading_display_mode': 'cards',
      'mushaf_font_size': 22.0,
      'auto_play_next_ayah': false,
    });
    await SettingsService.instance.init();
    await _loadRealFonts();
    final surah = await QuranRepository.getSurahById(1);
    expect(surah, isNotNull);
    fatiha = surah!;
  });

  tearDown(() {
    AyahAudioPlayer.instance.resetForTesting();
  });

  group('Repair 20 — SurahReaderScreen Verse Traversal & Accessibility Regression Tests', () {
    testWidgets(
      'Linear traversal matrix (360/412 @ 1x/2x, cards + accessibleNav): actual non-hidden nodes adjacency, clean labels, zero intermediate toolbars',
      (tester) async {
        final configs = [
          (const Size(360, 800), 1.0, true,  false, 'fixed_360x800_1x_accessibleNav.png', '360_1x_accNav'),
          (const Size(360, 800), 2.0, true,  false, 'fixed_360x800_2x_accessibleNav.png', '360_2x_accNav'),
          (const Size(412, 915), 1.0, true,  false, 'fixed_412x915_1x_accessibleNav.png', '412_1x_accNav'),
          (const Size(412, 915), 2.0, true,  true,  'fixed_412x915_2x_accessibleNav.png', '412_2x_accNav'),
          (const Size(360, 800), 1.0, false, false, '',                                     '360_1x_explicitCards'),
        ];

        for (final (size, scale, accNav, isDark, snapName, labelDesc) in configs) {
          final handle = tester.ensureSemantics();
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;

          await tester.pumpWidget(_buildHost(
            surah: fatiha,
            size: size,
            scale: scale,
            accessibleNav: accNav,
            isDark: isDark,
          ));
          await _settleReader(tester);

          // If explicit cards mode without accessibleNav, switch mode via dropdown
          if (!accNav) {
            await tester.tap(find.byType(DropdownButton<String>));
            await tester.pumpAndSettle();
            await tester.tap(find.text('بطاقات الآيات والتفسير').last);
            await _settleReader(tester);
          }

          if (snapName.isNotEmpty) {
            await _capturePng(tester, snapName);
          }

          // Collect actual non-hidden semantics nodes in traversal order
          final List<SemanticsNode> nonHiddenNodes = [];
          void collect(SemanticsNode n) {
            final data = n.getSemanticsData();
            final hasContent = data.label.isNotEmpty ||
                data.hint.isNotEmpty ||
                data.tooltip.isNotEmpty ||
                data.value.isNotEmpty;
            if (hasContent && !data.hasFlag(SemanticsFlag.isHidden)) {
              nonHiddenNodes.add(n);
            }
            n.visitChildren((child) {
              collect(child);
              return true;
            });
          }

          final root = tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!;
          collect(root);

          // Find visible Ayah nodes in non-hidden stream
          final visibleAyahs = nonHiddenNodes.where((n) {
            final lbl = n.getSemanticsData().label;
            return lbl.contains('الرَّحْمَانِ الرَّحِيمِ') || lbl.contains('الْحَمْدُ لِلَّهِ');
          }).toList();

          expect(visibleAyahs, isNotEmpty,
              reason: 'Visible Ayahs must exist in non-hidden semantics stream ($labelDesc)');

          // Ayah 1 checks
          final a1 = visibleAyahs[0];
          final d1 = a1.getSemanticsData();
          expect(d1.label, equals('بِسْمِ اللَّهِ الرَّحْمَانِ الرَّحِيمِ 1'),
              reason: 'Ayah 1 label must be clean verse and number only ($labelDesc)');
          expect(d1.label, isNot(contains('آية ١ / ٧')));
          expect(d1.label, isNot(contains('﴿1﴾')));
          expect(d1.hasAction(SemanticsAction.tap), isTrue);
          expect(d1.hasAction(SemanticsAction.longPress), isTrue);

          // If Ayah 2 is also in non-hidden viewport, verify strict adjacency
          if (visibleAyahs.length >= 2) {
            final a2 = visibleAyahs[1];
            final d2 = a2.getSemanticsData();
            expect(d2.label, equals('الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ 2'),
                reason: 'Ayah 2 label must be clean verse and number only ($labelDesc)');
            expect(d2.label, isNot(contains('آية ٢ / ٧')));
            expect(d2.hasAction(SemanticsAction.tap), isTrue);
            expect(d2.hasAction(SemanticsAction.longPress), isTrue);

            final idx1 = nonHiddenNodes.indexOf(a1);
            final idx2 = nonHiddenNodes.indexOf(a2);
            expect(idx2, equals(idx1 + 1),
                reason: 'Adjacent non-hidden Ayahs must be strictly contiguous with zero intervening nodes ($labelDesc)');
          }

          // Verify zero toolbar buttons exist as semantic stops in non-hidden traversal
          final toolbarTitles = [
            'عرض التفسير الميسر',
            'حفظ في العلامات المرجعية',
            'معاني الكلمات، غريب القرآن، وأسباب النزول',
            'تصميم ومشاركة بطاقة دعوية للآية (صورة)',
            'خيارات الآية، التكرار، والنسخ',
          ];
          for (final title in toolbarTitles) {
            final found = nonHiddenNodes.any((n) {
              final data = n.getSemanticsData();
              return data.tooltip == title || data.label == title;
            });
            expect(found, isFalse,
                reason: 'Toolbar button "$title" must not be in traversal stream ($labelDesc)');
          }

          handle.dispose();
        }
      },
    );

    testWidgets(
      'Scroll to later verses at 2x: reachability, visible rect, semantic showOnScreen, zero intermediate toolbars, and 2x scrolled captures',
      (tester) async {
        final configs = [
          (const Size(360, 800), 2.0, false, 'fixed_360x800_2x_scrolled_accessibleNav.png'),
          (const Size(412, 915), 2.0, true,  'fixed_412x915_2x_scrolled_accessibleNav.png'),
        ];

        for (final (size, scale, isDark, snapName) in configs) {
          final handle = tester.ensureSemantics();
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;

          await tester.pumpWidget(_buildHost(
            surah: fatiha,
            size: size,
            scale: scale,
            accessibleNav: true,
            isDark: isDark,
          ));
          await _settleReader(tester);

          // 1. Drag ListView to reveal later verses
          await tester.drag(find.byType(ListView), const Offset(0, -700));
          await tester.pumpAndSettle();

          // Capture 2x scrolled pixel snapshot
          await _capturePng(tester, snapName);

          // 2. Collect non-hidden nodes after scroll
          final List<SemanticsNode> nonHiddenAfterScroll = [];
          void collectNonHidden(SemanticsNode n) {
            final data = n.getSemanticsData();
            final hasContent = data.label.isNotEmpty ||
                data.hint.isNotEmpty ||
                data.tooltip.isNotEmpty ||
                data.value.isNotEmpty;
            if (hasContent && !data.hasFlag(SemanticsFlag.isHidden)) {
              nonHiddenAfterScroll.add(n);
            }
            n.visitChildren((child) {
              collectNonHidden(child);
              return true;
            });
          }
          collectNonHidden(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);

          // Find scrolled visible ayahs
          final scrolledAyahs = nonHiddenAfterScroll.where((n) {
            final lbl = n.getSemanticsData().label;
            return lbl.contains('الرَّحْمَانِ الرَّحِيمِ 3') ||
                   lbl.contains('مَالِكِ يَوْمِ الدِّينِ 4') ||
                   lbl.contains('إِيَّاكَ نَعْبُدُ') ||
                   lbl.contains('اهْدِنَا الصِّرَاطَ') ||
                   lbl.contains('صِرَاطَ الَّذِينَ');
          }).toList();

          expect(scrolledAyahs, isNotEmpty,
              reason: 'Later verses must be visible in non-hidden semantics tree after scroll at $size');

          for (int i = 0; i < scrolledAyahs.length - 1; i++) {
            final curr = scrolledAyahs[i];
            final next = scrolledAyahs[i + 1];
            final cIdx = nonHiddenAfterScroll.indexOf(curr);
            final nIdx = nonHiddenAfterScroll.indexOf(next);
            expect(nIdx, equals(cIdx + 1),
                reason: 'Later verses must remain strictly contiguous with zero intervening toolbar stops');
          }

          // 3. Verify target revealed verse is accessible, showOnScreen, and rect intersects ListView clip meaningfully
          final targetNode = scrolledAyahs.first;
          final targetLabel = targetNode.getSemanticsData().label;
          expect(targetLabel, matches(RegExp(r'^.+ [2-7]$')),
              reason: 'Target text must be complete clean verse and number only');
          expect(targetNode.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
          expect(targetNode.getSemanticsData().hasAction(SemanticsAction.longPress), isTrue);

          tester.binding.pipelineOwner.semanticsOwner!.performAction(targetNode.id, SemanticsAction.showOnScreen);
          await tester.pumpAndSettle();

          final targetFinder = find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == targetLabel,
          );
          expect(targetFinder, findsOneWidget, reason: 'Target verse widget must be rendered');

          final listFinder = find.byType(ListView).first;
          final listRect = tester.getRect(listFinder);
          final targetRect = tester.getRect(targetFinder);
          final intersection = targetRect.intersect(listRect);
          expect(intersection.isEmpty, isFalse,
              reason: 'Target verse rect must intersect actual ListView viewport clip');
          expect(intersection.height, greaterThanOrEqualTo(50.0),
              reason: 'Target verse must have meaningful visible height inside ListView clip');
          expect(targetRect.top, greaterThanOrEqualTo(listRect.top - 2.0),
              reason: 'Target verse top must be contained within or at ListView clip top after showOnScreen');
          expect(targetRect.bottom, lessThanOrEqualTo(listRect.bottom + 2.0),
              reason: 'Target verse bottom must be contained within ListView clip after showOnScreen');

          handle.dispose();
        }
      },
    );

    testWidgets(
      'Semantics tap action: executes through mocked audio plugin boundary (play selected2 and stop without production edits)',
      (tester) async {
        final handle = tester.ensureSemantics();
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.reset());

        // Intercept at platform channel boundary of just_audio
        final List<String> recordedMethodCalls = [];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.just_audio.methods'),
          (MethodCall call) async {
            recordedMethodCalls.add(call.method);
            if (call.method == 'init') {
              return {'id': 'test_player_id'};
            }
            return {};
          },
        );

        // Mock FastAudioService resilient player runner (plugin boundary)
        int playCallCount = 0;
        String? playedKey;
        int stopCallCount = 0;

        AyahAudioPlayer.instance.playResilientRunner = (
          positionalPrimaryUrl, {
          player,
          primaryUrl,
          fallbackUrls = const [],
          cacheKey,
          localDownloadedPath,
          onStopCallback,
        }) async {
          playCallCount++;
          playedKey = cacheKey;
          return true;
        };

        AyahAudioPlayer.instance.stopPlayerRunner = () async {
          stopCallCount++;
        };

        await tester.pumpWidget(_buildHost(
          surah: fatiha,
          size: const Size(360, 800),
          scale: 1.0,
          accessibleNav: true,
        ));
        await _settleReader(tester);

        // Find Ayah 2 semantics node
        SemanticsNode? a2Node;
        void findA2(SemanticsNode n) {
          if (n.getSemanticsData().label == 'الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ 2') {
            a2Node = n;
            return;
          }
          n.visitChildren((child) {
            findA2(child);
            return a2Node == null;
          });
        }
        findA2(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
        expect(a2Node, isNotNull, reason: 'Ayah 2 semantics node must exist');

        // Initially stopped
        expect(AyahAudioPlayer.instance.currentPlayingKey.value, isNull);
        expect(playCallCount, equals(0));

        // 1. Dispatch SemanticsAction.tap to play selected Ayah 2
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          a2Node!.id,
          SemanticsAction.tap,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(AyahAudioPlayer.instance.currentPlayingKey.value, equals('1:2'),
            reason: 'Current playing key must be set to 1:2 for selected Ayah 2');
        expect(playCallCount, equals(1));
        expect(playedKey, contains('1_2'));

        // 2. Dispatch SemanticsAction.tap again to stop playback
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          a2Node!.id,
          SemanticsAction.tap,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(AyahAudioPlayer.instance.currentPlayingKey.value, isNull,
            reason: 'Current playing key must be cleared after stop');
        expect(stopCallCount, greaterThanOrEqualTo(1));

        // Clean up platform handler
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.just_audio.methods'),
          null,
        );

        handle.dispose();
      },
    );

    testWidgets(
      'Semantics long-press action: context tools (Tafsir, Bookmark, Linguistics, Card, Options) are reachable non-hidden actions, showOnScreen + activated with verified outcomes, and clean close returns to verse node',
      (tester) async {
        final handle = tester.ensureSemantics();
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.reset());

        // Mock clipboard platform channel for copy action side-effects
        String? lastCopiedText;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          SystemChannels.platform,
          (MethodCall call) async {
            if (call.method == 'Clipboard.setData') {
              lastCopiedText = (call.arguments as Map)['text'] as String?;
              return null;
            }
            return null;
          },
        );
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });

        await tester.pumpWidget(_buildHost(
          surah: fatiha,
          size: const Size(360, 800),
          scale: 1.0,
          accessibleNav: true,
        ));
        await _settleReader(tester);

        // Helper: locate Ayah 1 semantics node with non-hidden check
        SemanticsNode getAyah1Node() {
          SemanticsNode? found;
          void search(SemanticsNode n) {
            final d = n.getSemanticsData();
            if (d.label == 'بِسْمِ اللَّهِ الرَّحْمَانِ الرَّحِيمِ 1' &&
                !d.hasFlag(SemanticsFlag.isHidden)) {
              found = n;
              return;
            }
            n.visitChildren((c) {
              search(c);
              return found == null;
            });
          }
          search(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
          expect(found, isNotNull, reason: 'Ayah 1 node must be present and non-hidden');
          return found!;
        }

        // Helper: open AyahActionSheet via longPress on Ayah 1
        Future<void> openSheet() async {
          final a1 = getAyah1Node();
          tester.binding.pipelineOwner.semanticsOwner!.performAction(
            a1.id,
            SemanticsAction.longPress,
          );
          await tester.pumpAndSettle();
          expect(find.byType(AyahActionSheet), findsOneWidget);
        }

        // Helper: find tool node, dispatch showOnScreen, verify non-hidden, dispatch tap
        Future<void> activateTool(String labelMatch) async {
          SemanticsNode? toolNode;
          void findNode(SemanticsNode n) {
            final d = n.getSemanticsData();
            if ((d.label.contains(labelMatch) || d.tooltip.contains(labelMatch)) &&
                d.hasAction(SemanticsAction.tap)) {
              toolNode = n;
              return;
            }
            n.visitChildren((c) {
              findNode(c);
              return toolNode == null;
            });
          }
          findNode(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
          expect(toolNode, isNotNull, reason: 'Tool node matching "$labelMatch" must exist in sheet');

          // 1. Dispatch showOnScreen
          tester.binding.pipelineOwner.semanticsOwner!.performAction(
            toolNode!.id,
            SemanticsAction.showOnScreen,
          );
          await tester.pumpAndSettle();

          // 2. Re-locate node to verify it is non-hidden after showOnScreen
          toolNode = null;
          findNode(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
          expect(toolNode, isNotNull);
          expect(toolNode!.getSemanticsData().hasFlag(SemanticsFlag.isHidden), isFalse,
              reason: 'Tool "$labelMatch" must be non-hidden after showOnScreen');

          // 3. Dispatch tap
          tester.binding.pipelineOwner.semanticsOwner!.performAction(
            toolNode!.id,
            SemanticsAction.tap,
          );
          await tester.pumpAndSettle();
        }

        // Helper: verify clean close and return to Ayah 1 verse node
        void assertCleanCloseVerseNode() {
          expect(find.byType(AyahActionSheet), findsNothing, reason: 'AyahActionSheet must be closed');
          final a1 = getAyah1Node();
          final d = a1.getSemanticsData();
          expect(d.hasFlag(SemanticsFlag.isHidden), isFalse);
          expect(d.label, equals('بِسْمِ اللَّهِ الرَّحْمَانِ الرَّحِيمِ 1'));
          expect(d.hasAction(SemanticsAction.tap), isTrue);
          expect(d.hasAction(SemanticsAction.longPress), isTrue);
        }

        // 1. Tool: Bookmark (إشارة مرجعية)
        expect(SettingsService.instance.isBookmarked(1, 1), isFalse);
        await openSheet();
        await activateTool('إشارة مرجعية');
        expect(SettingsService.instance.isBookmarked(1, 1), isTrue,
            reason: 'Bookmark tool tap must toggle bookmark state to true');
        // Dismiss sheet cleanly via Navigator.pop
        Navigator.of(tester.element(find.byType(AyahActionSheet))).pop();
        await tester.pumpAndSettle();
        assertCleanCloseVerseNode();

        // 2. Tool: Tafsir (التفسير والشروح)
        await openSheet();
        await activateTool('التفسير والشروح');
        expect(find.byType(TafsirViewerSheet), findsOneWidget,
            reason: 'Tafsir tool tap must push TafsirViewerSheet');
        // Dismiss TafsirViewerSheet cleanly
        Navigator.of(tester.element(find.byType(TafsirViewerSheet))).pop();
        await tester.pumpAndSettle();
        assertCleanCloseVerseNode();

        // 3. Tool: Linguistics (معاني الكلمات)
        await openSheet();
        await activateTool('معاني الكلمات');
        expect(find.byType(AyahLinguisticsSheet), findsOneWidget,
            reason: 'Linguistics tool tap must push AyahLinguisticsSheet');
        // Dismiss AyahLinguisticsSheet cleanly
        Navigator.of(tester.element(find.byType(AyahLinguisticsSheet))).pop();
        await tester.pumpAndSettle();
        assertCleanCloseVerseNode();

        // 4. Tool: Card (بطاقة دعوية)
        await openSheet();
        await activateTool('بطاقة دعوية');
        expect(find.byType(AyahCardShareSheet), findsOneWidget,
            reason: 'Card share tool tap must push AyahCardShareSheet');
        // Dismiss AyahCardShareSheet cleanly
        Navigator.of(tester.element(find.byType(AyahCardShareSheet))).pop();
        await tester.pumpAndSettle();
        assertCleanCloseVerseNode();

        // 5. Tool: Options / Copy (نسخ الآية)
        await openSheet();
        await activateTool('نسخ الآية');
        expect(lastCopiedText, contains('بِسۡمِ ٱللَّهِ ٱلرَّحۡمَـٰنِ ٱلرَّحِیمِ'),
            reason: 'Copy action must set clipboard data to verse text');
        expect(find.text('تم نسخ الآية الكريمة بنجاح'), findsOneWidget,
            reason: 'Copy action must display confirmation SnackBar');
        // Copy automatically pops AyahActionSheet in _copyAyah()
        assertCleanCloseVerseNode();

        handle.dispose();
      },
    );

    testWidgets(
      'Visual touch preservation: visual buttons remain accessible and functional for pointer touch',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.reset());

        await tester.pumpWidget(_buildHost(
          surah: fatiha,
          size: const Size(360, 800),
          scale: 1.0,
          accessibleNav: true,
        ));
        await _settleReader(tester);

        // Verify visual buttons exist in the widget tree despite ExcludeSemantics
        expect(find.byTooltip('عرض التفسير الميسر'), findsWidgets);
        expect(find.byTooltip('حفظ في العلامات المرجعية'), findsWidgets);
        expect(find.byTooltip('معاني الكلمات، غريب القرآن، وأسباب النزول'), findsWidgets);
        expect(find.byTooltip('تصميم ومشاركة بطاقة دعوية للآية (صورة)'), findsWidgets);
        expect(find.byTooltip('خيارات الآية، التكرار، والنسخ'), findsWidgets);

        // Tap visual tafsir button to expand inline tafsir
        final tafsirBtn = find.byTooltip('عرض التفسير الميسر').first;
        await tester.tap(tafsirBtn);
        await tester.pumpAndSettle();

        expect(find.text('التفسير الميسر:'), findsOneWidget);

        // Tap again to collapse
        await tester.tap(find.byTooltip('إخفاء التفسير الميسر').first);
        await tester.pumpAndSettle();

        expect(find.text('التفسير الميسر:'), findsNothing);
      },
    );
  });
}