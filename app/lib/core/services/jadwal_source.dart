import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html;

class JadwalPage {
  final int id, part, page;
  final String text;
  final int focusOffset;
  const JadwalPage(this.id, this.part, this.page, this.text, this.focusOffset);
}

class JadwalEntry {
  final int ayahFrom, ayahTo;
  final List<JadwalPage> pages;
  final String notice;
  const JadwalEntry(this.ayahFrom, this.ayahTo, this.pages, this.notice);
}

/// Navigation metadata only ships with the app. Source text is fetched on demand
/// from the provider's published contents URL and kept in session memory only.
class JadwalSource {
  static const sourceUrl = 'https://api.quranpedia.net/books-contents/book-1772.json';
  static const bookUrl = 'https://quranpedia.net/book/1772';
  final Dio dio;
  final Future<Map<String, dynamic>> Function() loadIndex;
  Future<Map<String, dynamic>>? _loadingContent;
  JadwalSource({Dio? dio, Future<Map<String, dynamic>> Function()? loadIndex})
      : dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 45))),
        loadIndex = loadIndex ?? _assetIndex;
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
      content = await (_loadingContent ??= _fetchContent());
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
      pages.add(JadwalPage(id as int, check['part'] as int, check['page'] as int, String.fromCharCodes(runes), from));
    }
    final notices = <String>['نص صفحات المصدر مع سياقها وهوامشها. الإعراب لمحمود صافي؛ البلاغة والفوائد وفق نسبة بطاقة الكتاب.'];
    if (record['ayahFrom'] != record['ayahTo']) notices.add('المقطع مشترك للآيات ${record['ayahFrom']} إلى ${record['ayahTo']}.');
    if (record['incomplete'] == true) notices.add('النص غير كامل: ص٢٥٠ من ج٢٢ ناقصة في التفريغ، والمتاح هنا من ص٢٥١ فقط.');
    if (record['providerOmittedHeading'] == true) notices.add('عنوان غافر ١٠ ونصها في تفريغ ص٢٢٥ لا يطابقان المصوّر. رُبط الإعراب والصرف من ص٢٢٦ بعد مراجعة المصوّر؛ لم يُعَد إنشاء النص الناقص.');
    return JadwalEntry(record['ayahFrom'] as int, record['ayahTo'] as int, pages, notices.join('\n'));
  }
}
