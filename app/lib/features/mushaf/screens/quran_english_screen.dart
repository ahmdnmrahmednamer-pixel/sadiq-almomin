import 'package:flutter/material.dart';
import '../../../core/services/quran_english_source.dart';

class QuranEnglishScreen extends StatefulWidget {
  final int surah, ayah, ayahCount;
  final QuranEnglishSource? source;
  const QuranEnglishScreen({super.key,required this.surah,required this.ayah,required this.ayahCount,this.source});
  @override State<QuranEnglishScreen> createState()=>_QuranEnglishScreenState();
}
class _QuranEnglishScreenState extends State<QuranEnglishScreen> {
  late int _ayah;
  late final QuranEnglishSource _source;
  QuranEnglishVerse? _verse;
  bool _loading=true;
  String? _error;
  int _generation=0;
  @override void initState(){super.initState();_ayah=widget.ayah;_source=widget.source??QuranEnglishSource();_load();}
  Future<void> _load()async {
    final generation=++_generation;setState((){_loading=true;_verse=null;_error=null;});
    try{
      final value=await _source.fetch(widget.surah,_ayah);
      if(!mounted||generation!=_generation)return;
      setState((){_verse=value;_loading=false;if(value==null)_error='تعذر العثور على ترجمة هذه الآية.';});
    }catch(_){if(mounted&&generation==_generation)setState((){_loading=false;_error='تعذر قراءة حزمة الترجمة المضمّنة. لا تُعرض ترجمة بديلة.';});}
  }
  @override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(
    appBar:AppBar(title:const Text('الترجمة الإنجليزية')),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      const Text('ترجمة مركز رواد الترجمة',style:TextStyle(fontWeight:FontWeight.bold,fontSize:20)),
      const Text('موسوعة القرآن الكريم QuranEnc • الإصدار ${QuranEnglishSource.version}'),
      const SizedBox(height:16),
      Row(children:[
        IconButton(tooltip:'الآية السابقة',onPressed:_ayah>1?(){setState(()=>_ayah--);_load();}:null,icon:const Icon(Icons.arrow_back)),
        Expanded(child:Text('سورة ${widget.surah}، آية $_ayah',textAlign:TextAlign.center)),
        IconButton(tooltip:'الآية التالية',onPressed:_ayah<widget.ayahCount?(){setState(()=>_ayah++);_load();}:null,icon:const Icon(Icons.arrow_forward)),
      ]),
      if(_loading)const Center(child:CircularProgressIndicator(semanticsLabel:'قراءة الترجمة')),
      if(_error!=null)...[Text(_error!),TextButton(onPressed:_load,child:const Text('إعادة المحاولة'))],
      if(_verse!=null)Directionality(textDirection:TextDirection.ltr,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Semantics(header:true,child:Text('Translation ${widget.surah}:$_ayah',style:const TextStyle(fontWeight:FontWeight.bold))),
        const SizedBox(height:12),SelectableText(_verse!.text,style:const TextStyle(fontSize:20,height:1.6)),
        if(_verse!.footnotes.isNotEmpty)...[
          const SizedBox(height:20),const Text('Footnotes',style:TextStyle(fontWeight:FontWeight.bold)),
          const SizedBox(height:8),SelectableText(_verse!.footnotes,style:const TextStyle(fontSize:16,height:1.5)),
        ],
        const Divider(height:32),
        const Text('Translated by the team of the Rowwad Translation Center, in cooperation with the Rabwah Dawah Association, the Islamic Content Service Association in Languages, and the IslamHouse.com website.'),
        const SizedBox(height:8),const SelectableText('QuranEnc.com • ${QuranEnglishSource.editionKey} • v${QuranEnglishSource.version}\n${QuranEnglishSource.sourceUrl}'),
      ])),
    ]),
  ));
}
