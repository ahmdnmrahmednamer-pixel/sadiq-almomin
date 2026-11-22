import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'islamic_audio_download_race_test.dart'
    show DynamicHttpOverrides, TestHttpClientResponse;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'Islamic audio ordinary download retries a failed cold storage init without opening held sources',
      () async {
    final service = IslamicAudioService.instance;
    final temp = Directory.systemTemp.createTempSync('islamic-init-retry-');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final priorHttp = HttpOverrides.current;
    final priorNativeFlag = service.disableNativePlayerForTesting;
    var failStorage = true;
    var storageCalls = 0;
    var httpCalls = 0;
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), (_) async {
      storageCalls++;
      if (failStorage)
        throw PlatformException(code: 'synthetic_initial_storage_failure');
      return temp.path;
    });
    SharedPreferences.setMockInitialValues({
      'selected_reciter_id': 'unchanged-reciter-sentinel',
      'stories_last_read': 'unchanged-story-sentinel',
    });
    HttpOverrides.global = DynamicHttpOverrides();
    DynamicHttpOverrides.activeHandler = (m, u, r) async {
      httpCalls++;
      return TestHttpClientResponse(Stream.value(Uint8List(2048)),
          contentLength: 2048);
    };
    service.disableNativePlayerForTesting = true;
    try {
      await service.init();
      failStorage = false;
      final downloaded = await service.downloadTrack('adhan_hussary');
      print(
          'storageCalls=$storageCalls httpCalls=$httpCalls downloaded=$downloaded');
      expect(downloaded, isTrue);
      expect(storageCalls, 2);
      expect(httpCalls, 1);
      expect(service.isDownloaded('adhan_hussary'), isTrue);
      final path = service.getLocalAudioPath('adhan_hussary')!;
      expect(File(path).lengthSync(), 2048);
      expect(
          path.endsWith(
              IslamicAudioService.downloadFileNameForTrack('adhan_hussary')),
          isTrue);
      expect(service.totalDownloadedBytes, 2048);
      await service.init();
      expect(storageCalls, 2);
      expect(service.getLocalAudioPath('adhan_hussary'), path);
      expect(await service.downloadTrack('adhan_sudais'), isFalse);
      expect(await service.downloadTrack('adhkar_morning'), isFalse);
      expect(httpCalls, 1);
      expect(service.getLocalAudioPath('adhan_sudais'), isNull);
      expect(service.getLocalAudioPath('adhkar_morning'), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(
          prefs.getString('selected_reciter_id'), 'unchanged-reciter-sentinel');
      expect(prefs.getString('stories_last_read'), 'unchanged-story-sentinel');
      expect(await service.deleteDownloadedTrack('adhan_hussary'), isTrue);
      expect(File(path).existsSync(), isFalse);
    } finally {
      service.disableNativePlayerForTesting = priorNativeFlag;
      await service.deleteAllDownloadedTracks();
      HttpOverrides.global = priorHttp;
      DynamicHttpOverrides.activeHandler = null;
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'), null);
      temp.deleteSync(recursive: true);
    }
  });
}
