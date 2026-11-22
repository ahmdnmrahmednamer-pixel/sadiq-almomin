import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/stories_service.dart';
import 'stories_download_race_test.dart'
    show DynamicHttpOverrides, TestHttpClientResponse;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'failed cold story storage init can retry through ordinary download without resetting preferences',
      () async {
    final service = StoriesService.instance;
    final temp = Directory.systemTemp.createTempSync('story-init-retry-');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final priorHttp = HttpOverrides.current;
    var failStorage = true;
    var storageCalls = 0;
    var httpCalls = 0;
    final notifications = <bool>[];
    void listener() => notifications.add(service.isInitialized);
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), (_) async {
      storageCalls++;
      if (failStorage)
        throw PlatformException(code: 'synthetic_initial_storage_failure');
      return temp.path;
    });
    SharedPreferences.setMockInitialValues({
      'stories_favorites': ['adam'],
      'stories_last_read': 'nuh',
    });
    HttpOverrides.global = DynamicHttpOverrides();
    DynamicHttpOverrides.activeHandler = (m, u, r) async {
      httpCalls++;
      return TestHttpClientResponse(Stream.value(Uint8List(2048)),
          contentLength: 2048);
    };
    service.addListener(listener);
    try {
      await service.init();
      final initializedAfterFailure = service.isInitialized;
      failStorage = false;
      final downloaded = await service.downloadStory('adam');
      print(
          'initializedAfterFailure=$initializedAfterFailure storageCalls=$storageCalls httpCalls=$httpCalls downloaded=$downloaded');
      expect(initializedAfterFailure, isFalse);
      expect(downloaded, isTrue);
      expect(service.isInitialized, isTrue);
      expect(storageCalls, 2);
      expect(httpCalls, 1);
      expect(notifications.first, isFalse);
      expect(notifications, contains(true));
      expect(service.isDownloaded('adam'), isTrue);
      final path = service.getLocalAudioPath('adam')!;
      expect(File(path).lengthSync(), 2048);
      expect(service.totalDownloadedStoriesBytes, 2048);
      expect(service.favoriteIds, {'adam'});
      expect(service.lastReadStoryId, 'nuh');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('stories_favorites'), ['adam']);
      expect(prefs.getString('stories_last_read'), 'nuh');
      await service.init();
      expect(storageCalls, 2);
      expect(service.getLocalAudioPath('adam'), path);
      expect(await service.deleteDownloadedStory('adam'), isTrue);
      expect(File(path).existsSync(), isFalse);
    } finally {
      service.removeListener(listener);
      await service.deleteAllDownloadedStories();
      HttpOverrides.global = priorHttp;
      DynamicHttpOverrides.activeHandler = null;
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'), null);
      temp.deleteSync(recursive: true);
    }
  });
}
