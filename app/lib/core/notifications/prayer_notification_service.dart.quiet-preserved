import 'dart:async';
import 'notification_destination.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import '../../app/router.dart';
import '../services/islamic_audio_service.dart';
import '../services/prayer_service.dart';
import '../services/adhan_sensor_gesture_service.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) {
  if (notificationResponse.actionId == 'stop_adhan') {
    PrayerNotificationService.instance.stopAdhanAudio();
  } else if (notificationResponse.actionId == 'snooze_5') {
    PrayerNotificationService.instance.stopAdhanAudio();
    String prayer = 'الصلاة';
    final payload = notificationResponse.payload;
    if (payload != null && payload.isNotEmpty) {
      try {
        final uri = Uri.parse('app://adhan?$payload');
        prayer = uri.queryParameters['prayer'] ?? 'الصلاة';
      } catch (_) {}
    }
    PrayerNotificationService.instance.snoozeAdhan(5, prayer);
  }
}

enum ShortReminderFrequency { off, halfHourly, hourly, twoHourly, daily }

enum AdhanSoundMode {
  fullAdhan,
  takbeerat,
  softBeep,
  vibrateOnly,
  silent,
}

class PrayerNotificationService extends ChangeNotifier {
  static final PrayerNotificationService instance = PrayerNotificationService._internal();
  PrayerNotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;
  int _derivedScheduleGeneration = 0;
  Future<void>? _activeDerivedOp;

  String? _prayerSchedulingError;
  String? get prayerSchedulingError => _prayerSchedulingError;

  /// Retries existing saved choices only. Does not request or grant permission.
  Future<void> retryPrayerScheduling() async {
    final data = PrayerService.instance.currentData;
    if (!_masterEnabled) {
      _prayerSchedulingError = 'تنبيهات الصلاة معطلة في إعدادات التطبيق.';
      notifyListeners();
    } else if (data == null) {
      _prayerSchedulingError = 'لم تُجدول تنبيهات الصلاة: حدّث موقع الصلاة أولاً ثم أعد المحاولة.';
      notifyListeners();
    } else {
      await schedulePrayerNotifications(data);
    }
  }

  static final StreamController<String> _adhanEventStream = StreamController<String>.broadcast();
  static Stream<String> get adhanEventStream => _adhanEventStream.stream;

  final Map<String, ShortReminderFrequency> _shortFrequencies = {
    'salawat': ShortReminderFrequency.off,
    'istighfar': ShortReminderFrequency.off,
  };
  final Map<String, String?> _shortErrors = {};
  bool _shortBusy = false;
  Future<void>? _shortOperation;
  int _shortGeneration = 0;
  bool get shortReminderBusy => _shortBusy;
  ShortReminderFrequency shortFrequency(String key) =>
      _shortFrequencies[key] ?? ShortReminderFrequency.off;
  String? shortReminderError(String key) => _shortErrors[key];
  static const shortReminderIds = {'salawat': 805, 'istighfar': 806};

  Future<void>? _shortPreferenceOperation;
  Future<void> setShortReminderFrequency(String key, ShortReminderFrequency value) async {
    if (!shortReminderIds.containsKey(key)) throw ArgumentError.value(key);
    final prior = _shortPreferenceOperation;
    final gate = Completer<void>();
    _shortPreferenceOperation = gate.future;
    try {
      if (prior != null) await prior;
      final prefs = await SharedPreferences.getInstance();
      try {
        final saved = await prefs.setString('notif_short_${key}_frequency', value.name);
        if (!saved) throw StateError('Reminder preference was not saved');
      } catch (_) {
        await prefs.reload();
        rethrow;
      }
      _shortFrequencies[key] = value;
      await scheduleShortReminders();
    } finally {
      if (!gate.isCompleted) gate.complete();
      if (identical(_shortPreferenceOperation, gate.future)) _shortPreferenceOperation = null;
    }
  }

  Future<void> scheduleShortReminders() async {
    final generation = ++_shortGeneration;
    final prior = _shortOperation;
    final gate = Completer<void>();
    _shortOperation = gate.future;
    _shortBusy = true;
    notifyListeners();
    try {
      if (prior != null) await prior;
      if (generation != _shortGeneration) return;
      for (final entry in shortReminderIds.entries) {
        final key = entry.key;
        try {
          await _localNotifications.cancel(entry.value);
          if (generation != _shortGeneration) return;
          _shortErrors[key] = null;
          final frequency = shortFrequency(key);
          if (!_masterEnabled ||
              !_isInitialized ||
              frequency == ShortReminderFrequency.off) { continue; }
          final android =
              _localNotifications.resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin>();
          final allowed = await android?.areNotificationsEnabled();
          if (generation != _shortGeneration) return;
          if (allowed != true) {
            _shortErrors[key] =
                'لم يتم تفعيل التذكير. اسمح بإشعارات التطبيق من إعدادات الجهاز ثم أعد المحاولة.';
            continue;
          }
          await _localNotifications.periodicallyShowWithDuration(
            entry.value,
            key == 'salawat' ? 'الصلاة على النبي' : 'الاستغفار والحوقلة',
            key == 'salawat'
                ? 'اللهم صل وسلم على نبينا محمد'
                : 'أستغفر الله وأتوب إليه. لا حول ولا قوة إلا بالله',
            switch (frequency) {
              ShortReminderFrequency.halfHourly => const Duration(minutes: 30),
              ShortReminderFrequency.hourly => const Duration(hours: 1),
              ShortReminderFrequency.twoHourly => const Duration(hours: 2),
              ShortReminderFrequency.daily => const Duration(days: 1),
              ShortReminderFrequency.off => throw StateError('disabled'),
            },
            NotificationDetails(
                android: AndroidNotificationDetails(
              'short_${key}_reminder_v1',
              key == 'salawat'
                  ? 'تذكير الصلاة على النبي'
                  : 'تذكير الاستغفار والحوقلة',
              importance: Importance.high,
              priority: Priority.high,
              sound: RawResourceAndroidNotificationSound('reminder_$key'),
              playSound: true,
            )),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            payload: 'type=short_reminder&kind=$key',
          );
          if (generation != _shortGeneration) return;
        } catch (_) {
          _shortErrors[key] =
              'تعذر تحديث التذكير. قد يبقى الإعداد السابق فعالاً. أعد المحاولة.';
        }
      }
    } finally {
      if (!gate.isCompleted) gate.complete();
      if (identical(_shortOperation, gate.future)) {
        _shortOperation = null;
        _shortBusy = false;
      }
      notifyListeners();
    }
  }

  bool _masterEnabled = true;
  AdhanSoundMode _soundMode = AdhanSoundMode.fullAdhan;
  bool _vibrateOnStop = true;
  DateTime? _muteUntil;
  String _selectedAdhanVoice = 'adhan_makkah';
  String _selectedFajrVoice = 'adhan_fajr';
  final Map<String, String> _prayerAdhanVoices = {
    'الفجر': 'adhan_fajr',
    'الظهر': 'adhan_makkah',
    'العصر': 'adhan_madinah',
    'المغرب': 'adhan_cairo',
    'العشاء': 'adhan_aqsa',
  };
  String _selectedIqamahVoice = 'iqamah_full';
  bool _iqamahReminderEnabled = true;
  int _iqamahOffsetMinutes = 15;
  bool _preReminderEnabled = true;
  int _preReminderMinutes = 10;
  bool _preReminderVoiceEnabled = true;
  final Map<String, bool> _preReminderPrayerToggles = {
    'الفجر': true,
    'الظهر': true,
    'العصر': true,
    'المغرب': true,
    'العشاء': true,
  };
  bool _qiyamReminderEnabled = true;
  int _qiyamOffsetMinutes = 60;
  bool _fridayReminderEnabled = true;
  int _fridayReminderHour = 9;
  bool _duhaReminderEnabled = true;
  int _duhaReminderMinutesAfterSunrise = 25;
  bool _fajrDistinctVoiceEnabled = true;
  bool _postPrayerAdhkarReminderEnabled = true;
  int _postPrayerAdhkarMinutes = 5;

  // Adhkar Reminders Timing & States
  bool _morningAdhkarEnabled = true;
  int _morningAdhkarHour = 7;
  int _morningAdhkarMinute = 0;

  bool _eveningAdhkarEnabled = true;
  int _eveningAdhkarHour = 17;
  int _eveningAdhkarMinute = 0;

  bool _sleepAdhkarEnabled = true;
  int _sleepAdhkarHour = 22;
  int _sleepAdhkarMinute = 30;

  /// Dedicated notification ID ranges with strict ownership:
  /// - 100..399: Location-derived prayer notifications ONLY (adhan, pre-reminder,
  ///   iqamah, post-prayer adhkar, sunrise, duha, fajr-derived qiyam).
  /// - 801..803: Fixed-clock daily Adhkar reminders.
  /// - 804: Fixed-clock Friday Sunnahs & Al-Kahf reminder (split out of legacy 100..139).
  /// - 880..881: FajrQiyamAlarmService (880 derived Pre-Fajr, 881 Qiyam).
  /// - 990: KhatmaService fixed-clock reminder.
  /// - 995: Adhan snooze notification (cancelled by policy when location -> UNKNOWN).
  static const int prayerDerivedNotificationIdStart = 100;
  static const int prayerDerivedNotificationIdEnd = 399;
  static const int morningAdhkarNotificationId = 801;
  static const int eveningAdhkarNotificationId = 802;
  static const int sleepAdhkarNotificationId = 803;
  static const int fridayReminderNotificationId = 804;
  static const int adhanSnoozeNotificationId = 995;

  final Map<String, bool> _prayerToggles = {
    'الفجر': true,
    'الشروق': false,
    'الظهر': true,
    'العصر': true,
    'المغرب': true,
    'العشاء': true,
  };

  bool get masterEnabled => _masterEnabled;
  AdhanSoundMode get soundMode => _soundMode;
  bool get vibrateOnStop => _vibrateOnStop;
  DateTime? get muteUntil => _muteUntil;
  bool get isTemporarilyMuted => _muteUntil != null && _muteUntil!.isAfter(DateTime.now());
  String get selectedAdhanVoice => _selectedAdhanVoice;
  String get selectedFajrVoice => _selectedFajrVoice;
  Map<String, String> get prayerAdhanVoices => Map.unmodifiable(_prayerAdhanVoices);

  String getPrayerVoice(String prayerName) {
    if (prayerName.contains('فجر') || prayerName.contains('الفجر')) {
      return _prayerAdhanVoices['الفجر'] ?? _selectedFajrVoice;
    }
    return _prayerAdhanVoices[prayerName] ?? _selectedAdhanVoice;
  }
  String get selectedIqamahVoice => _selectedIqamahVoice;
  bool get iqamahReminderEnabled => _iqamahReminderEnabled;
  int get iqamahOffsetMinutes => _iqamahOffsetMinutes;
  bool get preReminderEnabled => _preReminderEnabled;
  int get preReminderMinutes => _preReminderMinutes;
  bool get preReminderVoiceEnabled => _preReminderVoiceEnabled;
  Map<String, bool> get preReminderPrayerToggles => _preReminderPrayerToggles;
  bool isPreReminderPrayerEnabled(String prayerName) => _preReminderPrayerToggles[prayerName] ?? true;
  bool get qiyamReminderEnabled => _qiyamReminderEnabled;
  int get qiyamOffsetMinutes => _qiyamOffsetMinutes;
  bool get fridayReminderEnabled => _fridayReminderEnabled;
  int get fridayReminderHour => _fridayReminderHour;
  bool get duhaReminderEnabled => _duhaReminderEnabled;
  int get duhaReminderMinutesAfterSunrise => _duhaReminderMinutesAfterSunrise;
  bool get fajrDistinctVoiceEnabled => _fajrDistinctVoiceEnabled;
  bool get postPrayerAdhkarReminderEnabled => _postPrayerAdhkarReminderEnabled;
  int get postPrayerAdhkarMinutes => _postPrayerAdhkarMinutes;

  // Morning, Evening, and Sleep Adhkar Getters
  bool get morningAdhkarEnabled => _morningAdhkarEnabled;
  int get morningAdhkarHour => _morningAdhkarHour;
  int get morningAdhkarMinute => _morningAdhkarMinute;
  TimeOfDay get morningAdhkarTime => TimeOfDay(hour: _morningAdhkarHour, minute: _morningAdhkarMinute);

  bool get eveningAdhkarEnabled => _eveningAdhkarEnabled;
  int get eveningAdhkarHour => _eveningAdhkarHour;
  int get eveningAdhkarMinute => _eveningAdhkarMinute;
  TimeOfDay get eveningAdhkarTime => TimeOfDay(hour: _eveningAdhkarHour, minute: _eveningAdhkarMinute);

  bool get sleepAdhkarEnabled => _sleepAdhkarEnabled;
  int get sleepAdhkarHour => _sleepAdhkarHour;
  int get sleepAdhkarMinute => _sleepAdhkarMinute;
  TimeOfDay get sleepAdhkarTime => TimeOfDay(hour: _sleepAdhkarHour, minute: _sleepAdhkarMinute);
  Map<String, bool> get prayerToggles => _prayerToggles;

  bool isPrayerEnabled(String prayerName) => _prayerToggles[prayerName] ?? true;

  static bool _tzInitialized = false;

  static void _ensureTimeZonesInitialized() {
    if (!_tzInitialized) {
      tz.initializeTimeZones();
      _tzInitialized = true;
    }
  }

  Future<void> init({bool forceReload = false}) async {
    if (_isInitialized && !forceReload) return;

    _ensureTimeZonesInitialized();
    try {
      final String timeZoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZoneName));
    } catch (e) {
      debugPrint('Local timezone detection fallback: $e');
    }

    const androidSettings = AndroidInitializationSettings('@drawable/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    try {
      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          _handleNotificationResponse(response);
        },
        onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      );

      final launchDetails = await _localNotifications.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp == true &&
          launchDetails?.notificationResponse != null) {
        final payload = launchDetails!.notificationResponse!.payload;
        if (payload != null && payload.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _handlePayloadNavigation(payload, notificationId: launchDetails.notificationResponse!.id);
          });
        }
      }
    } catch (e) {
      debugPrint('Notification init exception: $e');
    }

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      try {
        await androidPlugin.requestNotificationsPermission();
      } catch (e) {
        debugPrint('requestNotificationsPermission error: $e');
      }
      try {
        await androidPlugin.requestExactAlarmsPermission();
      } catch (e) {
        debugPrint('requestExactAlarmsPermission error: $e');
      }

      await _createNotificationChannels(androidPlugin);
    }

    final prefs = await SharedPreferences.getInstance();
    for (final key in shortReminderIds.keys) {
      final stored = prefs.getString('notif_short_${key}_frequency');
      _shortFrequencies[key] = ShortReminderFrequency.values.firstWhere(
          (value) => value.name == stored,
          orElse: () => ShortReminderFrequency.off);
    }
    _masterEnabled = prefs.getBool('notif_master_enabled') ?? true;
    _preReminderEnabled = prefs.getBool('notif_pre_reminder_enabled') ?? true;
    _preReminderMinutes = prefs.getInt('notif_pre_reminder') ?? 10;
    _preReminderVoiceEnabled = prefs.getBool('notif_pre_reminder_voice_enabled') ?? true;
    for (final p in _preReminderPrayerToggles.keys) {
      _preReminderPrayerToggles[p] = prefs.getBool('notif_pre_reminder_prayer_$p') ?? true;
    }
    _selectedAdhanVoice = prefs.getString('notif_selected_adhan') ?? 'adhan_makkah';
    _selectedFajrVoice = prefs.getString('notif_selected_fajr_adhan') ?? 'adhan_fajr';
    for (final p in _prayerAdhanVoices.keys) {
      final defaultVoice = (p == 'الفجر') ? _selectedFajrVoice : _selectedAdhanVoice;
      _prayerAdhanVoices[p] = prefs.getString('notif_prayer_voice_$p') ?? defaultVoice;
    }
    _selectedIqamahVoice = prefs.getString('notif_selected_iqamah') ?? 'iqamah_full';
    _iqamahReminderEnabled = prefs.getBool('notif_iqamah_enabled') ?? true;
    _iqamahOffsetMinutes = prefs.getInt('notif_iqamah_offset') ?? 15;
    _qiyamReminderEnabled = prefs.getBool('notif_qiyam_enabled') ?? true;
    _qiyamOffsetMinutes = prefs.getInt('notif_qiyam_offset') ?? 60;
    _fridayReminderEnabled = prefs.getBool('notif_friday_enabled') ?? true;
    _fridayReminderHour = prefs.getInt('notif_friday_hour') ?? 9;
    _duhaReminderEnabled = prefs.getBool('notif_duha_enabled') ?? true;
    _duhaReminderMinutesAfterSunrise = prefs.getInt('notif_duha_offset') ?? 25;
    _fajrDistinctVoiceEnabled = prefs.getBool('notif_fajr_distinct') ?? true;
    _postPrayerAdhkarReminderEnabled = prefs.getBool('notif_post_adhkar_enabled') ?? true;
    _postPrayerAdhkarMinutes = prefs.getInt('notif_post_adhkar_offset') ?? 5;

    _morningAdhkarEnabled = prefs.getBool('notif_morning_adhkar_enabled') ?? true;
    _morningAdhkarHour = prefs.getInt('notif_morning_adhkar_hour') ?? 7;
    _morningAdhkarMinute = prefs.getInt('notif_morning_adhkar_minute') ?? 0;

    _eveningAdhkarEnabled = prefs.getBool('notif_evening_adhkar_enabled') ?? true;
    _eveningAdhkarHour = prefs.getInt('notif_evening_adhkar_hour') ?? 17;
    _eveningAdhkarMinute = prefs.getInt('notif_evening_adhkar_minute') ?? 0;

    _sleepAdhkarEnabled = prefs.getBool('notif_sleep_adhkar_enabled') ?? true;
    _sleepAdhkarHour = prefs.getInt('notif_sleep_adhkar_hour') ?? 22;
    _sleepAdhkarMinute = prefs.getInt('notif_sleep_adhkar_minute') ?? 30;

    _vibrateOnStop = prefs.getBool('notif_vibrate_on_stop') ?? true;
    final muteStr = prefs.getString('notif_mute_until');
    if (muteStr != null) {
      final parsed = DateTime.tryParse(muteStr);
      if (parsed != null && parsed.isAfter(DateTime.now())) {
        _muteUntil = parsed;
      }
    }

    final soundStr = prefs.getString('notif_sound_mode') ?? 'fullAdhan';
    _soundMode = AdhanSoundMode.values.firstWhere(
      (m) => m.name == soundStr,
      orElse: () => AdhanSoundMode.fullAdhan,
    );

    for (final p in _prayerToggles.keys) {
      _prayerToggles[p] = prefs.getBool('notif_prayer_$p') ?? (p != 'الشروق');
    }

    try {
      await AdhanSensorGestureService.instance.init();
    } catch (_) {}

    _isInitialized = true;
    await scheduleShortReminders();
    try {
      scheduleAdhkarReminders();
    } catch (_) {}
    notifyListeners();
  }

  /// Stops current playing Adhan audio through the audio service
  void stopAdhanAudio() {
    try {
      IslamicAudioService.instance.stop();
    } catch (_) {}
  }

  /// Snoozes Adhan alert for specified minutes and schedules follow-up reminder
  Future<void> snoozeAdhan(int minutes, [String? prayerName]) async {
    _ensureTimeZonesInitialized();
    stopAdhanAudio();
    final now = DateTime.now();
    final snoozeTime = now.add(Duration(minutes: minutes));
    final scheduledTz = tz.TZDateTime.from(snoozeTime, tz.local);
    final prayer = prayerName ?? 'الصلاة';

    const androidDetails = AndroidNotificationDetails(
      'prayer_reminder_channel',
      'تذكير ما بعد الغفوة',
      channelDescription: 'تنبيه الأذان بعد انتهاء فترة الغفوة',
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      actions: [
        AndroidNotificationAction(
          'open_interactive',
          'فتح الشاشة التفاعلية 🕌',
          showsUserInterface: true,
        ),
      ],
    );

    try {
      await _localNotifications.zonedSchedule(
        adhanSnoozeNotificationId,
        'تذكير أذان $prayer (غفوة $minutes دقائق) ⏰',
        'انتهت فترة الغفوة — حان وقت أداء الصلاة والتطهر والوقوف بين يدي الله',
        scheduledTz,
        const NotificationDetails(android: androidDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'type=adhan&prayer=$prayer',
      );
    } catch (e) {
      debugPrint('Snooze schedule error: $e');
    }
  }

  void _handleNotificationResponse(NotificationResponse response) {
    if (response.actionId == 'stop_adhan') {
      stopAdhanAudio();
      return;
    }
    if (response.actionId == 'snooze_5') {
      stopAdhanAudio();
      String prayer = 'الصلاة';
      final payload = response.payload;
      if (payload != null && payload.isNotEmpty) {
        try {
          final uri = Uri.parse('app://adhan?$payload');
          prayer = uri.queryParameters['prayer'] ?? 'الصلاة';
        } catch (_) {}
      }
      snoozeAdhan(5, prayer);
      return;
    }

    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      _adhanEventStream.add(payload);
      _handlePayloadNavigation(payload, notificationId: response.id);
    }
  }

  void _handlePayloadNavigation(String payload, {int? notificationId}) {
    try {
      appRouter.push(notificationDestination(payload, notificationId: notificationId));
    } catch (e) {
      debugPrint('Payload navigation error: $e');
    }
  }

  /// Checks whether battery optimization exemption has been granted
  Future<bool> isBatteryOptimizationIgnored() async {
    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Requests battery optimization exemption for uninterrupted background alarms
  Future<bool> requestIgnoreBatteryOptimizations() async {
    try {
      final status = await Permission.ignoreBatteryOptimizations.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  Future<void> _createNotificationChannels(AndroidFlutterLocalNotificationsPlugin androidPlugin) async {
    final List<AndroidNotificationChannel> channels = [
      const AndroidNotificationChannel(
        'prayer_adhan_makkah_channel',
        'أذان المسجد الحرام (مكة المكرمة)',
        description: 'تنبيه نداء الحق بصوت الشيخ علي ملا',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('adhan_makkah'),
        enableVibration: true,
      ),
      const AndroidNotificationChannel(
        'prayer_adhan_madinah_channel',
        'أذان المسجد النبوي (المدينة المنورة)',
        description: 'تنبيه نداء الحق من رحاب المسجد النبوي الشريف',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('adhan_madinah'),
        enableVibration: true,
      ),
      const AndroidNotificationChannel(
        'prayer_adhan_cairo_channel',
        'أذان القاهرة ومصر (الشيخ محمد رفعت)',
        description: 'نداء الحق التاريخي لجامع الأزهر الشريف',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('adhan_cairo'),
        enableVibration: true,
      ),
      const AndroidNotificationChannel(
        'prayer_adhan_aqsa_channel',
        'أذان المسجد الأقصى المبارك',
        description: 'نداء الحق الخالد من مسرى رسول الله ﷺ',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('adhan_aqsa'),
        enableVibration: true,
      ),
      const AndroidNotificationChannel(
        'prayer_adhan_hussary_channel',
        'أذان الشيخ محمود خليل الحصري',
        description: 'أذان خاشع بمقام البيات المتزن',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('adhan_hussary'),
        enableVibration: true,
      ),
      const AndroidNotificationChannel(
        'prayer_adhan_fajr_channel',
        'أذان الفجر المبارك (الصلاة خير من النوم)',
        description: 'نداء الفجر الخاص بدخول وقت الفجر',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('adhan_fajr'),
        enableVibration: true,
      ),
      const AndroidNotificationChannel(
        'prayer_takbeerat_channel',
        'تكبيرات الأذان والعيدين',
        description: 'تكبيرات سريعة وخفيفة للتنبيه',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('takbeerat'),
        enableVibration: true,
      ),
      const AndroidNotificationChannel(
        'prayer_softbeep_channel',
        'نغمة إشعار هادئة للتنبيه',
        description: 'إشعار النظام القياسي عند دخول الوقت',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
      const AndroidNotificationChannel(
        'prayer_silent_channel',
        'تنبيه صامت (بدون صوت)',
        description: 'إشعار بصري فقط على شاشة القفل دون رنين',
        importance: Importance.high,
        playSound: false,
        enableVibration: false,
      ),
      const AndroidNotificationChannel(
        'prayer_vibrate_channel',
        'تنبيه اهتزاز فقط (بدون رنين)',
        description: 'اهتزاز قوي عند دخول وقت الصلاة دون تشغيل صوت الأذان',
        importance: Importance.max,
        playSound: false,
        enableVibration: true,
      ),
      const AndroidNotificationChannel(
        'prayer_iqamah_channel',
        'تنبيه إقامة الصلاة',
        description: 'تنبيه بحلول وقت إقامة الصلاة بصوت الإقامة',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('iqamah'),
        enableVibration: true,
      ),
      const AndroidNotificationChannel(
        'prayer_reminder_channel',
        'تذكير ما قبل الصلاة (افتراضي)',
        description: 'تذكير مسبق قبل حلول الأذان للاستعداد والتطهر',
        importance: Importance.high,
      ),
      const AndroidNotificationChannel(
        'prayer_approaching_fajr_channel',
        'تنبيه اقتراب صلاة الفجر (صوتي)',
        description: 'تنبيه صوتي مسبق: اقتربت صلاة الفجر يرجى الاستعداد والتطهر',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('approaching_fajr'),
        enableVibration: true,
      ),
      const AndroidNotificationChannel(
        'prayer_approaching_dhuhr_channel',
        'تنبيه اقتراب صلاة الظهر (صوتي)',
        description: 'تنبيه صوتي مسبق: اقتربت صلاة الظهر يرجى الاستعداد والتطهر',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('approaching_dhuhr'),
        enableVibration: true,
      ),
      const AndroidNotificationChannel(
        'prayer_approaching_asr_channel',
        'تنبيه اقتراب صلاة العصر (صوتي)',
        description: 'تنبيه صوتي مسبق: اقتربت صلاة العصر يرجى الاستعداد والتطهر',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('approaching_asr'),
        enableVibration: true,
      ),
      const AndroidNotificationChannel(
        'prayer_approaching_maghrib_channel',
        'تنبيه اقتراب صلاة المغرب (صوتي)',
        description: 'تنبيه صوتي مسبق: اقتربت صلاة المغرب يرجى الاستعداد والتطهر',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('approaching_maghrib'),
        enableVibration: true,
      ),
      const AndroidNotificationChannel(
        'prayer_approaching_isha_channel',
        'تنبيه اقتراب صلاة العشاء (صوتي)',
        description: 'تنبيه صوتي مسبق: اقتربت صلاة العشاء يرجى الاستعداد والتطهر',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('approaching_isha'),
        enableVibration: true,
      ),
      const AndroidNotificationChannel(
        'prayer_qiyam_channel',
        'تنبيه قيام الليل والتهجد',
        description: 'تذكير بالثلث الأخير من الليل لقيام الليل والدعاء',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('reminder_qiyam'),
        enableVibration: true,
      ),
      const AndroidNotificationChannel(
        'prayer_friday_channel',
        'تذكير سنن يوم الجمعة',
        description: 'تذكير بقراءة سورة الكهف والصلاة على النبي ﷺ',
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('reminder_salawat'),
        enableVibration: true,
      ),
      const AndroidNotificationChannel(
        'prayer_duha_channel',
        'تذكير صلاة الضحى',
        description: 'صلاة الأوابين بعد شروق الشمس بـ ٢٠-٣٠ دقيقة',
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('reminder_duha'),
        enableVibration: true,
      ),
      const AndroidNotificationChannel(
        'prayer_sunrise_channel',
        'تنبيه شروق الشمس',
        description: 'تنبيه بحلول وقت شروق الشمس وانتهاء وقت الفجر',
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('reminder_sunrise'),
        enableVibration: true,
      ),
      const AndroidNotificationChannel(
        'prayer_post_adhkar_channel',
        'أذكار ما بعد الصلاة المكتوبة',
        description: 'تذكير بالاستغفار والتسبيح وقراءة آية الكرسي دبر كل صلاة',
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('reminder_istighfar'),
        enableVibration: true,
      ),
      const AndroidNotificationChannel(
        'adhkar_morning_channel',
        'أذكار الصباح المباركة',
        description: 'تنبيه يومي لموعد أذكار الصباح وحصن المسلم',
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('reminder_istighfar'),
        enableVibration: true,
      ),
      const AndroidNotificationChannel(
        'adhkar_evening_channel',
        'أذكار المساء المباركة',
        description: 'تنبيه يومي لموعد أذكار المساء وحفظ النفس',
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('reminder_istighfar'),
        enableVibration: true,
      ),
      const AndroidNotificationChannel(
        'adhkar_sleep_channel',
        'أذكار النوم والسنن النبوية',
        description: 'تنبيه يومي لموعد أذكار النوم وسنن الاضطجاع',
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('reminder_istighfar'),
        enableVibration: true,
      ),
    ];

    for (final ch in channels) {
      try {
        await androidPlugin.createNotificationChannel(ch);
      } catch (e) {
        debugPrint('Channel create error for ${ch.id}: $e');
      }
    }
  }

  Future<void>? _masterOperation;
  Future<void> toggleMaster(bool enabled) async {
    final prior = _masterOperation;
    final gate = Completer<void>();
    _masterOperation = gate.future;
    try {
      if (prior != null) await prior;
      final prefs = await SharedPreferences.getInstance();
      try {
        final saved = await prefs.setBool('notif_master_enabled', enabled);
        if (!saved) throw StateError('Master preference was not saved');
      } catch (_) {
        await prefs.reload();
        rethrow;
      }
      _masterEnabled = enabled;
      if (!enabled) {
        await cancelAll();
      } else {
        rescheduleCurrentPrayers();
      }
      await scheduleShortReminders();
      notifyListeners();
    } finally {
      if (!gate.isCompleted) gate.complete();
      if (identical(_masterOperation, gate.future)) _masterOperation = null;
    }
  }

  Future<void> togglePrayer(String prayerName, bool enabled) async {
    _prayerToggles[prayerName] = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_prayer_$prayerName', enabled);
    rescheduleCurrentPrayers();
    notifyListeners();
  }

  Future<void> setSoundMode(AdhanSoundMode mode) async {
    _soundMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notif_sound_mode', mode.name);
    rescheduleCurrentPrayers();
    notifyListeners();
  }

  Future<void> toggleVibrateOnStop(bool enabled) async {
    _vibrateOnStop = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_vibrate_on_stop', enabled);
    notifyListeners();
  }

  Future<void> muteForDuration(Duration duration) async {
    _muteUntil = DateTime.now().add(duration);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notif_mute_until', _muteUntil!.toIso8601String());
    rescheduleCurrentPrayers();
    notifyListeners();
  }

  Future<void> cancelTemporaryMute() async {
    _muteUntil = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('notif_mute_until');
    rescheduleCurrentPrayers();
    notifyListeners();
  }

  /// Only keys with an explicit Android sound mapping can be newly assigned.
  /// Loading old preferences does not call this guard or change stored choices.
  static String? adhanAssignmentUnavailableReason(String voiceKey) {
    final unavailable = IslamicAudioService.unavailableRecordingReason(voiceKey);
    if (unavailable != null) return unavailable;
    const supported = {
      'adhan_makkah', 'adhan_madinah', 'adhan_fajr_madinah',
      'adhan_cairo', 'adhan_cairo_refaat', 'adhan_aqsa',
      'adhan_fajr_aqsa', 'adhan_hussary', 'adhan_fajr', 'takbeerat',
    };
    return supported.contains(voiceKey) ? null :
        'متاح للاستماع والتحميل فقط حاليا. تعيين هذا الصوت لأذان التنبيه غير مدعوم بعد. مواعيدك واختياراتك المحفوظة لم تتغير.';
  }

  void _requireAssignableAdhanRecording(String voiceKey) {
    final reason = adhanAssignmentUnavailableReason(voiceKey);
    if (reason != null) throw StateError(reason);
  }

  void _requireAvailableRecording(String voiceKey) {
    final reason = IslamicAudioService.unavailableRecordingReason(voiceKey);
    if (reason != null) throw StateError(reason);
  }

  Future<void> setSelectedAdhanVoice(String voiceKey) async {
    _requireAssignableAdhanRecording(voiceKey);
    _selectedAdhanVoice = voiceKey;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notif_selected_adhan', voiceKey);
    rescheduleCurrentPrayers();
    notifyListeners();
  }

  Future<void> setPrayerVoice(String prayerName, String voiceKey) async {
    _requireAssignableAdhanRecording(voiceKey);
    _prayerAdhanVoices[prayerName] = voiceKey;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notif_prayer_voice_$prayerName', voiceKey);
    if (prayerName.contains('فجر') || prayerName.contains('الفجر')) {
      _selectedFajrVoice = voiceKey;
      await prefs.setString('notif_selected_fajr_adhan', voiceKey);
    } else {
      _selectedAdhanVoice = voiceKey;
      await prefs.setString('notif_selected_adhan', voiceKey);
    }
    rescheduleCurrentPrayers();
    notifyListeners();
  }

  Future<void> setAllPrayersVoice(String voiceKey) async {
    _requireAssignableAdhanRecording(voiceKey);
    final prefs = await SharedPreferences.getInstance();
    for (final p in _prayerAdhanVoices.keys) {
      _prayerAdhanVoices[p] = voiceKey;
      await prefs.setString('notif_prayer_voice_$p', voiceKey);
    }
    _selectedAdhanVoice = voiceKey;
    await prefs.setString('notif_selected_adhan', voiceKey);
    rescheduleCurrentPrayers();
    notifyListeners();
  }

  Future<void> setSelectedFajrVoice(String voiceKey) async {
    _requireAssignableAdhanRecording(voiceKey);
    _selectedFajrVoice = voiceKey;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notif_selected_fajr_adhan', voiceKey);
    rescheduleCurrentPrayers();
    notifyListeners();
  }

  Future<void> setSelectedIqamahVoice(String voiceKey) async {
    _requireAvailableRecording(voiceKey);
    _selectedIqamahVoice = voiceKey;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notif_selected_iqamah', voiceKey);
    rescheduleCurrentPrayers();
    notifyListeners();
  }

  Future<void> toggleIqamahReminder(bool enabled) async {
    _iqamahReminderEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_iqamah_enabled', enabled);
    rescheduleCurrentPrayers();
    notifyListeners();
  }

  Future<void> setPrayerCustomVoice(String prayerName, String voiceKey) => setPrayerVoice(prayerName, voiceKey);
  Future<void> setIqamahVoice(String voiceKey) => setSelectedIqamahVoice(voiceKey);
  Future<void> setPreReminderMinutes(int minutes) => setPreReminder(minutes);
  Future<void> setIqamahOffsetMinutes(int minutes) => setIqamahOffset(minutes);

  Future<void> setIqamahOffset(int minutes) async {
    _iqamahOffsetMinutes = minutes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('notif_iqamah_offset', minutes);
    rescheduleCurrentPrayers();
    notifyListeners();
  }

  Future<void> togglePreReminder(bool enabled) async {
    _preReminderEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_pre_reminder_enabled', enabled);
    rescheduleCurrentPrayers();
    notifyListeners();
  }

  Future<void> setPreReminder(int minutes) async {
    _preReminderMinutes = minutes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('notif_pre_reminder', minutes);
    rescheduleCurrentPrayers();
    notifyListeners();
  }

  Future<void> togglePreReminderVoice(bool enabled) async {
    _preReminderVoiceEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_pre_reminder_voice_enabled', enabled);
    rescheduleCurrentPrayers();
    notifyListeners();
  }

  Future<void> togglePreReminderPrayer(String prayerName, bool enabled) async {
    _preReminderPrayerToggles[prayerName] = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_pre_reminder_prayer_$prayerName', enabled);
    rescheduleCurrentPrayers();
    notifyListeners();
  }

  Future<void> toggleQiyamReminder(bool enabled) async {
    _qiyamReminderEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_qiyam_enabled', enabled);
    rescheduleCurrentPrayers();
    notifyListeners();
  }

  Future<void> setQiyamOffset(int minutes) async {
    _qiyamOffsetMinutes = minutes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('notif_qiyam_offset', minutes);
    rescheduleCurrentPrayers();
    notifyListeners();
  }

  Future<void> toggleFridayReminder(bool enabled) async {
    _fridayReminderEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_friday_enabled', enabled);
    await scheduleFridayReminder();
    notifyListeners();
  }

  Future<void> setFridayReminderHour(int hour) async {
    _fridayReminderHour = hour;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('notif_friday_hour', hour);
    await scheduleFridayReminder();
    notifyListeners();
  }

  Future<void> toggleDuhaReminder(bool enabled) async {
    _duhaReminderEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_duha_enabled', enabled);
    rescheduleCurrentPrayers();
    notifyListeners();
  }

  Future<void> setDuhaOffset(int minutes) async {
    _duhaReminderMinutesAfterSunrise = minutes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('notif_duha_offset', minutes);
    rescheduleCurrentPrayers();
    notifyListeners();
  }

  Future<void> toggleFajrDistinctVoice(bool enabled) async {
    _fajrDistinctVoiceEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_fajr_distinct', enabled);
    rescheduleCurrentPrayers();
    notifyListeners();
  }

  Future<void> togglePostPrayerAdhkar(bool enabled) async {
    _postPrayerAdhkarReminderEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_post_adhkar_enabled', enabled);
    rescheduleCurrentPrayers();
    notifyListeners();
  }

  Future<void> setPostPrayerAdhkarOffset(int minutes) async {
    _postPrayerAdhkarMinutes = minutes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('notif_post_adhkar_offset', minutes);
    rescheduleCurrentPrayers();
    notifyListeners();
  }

  // Morning, Evening, and Sleep Adhkar Management
  Future<void> toggleMorningAdhkar(bool enabled) async {
    _morningAdhkarEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_morning_adhkar_enabled', enabled);
    await scheduleAdhkarReminders();
    notifyListeners();
  }

  Future<void> setMorningAdhkarTime(int hour, int minute) async {
    _morningAdhkarHour = hour;
    _morningAdhkarMinute = minute;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('notif_morning_adhkar_hour', hour);
    await prefs.setInt('notif_morning_adhkar_minute', minute);
    await scheduleAdhkarReminders();
    notifyListeners();
  }

  Future<void> toggleEveningAdhkar(bool enabled) async {
    _eveningAdhkarEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_evening_adhkar_enabled', enabled);
    await scheduleAdhkarReminders();
    notifyListeners();
  }

  Future<void> setEveningAdhkarTime(int hour, int minute) async {
    _eveningAdhkarHour = hour;
    _eveningAdhkarMinute = minute;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('notif_evening_adhkar_hour', hour);
    await prefs.setInt('notif_evening_adhkar_minute', minute);
    await scheduleAdhkarReminders();
    notifyListeners();
  }

  Future<void> toggleSleepAdhkar(bool enabled) async {
    _sleepAdhkarEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_sleep_adhkar_enabled', enabled);
    await scheduleAdhkarReminders();
    notifyListeners();
  }

  Future<void> setSleepAdhkarTime(int hour, int minute) async {
    _sleepAdhkarHour = hour;
    _sleepAdhkarMinute = minute;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('notif_sleep_adhkar_hour', hour);
    await prefs.setInt('notif_sleep_adhkar_minute', minute);
    await scheduleAdhkarReminders();
    notifyListeners();
  }

  static String formatTimeArabic(int hour, int minute) {
    final period = hour >= 12 ? 'م' : 'ص';
    final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final hStr = h12.toString().padLeft(2, '0');
    final mStr = minute.toString().padLeft(2, '0');
    return '$hStr:$mStr $period';
  }

  void rescheduleCurrentPrayers() {
    final cur = PrayerService.instance.currentData;
    if (cur != null) {
      schedulePrayerNotifications(cur);
    } else {
      cancelLocationDerivedNotifications(cancelStaleAdhanSnooze: false);
      scheduleAdhkarReminders();
    }
  }

  /// Zone-safe serializer for location-derived notification mutations so
  /// delayed `schedulePrayerNotifications` calls cannot interleave with or
  /// enqueue derived 100..399 notifications after an `UNKNOWN` cancellation.
  Future<T> _serializeDerivedOp<T>(Future<T> Function() action) async {
    final previous = _activeDerivedOp;
    final currentGate = Completer<void>();
    _activeDerivedOp = currentGate.future;
    if (previous != null) {
      try {
        await previous;
      } catch (_) {}
    }
    try {
      return await action();
    } finally {
      if (identical(_activeDerivedOp, currentGate.future)) {
        _activeDerivedOp = null;
      }
      if (!currentGate.isCompleted) {
        currentGate.complete();
      }
    }
  }

  Future<void> _cancelLocationDerivedRange(int generation) async {
    for (int id = prayerDerivedNotificationIdStart;
        id <= prayerDerivedNotificationIdEnd;
        id++) {
      if (generation != _derivedScheduleGeneration) return;
      try {
        await _localNotifications.cancel(id);
      } catch (_) {}
    }
  }

  /// Cancels ONLY location-derived prayer notifications (100..399, plus legacy
  /// pre-migration Friday slot if any), optionally cancels stale Adhan snooze
  /// (995) by policy, and migrates/rebuilds the fixed-clock Friday reminder on
  /// its dedicated ID (804). Never cancels Adhkar (801..803), Khatma (990), or
  /// fixed-clock Qiyam (881).
  Future<void> cancelLocationDerivedNotifications({
    bool cancelStaleAdhanSnooze = false,
  }) async {
    final int generation = ++_derivedScheduleGeneration;
    if (!_isInitialized) return;
    await _serializeDerivedOp<void>(() async {
      if (generation != _derivedScheduleGeneration || !_isInitialized) return;
      await _cancelLocationDerivedRange(generation);
      if (generation != _derivedScheduleGeneration) return;
      if (cancelStaleAdhanSnooze) {
        try {
          await _localNotifications.cancel(adhanSnoozeNotificationId);
        } catch (_) {}
      }
      if (generation != _derivedScheduleGeneration) return;
      await scheduleFridayReminder();
    });
  }

  /// Schedules or cancels the fixed-clock Friday Sunnahs & Al-Kahf reminder on
  /// its dedicated ID (804), independent of GPS location availability.
  Future<void> scheduleFridayReminder() async {
    if (!_isInitialized) return;
    if (!_masterEnabled || !_fridayReminderEnabled) {
      try {
        await _localNotifications.cancel(fridayReminderNotificationId);
      } catch (_) {}
      return;
    }
    _ensureTimeZonesInitialized();
    try {
      final now = DateTime.now();
      int daysUntilFriday = (DateTime.friday - now.weekday) % 7;
      var targetDate = now.add(Duration(days: daysUntilFriday));
      var fridayTime = DateTime(
        targetDate.year,
        targetDate.month,
        targetDate.day,
        _fridayReminderHour,
        0,
      );
      if (!fridayTime.isAfter(now)) {
        fridayTime = fridayTime.add(const Duration(days: 7));
      }

      final fridayTz = tz.TZDateTime.from(fridayTime, tz.local);
      final fridayDetails = AndroidNotificationDetails(
        'prayer_friday_channel',
        'تذكير سنن يوم الجمعة',
        channelDescription:
            'تذكير بقراءة سورة الكهف، الصلاة على النبي ﷺ، وساعة الاستجابة',
        importance: Importance.high,
        priority: Priority.high,
        playSound: _soundMode != AdhanSoundMode.silent &&
            _soundMode != AdhanSoundMode.vibrateOnly,
        sound: const RawResourceAndroidNotificationSound('reminder_salawat'),
        enableVibration: true,
      );

      await _localNotifications.zonedSchedule(
        fridayReminderNotificationId,
        'سنن يوم الجمعة المباركة 🕌',
        'نور ما بين الجمعتين: قراءة سورة الكهف، الإكثار من الصلاة على النبي ﷺ، والدعاء في ساعة الاستجابة',
        fridayTz,
        NotificationDetails(android: fridayDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('Error scheduling Friday reminder: $e');
    }
  }

  /// Sends an immediate test notification to verify audio & notification display
  Future<void> sendTestNotification({String? customVoice}) async {
    final voice = customVoice ?? _selectedAdhanVoice;
    final channelId = _resolveChannelIdForVoice(voice, isFajr: false);

    final androidDetails = AndroidNotificationDetails(
      channelId,
      'تجربة تنبيه الأذان',
      channelDescription: 'فحص فوري لصوت التنبيه وقناة الأذان',
      importance: Importance.max,
      priority: Priority.high,
      playSound: _soundMode != AdhanSoundMode.silent,
      sound: _resolveSoundForVoice(voice, isFajr: false),
      enableVibration: true,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      actions: const [
        AndroidNotificationAction(
          'stop_adhan',
          'إيقاف الأذان ⏹️',
          showsUserInterface: false,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          'snooze_5',
          'غفوة ٥ دقائق ⏰',
          showsUserInterface: false,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          'open_interactive',
          'فتح الشاشة التفاعلية 🕌',
          showsUserInterface: true,
        ),
      ],
    );

    await _localNotifications.show(
      999,
      'تجربة نداء الأذان 🕌 — تطبيق صديق المؤمن',
      'الله أكبر، الله أكبر.. خدمة الأذان والتنبيهات تعمل بأعلى كفاءة وجاهزية',
      NotificationDetails(android: androidDetails),
      payload: 'type=adhan&prayer=الظهر',
    );
  }

  /// Sends an immediate test Iqamah notification to verify alert sound
  Future<void> sendTestIqamahNotification({String? customVoice}) async {
    final voiceKey = customVoice ?? _selectedIqamahVoice;
    final rawSoundName = IslamicAudioService.allTracks
            .where((t) => t.id == voiceKey)
            .map((t) => t.rawNotificationSound)
            .firstOrNull ??
        'iqamah';
    final androidDetails = AndroidNotificationDetails(
      'prayer_iqamah_channel',
      'تنبيه إقامة الصلاة',
      channelDescription: 'تنبيه بحلول وقت إقامة الصلاة المكتوبة',
      importance: Importance.max,
      priority: Priority.high,
      playSound: _soundMode != AdhanSoundMode.silent,
      sound: RawResourceAndroidNotificationSound(rawSoundName),
      enableVibration: true,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      actions: const [
        AndroidNotificationAction(
          'stop_adhan',
          'إيقاف ⏹️',
          showsUserInterface: false,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          'open_interactive',
          'فتح الشاشة 🕌',
          showsUserInterface: true,
        ),
      ],
    );

    await _localNotifications.show(
      998,
      'تجربة إقامة الصلاة 🕌 — تطبيق صديق المؤمن',
      'قد قامت الصلاة، قد قامت الصلاة.. استعد للوقوف بين يدي الله بسكينة وخشوع',
      NotificationDetails(android: androidDetails),
      payload: 'type=iqamah&prayer=الظهر',
    );
  }

  String _resolveChannelIdForVoice(String voiceKey, {required bool isFajr}) {
    if (_soundMode == AdhanSoundMode.silent) {
      return 'prayer_silent_channel';
    }
    if (_soundMode == AdhanSoundMode.vibrateOnly) {
      return 'prayer_vibrate_channel';
    }
    if (_soundMode == AdhanSoundMode.softBeep) {
      return 'prayer_softbeep_channel';
    }
    if (_soundMode == AdhanSoundMode.takbeerat) {
      return 'prayer_takbeerat_channel';
    }

    switch (voiceKey) {
      case 'adhan_madinah':
      case 'adhan_fajr_madinah':
        return 'prayer_adhan_madinah_channel';
      case 'adhan_cairo':
      case 'adhan_cairo_refaat':
        return 'prayer_adhan_cairo_channel';
      case 'adhan_aqsa':
      case 'adhan_fajr_aqsa':
        return 'prayer_adhan_aqsa_channel';
      case 'adhan_hussary':
        return 'prayer_adhan_hussary_channel';
      case 'adhan_fajr':
        return 'prayer_adhan_fajr_channel';
      case 'takbeerat':
        return 'prayer_takbeerat_channel';
      case 'adhan_makkah':
      default:
        return 'prayer_adhan_makkah_channel';
    }
  }

  AndroidNotificationSound? _resolveSoundForVoice(String voiceKey, {required bool isFajr}) {
    if (_soundMode == AdhanSoundMode.silent || _soundMode == AdhanSoundMode.vibrateOnly) {
      return null;
    }
    if (_soundMode == AdhanSoundMode.softBeep) {
      return null; // Uses device default notification sound
    }
    if (_soundMode == AdhanSoundMode.takbeerat) {
      return const RawResourceAndroidNotificationSound('takbeerat');
    }

    switch (voiceKey) {
      case 'adhan_madinah':
      case 'adhan_fajr_madinah':
        return const RawResourceAndroidNotificationSound('adhan_madinah');
      case 'adhan_cairo':
      case 'adhan_cairo_refaat':
        return const RawResourceAndroidNotificationSound('adhan_cairo');
      case 'adhan_aqsa':
      case 'adhan_fajr_aqsa':
        return const RawResourceAndroidNotificationSound('adhan_aqsa');
      case 'adhan_hussary':
        return const RawResourceAndroidNotificationSound('adhan_hussary');
      case 'adhan_fajr':
        return const RawResourceAndroidNotificationSound('adhan_fajr');
      case 'takbeerat':
        return const RawResourceAndroidNotificationSound('takbeerat');
      case 'adhan_makkah':
      default:
        return const RawResourceAndroidNotificationSound('adhan_makkah');
    }
  }

  String _resolveApproachingChannelId(String prayerName) {
    if (!_preReminderVoiceEnabled || _soundMode == AdhanSoundMode.silent) {
      return 'prayer_reminder_channel';
    }
    if (prayerName.contains('فجر') || prayerName.contains('الفجر')) {
      return 'prayer_approaching_fajr_channel';
    } else if (prayerName.contains('ظهر') || prayerName.contains('الظهر')) {
      return 'prayer_approaching_dhuhr_channel';
    } else if (prayerName.contains('عصر') || prayerName.contains('العصر')) {
      return 'prayer_approaching_asr_channel';
    } else if (prayerName.contains('مغرب') || prayerName.contains('المغرب')) {
      return 'prayer_approaching_maghrib_channel';
    } else if (prayerName.contains('عشاء') || prayerName.contains('العشاء')) {
      return 'prayer_approaching_isha_channel';
    }
    return 'prayer_reminder_channel';
  }

  AndroidNotificationSound? _resolveApproachingSound(String prayerName) {
    if (!_preReminderVoiceEnabled ||
        _soundMode == AdhanSoundMode.silent ||
        _soundMode == AdhanSoundMode.vibrateOnly) {
      return null;
    }
    if (prayerName.contains('فجر') || prayerName.contains('الفجر')) {
      return const RawResourceAndroidNotificationSound('approaching_fajr');
    } else if (prayerName.contains('ظهر') || prayerName.contains('الظهر')) {
      return const RawResourceAndroidNotificationSound('approaching_dhuhr');
    } else if (prayerName.contains('عصر') || prayerName.contains('العصر')) {
      return const RawResourceAndroidNotificationSound('approaching_asr');
    } else if (prayerName.contains('مغرب') || prayerName.contains('المغرب')) {
      return const RawResourceAndroidNotificationSound('approaching_maghrib');
    } else if (prayerName.contains('عشاء') || prayerName.contains('العشاء')) {
      return const RawResourceAndroidNotificationSound('approaching_isha');
    }
    return null;
  }

  Future<void> sendTestPreReminderNotification(String prayerName) async {
    final approChannelId = _resolveApproachingChannelId(prayerName);
    final approSound = _resolveApproachingSound(prayerName);

    final androidDetails = AndroidNotificationDetails(
      approChannelId,
      'تنبيه اقتراب الصلاة',
      channelDescription: 'تنبيه صوتي مسبق للاستعداد والتطهر للصلاة',
      importance: Importance.max,
      priority: Priority.high,
      playSound: approSound != null,
      sound: approSound,
      enableVibration: true,
      category: AndroidNotificationCategory.reminder,
      actions: const [
        AndroidNotificationAction(
          'open_interactive',
          'فتح التطبيق 🕌',
          showsUserInterface: true,
        ),
      ],
    );

    await _localNotifications.show(
      996,
      'اقتربت صلاة $prayerName ⏳ (باقي $_preReminderMinutes دقائق)',
      'اقتربت صلاة $prayerName، يرجى الاستعداد والتطهر والتهيؤ للوقوف بين يدي الله',
      NotificationDetails(android: androidDetails),
      payload: 'type=prereminder&prayer=$prayerName',
    );
  }

  Future<void> schedulePrayerNotifications(PrayerData data) async {
    final int generation = ++_derivedScheduleGeneration;
    if (!_masterEnabled || !_isInitialized) return;

    await _serializeDerivedOp<void>(() async {
      bool isStale() =>
          generation != _derivedScheduleGeneration ||
          !_masterEnabled ||
          !_isInitialized;

      if (isStale()) return;

      try {
        final android = _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        if (android != null) {
          final notificationsAllowed = await android.areNotificationsEnabled();
          if (isStale()) return;
          final exactAllowed = await android.canScheduleExactNotifications();
          if (isStale()) return;
          if (notificationsAllowed == false || exactAllowed == false) {
            _prayerSchedulingError = notificationsAllowed == false
                ? 'لم تُجدول تنبيهات الصلاة: إشعارات التطبيق غير مسموحة. اسمح بها من إعدادات الجهاز ثم أعد المحاولة. لم نحذف الجدولة السابقة، لكن لا نعتمد عليها مع الإذن المغلق.'
                : 'لم تُجدول تنبيهات الصلاة: إذن المنبهات الدقيقة غير مسموح. اسمح به من إعدادات الجهاز ثم أعد المحاولة. لم نحذف الجدولة السابقة، لكن النظام قد يكون ألغاها عند سحب الإذن.';
            notifyListeners();
            return;
          }
        }
        await _cancelLocationDerivedRange(generation);
        if (isStale()) return;
        final now = DateTime.now();

        final prayers = data.notificationPrayers ?? data.prayers;
        int notificationId = prayerDerivedNotificationIdStart;
        for (final prayer in prayers) {
          if (isStale()) return;
          if (!isPrayerEnabled(prayer.name)) continue;
          if (isTemporarilyMuted && prayer.time.isBefore(_muteUntil!)) continue;

          if (prayer.name.contains('الشروق')) {
            if (prayer.time.isAfter(now)) {
              if (isStale()) return;
              final scheduledTz = tz.TZDateTime.from(prayer.time, tz.local);
              final sunriseDetails = AndroidNotificationDetails(
                'prayer_sunrise_channel',
                'تنبيه شروق الشمس',
                channelDescription: 'تنبيه بحلول وقت شروق الشمس وانتهاء وقت الفجر',
                importance: Importance.high,
                priority: Priority.high,
                playSound: _soundMode != AdhanSoundMode.silent && _soundMode != AdhanSoundMode.vibrateOnly,
                sound: const RawResourceAndroidNotificationSound('reminder_sunrise'),
                enableVibration: _soundMode != AdhanSoundMode.silent,
              );
              await _localNotifications.zonedSchedule(
                notificationId++,
                'شروق الشمس 🌅',
                'أشرقت الشمس.. تقبل الله طاعاتكم وصالح أعمالكم',
                scheduledTz,
                NotificationDetails(android: sunriseDetails),
                androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
                uiLocalNotificationDateInterpretation:
                    UILocalNotificationDateInterpretation.absoluteTime,
              );
              if (isStale()) return;
            }
            continue;
          }

          // Schedule Main Adhan / Prayer Time Notification only if prayer time is in the future
          if (prayer.time.isAfter(now)) {
            if (isStale()) return;
            final scheduledTz = tz.TZDateTime.from(prayer.time, tz.local);
            final isFajr = prayer.name.contains('الفجر');
            final prayerVoice = getPrayerVoice(prayer.name);
            final channelId = _resolveChannelIdForVoice(prayerVoice, isFajr: isFajr);
            final sound = _resolveSoundForVoice(prayerVoice, isFajr: isFajr);

            final androidDetails = AndroidNotificationDetails(
              channelId,
              isFajr ? 'أذان الفجر المبارك' : 'مواقيت الصلاة والأذان',
              channelDescription: 'تنبيهات دخول أوقات الصلوات المفروضة ونداء الحق',
              importance: Importance.max,
              priority: Priority.high,
              playSound: _soundMode != AdhanSoundMode.silent && _soundMode != AdhanSoundMode.vibrateOnly,
              sound: sound,
              enableVibration: _soundMode != AdhanSoundMode.silent,
              fullScreenIntent: true,
              category: AndroidNotificationCategory.alarm,
              actions: const [
                AndroidNotificationAction(
                  'stop_adhan',
                  'إيقاف الأذان ⏹️',
                  showsUserInterface: false,
                  cancelNotification: true,
                ),
                AndroidNotificationAction(
                  'snooze_5',
                  'غفوة ٥ دقائق ⏰',
                  showsUserInterface: false,
                  cancelNotification: true,
                ),
                AndroidNotificationAction(
                  'open_interactive',
                  'فتح الشاشة التفاعلية 🕌',
                  showsUserInterface: true,
                ),
              ],
            );

            await _localNotifications.zonedSchedule(
              notificationId++,
              'حان الآن موعد صلاة ${prayer.name} 🕌',
              'الله أكبر الله أكبر — حي على الصلاة، حي على الفلاح (${data.locationName})',
              scheduledTz,
              NotificationDetails(android: androidDetails),
              androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
              uiLocalNotificationDateInterpretation:
                  UILocalNotificationDateInterpretation.absoluteTime,
              payload: 'type=adhan&prayer=${prayer.name}',
            );
            if (isStale()) return;
          }

          // Schedule Pre-reminder if enabled
          if (_preReminderEnabled && _preReminderMinutes > 0 && isPreReminderPrayerEnabled(prayer.name) && prayer.name != 'الشروق') {
            final preTime = prayer.time.subtract(Duration(minutes: _preReminderMinutes));
            if (preTime.isAfter(now)) {
              if (isStale()) return;
              final preTz = tz.TZDateTime.from(preTime, tz.local);
              final approChannelId = _resolveApproachingChannelId(prayer.name);
              final approSound = _resolveApproachingSound(prayer.name);

              await _localNotifications.zonedSchedule(
                notificationId++,
                'اقتربت صلاة ${prayer.name} ⏳ (متبقي $_preReminderMinutes دقيقة)',
                'اقتربت صلاة ${prayer.name}، يرجى الاستعداد والتطهر والتهيؤ للوقوف بين يدي الله',
                preTz,
                NotificationDetails(
                  android: AndroidNotificationDetails(
                    approChannelId,
                    'تذكير اقتراب الصلاة',
                    channelDescription: 'تنبيه مسبق قبل حلول الأذان للاستعداد والتطهر',
                    importance: Importance.max,
                    priority: Priority.high,
                    playSound: approSound != null,
                    sound: approSound,
                    enableVibration: true,
                    category: AndroidNotificationCategory.reminder,
                  ),
                ),
                androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
                uiLocalNotificationDateInterpretation:
                    UILocalNotificationDateInterpretation.absoluteTime,
                payload: 'type=prereminder&prayer=${prayer.name}',
              );
              if (isStale()) return;
            }
          }

          // Schedule Iqamah Alert if enabled (and not Shurouq)
          if (_iqamahReminderEnabled && prayer.name != 'الشروق') {
            final iqamahTime = prayer.time.add(Duration(minutes: _iqamahOffsetMinutes));
            if (iqamahTime.isAfter(now)) {
              if (isStale()) return;
              final iqamahTz = tz.TZDateTime.from(iqamahTime, tz.local);
              final iqamahRawSound = IslamicAudioService.allTracks
                      .where((t) => t.id == _selectedIqamahVoice)
                      .map((t) => t.rawNotificationSound)
                      .firstOrNull ??
                  'iqamah';
              final iqamahDetails = AndroidNotificationDetails(
                'prayer_iqamah_channel',
                'تنبيه إقامة الصلاة',
                channelDescription: 'تنبيه بحلول وقت إقامة الصلاة المكتوبة',
                importance: Importance.max,
                priority: Priority.high,
                playSound: _soundMode != AdhanSoundMode.silent && _soundMode != AdhanSoundMode.vibrateOnly,
                sound: RawResourceAndroidNotificationSound(iqamahRawSound),
                enableVibration: true,
                fullScreenIntent: true,
                category: AndroidNotificationCategory.alarm,
                actions: [
                  const AndroidNotificationAction(
                    'stop_adhan',
                    'إيقاف ⏹️',
                    showsUserInterface: false,
                    cancelNotification: true,
                  ),
                  const AndroidNotificationAction(
                    'open_interactive',
                    'فتح الشاشة 🕌',
                    showsUserInterface: true,
                  ),
                ],
              );

              await _localNotifications.zonedSchedule(
                notificationId++,
                'حان الآن موعد إقامة صلاة ${prayer.name} 🕌',
                'قد قامت الصلاة، أقبل على ربك بسكينة وخشوع (${data.locationName})',
                iqamahTz,
                NotificationDetails(android: iqamahDetails),
                androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
                uiLocalNotificationDateInterpretation:
                    UILocalNotificationDateInterpretation.absoluteTime,
                payload: 'type=iqamah&prayer=${prayer.name}',
              );
              if (isStale()) return;
            }
          }

          // Schedule Post-Prayer Adhkar Reminder (سنن وأذكار ما بعد الصلاة)
          if (_postPrayerAdhkarReminderEnabled && prayer.name != 'الشروق') {
            final adhkarTime = prayer.time.add(Duration(minutes: _iqamahOffsetMinutes + _postPrayerAdhkarMinutes));
            if (adhkarTime.isAfter(now)) {
              if (isStale()) return;
              final adhkarTz = tz.TZDateTime.from(adhkarTime, tz.local);
              final adhkarDetails = AndroidNotificationDetails(
                'prayer_post_adhkar_channel',
                'أذكار ما بعد الصلاة المكتوبة',
                channelDescription: 'تذكير بالاستغفار والتسبيح وقراءة آية الكرسي دبر كل صلاة',
                importance: Importance.high,
                priority: Priority.high,
                playSound: _soundMode != AdhanSoundMode.silent && _soundMode != AdhanSoundMode.vibrateOnly,
                sound: const RawResourceAndroidNotificationSound('reminder_istighfar'),
                enableVibration: true,
              );

              await _localNotifications.zonedSchedule(
                notificationId++,
                'أذكار ما بعد صلاة ${prayer.name} 📿',
                'أستغفر الله، أستغفر الله، أستغفر الله.. اللهم أنت السلام ومنك السلام تباركت يا ذا الجلال والإكرام',
                adhkarTz,
                NotificationDetails(android: adhkarDetails),
                androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
                uiLocalNotificationDateInterpretation:
                    UILocalNotificationDateInterpretation.absoluteTime,
              );
              if (isStale()) return;
            }
          }
        }

        // Schedule Duha Prayer Reminder (صلاة الضحى والأوابين بعد الشروق)
        if (_duhaReminderEnabled && !isStale()) {
          for (final shurouqPrayer in prayers.where((p) => p.name.contains('الشروق'))) {
            final duhaTime = shurouqPrayer.time.add(Duration(minutes: _duhaReminderMinutesAfterSunrise));
            if (duhaTime.isAfter(now)) {
              if (isStale()) return;
              final duhaTz = tz.TZDateTime.from(duhaTime, tz.local);
              final duhaDetails = AndroidNotificationDetails(
                'prayer_duha_channel',
                'تذكير صلاة الضحى',
                channelDescription: 'صلاة الأوابين بعد شروق الشمس بـ ٢٥ دقيقة',
                importance: Importance.high,
                priority: Priority.high,
                playSound: _soundMode != AdhanSoundMode.silent && _soundMode != AdhanSoundMode.vibrateOnly,
                sound: const RawResourceAndroidNotificationSound('reminder_duha'),
                enableVibration: true,
              );

              await _localNotifications.zonedSchedule(
                notificationId++,
                'صلاة الضحى (صلاة الأوابين) ☀️',
                'يصبح على كل سلامى من أحدكم صدقة.. وتجزئ من ذلك ركعتان يركعهما من الضحى',
                duhaTz,
                NotificationDetails(android: duhaDetails),
                androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
                uiLocalNotificationDateInterpretation:
                    UILocalNotificationDateInterpretation.absoluteTime,
              );
              if (isStale()) return;
            }
          }

        }
        // Schedule Qiyam Al-Layl & Tahajjud Reminder (قبل الفجر)
        if (_qiyamReminderEnabled && !isStale()) {
          for (final fajrPrayer in prayers.where((p) => p.name.contains('الفجر'))) {
            final qiyamTime = fajrPrayer.time.subtract(Duration(minutes: _qiyamOffsetMinutes));
            if (qiyamTime.isAfter(now)) {
              if (isStale()) return;
              final qiyamTz = tz.TZDateTime.from(qiyamTime, tz.local);
              final qiyamDetails = AndroidNotificationDetails(
                'prayer_qiyam_channel',
                'تنبيه قيام الليل والتهجد',
                channelDescription: 'تذكير إيماني بالثلث الأخير من الليل لقيام الليل والوتر والدعاء',
                importance: Importance.max,
                priority: Priority.high,
                playSound: _soundMode != AdhanSoundMode.silent && _soundMode != AdhanSoundMode.vibrateOnly,
                sound: const RawResourceAndroidNotificationSound('reminder_qiyam'),
                enableVibration: true,
              );

              await _localNotifications.zonedSchedule(
                notificationId++,
                'قيام الليل والتهجد 🌙',
                'ركعتان في جوف الليل خير من الدنيا وما فيها — ثلث الليل الآخر وقت النزول الإلهي واستجابة الدعاء',
                qiyamTz,
                NotificationDetails(android: qiyamDetails),
                androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
                uiLocalNotificationDateInterpretation:
                    UILocalNotificationDateInterpretation.absoluteTime,
              );
              if (isStale()) return;
            }
          }

        }
        if (isStale()) return;
        // Schedule fixed-clock Friday Sunnahs & Kahf Reminder on dedicated ID (804)
        await scheduleFridayReminder();

        if (isStale()) return;
        // Schedule Morning, Evening, and Sleep Adhkar Reminders on dedicated IDs (801..803)
        await scheduleAdhkarReminders();
        if (!isStale()) {
          _prayerSchedulingError = null;
          notifyListeners();
        }
      } catch (e) {
        if (!isStale()) {
          _prayerSchedulingError = 'تعذر إكمال جدولة تنبيهات الصلاة. بعض التنبيهات قد لا تعمل. راجع إذن الإشعارات والمنبهات الدقيقة ثم أعد المحاولة. نجاح فتح شاشة الأذان لا يثبت عمل التنبيه.';
          notifyListeners();
        }
        debugPrint('Error scheduling prayer notifications: $e');
      }
    });
  }

  /// Schedules recurring daily notifications for Morning, Evening, and Sleep Adhkar
  Future<void> scheduleAdhkarReminders() async {
    if (!_masterEnabled || !_isInitialized) return;
    _ensureTimeZonesInitialized();
    final now = DateTime.now();

    // 1. Morning Adhkar
    try {
      if (_morningAdhkarEnabled) {
        var morningTarget = DateTime(now.year, now.month, now.day, _morningAdhkarHour, _morningAdhkarMinute);
        if (morningTarget.isBefore(now)) {
          morningTarget = morningTarget.add(const Duration(days: 1));
        }
        final morningTz = tz.TZDateTime.from(morningTarget, tz.local);
        const morningDetails = AndroidNotificationDetails(
          'adhkar_morning_channel',
          'أذكار الصباح المباركة',
          channelDescription: 'تنبيه يومي لموعد أذكار الصباح وحصن المسلم',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('reminder_istighfar'),
          enableVibration: true,
        );

        await _localNotifications.zonedSchedule(
          morningAdhkarNotificationId,
          'حان وقت أذكار الصباح ☀️',
          'أصبحنا وأصبح الملك لله والحمد لله.. حصّن يومك بذكر الله وانشراح الصدر',
          morningTz,
          const NotificationDetails(android: morningDetails),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
          payload: 'type=adhkar&category=morning',
        );
      } else {
        await _localNotifications.cancel(morningAdhkarNotificationId);
      }
    } catch (e) {
      debugPrint('Error scheduling morning adhkar: $e');
    }

    // 2. Evening Adhkar
    try {
      if (_eveningAdhkarEnabled) {
        var eveningTarget = DateTime(now.year, now.month, now.day, _eveningAdhkarHour, _eveningAdhkarMinute);
        if (eveningTarget.isBefore(now)) {
          eveningTarget = eveningTarget.add(const Duration(days: 1));
        }
        final eveningTz = tz.TZDateTime.from(eveningTarget, tz.local);
        const eveningDetails = AndroidNotificationDetails(
          'adhkar_evening_channel',
          'أذكار المساء المباركة',
          channelDescription: 'تنبيه يومي لموعد أذكار المساء وحفظ النفس',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('reminder_istighfar'),
          enableVibration: true,
        );

        await _localNotifications.zonedSchedule(
          eveningAdhkarNotificationId,
          'حان وقت أذكار المساء 🌙',
          'أمسينا وأمسى الملك لله والحمد لله.. حفظ ووقاية وبركة لليلتك',
          eveningTz,
          const NotificationDetails(android: eveningDetails),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
          payload: 'type=adhkar&category=evening',
        );
      } else {
        await _localNotifications.cancel(eveningAdhkarNotificationId);
      }
    } catch (e) {
      debugPrint('Error scheduling evening adhkar: $e');
    }

    // 3. Sleep Adhkar
    try {
      if (_sleepAdhkarEnabled) {
        var sleepTarget = DateTime(now.year, now.month, now.day, _sleepAdhkarHour, _sleepAdhkarMinute);
        if (sleepTarget.isBefore(now)) {
          sleepTarget = sleepTarget.add(const Duration(days: 1));
        }
        final sleepTz = tz.TZDateTime.from(sleepTarget, tz.local);
        const sleepDetails = AndroidNotificationDetails(
          'adhkar_sleep_channel',
          'أذكار النوم والسنن النبوية',
          channelDescription: 'تنبيه يومي لموعد أذكار النوم وسنن الاضطجاع',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('reminder_istighfar'),
          enableVibration: true,
        );

        await _localNotifications.zonedSchedule(
          sleepAdhkarNotificationId,
          'حان وقت أذكار النوم 🛏️',
          'باسمك ربي وضعت جنبي وبك أرفعه.. سنة النبي ﷺ وقراءة المعوذات وآية الكرسي قبل النوم',
          sleepTz,
          const NotificationDetails(android: sleepDetails),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
          payload: 'type=adhkar&category=sleep',
        );
      } else {
        await _localNotifications.cancel(sleepAdhkarNotificationId);
      }
    } catch (e) {
      debugPrint('Error scheduling sleep adhkar: $e');
    }
  }

  Future<void> cancelAll() async {
    ++_shortGeneration;
    final shortPending = _shortOperation;
    if (shortPending != null) await shortPending;
    final int generation = ++_derivedScheduleGeneration;
    await _serializeDerivedOp<void>(() async {
      if (generation != _derivedScheduleGeneration) return;
      try {
        await _localNotifications.cancelAll();
      } catch (_) {}
    });
  }
}
