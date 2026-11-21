import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/core/services/quran_accessibility_service.dart';

void main() {
  for (final separator in ['\u2028', '\u2029']) {
    test(
        'spoken words stay separated across U+${separator.codeUnitAt(0).toRadixString(16)}',
        () {
      final input = 'قُلْ${separator}هُوَ';
      expect(QuranAccessibilityService.toScreenReaderText(input), 'قُلْ هُوَ');
      expect(
          QuranAccessibilityService.buildAyahSemanticLabel(
            surahName: 'الإخلاص',
            ayahNumber: 1,
            uthmaniText: input,
          ),
          'قُلْ هُوَ 1');
    });
  }
  test('mixed structural whitespace collapses without joining words', () {
    expect(
        QuranAccessibilityService.toScreenReaderText(
            '  قُلْ\n\u2028\t\u2029هُوَ  '),
        'قُلْ هُوَ');
  });
  test('format controls remain removable without inserting word breaks', () {
    expect(
        QuranAccessibilityService.toScreenReaderText('قُ\u200Cلْ\u202A\u202C'),
        'قُلْ');
  });
  test('existing intra-word hair-space before dagger-alef remains joined', () {
    expect(
        QuranAccessibilityService.toScreenReaderText(
            'ذَ\u200A\u0670\u2060لِكَ'),
        'ذَالِكَ');
  });
  test('vowels and current Quranic normalization remain unchanged', () {
    expect(
        QuranAccessibilityService.toScreenReaderText(
            'بِسۡمِ ٱللَّهِ ٱلرَّحۡمَـٰنِ ٱلرَّحِیمِ'),
        'بِسْمِ اللَّهِ الرَّحْمَانِ الرَّحِيمِ');
    expect(QuranAccessibilityService.toScreenReaderText(''), '');
  });
}
