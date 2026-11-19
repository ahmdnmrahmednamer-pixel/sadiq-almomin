import 'package:dio/dio.dart';
import '../models/ayah.dart';
import '../models/surah.dart';

class BudurPassage {
  final String text;
  final int firstPage, lastPage;
  final List<int> ayahs;
  const BudurPassage(this.text, this.firstPage, this.lastPage, this.ayahs);
}

/// Reads the original book only, stopping before the separately added corrections.
/// Linkage is lexical navigation, not a newly authored reading or ruling.
class BudurSource {
  static const bookUrl = 'https://shamela.ws/book/57';
  static const textUrl = 'https://www-archiv.fdm.uni-hamburg.de/islamicempire/texts/57.txt';
  final Dio dio;
  BudurSource({Dio? dio}) : dio=dio ?? Dio(BaseOptions(
    connectTimeout:const Duration(seconds:15),receiveTimeout:const Duration(seconds:30)));
  String? _sessionText;
  Future<String> load() async {
    if (_sessionText != null) return _sessionText!;
    final response=await dio.get<String>(textUrl,options:Options(responseType:ResponseType.plain));
    final value=response.data;
    if(value==null || !value.contains('عبد الفتاح') || !value.contains('الشاطبية') || !value.contains('الدرة')) {
      throw const FormatException('Book identity mismatch');
    }
    final stop=value.indexOf('تصويبات للشيخ');
    if(stop<0) throw const FormatException('Original-text boundary missing');
    return _sessionText=value.substring(0,stop);
  }
  static String normalize(String s) => s.replaceAll(RegExp('[ً-ٰٟۖ-ۭـ]'),'')
    .replaceAll(RegExp('[أإآٱ]'),'ا').replaceAll('ى','ي')
    .replaceAll(RegExp('[^ء-ي ]'),' ').replaceAll(RegExp(r'\s+'),' ').trim();

  static List<BudurPassage> passages(String source,Surah surah,List<Ayah> ayahs) {
    final stop=source.indexOf('تصويبات للشيخ');
    if(stop>=0)source=source.substring(0,stop);
    const aliases={'يونس عليه السلام':10,'طه عليه السلام':20,'نوح عليه السلام':71,'المؤمن':40,'ن':68,'الدهر':76,'المنافقين':63,'والطور':52,
      'والمرسلات':77,'والفجر':89,'والشمس':91,'والليل':92,'والضحى':93,
      'الم نشرح':94,'والتين':95,'الزلزال':99,'والعاديات':100,'والعصر':103,
      'سيدنا ومولانا محمد صلي الله عليه وسلم':47};
    final heads=RegExp(r'"[ \t]*سورة[ \t]+([^"\n]+)"|^[ \t]*\(?[ \t]*سورة[ \t]+([^\n)]+?)\)?[ \t]*$',multiLine:true)
      .allMatches(source).where((m)=>!(m.group(1)??m.group(2)!).contains('من السور') && !(m.group(1)??m.group(2)!).contains('آخر السور')).toList();
    RegExpMatch? heading;int end=source.length;
    for(var i=0;i<heads.length;i++) {
      final n=normalize(heads[i].group(1)??heads[i].group(2)!);
      if(n==normalize(surah.nameAr).replaceFirst(RegExp(r'^سورة '),'') || aliases.entries.any((e)=>normalize(e.key)==n && e.value==surah.id)) {
        heading=heads[i];end=i+1<heads.length?heads[i+1].start:source.length;break;
      }
    }
    if(heading==null)return const [];
    // The final chapter ends before the separately headed takbir chapter.
    final takbir=source.indexOf('باب التكبير',heading.end);
    if(takbir>=0 && takbir<end)end=takbir;
    final chapter=source.substring(heading.end,end);
    final markers=RegExp(r'^\s*"\s*([^"\n]+)"',multiLine:true).allMatches(chapter).toList();
    final pages=RegExp(r'الجزء:\s*\d+\s*¦\s*الصفحة:\s*(\d+)').allMatches(source).toList();
    int pageAt(int offset) {
      for(final p in pages) {if(p.start>=offset)return int.parse(p.group(1)!);}
      return 357;
    }
    final result=<BudurPassage>[];
    final introEnd=markers.isEmpty?end:heading.end+markers.first.start;
    final intro=source.substring(heading.end,introEnd).replaceAll(RegExp(r'\s*الجزء:\s*\d+\s*¦\s*الصفحة:\s*\d+\s*'),'\n\n').trim();
    if(intro.isNotEmpty)result.add(BudurPassage(intro,pageAt(heading.end),pageAt(introEnd-1),const []));
    for(var i=0;i<markers.length;i++) {
      final m=markers[i];final a=heading.end+m.start;
      final b=i+1<markers.length?heading.end+markers[i+1].start:end;
      final quote=normalize(m.group(1)!);
      final matches=ayahs.where((v)=>(' ${normalize(v.cleanTextUthmani)} ').contains(' $quote ')).toList();
      // Repeated words stay unassigned. No neighbouring-verse fallback.
      final linked=matches.length==1 ? [matches.single.ayahNumber] : <int>[];
      final text=source.substring(a,b).replaceAll(RegExp(r'\s*الجزء:\s*\d+\s*¦\s*الصفحة:\s*\d+\s*'),'\n\n').trim();
      var last=b-1;
      final included=pages.where((p)=>p.start>=a && p.end<=b).toList();
      if(included.isNotEmpty && source.substring(included.last.end,b).trim().isEmpty) {
        last=included.last.start-1;
      }
      result.add(BudurPassage(text,pageAt(a),pageAt(last),linked));
    }
    return result;
  }
}
