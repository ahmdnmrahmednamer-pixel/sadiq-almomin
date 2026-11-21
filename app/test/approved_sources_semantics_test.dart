import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/core/services/settings_service.dart';
import '../lib/features/library/screens/approved_sources_screen.dart';
void main(){
 testWidgets('Sources screen exposes each source title as a heading and body lines as non-headings',(t)async{
  SharedPreferences.setMockInitialValues({});
  await t.runAsync(()async{await SettingsService.instance.init(forceReload:true);});
  t.view.physicalSize=const Size(800,4000);t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
  final h=t.ensureSemantics();
  await t.pumpWidget(const MaterialApp(home:ApprovedSourcesScreen()));
  await t.pumpAndSettle();
  for(final title in ['القراءات','التفسير','أسباب النزول','الإعراب']){
   expect(t.getSemantics(find.text(title)),matchesSemantics(label:title,isHeader:true,textDirection:TextDirection.rtl),reason:title);
  }
  final src=t.getSemantics(find.text('لباب النقول، جلال الدين السيوطي'));
  expect(src.getSemanticsData().hasFlag(SemanticsFlag.isHeader),isFalse);
  h.dispose();
 });
}
