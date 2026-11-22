import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/core/audio/islamic_audio_catalog.dart';
import 'package:almomin/core/audio/islamic_audio_models.dart';
import 'package:almomin/core/audio/kiwifu_adhan_catalog.dart';

Map<String, Object?> legacyFields(IslamicAudioTrack t) => {
      'id': t.id,
      'title': t.title,
      'subtitle': t.subtitle,
      'type': t.type.name,
      'assetPath': t.assetPath,
      'remoteUrl': t.remoteUrl,
      'fallbackUrls': t.fallbackUrls,
      'durationFormatted': t.durationFormatted,
      'rawNotificationSound': t.rawNotificationSound,
      'quality': t.quality,
      'fileSizeBytes': t.fileSizeBytes,
      'categoryAr': t.categoryAr,
      'muezzinName': t.muezzinName,
      'imageUrl': t.imageUrl,
      'surahNumber': t.surahNumber,
      'reciterId': t.reciterId,
    };

void main() {
  const revision = 'b9180a2bb769f74cff8e378ef2cc7aaf8db5cd5b';
  final legacy = jsonDecode(File('test/fixtures/pre_kiwifu_audio_catalog.json')
      .readAsStringSync()) as List;
  test('all 93 existing catalog records retain every original field and order',
      () {
    expect(legacy.length, 93);
    expect(islamicAudioCatalog.take(legacy.length).map(legacyFields).toList(),
        legacy);
    expect(islamicAudioCatalog.length, legacy.length + 230);
  });
  test('231 source filenames are retained as 230 unique recording blobs', () {
    expect(kiwifuAdhanCatalog.length, 230);
    final names = kiwifuAdhanCatalog.expand((t) => t.sourceFileNames).toList();
    expect(names.length, 231);
    expect(names.toSet().length, 231);
    expect(
        kiwifuAdhanCatalog.where((t) => t.sourceFileNames.length == 2).length,
        1);
    expect(
        kiwifuAdhanCatalog.every((t) => t.sourceFileNames.length <= 2), isTrue);
  });
  test('new stable content IDs are unique and never replace stored legacy IDs',
      () {
    final ids = islamicAudioCatalog.map((t) => t.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final t in kiwifuAdhanCatalog) {
      expect(t.remoteGitBlobSha1, matches(RegExp(r'^[0-9a-f]{40}$')));
      expect(t.id, 'kiwifu_adhan_${t.remoteGitBlobSha1}');
      expect(t.sourceRevision, revision);
    }
  });
  test('all downloads point to exact pinned HTTPS source bytes', () {
    for (final t in kiwifuAdhanCatalog) {
      final u = Uri.parse(t.remoteUrl!);
      expect(u.scheme, 'https');
      expect(u.host, 'raw.githubusercontent.com');
      expect(
          u.pathSegments.take(3).toList(), ['Kiwifu', 'adhan-mp3', revision]);
      expect(t.sourceFileNames, contains(u.pathSegments.last));
      expect(t.fallbackUrls, isEmpty);
      expect(t.fileSizeBytes, greaterThan(1000));
      final source = Uri.parse(t.sourceUrl!);
      expect(source.host, 'github.com');
      expect(source.pathSegments.take(4).toList(),
          ['Kiwifu', 'adhan-mp3', 'blob', revision]);
      expect(source.pathSegments.last, u.pathSegments.last);
    }
  });
  test(
      'catalog adds on-demand records without bundling or fake alarm resources',
      () {
    for (final t in kiwifuAdhanCatalog) {
      expect(t.type, IslamicAudioType.adhan);
      expect(t.isBundled, isFalse);
      expect(t.assetPath, isNull);
      expect(t.rawNotificationSound, isNull);
      expect(t.muezzinName, isNull);
    }
    expect(
        islamicAudioCatalog
            .take(legacy.length)
            .where((t) => t.isBundled)
            .length,
        legacy.where((t) => t['assetPath'] != null).length);
  });
  test(
      'source labels do not assert uniform HD, duration or verified voice identity',
      () {
    for (final t in kiwifuAdhanCatalog) {
      expect(t.title, isNotEmpty);
      expect(t.title.length, lessThanOrEqualTo(70));
      expect(t.subtitle, contains('الاسم حسب ملف المصدر'));
      expect(t.quality, isNot(contains('HD')));
      expect(t.durationFormatted, 'غير محددة');
    }
  });
  test('legacy source metadata defaults do not migrate user data', () {
    for (final t in islamicAudioCatalog.take(legacy.length)) {
      expect(t.sourceUrl, isNull);
      expect(t.sourceRevision, isNull);
      expect(t.sourceFileNames, isEmpty);
      expect(t.remoteGitBlobSha1, isNull);
    }
  });
}
