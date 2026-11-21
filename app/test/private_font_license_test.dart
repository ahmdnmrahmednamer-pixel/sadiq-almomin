import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/services/source_font_support.dart';
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 test('bundled source font license is readable and registration is idempotent',()async{
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async{final f=File(utf8.decode(m!.buffer.asUint8List()));return f.existsSync()?ByteData.sublistView(f.readAsBytesSync()):null;});
  registerSourceFontLicense();registerSourceFontLicense();
  final entries=await LicenseRegistry.licenses.where((entry)=>entry.packages.contains('Kitab')).toList();
  expect(entries.length,1);final text=entries.single.paragraphs.map((p)=>p.text).join('\n');
  expect(text,contains('SIL OPEN FONT LICENSE'));expect(text,contains('Katib Project Authors'));expect(text,contains('Scheherazade'));
 });
}
