import '../models/ayah.dart';
import '../models/surah.dart';
import 'budur_source.dart';
import 'budur_verse_linker.dart';

/// Only independently inspected, explicit author references are enabled.
/// A reference opens original source context, never a generated ruling.
class BudurReference {
  final int surah;
  final String quote;
  final String? exactText;
  const BudurReference(this.surah, this.quote, {this.exactText});
}

class BudurReferenceResolver {
  static const _qasasFirst = "\" أئمة \" تقدم نظيره في سورة الأنبياء.";
  static const _qasasLater = "\" أئمة \" تقدم أول السورة.";
  static const _sajda = "\" أئمة \" سبق حكمها قريبا في القصص.";
  static List<BudurReference> references(int surah, String text) {
    if (surah == 28 && text == _qasasFirst)
      return const [BudurReference(21, 'أئمة')];
    if (surah == 28 && text == _qasasLater)
      return const [BudurReference(28, 'أئمة', exactText: _qasasFirst)];
    if (surah == 32 && text == _sajda)
      return const [BudurReference(28, 'أئمة', exactText: _qasasFirst)];
    final quotes = BudurVerseLinker.quotes(text);
    if (quotes.length != 1) return const [];
    final q = quotes.single;
    bool isQuote(String value) => q == BudurVerseLinker.normalize(value);
    if ((surah == 3 || surah == 5) &&
        isQuote('وأبرئ') &&
        text.contains('يستهزئ بالبقرة'))
      return const [BudurReference(2, 'يستهزئ')];
    if (surah == 13 && isQuote('وينشئ') && text.contains('يستهزئ بالبقرة'))
      return const [BudurReference(2, 'يستهزئ')];
    if (surah == 34 && isQuote('يبدئ') && text.contains('يستهزئ بالبقرة'))
      return const [BudurReference(2, 'يستهزئ')];
    if ((surah == 5 || surah == 6) &&
        isQuote('فمن اضطر') &&
        text.contains('سورة البقرة'))
      return const [BudurReference(2, 'فمن اضطر')];
    if (surah == 21 &&
        isQuote('أف لكم') &&
        text.contains('تقدم في سورة الإسراء'))
      return const [BudurReference(17, 'أف')];
    if (surah == 21 && isQuote('أئمة') && text.contains('تقدم في سورة التوبة'))
      return const [BudurReference(9, 'أئمة')];
    if (surah == 23 && isQuote('نسقيكم') && text.contains('تقدم في سورة النحل'))
      return const [BudurReference(16, 'نسقيكم')];
    if (surah == 53 &&
        isQuote('النشأة') &&
        text.contains('تقدم في سورة العنكبوت'))
      return const [BudurReference(29, 'النشأة')];
    if (surah == 56 && isQuote('النشأة') && text.contains('تقدم في سورة النجم'))
      return const [BudurReference(53, 'النشأة')];
    return const [];
  }

  static BudurPassage? resolve(
      String source, BudurReference reference, Surah surah, List<Ayah> ayahs) {
    if (surah.id != reference.surah) return null;
    final q = BudurVerseLinker.normalize(reference.quote);
    final matches = BudurSource.passages(source, surah, ayahs).where((p) {
      final qs = BudurVerseLinker.quotes(p.text);
      return qs.length == 1 &&
          qs.single == q &&
          (reference.exactText == null || p.text == reference.exactText);
    }).toList();
    // Never silently choose the first of several possible source entries.
    return matches.length == 1 ? matches.single : null;
  }
}
