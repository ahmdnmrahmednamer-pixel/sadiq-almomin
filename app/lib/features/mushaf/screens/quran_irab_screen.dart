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
  DateTime? _savedAt;
  bool _copyBusy=false,_badCopy=false;
  String? _copyMessage;
  @override void initState(){super.initState();_surah=widget.initialSurahId;_ayah=widget.initialAyah;_source=widget.source??JadwalSource();_init();}
  Future<void> _init()async{try{final list=await QuranRepository.loadSurahs();if(!mounted)return;setState(()=>_surahs=list);try{_savedAt=await _source.offlineSavedAt();}catch(_){_badCopy=true;}await _load();}catch(_){if(mounted)setState((){_loading=false;_error='تعذر تحميل فهرس السور.';});}}
  Future<void> _load()async{
    final generation=++_generation;
    setState((){_loading=true;_entry=null;_error=null;});
    try{final entry=await _source.fetch(_surah,_ayah);if(!mounted||generation!=_generation)return;setState((){_entry=entry;_loading=false;});}
    catch(_){if(!mounted||generation!=_generation)return;setState((){_loading=false;_error='تعذر تحميل المصدر أو تغيّرت صفحاته. أعد المحاولة. لا يعني ذلك عدم وجود إعراب للآية.';});}
  }
  Future<void> _offlineAction(String action)async{
    setState((){_copyBusy=true;_copyMessage=null;});
    try{
      if(action=='delete'){await _source.deleteOffline();_savedAt=null;_badCopy=false;}
      else{await _source.downloadForOffline(refresh:action=='refresh');_savedAt=await _source.offlineSavedAt();_badCopy=false;}
      if(!mounted)return;
      setState(()=>_copyMessage=action=='delete'?'حُذفت النسخة من الجهاز.':'حُفظ الكتاب كاملًا داخل التطبيق.');
      await _load();
    }catch(_){if(mounted)setState(()=>_copyMessage='تعذر حفظ النسخة أو تحديثها. لم يُستبدل النص بنسخة غير مطابقة للفهرس.');}
    finally{if(mounted)setState(()=>_copyBusy=false);}
  }
  @override Widget build(BuildContext context){
    final matches=_surahs.where((s)=>s.id==_surah);
    final surah=matches.isEmpty?null:matches.first;
    return Directionality(textDirection:TextDirection.rtl,child:Scaffold(
      appBar:AppBar(title:const Text('إعراب القرآن')),
      body:ListView(padding:const EdgeInsets.all(16),children:[
        const Text('الجدول في إعراب القرآن الكريم',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
        Text(_source.isBundled
            ? 'محمود صافي • الموسوعة القرآنية\nالنص مدمج مع التثبيت، ولا يحتاج اتصالًا.'
            : 'محمود صافي • الموسوعة القرآنية\nقراءة من المصدر، وتنزيل اختياري داخل التطبيق. نص الكتاب غير مضمّن في ملف التثبيت.'),
        if(_savedAt!=null)Text('نسخة الجهاز: ${_savedAt!.toLocal().toIso8601String().split("T").first}. قد يصحّح المصدر نصه؛ حدّث النسخة عند الاتصال.'),
        if(_badCopy)const Text('نسخة الجهاز لا تطابق الإصدار المعتمد. احذفها وأعد التنزيل.'),
        if(!_source.isBundled) Wrap(spacing:8,children:[
          if(_savedAt==null&&!_badCopy)TextButton(onPressed:_copyBusy?null:()=>_offlineAction('download'),child:const Text('تنزيل الكتاب كاملًا')),
          if(_savedAt!=null)TextButton(onPressed:_copyBusy?null:()=>_offlineAction('refresh'),child:const Text('تحديث نسخة الجهاز')),
          if(_savedAt!=null||_badCopy)TextButton(onPressed:_copyBusy?null:()=>_offlineAction('delete'),child:const Text('حذف نسخة الجهاز')),
        ]),
        if(_copyBusy)const LinearProgressIndicator(semanticsLabel:'حفظ نسخة الكتاب أو تحديثها'),
        if(_copyMessage!=null)Semantics(liveRegion:true,child:Text(_copyMessage!)),
        const SizedBox(height:16),
        if(_surahs.isNotEmpty) Row(children:[
          Expanded(flex:3,child:DropdownButtonFormField<int>(initialValue:_surah,isExpanded:true,decoration:const InputDecoration(labelText:'السورة'),items:_surahs.map((s)=>DropdownMenuItem(value:s.id,child:Text(s.nameAr))).toList(),onChanged:(v){if(v==null)return;setState((){_surah=v;_ayah=1;});_load();})),
          const SizedBox(width:12),
          Expanded(flex:2,child:DropdownButtonFormField<int>(key:ValueKey('$_surah:$_ayah'),initialValue:_ayah,isExpanded:true,decoration:const InputDecoration(labelText:'الآية'),items:List.generate(surah?.ayahCount??7,(i)=>DropdownMenuItem(value:i+1,child:Text('${i+1}'))),onChanged:(v){if(v==null)return;setState(()=>_ayah=v);_load();})),
        ]),
        const SizedBox(height:16),
        if(_loading)const Padding(padding:EdgeInsets.all(32),child:Center(child:CircularProgressIndicator(semanticsLabel:'تحميل صفحات الإعراب'))),
        if(_error!=null)...[Text(_error!),TextButton(onPressed:_load,child:const Text('إعادة المحاولة'))],
        if(!_loading&&_error==null&&_entry==null)const Text('لا يوجد حاليا نص إعراب مرتبط بهذه الآية.'),
        if(_entry!=null)...[
          Text(_entry!.notice,style:const TextStyle(height:1.6)),
          const SizedBox(height:12),
          for(final page in _entry!.pages)Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
            Semantics(header:true,child:Text(page.label??'ج${page.part} ص${page.page}',style:const TextStyle(fontWeight:FontWeight.bold))),
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
