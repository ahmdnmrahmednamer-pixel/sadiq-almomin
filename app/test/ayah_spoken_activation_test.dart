import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/audio/ayah_audio_player.dart';
import 'package:almomin/core/audio/fast_audio_service.dart';
import 'package:almomin/core/services/quran_repository.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/features/mushaf/page_mode_mushaf_screen.dart';
import 'package:almomin/features/mushaf/surah_reader_screen.dart';
import 'package:almomin/core/gestures/ayah_gesture_recognizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final pageMode in [false, true]) {
    testWidgets(
        'current ${pageMode ? 'page' : 'surah'} reader semantic activation plays and stops first ayah',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.instance.init(forceReload: true);
      await tester.runAsync(() async {
        await QuranRepository.loadSurahs();
        await QuranRepository.getAyahsForSurah(1);
        await QuranRepository.getAyahsForPage(1);
      });
      final surah = (await QuranRepository.loadSurahs()).first;
      final player = AyahAudioPlayer.instance;
      final engine = FastAudioService.instance;
      player.resetForTesting();
      engine.resetForTesting();
      final played = <String>[];
      player.stopPlayerRunner = () async {};
      player.prefetchAudioRunner = (_, __) {};
      player.playResilientRunner = (url,
          {player,
          primaryUrl,
          fallbackUrls = const [],
          cacheKey,
          localDownloadedPath,
          onStopCallback}) async {
        played.add(cacheKey!);
        return true;
      };
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(MaterialApp(
            home: pageMode
                ? const PageModeMushafScreen(initialPage: 1)
                : SurahReaderScreen(surah: surah)));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        List<SemanticsNode> targets() {
          final nodes = <SemanticsNode>[];
          void visit(SemanticsNode node) {
            if (node.label.contains('بِسْمِ') &&
                node.getSemanticsData().hasAction(ui.SemanticsAction.tap))
              nodes.add(node);
            node.visitChildren((child) {
              visit(child);
              return true;
            });
          }

          tester.binding.rootPipelineOwner.visitChildren((owner) {
            final root = owner.semanticsOwner?.rootSemanticsNode;
            if (root != null) visit(root);
          });
          return nodes;
        }

        expect(targets(), hasLength(1));
        var node = targets().single;
        node.owner!.performAction(node.id, ui.SemanticsAction.tap);
        await tester.pumpAndSettle();
        expect(player.currentPlayingKey.value, '1:1');
        expect(played, hasLength(1));
        node = targets().single;
        node.owner!.performAction(node.id, ui.SemanticsAction.tap);
        await tester.pumpAndSettle();
        expect(player.currentPlayingKey.value, isNull);
        expect(played, hasLength(1));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        semantics.dispose();
        player.resetForTesting();
        engine.resetForTesting();
      }
    });
  }
  for (final action in ['tap', 'hold', 'cancel', 'dispose']) {
    testWidgets('recognizer pointer lifecycle $action remains single action',
        (tester) async {
      var taps = 0, holds = 0;
      final recognizer = AyahGestureRecognizer(
          onAyahTap: () => taps++, onAyahLongPress: () => holds++);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Center(
                  child: RichText(
                      text: TextSpan(
                          text: 'الحمد لله',
                          style: const TextStyle(fontSize: 24),
                          recognizer: recognizer))))));
      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(RichText)));
      await tester.pump(const Duration(milliseconds: 150));
      if (action == 'dispose') {
        await tester.pumpWidget(const SizedBox.shrink());
        recognizer.dispose();
        await tester.pump(const Duration(seconds: 1));
        await gesture.up();
        expect(taps, 0);
        expect(holds, 0);
        return;
      }
      if (action == 'cancel') {
        await gesture.cancel();
        await tester.pump(const Duration(seconds: 1));
        expect(taps, 0);
        expect(holds, 0);
      } else if (action == 'hold') {
        await tester.pump(const Duration(seconds: 1));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(taps, 0);
        expect(holds, 1);
        await tester.tap(find.byType(RichText));
        await tester.pumpAndSettle();
        expect(taps, 1);
        expect(holds, 1);
      } else {
        await gesture.up();
        await tester.pump(const Duration(seconds: 1));
        expect(taps, 1);
        expect(holds, 0);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      recognizer.dispose();
    });
  }
  for (final number in [false, true]) {
    testWidgets('ayah ${number ? 'number' : 'text'} span exposes semantic tap',
        (tester) async {
      var taps = 0, holds = 0;
      final recognizer = AyahGestureRecognizer(
          onAyahTap: () => taps++, onAyahLongPress: () => holds++);
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: Center(
                    child: RichText(
                        text: TextSpan(
          text: number ? '﴿1﴾' : 'الحمد لله رب العالمين',
          semanticsLabel:
              number ? 'الآية 1' : 'الفاتحة الآية 1 الحمد لله رب العالمين',
          style: const TextStyle(fontSize: 24, color: Colors.black),
          recognizer: recognizer,
        ))))));
        await tester.pumpAndSettle();
        final root = tester.getSemantics(find.byType(RichText));
        final nodes = <SemanticsNode>[];
        void visit(SemanticsNode node) {
          nodes.add(node);
          node.visitChildren((child) {
            visit(child);
            return true;
          });
        }

        visit(root);
        final targets = nodes
            .where(
                (n) => n.getSemanticsData().hasAction(ui.SemanticsAction.tap))
            .toList();
        expect(targets, hasLength(1));
        final node = targets.single;
        node.owner!.performAction(node.id, ui.SemanticsAction.tap);
        await tester.pumpAndSettle();
        expect(taps, 1);
        expect(holds, 0);
        recognizer.onAyahTap = () => taps += 10;
        node.owner!.performAction(node.id, ui.SemanticsAction.tap);
        await tester.pumpAndSettle();
        expect(taps, 11);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        handle.dispose();
        recognizer.dispose();
      }
    });
  }
}
