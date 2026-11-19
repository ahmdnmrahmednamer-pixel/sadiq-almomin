import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'shamela_synthetic_fixtures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import '../lib/core/services/shamela_epub_service.dart';
import '../lib/core/services/shamela_library_service.dart';

const book = ShamelaBook(
    id: 1446,
    title: 'صحيح ابن خزيمة',
    author: 'ابن خزيمة',
    downloadUrl: '',
    urlCandidates: []);
Uint8List fixture(String name) {
 final file=File('test/fixtures/shamela/$name.epub');
 return file.existsSync()?file.readAsBytesSync():base64Decode(shamelaSyntheticFixtures[name]!);
}

class DownloadFixture implements HttpClientAdapter {
  bool offline = false;
  int calls = 0;
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? stream,
      Future<dynamic>? future) async {
    calls++;
    if (offline)
      throw DioException.connectionError(requestOptions: o, reason: 'offline');
    if (o.uri.path.contains('/index.php/book/'))
      return ResponseBody.fromString(
          '<a href="https://old.shamela.ws/epubs/014/1446.epub">EPUB</a>', 200,
          headers: {
            Headers.contentTypeHeader: ['text/html']
          });
    return ResponseBody.fromBytes(fixture('valid'), 200, headers: {
      Headers.contentTypeHeader: ['application/epub+zip']
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
      'official metadata link discovered exactly, foreign or different-book links rejected',
      () {
    expect(
        ShamelaEpubService.discoverEpubUrl(
            '<a href="https://old.shamela.ws/epubs/014/1446.epub">EPUB</a>',
            1446),
        'https://old.shamela.ws/epubs/014/1446.epub');
    expect(
        () => ShamelaEpubService.discoverEpubUrl(
            '<a href="https://evil.invalid/epubs/1446.epub">x</a>', 1446),
        throwsA(isA<ShamelaEpubUnavailableException>()));
    expect(
        () => ShamelaEpubService.discoverEpubUrl(
            '<a href="https://old.shamela.ws/epubs/014/1447.epub">x</a>', 1446),
        throwsA(isA<ShamelaEpubUnavailableException>()));
  });
  test(
      'synthetic EPUB preserves reading order, tashkeel, footnotes and strips active HTML',
      () {
    final b = ShamelaEpubService.parseEpub(fixture('valid'), book);
    expect(b.pages.length, 2);
    expect(b.pages.first.text, contains('بِسْمِ اللَّهِ'));
    expect(b.pages.first.text, contains('حاشية الصفحة الأولى'));
    expect(b.pages.last.text, contains('الصفحة الثانية'));
    expect(b.pages.first.text, isNot(contains('ATTACK_SHOULD_NOT_RENDER')));
    expect(b.pages.first.text, isNot(contains('HIDDEN_STYLE')));
    expect(b.flattenedToc.length, 2);
  });
  for (final name in [
    'traversal',
    'entity',
    'identity',
    'missing',
    'oversized',
    'encrypted',
    'symlink',
    'duplicate'
  ]) {
    test('rejects $name EPUB', () {
      expect(() => ShamelaEpubService.parseEpub(fixture(name), book),
          throwsA(isA<ShamelaEpubException>()));
    });
  }
  test('real official EPUB has complete spine and NCX references', () {
    final b = ShamelaEpubService.parseEpub(
        File(Platform.environment['SHAMELA_REAL_EPUB']!).readAsBytesSync(),
        book);
    expect(b.id, 1446);
    expect(b.pages.length, 5118);
    expect(b.flattenedToc.length, 2245);
    expect(b.pages[1].text, contains('صَحِيحُ ابْنِ خُزَيْمَةَ'));
    expect(b.pages.last.path, endsWith('P5117.xhtml'));
  }, skip: Platform.environment['SHAMELA_REAL_EPUB'] == null);
  test(
      'download saves to private root and all pages/TOC reopen with network disabled',
      () async {
    final dir = await Directory.systemTemp.createTemp('shamela-private-test-');
    addTearDown(() => dir.delete(recursive: true));
    final adapter = DownloadFixture();
    final dio = Dio()..httpClientAdapter = adapter;
    final svc = ShamelaEpubService(dio: dio, rootDir: dir);
    final downloaded = await svc.downloadBook(book);
    expect(downloaded.pages.length, 2);
    adapter.offline = true;
    final calls = adapter.calls;
    final reloaded = await svc.loadSavedBook(1446);
    expect(adapter.calls, calls);
    expect(reloaded!.pages[1].text, contains('الصفحة الثانية'));
    expect(reloaded.flattenedToc.length, 2);
    expect((await svc.listSavedBooks()).length, 1);
    expect(await File('${dir.path}/shamela/1446/book.epub').exists(), true);
  });
}
