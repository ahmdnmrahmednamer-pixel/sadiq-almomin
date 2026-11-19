import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html;

class LubabEntry {
  final String text;
  final List<int> pages;
  const LubabEntry(this.text,this.pages);
}

/// The index navigates to an explicit source heading. It does not classify the
/// narration, authenticate its chain or claim its whole span is one ayah's cause.
class LubabSource {
  static const sourceUrl='https://api.quranpedia.net/books-contents/book-69.json';
  final Dio dio;
  final Future<Map<String,dynamic>> Function() loadIndex;
  Map<String,dynamic>? _content;
  LubabSource({Dio? dio,Future<Map<String,dynamic>> Function()? loadIndex})
    :dio=dio??Dio(BaseOptions(connectTimeout:const Duration(seconds:15),receiveTimeout:const Duration(seconds:30))),
     loadIndex=loadIndex??_assetIndex;
  static Future<Map<String,dynamic>> _assetIndex()async=>jsonDecode(await rootBundle.loadString('assets/data/lubab_verse_index.json')) as Map<String,dynamic>;
  static String plain(String value)=>html.parseFragment(value
    .replaceAll(RegExp(r'<br\s*/?>|</?p(?:\s[^>]*)?>',caseSensitive:false),'\n')).text!.replaceAll('\r','\n');
  Future<List<LubabEntry>> fetch(int surah,int ayah)async{
    final index=await loadIndex();
    if(index['bookId']!=69 || index['provider']!='quranpedia.net' || index['linkType']!='explicit_heading_quote')throw const FormatException('Index identity mismatch');
    final records=(index['records'] as List).where((r)=>r['surah']==surah&&r['ayah']==ayah).toList();
    if(records.isEmpty)return const [];
    if(_content==null){
      final meta=(await dio.get('https://api.quranpedia.net/v1/book/69')).data;
      if(meta is! Map||meta['id']!=69||meta['type']!='asbab'||meta['author'] is! Map||meta['author']['id']!=14264)throw const FormatException('Book identity mismatch');
      final response=(await dio.get(sourceUrl)).data;
      if(response is! Map<String,dynamic>||response['contents'] is! List)throw const FormatException('Invalid book content');
      _content=response;
    }
    final contents={for(final c in _content!['contents'] as List)c['id']:c};
    final checks={for(final c in index['pages'] as List)c['id']:c};
    final entries=<LubabEntry>[];
    for(final record in records){
      final spans=<String>[];final pages=<int>[];
      for(final segment in record['segments'] as List){
        final id=segment['id'];final c=contents[id];final expected=checks[id];
        if(c==null||expected==null||c['text'] is! String||sha256.convert(utf8.encode(c['text'] as String)).toString()!=expected['sha256'])throw const FormatException('Source changed; index needs update');
        final runes=plain(c['text'] as String).runes.toList();final from=segment['from'] as int;final to=segment['to'] as int;
        if(from<0||to>runes.length||from>=to)throw const FormatException('Source span invalid');
        spans.add(String.fromCharCodes(runes.sublist(from,to)));pages.add(expected['page'] as int);
      }
      final text=spans.join('\n').trim();
      if(!text.startsWith('قوله'))throw const FormatException('Source entry boundary mismatch');
      entries.add(LubabEntry(text,pages.toSet().toList()));
    }
    return entries;
  }
}
