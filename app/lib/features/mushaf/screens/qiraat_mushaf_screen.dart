import 'package:flutter/material.dart';
import '../../../core/services/budur_source.dart';
import '../../../core/services/quran_repository.dart';
import '../../../core/models/surah.dart';
import '../../../core/services/settings_service.dart';
import '../../../app/router.dart';

class QiraatMushafScreen extends StatefulWidget {
  final BudurSource? source;
  final int initialSurah, initialAyah;
  const QiraatMushafScreen({super.key,this.source,this.initialSurah=1,this.initialAyah=0});
  @override State<QiraatMushafScreen> createState()=>_QiraatMushafScreenState();
}
class _QiraatMushafScreenState extends State<QiraatMushafScreen> {
  late final BudurSource _source;
  List<Surah> _surahs=[];
  List<BudurPassage> _passages=[];
  int _surah=1,_ayah=0,_count=7,_version=0;
  bool _busy=true;
  String? _error;
  @override void initState(){super.initState();_surah=widget.initialSurah;_ayah=widget.initialAyah;_count=_ayah>7?_ayah:7;_source=widget.source??BudurSource();_load();}
  Future<void> _load() async {
    final version=++_version;
    setState((){_busy=true;_error=null;_passages=[];});
    try {
      final surahs=await QuranRepository.loadSurahs();
      if(surahs.isEmpty)throw const FormatException('Surah catalogue unavailable');
      final current=surahs.firstWhere((s)=>s.id==_surah);
      final ayahs=await QuranRepository.getAyahsForSurah(_surah);
      if(ayahs.isEmpty)throw const FormatException('Verse reference unavailable');
      final text=await _source.load();
      final passages=BudurSource.passages(text,current,ayahs);
      if(!mounted||version!=_version)return;
      setState((){_surahs=surahs;_count=ayahs.length;_passages=passages;_busy=false;});
    }catch(_){if(mounted&&version==_version)setState((){_busy=false;_error='تعذر تحميل نص البدور الزاهرة. تحقق من الاتصال وأعد المحاولة.';});}
  }
  @override Widget build(BuildContext context){
    final shown=_ayah==0?_passages:_passages.where((p)=>p.ayahs.contains(_ayah)).toList();
    return Directionality(textDirection:SettingsService.instance.textDirection,child:Scaffold(
      appBar:AppBar(leading:const IsolatedBackButton(),title:const Text('القراءات')),
      body:Column(children:[
        const ListTile(title:Text('البدور الزاهرة'),subtitle:Text('عبد الفتاح القاضي · الشاطبية والدرة')),
        Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:Row(children:[
          Expanded(child:DropdownButtonFormField<int>(initialValue:_surah,
            decoration:const InputDecoration(labelText:'السورة'),isExpanded:true,
            items:_surahs.map((s)=>DropdownMenuItem(value:s.id,child:Text(s.nameAr))).toList(),
            onChanged:_busy?null:(v){if(v!=null){_surah=v;_ayah=0;_load();}})),
          const SizedBox(width:12),
          Expanded(child:DropdownButtonFormField<int>(key:ValueKey('$_surah:$_count'),initialValue:_ayah,
            decoration:const InputDecoration(labelText:'الآية'),isExpanded:true,
            items:[const DropdownMenuItem(value:0,child:Text('السورة كاملة')),
              for(var n=1;n<=_count;n++)DropdownMenuItem(value:n,child:Text('$n'))],
            onChanged:_busy?null:(v){if(v!=null)setState(()=>_ayah=v);})),
        ])),
        const Padding(padding:EdgeInsets.all(12),child:Text('مواضع النص بحسب اللفظ. الإحالات والأصول العامة تُقرأ في سياق السورة.')),
        Expanded(child:_busy?const Center(child:CircularProgressIndicator()):_error!=null?
          Center(child:Column(mainAxisSize:MainAxisSize.min,children:[Text(_error!),TextButton(onPressed:_load,child:const Text('إعادة المحاولة'))])):
          shown.isEmpty?const Center(child:Padding(padding:EdgeInsets.all(24),child:Text('لم يُثبت ربط لفظي لهذا الموضع. لا يعني ذلك عدم وجود حكم في الكتاب. اختر السورة كاملة لقراءة السياق.'))):
          ListView.builder(padding:const EdgeInsets.all(16),itemCount:shown.length,itemBuilder:(c,i){final p=shown[i];return Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
            Text(p.firstPage==p.lastPage?'ص ${p.firstPage}':'ص ${p.firstPage} إلى ${p.lastPage}',style:Theme.of(context).textTheme.labelMedium),
            const SizedBox(height:8),SelectableText(p.text,style:const TextStyle(fontSize:18,height:1.8)),
          ])));})),
        const Padding(padding:EdgeInsets.all(8),child:SelectableText(BudurSource.bookUrl,style:TextStyle(fontSize:12))),
      ])));
  }
}
