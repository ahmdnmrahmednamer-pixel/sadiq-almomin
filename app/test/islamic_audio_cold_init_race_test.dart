import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'islamic_audio_download_race_test.dart'
    show DynamicHttpOverrides, TestHttpClientResponse;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'overlapping Islamic audio cold init keeps active temp and initialized calls still contain held playback',
      () async {
    final service = IslamicAudioService.instance;
    final temp = Directory.systemTemp.createTempSync('islamic-cold-init-');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final delayedPath = Completer<String>();
    final responseStarted = Completer<void>();
    final stream = StreamController<List<int>>();
    final priorHttp = HttpOverrides.current;
    final priorNativeFlag = service.disableNativePlayerForTesting;
    service.disableNativePlayerForTesting = true;
    var failPath = true;
    var pathCalls = 0;
    Future<bool>? download;
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), (_) async {
      if (failPath)
        throw PlatformException(code: 'synthetic_initial_storage_failure');
      pathCalls++;
      if (pathCalls > 1) return delayedPath.future;
      return temp.path;
    });
    HttpOverrides.global = DynamicHttpOverrides();
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init();
    try {
      await service.init();
      failPath = false;
      final firstInit = service.init();
      final secondInit = service.init();
      await firstInit;
      DynamicHttpOverrides.activeHandler = (m, u, r) async {
        responseStarted.complete();
        return TestHttpClientResponse(stream.stream, contentLength: 2048);
      };
      download = service.downloadTrack('adhan_hussary');
      await responseStarted.future;
      stream.add(Uint8List(1024));
      final dir = Directory('${temp.path}/adhkar_audio');
      List<File> temporaryFiles() => dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.tmp'))
          .toList();
      for (var tries = 0; tries < 100 && temporaryFiles().isEmpty; tries++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(temporaryFiles(), hasLength(1));
      final activeTempPath = temporaryFiles().single.path;
      delayedPath.complete(temp.path);
      await secondInit;
      final tempSurvived = File(activeTempPath).existsSync();
      stream.add(Uint8List(1024));
      await stream.close();
      final completed = await download;
      print(
          'storagePathCalls=$pathCalls activeTempSurvived=$tempSurvived downloadCompleted=$completed');
      expect(tempSurvived, isTrue,
          reason:
              'A late duplicate startup scan must not delete the active attempt temp file');
      expect(completed, isTrue);
      expect(pathCalls, 1);
      expect(service.isDownloaded('adhan_hussary'), isTrue);
      expect(
          File(service.getLocalAudioPath('adhan_hussary')!).lengthSync(), 2048);
      final path = service.getLocalAudioPath('adhan_hussary');
      await Future.wait([service.init(), service.init()]);
      expect(pathCalls, 1);
      expect(service.getLocalAudioPath('adhan_hussary'), path);
      expect(temporaryFiles(), isEmpty);
      final held = IslamicAudioService.allTracks
          .firstWhere((t) => t.id == 'adhkar_morning');
      final allowed = IslamicAudioService.allTracks
          .firstWhere((t) => t.id == 'adhan_hussary');
      service.seedPlaybackSnapshotForTesting(
          queue: [held, allowed], currentIndex: 0, playing: true);
      await service.init();
      expect(pathCalls, 1);
      expect(service.currentTrack, isNull);
      expect(service.isPlaying, isFalse);
      expect(service.queue.map((t) => t.id), ['adhan_hussary']);
      expect(service.heldLegacyTrack?.id, 'adhkar_morning');
      expect(service.legacyStopPending, isFalse);
      expect(service.legacyStopFailed, isFalse);
    } finally {
      if (!delayedPath.isCompleted) delayedPath.complete(temp.path);
      if (!stream.isClosed) await stream.close();
      if (download != null) await download;
      await service.deleteAllDownloadedTracks();
      service.disableNativePlayerForTesting = priorNativeFlag;
      HttpOverrides.global = priorHttp;
      DynamicHttpOverrides.activeHandler = null;
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'), null);
      temp.deleteSync(recursive: true);
    }
  });
}
