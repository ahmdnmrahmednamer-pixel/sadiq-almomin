import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/audio/ayah_audio_player.dart';
import 'package:almomin/core/audio/fast_audio_service.dart';
import 'package:almomin/core/models/surah.dart';
import 'package:almomin/core/services/settings_service.dart';

const surah = Surah(
    id: 1,
    nameAr: 'الفاتحة',
    nameSimple: 'Al-Fatihah',
    revelationPlace: 'makkah',
    revelationOrder: 5,
    ayahCount: 7,
    hasBasmala: false,
    pageStart: 1,
    pageEnd: 1);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final player = AyahAudioPlayer.instance;
  final engine = FastAudioService.instance;
  late StreamController<PlayerState> states;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init(forceReload: true);
    await SettingsService.instance.setSelectedReciter('banna');
    engine.resetForTesting();
    player.resetForTesting();
    states = StreamController<PlayerState>.broadcast();
    player.playerStateStreamOverride = states.stream;
    player.stopPlayerRunner = () async {};
    player.loadSurahsRunner = () async => [surah];
    player.prefetchAudioRunner = (_, __) {};
  });
  tearDown(() async {
    await states.close();
    player.resetForTesting();
    engine.resetForTesting();
  });
  for (final stage in ['before-completion', 'during-metadata', 'other-owner']) {
    testWidgets('automatic next keeps loaded reciter and ownership: $stage',
        (t) async {
      late BuildContext context;
      await t.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) {
        context = c;
        return const SizedBox();
      }))));
      final urls = <String>[];
      final keys = <String>[];
      final prefetch = <String>[];
      player.playResilientRunner = (url,
          {player,
          primaryUrl,
          fallbackUrls = const [],
          cacheKey,
          localDownloadedPath,
          onStopCallback}) async {
        urls.add(primaryUrl!);
        keys.add(cacheKey!);
        return true;
      };
      player.prefetchAudioRunner = (url, key) => prefetch.add(key);
      await player.playAyah(context, 1, 1);
      final gate = Completer<List<Surah>>();
      if (stage != 'before-completion')
        player.loadSurahsRunner = () => gate.future;
      if (stage == 'before-completion')
        await SettingsService.instance.setSelectedReciter('fares_abbad');
      states.add(PlayerState(false, ProcessingState.completed));
      await t.pump();
      if (stage != 'before-completion') {
        if (stage == 'other-owner') {
          engine.registerAudioFocus();
        } else {
          await SettingsService.instance.setSelectedReciter('fares_abbad');
        }
        gate.complete([surah]);
        await t.pump();
      }
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await t.pumpAndSettle();
      if (stage == 'other-owner') {
        expect(urls.length, 1);
        expect(player.currentPlayingKey.value, isNull);
      } else {
        expect(
            urls.last, SettingsService.instance.getAyahAudioUrl(1, 2, 'banna'));
        expect(keys.last, 'ayah_banna_1_2');
        expect(prefetch.last, 'ayah_banna_1_3');
        expect(SettingsService.instance.selectedReciterId, 'fares_abbad');
      }
      await t.pumpWidget(const SizedBox());
    });
  }
}
