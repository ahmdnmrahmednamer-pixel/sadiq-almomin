import 'package:flutter/material.dart';
import '../../../core/services/reader_bookmark_service.dart';

/// Reusable for online books, EPUB books and future document readers.
Future<ReaderBookmark?> showReaderBookmarks(BuildContext context, {
  required String documentId,
  required String locationKind,
  required int page,
  required double scrollOffset,
  required String pageLabel,
  ReaderBookmarkService? service,
}) => showModalBottomSheet<ReaderBookmark>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _ReaderBookmarksSheet(documentId:documentId,
    locationKind:locationKind,page:page,scrollOffset:scrollOffset,
    pageLabel:pageLabel,service:service ?? ReaderBookmarkService()),
);

class _ReaderBookmarksSheet extends StatefulWidget {
  final String documentId, locationKind, pageLabel;
  final int page;
  final double scrollOffset;
  final ReaderBookmarkService service;
  const _ReaderBookmarksSheet({required this.documentId,required this.locationKind,
    required this.page,required this.scrollOffset,required this.pageLabel,required this.service});
  @override
  State<_ReaderBookmarksSheet> createState()=>_ReaderBookmarksSheetState();
}
class _ReaderBookmarksSheetState extends State<_ReaderBookmarksSheet> {
  List<ReaderBookmark> _marks=[];
  bool _loading=true;
  String? _error;
  @override
  void initState(){super.initState();_reload();}
  Future<void> _reload() async {
    try {
      final marks=await widget.service.list(widget.documentId,widget.locationKind);
      if(mounted) setState((){_marks=marks;_loading=false;_error=null;});
    } catch (_) {
      if(mounted) setState((){_loading=false;_error='تعذر قراءة العلامات. لم تُغيّر البيانات.';});
    }
  }
  Future<void> _add() async {
    var draftLabel=widget.pageLabel;
    final label=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('علامة جديدة'),
      content:TextFormField(initialValue:widget.pageLabel,onChanged:(value)=>draftLabel=value,autofocus:true,decoration:const InputDecoration(labelText:'اسم العلامة'),onFieldSubmitted:(value)=>Navigator.pop(ctx,value)),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('إلغاء')),TextButton(onPressed:()=>Navigator.pop(ctx,draftLabel),child:const Text('حفظ'))],
    ));
    if(label==null || !mounted) return;
    try {
      await widget.service.add(documentId:widget.documentId,locationKind:widget.locationKind,
        page:widget.page,scrollOffset:widget.scrollOffset,label:label.trim().isEmpty?widget.pageLabel:label);
      await _reload();
    }catch(_){if(mounted)setState(()=>_error='تعذر حفظ العلامة. حاول مرة أخرى.');}
  }
  Future<void> _remove(ReaderBookmark mark) async {
    try{await widget.service.remove(mark);await _reload();}
    catch(_){if(mounted)setState(()=>_error='تعذر حذف العلامة.');}
  }
  @override
  Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,
    child:SafeArea(child:SizedBox(height:MediaQuery.sizeOf(context).height*.75,
      child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Padding(padding:const EdgeInsets.all(16),child:Text('العلامات المرجعية',style:Theme.of(context).textTheme.titleLarge)),
        Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:FilledButton.icon(onPressed:_loading||_error!=null?null:_add,icon:const Icon(Icons.bookmark_add_outlined),label:const Text('إضافة الموضع الحالي'))),
        if(_error!=null) Padding(padding:const EdgeInsets.all(16),child:Text(_error!,semanticsLabel:_error)),
        Expanded(child:_loading?const Center(child:CircularProgressIndicator()):_marks.isEmpty?const Center(child:Text('لا توجد علامات')):ListView.builder(
          itemCount:_marks.length,itemBuilder:(context,index){final mark=_marks[index];return ListTile(
            title:Text(mark.label),subtitle:Text('الصفحة ${mark.locationKind=="epub-spine"?mark.page+1:mark.page}'),
            onTap:()=>Navigator.pop(context,mark),
            trailing:IconButton(tooltip:'حذف ${mark.label}',icon:const Icon(Icons.delete_outline),onPressed:()=>_remove(mark)),
          );},
        )),
      ]),
    )),
  );
}
