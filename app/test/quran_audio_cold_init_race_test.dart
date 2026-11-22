import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/audio_download_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'quran_audio_download_race_test.dart'
    show DynamicHttpOverrides, TestHttpClientResponse;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'overlapping cold init cannot scan away an active download and failed init remains retryable',
      () async {
    final service = AudioDownloadService.instance;
    final temp = Directory.systemTemp.createTempSync('quran-cold-init-');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final delayedPath = Completer<String>();
    final responseStarted = Completer<void>();
    final stream = StreamController<List<int>>();
    final priorHttp = HttpOverrides.current;
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
      expect(service.isInitialized, isFalse);
      failPath = false;
      final firstInit = service.init();
      final secondInit = service.init();
      await firstInit;
      expect(service.isInitialized, isTrue);
      DynamicHttpOverrides.activeHandler = (m, u, r) async {
        responseStarted.complete();
        return TestHttpClientResponse(stream.stream, contentLength: 2048);
      };
      download = service.downloadSurah(
          reciterId: 'alafasy', surahId: 1, surahName: 'Synthetic');
      await responseStarted.future;
      stream.add(Uint8List(1024));
      final dir = Directory('${temp.path}/quran_audio');
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
      expect(service.isDownloaded('alafasy', 1), isTrue);
      expect(File(service.getLocalAudioPath('alafasy', 1)!).lengthSync(), 2048);
      final metadata = service.downloadedSurahs['alafasy_1'];
      await Future.wait([service.init(), service.init()]);
      expect(pathCalls, 1);
      expect(
          identical(service.downloadedSurahs['alafasy_1'], metadata), isTrue);
      expect(temporaryFiles(), isEmpty);
    } finally {
      if (!delayedPath.isCompleted) delayedPath.complete(temp.path);
      if (!stream.isClosed) await stream.close();
      if (download != null) await download;
      await service.deleteAllDownloads();
      HttpOverrides.global = priorHttp;
      DynamicHttpOverrides.activeHandler = null;
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'), null);
      temp.deleteSync(recursive: true);
    }
  });
}
