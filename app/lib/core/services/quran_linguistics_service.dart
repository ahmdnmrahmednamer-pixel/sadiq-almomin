import 'quran_repository.dart';
import 'lubab_source.dart';
import 'package:flutter/foundation.dart';

class WordMeaning {
  final String word;
  final String meaning;
  final String? root;
  final String? note;

  const WordMeaning({
    required this.word,
    required this.meaning,
    this.root,
    this.note,
  });
}

class AsbabNuzul {
  final int surahId;
  final int ayahNumber;
  final String title;
  final String narration;
  final String source;
  final bool hasSpecificIncident;
  final bool hasSourceText;

  const AsbabNuzul({
    required this.surahId,
    required this.ayahNumber,
    required this.title,
    required this.narration,
    required this.source,
    this.hasSpecificIncident = true,
    this.hasSourceText = false,
  });
}

class WordGrammar {
  final String word;
  final String role;
  final String caseEnding;

  const WordGrammar({
    required this.word,
    required this.role,
    required this.caseEnding,
  });
}

class AyahGrammar {
  final int surahId;
  final int ayahNumber;
  final String summary;
  final String rhetoricSummary;
  final List<WordGrammar> words;

  const AyahGrammar({
    required this.surahId,
    required this.ayahNumber,
    required this.summary,
    this.rhetoricSummary = '',
    this.words = const [],
  });
}

class QuranLinguisticsResult {
  final int surahId;
  final int ayahNumber;
  final String ayahText;
  final List<WordMeaning> wordMeanings;
  final AsbabNuzul asbabNuzul;
  final AyahGrammar grammar;

  const QuranLinguisticsResult({
    required this.surahId,
    required this.ayahNumber,
    required this.ayahText,
    required this.wordMeanings,
    required this.asbabNuzul,
    required this.grammar,
  });

  String formatForShare(String surahName) {
    final buffer = StringBuffer();
    buffer.writeln('﴿$ayahText﴾');
    buffer.writeln('[سورة $surahName — آية $ayahNumber]\n');

    if (wordMeanings.isNotEmpty) {
      buffer.writeln('📖 معاني كلمات وغريب الآية:');
      for (final w in wordMeanings) {
        buffer.writeln('• ${w.word}: ${w.meaning}');
      }
      buffer.writeln();
    }

    buffer.writeln('نص المصدر (${asbabNuzul.source}):');
    buffer.writeln(asbabNuzul.narration);
    buffer.writeln();

    buffer.writeln('📐 الإعراب والدلالة النحوية:');
    buffer.writeln(grammar.summary);
    if (grammar.rhetoricSummary.isNotEmpty) {
      buffer.writeln('\n✨ البلاغة والبيان القرآني:');
      buffer.writeln(grammar.rhetoricSummary);
    }
    buffer.writeln('\nتطبيق صديق المؤمن');

    return buffer.toString();
  }
}

/// No generated religious explanations. Sources are connected only after review.
class QuranLinguisticsService {
  static LubabSource _source=LubabSource();
  @visibleForTesting static void setSourceForTesting(LubabSource? source){_source=source??LubabSource();}
  static Future<AsbabNuzul> _asbab(int surah,int ayah)async{
    try{
      final entries=await _source.fetch(surah,ayah);
      if(entries.isNotEmpty){
        final pages=entries.expand((e)=>e.pages).toSet().toList();
        return AsbabNuzul(surahId:surah,ayahNumber:ayah,title:'نص لباب النقول',
          narration:entries.map((e)=>e.text).join('\n\n'),
          source:'لباب النقول، السيوطي. ص ${pages.join("، ")}. الموسوعة القرآنية\n${LubabSource.sourceUrl}\nمقطع يبدأ بلفظ الآية وقد يشمل سياق ما بعدها. ليس حكمًا على صحة الرواية أو إثباتًا لسبب خاص.',
          hasSpecificIncident:false,hasSourceText:true);
      }
      return AsbabNuzul(surahId:surah,ayahNumber:ayah,title:'لباب النقول',
        narration:'لم يُثبت ربط هذا الموضع في الفهرس بعد. هذا لا يعني عدم وجود سبب نزول لهذه الآية.',
        source:'لباب النقول، السيوطي',hasSpecificIncident:false);
    }catch(_){
      return AsbabNuzul(surahId:surah,ayahNumber:ayah,title:'لباب النقول',
        narration:'تعذر تحميل نص المصدر أو تغيّرت نسخته. هذا لا يعني عدم وجود سبب نزول لهذه الآية.',
        source:'لباب النقول، السيوطي',hasSpecificIncident:false);
    }
  }
  static final Map<String, String> _ghareebDictionary = {
    'الصمد': 'السيد الذي يُصمد إليه في الحوائج، الكامل في سؤدده الذي تصمد إليه الخلائق في حوائجها، الغني عن كل أحد.',
    'أحد': 'المتفرد بالوحدانية في ذاته وأسمائه وصفاته، لا شبيه له ولا نظير.',
    'كفوا': 'مثيلاً ونظيراً ومكافئاً.',
    'الفلق': 'الصبح إذا انفلق ضوؤه عن الظلام، وكل ما فلقه الله وأبرزه من العدم.',
    'غاسق': 'الليل إذا أظلم ودخل بظلمته في كل شيء.',
    'وقب': 'دخل وغاب واشتدت ظلمته وركود ظلامه.',
    'النفاثات': 'السواحر اللاتي يعقدن الخيوط وينفخن فيها بغير ريق.',
    'العقد': 'عقد الخيوط والحبال التي يعقدها السحرة.',
    'الوسواس': 'الشيطان الذي يلقي الوسوسة والشبهات في القلب خفية.',
    'الخناس': 'الذي ينقبض ويتأخر ويختفي إذا ذُكر الله عز وجل.',
    'الكوثر': 'الخير الكثير الدائم في الدنيا والآخرة، ومنه نهر الكوثر في الجنة.',
    'شانئك': 'مبغضك وعدوك الكاره لما جئت به من الهدى.',
    'الأبتر': 'المقطوع من كل خير، الذي لا يبقى له ذكر حسن ولا أثر.',
    'تبت': 'خسرت وهلكت وضلت خسراناً مبيناً.',
    'وتب': 'تحقق هلاكه وخسرانه التام.',
    'جيدها': 'عنقها ورقبتها.',
    'مسد': 'حبل محكم الفتل من ليف خشن أو سلاسل من نار.',
    'حمالة الحطب': 'أم جميل امرأة أبي لهب، كانت تحمل الشوك وتلقيه في طريق النبي ﷺ، وتمشي بالنميمة.',
    'سجى': 'سكن واستقر واشتد ظلامه.',
    'ما ودعك': 'ما تركك ربك وما أهملك منذ اختارك.',
    'ما قلى': 'وما أبغضك ربك قط.',
    'عائلا': 'فقيراً ذا عيال لا مال له.',
    'تقهر': 'لا تظلم اليتيم ولا تستضعفه ولا تأخذ حقه.',
    'تنهر': 'لا تزجر السائل المستستر ولا ترده بغلظة.',
    'سنة': 'النعاس الخفيف والفتور الذي يسبق النوم.',
    'القيوم': 'القائم بنفسه المقيم لشؤون خلقه وتدبير الكون.',
    'يؤوده': 'يثقله أو يعجزه أو يشق عليه.',
    'كرسيه': 'موضع قدمي الرب جل جلاله، وقد وسع السماوات والأرض.',
    'المفلحون': 'الفائزون بمطلوبهم، الناجون من مرهوبهم في الدنيا والآخرة.',
    'الغيب': 'كل ما غاب عن الحواس مما أخبر الله به كالملائكة والجنة والنار والقدر.',
    'طغيانهم': 'تجاوزهم الحد في الكفر والظلم والعتو.',
    'يعمهون': 'يترددون في الضلالة متحيرين لا يهتدون سبيلاً.',
    'صيب': 'المطر النازل من السحاب بقوة وتتابع.',
    'برق': 'الضوء اللامع الخاطف في السحاب.',
    'الفرقان': 'القرآن الفارق بين الحق والباطل والهدى والضلال.',
    'قنوت': 'الطاعة الدائمة والخشوع وطول القيام لله.',
    'الألباب': 'العقول الصافية الخالصة من شوائب الهوى.',
    'المتقين': 'الذين اتقوا سخط الله بفعل أوامره واجتناب نواهيه.',
    'الهدى': 'البيان والدلالة الموصلة إلى الحق والرشاد.',
    'العروة الوثقى': 'العقد المحكم الوثيق الذي لا ينفصم، وهو التوحيد والإسلام.',
    'الطاغوت': 'كل ما عُبد من دون الله أو تُجاوز به الحد من شيطان أو صنم أو هوى.',
    'القيام': 'النهوض بالحق وإقامة الصلاة بأركانها وخشوعها.',
    'الرحمن': 'ذو الرحمة الواسعة الشاملة لجميع الخلائق في الدنيا وللمؤمنين في الآخرة.',
    'الرحيم': 'الموصل رحمته الخاصة لعباده المؤمنين يوم القيامة.',
    'الصراط': 'الطريق الواسع المستقيم الواضح الذي لا اعوجاج فيه.',
    'المغضوب عليهم': 'من علموا الحق وحادوا عنه عمداً واستكباراً.',
    'الضالين': 'من عبدوا الله على جهل وضلالة بغير هدىً من الله.',
  };


  static Future<QuranLinguisticsResult> getDetails({
    required int surahId, required int ayahNumber,
  }) async {
    final ayah = await QuranRepository.getAyah(surahId, ayahNumber);
    return QuranLinguisticsResult(
      surahId: surahId, ayahNumber: ayahNumber,
      ayahText: ayah?.cleanTextUthmani ?? '', wordMeanings: _extractWordMeanings(ayah?.cleanTextUthmani ?? ''),
      asbabNuzul: await _asbab(surahId,ayahNumber),
      grammar: AyahGrammar(surahId:surahId, ayahNumber:ayahNumber,
        summary:'الجدول في إعراب القرآن الكريم، محمود صافي. افتح صفحات المصدر لقراءة الإعراب في سياقه.'),
    );
  }
  /// Extracts difficult words and lexicon meanings for an ayah
  static List<WordMeaning> _extractWordMeanings(String text) {
    final List<WordMeaning> results = [];
    final cleaned = text.replaceAll(RegExp(r'[ًٌٍَُِّْـٰۖۗۚۛۜ۝۞]'), '');
    final tokens = cleaned.split(RegExp(r'\s+'));

    for (final rawToken in tokens) {
      final token = _normalizeToken(rawToken);
      if (token.isEmpty) continue;

      for (final entry in _ghareebDictionary.entries) {
        if (token == entry.key || token.contains(entry.key) || entry.key.contains(token)) {
          if (!results.any((r) => r.word == entry.key)) {
            results.add(WordMeaning(
              word: entry.key,
              meaning: entry.value,
            ));
          }
        }
      }
    }

    return results;
  }

  static String _normalizeToken(String word) {
    return word
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ٱ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll(RegExp(r'[^ء-ي]'), '')
        .trim();
  }

}
