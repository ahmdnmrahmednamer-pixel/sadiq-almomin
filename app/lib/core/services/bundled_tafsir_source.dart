import 'dart:collection';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html;

class BundledTafsirPage {
  final String text, verseIds;
  final String part;
  final String previousContextTitle;
  final String? sourceUrl,sourceLabel;
  final int? page;
  final int focusOffset;
  final int? sourceId;
  const BundledTafsirPage(this.text,this.part,this.page,this.verseIds,{this.focusOffset=0,this.sourceUrl,this.sourceLabel,this.previousContextTitle='سياق الصفحة السابق',this.sourceId});
}
class BundledTafsirBookSection {
  final String id, title;
  final List<BundledTafsirPage> pages;
  const BundledTafsirBookSection(this.id,this.title,this.pages);
}
class BundledTafsirEntry {
  final int bookId;
  final List<BundledTafsirPage> pages;
  final Map<String,dynamic> book;
  final String? sourceUrl;
  final String? sourceWarning;
  final bool hasBookSections;
  const BundledTafsirEntry(this.bookId,this.pages,{this.book=const {},this.sourceUrl,this.sourceWarning,this.hasBookSections=false});
  String get editionDetails=>[
    book['nasher'],book['edition'],book['publish_year'],
    if(book['mohaqeq']!=null)'تحقيق: ${book['mohaqeq']}',
  ].where((v)=>v!=null&&v.toString().trim().isNotEmpty).join('، ');
}
/// On-device corpora, loaded per surah with a bounded cache. Metadata and page
/// context are retained. A missing row never borrows the nearest verse's text.
class BundledTafsirSource {
  final Future<String> Function(String) readAsset;
  final Map<String,Future<Map<String,dynamic>>> _manifests={};
  final LinkedHashMap<String,Map<String,dynamic>> _chapters=LinkedHashMap();
  final Map<String,Future<Map<String,dynamic>>> _loading={};
  BundledTafsirSource({Future<String> Function(String)? readAsset}):readAsset=readAsset??rootBundle.loadString;
  static String plain(String value){
    final ordered=value.replaceAll(RegExp(r'<br\s*/?>|</?(?:p|h[1-6])(?:\s[^>]*)?>',caseSensitive:false),'\n').replaceAll(RegExp(r'<[^>]*>'),'').replaceAll('<','&lt;').replaceAll('>','&gt;');
    return html.parseFragment(ordered).text!.replaceAll('\r','\n');
  }
  Future<Map<String,dynamic>> _manifest(String edition)=>_manifests.putIfAbsent(edition,()=>_readManifest(edition).catchError((Object error){
    _manifests.remove(edition);
    throw error;
  }));
  Future<Map<String,dynamic>> _readManifest(String edition)async{
    final value=jsonDecode(await readAsset('assets/data/tafsir_${edition}_manifest.json')) as Map<String,dynamic>;
    if(value['edition']!=edition || value['book'] is! Map || value['surahs'] is! Map)throw const FormatException('Tafsir manifest identity mismatch');
    return value;
  }
  Future<List<BundledTafsirBookSection>> bookSections(String edition)async {
    if(!RegExp(r'^[a-z_]+$').hasMatch(edition))throw ArgumentError('Invalid tafsir edition');
    final manifest=await _manifest(edition);final meta=manifest['bookSections'];
    if(meta==null)return const [];
    if(meta is! Map || meta['parts'] is! int || meta['parts']<1 || meta['parts']>100)throw const FormatException('Invalid book sections metadata');
    final parts=await Future.wait([for(var n=1;n<=meta['parts'];n++)readAsset('assets/data/tafsir_${edition}_sections_$n.b64')]);
    final bytes=GZipDecoder().decodeBytes(base64Decode(parts.map((p)=>p.trim()).join()));
    if(sha256.convert(bytes).toString()!=meta['sha256'])throw const FormatException('Book sections checksum mismatch');
    final value=jsonDecode(utf8.decode(bytes));
    if(value is! Map || value['bookId']!=manifest['book']['id'] || value['sections'] is! List)throw const FormatException('Book sections identity mismatch');
    final sections=<BundledTafsirBookSection>[];final ids=<String>{};final pageIds=<int>{};
    for(final raw in value['sections']){
      if(raw is! Map || raw['id'] is! String || !ids.add(raw['id']) || raw['title'] is! String || raw['title'].trim().isEmpty || raw['pages'] is! List || raw['pages'].isEmpty)throw const FormatException('Invalid book section');
      final pages=<BundledTafsirPage>[];
      for(final page in raw['pages']){
        if(page is! Map || page['id'] is! int || !pageIds.add(page['id']) || page['text'] is! String || page['text'].trim().isEmpty)throw const FormatException('Invalid book section page');
        final text=page['textFormat']=='plain'?page['text'] as String:plain(page['text'] as String);
        pages.add(BundledTafsirPage(text,page['part']?.toString()??'',int.tryParse(page['page']?.toString()??''),'',sourceId:page['id'],sourceUrl:page['sourceUrl'] as String?,sourceLabel:page['sourceLabel'] as String?));
      }
      sections.add(BundledTafsirBookSection(raw['id'],raw['title'],List.unmodifiable(pages)));
    }
    return List.unmodifiable(sections);
  }
  Future<Map<String,dynamic>> _load(String edition,int surah)async {
    final meta=await _manifest(edition);final chapter=meta['surahs']['$surah'];
    if(chapter==null)throw const FormatException('Missing tafsir chapter');
    final parts=await Future.wait([for(var n=1;n<=(chapter['parts'] as int);n++)readAsset('assets/data/tafsir_${edition}_${surah}_$n.b64')]);
    final bytes=GZipDecoder().decodeBytes(base64Decode(parts.map((p)=>p.trim()).join()));
    if(sha256.convert(bytes).toString()!=chapter['sha256'])throw const FormatException('Tafsir checksum mismatch');
    final value=jsonDecode(utf8.decode(bytes)) as Map<String,dynamic>;
    if(value['bookId']!=meta['book']['id'] || value['surah']!=surah || value['locations'] is! Map || value['pages'] is! List)throw const FormatException('Tafsir chapter identity mismatch');
    value['_hasBookSections']=meta['bookSections']!=null;value['_locationSources']=meta['locationSources'];value['_sourceWarnings']=meta['sourceWarnings'];value['_book']=meta['book'];value['_source']=meta['source'];
    return value;
  }
  Future<BundledTafsirEntry?> fetch(String edition,int surah,int ayah)async {
    if(!RegExp(r'^[a-z_]+$').hasMatch(edition)||surah<1||surah>114||ayah<1)throw ArgumentError('Invalid tafsir location');
    final key='$edition:$surah';
    var chapter=_chapters.remove(key);
    if(chapter==null){
      try{chapter=await _loading.putIfAbsent(key,()=>_load(edition,surah));}finally{_loading.remove(key);}
    }
    _chapters[key]=chapter;
    while(_chapters.length>3){_chapters.remove(_chapters.keys.first);}
    final ids=chapter['locations']['$ayah'];if(ids==null)return null;
    final pages=<BundledTafsirPage>[];
    for(final location in ids){
      final id=location is Map?location['id']:location;
      final focus=location is Map?location['focus'] as int:0;
      final raw=chapter['pages'][id];
      if(raw['text'] is! String || (raw['text'] as String).trim().isEmpty)throw const FormatException('Empty tafsir source text');
      final text=raw['textFormat']=='plain'?raw['text'] as String:plain(raw['text'] as String);
      if(focus<0||focus>text.runes.length)throw const FormatException('Tafsir focus outside source');
      pages.add(BundledTafsirPage(text,raw['part'].toString(),int.tryParse(raw['page'].toString()),raw['ayahs'].toString(),focusOffset:focus,sourceUrl:raw['sourceUrl']as String?,sourceLabel:raw['sourceLabel']as String?,previousContextTitle:raw['previousContextTitle']as String? ?? 'سياق الصفحة السابق',sourceId:raw['id'] as int?));
    }
    return pages.isEmpty?null:BundledTafsirEntry(chapter['bookId'] as int,pages,book:Map<String,dynamic>.from(chapter['_book']as Map? ?? const {}),sourceUrl:(chapter['_locationSources']as Map?)?['$surah:$ayah']as String? ?? chapter['_source']as String?,sourceWarning:(chapter['_sourceWarnings']as Map?)?['$surah:$ayah']as String?,hasBookSections:chapter['_hasBookSections']==true);
  }
}
