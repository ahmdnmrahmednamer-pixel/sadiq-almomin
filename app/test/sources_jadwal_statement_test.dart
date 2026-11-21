import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
void main(){
 test('Sources Jadwal card no longer claims a missing Fatir page and matches the recovered passages',(){
  final s=File('lib/features/library/screens/approved_sources_screen.dart').readAsStringSync();
  expect(s.contains('نقص فاطر'),isFalse);
  expect(s.contains('اختلاف تفريغ غافر'),isFalse);
  expect(s.contains('فاطر ٣–٤ وغافر ١٠'),isTrue);
  expect(File('test/data/jadwal_fatir_35_3_4_recovered.txt').existsSync(),isTrue);
  expect(File('test/data/jadwal_ghafir_40_10_recovered.txt').existsSync(),isTrue);
 });
}
