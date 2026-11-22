import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/services/bundled_tafsir_source.dart';
import '../lib/core/services/tafsir_service.dart';

/// Independent real-asset identity coverage: decodes the bundled bytes on disk
/// (manifest identity + sha256, same as the loader) and ties the service output
/// verbatim to those bytes. No fakes and no asset mocks.
Map<String, dynamic> decodeChapter(String bundledId, int surah) {
  final manifest = jsonDecode(File('assets/data/tafsir_${bundledId}_manifest.json').readAsStringSync()) as Map<String, dynamic>;
  expect(manifest['edition'], bundledId);
  final chapter = manifest['surahs']['$surah'] as Map<String, dynamic>;
  final parts = [for (var n = 1; n <= (chapter['parts'] as int); n++) File('assets/data/tafsir_${bundledId}_${surah}_$n.b64').readAsStringSync()];
  final bytes = GZipDecoder().decodeBytes(base64Decode(parts.map((p) => p.trim()).join()));
  expect(sha256.convert(bytes).toString(), chapter['sha256']);
  return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
}

String pageTextFor(Map<String, dynamic> chapter, int ayah) {
  final ids = chapter['locations']['$ayah'] as List;
  final first = ids.first;
  final id = first is Map ? first['id'] as int : first as int;
  final raw = chapter['pages'][id] as Map<String, dynamic>;
  return raw['textFormat'] == 'plain' ? raw['text'] as String : BundledTafsirSource.plain(raw['text'] as String);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('real bundled Muyassar asset read keeps Muyassar identity and verbatim text', () async {
    final chapter = decodeChapter('muyassar_witness', 1);
    final assetText = pageTextFor(chapter, 1);
    final r = await TafsirService.getTafsir(surahId: 1, ayahNumber: 1, editionId: 'muyassar');
    expect(r.editionId, 'muyassar');
    expect(r.editionName, 'التفسير الميسر');
    expect(r.hasSourceText, isTrue);
    expect(r.sourceUrl, isNull);
    expect(r.tafsirText, contains(assetText));
  });
  test('real bundled Ibn Kathir asset read keeps its own identity, never Muyassar text', () async {
    final chapter = decodeChapter('ibn_kathir_pages', 1);
    final assetText = pageTextFor(chapter, 1);
    final r = await TafsirService.getTafsir(surahId: 1, ayahNumber: 1, editionId: 'ibn_kathir');
    expect(r.editionId, 'ibn_kathir');
    expect(r.editionName, contains('ابن كثير'));
    expect(r.hasSourceText, isTrue);
    expect(r.tafsirText, contains(assetText));
    final m = await TafsirService.getTafsir(surahId: 1, ayahNumber: 1, editionId: 'muyassar');
    expect(r.tafsirText, isNot(m.tafsirText));
  });
}
