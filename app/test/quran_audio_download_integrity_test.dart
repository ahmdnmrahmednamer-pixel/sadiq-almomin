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
  final service = AudioDownloadService.instance;
  late Directory temp;
  HttpOverrides? prior;
  setUpAll(() async {
    temp = Directory.systemTemp.createTempSync('audio_integrity_review_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => call.method == 'getApplicationDocumentsDirectory'
                ? temp.path
                : null);
    prior = HttpOverrides.current;
    HttpOverrides.global = DynamicHttpOverrides();
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init();
    await service.init();
  });
  tearDownAll(() {
    HttpOverrides.global = prior;
    DynamicHttpOverrides.activeHandler = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    temp.deleteSync(recursive: true);
  });
  for (final size in [0, 32, 1000]) {
    test(
        'rejected short body size=$size must preserve an accepted existing download',
        () async {
      DynamicHttpOverrides.activeHandler = (m, u, r) async =>
          TestHttpClientResponse(
              Stream.value(Uint8List(2048)..fillRange(0, 2048, 7)),
              contentLength: 2048);
      expect(
          await service.downloadSurah(
              reciterId: 'mishari_alafasy', surahId: 1, surahName: 'Synthetic'),
          isTrue);
      final original = service.getLocalAudioPath('mishari_alafasy', 1)!;
      DynamicHttpOverrides.activeHandler = (m, u, r) async =>
          TestHttpClientResponse(Stream.value(Uint8List(size)),
              contentLength: size);
      final accepted = await service.downloadSurah(
          reciterId: 'mishari_alafasy', surahId: 1, surahName: 'Synthetic');
      // Evidence of whether the replacement was published, even before assertions.
      print(
          'candidateBytes=$size accepted=$accepted previousPathBytes=${File(original).lengthSync()} downloaded=${service.isDownloaded('mishari_alafasy', 1)}');
      expect(accepted, isFalse);
      expect(File(original).readAsBytesSync(), everyElement(7));
      expect(File(original).lengthSync(), 2048);
      expect(service.isDownloaded('mishari_alafasy', 1), isTrue);
    });
  }
  test(
      'rejected fresh short body never creates an offline entry or leaves temp files',
      () async {
    DynamicHttpOverrides.activeHandler = (m, u, r) async =>
        TestHttpClientResponse(Stream.value(Uint8List(32)), contentLength: 32);
    expect(
        await service.downloadSurah(
            reciterId: 'mishari_alafasy', surahId: 2, surahName: 'Synthetic'),
        isFalse);
    expect(service.getLocalAudioPath('mishari_alafasy', 2), isNull);
    expect(service.isDownloading('mishari_alafasy', 2), isFalse);
    expect(service.getDownloadProgress('mishari_alafasy', 2), 0);
    expect(
        Directory('${temp.path}/quran_audio')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.tmp')),
        isEmpty);
  });
  test('valid replacement just above existing minimum is accepted', () async {
    DynamicHttpOverrides.activeHandler = (m, u, r) async =>
        TestHttpClientResponse(
            Stream.value(Uint8List(1001)..fillRange(0, 1001, 9)),
            contentLength: 1001);
    expect(
        await service.downloadSurah(
            reciterId: 'mishari_alafasy', surahId: 1, surahName: 'Synthetic'),
        isTrue);
    expect(service.isDownloaded('mishari_alafasy', 1), isTrue);
    expect(File(service.getLocalAudioPath('mishari_alafasy', 1)!).lengthSync(),
        1001);
    expect(service.downloadedSurahs['mishari_alafasy_1']!.fileSizeBytes, 1001);
  });
}
