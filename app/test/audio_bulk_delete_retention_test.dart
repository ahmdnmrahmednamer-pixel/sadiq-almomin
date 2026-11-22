import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/audio_download_service.dart';
import 'package:almomin/core/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'bulk delete retains failed Quran files and metadata, then retry removes them',
      () async {
    final temp = Directory.systemTemp.createTempSync('bulk-delete-retention-');
    final audio = Directory('${temp.path}/quran_audio')..createSync();
    final retained = File('${audio.path}/minshawi_murattal_001.mp3')
      ..writeAsBytesSync(List.filled(4096, 1));
    final missing = File('${audio.path}/minshawi_murattal_002.mp3')
      ..writeAsBytesSync(List.filled(2048, 1));
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => temp.path);
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init(forceReload: true);
    final service = AudioDownloadService.instance;
    try {
      await service.init();
      expect(service.getDownloadedSurahsList(), hasLength(2));
      final info = service.downloadedSurahs['minshawi_murattal_1'];
      missing.deleteSync();
      expect(Process.runSync('chmod', ['0555', audio.path]).exitCode, 0);
      final snapshots = <List<int>>[];
      void listener() => snapshots.add(
          service.getDownloadedSurahsList().map((x) => x.surahId).toList());
      service.addListener(listener);
      try {
        await service.deleteAllDownloads();
        expect(retained.existsSync(), isTrue);
        expect(service.isDownloaded('minshawi_murattal', 1), isTrue,
            reason: 'Failed deletion must remain visible as downloaded');
        expect(service.downloadedSurahs['minshawi_murattal_1'], same(info));
        expect(service.getDownloadedSurahsList().map((x) => x.surahId), [1]);
        expect(service.totalStorageUsedBytes, 4096);
        expect(snapshots, [
          [1]
        ]);
        expect(service.isDownloaded('minshawi_murattal', 2), isFalse);
        expect(Process.runSync('chmod', ['0755', audio.path]).exitCode, 0);
        await service.deleteAllDownloads();
        expect(retained.existsSync(), isFalse);
        expect(service.getDownloadedSurahsList(), isEmpty);
        expect(service.totalStorageUsedBytes, 0);
        expect(snapshots.last, isEmpty);
        await service.deleteAllDownloads();
        expect(service.getDownloadedSurahsList(), isEmpty);
      } finally {
        service.removeListener(listener);
      }
    } finally {
      Process.runSync('chmod', ['0755', audio.path]);
      await service.deleteAllDownloads();
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'), null);
      temp.deleteSync(recursive: true);
    }
  });
}
