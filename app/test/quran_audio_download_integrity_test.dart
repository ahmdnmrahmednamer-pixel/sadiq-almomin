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
  for (final (reciterId, surahId) in [
    ('unknown_reciter', 1),
    ('', 1),
    ('alafasy', 0),
    ('alafasy', -1),
    ('alafasy', 115),
  ]) {
    test('invalid request $reciterId/$surahId cannot download another reciter or invalid surah', () async {
      var requests = 0;
      final filesBefore = Directory('${temp.path}/quran_audio').listSync().map((f) => f.path).toSet();
      DynamicHttpOverrides.activeHandler = (m, u, r) async {
        requests++;
        return TestHttpClientResponse(Stream.value(Uint8List(2048)), contentLength: 2048);
      };
      expect(await service.downloadSurah(reciterId: reciterId, surahId: surahId, surahName: 'Synthetic'), isFalse);
      expect(requests, 0);
      expect(service.downloadedSurahs, isNot(contains('${reciterId}_$surahId')));
      expect(service.isDownloading(reciterId, surahId), isFalse);
      expect(service.getLocalAudioPath(reciterId, surahId), isNull);
      expect(Directory('${temp.path}/quran_audio').listSync().map((f) => f.path).toSet(), filesBefore);
    });
  }
  test('valid first and last surah keep the exact requested reciter without changing preferences', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_reciter_id', 'unchanged_test_sentinel');
    final urls = <Uri>[];
    DynamicHttpOverrides.activeHandler = (m, u, r) async {
      urls.add(u);
      return TestHttpClientResponse(Stream.value(Uint8List(2048)), contentLength: 2048);
    };
    final reciter = SettingsService.availableReciters.last;
    try {
      for (final number in [1, 114]) {
        expect(await service.downloadSurah(reciterId: reciter.id, surahId: number, surahName: 'Synthetic'), isTrue);
        expect(urls.last.toString(), '${reciter.serverUrl}${number.toString().padLeft(3, '0')}.mp3');
        expect(service.downloadedSurahs['${reciter.id}_$number']!.reciterName, reciter.nameAr);
        expect(service.isDownloaded(reciter.id, number), isTrue);
      }
      expect(prefs.getString('selected_reciter_id'), 'unchanged_test_sentinel');
    } finally {
      for (final number in [1, 114]) {
        await service.deleteDownloadedSurah(reciter.id, number);
      }
    }
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
              reciterId: 'alafasy', surahId: 1, surahName: 'Synthetic'),
          isTrue);
      final original = service.getLocalAudioPath('alafasy', 1)!;
      DynamicHttpOverrides.activeHandler = (m, u, r) async =>
          TestHttpClientResponse(Stream.value(Uint8List(size)),
              contentLength: size);
      final accepted = await service.downloadSurah(
          reciterId: 'alafasy', surahId: 1, surahName: 'Synthetic');
      // Evidence of whether the replacement was published, even before assertions.
      print(
          'candidateBytes=$size accepted=$accepted previousPathBytes=${File(original).lengthSync()} downloaded=${service.isDownloaded('alafasy', 1)}');
      expect(accepted, isFalse);
      expect(File(original).readAsBytesSync(), everyElement(7));
      expect(File(original).lengthSync(), 2048);
      expect(service.isDownloaded('alafasy', 1), isTrue);
    });
  }
  test(
      'rejected fresh short body never creates an offline entry or leaves temp files',
      () async {
    DynamicHttpOverrides.activeHandler = (m, u, r) async =>
        TestHttpClientResponse(Stream.value(Uint8List(32)), contentLength: 32);
    expect(
        await service.downloadSurah(
            reciterId: 'alafasy', surahId: 2, surahName: 'Synthetic'),
        isFalse);
    expect(service.getLocalAudioPath('alafasy', 2), isNull);
    expect(service.isDownloading('alafasy', 2), isFalse);
    expect(service.getDownloadProgress('alafasy', 2), 0);
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
            reciterId: 'alafasy', surahId: 1, surahName: 'Synthetic'),
        isTrue);
    expect(service.isDownloaded('alafasy', 1), isTrue);
    expect(File(service.getLocalAudioPath('alafasy', 1)!).lengthSync(),
        1001);
    expect(service.downloadedSurahs['alafasy_1']!.fileSizeBytes, 1001);
  });
}
