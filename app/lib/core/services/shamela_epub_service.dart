import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

import 'shamela_library_service.dart';

// ==============================================================================
// Typed Exceptions for Shamela EPUB operations
// ==============================================================================

/// Base exception for Shamela EPUB handling.
class ShamelaEpubException implements Exception {
  final String message;
  final Object? cause;

  const ShamelaEpubException(this.message, [this.cause]);

  @override
  String toString() => cause != null
      ? 'ShamelaEpubException: $message ($cause)'
      : 'ShamelaEpubException: $message';
}

/// Thrown when an EPUB download link is not exposed or unavailable on old.shamela.ws.
class ShamelaEpubUnavailableException extends ShamelaEpubException {
  const ShamelaEpubUnavailableException(super.message, [super.cause]);

  @override
  String toString() => 'ShamelaEpubUnavailableException: $message';
}

/// Thrown when title validation or EPUB structural integrity verification fails.
class ShamelaEpubValidationException extends ShamelaEpubException {
  const ShamelaEpubValidationException(super.message, [super.cause]);

  @override
  String toString() => 'ShamelaEpubValidationException: $message';
}

/// Thrown when security constraints (size, zip bomb, traversal, encryption, symlink, XXE) are violated.
class ShamelaEpubSecurityException extends ShamelaEpubException {
  const ShamelaEpubSecurityException(super.message, [super.cause]);

  @override
  String toString() => 'ShamelaEpubSecurityException: $message';
}

// ==============================================================================
// Data Models: OfflineShamelaBook, OfflineShamelaPage, ShamelaTocEntry
// ==============================================================================

/// Represents a single chapter or page within an offline Shamela book.
class OfflineShamelaPage {
  /// Unique identifier from the EPUB manifest or spine itemref.
  final String id;

  /// Safe archive-relative path (e.g. "OEBPS/xhtml/P2.xhtml").
  final String path;

  /// Page title or section title extracted from markup.
  final String title;

  /// Accessible cleaned text content with original Arabic and tashkeel preserved.
  final String text;

  /// Extracted volume label if present (e.g. "الجزء: 1").
  final String? volume;

  /// Extracted printed page number if present (e.g. "الصفحة: 3").
  final String? pageNumber;

  const OfflineShamelaPage({
    required this.id,
    required this.path,
    required this.title,
    required this.text,
    this.volume,
    this.pageNumber,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'title': title,
        'text': text,
        if (volume != null) 'volume': volume,
        if (pageNumber != null) 'pageNumber': pageNumber,
      };

  factory OfflineShamelaPage.fromJson(Map<String, dynamic> json) =>
      OfflineShamelaPage(
        id: json['id'] as String? ?? '',
        path: json['path'] as String? ?? '',
        title: json['title'] as String? ?? '',
        text: json['text'] as String? ?? '',
        volume: json['volume'] as String?,
        pageNumber: json['pageNumber'] as String?,
      );

  @override
  String toString() =>
      'OfflineShamelaPage(id: $id, path: $path, title: "$title", length: ${text.length})';
}

/// Represents an entry in the table of contents (NCX navPoint or Nav XHTML).
class ShamelaTocEntry {
  /// Human-readable section or chapter label.
  final String label;

  /// Content source path as declared in the TOC (e.g. "xhtml/P2.xhtml#C1").
  final String contentSrc;

  /// Nesting depth level in hierarchy (0 = root level).
  final int depth;

  /// Corresponding 0-based page index in the book spine (-1 if not mapped).
  final int spineIndex;

  /// Nested child sections.
  final List<ShamelaTocEntry> children;

  const ShamelaTocEntry({
    required this.label,
    required this.contentSrc,
    required this.depth,
    required this.spineIndex,
    this.children = const [],
  });

  Map<String, dynamic> toJson() => {
        'label': label,
        'contentSrc': contentSrc,
        'depth': depth,
        'spineIndex': spineIndex,
        'children': children.map((c) => c.toJson()).toList(),
      };

  factory ShamelaTocEntry.fromJson(Map<String, dynamic> json) =>
      ShamelaTocEntry(
        label: json['label'] as String? ?? '',
        contentSrc: json['contentSrc'] as String? ?? '',
        depth: json['depth'] as int? ?? 0,
        spineIndex: json['spineIndex'] as int? ?? -1,
        children: (json['children'] as List<dynamic>?)
                ?.map(
                    (e) => ShamelaTocEntry.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  /// Recursively flattens this entry and all its children into a sequential list.
  List<ShamelaTocEntry> toFlatList() {
    final list = <ShamelaTocEntry>[this];
    for (final child in children) {
      list.addAll(child.toFlatList());
    }
    return list;
  }

  @override
  String toString() =>
      'ShamelaTocEntry(label: "$label", depth: $depth, spineIndex: $spineIndex, children: ${children.length})';
}

/// Complete offline Shamela book model stored in app internal storage.
class OfflineShamelaBook {
  /// Shamela numeric book ID.
  final int id;

  /// Validated book title.
  final String title;

  /// Author name.
  final String author;

  /// Verified source URL from which EPUB was retrieved.
  final String sourceUrl;

  /// Timestamp when the book was downloaded and parsed.
  final DateTime downloadedAt;

  /// Metadata extracted from EPUB OPF (identifier, language, publisher, etc.).
  final Map<String, dynamic> metadata;

  /// Ordered pages corresponding to the EPUB spine order.
  final List<OfflineShamelaPage> pages;

  /// Structured table of contents.
  final List<ShamelaTocEntry> toc;

  const OfflineShamelaBook({
    required this.id,
    required this.title,
    required this.author,
    required this.sourceUrl,
    required this.downloadedAt,
    required this.metadata,
    required this.pages,
    required this.toc,
  });

  /// Total page count.
  int get pageCount => pages.length;

  /// Access a page by stable 0-based spine index. Returns null if out of bounds.
  OfflineShamelaPage? getPage(int spineIndex) {
    if (spineIndex >= 0 && spineIndex < pages.length) {
      return pages[spineIndex];
    }
    return null;
  }

  /// Returns a flattened list of all TOC entries in depth-first reading order.
  List<ShamelaTocEntry> get flattenedToc =>
      toc.expand((entry) => entry.toFlatList()).toList();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'sourceUrl': sourceUrl,
        'downloadedAt': downloadedAt.toIso8601String(),
        'metadata': metadata,
        'pages': pages.map((p) => p.toJson()).toList(),
        'toc': toc.map((t) => t.toJson()).toList(),
      };

  factory OfflineShamelaBook.fromJson(Map<String, dynamic> json) =>
      OfflineShamelaBook(
        id: json['id'] is int
            ? json['id'] as int
            : (int.tryParse(json['id']?.toString() ?? '0') ?? 0),
        title: json['title'] as String? ?? '',
        author: json['author'] as String? ?? '',
        sourceUrl: json['sourceUrl'] as String? ?? '',
        downloadedAt: json['downloadedAt'] != null
            ? DateTime.tryParse(json['downloadedAt'].toString()) ??
                DateTime.now()
            : DateTime.now(),
        metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
        pages: (json['pages'] as List<dynamic>?)
                ?.map((p) =>
                    OfflineShamelaPage.fromJson(p as Map<String, dynamic>))
                .toList() ??
            const [],
        toc: (json['toc'] as List<dynamic>?)
                ?.map(
                    (t) => ShamelaTocEntry.fromJson(t as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  @override
  String toString() =>
      'OfflineShamelaBook(id: $id, title: "$title", author: "$author", pages: ${pages.length})';
}

// ==============================================================================
// ZIP Central Directory Preflight Scanner
// ==============================================================================

class _ZipPreflight {
  static const int maxCompressedBytes = 32 * 1024 * 1024; // 32 MiB
  static const int maxEntries = 20000;
  static const int maxIndividualExpandedBytes = 8 * 1024 * 1024; // 8 MiB
  static const int maxTotalExpandedBytes = 128 * 1024 * 1024; // 128 MiB
  static const double maxExpansionRatio = 200.0;

  static const int eocdSignature = 0x06054b50;
  static const int cdSignature = 0x02014b50;

  /// Inspects the ZIP Central Directory in memory before passing bytes to ZipDecoder.
  static void preflight(Uint8List bytes) {
    if (bytes.length > maxCompressedBytes) {
      throw ShamelaEpubSecurityException(
        'Archive exceeds compressed cap of 32 MiB: ${bytes.length} bytes',
      );
    }
    if (bytes.length < 22) {
      throw ShamelaEpubValidationException(
          'Archive too small to be a valid ZIP');
    }

    final byteData = ByteData.sublistView(bytes);

    // Locate EOCD record
    int eocdOffset = -1;
    final maxSearch = bytes.length - 65557;
    final stop = maxSearch < 0 ? 0 : maxSearch;
    for (int i = bytes.length - 22; i >= stop; i--) {
      if (byteData.getUint32(i, Endian.little) == eocdSignature) {
        eocdOffset = i;
        break;
      }
    }

    if (eocdOffset == -1) {
      throw ShamelaEpubValidationException(
          'EOCD signature not found in ZIP archive');
    }

    final diskNumber = byteData.getUint16(eocdOffset + 4, Endian.little);
    final cdDisk = byteData.getUint16(eocdOffset + 6, Endian.little);
    if (diskNumber != 0 || cdDisk != 0) {
      throw ShamelaEpubValidationException(
          'Multi-disk ZIP archives are not supported');
    }

    final totalEntries = byteData.getUint16(eocdOffset + 10, Endian.little);
    final cdSize = byteData.getUint32(eocdOffset + 12, Endian.little);
    final cdOffset = byteData.getUint32(eocdOffset + 16, Endian.little);

    if (totalEntries > maxEntries) {
      throw ShamelaEpubSecurityException(
        'ZIP entry count ($totalEntries) exceeds limit of $maxEntries entries',
      );
    }

    if (cdOffset < 0 || cdOffset + cdSize > bytes.length) {
      throw ShamelaEpubValidationException(
        'ZIP Central Directory bounds outside archive limits',
      );
    }

    int totalExpanded = 0;
    final seenPaths = <String>{};
    int curr = cdOffset;

    for (int i = 0; i < totalEntries; i++) {
      if (curr + 46 > cdOffset + cdSize) {
        throw ShamelaEpubValidationException(
          'Malformed Central Directory: header exceeds directory boundary at entry $i',
        );
      }

      final sig = byteData.getUint32(curr, Endian.little);
      if (sig != cdSignature) {
        throw ShamelaEpubValidationException(
          'Invalid Central Directory file header signature at entry $i',
        );
      }

      final flags = byteData.getUint16(curr + 8, Endian.little);
      // Bit 0: Encryption flag
      if ((flags & 0x01) != 0) {
        throw ShamelaEpubSecurityException(
            'Encrypted ZIP entry detected at index $i');
      }

      final compressedSize = byteData.getUint32(curr + 20, Endian.little);
      final uncompressedSize = byteData.getUint32(curr + 24, Endian.little);
      final fnLen = byteData.getUint16(curr + 28, Endian.little);
      final exLen = byteData.getUint16(curr + 30, Endian.little);
      final cmLen = byteData.getUint16(curr + 32, Endian.little);
      final externalAttributes = byteData.getUint32(curr + 38, Endian.little);

      // Check Unix symbolic link mode: (mode & 0170000) == 0120000 (0xA000)
      final unixMode = (externalAttributes >> 16) & 0xFFFF;
      if ((unixMode & 0xF000) == 0xA000) {
        throw ShamelaEpubSecurityException(
            'Symbolic link detected in ZIP archive at entry $i');
      }

      // Check individual expanded size limit
      if (uncompressedSize > maxIndividualExpandedBytes) {
        throw ShamelaEpubSecurityException(
          'ZIP entry expanded size ($uncompressedSize bytes) exceeds limit of 8 MiB',
        );
      }

      totalExpanded += uncompressedSize;
      if (totalExpanded > maxTotalExpandedBytes) {
        throw ShamelaEpubSecurityException(
          'Total expanded size ($totalExpanded bytes) exceeds cap of 128 MiB',
        );
      }

      // Expansion ratio check
      if (compressedSize > 0) {
        final ratio = uncompressedSize / compressedSize;
        if (ratio > maxExpansionRatio) {
          throw ShamelaEpubSecurityException(
            'ZIP entry expansion ratio ($ratio) exceeds max ratio of $maxExpansionRatio',
          );
        }
      } else if (uncompressedSize > 0) {
        throw ShamelaEpubSecurityException(
          'ZIP entry has 0 compressed bytes with $uncompressedSize uncompressed bytes',
        );
      }

      if (curr + 46 + fnLen > cdOffset + cdSize) {
        throw ShamelaEpubValidationException(
            'File name extends past Central Directory bounds');
      }

      final rawName = utf8.decode(
        bytes.sublist(curr + 46, curr + 46 + fnLen),
        allowMalformed: true,
      );

      // Security checks on entry path
      if (rawName.contains('\\')) {
        throw ShamelaEpubSecurityException(
            'ZIP entry path contains backslash: $rawName');
      }
      if (rawName.startsWith('/')) {
        throw ShamelaEpubSecurityException(
            'ZIP entry path is absolute: $rawName');
      }
      if (RegExp(r'^[a-zA-Z]:').hasMatch(rawName) || rawName.contains(':/')) {
        throw ShamelaEpubSecurityException(
            'ZIP entry path contains drive specifier: $rawName');
      }
      if (rawName.split('/').contains('..')) {
        throw ShamelaEpubSecurityException(
            'ZIP entry path contains ".." traversal: $rawName');
      }

      final normalizedPath = p.posix.normalize(
        rawName.endsWith('/') && rawName.length > 1
            ? rawName.substring(0, rawName.length - 1)
            : rawName,
      );

      if (seenPaths.contains(normalizedPath)) {
        throw ShamelaEpubSecurityException(
            'Duplicate ZIP entry path: $normalizedPath');
      }
      seenPaths.add(normalizedPath);

      curr += 46 + fnLen + exLen + cmLen;
    }

    if (bytes.isNotEmpty &&
        (totalExpanded / bytes.length) > maxExpansionRatio) {
      throw ShamelaEpubSecurityException(
          'Archive overall expansion ratio exceeds limit');
    }
  }
}

// ==============================================================================
// Safe XML & HTML Body Extraction Helpers
// ==============================================================================

class _XmlSafety {
  static final RegExp _entityPattern =
      RegExp(r'<!ENTITY\b', caseSensitive: false);

  /// Parses XML without network access and rejects DOCTYPE ENTITY definitions (XXE prevention).
  static XmlDocument parseSafeXml(String xmlString) {
    if (_entityPattern.hasMatch(xmlString)) {
      throw ShamelaEpubSecurityException(
          'External entity expansion is prohibited');
    }
    return XmlDocument.parse(xmlString);
  }
}

class _ArabicComparer {
  static final RegExp _tashkeelRegex = RegExp(
    r'[\u0617-\u061A\u064B-\u065F\u0670\u06D6-\u06ED\u0640]',
  );

  /// Conservative Arabic normalization used STRICTLY for comparison; original text remains untouched.
  static String normalizeForComparison(String text) {
    if (text.isEmpty) return '';
    var s = text.replaceAll(_tashkeelRegex, '');
    s = s.replaceAll(RegExp(r'[إأآٱ]'), 'ا');
    s = s.replaceAll('ة', 'ه');
    s = s.replaceAll('ى', 'ي');
    s = s.replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e]'), '');
    s = s.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), ' ');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Conservative title validation rejecting book mismatches while allowing editorial subtitle variations.
  static bool validateTitlesConservatively(String requested, String epubTitle) {
    final reqNorm = normalizeForComparison(requested).toLowerCase();
    final epubNorm = normalizeForComparison(epubTitle).toLowerCase();

    if (reqNorm.isEmpty || epubNorm.isEmpty) return false;
    if (reqNorm == epubNorm) return true;

    // Direct containment when substring is substantive
    if (reqNorm.contains(epubNorm) || epubNorm.contains(reqNorm)) {
      final shorter = reqNorm.length < epubNorm.length ? reqNorm : epubNorm;
      if (shorter.length >= 4) return true;
    }

    const genericStopwords = {
      'كتاب',
      'شرح',
      'مختصر',
      'رسالة',
      'متن',
      'في',
      'من',
      'على',
      'عن',
      'طبعة',
      'تحقيق',
      'دار',
      'مكتبة',
      'ط',
      'ج',
      'باب',
      'الجزء'
    };

    final reqTokens = reqNorm
        .split(' ')
        .where((w) => w.length > 1 && !genericStopwords.contains(w))
        .toSet();
    final epubTokens = epubNorm
        .split(' ')
        .where((w) => w.length > 1 && !genericStopwords.contains(w))
        .toSet();

    if (reqTokens.isEmpty || epubTokens.isEmpty) return false;

    final common = reqTokens.intersection(epubTokens);
    if (common.isEmpty) return false;

    final minSize = reqTokens.length < epubTokens.length
        ? reqTokens.length
        : epubTokens.length;
    if (common.length == minSize) return true;

    final unionSize = reqTokens.length + epubTokens.length - common.length;
    final jaccard = unionSize > 0 ? (common.length / unionSize) : 0.0;
    return jaccard >= 0.5;
  }
}

class _HtmlExtractor {
  static const Set<String> _disallowedTags = {
    'script',
    'style',
    'iframe',
    'object',
    'svg',
    'form',
    'button',
    'nav',
    'noscript',
    'input',
    'select',
    'textarea'
  };

  static const Set<String> _blockTags = {
    'p',
    'div',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'li',
    'blockquote',
    'hr',
    'tr',
    'table',
    'section',
    'article'
  };

  /// Extracts body text using HTML DOM without JS/WebView, preserving paragraph boundaries,
  /// original Arabic/tashkeel, footnotes, and page/volume labels.
  static ({String text, String? title, String? volume, String? pageNumber})
      extractPage(
    String htmlContent,
  ) {
    final document = html_parser.parse(htmlContent);

    // Remove forbidden and non-content elements
    for (final tag in _disallowedTags) {
      document.querySelectorAll(tag).forEach((el) => el.remove());
    }

    // Extract title from head
    String? pageTitle = document.querySelector('title')?.text.trim();
    if (pageTitle != null && pageTitle.isEmpty) pageTitle = null;

    final body = document.body ?? document.documentElement;
    if (body == null) {
      return (text: '', title: pageTitle, volume: null, pageNumber: null);
    }

    // Attempt to locate specific volume and page number labels
    String? volume;
    String? pageNumber;
    for (final el in body.querySelectorAll('div, span')) {
      final t = el.text;
      if (volume == null && t.contains('الجزء:')) {
        final match = RegExp(r'الجزء:\s*([^\s¦|]+)').firstMatch(t);
        if (match != null) volume = match.group(1)?.trim();
      }
      if (pageNumber == null && t.contains('الصفحة:')) {
        final match = RegExp(r'الصفحة:\s*([^\s¦|]+)').firstMatch(t);
        if (match != null) pageNumber = match.group(1)?.trim();
      }
    }

    // Extract section heading inside body if available
    final heading = body.querySelector('span.title, h1, h2, h3')?.text.trim();
    if (heading != null && heading.isNotEmpty) {
      pageTitle ??= heading;
    }

    final buffer = StringBuffer();

    void traverse(dom.Node node) {
      if (node is dom.Text) {
        buffer.write(node.text);
        return;
      }
      if (node is dom.Element) {
        final tag = node.localName?.toLowerCase() ?? '';
        final isBlock = _blockTags.contains(tag);
        final isFootnote =
            node.classes.contains('footnote') || node.classes.contains('note');

        if (isBlock || isFootnote) {
          buffer.write('\n');
        }
        if (tag == 'br') {
          buffer.write('\n');
        }

        for (final child in node.nodes) {
          traverse(child);
        }

        if (isBlock || isFootnote) {
          buffer.write('\n');
        }
      }
    }

    traverse(body);

    final rawLines = buffer.toString().split('\n');
    final cleanedLines = <String>[];
    for (final line in rawLines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        cleanedLines.add(trimmed);
      }
    }

    final fullText = cleanedLines.join('\n\n');
    return (
      text: fullText,
      title: pageTitle,
      volume: volume,
      pageNumber: pageNumber,
    );
  }
}

// ==============================================================================
// Shamela EPUB Service
// ==============================================================================

/// Service for discovering, downloading, validating, and managing offline Al-Maktaba
/// Al-Shamela EPUB books for accessible in-app reading.
class ShamelaEpubService {
  final Dio _dio;
  final Directory? _rootDir;

  static const String _prefPrefix = 'shamela_last_spine_pos_';
  static const Set<String> _allowlistedHosts = {'shamela.ws', 'old.shamela.ws'};

  /// Constructor with injectable Dio client and root Directory for isolated testing.
  ShamelaEpubService({Dio? dio, Directory? rootDir})
      : _dio = dio ?? _createDefaultDio(),
        _rootDir = rootDir;

  static Dio _createDefaultDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 15),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Referer': 'https://old.shamela.ws/',
          'Accept': '*/*',
        },
      ),
    );
  }

  Future<Directory> _getBaseDir() async {
    if (_rootDir != null) return _rootDir!;
    return await getApplicationSupportDirectory();
  }

  Future<Directory> _getShamelaDir() async {
    final base = await _getBaseDir();
    final shamelaDir = Directory(p.join(base.path, 'shamela'));
    if (!await shamelaDir.exists()) {
      await shamelaDir.create(recursive: true);
    }
    return shamelaDir;
  }

  // ==============================================================================
  // URL Discovery & Validation (Pure Static Method)
  // ==============================================================================

  /// Parses legacy book metadata HTML (from https://old.shamela.ws/index.php/book/{id})
  /// to discover the actual EPUB download URL.
  ///
  /// Strictly requires HTTPS scheme, host `old.shamela.ws`, path `/epubs/.../{bookId}.epub`
  /// with matching numeric ID, and no query parameters or traversal segments.
  /// Throws [ShamelaEpubUnavailableException] if absent or invalid.
  static String discoverEpubUrl(String html, int bookId) {
    if (html.isEmpty || bookId <= 0) {
      throw ShamelaEpubUnavailableException('Invalid book ID or empty HTML');
    }

    final doc = html_parser.parse(html);
    final anchors = doc.querySelectorAll('a[href]');

    for (final anchor in anchors) {
      final href = anchor.attributes['href']?.trim() ?? '';
      if (href.isEmpty) continue;

      final uri = Uri.tryParse(href);
      if (uri == null) continue;

      final resolved = uri.hasScheme
          ? uri
          : Uri.parse('https://old.shamela.ws').resolveUri(uri);

      if (resolved.scheme.toLowerCase() != 'https') continue;
      if (resolved.host.toLowerCase() != 'old.shamela.ws') continue;
      if (resolved.hasQuery && resolved.query.isNotEmpty) continue;
      if (resolved.hasFragment && resolved.fragment.isNotEmpty) continue;

      final segments = resolved.pathSegments;
      if (segments.length < 2) continue;
      if (segments.first != 'epubs') continue;
      if (segments.last != '$bookId.epub') continue;

      // Ensure no path traversal
      if (segments.any((s) => s == '.' || s == '..' || s.contains('\\'))) {
        continue;
      }

      return resolved.toString();
    }

    throw ShamelaEpubUnavailableException(
      'No valid EPUB download link found for book $bookId on old.shamela.ws',
    );
  }

  /// Convenience wrapper returning parsed [Uri].
  static Uri discoverEpubUri(String html, int bookId) =>
      Uri.parse(discoverEpubUrl(html, bookId));

  // URL references encode file names; archive entry names remain decoded.
  static String _decodeReferencePath(String reference) =>
      _decodePath(reference.split('#').first);

  static String _decodePath(String path) {
    try {
      return Uri.decodeComponent(path);
    } on ArgumentError {
      throw const ShamelaEpubValidationException(
          'Invalid percent-encoded EPUB path');
    } on FormatException {
      throw const ShamelaEpubValidationException(
          'Invalid percent-encoded EPUB path');
    }
  }

  // ==============================================================================
  // EPUB Parser (Pure Static Method)
  // ==============================================================================

  /// Pure in-memory method to preflight and parse EPUB bytes against an expected [ShamelaBook].
  ///
  /// Verifies ZIP Central Directory, parses container.xml and OPF safely without network,
  /// conservatively validates dc:title against expected title, verifies spine and manifest,
  /// parses TOC hierarchy, and extracts accessible body text.
  static OfflineShamelaBook parseEpub(
    Uint8List bytes,
    ShamelaBook expected, {
    String? sourceUrl,
  }) {
    // 1. Preflight ZIP Central Directory
    _ZipPreflight.preflight(bytes);

    // 2. Decode into memory
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final archiveMap = <String, ArchiveFile>{};
    for (final file in archive.files) {
      archiveMap[p.posix.normalize(file.name)] = file;
    }

    // 3. Locate and parse META-INF/container.xml safely
    const containerPath = 'META-INF/container.xml';
    final containerFile = archiveMap[containerPath];
    if (containerFile == null) {
      throw const ShamelaEpubValidationException(
          'Missing META-INF/container.xml in EPUB');
    }

    final containerXmlStr = utf8.decode(
      containerFile.content as List<int>,
      allowMalformed: true,
    );
    final containerDoc = _XmlSafety.parseSafeXml(containerXmlStr);

    final rootfileElem = containerDoc.findAllElements('rootfile').firstOrNull;
    if (rootfileElem == null) {
      throw const ShamelaEpubValidationException(
          'No rootfile found in container.xml');
    }

    final rawOpfPath = rootfileElem.getAttribute('full-path')?.trim() ?? '';
    if (rawOpfPath.isEmpty ||
        rawOpfPath.startsWith('/') ||
        rawOpfPath.contains('\\') ||
        rawOpfPath.contains('://')) {
      throw ShamelaEpubSecurityException('Invalid rootfile path: $rawOpfPath');
    }

    var opfPath = p.posix.normalize(rawOpfPath);
    if (opfPath.startsWith('..')) {
      throw ShamelaEpubSecurityException('Rootfile path traversal: $opfPath');
    }

    // Preserve existing raw-entry selection before resolving an encoded path.
    if (!archiveMap.containsKey(opfPath)) {
      final decodedOpfPath = _decodePath(rawOpfPath);
      if (decodedOpfPath.startsWith('/') ||
          decodedOpfPath.contains('\\') ||
          decodedOpfPath.contains('://')) {
        throw ShamelaEpubSecurityException(
            'Invalid rootfile path: $decodedOpfPath');
      }
      opfPath = p.posix.normalize(decodedOpfPath);
      if (opfPath.startsWith('..')) {
        throw ShamelaEpubSecurityException('Rootfile path traversal: $opfPath');
      }
    }

    final opfFile = archiveMap[opfPath];
    if (opfFile == null) {
      throw ShamelaEpubValidationException(
          'Rootfile $opfPath not found in archive');
    }

    // 4. Parse OPF XML safely
    final opfXmlStr =
        utf8.decode(opfFile.content as List<int>, allowMalformed: true);
    final opfDoc = _XmlSafety.parseSafeXml(opfXmlStr);
    final opfDir = p.posix.dirname(opfPath);

    // 5. Extract metadata and conservatively validate title
    final titleElem = opfDoc.findAllElements('dc:title').firstOrNull ??
        opfDoc.findAllElements('title').firstOrNull;
    final epubTitle = titleElem?.innerText.trim() ?? '';

    final creatorElem = opfDoc.findAllElements('dc:creator').firstOrNull ??
        opfDoc.findAllElements('creator').firstOrNull;
    final epubAuthor = creatorElem?.innerText.trim() ?? expected.author;

    final langElem = opfDoc.findAllElements('dc:language').firstOrNull ??
        opfDoc.findAllElements('language').firstOrNull;
    final idElem = opfDoc.findAllElements('dc:identifier').firstOrNull ??
        opfDoc.findAllElements('identifier').firstOrNull;
    final pubElem = opfDoc.findAllElements('dc:publisher').firstOrNull ??
        opfDoc.findAllElements('publisher').firstOrNull;

    if (!_ArabicComparer.validateTitlesConservatively(
        expected.title, epubTitle)) {
      throw ShamelaEpubValidationException(
        'Title mismatch: requested "${expected.title}", but EPUB dc:title is "$epubTitle"',
      );
    }

    final bookMetadata = <String, dynamic>{
      'dc:title': epubTitle,
      'dc:creator': epubAuthor,
      if (langElem != null) 'dc:language': langElem.innerText.trim(),
      if (idElem != null) 'dc:identifier': idElem.innerText.trim(),
      if (pubElem != null) 'dc:publisher': pubElem.innerText.trim(),
    };

    // 6. Parse manifest items
    final manifest = <String, ({String path, String mediaType})>{};
    for (final item in opfDoc.findAllElements('item')) {
      final id = item.getAttribute('id')?.trim();
      final href = item.getAttribute('href')?.trim();
      final mediaType = item.getAttribute('media-type')?.trim() ?? '';

      if (id == null || href == null || href.isEmpty) continue;
      if (href.contains('://') ||
          href.startsWith('data:') ||
          href.contains('\\')) {
        throw ShamelaEpubSecurityException(
            'Illegal external href in manifest item: $href');
      }

      final cleanHref = _decodeReferencePath(href);
      if (cleanHref.startsWith('/') ||
          cleanHref.contains('://') ||
          cleanHref.startsWith('data:') ||
          cleanHref.contains('\\')) {
        throw ShamelaEpubSecurityException(
            'Illegal archive href in manifest item: $href');
      }
      final resolvedPath = p.posix.normalize(
        opfDir == '.' ? cleanHref : p.posix.join(opfDir, cleanHref),
      );

      if (resolvedPath.startsWith('..') || resolvedPath.startsWith('/')) {
        throw ShamelaEpubSecurityException(
            'Path traversal in manifest href: $href');
      }

      manifest[id] = (path: resolvedPath, mediaType: mediaType);
    }

    // 7. Parse spine and verify every referenced text entry exists
    final spineElem = opfDoc.findAllElements('spine').firstOrNull;
    if (spineElem == null) {
      throw const ShamelaEpubValidationException('Missing spine in OPF');
    }

    final spineItemIds = <String>[];
    final spinePaths = <String>[];

    for (final itemref in spineElem.findElements('itemref')) {
      final idref = itemref.getAttribute('idref')?.trim();
      if (idref == null || !manifest.containsKey(idref)) {
        throw ShamelaEpubValidationException(
            'Spine itemref $idref not declared in manifest');
      }

      final itemEntry = manifest[idref]!;
      if (!archiveMap.containsKey(itemEntry.path)) {
        throw ShamelaEpubValidationException(
          'Referenced spine text entry does not exist in archive: ${itemEntry.path}',
        );
      }

      spineItemIds.add(idref);
      spinePaths.add(itemEntry.path);
    }

    // 8. Parse TOC (NCX or Nav XHTML)
    final tocEntries = <ShamelaTocEntry>[];
    final tocId = spineElem.getAttribute('toc')?.trim();

    String? ncxPath;
    if (tocId != null && manifest.containsKey(tocId)) {
      ncxPath = manifest[tocId]!.path;
    } else {
      // Look for dtbncx item
      for (final entry in manifest.values) {
        if (entry.mediaType == 'application/x-dtbncx+xml') {
          ncxPath = entry.path;
          break;
        }
      }
    }

    if (ncxPath != null && archiveMap.containsKey(ncxPath)) {
      final ncxFile = archiveMap[ncxPath]!;
      final ncxXmlStr =
          utf8.decode(ncxFile.content as List<int>, allowMalformed: true);
      final ncxDoc = _XmlSafety.parseSafeXml(ncxXmlStr);
      final ncxDir = p.posix.dirname(ncxPath);

      final navMap = ncxDoc.findAllElements('navMap').firstOrNull;
      if (navMap != null) {
        List<ShamelaTocEntry> parseNavPoints(
            Iterable<XmlElement> points, int depth) {
          final entries = <ShamelaTocEntry>[];
          for (final np in points) {
            final labelText = np
                    .findElements('navLabel')
                    .firstOrNull
                    ?.findElements('text')
                    .firstOrNull
                    ?.innerText
                    .trim() ??
                '';
            final contentSrc = np
                    .findElements('content')
                    .firstOrNull
                    ?.getAttribute('src')
                    ?.trim() ??
                '';
            String cleanSrc;
            try {
              cleanSrc = _decodeReferencePath(contentSrc);
            } on ShamelaEpubValidationException {
              // Optional malformed navigation must not discard readable pages.
              cleanSrc = contentSrc.split('#').first;
            }
            final resolvedSrc = p.posix.normalize(
              ncxDir == '.' ? cleanSrc : p.posix.join(ncxDir, cleanSrc),
            );

            // Match against spine entries to compute stable spineIndex
            int spineIdx = spinePaths.indexOf(resolvedSrc);
            if (spineIdx == -1) {
              // Try basename match
              final base = p.posix.basename(resolvedSrc);
              spineIdx = spinePaths
                  .indexWhere((p) => p.endsWith('/$base') || p == base);
            }

            final childPoints = np.findElements('navPoint');
            final children = parseNavPoints(childPoints, depth + 1);

            entries.add(
              ShamelaTocEntry(
                label: labelText,
                contentSrc: contentSrc,
                depth: depth,
                spineIndex: spineIdx,
                children: children,
              ),
            );
          }
          return entries;
        }

        tocEntries.addAll(parseNavPoints(navMap.findElements('navPoint'), 0));
      }
    }

    // 9. Extract body text for each spine item, preserving order
    final pages = <OfflineShamelaPage>[];
    for (int i = 0; i < spineItemIds.length; i++) {
      final idref = spineItemIds[i];
      final pagePath = spinePaths[i];
      final pageFile = archiveMap[pagePath]!;
      final htmlStr =
          utf8.decode(pageFile.content as List<int>, allowMalformed: true);

      final extracted = _HtmlExtractor.extractPage(htmlStr);
      pages.add(
        OfflineShamelaPage(
          id: idref,
          path: pagePath,
          title: extracted.title ?? '${expected.title} - ${i + 1}',
          text: extracted.text,
          volume: extracted.volume,
          pageNumber: extracted.pageNumber,
        ),
      );
    }

    return OfflineShamelaBook(
      id: expected.id,
      title: epubTitle.isNotEmpty ? epubTitle : expected.title,
      author: epubAuthor.isNotEmpty ? epubAuthor : expected.author,
      sourceUrl: sourceUrl ?? expected.downloadUrl,
      downloadedAt: DateTime.now(),
      metadata: bookMetadata,
      pages: pages,
      toc: tocEntries,
    );
  }

  // ==============================================================================
  // Download with Streamed Cap, Redirect Whitelisting, and Atomic Save
  // ==============================================================================

  void _validateAllowlistedUri(Uri uri) {
    if (uri.scheme.toLowerCase() != 'https') {
      throw ShamelaEpubSecurityException(
          'Disallowed non-HTTPS protocol: ${uri.scheme}');
    }
    final host = uri.host.toLowerCase();
    if (!_allowlistedHosts.contains(host)) {
      throw ShamelaEpubSecurityException(
          'Disallowed host for EPUB download: $host');
    }
  }

  /// Downloads and parses a [ShamelaBook] into structured offline format.
  ///
  /// Enforces streamed 32 MiB size cap, allowlisted HTTPS redirects, preflight verification,
  /// and atomic structured JSON caching. Preserves existing good copy if download fails or is cancelled.
  Future<OfflineShamelaBook> downloadBook(
    ShamelaBook book, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    // 1. Grounded discovery: ALWAYS query legacy book metadata page to discover actual EPUB anchor
    Uri metaUri = Uri.parse('https://old.shamela.ws/index.php/book/${book.id}');
    _validateAllowlistedUri(metaUri);

    Response<String> metaResp;
    int metaRedirects = 0;

    while (true) {
      metaResp = await _dio.get<String>(
        metaUri.toString(),
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: false,
          validateStatus: (s) => s != null && s < 400,
        ),
        cancelToken: cancelToken,
      );

      if (metaResp.statusCode != null &&
          metaResp.statusCode! >= 300 &&
          metaResp.statusCode! < 400) {
        metaRedirects++;
        if (metaRedirects > 5) {
          throw const ShamelaEpubSecurityException(
            'Exceeded maximum allowed redirects for metadata (5)',
          );
        }
        final loc = metaResp.headers.value('location');
        if (loc == null || loc.trim().isEmpty) {
          throw const ShamelaEpubException(
              'Redirect response missing location header');
        }
        final nextUri = metaUri.resolve(loc.trim());
        _validateAllowlistedUri(nextUri);
        metaUri = nextUri;
        continue;
      }
      break;
    }

    final htmlBody = metaResp.data ?? '';
    final targetUrl = discoverEpubUrl(htmlBody, book.id);

    Uri currentUri = Uri.parse(targetUrl);
    _validateAllowlistedUri(currentUri);

    // 2. Streamed download with redirect verification and 32 MiB cap
    Response<ResponseBody> response;
    int redirects = 0;

    while (true) {
      response = await _dio.get<ResponseBody>(
        currentUri.toString(),
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: false,
          validateStatus: (s) => s != null && s < 400,
        ),
        cancelToken: cancelToken,
      );

      if (response.statusCode != null &&
          response.statusCode! >= 300 &&
          response.statusCode! < 400) {
        redirects++;
        if (redirects > 5) {
          throw const ShamelaEpubSecurityException(
              'Exceeded maximum allowed redirects (5)');
        }
        final loc = response.headers.value('location');
        if (loc == null || loc.trim().isEmpty) {
          throw const ShamelaEpubException(
              'Redirect response missing location header');
        }
        final nextUri = currentUri.resolve(loc.trim());
        _validateAllowlistedUri(nextUri);
        currentUri = nextUri;
        continue;
      }
      break;
    }

    final rawContentLength =
        response.headers.value(Headers.contentLengthHeader);
    final contentLength = int.tryParse(rawContentLength ?? '-1') ?? -1;
    if (contentLength > _ZipPreflight.maxCompressedBytes) {
      throw ShamelaEpubSecurityException(
        'Content-Length ($contentLength bytes) exceeds 32 MiB limit',
      );
    }

    final builder = BytesBuilder(copy: false);
    int receivedBytes = 0;

    try {
      await for (final chunk in response.data!.stream) {
        if (cancelToken?.isCancelled ?? false) {
          throw DioException.requestCancelled(
            requestOptions: response.requestOptions,
            reason: 'User cancelled download',
          );
        }
        receivedBytes += chunk.length;
        if (receivedBytes > _ZipPreflight.maxCompressedBytes) {
          cancelToken?.cancel('Compressed cap 32 MiB exceeded');
          throw ShamelaEpubSecurityException(
            'Stream exceeded 32 MiB compressed limit ($receivedBytes bytes)',
          );
        }
        builder.add(chunk);
        onProgress?.call(receivedBytes, contentLength > 0 ? contentLength : -1);
      }
    } on DioException {
      rethrow;
    }

    final downloadedBytes = builder.takeBytes();

    // 3. Parse in memory (preflight + validation + text extraction)
    final offlineBook = parseEpub(
      downloadedBytes,
      book,
      sourceUrl: currentUri.toString(),
    );

    // 4. Atomic cache to disk
    await _atomicSaveBook(
      bookId: book.id,
      book: offlineBook,
      rawBytes: downloadedBytes,
    );

    return offlineBook;
  }

  Future<void> _atomicSaveBook({
    required int bookId,
    required OfflineShamelaBook book,
    required Uint8List rawBytes,
  }) async {
    final shamelaDir = await _getShamelaDir();
    final bookDir = Directory(p.join(shamelaDir.path, bookId.toString()));
    if (!await bookDir.exists()) {
      await bookDir.create(recursive: true);
    }

    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final jsonFinal = File(p.join(bookDir.path, 'book.json'));
    final jsonTmp = File(p.join(bookDir.path, 'book.json.tmp.$timestamp'));

    final epubFinal = File(p.join(bookDir.path, 'book.epub'));
    final epubTmp = File(p.join(bookDir.path, 'book.epub.tmp.$timestamp'));

    try {
      final jsonString = jsonEncode(book.toJson());
      await jsonTmp.writeAsString(jsonString, flush: true);
      await epubTmp.writeAsBytes(rawBytes, flush: true);

      await jsonTmp.rename(jsonFinal.path);
      await epubTmp.rename(epubFinal.path);
    } catch (e) {
      if (await jsonTmp.exists()) {
        try {
          await jsonTmp.delete();
        } catch (_) {}
      }
      if (await epubTmp.exists()) {
        try {
          await epubTmp.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  // ==============================================================================
  // Offline Book Storage Management & Reader Position Persistence
  // ==============================================================================

  /// Loads a saved offline book from application support directory.
  Future<OfflineShamelaBook?> loadSavedBook(int bookId) async {
    final shamelaDir = await _getShamelaDir();
    final jsonFile =
        File(p.join(shamelaDir.path, bookId.toString(), 'book.json'));
    if (!await jsonFile.exists()) return null;

    try {
      final jsonStr = await jsonFile.readAsString();
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      return OfflineShamelaBook.fromJson(data);
    } catch (e) {
      return null;
    }
  }

  /// Lists all successfully saved offline books.
  Future<List<OfflineShamelaBook>> listSavedBooks() async {
    final shamelaDir = await _getShamelaDir();
    if (!await shamelaDir.exists()) return const [];

    final books = <OfflineShamelaBook>[];
    await for (final entity in shamelaDir.list(followLinks: false)) {
      if (entity is Directory) {
        final jsonFile = File(p.join(entity.path, 'book.json'));
        if (await jsonFile.exists()) {
          try {
            final jsonStr = await jsonFile.readAsString();
            final data = jsonDecode(jsonStr) as Map<String, dynamic>;
            books.add(OfflineShamelaBook.fromJson(data));
          } catch (_) {
            // Skip corrupted or incomplete directories
          }
        }
      }
    }

    books.sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));
    return books;
  }

  /// Deletes a saved offline book by ID. Returns true if removed.
  Future<bool> deleteSavedBook(int bookId) async {
    final shamelaDir = await _getShamelaDir();
    final bookDir = Directory(p.join(shamelaDir.path, bookId.toString()));
    if (!await bookDir.exists()) return false;

    try {
      await bookDir.delete(recursive: true);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Checks whether a book is already downloaded and saved offline.
  Future<bool> isBookSaved(int bookId) async {
    final shamelaDir = await _getShamelaDir();
    final jsonFile =
        File(p.join(shamelaDir.path, bookId.toString(), 'book.json'));
    return await jsonFile.exists();
  }

  /// Requests position storage and requires the provider's acknowledgement.
  /// Acknowledgement does not guarantee physical storage durability.
  Future<void> saveLastPosition(int bookId, int spineIndex) async {
    final prefs = await SharedPreferences.getInstance();
    final confirmed = await prefs.setInt('$_prefPrefix$bookId', spineIndex);
    if (!confirmed) {
      throw StateError('Reader position write was not confirmed');
    }
  }

  /// Retrieves the reader's last read stable spine index, or null if unset.
  Future<int?> getLastPosition(int bookId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_prefPrefix$bookId');
  }
}
