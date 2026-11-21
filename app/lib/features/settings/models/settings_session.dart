import '../../../core/localization/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/services/adhan_sensor_gesture_service.dart';
import '../../../core/notifications/prayer_notification_service.dart';
import 'settings_draft.dart';

typedef LanguageChoice = ({
  String language,
  String translation,
  bool bilingual
});

class SettingsSession {
  SettingsSession() {
    final s = SettingsService.instance;
    final n = PrayerNotificationService.instance;
    final sensors = AdhanSensorGestureService.instance;
    language = draft.add<LanguageChoice>(
      key: 'language',
      read: () => (
        language: s.languageCode,
        translation: s.quranTranslationEdition,
        bilingual: s.bilingualDisplayEnabled
      ),
      write: (value) async {
        await s.setLanguage(value.language);
        await s.setQuranTranslationEdition(value.translation);
        await s.toggleBilingualDisplay(value.bilingual);
      },
      verify: (value) => _saved({
        'app_language': value.language,
        'quran_translation_edition': value.translation,
        'bilingual_display_enabled': value.bilingual
      }),
    );
    master = draft.add<({bool settings, bool notifications})>(
      key: 'master',
      read: () =>
          (settings: s.adhanAlertsEnabled, notifications: n.masterEnabled),
      write: (value) async {
        await s.toggleAdhanAlerts(value.settings);
      },
      verify: (value) => _saved({
        'adhan_alerts': value.settings,
        'notif_master_enabled': value.notifications
      }),
    );
    font = draft.add<double>(
        key: 'font',
        read: () => s.mushafFontSize,
        write: s.setMushafFontSize,
        verify: (value) => _saved({'mushaf_font_size': value}));
    reciter = draft.add<String>(
        key: 'reciter',
        read: () => s.selectedReciterId,
        write: s.setSelectedReciter,
        verify: (value) => _saved({'selected_reciter_id': value}));
    method = draft.add<String>(
        key: 'method',
        read: () => s.calculationMethod,
        write: s.setCalculationMethod,
        verify: (value) => _saved({'calculation_method': value}));
    hijri = draft.add<int>(
        key: 'hijri',
        read: () => s.hijriAdjustmentDays,
        write: s.setHijriAdjustmentDays,
        verify: (value) => _saved({'hijri_adjustment_days': value}));
    quality = draft.add<String>(
        key: 'quality',
        read: () => s.audioQualityPreset,
        write: s.setAudioQualityPreset,
        verify: (value) => _saved({'audio_quality_preset': value}));
    speed = draft.add<double>(
        key: 'speed',
        read: () => s.defaultPlaybackSpeed,
        write: s.setDefaultPlaybackSpeed,
        verify: (value) => _saved({'default_playback_speed': value}));
    repeat = draft.add<int>(
        key: 'repeat',
        read: () => s.ayahRepeatCount,
        write: s.setAyahRepeatCount,
        verify: (value) => _saved({'ayah_repeat_count': value}));
    tafsir = draft.add<String>(
        key: 'tafsir',
        read: () => s.defaultTafsirEdition,
        write: s.setDefaultTafsirEdition,
        verify: (value) => _saved({'default_tafsir_edition': value}));
    fiqh = draft.add<String>(
        key: 'fiqh',
        read: () => s.fiqhMadhhab,
        write: s.setFiqhMadhhab,
        verify: (value) => _saved({'fiqh_madhhab': value}));
    silent = draft.add<bool>(
        key: 'silent',
        read: () => s.autoSilentDuringPrayer,
        write: s.toggleAutoSilentDuringPrayer,
        verify: (value) => _saved({'auto_silent_prayer': value}));
    sunan = draft.add<bool>(
        key: 'sunan',
        read: () => s.sunanRawatibReminderEnabled,
        write: s.toggleSunanRawatibReminder,
        verify: (value) => _saved({'sunan_rawatib_reminder': value}));
    theme = draft.add<String>(
        key: 'theme',
        read: () => s.themeMode,
        write: s.setThemeMode,
        verify: (value) => _saved({'theme_mode': value}));
    sharawi = draft.add<bool>(
        key: 'sharawi',
        read: () => s.playSharawiDuaaAfterAdhan,
        write: s.togglePlaySharawiDuaaAfterAdhan,
        verify: (value) => _saved({'play_sharawi_duaa_after_adhan': value}));
    volume = draft.add<bool>(
        key: 'volume',
        read: () => s.tasbihVolumeButtonEnabled,
        write: s.toggleTasbihVolumeButton,
        verify: (value) => _saved({'tasbih_volume_button_enabled': value}));
    slider = draft.add<bool>(
        key: 'slider',
        read: () => s.tasbihSliderEnabled,
        write: s.toggleTasbihSlider,
        verify: (value) => _saved({'tasbih_slider_enabled': value}));
    wifi = draft.add<bool>(
        key: 'wifi',
        read: () => s.downloadOverWifiOnly,
        write: s.toggleDownloadOverWifiOnly,
        verify: (value) => _saved({'download_wifi_only': value}));
    mode = draft.add<String>(
        key: 'mode',
        read: () => s.mushafDefaultMode,
        write: s.setMushafDefaultMode,
        verify: (value) => _saved({'mushaf_default_mode': value}));
    layout = draft.add<String>(
        key: 'layout',
        read: () => s.screenLayoutMode,
        write: s.setScreenLayoutMode,
        verify: (value) => _saved({'screen_layout_mode': value}));
    numbering = draft.add<String>(
        key: 'numbering',
        read: () => s.quranNumberingStyle,
        write: s.setQuranNumberingStyle,
        verify: (value) => _saved({'quran_numbering_style': value}));
    autoplay = draft.add<bool>(
        key: 'autoplay',
        read: () => s.autoPlayNextAyah,
        write: s.toggleAutoPlayNextAyah,
        verify: (value) => _saved({'auto_play_next_ayah': value}));
    screen = draft.add<bool>(
        key: 'screen',
        read: () => s.keepScreenOn,
        write: s.toggleKeepScreenOn,
        verify: (value) => _saved({'keep_screen_on': value}));
    pre = draft.add<bool>(
        key: 'pre',
        read: () => n.preReminderEnabled,
        write: n.togglePreReminder,
        verify: (value) => _saved({'notif_pre_reminder_enabled': value}));
    preMinutes = draft.add<int>(
        key: 'preMinutes',
        read: () => n.preReminderMinutes,
        write: n.setPreReminderMinutes,
        verify: (value) => _saved({'notif_pre_reminder': value}));
    qiyam = draft.add<bool>(
        key: 'qiyam',
        read: () => n.qiyamReminderEnabled,
        write: n.toggleQiyamReminder,
        verify: (value) => _saved({'notif_qiyam_enabled': value}));
    qiyamMinutes = draft.add<int>(
        key: 'qiyamMinutes',
        read: () => n.qiyamOffsetMinutes,
        write: n.setQiyamOffset,
        verify: (value) => _saved({'notif_qiyam_offset': value}));
    friday = draft.add<bool>(
        key: 'friday',
        read: () => n.fridayReminderEnabled,
        write: n.toggleFridayReminder,
        verify: (value) => _saved({'notif_friday_enabled': value}));
    sound = draft.add<AdhanSoundMode>(
        key: 'sound',
        read: () => n.soundMode,
        write: n.setSoundMode,
        verify: (value) => _saved({'notif_sound_mode': value.name}));
    iqamahMinutes = draft.add<int>(
        key: 'iqamahMinutes',
        read: () => n.iqamahOffsetMinutes,
        write: n.setIqamahOffsetMinutes,
        verify: (value) => _saved({'notif_iqamah_offset': value}));
    fajr = draft.add<bool>(
        key: 'fajr',
        read: () => n.fajrDistinctVoiceEnabled,
        write: n.toggleFajrDistinctVoice,
        verify: (value) => _saved({'notif_fajr_distinct': value}));
    iqamahVoice = draft.add<String>(
        key: 'iqamahVoice',
        read: () => n.selectedIqamahVoice,
        write: n.setSelectedIqamahVoice,
        verify: (value) => _saved({'notif_selected_iqamah': value}));
    morning = draft.add<bool>(
        key: 'morning',
        read: () => n.morningAdhkarEnabled,
        write: n.toggleMorningAdhkar,
        verify: (value) async =>
            await _saved({'notif_morning_adhkar_enabled': value}) &&
            n.adhkarScheduleConfirmed('morning'));
    evening = draft.add<bool>(
        key: 'evening',
        read: () => n.eveningAdhkarEnabled,
        write: n.toggleEveningAdhkar,
        verify: (value) async =>
            await _saved({'notif_evening_adhkar_enabled': value}) &&
            n.adhkarScheduleConfirmed('evening'));
    sleep = draft.add<bool>(
        key: 'sleep',
        read: () => n.sleepAdhkarEnabled,
        write: n.toggleSleepAdhkar,
        verify: (value) async =>
            await _saved({'notif_sleep_adhkar_enabled': value}) &&
            n.adhkarScheduleConfirmed('sleep'));
    shake = draft.add<bool>(
        key: 'shake',
        read: () => sensors.shakeToStopEnabled,
        write: sensors.toggleShakeToStop,
        verify: (value) => _saved({'notif_shake_to_stop': value}));
    flip = draft.add<bool>(
        key: 'flip',
        read: () => sensors.flipToMuteEnabled,
        write: sensors.toggleFlipToMute,
        verify: (value) => _saved({'notif_flip_to_mute': value}));
    overlay = draft.add<bool>(
        key: 'overlay',
        read: () => sensors.overlayWindowEnabled,
        write: sensors.toggleOverlayWindow,
        verify: (value) => _saved({'notif_overlay_window': value}));
    for (final prayer in prayers) {
      prayerEnabled[prayer] = draft.add<bool>(
          key: 'prayer_$prayer',
          read: () => n.isPrayerEnabled(prayer),
          write: (value) => n.togglePrayer(prayer, value),
          verify: (value) => _saved({'notif_prayer_$prayer': value}));
      prePrayerEnabled[prayer] = draft.add<bool>(
          key: 'prePrayer_$prayer',
          read: () => n.isPreReminderPrayerEnabled(prayer),
          write: (value) => n.togglePreReminderPrayer(prayer, value),
          verify: (value) =>
              _saved({'notif_pre_reminder_prayer_$prayer': value}));
      voices[prayer] = draft.add<String>(
          key: 'voice_$prayer',
          read: () => n.getPrayerVoice(prayer),
          write: (value) => n.setPrayerVoice(prayer, value),
          verify: (value) => _saved({'notif_prayer_voice_$prayer': value}));
    }
    for (final key in ['salawat', 'istighfar']) {
      shortFrequencies[key] = draft.add<ShortReminderFrequency>(
          key: 'short_$key',
          read: () => n.shortFrequency(key),
          write: (value) => n.setShortReminderFrequency(key, value),
          verify: (value) async =>
              await _saved({'notif_short_${key}_frequency': value.name}) &&
              n.shortReminderError(key) == null);
    }
    morningTime = _time('morning', () => n.morningAdhkarHour,
        () => n.morningAdhkarMinute, n.setMorningAdhkarTime);
    eveningTime = _time('evening', () => n.eveningAdhkarHour,
        () => n.eveningAdhkarMinute, n.setEveningAdhkarTime);
    sleepTime = _time('sleep', () => n.sleepAdhkarHour,
        () => n.sleepAdhkarMinute, n.setSleepAdhkarTime);
  }
  final SettingsDraft draft = SettingsDraft();
  static const prayers = ['الفجر', 'الظهر', 'العصر', 'المغرب', 'العشاء'];
  final voices = <String, DraftSetting<String>>{};
  final prayerEnabled = <String, DraftSetting<bool>>{};
  final prePrayerEnabled = <String, DraftSetting<bool>>{};
  final shortFrequencies = <String, DraftSetting<ShortReminderFrequency>>{};
  late final DraftSetting<LanguageChoice> language;
  late final DraftSetting<({bool settings, bool notifications})> master;
  late final DraftSetting<({int hour, int minute})> morningTime,
      eveningTime,
      sleepTime;
  late final DraftSetting<double> font;
  late final DraftSetting<String> reciter;
  late final DraftSetting<String> method;
  late final DraftSetting<int> hijri;
  late final DraftSetting<String> quality;
  late final DraftSetting<double> speed;
  late final DraftSetting<int> repeat;
  late final DraftSetting<String> tafsir;
  late final DraftSetting<String> fiqh;
  late final DraftSetting<bool> silent;
  late final DraftSetting<bool> sunan;
  late final DraftSetting<String> theme;
  late final DraftSetting<bool> sharawi;
  late final DraftSetting<bool> volume;
  late final DraftSetting<bool> slider;
  late final DraftSetting<bool> wifi;
  late final DraftSetting<String> mode;
  late final DraftSetting<String> layout;
  late final DraftSetting<String> numbering;
  late final DraftSetting<bool> autoplay;
  late final DraftSetting<bool> screen;
  late final DraftSetting<bool> pre;
  late final DraftSetting<int> preMinutes;
  late final DraftSetting<bool> qiyam;
  late final DraftSetting<int> qiyamMinutes;
  late final DraftSetting<bool> friday;
  late final DraftSetting<AdhanSoundMode> sound;
  late final DraftSetting<int> iqamahMinutes;
  late final DraftSetting<bool> fajr;
  late final DraftSetting<String> iqamahVoice;
  late final DraftSetting<bool> morning;
  late final DraftSetting<bool> evening;
  late final DraftSetting<bool> sleep;
  late final DraftSetting<bool> shake;
  late final DraftSetting<bool> flip;
  late final DraftSetting<bool> overlay;

  void stageLanguage(String code) {
    final current = language.value;
    final match = QuranTranslationEdition.availableTranslations
        .where((value) => value.languageCode == code)
        .firstOrNull;
    language.stage((
      language: code,
      translation:
          code != 'ar' && match != null ? match.id : current.translation,
      bilingual: code != 'ar' && match != null ? true : current.bilingual
    ));
  }

  DraftSetting<({int hour, int minute})> _time(String key, int Function() hour,
          int Function() minute, Future<void> Function(int, int) write) =>
      draft.add(
          key: '${key}Time',
          read: () => (hour: hour(), minute: minute()),
          write: (value) => write(value.hour, value.minute),
          verify: (value) async =>
              await _saved({
                'notif_${key}_adhkar_hour': value.hour,
                'notif_${key}_adhkar_minute': value.minute
              }) &&
              PrayerNotificationService.instance.adhkarScheduleConfirmed(key));

  static Future<bool> _saved(Map<String, Object> expected) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return expected.entries
        .every((entry) => prefs.get(entry.key) == entry.value);
  }
}
