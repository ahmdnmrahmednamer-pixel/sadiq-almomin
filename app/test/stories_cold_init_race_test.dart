import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/stories_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'stories_download_race_test.dart'
    show DynamicHttpOverrides, TestHttpClientResponse;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'ordinary cold story init shares one scan, retries failure and preserves explicit forced reload',
      () async {
    final service = StoriesService.instance;
    final temp = Directory.systemTemp.createTempSync('stories-cold-init-');
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
      download = service.downloadStory('adam');
      await responseStarted.future;
      stream.add(Uint8List(1024));
      final dir = Directory('${temp.path}/prophet_stories');
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
      expect(service.isDownloaded('adam'), isTrue);
      expect(File(service.getLocalAudioPath('adam')!).lengthSync(), 2048);
      final path = service.getLocalAudioPath('adam');
      await Future.wait([service.init(), service.init()]);
      expect(pathCalls, 1);
      expect(service.getLocalAudioPath('adam'), path);
      expect(temporaryFiles(), isEmpty);
      // Explicit restore/reload must not be swallowed by ordinary singleflight.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('stories_favorites', ['adam']);
      await prefs.setString('stories_last_read', 'nuh');
      await service.init();
      expect(pathCalls, 1);
      expect(service.favoriteIds, isEmpty);
      expect(service.lastReadStoryId, isNull);
      await service.init(forceReload: true);
      expect(pathCalls, 2);
      expect(service.favoriteIds, {'adam'});
      expect(service.lastReadStoryId, 'nuh');
      expect(service.getLocalAudioPath('adam'), path);
      expect(File(path!).lengthSync(), 2048);
    } finally {
      if (!delayedPath.isCompleted) delayedPath.complete(temp.path);
      if (!stream.isClosed) await stream.close();
      if (download != null) await download;
      await service.deleteAllDownloadedStories();
      HttpOverrides.global = priorHttp;
      DynamicHttpOverrides.activeHandler = null;
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'), null);
      temp.deleteSync(recursive: true);
    }
  });
}
