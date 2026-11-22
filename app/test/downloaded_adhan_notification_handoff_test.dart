import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Existing shared_preferences test interface, used only for fault injection.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:almomin/core/notifications/prayer_notification_service.dart';
import 'package:almomin/core/services/prayer_service.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/core/services/downloaded_adhan_sound_store.dart';
import 'package:almomin/core/services/downloaded_adhan_assignments.dart';
import 'adhan_choice_write_confirmation_test.dart' as choice;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = PrayerNotificationService.instance;
  final track = IslamicAudioService.allTracks.firstWhere(
      (track) => DownloadedAdhanSoundStore.isPinnedAdhanTrack(track));
  final id = track.id;
  final sound = PreparedDownloadedAdhan(
    uri: Uri(
        scheme: 'content',
        host: DownloadedAdhanSoundStore.authority,
        pathSegments: [
          'v1',
          track.remoteGitBlobSha1!,
          track.fileSizeBytes.toString()
        ]).toString(),
    blobSha1: track.remoteGitBlobSha1!,
    sizeBytes: track.fileSizeBytes!,
  );
  final calls = <MethodCall>[];
  var preparations = 0;
  var rejectSchedule = false;
  PrayerData futureData({String prayer = 'الظهر'}) => PrayerData(
      latitude: 30,
      longitude: 31,
      locationName: 'fixture',
      prayers: [
        PrayerInfo(
            name: prayer,
            time: DateTime.now().add(const Duration(hours: 1)),
            formattedTime: '')
      ],
      qiblaDegrees: 135,
      lastUpdated: DateTime.now());
  Future<void> load(
      {bool pin = false,
      AdhanSoundMode mode = AdhanSoundMode.fullAdhan,
      bool enabled = true}) async {
    SharedPreferences.setMockInitialValues({
      'notif_master_enabled': true,
      'notif_sound_mode': mode.name,
      'notif_prayer_الظهر': enabled,
      if (pin) 'notif_prayer_voice_الظهر': id,
      'notif_morning_adhkar_enabled': false,
      'notif_evening_adhkar_enabled': false,
      'notif_sleep_adhkar_enabled': false,
    });
    await service.init(forceReload: true);
    calls.clear();
    preparations = 0;
  }

  setUp(() async {
    rejectSchedule = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            (call) async {
      calls.add(call);
      if (call.method == 'zonedSchedule' && rejectSchedule) {
        throw PlatformException(code: 'fixture-schedule-refused');
      }
      if (call.method == 'initialize' ||
          call.method == 'areNotificationsEnabled' ||
          call.method == 'canScheduleExactNotifications') {
        return true;
      }
      if (call.method == 'pendingNotificationRequests' ||
          call.method == 'getActiveNotifications') {
        return [];
      }
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_timezone'),
            (_) async => 'Africa/Cairo');
    service.downloadedAdhanPreparerForTesting = (_) async {
      preparations++;
      return sound;
    };
    await load();
  });
  tearDown(() {
    service.downloadedAdhanPreparerForTesting = null;
  });
  test(
      'failed native preparation precedes every preference write and visible choice',
      () async {
    service.downloadedAdhanPreparerForTesting =
        (_) async => throw StateError('fixture unavailable');
    final prefs = await SharedPreferences.getInstance();
    final before = {for (final key in prefs.getKeys()) key: prefs.get(key)};
    await expectLater(service.setPrayerVoice('الظهر', id), throwsStateError);
    await prefs.reload();
    expect({for (final key in prefs.getKeys()) key: prefs.get(key)}, before);
    expect(service.getPrayerVoice('الظهر'), 'adhan_makkah');
    expect(
        calls.where((call) =>
            call.method == 'cancel' || call.method == 'zonedSchedule'),
        isEmpty);
    expect(DownloadedAdhanAssignments.isPending(id), isFalse);
  });
  test('descriptor identity mismatch cannot persist a downloaded choice',
      () async {
    service.downloadedAdhanPreparerForTesting = (_) async =>
        PreparedDownloadedAdhan(
            uri: 'content://wrong/identity',
            blobSha1: sound.blobSha1,
            sizeBytes: sound.sizeBytes);
    await expectLater(service.setPrayerVoice('الظهر', id), throwsStateError);
    expect(service.getPrayerVoice('الظهر'), 'adhan_makkah');
  });
  test('setter prepares and retains new file before confirmed preference write',
      () async {
    await service.setPrayerVoice('الظهر', id);
    expect(preparations, 1);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString('notif_prayer_voice_الظهر'), id);
    expect(prefs.getStringList(DownloadedAdhanAssignments.protectionKey),
        contains(id));
  });
  test('queued assignment protects its file before its queue slot starts',
      () async {
    final store = choice.RefusingAdhanStore();
    SharedPreferencesStorePlatform.instance = store;
    await (await SharedPreferences.getInstance()).reload();
    await service.init(forceReload: true);
    final hold = Completer<void>();
    store.hold = hold;
    final first = service.setPrayerVoice('الظهر', 'adhan_hussary');
    while (store.writes == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    final second = service.setPrayerVoice('الظهر', id);
    expect(DownloadedAdhanAssignments.isPending(id), isTrue);
    hold.complete();
    await Future.wait([first, second]);
    expect(DownloadedAdhanAssignments.isPending(id), isFalse);
    expect(service.getPrayerVoice('الظهر'), id);
  });
  test(
      'preflight failure preserves old native plan without Makkah substitution',
      () async {
    await load(pin: true);
    service.downloadedAdhanPreparerForTesting =
        (_) async => throw StateError('fixture unavailable');
    expect(await service.schedulePrayerNotifications(futureData()),
        PrayerScheduleOutcome.failed);
    expect(
        calls.where((call) =>
            call.method == 'cancel' || call.method == 'zonedSchedule'),
        isEmpty);
    expect(service.prayerSchedulingError, contains('لم نحذف الجدولة السابقة'));
  });
  test(
      'normal prayer uses content URI and new digest-specific channel, without changing time or ID',
      () async {
    await load(pin: true);
    final data = futureData();
    expect(await service.schedulePrayerNotifications(data),
        PrayerScheduleOutcome.applied);
    expect(preparations, 1);
    final args = calls
        .where((call) => call.method == 'zonedSchedule')
        .map((call) => call.arguments as Map)
        .singleWhere((args) =>
            (args['payload'] as String?)?.startsWith('type=adhan') ?? false);
    final android = args['platformSpecifics'] as Map;
    expect(android['sound'], sound.uri);
    expect(android['soundSource'], 1);
    expect(android['channelId'], sound.channelId);
    expect(args['id'], inInclusiveRange(100, 399));
    expect(DateTime.parse(args['scheduledDateTime'] as String).hour,
        data.prayers.single.time.hour);
    expect(service.prayerVoiceConfirmed('الظهر', id), isTrue);
  });
  for (final mode in AdhanSoundMode.values
      .where((mode) => mode != AdhanSoundMode.fullAdhan)) {
    test('$mode does not require unused downloaded sound to exist', () async {
      await load(pin: true, mode: mode);
      service.downloadedAdhanPreparerForTesting =
          (_) async => throw StateError('must not be used');
      expect(await service.schedulePrayerNotifications(futureData()),
          PrayerScheduleOutcome.applied);
      final args = calls
          .where((call) => call.method == 'zonedSchedule')
          .map((call) => call.arguments as Map)
          .singleWhere((args) =>
              (args['payload'] as String?)?.startsWith('type=adhan') ?? false);
      expect((args['platformSpecifics'] as Map)['sound'], isNot(sound.uri));
    });
  }
  test('disabled prayer does not preflight unused downloaded voice', () async {
    await load(pin: true, enabled: false);
    service.downloadedAdhanPreparerForTesting =
        (_) async => throw StateError('must not be used');
    expect(await service.schedulePrayerNotifications(futureData()),
        PrayerScheduleOutcome.applied);
    expect(preparations, 0);
  });
  test('superseded preflight never cancels the prior native plan', () async {
    await load(pin: true);
    final entered = Completer<void>();
    final release = Completer<void>();
    service.downloadedAdhanPreparerForTesting = (_) async {
      entered.complete();
      await release.future;
      return sound;
    };
    final stale = service.schedulePrayerNotifications(futureData());
    await entered.future;
    final replacement =
        service.schedulePrayerNotifications(futureData(prayer: 'الفجر'));
    release.complete();
    expect(await stale, PrayerScheduleOutcome.superseded);
    expect(await replacement, PrayerScheduleOutcome.applied);
    expect(
        calls
            .where((call) => call.method == 'zonedSchedule')
            .map((call) => call.arguments as Map)
            .where((args) =>
                (args['payload'] as String?)
                    ?.startsWith('type=adhan&prayer=الظهر') ??
                false),
        isEmpty);
  });
  test(
      'ID999 device test uses prepared URI, and preflight failure does not call show',
      () async {
    await service.sendTestNotification(customVoice: id);
    final args =
        calls.singleWhere((call) => call.method == 'show').arguments as Map;
    expect(args['id'], 999);
    expect((args['platformSpecifics'] as Map)['sound'], sound.uri);
    calls.clear();
    service.downloadedAdhanPreparerForTesting =
        (_) async => throw StateError('fixture unavailable');
    await expectLater(
        service.sendTestNotification(customVoice: id), throwsStateError);
    expect(calls.where((call) => call.method == 'show'), isEmpty);
  });
  test('failed durable protection prevents voice preference writes', () async {
    final store = choice.RefusingAdhanStore();
    SharedPreferencesStorePlatform.instance = store;
    await (await SharedPreferences.getInstance()).reload();
    await service.init(forceReload: true);
    store.rejectAt = 1;
    await expectLater(service.setPrayerVoice('الظهر', id), throwsStateError);
    expect(store.writes, 1);
    expect(service.getPrayerVoice('الظهر'), 'adhan_makkah');
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString('notif_prayer_voice_الظهر'), 'adhan_makkah');
  });
  test('sound-mode change while preflighting supersedes the old sound payload',
      () async {
    await load(pin: true);
    final entered = Completer<void>();
    final release = Completer<void>();
    service.downloadedAdhanPreparerForTesting = (_) async {
      entered.complete();
      await release.future;
      return sound;
    };
    final plan = service.schedulePrayerNotifications(futureData());
    await entered.future;
    await service.setSoundMode(AdhanSoundMode.silent);
    release.complete();
    expect(await plan, PrayerScheduleOutcome.superseded);
    expect(calls.where((call) => call.method == 'zonedSchedule'), isEmpty);
    // Changing a mode with no known location intentionally queues a separate
    // UNKNOWN-location cancellation in existing code. Drain it before teardown.
    await service.cancelLocationDerivedNotifications();
  });
  test(
      'duplicate selected downloads are prepared once for the native prayer plan',
      () async {
    await service.setAllPrayersVoice(id);
    preparations = 0;
    calls.clear();
    final now = DateTime.now();
    final data = PrayerData(
        latitude: 30,
        longitude: 31,
        locationName: 'fixture',
        prayers: [
          for (final (index, name) in ['الظهر', 'العصر'].indexed)
            PrayerInfo(
                name: name,
                time: now.add(Duration(hours: index + 1)),
                formattedTime: '')
        ],
        qiblaDegrees: 135,
        lastUpdated: now);
    expect(await service.schedulePrayerNotifications(data),
        PrayerScheduleOutcome.applied);
    expect(preparations, 1);
    final alarms = calls
        .where((call) => call.method == 'zonedSchedule')
        .map((call) => call.arguments as Map)
        .where((args) =>
            (args['payload'] as String?)?.startsWith('type=adhan') ?? false)
        .toList();
    expect(alarms.length, 2);
    expect(
        alarms.map((args) => (args['platformSpecifics'] as Map)['channelId']),
        everyElement(sound.channelId));
  });
  test(
      'failed replacement retains old file possibility until a complete rebuild',
      () async {
    await load(pin: true);
    expect(await service.schedulePrayerNotifications(futureData()),
        PrayerScheduleOutcome.applied);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notif_prayer_voice_الظهر', 'adhan_makkah');
    await service.init(forceReload: true);
    calls.clear();
    rejectSchedule = true;
    expect(await service.schedulePrayerNotifications(futureData()),
        PrayerScheduleOutcome.failed);
    await prefs.reload();
    expect(prefs.getStringList(DownloadedAdhanAssignments.protectionKey),
        contains(id));
    rejectSchedule = false;
    expect(await service.schedulePrayerNotifications(futureData()),
        PrayerScheduleOutcome.applied);
    await prefs.reload();
    expect(
        prefs.getStringList(DownloadedAdhanAssignments.protectionKey), isEmpty);
  });
}
