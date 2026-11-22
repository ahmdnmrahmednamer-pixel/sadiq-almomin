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
  for (final outcome in ['success', 'short', 'cancel']) {
    test('forced story scan protects exact active temp through $outcome',
        () async {
      final service = StoriesService.instance;
      final temp = Directory.systemTemp.createTempSync('stories-forced-scan-');
      final dir = Directory('${temp.path}/prophet_stories')..createSync();
      final old = File('${dir.path}/adam.mp3')
        ..writeAsBytesSync(List.filled(2001, 7));
      File('${dir.path}/nuh.mp3').writeAsBytesSync(List.filled(3001, 8));
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => temp.path);
      final stream = StreamController<List<int>>();
      final started = Completer<void>();
      final priorHttp = HttpOverrides.current;
      Future<bool>? pending;
      HttpOverrides.global = DynamicHttpOverrides();
      SharedPreferences.setMockInitialValues({});
      await SettingsService.instance.init(forceReload: true);
      try {
        await service.init(forceReload: true);
        DynamicHttpOverrides.activeHandler = (m, u, r) async {
          started.complete();
          return TestHttpClientResponse(stream.stream,
              contentLength: outcome == 'short' ? 1000 : 2048);
        };
        pending = service.downloadStory('adam');
        await started.future;
        stream.add(Uint8List(outcome == 'short' ? 1000 : 1024));
        List<File> temps() => dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.tmp'))
            .toList();
        for (var tick = 0; tick < 100 && temps().isEmpty; tick++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(temps(), hasLength(1));
        final activePath = temps().single.path;
        final stale = File('${dir.path}/adam.mp3.999999.tmp')
          ..writeAsStringSync('stale');
        final partial = File('${dir.path}/orphan.part')
          ..writeAsStringSync('stale');
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('stories_favorites', ['nuh']);
        await prefs.setString('stories_last_read', 'adam');
        await service.init(forceReload: true);
        final activeSurvived = File(activePath).existsSync();
        final orphansRemoved = !stale.existsSync() && !partial.existsSync();
        final wasDownloading = service.isDownloading('adam');
        if (outcome == 'cancel') service.cancelDownload('adam');
        if (outcome != 'short') stream.add(Uint8List(1024));
        await stream.close();
        final completed = await pending;
        print(
            'outcome=$outcome activeSurvived=$activeSurvived completed=$completed');
        expect(activeSurvived, isTrue);
        expect(orphansRemoved, isTrue);
        expect(wasDownloading, isTrue);
        expect(completed, outcome == 'success');
        expect(service.favoriteIds, {'nuh'});
        expect(service.lastReadStoryId, 'adam');
        expect(service.isDownloading('adam'), isFalse);
        expect(service.isDownloaded('adam'), isTrue);
        expect(service.isDownloaded('nuh'), isTrue);
        expect(old.lengthSync(), outcome == 'success' ? 2048 : 2001);
        if (outcome != 'success') {
          expect(old.readAsBytesSync(), List.filled(2001, 7));
        }
        expect(File(service.getLocalAudioPath('nuh')!).lengthSync(), 3001);
        expect(File(activePath).existsSync(), isFalse);
        // Settled attempts must not permanently exempt this path from cleanup.
        File(activePath).writeAsStringSync('stale after settlement');
        await service.init(forceReload: true);
        expect(File(activePath).existsSync(), isFalse);
      } finally {
        if (!stream.isClosed) await stream.close();
        if (pending != null) await pending;
        await service.deleteAllDownloadedStories();
        HttpOverrides.global = priorHttp;
        DynamicHttpOverrides.activeHandler = null;
        messenger.setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
        temp.deleteSync(recursive: true);
      }
    });
  }
}
