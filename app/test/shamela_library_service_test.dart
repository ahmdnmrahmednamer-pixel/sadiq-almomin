import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/services/shamela_library_service.dart';

class FixtureAdapter implements HttpClientAdapter {
  final bool offline;
  final int? category;
  final String? categoryHref;
  FixtureAdapter({this.offline = false, this.category = 6, this.categoryHref});
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<dynamic>? cancelFuture) async {
    if (offline)
      throw DioException.connectionError(
          requestOptions: options, reason: 'offline fixture');
    if (options.uri.path.startsWith('/book/'))
      return ResponseBody.fromString(
          category == null
              ? '<html><title>Unknown classification</title></html>'
              : '<html><title>صحيح ابن خزيمة</title><a href="${categoryHref ?? "https://shamela.ws/category/$category"}">تصنيف مصدر</a></html>',
          200,
          headers: {
            Headers.contentTypeHeader: ['text/html']
          });
    return ResponseBody.fromString(
        jsonEncode({
          'results': {
            'items': [
              {'id': '-1', 'text': 'جميع الكتب'},
              {'id': '1446', 'text': 'صحيح ابن خزيمة - ابن خزيمة'},
              {'id': '1446', 'text': 'صحيح ابن خزيمة - ابن خزيمة'},
              {'id': 'bad', 'text': 'invalid'}
            ]
          }
        }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json']
        });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('Arabic query normalization leaves original book text untouched', () {
    const original = 'إِحْيَاءُ العُلُومِ';
    expect(
        ShamelaLibraryService.normalizeArabicSearch(original), 'احياء العلوم');
    expect(original, 'إِحْيَاءُ العُلُومِ');
  });
  test('Search rejects placeholder IDs and deduplicates book identity',
      () async {
    final dio = Dio()..httpClientAdapter = FixtureAdapter();
    final svc = ShamelaLibraryService(dio: dio);
    final results = await svc.searchBooks('صحيح');
    expect(results.length, 1);
    expect(results.single.id, 1446);
    expect(results.single.title, 'صحيح ابن خزيمة');
    expect(results.single.author, 'ابن خزيمة');
  });
  test('Network failure must not masquerade as empty catalog', () async {
    final dio = Dio()..httpClientAdapter = FixtureAdapter(offline: true);
    final svc = ShamelaLibraryService(dio: dio);
    await svc.searchBooks('صحيح');
    expect(svc.lastError, isNotNull,
        reason: 'UI needs a real network error instead of no-results');
  });
  test('Nonreligious and unknown source categories are excluded', () async {
    for (final category in [13, 25, 26, 29, 32, 36, 37, 40, null]) {
      final svc = ShamelaLibraryService(
          dio: Dio()..httpClientAdapter = FixtureAdapter(category: category));
      expect(await svc.searchBooks('صحيح'), isEmpty,
          reason: 'Must exclude category $category');
    }
  });
  test('Verified source category retained and guessed download URLs retired',
      () async {
    final svc =
        ShamelaLibraryService(dio: Dio()..httpClientAdapter = FixtureAdapter());
    final found = await svc.searchBooks('صحيح');
    expect(found.single.categoryId, 6);
    expect(found.single.downloadUrl, isEmpty);
    expect(found.single.urlCandidates, isEmpty);
  });

  test('Foreign and lookalike category URLs cannot classify religious books',
      () async {
    for (final href in [
      'https://evil.invalid/category/6',
      'https://evil.invalid/https://shamela.ws/category/6',
      'http://shamela.ws/category/6',
      'https://shamela.ws/category/6/extra',
      'https://shamela.ws/category/6?q=1',
      'https://shamela.ws@evil.invalid/category/6'
    ]) {
      final svc = ShamelaLibraryService(
          dio: Dio()..httpClientAdapter = FixtureAdapter(categoryHref: href));
      expect(await svc.searchBooks('صحيح'), isEmpty, reason: href);
    }
  });
}
