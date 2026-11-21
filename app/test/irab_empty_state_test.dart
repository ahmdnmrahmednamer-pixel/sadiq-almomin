import 'package:almomin/core/services/jadwal_source.dart';
import 'package:almomin/features/mushaf/screens/quran_irab_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoEntrySource extends JadwalSource {
  _NoEntrySource() : super(useBundled: false);
  @override
  Future<JadwalEntry?> fetch(int surah, int ayah) async => null;
  @override
  Future<DateTime?> offlineSavedAt() async => null;
}

void main() {
  testWidgets('i\'rab screen shows a plain empty state with no indexing language', (t) async {
    await t.pumpWidget(MaterialApp(home: QuranIrabScreen(initialSurahId: 1, initialAyah: 1, source: _NoEntrySource())));
    await t.pumpAndSettle();
    expect(find.text('لا يوجد حاليا نص إعراب مرتبط بهذه الآية.'), findsOneWidget);
    expect(find.textContaining('فهرس'), findsNothing);
  });
}
