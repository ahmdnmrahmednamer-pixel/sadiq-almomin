import 'package:flutter/material.dart';
import '../../../core/models/surah.dart';
import '../../../core/services/jadwal_source.dart';
import '../../../core/services/quran_repository.dart';

class QuranIrabScreen extends StatefulWidget {
  final int initialSurahId, initialAyah;
  final JadwalSource? source;
  const QuranIrabScreen({super.key,this.initialSurahId=1,this.initialAyah=1,this.source});
  @override State<QuranIrabScreen> createState()=>_QuranIrabScreenState();
}
class _QuranIrabScreenState extends State<QuranIrabScreen>{
  List<Surah> _surahs=[];
  late int _surah,_ayah;
  late final JadwalSource _source;
  JadwalEntry? _entry;
  String? _error;
  bool _loading=true;
  int _generation=0;
  @override void initState(){super.initState();_surah=widget.initialSurahId;_ayah=widget.initialAyah;_source=widget.source??JadwalSource();_init();}
  Future<void> _init()async{try{final list=await QuranRepository.loadSurahs();if(!mounted)return;setState(()=>_surahs=list);await _load();}catch(_){if(mounted)setState((){_loading=false;_error='تعذر تحميل فهرس السور.';});}}
  Future<void> _load()async{
    final generation=++_generation;
    setState((){_loading=true;_entry=null;_error=null;});
    try{final entry=await _source.fetch(_surah,_ayah);if(!mounted||generation!=_generation)return;setState((){_entry=entry;_loading=false;});}
    catch(_){if(!mounted||generation!=_generation)return;setState((){_loading=false;_error='تعذر تحميل المصدر أو تغيّرت صفحاته. أعد المحاولة. لا يعني ذلك عدم وجود إعراب للآية.';});}
  }
  @override Widget build(BuildContext context){
    final matches=_surahs.where((s)=>s.id==_surah);
    final surah=matches.isEmpty?null:matches.first;
    return Directionality(textDirection:TextDirection.rtl,child:Scaffold(
      appBar:AppBar(title:const Text('إعراب القرآن')),
      body:ListView(padding:const EdgeInsets.all(16),children:[
        const Text('الجدول في إعراب القرآن الكريم',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
        const Text('محمود صافي • الموسوعة القرآنية\nقراءة مباشرة عبر الإنترنت، دون تضمين نص الكتاب في التطبيق.'),
        const SizedBox(height:16),
        if(_surahs.isNotEmpty) Row(children:[
          Expanded(flex:3,child:DropdownButtonFormField<int>(initialValue:_surah,isExpanded:true,decoration:const InputDecoration(labelText:'السورة'),items:_surahs.map((s)=>DropdownMenuItem(value:s.id,child:Text(s.nameAr))).toList(),onChanged:(v){if(v==null)return;setState((){_surah=v;_ayah=1;});_load();})),
          const SizedBox(width:12),
          Expanded(flex:2,child:DropdownButtonFormField<int>(key:ValueKey('$_surah:$_ayah'),initialValue:_ayah,isExpanded:true,decoration:const InputDecoration(labelText:'الآية'),items:List.generate(surah?.ayahCount??7,(i)=>DropdownMenuItem(value:i+1,child:Text('${i+1}'))),onChanged:(v){if(v==null)return;setState(()=>_ayah=v);_load();})),
        ]),
        const SizedBox(height:16),
        if(_loading)const Padding(padding:EdgeInsets.all(32),child:Center(child:CircularProgressIndicator(semanticsLabel:'تحميل صفحات الإعراب'))),
        if(_error!=null)...[Text(_error!),TextButton(onPressed:_load,child:const Text('إعادة المحاولة'))],
        if(!_loading&&_error==null&&_entry==null)const Text('لم يُثبت موضع الآية في فهرس الكتاب. لا يعني ذلك عدم وجود إعراب لها.'),
        if(_entry!=null)...[
          Text(_entry!.notice,style:const TextStyle(height:1.6)),
          const SizedBox(height:12),
          for(final page in _entry!.pages)Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
            Semantics(header:true,child:Text('ج${page.part} ص${page.page}',style:const TextStyle(fontWeight:FontWeight.bold))),
            const Divider(),
            if(page.focusOffset>0)ExpansionTile(key:ValueKey('context:$_surah:$_ayah:${page.id}'),title:const Text('سياق الصفحة السابق'),children:[SelectableText(String.fromCharCodes(page.text.runes.take(page.focusOffset)),style:const TextStyle(fontSize:18,height:1.8,fontFamily:'Amiri'))]),
            Semantics(header:true,child:Text('موضع الربط في الصفحة',style:TextStyle(fontWeight:FontWeight.bold,color:Theme.of(context).colorScheme.primary))),
            const SizedBox(height:8),
            SelectableText(String.fromCharCodes(page.text.runes.skip(page.focusOffset)),style:const TextStyle(fontSize:18,height:1.8,fontFamily:'Amiri')),
          ]))),
          const SizedBox(height:16),
          const SelectableText(JadwalSource.bookUrl),
        ],
      ]),
    ));
  }
}
