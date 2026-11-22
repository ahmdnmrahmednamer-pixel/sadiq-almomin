import 'dart:typed_data';

import 'package:almomin/core/services/shamela_epub_service.dart';
import 'package:almomin/core/services/shamela_library_service.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

const _expected = ShamelaBook(
  id: 87,
  title: 'Fixture Book',
  author: 'Fixture Author',
  downloadUrl: '',
  urlCandidates: [],
);

// Synthetic local ZIPs only. No real book, network access or user files.
Uint8List _epub({
  required String href,
  required String filePath,
  String tocHref = 'toc.ncx',
  String tocFile = 'toc.ncx',
  String? firstTocHref,
}) {
  final archive = Archive();
  archive.addFile(ArchiveFile.string('mimetype', 'application/epub+zip')
    ..compression = CompressionType.none);
  archive.addFile(ArchiveFile.string('META-INF/container.xml', '''
<?xml version="1.0"?>
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
  <rootfiles><rootfile full-path="OEBPS/content.opf"
    media-type="application/oebps-package+xml"/></rootfiles>
</container>'''));
  archive.addFile(ArchiveFile.string('OEBPS/content.opf', '''
<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Fixture Book</dc:title><dc:creator>Fixture Author</dc:creator>
    <dc:identifier id="id">fixture-87</dc:identifier><dc:language>en</dc:language>
  </metadata>
  <manifest>
    <item id="first" href="$href" media-type="application/xhtml+xml"/>
    <item id="second" href="second.xhtml" media-type="application/xhtml+xml"/>
    <item id="toc" href="$tocHref" media-type="application/x-dtbncx+xml"/>
  </manifest>
  <spine toc="toc"><itemref idref="first"/><itemref idref="second"/></spine>
</package>'''));
  archive.addFile(ArchiveFile.string('OEBPS/$tocFile', '''
<?xml version="1.0"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head/><docTitle><text>Fixture Book</text></docTitle><navMap>
    <navPoint id="one" playOrder="1"><navLabel><text>First</text></navLabel>
      <content src="${firstTocHref ?? href}#section"/></navPoint>
    <navPoint id="two" playOrder="2"><navLabel><text>Second</text></navLabel>
      <content src="second.xhtml#section"/></navPoint>
  </navMap>
</ncx>'''));
  for (final (path, text) in [
    (filePath, 'FIRST synthetic text'),
    ('second.xhtml', 'SECOND synthetic text'),
  ]) {
    archive.addFile(ArchiveFile.string('OEBPS/$path', '''
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Fixture</title></head>
<body><p id="section">$text</p></body></html>'''));
  }
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  final cases = <(String, String, String)>[
    ('ordinary path', 'first.xhtml', 'first.xhtml'),
    ('space', 'first%20chapter.xhtml', 'first chapter.xhtml'),
    ('Arabic UTF-8', '${Uri.encodeComponent('الفصل')}.xhtml', 'الفصل.xhtml'),
    (
      'encoded hash in filename',
      'first%23chapter.xhtml',
      'first#chapter.xhtml'
    ),
    (
      'percent decoded once',
      'first%2520chapter.xhtml',
      'first%20chapter.xhtml'
    ),
    ('literal plus stays plus', 'first+chapter.xhtml', 'first+chapter.xhtml'),
    ('encoded directory', 'part%20one/first.xhtml', 'part one/first.xhtml'),
  ];

  for (final (name, href, path) in cases) {
    test('resolves $name and maps NCX to the same stable spine page', () {
      final book = ShamelaEpubService.parseEpub(
          _epub(href: href, filePath: path), _expected);
      expect(
          book.pages.map((p) => p.path), ['OEBPS/$path', 'OEBPS/second.xhtml']);
      expect(book.pages.map((p) => p.text),
          ['FIRST synthetic text', 'SECOND synthetic text']);
      expect(book.flattenedToc.map((entry) => entry.spineIndex), [0, 1]);
      expect(book.flattenedToc.first.contentSrc, '$href#section');
      expect(book.id, 87);
      expect(book.title, 'Fixture Book');
    });
  }

  test('resolves a percent-encoded NCX manifest href', () {
    final book = ShamelaEpubService.parseEpub(
        _epub(
          href: 'first.xhtml',
          filePath: 'first.xhtml',
          tocHref: 'toc%20data.ncx',
          tocFile: 'toc data.ncx',
        ),
        _expected);
    expect(book.flattenedToc.map((entry) => entry.spineIndex), [0, 1]);
    expect(book.pages.first.text, 'FIRST synthetic text');
  });

  for (final (name, href) in [
    ('external URL', 'https%3A%2F%2Fevil.invalid%2Ffirst.xhtml'),
    ('data URL', 'data%3Aapplication%2Fxhtml%2Bxml%2Cbody'),
    ('backslash', 'part%5Cfirst.xhtml'),
    ('absolute path', '%2Ffirst.xhtml'),
    ('container escape', '%2e%2e/%2e%2e/escape.xhtml'),
  ]) {
    test('checks decoded manifest paths against existing $name restrictions',
        () {
      expect(
          () => ShamelaEpubService.parseEpub(
              _epub(href: href, filePath: href), _expected),
          throwsA(isA<ShamelaEpubSecurityException>()));
    });
  }

  for (final href in [
    'missing.xhtml',
    '',
    'missing%ZZ.xhtml',
    'missing%.xhtml',
    'missing%F.xhtml',
    'missing%FF.xhtml',
    'missing%C3%28.xhtml',
  ]) {
    test('unmapped NCX reference $href preserves readable spine pages', () {
      final book = ShamelaEpubService.parseEpub(
          _epub(
              href: 'first.xhtml', filePath: 'first.xhtml', firstTocHref: href),
          _expected);
      expect(book.pages.map((page) => page.text),
          ['FIRST synthetic text', 'SECOND synthetic text']);
      expect(book.flattenedToc.map((entry) => entry.spineIndex), [-1, 1]);
      expect(book.flattenedToc.first.contentSrc, '$href#section');
    });
  }

  test('malformed NCX reference retains the former basename fallback', () {
    const href = 'unknown%ZZ/first.xhtml';
    final book = ShamelaEpubService.parseEpub(
        _epub(href: 'first.xhtml', filePath: 'first.xhtml', firstTocHref: href),
        _expected);
    expect(book.pages.map((page) => page.text),
        ['FIRST synthetic text', 'SECOND synthetic text']);
    expect(book.flattenedToc.map((entry) => entry.spineIndex), [0, 1]);
    expect(book.flattenedToc.first.contentSrc, '$href#section');
  });

  for (final invalid in ['%ZZ', '%', '%F', '%FF', '%C3%28']) {
    test('malformed encoding $invalid produces a typed validation failure', () {
      expect(
          () => ShamelaEpubService.parseEpub(
              _epub(
                  href: 'first$invalid.xhtml', filePath: 'first$invalid.xhtml'),
              _expected),
          throwsA(isA<ShamelaEpubValidationException>()));
    });
  }
}
