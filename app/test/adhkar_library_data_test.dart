import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/models/adhkar_library.dart';
import 'package:almomin/core/services/adhkar_library_loader.dart';

class _BytesBundle extends CachingAssetBundle {
  _BytesBundle(this.bytes);
  final List<int> bytes;
  @override
  Future<ByteData> load(String key) async {
    expect(key, AdhkarLibraryLoader.assetPath);
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final source = File('assets/data/rn0x_adhkar.json').readAsStringSync();

  test('packaging adds exactly LF and preserves pinned upstream bytes',
      () async {
    final packaged = File('assets/data/rn0x_adhkar.json').readAsBytesSync();
    expect(packaged, hasLength(148986));
    expect(packaged.last, 10);
    final original = packaged.sublist(0, packaged.length - 1);
    expect(original, hasLength(148985));
    expect(original.last, 93);
    expect(sha256.convert(original).toString(),
        ImportedAdhkarLibrary.upstreamSha256);
    expect(sha256.convert(packaged).toString(),
        ImportedAdhkarLibrary.bundledSha256);
    expect(
        jsonDecode(utf8.decode(packaged)), jsonDecode(utf8.decode(original)));
    await expectLater(
      AdhkarLibraryLoader.load(bundle: _BytesBundle(original)),
      throwsFormatException,
    );
  });

  test('pinned corpus preserves every source category, text and count', () {
    final library = ImportedAdhkarLibrary.parse(source);
    final raw = jsonDecode(source) as List;
    expect(library.categories, hasLength(132));
    final all = library.categories.expand((c) => c.items).toList();
    expect(all, hasLength(267));
    expect(all.map((e) => e.progressKey).toSet(), hasLength(267));
    expect(all.map((e) => e.sourceItemId).toSet(), hasLength(24));
    for (var c = 0; c < raw.length; c++) {
      final actual = library.categories[c];
      final expected = raw[c] as Map;
      expect(actual.sourceCategoryId, expected['id']);
      expect(actual.title, expected['category']);
      expect(actual.audioRelativePath, expected['audio']);
      final items = expected['array'] as List;
      expect(actual.items, hasLength(items.length));
      for (var i = 0; i < items.length; i++) {
        final item = actual.items[i];
        final expectedItem = items[i] as Map;
        expect(item.sourceItemId, expectedItem['id']);
        expect(item.text, expectedItem['text']);
        expect(item.repeatCount, expectedItem['count']);
        expect(item.audioRelativePath, expectedItem['audio']);
        expect(item.progressKey, isNot(item.sourceItemId.toString()));
      }
    }
    expect(() => library.categories.clear(), throwsUnsupportedError);
    expect(
        () => library.categories.first.items.clear(), throwsUnsupportedError);
  });

  test('bundled text passes integrity and never changes existing preferences',
      () async {
    SharedPreferences.setMockInitialValues({
      'adhkar_daily_counts_v1': '{"101":1,"201":2}',
      'tasbih_count': 17,
      'notif_short_salawat_frequency': 'hourly',
    });
    final prefs = await SharedPreferences.getInstance();
    final before = {for (final key in prefs.getKeys()) key: prefs.get(key)};
    final loaded = await AdhkarLibraryLoader.load();
    expect(loaded.categories, hasLength(132));
    expect({for (final key in prefs.getKeys()) key: prefs.get(key)}, before);
  });

  test(
      'altered bundle fails integrity rather than silently changing the corpus',
      () async {
    await expectLater(
      AdhkarLibraryLoader.load(bundle: _BytesBundle(utf8.encode('$source\n'))),
      throwsFormatException,
    );
  });

  test('malformed shape, duplicate IDs, count and audio location are rejected',
      () {
    final raw = jsonDecode(source) as List;
    final first = jsonDecode(jsonEncode(raw.first)) as Map<String, dynamic>;
    expect(() => ImportedAdhkarLibrary.parse('{}'), throwsFormatException);
    expect(() => ImportedAdhkarLibrary.parse('[]'), throwsFormatException);
    expect(() => ImportedAdhkarLibrary.parse(jsonEncode([first, first])),
        throwsFormatException);
    final firstItem = (first['array'] as List).first;
    first['array'] = [firstItem, firstItem];
    expect(() => ImportedAdhkarLibrary.parse(jsonEncode([first])),
        throwsFormatException);
    first['array'] = [firstItem];
    firstItem['count'] = 0;
    expect(() => ImportedAdhkarLibrary.parse(jsonEncode([first])),
        throwsFormatException);
    firstItem['count'] = 1;
    firstItem['audio'] = '/audio/../1.mp3';
    expect(() => ImportedAdhkarLibrary.parse(jsonEncode([first])),
        throwsFormatException);
    firstItem['audio'] = 'https://example.invalid/1.mp3';
    expect(() => ImportedAdhkarLibrary.parse(jsonEncode([first])),
        throwsFormatException);
  });
}
