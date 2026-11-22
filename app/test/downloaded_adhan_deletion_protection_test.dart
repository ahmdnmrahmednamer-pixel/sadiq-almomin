import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/core/services/downloaded_adhan_assignments.dart';
import 'islamic_audio_failed_focus_fallback_test.dart' show FallbackProbePlayer;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final bytes = List.generate(4096, (i) => i % 251);
  final hash = sha1.convert(
      [...utf8.encode('blob ${bytes.length}\u0000'), ...bytes]).toString();
  final id = 'kiwifu_adhan_$hash';
  final track = IslamicAudioTrack(
      id: id,
      title: 'fixture',
      subtitle: '',
      type: IslamicAudioType.adhan,
      durationFormatted: '',
      remoteGitBlobSha1: hash,
      fileSizeBytes: bytes.length,
      remoteUrl: 'https://fixture.invalid/audio.mp3');
  late Directory dir;
  late File pinned;
  late File other;
  late IslamicAudioService service;
  var failNative = false;
  Completer<void>? readGate;
  Completer<void>? readEntered;
  setUp(() async {
    failNative = false;
    readGate = null;
    readEntered = null;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            (call) async {
      if (readGate != null) {
        readEntered?.complete();
        await readGate!.future;
        readGate = null;
      }
      if (failNative) throw PlatformException(code: 'fixture-unavailable');
      return [];
    });
    dir = Directory.systemTemp.createTempSync('native-adhan-deletion-');
    pinned = File('${dir.path}/$id.mp3')..writeAsBytesSync(bytes);
    other = File('${dir.path}/unassigned.mp3')..writeAsBytesSync(bytes);
    service = IslamicAudioService.forTesting(FallbackProbePlayer(), catalog: [
      track,
      const IslamicAudioTrack(
          id: 'unassigned',
          title: '',
          subtitle: '',
          type: IslamicAudioType.adhan,
          durationFormatted: '')
    ]);
    service.disableNativePlayerForTesting = true;
    await service.scanDownloadsForTesting(dir);
    expect(service.isDownloaded(id), isTrue);
  });
  tearDown(() {
    service.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  for (final key in [
    'notif_selected_adhan',
    'notif_selected_fajr_adhan',
    'notif_prayer_voice_الفجر',
    'notif_prayer_voice_الظهر',
    'notif_prayer_voice_العصر',
    'notif_prayer_voice_المغرب',
    'notif_prayer_voice_العشاء'
  ]) {
    test('saved voice prevents deletion with bytes intact: $key', () async {
      await (await SharedPreferences.getInstance()).setString(key, id);
      expect(await service.deleteDownloadedTrack(id), isFalse);
      expect(pinned.existsSync(), isTrue);
      expect(service.totalDownloadedBytes, 8192);
      expect(service.lastDeletionError, contains('احتفظنا'));
    });
  }
  test('pending assignment blocks both single and bulk delete, then releases',
      () async {
    final release = Completer<void>();
    final assignment =
        DownloadedAdhanAssignments.protect([id], () => release.future);
    expect(await service.deleteDownloadedTrack(id), isFalse);
    expect(await service.deleteAllDownloadedTracks(), isFalse);
    expect(pinned.existsSync(), isTrue);
    expect(other.existsSync(), isFalse);
    expect(service.totalDownloadedBytes, 4096);
    release.complete();
    await assignment;
    expect(await service.deleteDownloadedTrack(id), isTrue);
    expect(service.totalDownloadedBytes, 0);
  });
  test(
      'bulk cleanup deletes other files while retaining assigned file and its true size',
      () async {
    await (await SharedPreferences.getInstance())
        .setString('notif_prayer_voice_الفجر', id);
    expect(await service.deleteAllDownloadedTracks(), isFalse);
    expect(pinned.existsSync(), isTrue);
    expect(other.existsSync(), isFalse);
    expect(service.totalDownloadedBytes, 4096);
    expect(service.lastDeletionError, contains('اختر تسجيلاً آخر'));
  });
  test(
      'malformed protection state retains pinned downloads but does not block unrelated cleanup',
      () async {
    await (await SharedPreferences.getInstance())
        .setInt(DownloadedAdhanAssignments.protectionKey, 42);
    expect(await service.deleteDownloadedTrack(id), isFalse);
    expect(await service.deleteAllDownloadedTracks(), isFalse);
    expect(pinned.existsSync(), isTrue);
    expect(other.existsSync(), isFalse);
    expect(service.totalDownloadedBytes, 4096);
    expect(service.lastDeletionError, contains('تعذر التأكد'));
  });
  test(
      'unverified native state retains possibly scheduled file after saved selection changes',
      () async {
    await DownloadedAdhanAssignments.retain([id]);
    failNative = true;
    expect(await service.deleteDownloadedTrack(id), isFalse);
    expect(pinned.existsSync(), isTrue);
    failNative = false;
    expect(await service.deleteDownloadedTrack(id), isTrue);
  });
  test(
      'new pending assignment during asynchronous native check is rechecked immediately before unlink',
      () async {
    await DownloadedAdhanAssignments.retain([id]);
    readGate = Completer<void>();
    readEntered = Completer<void>();
    final deletion = service.deleteDownloadedTrack(id);
    await readEntered!.future;
    final release = Completer<void>();
    final assignment =
        DownloadedAdhanAssignments.protect([id], () => release.future);
    readGate!.complete();
    expect(await deletion, isFalse);
    expect(pinned.existsSync(), isTrue);
    release.complete();
    await assignment;
    expect(await service.deleteDownloadedTrack(id), isTrue);
  });
}
