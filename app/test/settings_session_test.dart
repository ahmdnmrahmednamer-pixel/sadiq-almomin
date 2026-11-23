import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:almomin/core/localization/app_localizations.dart';
import 'package:almomin/core/ui/app_dropdown_field.dart';
import 'package:almomin/core/notifications/prayer_notification_service.dart';
// Test-only preference backend fault injection.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/features/settings/models/settings_session.dart';

class RejectingSettingsStore extends InMemorySharedPreferencesStore {
  RejectingSettingsStore() : super.withData({'flutter.theme_mode': 'dark'});
  bool reject = true;
  @override
  Future<bool> setValue(String type, String key, Object value) async =>
      reject ? false : await super.setValue(type, key, value);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'app_language': 'ar',
      'mushaf_font_size': 30.0,
      'default_playback_speed': 1.1,
      'theme_mode': 'dark',
      'quran_translation_edition': 'en_saheeh',
      'bilingual_display_enabled': false,
      'bookmarks': <String>['2:255'],
    });
    await SettingsService.instance.init();
  });

  test(
      'session creation and draft edits keep preferences and services unchanged',
      () async {
    final session = SettingsSession();
    expect(session.font.value, 30.0);
    expect(session.speed.value, 1.1);
    session.theme.stage('light');
    session.font.stage(32);
    session.stageLanguage('en');
    expect(SettingsService.instance.themeMode, 'dark');
    expect(SettingsService.instance.languageCode, 'ar');
    expect(SettingsService.instance.mushafFontSize, 30);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_language'), 'ar');
    expect(prefs.getString('theme_mode'), 'dark');
    session.draft.discard();
    expect(session.theme.value, 'dark');
    expect(session.font.value, 30);
    expect(session.speed.value, 1.1);
    expect(prefs.getStringList('bookmarks'), ['2:255']);
  });

  test(
      'language group applies the explicitly selected translation and bilingual value',
      () async {
    final session = SettingsSession();
    session.stageLanguage('en');
    expect(session.language.value.bilingual, isTrue);
    session.language
        .stage((language: 'en', translation: 'en_rwwad', bilingual: false));
    final result = await session.draft.apply();
    expect(result.success, isTrue);
    expect(SettingsService.instance.languageCode, 'en');
    expect(SettingsService.instance.bilingualDisplayEnabled, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('quran_translation_edition'), 'en_rwwad');
    expect(prefs.getBool('bilingual_display_enabled'), isFalse);
    expect(prefs.getStringList('bookmarks'), ['2:255']);
  });

  test('unavailable explicit translation fails before any grouped write',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final before = {for (final key in prefs.getKeys()) key: prefs.get(key)};
    final session = SettingsSession();
    session.language
        .stage((language: 'en', translation: 'en_saheeh', bilingual: true));
    final result = await session.draft.apply();
    expect(result.success, isFalse);
    expect(result.failedKey, 'language');
    expect(session.draft.dirty, isTrue);
    expect(SettingsService.instance.languageCode, 'ar');
    expect(SettingsService.instance.quranTranslationEdition, 'en_saheeh');
    expect(SettingsService.instance.bilingualDisplayEnabled, isFalse);
    expect({for (final key in prefs.getKeys()) key: prefs.get(key)}, before);
    session.language
        .stage((language: 'en', translation: 'en_rwwad', bilingual: true));
    expect((await session.draft.apply()).success, isTrue);
    expect(prefs.getString('quran_translation_edition'), 'en_rwwad');
  });

  testWidgets(
      'stale translation is visibly and semantically unavailable, never Rowwad',
      (tester) async {
    final settings = SettingsService.instance;
    final options = QuranTranslationEdition.choicesWithSaved(
        settings.quranTranslationEdition);
    expect(options.first.id, 'en_saheeh');
    expect(
        QuranTranslationEdition.availableTranslations
            .any((e) => e.id == 'en_saheeh'),
        isFalse);
    final font = Platform.environment['ENGLISH_SELECTION_FONT'];
    if (font != null) {
      await tester.runAsync(() async {
        await (FontLoader('Amiri')
              ..addFont(Future.value(
                  ByteData.sublistView(await File(font).readAsBytes()))))
            .load();
      });
    }
    final key = GlobalKey();
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: font == null ? null : 'Amiri'),
        home: Scaffold(
            body: RepaintBoundary(
                key: key,
                child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(24),
                    child: AppDropdownField<String>(
                      label: 'Quran translation',
                      value: settings.quranTranslationEdition,
                      options: options
                          .map((e) => AppDropdownOption(
                              value: e.id, label: e.nameNative))
                          .toList(),
                      onChanged: (_) {},
                    ))))));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Saved translation unavailable (en_saheeh). Choose another translation'),
        findsOneWidget);
    expect(
        find.bySemanticsLabel(RegExp(
            'Saved translation unavailable.*Choose another translation')),
        findsWidgets);
    expect(settings.quranTranslationEdition, 'en_saheeh');
    expect(
        (await SharedPreferences.getInstance())
            .getString('quran_translation_edition'),
        'en_saheeh');
    if (Platform.environment['ENGLISH_SELECTION_PREVIEW'] != null) {
      await tester.runAsync(() async {
        final image = await (key.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(Platform.environment['ENGLISH_SELECTION_PREVIEW']!)
            .writeAsBytes(bytes!.buffer.asUint8List());
      });
    }
    semantics.dispose();
  });

  test('custom values survive Apply of a different setting', () async {
    final session = SettingsSession();
    session.theme.stage('light');
    expect((await session.draft.apply()).success, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('mushaf_font_size'), 30);
    expect(prefs.getDouble('default_playback_speed'), 1.1);
    expect(prefs.getString('theme_mode'), 'light');
  });
  test(
      'notification and sensor edits trigger no device methods or preference writes',
      () async {
    var calls = 0;
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls++;
      return true;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final before = await SharedPreferences.getInstance();
    final keys = before.getKeys().toSet();
    final session = SettingsSession();
    session.pre.stage(!session.pre.value);
    session.master.stage((settings: false, notifications: false));
    session.morningTime.stage((hour: 8, minute: 15));
    session.shortFrequencies['salawat']!.stage(ShortReminderFrequency.hourly);
    session.shake.stage(!session.shake.value);
    session.overlay.stage(!session.overlay.value);
    expect(calls, 0);
    expect(before.getKeys(), keys);
    session.draft.discard();
    expect(calls, 0);
    expect(before.getKeys(), keys);
  });

  test('a service that silently fails persistence cannot report saved settings',
      () async {
    final store = RejectingSettingsStore();
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
    await SettingsService.instance.init();
    final session = SettingsSession();
    session.theme.stage('light');
    final result = await session.draft.apply();
    expect(result.success, isFalse);
    expect(result.failedKey, 'theme');
    expect(session.draft.dirty, isTrue);
    store.reject = false;
    expect((await session.draft.apply()).success, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'light');
  });
}
