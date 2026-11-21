import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import '../lib/core/services/jadwal_source.dart';

// Expected text comes from the auditor's reviewed transcription of the
// printed Dar al-Rashid 1409 AH edition (vol. 21, pp. 333-334), stored
// independently of the shipped asset.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (m) async {
    final path = utf8.decode(m!.buffer.asUint8List());
    final f = File(path);
    return f.existsSync() ? ByteData.sublistView(f.readAsBytesSync()) : null;
  });
  final expected = File('test/data/jadwal_fatir_35_3_4_recovered.txt').readAsStringSync().trimRight();

  test('Fatir 35:3 and 35:4 open the recovered passage, shared by both ayahs', () async {
    final s = JadwalSource();
    for (final ayah in [3, 4]) {
      final e = (await s.fetch(35, ayah))!;
      expect(e.ayahFrom, 3);
      expect(e.ayahTo, 4);
      expect(e.pages, hasLength(1));
      expect(e.pages.single.text, expected);
      expect(e.pages.single.label, contains('دار الرشيد'));
      expect(e.pages.single.label, contains('١٤٠٩'));
      expect(e.notice, contains('المقطع مشترك للآيات 3 إلى 4'));
      expect(e.notice, contains('دار الرشيد'));
      expect(e.notice, isNot(contains('الصفحة غير متوفرة')));
    }
  });

  test('neighbouring ayahs are unchanged and keep the mapped edition labels', () async {
    final s = JadwalSource();
    final two = (await s.fetch(35, 2))!;
    expect(two.pages.every((p) => p.label == null), isTrue);
    expect(two.ayahFrom, 2);
    expect(two.ayahTo, 2);
    final five = (await s.fetch(35, 5))!;
    expect(five.ayahFrom, 5);
    expect(five.ayahTo, 7);
    expect(five.pages.first.id, 2195577);
    expect(five.pages.first.label, isNull);
  });

  test('Ghafir 40:10 opens the complete printed passage with heading and footnotes', () async {
    final want = File('test/data/jadwal_ghafir_40_10_recovered.txt').readAsStringSync().trimRight();
    final e = (await JadwalSource().fetch(40, 10))!;
    expect(e.pages, hasLength(1));
    expect(e.pages.single.text, want);
    expect(e.pages.single.text, startsWith('١٠ ـ ﴿إِنَّ الَّذِينَ كَفَرُوا'));
    expect(e.pages.single.text, contains('الحواشي:'));
    expect(e.pages.single.label, contains('دار الرشيد'));
    expect(e.notice, contains('دار الرشيد'));
    final next = (await JadwalSource().fetch(40, 11))!;
    expect(next.ayahFrom, 11);
    expect(next.pages.first.id, 2195851);
    expect(next.pages.first.label, isNull);
  });
}
