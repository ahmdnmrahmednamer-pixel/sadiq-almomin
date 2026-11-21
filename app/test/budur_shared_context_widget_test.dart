import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/core/services/budur_source.dart';
import '../lib/core/services/quran_repository.dart';
import '../lib/core/services/settings_service.dart';
import '../lib/features/mushaf/screens/qiraat_mushaf_screen.dart';

class SharedContextLocalSource extends BudurSource {
 @override Future<String>load()async=>File(Platform.environment['BUDUR_REFERENCE_SOURCE']!).readAsStringSync();
}
void main(){
 testWidgets('shared context leaves when selected ayah moves to following quarter',(t)async{
  SharedPreferences.setMockInitialValues({});await SettingsService.instance.init(forceReload:true);
  QuranRepository.resetCachesForTesting();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async{
   final f=File(utf8.decode(m!.buffer.asUint8List()));return f.existsSync()?ByteData.sublistView(f.readAsBytesSync()):null;
  });
  addTearDown((){QuranRepository.resetCachesForTesting();TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',null);});
  await t.pumpWidget(MaterialApp(home:QiraatMushafScreen(source:SharedContextLocalSource(),initialSurah:76,initialAyah:18)));
  await t.runAsync(()async{for(var i=0;i<100;i++){await Future<void>.delayed(const Duration(milliseconds:20));await t.pump();}});
  await t.pumpAndSettle();
  expect(find.textContaining('1 إلى 18'),findsOneWidget);
  final previous = BudurSource.sharedContexts(File(Platform.environment['BUDUR_REFERENCE_SOURCE']!).readAsStringSync(),surahId:76,ayahNumber:18).single.text;
  await t.tap(find.byType(DropdownButtonFormField<int>).last);await t.pumpAndSettle();
  await t.tap(find.text('19').last);await t.pumpAndSettle();
  expect(find.textContaining('1 إلى 18'),findsNothing);
  expect(find.textContaining('19 إلى 31'),findsOneWidget);
  expect(find.byWidgetPredicate((w)=>w is SelectableText && w.data==previous),findsNothing);
  expect(t.takeException(),isNull);
 },skip:Platform.environment['BUDUR_REFERENCE_SOURCE']==null);
}
