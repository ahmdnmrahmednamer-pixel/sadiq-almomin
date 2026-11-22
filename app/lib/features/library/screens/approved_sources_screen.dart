import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router.dart';
import '../../../core/services/settings_service.dart';

/// Lists actual source connections separately from work not yet connected.
class ApprovedSourcesScreen extends StatelessWidget {
  const ApprovedSourcesScreen({super.key});
  @override Widget build(BuildContext context)=>Directionality(
    textDirection:SettingsService.instance.textDirection,
    child:Scaffold(appBar:AppBar(leading:const IsolatedBackButton(),title:const Text('المصادر')),
      body:ListView(padding:const EdgeInsets.all(16),children:[
        _card(context,'القراءات','البدور الزاهرة، عبد الفتاح القاضي',
          'الشاطبية والدرة. نص مباشر مع ترقيم المطبوع، دون التصويبات الملحقة. الربط بالآية لفظي وليس حصرًا لجميع أحكامها.',
          'https://shamela.ws/book/57',action:'فتح القراءات',route:'/qiraat'),
        _card(context,'التفسير','الميسر، الجلالين، القرطبي، البغوي',
          'الميسر من النص الموجود في التطبيق. الجلالين والقرطبي والبغوي باستعلام حي من AlQuran Cloud. بقية الاختيارات لم تُربط بعد.',
          'https://alquran.cloud'),
        _card(context,'أسباب النزول','لباب النقول، جلال الدين السيوطي',
          'تنقل بعناوين الآيات الصريحة في الكتاب مع حفظ نطاق النص والصفحات. المواضع غير المحسومة لا تُنسب تلقائيًا.',
          'https://api.quranpedia.net/v1/book/69'),
        _card(context,'الإعراب','الجدول في إعراب القرآن الكريم، محمود صافي',
          'قراءة مباشرة من المصدر مع صفحات الكتاب وسياقها. استُرجع موضعا فاطر ٣–٤ وغافر ١٠، وأي اختلاف موضح في موضعه.',
          'https://api.quranpedia.net/v1/book/1772',action:'فتح الإعراب',route:'/quran-irab'),
        _card(context,'التفسير الصوتي','المختصر في تفسير القرآن الكريم',
          'روابط الاستماع المتاحة في قسم التفسير الصوتي.','',action:'فتح التفسير الصوتي',route:'/audio-tafsir'),
      ])));
  Widget _card(BuildContext context,String title,String source,String state,String url,{String? action,String? route})=>Card(
    child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Text(title,style:Theme.of(context).textTheme.titleMedium),const SizedBox(height:6),
      Text(source,style:const TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:6),Text(state),
      if(url.isNotEmpty)...[const SizedBox(height:6),SelectableText(url,style:const TextStyle(fontSize:12))],
      if(route!=null)TextButton(onPressed:()=>context.push(route),child:Text(action!)),
    ])));
}
