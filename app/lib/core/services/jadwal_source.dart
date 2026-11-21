import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'bundled_original_book.dart';
import 'installed_original_books.dart';
import 'package:html/parser.dart' as html;

class JadwalPage {
  final int id, part, page;
  final String text;
  final int focusOffset;
  final String? label;
  const JadwalPage(this.id, this.part, this.page, this.text, this.focusOffset, [this.label]);
}

class JadwalEntry {
  final int ayahFrom, ayahTo;
  final List<JadwalPage> pages;
  final String notice;
  const JadwalEntry(this.ayahFrom, this.ayahTo, this.pages, this.notice);
}

/// Reads the exact reviewed installation book and its navigation index.
/// The explicit nonbundled mode is retained for transport and cache tests.
class JadwalSource {
  static const sourceUrl = 'https://api.quranpedia.net/books-contents/book-1772.json';
  static const bookUrl = 'https://quranpedia.net/book/1772';
  final Dio dio;
  final BundledOriginalBook? bundledOriginal;
  bool get isBundled => bundledOriginal != null;
  final Future<Directory> Function() storageDirectory;
  Future<Map<String,dynamic>?>? _cachedRead;
  DateTime? downloadedAt;
  final Future<Map<String, dynamic>> Function() loadIndex;
  Future<Map<String, dynamic>>? _loadingContent;
  JadwalSource({Dio? dio, BundledOriginalBook? bundledOriginal, bool useBundled = true, Future<Map<String, dynamic>> Function()? loadIndex, Future<Directory> Function()? storageDirectory})
      : bundledOriginal = bundledOriginal ?? (useBundled ? InstalledOriginalBooks.jadwal() : null),
        dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 45))),
        loadIndex = loadIndex ?? _assetIndex,
        storageDirectory = storageDirectory ?? getApplicationSupportDirectory;
  static Future<Map<String, dynamic>> _assetIndex() async {
    final chunks = await Future.wait([for(var n=1;n<=2;n++) rootBundle.loadString('assets/data/jadwal_index_$n.b64')]);
    return jsonDecode(utf8.decode(GZipDecoder().decodeBytes(base64Decode(chunks.map((c)=>c.trim()).join())))) as Map<String,dynamic>;
  }

  // DOM parsing malformed table markup can reorder source paragraphs. Remove
  // markup in source order, then decode entities without reinterpreting tags.
  static String plain(String value) {
    final text = value.replaceAll(RegExp(r'<br\s*/?>|</?p(?:\s[^>]*)?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
    return html.parseFragment(text).text!.replaceAll('\r', '\n');
  }

  Future<File> _cacheFile() async => File('${(await storageDirectory()).path}/jadwal/book-1772-v1.json');
  Future<Map<String,dynamic>?> _readCached() async {
    try {
      final file=await _cacheFile();
      if(!await file.exists())return null;
      final envelope=jsonDecode(await file.readAsString());
      if(envelope is! Map || envelope['bookId']!=1772 || envelope['source']!=sourceUrl || envelope['content'] is! Map<String,dynamic>) throw const FormatException('Invalid private Jadwal copy');
      final content=envelope['content'] as Map<String,dynamic>;
      await _validateAll(content);
      downloadedAt=DateTime.parse(envelope['savedAt'] as String);
      return content;
    } on FileSystemException {return null;}
  }
  Future<void> _validateAll(Map<String,dynamic> content) async {
    if(content['contents'] is! List) throw const FormatException('Invalid Jadwal copy');
    final rows={for(final c in content['contents'] as List)c['id']:c};
    final index=await loadIndex();
    for(final check in index['pages'] as List){
      final raw=rows[check['id']]?['text'];
      if(raw is! String || sha256.convert(utf8.encode(raw)).toString()!=check['sha256']) throw const FormatException('Jadwal copy differs from reviewed index');
    }
  }
  Future<DateTime?> offlineSavedAt() async {
    if(isBundled) return null;
    await (_cachedRead??=_readCached());
    return downloadedAt;
  }
  Future<void> downloadForOffline({bool refresh=false}) async {
    if(isBundled) throw StateError('Installed book does not use optional downloads');
    final content=refresh?await _fetchContent():await (_loadingContent??=_loadContent());
    await _validateAll(content);
    final savedAt=DateTime.now().toUtc();
    final file=await _cacheFile();await file.parent.create(recursive:true);
    final temp=File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode({'bookId':1772,'source':sourceUrl,'savedAt':savedAt.toIso8601String(),'content':content}),flush:true);
    await temp.rename(file.path);
    downloadedAt=savedAt;_cachedRead=Future.value(content);_loadingContent=Future.value(content);
  }
  Future<void> deleteOffline() async {
    if(isBundled) throw StateError('Installed book is part of the application');
    final file=await _cacheFile();if(await file.exists())await file.delete();
    downloadedAt=null;_cachedRead=null;
    // A delete also clears session content, so the next read reflects the
    // currently available source instead of silently retaining a deleted copy.
    _loadingContent=null;
  }
  Future<Map<String,dynamic>> _loadContent() async {
    if(bundledOriginal != null) {
      final content=jsonDecode(await bundledOriginal!.load());
      if(content is! Map<String,dynamic>) throw const FormatException('Invalid bundled Jadwal');
      await _validateAll(content);
      return content;
    }
    return await (_cachedRead??=_readCached()) ?? await _fetchContent();
  }

  Future<Map<String, dynamic>> _fetchContent() async {
    final meta = (await dio.get('https://api.quranpedia.net/v1/book/1772')).data;
    if (meta is! Map || meta['id'] != 1772 || meta['author'] is! Map || meta['author']['id'] != 1346 || meta['contents_url'] != sourceUrl) {
      throw const FormatException('Jadwal source identity changed');
    }
    final content = (await dio.get(sourceUrl)).data;
    if (content is! Map<String, dynamic> || content['contents'] is! List) throw const FormatException('Invalid Jadwal content');
    return content;
  }

  Future<JadwalEntry?> fetch(int surah, int ayah) async {
    final index = await loadIndex();
    if (index['bookId'] != 1772 || index['authorId'] != 1346 || index['provider'] != 'quranpedia.net') throw const FormatException('Jadwal index identity mismatch');
    final records = (index['records'] as List).where((r) => r['surah'] == surah && r['ayahFrom'] <= ayah && r['ayahTo'] >= ayah).toList();
    if (records.isEmpty) return null;
    if (records.length != 1) throw const FormatException('Ambiguous Jadwal location');
    final record = records.single;
    Map<String, dynamic> content;
    try {
      content = await (_loadingContent ??= _loadContent());
    } catch (_) {
      _loadingContent = null;
      rethrow;
    }
    final byId = {for (final c in content['contents'] as List) c['id']: c};
    final checks = {for (final c in index['pages'] as List) c['id']: c};
    final pages = <JadwalPage>[];
    for (final segment in record['segments'] as List) {
      final id = segment['id'];
      if (pages.any((p) => p.id == id)) continue;
      final raw = byId[id]?['text'];
      final check = checks[id];
      if (raw is! String || check == null || sha256.convert(utf8.encode(raw)).toString() != check['sha256']) throw const FormatException('Jadwal source changed; index needs review');
      var runes = plain(raw).runes.toList();
      final from = segment['from'] as int;
      final to = segment['to'] as int;
      if (from < 0 || to > runes.length || from >= to) throw const FormatException('Invalid Jadwal location');
      // Keep whole-page footnotes. The sole reviewed substituted Quran passage
      // is withheld with an explicit marker, never silently corrected.
      if (id == 2195850) {
        final exclusions = (index['quarantine'] as List).where((q) => q['id'] == id && q['reason'] == 'foreign_heading_and_body').toList();
        if (exclusions.length != 1) throw const FormatException('Missing reviewed Jadwal exclusion');
        final cut = exclusions.single['from'] as int;
        if (cut < to || cut > runes.length) throw const FormatException('Invalid Jadwal exclusion');
        runes = [...runes.take(cut), ...'\n[حُجب هنا مقطع قرآني لا يطابق المصوّر. أصل غافر ١٠ في ج٢٤ ص٢٢٥، وإعرابها ص٢٢٦.]'.runes];
      }
      pages.add(JadwalPage(id as int, check['part'] as int, check['page'] as int, String.fromCharCodes(runes), from, check['label'] as String?));
    }
    final notices = <String>['نص صفحات المصدر مع سياقها وهوامشها. الإعراب لمحمود صافي؛ البلاغة والفوائد وفق نسبة بطاقة الكتاب.'];
    if (record['ayahFrom'] != record['ayahTo']) notices.add('المقطع مشترك للآيات ${record['ayahFrom']} إلى ${record['ayahTo']}.');
    if (record['supplementNotice'] is String) notices.add(record['supplementNotice'] as String);
    if (record['incomplete'] == true) notices.add('الصفحة غير متوفرة: ص٢٥٠ من ج٢٢ ناقصة في التفريغ، والمتاح هنا من ص٢٥١ فقط.');
    if (record['providerOmittedHeading'] == true) notices.add('عنوان غافر ١٠ ونصها في تفريغ ص٢٢٥ لا يطابقان المصوّر. رُبط الإعراب والصرف من ص٢٢٦ بعد مراجعة المصوّر؛ لم يُعَد إنشاء النص الناقص.');
    return JadwalEntry(record['ayahFrom'] as int, record['ayahTo'] as int, pages, notices.join('\n'));
  }
}
