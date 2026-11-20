import 'dart:async';
import 'package:almomin/core/audio/ayah_audio_player.dart';
import 'package:almomin/features/settings/widgets/settings_reciter_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/features/settings/settings_screen.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'theme_mode': 'dark', 'default_playback_speed': 1.1});
    await SettingsService.instance.init();
  });
  Future<void> host(WidgetTester tester, {double scale = 1}) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: const SettingsScreen(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!)));
    await tester.pumpAndSettle();
  }

  Future<void> chooseTheme(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('settings_category_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('setting_المظهر')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('فاتح'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'categories show only their own settings, Apply is genuinely deferred',
      (tester) async {
    await host(tester);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.byKey(const ValueKey('settings_category_5')), findsOneWidget);
    await chooseTheme(tester);
    expect(SettingsService.instance.themeMode, 'dark');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'dark');
    expect(find.text('صوت الإقامة'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('settings_apply')));
    await tester.pumpAndSettle();
    expect(SettingsService.instance.themeMode, 'light');
    expect(prefs.getString('theme_mode'), 'light');
    expect(find.text('تم حفظ التغييرات'), findsOneWidget);
    expect(prefs.getDouble('default_playback_speed'), 1.1);
  });
  testWidgets(
      'Discard saves nothing and back retains drafts between categories',
      (tester) async {
    await host(tester);
    await chooseTheme(tester);
    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings_category_0')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings_category_0')));
    await tester.pumpAndSettle();
    expect(find.text('فاتح'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings_discard')));
    await tester.pumpAndSettle();
    expect(find.text('داكن'), findsOneWidget);
    expect(SettingsService.instance.themeMode, 'dark');
  });
  testWidgets('leaving with pending changes asks before discard',
      (tester) async {
    await host(tester);
    await chooseTheme(tester);
    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('تغييرات غير مطبقة'), findsOneWidget);
    await tester.tap(find.text('البقاء'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings_category_0')), findsOneWidget);
    expect(SettingsService.instance.themeMode, 'dark');
  });
  testWidgets('all settings categories render at 2x on narrow screen',
      (tester) async {
    await host(tester, scale: 2);
    for (var i = 0; i < 6; i++) {
      await tester.ensureVisible(find.byKey(ValueKey('settings_category_$i')));
      await tester.tap(find.byKey(ValueKey('settings_category_$i')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'category $i');
      await tester.tap(find.byTooltip('رجوع'));
      await tester.pumpAndSettle();
    }
  });
  testWidgets(
      'staged reciter picker changes neither saved reciter nor playback',
      (tester) async {
    final before = SettingsService.instance.selectedReciterId;
    String? staged;
    var previews = 0;
    AyahAudioPlayer.instance.playResilientRunner = (url,
        {player,
        primaryUrl,
        fallbackUrls = const [],
        localDownloadedPath,
        cacheKey,
        onStopCallback}) async {
      previews++;
      return true;
    };
    addTearDown(() => AyahAudioPlayer.instance.playResilientRunner = null);
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showSettingsReciterModal(context,
                        selectedReciter: before,
                        onStage: (value) => staged = value),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final chosen =
        SettingsService.availableReciters.firstWhere((r) => r.id != before);
    await tester.enterText(find.byType(TextField), chosen.id);
    await tester.pumpAndSettle();
    await tester.tap(find.text(chosen.nameAr).last);
    await tester.pumpAndSettle();
    expect(staged, chosen.id);
    expect(SettingsService.instance.selectedReciterId, before);
    expect(previews, 0);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('selected_reciter_id'), isNull);
  });

  testWidgets(
      'explicit discard when leaving clears staged changes without saving',
      (tester) async {
    await host(tester);
    await chooseTheme(tester);
    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('تجاهل').last);
    await tester.pumpAndSettle();
    expect(find.text('تغييرات غير مطبقة'), findsNothing);
    expect(SettingsService.instance.themeMode, 'dark');
    await tester.tap(find.byKey(const ValueKey('settings_category_0')));
    await tester.pumpAndSettle();
    expect(find.text('داكن'), findsOneWidget);
  });
  testWidgets('leaving Quran cancels a reciter preview still starting', (tester) async {
    final player = AyahAudioPlayer.instance;
    player.resetForTesting();
    final gate = Completer<void>();
    var stops = 0;
    var starts = 0;
    player.stopPlayerRunner = () async {
      stops++;
      if (stops == 1) await gate.future;
    };
    player.playResilientRunner = (url, {player, primaryUrl, fallbackUrls = const [], localDownloadedPath, cacheKey, onStopCallback}) async {
      starts++;
      return true;
    };
    addTearDown(player.resetForTesting);
    await host(tester);
    await tester.tap(find.byKey(const ValueKey('settings_category_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('استماع أو إيقاف العينة'));
    await tester.pump();
    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();
    expect(starts, 0);
    expect(player.currentPlayingKey.value, isNull);
  });

}
