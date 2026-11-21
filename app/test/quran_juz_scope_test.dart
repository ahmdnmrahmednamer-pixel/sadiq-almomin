import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/core/services/quran_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('juz ayahs: counts follow the independent standard (juz 1 starts 1:1, juz 30 ends 114:6, all 6236)', () async {
    var total = 0;
    for (var j = 1; j <= 30; j++) {
      final l = await QuranRepository.getAyahsForJuz(j);
      expect(l, isNotEmpty);
      total += l.length;
      if (j == 1) expect('${l.first.surahId}:${l.first.ayahNumber}', '1:1');
      if (j == 2) expect('${l.first.surahId}:${l.first.ayahNumber}', '2:142');
      if (j == 30) {
        expect('${l.first.surahId}:${l.first.ayahNumber}', '78:1');
        expect('${l.last.surahId}:${l.last.ayahNumber}', '114:6');
      }
    }
    expect(total, 6236);
  });
}
