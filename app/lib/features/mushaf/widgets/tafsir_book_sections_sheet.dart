import 'package:flutter/material.dart';
import '../../../core/services/bundled_tafsir_source.dart';

/// Separate book material, never presented as commentary on the selected ayah.
/// All text comes from the same pinned installation source as the ayah reader.
class TafsirBookSectionsSheet extends StatefulWidget {
  final String bookName;
  final Future<List<BundledTafsirBookSection>> Function() loadSections;
  final double fontSize;
  const TafsirBookSectionsSheet({super.key,required this.bookName,required this.loadSections,this.fontSize=18});
  @override State<TafsirBookSectionsSheet> createState()=>_TafsirBookSectionsSheetState();
}
class _TafsirBookSectionsSheetState extends State<TafsirBookSectionsSheet>{
  late Future<List<BundledTafsirBookSection>> _future;
  int _section=0,_page=0;
  final _scroll=ScrollController();
  Future<List<BundledTafsirBookSection>> _load(){
    final future=Future<List<BundledTafsirBookSection>>.sync(widget.loadSections);
    // A retry may fail before FutureBuilder's next frame attaches its listener.
    // Keep that error handled immediately; FutureBuilder still renders it.
    future.ignore();return future;
  }
  @override void initState(){super.initState();_future=_load();}
  @override void dispose(){_scroll.dispose();super.dispose();}
  void _go(int section,int page){setState((){_section=section;_page=page;});if(_scroll.hasClients)_scroll.jumpTo(0);}
  @override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:SafeArea(child:SizedBox(height:MediaQuery.sizeOf(context).height*.9,child:Column(children:[
    Padding(padding:const EdgeInsets.symmetric(horizontal:12,vertical:8),child:Row(children:[Expanded(child:Semantics(header:true,child:Text('أقسام الكتاب',style:Theme.of(context).textTheme.titleLarge))),IconButton(tooltip:'إغلاق أقسام الكتاب',onPressed:()=>Navigator.of(context).pop(),icon:const Icon(Icons.close))])),
    Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:Text(widget.bookName)),
    Expanded(child:FutureBuilder<List<BundledTafsirBookSection>>(future:_future,builder:(context,snapshot){
      if(snapshot.hasError)return Center(child:Column(mainAxisSize:MainAxisSize.min,children:[const Text('تعذر قراءة أقسام الكتاب. لا يعرض نص بديل.'),TextButton(onPressed:()=>setState((){_future=_load();}),child:const Text('إعادة المحاولة'))]));
      if(!snapshot.hasData)return const Center(child:CircularProgressIndicator());
      final sections=snapshot.data!;if(sections.isEmpty)return const Center(child:Text('لا توجد أقسام إضافية في هذا المصدر.'));
      final section=sections[_section];final page=section.pages[_page];
      return Column(children:[
        Padding(padding:const EdgeInsets.all(12),child:DropdownButtonFormField<int>(key:ValueKey('section-$_section'),initialValue:_section,isExpanded:true,decoration:const InputDecoration(labelText:'قسم الكتاب',border:OutlineInputBorder()),items:[for(var i=0;i<sections.length;i++)DropdownMenuItem(value:i,child:Text(sections[i].title,maxLines:2,overflow:TextOverflow.ellipsis))],onChanged:(value){if(value!=null)_go(value,0);})),
        Expanded(child:SingleChildScrollView(controller:_scroll,padding:const EdgeInsets.fromLTRB(20,8,20,24),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          if(page.sourceLabel!=null)Padding(padding:const EdgeInsets.only(bottom:8),child:Text(page.sourceLabel!,style:const TextStyle(fontSize:13))),
          if(page.sourceUrl!=null)Padding(padding:const EdgeInsets.only(bottom:12),child:SelectableText(page.sourceUrl!,style:const TextStyle(fontSize:11))),
          SelectableText(page.text,style:TextStyle(fontSize:widget.fontSize,height:1.9,fontFamilyFallback:const ['Kitab'])),
        ]))),
        const Divider(height:1),
        Padding(padding:const EdgeInsets.symmetric(horizontal:8,vertical:8),child:Row(children:[
          Expanded(child:TextButton(onPressed:_page>0?()=>_go(_section,_page-1):null,child:const Text('السابق',textAlign:TextAlign.center))),
          Expanded(child:Semantics(liveRegion:true,child:Text('${_page+1} من ${section.pages.length}',textAlign:TextAlign.center))),
          Expanded(child:TextButton(onPressed:_page+1<section.pages.length?()=>_go(_section,_page+1):null,child:const Text('التالي',textAlign:TextAlign.center))),
        ])),
      ]);
    })),
  ]))));
}
