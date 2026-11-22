import 'dart:typed_data';

import 'package:almomin/core/services/shamela_epub_service.dart';
import 'package:almomin/core/services/shamela_library_service.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

const _expected = ShamelaBook(
  id: 88,
  title: 'Rootfile Fixture',
  author: 'Fixture Author',
  downloadUrl: '',
  urlCandidates: [],
);

// Local synthetic ZIPs only, never a real book or user file.
Uint8List _epub(String reference, String opfPath, {String? alternateOpfPath}) {
  final slash = opfPath.lastIndexOf('/');
  final directory = slash < 0 ? '' : opfPath.substring(0, slash + 1);
  const opf = '''
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Rootfile Fixture</dc:title><dc:creator>Fixture Author</dc:creator>
    <dc:identifier id="id">fixture-88</dc:identifier>
  </metadata>
  <manifest><item id="first" href="first.xhtml"
    media-type="application/xhtml+xml"/></manifest>
  <spine><itemref idref="first"/></spine>
</package>''';
  final archive = Archive();
  archive.addFile(ArchiveFile.string('mimetype', 'application/epub+zip')
    ..compression = CompressionType.none);
  archive.addFile(ArchiveFile.string('META-INF/container.xml', '''
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
  <rootfiles><rootfile full-path="$reference"
    media-type="application/oebps-package+xml"/></rootfiles>
</container>'''));
  archive.addFile(ArchiveFile.string(opfPath, opf));
  if (alternateOpfPath != null) {
    archive.addFile(ArchiveFile.string(alternateOpfPath,
        opf.replaceFirst('Rootfile Fixture', 'Wrong Alternate Package')));
  }
  archive.addFile(ArchiveFile.string('${directory}first.xhtml', '''
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Fixture</title></head>
<body><p>ROOTFILE synthetic text</p></body></html>'''));
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  for (final (name, reference, path) in <(String, String, String)>[
    ('space', 'OEBPS/content%20book.opf', 'OEBPS/content book.opf'),
    (
      'Arabic filename',
      'OEBPS/${Uri.encodeComponent('كتاب')}.opf',
      'OEBPS/كتاب.opf'
    ),
    ('encoded hash', 'OEBPS/content%23book.opf', 'OEBPS/content#book.opf'),
    ('decode once', 'OEBPS/content%2520book.opf', 'OEBPS/content%20book.opf'),
    ('encoded directory', 'EPUB%20Book/content.opf', 'EPUB Book/content.opf'),
    ('encoded plus', 'OEBPS/content%2Bbook.opf', 'OEBPS/content+book.opf'),
    (
      'Arabic directory',
      '${Uri.encodeComponent('الكتاب')}/content.opf',
      'الكتاب/content.opf'
    ),
  ]) {
    test('resolves encoded rootfile $name when no exact raw entry exists', () {
      final book =
          ShamelaEpubService.parseEpub(_epub(reference, path), _expected);
      final slash = path.lastIndexOf('/');
      final directory = slash < 0 ? '' : path.substring(0, slash + 1);
      expect(book.id, 88);
      expect(book.title, 'Rootfile Fixture');
      expect(book.pages.single.path, '${directory}first.xhtml');
      expect(book.pages.single.text, 'ROOTFILE synthetic text');
    });
  }

  // Exact raw-entry priority is the existing compatibility contract. This
  // repair adds a missing-entry fallback, not full rootfile URL conformance.
  for (final path in [
    'OEBPS/content.opf',
    'OEBPS/content book.opf',
    'OEBPS/كتاب.opf',
    'OEBPS/content+book.opf',
    'OEBPS/content#book.opf',
    'OEBPS/content%book.opf',
    'OEBPS/content%ZZbook.opf',
    'OEBPS/content%FFbook.opf',
  ]) {
    test('preserves an existing exact raw rootfile entry $path', () {
      final book = ShamelaEpubService.parseEpub(_epub(path, path), _expected);
      expect(book.pages.single.text, 'ROOTFILE synthetic text');
    });
  }

  test('preserves raw-entry priority if raw and decoded package names coexist',
      () {
    const raw = 'OEBPS/content%20book.opf';
    final book = ShamelaEpubService.parseEpub(
        _epub(raw, raw, alternateOpfPath: 'OEBPS/content book.opf'), _expected);
    expect(book.title, 'Rootfile Fixture');
    expect(book.pages.single.text, 'ROOTFILE synthetic text');
  });

  for (final (name, reference) in [
    ('absolute path', '%2FOEBPS/content.opf'),
    ('backslash', 'OEBPS%5Ccontent.opf'),
    ('external URL', 'https%3A%2F%2Fevil.invalid%2Fcontent.opf'),
    ('container escape', '%2e%2e/escape.opf'),
  ]) {
    test('checks decoded missing-entry rootfile $name restrictions', () {
      expect(
          () => ShamelaEpubService.parseEpub(
              _epub(reference, 'OEBPS/content.opf'), _expected),
          throwsA(isA<ShamelaEpubSecurityException>()));
    });
  }

  for (final reference in [
    '',
    '/OEBPS/content.opf',
    'OEBPS\\content.opf',
    'https://evil.invalid/content.opf',
    '../escape.opf',
  ]) {
    test('retains raw rootfile rejection for $reference', () {
      expect(
          () => ShamelaEpubService.parseEpub(
              _epub(reference, 'OEBPS/content.opf'), _expected),
          throwsA(isA<ShamelaEpubSecurityException>()));
    });
  }

  for (final invalid in ['%ZZ', '%', '%F', '%FF', '%C3%28']) {
    test('missing rootfile with malformed encoding $invalid fails validation',
        () {
      expect(
          () => ShamelaEpubService.parseEpub(
              _epub('OEBPS/missing$invalid.opf', 'OEBPS/content.opf'),
              _expected),
          throwsA(isA<ShamelaEpubValidationException>()));
    });
  }

  for (final reference in [
    'OEBPS/content.opf#not-a-rootfile-fragment',
    'OEBPS/content.opf?not-a-rootfile-query',
  ]) {
    test('does not add fragment or query interpretation for $reference', () {
      expect(
          () => ShamelaEpubService.parseEpub(
              _epub(reference, 'OEBPS/content.opf'), _expected),
          throwsA(isA<ShamelaEpubValidationException>()));
    });
  }

  test('a missing decoded rootfile still fails validation', () {
    expect(
        () => ShamelaEpubService.parseEpub(
            _epub('OEBPS/missing%20book.opf', 'OEBPS/content.opf'), _expected),
        throwsA(isA<ShamelaEpubValidationException>()));
  });
}
