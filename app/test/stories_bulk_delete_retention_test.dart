import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/stories_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('bulk deletion retains failed story paths and sizes until retry',
      () async {
    final temp = Directory.systemTemp.createTempSync('stories-bulk-retention-');
    final dir = Directory('${temp.path}/prophet_stories')..createSync();
    final retained = File('${dir.path}/adam.mp3')
      ..writeAsBytesSync(List.filled(4096, 1));
    final missing = File('${dir.path}/nuh.mp3')
      ..writeAsBytesSync(List.filled(2048, 1));
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => temp.path);
    SharedPreferences.setMockInitialValues({
      'stories_favorites': ['adam'],
      'stories_last_read': 'nuh',
    });
    final service = StoriesService.instance;
    final snapshots = <int>[];
    void listener() => snapshots.add(service.totalDownloadedStoriesBytes);
    try {
      await service.init(forceReload: true);
      final stories = service.getDownloadedStories();
      final adam = stories.firstWhere((s) => s.id == 'adam');
      expect(stories, hasLength(2));
      expect(service.totalDownloadedStoriesBytes, 6144);
      missing.deleteSync();
      expect(Process.runSync('chmod', ['0555', dir.path]).exitCode, 0);
      service.addListener(listener);
      await expectBulkResult(service.deleteAllDownloadedStories(), false);
      expect(retained.existsSync(), isTrue);
      expect(service.totalDownloadedStoriesBytes, 4096,
          reason: 'Failed file deletion must retain the story storage count');
      expect(service.getDownloadedStories(), [same(adam)]);
      expect(service.getLocalAudioPath('adam'), retained.path);
      expect(service.isDownloaded('nuh'), isFalse);
      expect(snapshots, [4096]);
      expect(Process.runSync('chmod', ['0755', dir.path]).exitCode, 0);
      await expectBulkResult(service.deleteAllDownloadedStories(), true);
      expect(retained.existsSync(), isFalse);
      expect(service.getDownloadedStories(), isEmpty);
      expect(service.totalDownloadedStoriesBytes, 0);
      expect(snapshots, [4096, 0]);
      await expectBulkResult(service.deleteAllDownloadedStories(), true);
      expect(service.totalDownloadedStoriesBytes, 0);
      expect(service.favoriteIds, {'adam'});
      expect(service.lastReadStoryId, 'nuh');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('stories_favorites'), ['adam']);
      expect(prefs.getString('stories_last_read'), 'nuh');
    } finally {
      service.removeListener(listener);
      Process.runSync('chmod', ['0755', dir.path]);
      await service.deleteAllDownloadedStories();
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'), null);
      temp.deleteSync(recursive: true);
    }
  });
}

Future<void> expectBulkResult(Future<bool> result, bool expected) async {
  expect(await result, expected);
}
