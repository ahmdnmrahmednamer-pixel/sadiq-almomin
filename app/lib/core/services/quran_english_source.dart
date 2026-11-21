import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

class QuranEnglishVerse {
  final String text, footnotes;
  const QuranEnglishVerse(this.text, this.footnotes);
}

/// Verbatim Rowwad translation and footnotes from QuranEnc's published SQLite.
/// All 6236 rows are bundled. This service has no network client or fallback.
class QuranEnglishSource {
  static const editionKey = 'english_rwwad';
  static const editionName = 'Rowwad Translation Center';
  static const version = '1.0.21';
  static const sourceUrl = 'https://quranenc.com/en/home';
  final Future<String> Function(String) readAsset;
  Future<Map<String, QuranEnglishVerse>>? _loading;
  QuranEnglishSource({Future<String> Function(String)? readAsset})
      : readAsset = readAsset ?? rootBundle.loadString;

  Future<Map<String, QuranEnglishVerse>> _load() async {
    final meta = jsonDecode(await readAsset('assets/data/english_rwwad_manifest.json'));
    if(meta['key']!=editionKey || meta['version']!=version || meta['verseCount']!=6236) {
      throw const FormatException('English translation identity mismatch');
    }
    final parts=await Future.wait([for(var i=1;i<=(meta['parts'] as int);i++)readAsset('assets/data/english_rwwad_$i.b64')]);
    final bytes=GZipDecoder().decodeBytes(base64Decode(parts.map((p)=>p.trim()).join()));
    if(sha256.convert(bytes).toString()!=meta['payloadSha256'])throw const FormatException('English translation checksum mismatch');
    final data=jsonDecode(utf8.decode(bytes));
    if(data['key']!=editionKey || data['version']!=version)throw const FormatException('English translation payload mismatch');
    final result=<String,QuranEnglishVerse>{};
    for(final row in data['rows']){
      final key='${row['sura']}:${row['aya']}';
      if(result.containsKey(key) || row['translation'] is! String || (row['translation'] as String).trim().isEmpty)throw const FormatException('Invalid English verse');
      result[key]=QuranEnglishVerse(row['translation'] as String,row['footnotes'] as String? ?? '');
    }
    if(result.length!=6236)throw const FormatException('Incomplete English translation');
    return result;
  }
  Future<QuranEnglishVerse?> fetch(int surah,int ayah)async {
    try{return (await (_loading??=_load()))['$surah:$ayah'];}
    catch(_){_loading=null;rethrow;}
  }
}
