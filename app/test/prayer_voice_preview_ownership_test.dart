import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/audio/fast_audio_service.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/notifications/prayer_notification_service.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/features/settings/widgets/settings_adhan_voice_modal.dart';
import 'package:almomin/features/settings/widgets/adhan_voice_option.dart';

class VoicePreviewPlayer extends AudioPlayer {
  final states = StreamController<PlayerState>.broadcast(sync: true);
  final urls = <String>[];
  bool failDispose = false;
  Completer<void>? playFailureGate;
  bool active = false,
      disposed = false,
      failLoad = false,
      failPlay = false,
      failStop = false;
  int plays = 0, stops = 0;
  Completer<void>? loadGate, stopGate;
  @override
  bool get playing => active;
  @override
  Stream<PlayerState> get playerStateStream => states.stream;
  void emit(bool value, ProcessingState state) {
    active = value;
    if (!disposed) states.add(PlayerState(value, state));
  }

  @override
  Future<Duration?> setUrl(String url,
      {Map<String, String>? headers,
      Duration? initialPosition,
      bool preload = true,
      dynamic tag}) async {
    urls.add(url);
    if (loadGate != null) await loadGate!.future;
    if (failLoad) throw StateError('load');
    return const Duration(seconds: 3);
  }

  @override
  Future<void> play() async {
    plays++;
    if (failPlay) throw StateError('play');
    if (playFailureGate != null) await playFailureGate!.future;
    emit(true, ProcessingState.ready);
  }

  @override
  Future<void> stop() async {
    stops++;
    if (stopGate != null) await stopGate!.future;
    if (failStop) throw StateError('stop');
    emit(false, ProcessingState.idle);
  }

  @override
  Future<void> dispose() async {
    if (failDispose) throw StateError('dispose');
    disposed = true;
    active = false;
    await states.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final audio = IslamicAudioService.instance;
  final focus = FastAudioService.instance;
  final notifications = PrayerNotificationService.instance;
  late VoicePreviewPlayer player;
  final boundary = GlobalKey();
  setUpAll(() async {
    for (final family in ['Cairo', 'Amiri']) {
      final loader = FontLoader(family);
      for (final weight in ['Regular', 'Bold']) {
        final f = File('assets/fonts/$family-$weight.ttf');
        if (f.existsSync()) {
          loader
              .addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
        }
      }
      await loader.load();
    }
    const iconFont = String.fromEnvironment('MATERIAL_ICONS_FONT');
    if (iconFont.isNotEmpty) {
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(
                ByteData.sublistView(File(iconFont).readAsBytesSync()))))
          .load();
    }
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({'notif_master_enabled': false});
    await SettingsService.instance.init(forceReload: true);
    await notifications.init(forceReload: true);
    audio.disableNativePlayerForTesting = true;
    await audio.init();
    await audio.stop();
    focus.resetForTesting();
    player = VoicePreviewPlayer();
  });
  tearDown(() {
    focus.resetForTesting();
  });
  Future<void> mount(WidgetTester t,
      {double width = 360,
      double height = 800,
      double scale = 1,
      bool dark = false,
      String prayer = 'الفجر',
      bool iqamah = false, ValueChanged<String>? onStage}) async {
    t.view.physicalSize = Size(width, height);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetViewInsets);
    await t.pumpWidget(RepaintBoundary(
        key: boundary,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
            builder: (c, ch) => MediaQuery(
                data: MediaQuery.of(c)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: ch!),
            home: Scaffold(
                body: Builder(
                    builder: (c) => TextButton(
                        onPressed: () => showPrayerMuezzinDropdownPicker(
                            c, prayer,
                            isIqamah: iqamah, onStage: onStage,
                            previewPlayerFactory: () => player),
                        child: const Text('فتح')))))));
    await t.tap(find.text('فتح'));
    await t.pumpAndSettle();
  }

  Finder option(int index) => find.byType(AdhanVoiceOption).at(index);
  AdhanVoiceOption card(WidgetTester t, int index) =>
      t.widget<AdhanVoiceOption>(option(index));
  Future<void> listen(WidgetTester t, {int index = 0}) async {
    card(t, index).onListen();
    await t.pumpAndSettle();
  }

  Future<void> capture(WidgetTester t, String name) async {
    const dir = String.fromEnvironment('VOICE_PREVIEW_PIXELS_DIR');
    if (dir.isEmpty) return;
    await t.runAsync(() async {
      final image = await (boundary.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final f = File('$dir/$name.png');
      f.parent.createSync(recursive: true);
      await f.writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  testWidgets(
      'close without Listen preserves existing studio playback and saved voices',
      (t) async {
    const existing = IslamicAudioTrack(
        id: 'existing',
        title: 'existing',
        subtitle: '',
        type: IslamicAudioType.quran,
        durationFormatted: '01:00');
    await audio.playTrack(existing);
    final saved = notifications.getPrayerVoice('الفجر');
    await mount(t);
    expect(audio.currentTrack?.id, 'existing');
    expect(audio.isPlaying, isTrue,
        reason: 'opening init must not change playback');
    expect(player.urls, isEmpty);
    await t.tap(find.byTooltip('إغلاق'));
    await t.pumpAndSettle();
    expect(player.disposed, isTrue);
    expect(audio.currentTrack?.id, 'existing');
    expect(audio.isPlaying, isTrue);
    expect(notifications.getPrayerVoice('الفجر'), saved);
  });
  testWidgets('staged assignment returns selection without changing saved voices', (t) async {
    final before = notifications.getPrayerVoice('الفجر');
    String? staged;
    await mount(t, onStage: (value) => staged = value);
    final selected = (card(t, 0).key! as ValueKey).value.toString().substring('voice_'.length);
    card(t, 0).onAssign();
    await t.pumpAndSettle();
    expect(staged, selected);
    expect(notifications.getPrayerVoice('الفجر'), before);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('notif_prayer_voice_الفجر'), isNull);
    expect(player.urls, isEmpty);
    expect(player.disposed, isTrue);
  });

  testWidgets('Listen streams selected catalog URL only and does not assign',
      (t) async {
    await mount(t);
    final saved = notifications.getPrayerVoice('الفجر');
    final chosen = card(t, 0).key! as ValueKey;
    await listen(t);
    expect(player.active, isTrue);
    expect(player.urls.length, 1);
    final track = IslamicAudioService.allTracks
        .singleWhere((track) => 'voice_${track.id}' == chosen.value);
    expect(player.urls.single, track.remoteUrl);
    expect(notifications.getPrayerVoice('الفجر'), saved);
    await t.tap(find.byTooltip('إغلاق'));
    await t.pumpAndSettle();
    expect(player.disposed, isTrue);
  });
  testWidgets('actual semantics Listen and Assign remain separate', (t) async {
    final semantics = t.ensureSemantics();
    await mount(t);
    final buttons = find.descendant(
        of: option(0), matching: find.bySubtype<ButtonStyleButton>());
    expect(buttons, findsNWidgets(2));
    final listenButton = find.descendant(
        of: option(0), matching: find.widgetWithText(OutlinedButton, 'استماع'));
    expect(
        t
            .getSemantics(listenButton)
            .getSemanticsData()
            .hasAction(ui.SemanticsAction.tap),
        isTrue);
    t.binding.pipelineOwner.semanticsOwner!
        .performAction(t.getSemantics(listenButton).id, ui.SemanticsAction.tap);
    await t.pumpAndSettle();
    expect(player.plays, 1);
    expect(notifications.getPrayerVoice('الفجر'), 'adhan_fajr');
    semantics.dispose();
  });
  testWidgets('untagged late state-stream error cannot cancel newer request',
      (t) async {
    await mount(t);
    await listen(t);
    await listen(t, index: 1);
    final played = player.plays;
    final stopped = player.stops;
    player.states.addError(StateError('older stream error'));
    await t.pumpAndSettle();
    expect(player.active, isTrue);
    expect(player.plays, played);
    expect(player.stops, stopped);
    expect(find.textContaining('تعذر تشغيل الصوت'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('late older play failure cannot cancel newer playback',
      (t) async {
    await mount(t);
    final old = Completer<void>();
    player.playFailureGate = old;
    await listen(t);
    player.playFailureGate = null;
    await listen(t, index: 1);
    expect(player.active, isTrue);
    final stopped = player.stops;
    old.completeError(StateError('older play failed'));
    await t.pumpAndSettle();
    expect(player.active, isTrue);
    expect(player.stops, stopped);
    expect(find.textContaining('تعذر تشغيل الصوت'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('late old load failure cannot poison newer load', (t) async {
    await mount(t);
    final old = Completer<void>();
    player.loadGate = old;
    await listen(t);
    card(t, 1).onListen();
    await t.pumpAndSettle();
    player.loadGate = null;
    old.completeError(StateError('older load failed'));
    await t.pumpAndSettle();
    expect(player.urls.length, 2);
    expect(player.plays, 1);
    expect(player.active, isTrue);
    expect(find.textContaining('تعذر تشغيل الصوت'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('dispose rejection is contained and next owner can claim focus',
      (t) async {
    await mount(t);
    await listen(t);
    player.failDispose = true;
    await t.tap(find.byTooltip('إغلاق'));
    await t.pumpAndSettle();
    expect(player.active, isFalse);
    expect(t.takeException(), isNull);
    final newer = VoicePreviewPlayer();
    await focus.claimAudioFocus(player: newer, onStopOther: newer.stop);
    await newer.play();
    expect(newer.active, isTrue);
    expect(t.takeException(), isNull);
    player.failDispose = false;
    await player.dispose();
    await newer.dispose();
  });
  testWidgets('repeat Listen cancels pending load and cannot later start',
      (t) async {
    await mount(t);
    player.loadGate = Completer<void>();
    await listen(t);
    expect(player.urls.length, 1);
    await listen(t);
    player.loadGate!.complete();
    await t.pumpAndSettle();
    expect(player.plays, 0);
    expect(player.active, isFalse);
  });
  testWidgets('dismiss during pending load cannot play later', (t) async {
    await mount(t);
    player.loadGate = Completer<void>();
    await listen(t);
    await t.tap(find.byTooltip('إغلاق'));
    await t.pumpAndSettle();
    player.loadGate!.complete();
    await t.pumpAndSettle();
    expect(player.disposed, isTrue);
    expect(player.plays, 0);
    expect(t.takeException(), isNull);
  });
  testWidgets('new owner survives old picker close and old pending load',
      (t) async {
    await mount(t);
    player.loadGate = Completer<void>();
    await listen(t);
    final newer = VoicePreviewPlayer();
    await focus.claimAudioFocus(player: newer, onStopOther: newer.stop);
    await newer.play();
    final token = focus.activePlaybackToken;
    await t.tap(find.byTooltip('إغلاق'));
    await t.pumpAndSettle();
    player.loadGate!.complete();
    await t.pumpAndSettle();
    expect(newer.active, isTrue);
    expect(focus.activePlaybackToken, token);
    expect(player.plays, 0);
    await newer.dispose();
  });
  testWidgets('older stop completes before a new preview loads on same player',
      (t) async {
    await mount(t);
    await listen(t);
    player.stopGate = Completer<void>();
    card(t, 1).onListen();
    await t.pump();
    expect(player.urls.length, 1);
    player.stopGate!.complete();
    await t.pumpAndSettle();
    expect(player.urls.length, 2);
    expect(player.active, isTrue);
  });
  testWidgets('new load waits for old pending load before selecting next voice',
      (t) async {
    await mount(t);
    player.loadGate = Completer<void>();
    await listen(t);
    card(t, 1).onListen();
    await t.pumpAndSettle();
    expect(player.urls.length, 1);
    player.loadGate!.complete();
    await t.pumpAndSettle();
    expect(player.urls.length, 2);
    expect(player.plays, 1);
  });
  testWidgets('load and playback errors are shown without assigning',
      (t) async {
    await mount(t);
    player.failLoad = true;
    await listen(t);
    expect(find.textContaining('تعذر تشغيل الصوت'), findsOneWidget);
    expect(player.plays, 0);
    expect(notifications.getPrayerVoice('الفجر'), 'adhan_fajr');
    player.failLoad = false;
    player.failPlay = true;
    await listen(t);
    expect(find.textContaining('تعذر تشغيل الصوت'), findsOneWidget);
    expect(player.active, isFalse);
    expect(t.takeException(), isNull);
  });
  testWidgets('failed Stop remains an explicit retry and announces its error',
      (t) async {
    final semantics = t.ensureSemantics();
    await mount(t);
    await listen(t);
    player.failStop = true;
    await listen(t);
    expect(player.active, isTrue);
    expect(card(t, 0).playing, isTrue);
    final error = find.text('تعذر إيقاف المعاينة. أعد محاولة الإيقاف.');
    expect(error, findsOneWidget);
    expect(
        find.ancestor(
            of: error,
            matching: find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.liveRegion == true)),
        findsOneWidget);
    player.failStop = false;
    await listen(t);
    expect(player.active, isFalse);
    expect(card(t, 0).playing, isFalse);
    semantics.dispose();
  });
  testWidgets('assignment without Listen also preserves unrelated playback',
      (t) async {
    const existing = IslamicAudioTrack(
        id: 'existing',
        title: 'existing',
        subtitle: '',
        type: IslamicAudioType.quran,
        durationFormatted: '01:00');
    await audio.playTrack(existing);
    await mount(t);
    card(t, 1).onAssign();
    await t.pumpAndSettle();
    expect(audio.currentTrack?.id, 'existing');
    expect(audio.isPlaying, isTrue);
    expect(player.urls, isEmpty);
  });
  testWidgets('stop failure blocks assignment until explicit retry', (t) async {
    await mount(t);
    await listen(t);
    player.failStop = true;
    card(t, 1).onAssign();
    await t.pumpAndSettle();
    expect(find.textContaining('تعذر إيقاف المعاينة أو حفظ'), findsOneWidget);
    expect(notifications.getPrayerVoice('الفجر'), 'adhan_fajr');
    player.failStop = false;
    final expected =
        (card(t, 1).key! as ValueKey).value.toString().substring(6);
    card(t, 1).onAssign();
    await t.pumpAndSettle();
    expect(notifications.getPrayerVoice('الفجر'), expected);
    expect(find.byType(AdhanVoiceOption), findsNothing);
  });
  for (final prayer in ['الفجر', 'الكل', 'إقامة الصلاة']) {
    testWidgets('explicit Assign persists only requested scope $prayer',
        (t) async {
      await mount(t, prayer: prayer, iqamah: prayer == 'إقامة الصلاة');
      final old = notifications.getPrayerVoice('الظهر');
      final expected =
          (card(t, 1).key! as ValueKey).value.toString().substring(6);
      card(t, 1).onAssign();
      card(t, 1).onAssign();
      await t.pumpAndSettle();
      if (prayer == 'إقامة الصلاة') {
        expect(notifications.selectedIqamahVoice, expected);
        expect(notifications.getPrayerVoice('الظهر'), old);
      } else if (prayer == 'الكل') {
        for (final p in ['الفجر', 'الظهر', 'العصر', 'المغرب', 'العشاء']) {
          expect(notifications.getPrayerVoice(p), expected);
        }
      } else {
        expect(notifications.getPrayerVoice(prayer), expected);
        expect(notifications.getPrayerVoice('الظهر'), old);
      }
      expect(player.disposed, isTrue);
    });
  }
  testWidgets('keyboard focus does not stop preview; app pause does',
      (t) async {
    await mount(t);
    await listen(t);
    await t.tap(find.byType(TextField));
    await t.pumpAndSettle();
    expect(player.active, isTrue);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await t.pumpAndSettle();
    expect(player.active, isFalse);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(player.active, isFalse);
  });
  testWidgets('covered route stops only owned preview', (t) async {
    await mount(t);
    await listen(t);
    final c = t.element(option(0));
    Navigator.of(c).push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('cover'))));
    await t.pumpAndSettle();
    expect(player.active, isFalse);
    Navigator.of(c).pop();
    await t.pumpAndSettle();
    expect(player.active, isFalse);
  });
  testWidgets(
      'narrow loaded-font large text keyboard actions and errors remain reachable',
      (t) async {
    for (final dark in [false, true]) {
      await mount(t, width: 320, height: 640, scale: 2, dark: dark);
      expect(t.takeException(), isNull);
      await capture(t, 'picker-$dark');
      await t.tap(find.byType(TextField));
      t.view.viewInsets = const FakeViewPadding(bottom: 300);
      await t.pumpAndSettle();
      final assign = find.text('تعيين').first;
      await t.ensureVisible(assign);
      await t.pumpAndSettle();
      expect(t.getRect(assign).bottom, lessThanOrEqualTo(340));
      expect(t.takeException(), isNull);
      await capture(t, 'keyboard-$dark');
      t.view.resetViewInsets();
      await t.pumpAndSettle();
      player.failLoad = true;
      await listen(t);
      expect(find.textContaining('تعذر تشغيل الصوت'), findsOneWidget);
      expect(t.takeException(), isNull);
      await capture(t, 'error-$dark');
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      player = VoicePreviewPlayer();
    }
  });  for (final kind in ['material', 'fullscreen', 'dialog', 'dialog-no-focus', 'material-no-focus']) {
    testWidgets('route coverage without relying on secondary animation: $kind', (t) async {
      await mount(t);
      await listen(t);
      final c = t.element(option(0));
      final nav = Navigator.of(c);
      Route<void> route;
      if (kind.startsWith('dialog')) {
        route = DialogRoute<void>(context: c, requestFocus: kind != 'dialog-no-focus', builder: (_) => const AlertDialog(content: Text('cover')));
      } else {
        route = MaterialPageRoute<void>(requestFocus: kind != 'material-no-focus', fullscreenDialog: kind == 'fullscreen', builder: (_) => const Scaffold(body: Text('cover')));
      }
      unawaited(nav.push(route));
      await t.pumpAndSettle();
      final active = player.active;
      nav.pop();
      await t.pumpAndSettle();
      expect(active, isFalse, reason: kind);
    });
  }

}
