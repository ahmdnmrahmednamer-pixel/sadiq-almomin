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
  static const _yunusDetailed =
      "\" أرأيتم \" قرأ أبو جعفر ونافع بتسهيل الهمزة الثانية بين بين، ولورش إبدالها ألفا مع إشباع المد للساكنين. وقرأ الكسائي بحذفها: والباقون باثباتها محققة. وإذا وقف حمزة فليس له إلا تسهيلها.";
  static List<BudurReference> references(int surah, String text) {
    if (surah == 4 && text == "\" نعما \" سبق الكلام عليه في البقرة.")
      return const [BudurReference(2, "فنعما", exactText: "\" فنعما \" قرأ ابن عامر وحمزة والكسائي وخلف بفتح النون وكسر العين، وقرأ ورش وابن كثير وحفص ويعقوب بكسر النون والعين، وقرأ أبو جعفر بكسر النون وإسكان العين. واختلف عن قالون والبصري وشعبة، فروي عنهم وجهان: الأول: كسر النون واختلاس كسرة العين وهذا هو الذي ذكره الشاطبي، الثاني: كسر النون وإسكان العين كقراءة أبي جعفر.\n\nوعلى هذا الوجه أكثر أهل الأداء وقد ذكره في التيسير فلا يضر عدم ذكره في الشاطبية إذ هو مذكور في أصلها. قال في النشر: والوجهان صحيحان عنهم وعلى هذا كان ينبغي للشاطبي ذكر هذا الوجه حيث إنه ذكره في التيسير. واتفق القراء على تشديد الميم.")];
    if (surah == 7 && text == "\" جاء أجلهم \" هو مثل جاء أحد، وسبق في سورة النساء.")
      return const [BudurReference(4, "أو جاء أحد", exactText: "\" أو جاء أحد \" قرأ قالون والبزي وأبو عمرو بإسقاط الهمزة الأولى مع المد والقصر، وهو أرجح لذهاب أثر الهمز كما تقدم.\r\nوقرأ ورش وقنبل وأبو جعفر ورويس بتسهيل الثانية بين بين، ولورش وقنبل أيضا إبدالها حرف مد من غير إشباع، أي بقدر ألف إذ لا ساكن بعده، والباقون بتحقيقهما، ولا يعتبر المد هنا مد بدل لورش كآمنوا لأن حرف المد عارض. وفي هذه الآية مد منفصل وهو يأيها ومرضى أو، فإذا قرأت لقالون أو البزي أو أبي عمرو بقصر المنفصل جاز لك في جاء أحد، القصر والمد. وإذا قرأت لقالون أو الدوري بمد المنفصل تعين المد في جاء أحد. لأننا إذا قلنا إن الهمزة الساقطة هي الأولى يكون المد حينئذ من قبيل المنفصل، فتجب التسوية بينهما.\r\nوإذا قلنا إن الساقطة هي الثانية يكون المد من قبيل المتصل، وحينئذ يتعين مده أيضا كما لا يخفى.")];
    if (surah == 29 && text == "\" يبدئ وينشئ \" فيه لهشام وحمزة وقفا ما في \" يستهزئ\" في البقرة.")
      return const [BudurReference(2, "يستهزئ", exactText: "\" يستهزئ \" فيه وأمثاله نحو يبرئ وينشئ عند الوقف لهشام وحمزة خمسة أوجه تقديرا وأربعة عمليا.\r\nالأول: إبدال الهمزة ياء ساكنة على القياس.\r\nالثاني: تسهيلها بين بين مع الروم.\r\nالثالث: إبدالها ياء مضمومة على الرسم وعلى مذهب الأخفش ثم تسكن للوقف فيتحد هذا الوجه مع الوجه الأول في العمل ويختلف في التقدير. الرابع: كالثالث ولكن مع الاشمام.\n\nالخامس: إبدالها ياء مضمومة أيضا مع الروم.")];
    if (surah == 58 && text == "\" اللائي \" سبق بسط الكلام عليه لجميع القراء وصلا ووقفا في سورة الأحزاب.")
      return const [BudurReference(33, "اللائي", exactText: "\" اللائي \" قرأ قالون وقنبل ويعقوب بهمزة مكسورة من غير ياء بعدها وصلا ووقفا، ولهم في الوقف عليه ما لهم في الوقف على نحو السماء من الأوجه. وقرأ البزي وأبو عمرو وصلا بتسهيل الهمزة بين بين مع المد والقصر عنهما إبدال الهمزة ياء ساكنة مع المد المشبع لالتقاء الساكنين وصلا أيضا. فإذا وقفا كان لهما ثلاثة أوجه: تسهيل الهمزة بالروم مع المد والقصر وإبدالها ياء ساكنة مع المد المشبع لالتقاء الساكنين أيضا. وقرأ ورش وأبو جعفر بتسهيل الهمزة بين بين مع المد والقصر وصلا فإذا وقفا كان لهما ثلاثة أوجه أيضا: بتسهيل الهمزة بالروم مع المد والقصر، وإبدالها ياء ساكنة مع التطويل وكل على أصله في مقدار المد، وقرأ الشامي والكوفيون بهمزة مكسورة بعدها ياء ساكنة وصلا ووقفا وهم على أصولهم في المد ولحمزة في الوقف عليه تسهيل الهمزة مع المد والقصر.")];
    if (surah == 65 && text == "\" واللائي معا \" تقدم الكلام عليه مبسوطا في سورة الأحزاب.")
      return const [BudurReference(33, "اللائي", exactText: "\" اللائي \" قرأ قالون وقنبل ويعقوب بهمزة مكسورة من غير ياء بعدها وصلا ووقفا، ولهم في الوقف عليه ما لهم في الوقف على نحو السماء من الأوجه. وقرأ البزي وأبو عمرو وصلا بتسهيل الهمزة بين بين مع المد والقصر عنهما إبدال الهمزة ياء ساكنة مع المد المشبع لالتقاء الساكنين وصلا أيضا. فإذا وقفا كان لهما ثلاثة أوجه: تسهيل الهمزة بالروم مع المد والقصر وإبدالها ياء ساكنة مع المد المشبع لالتقاء الساكنين أيضا. وقرأ ورش وأبو جعفر بتسهيل الهمزة بين بين مع المد والقصر وصلا فإذا وقفا كان لهما ثلاثة أوجه أيضا: بتسهيل الهمزة بالروم مع المد والقصر، وإبدالها ياء ساكنة مع التطويل وكل على أصله في مقدار المد، وقرأ الشامي والكوفيون بهمزة مكسورة بعدها ياء ساكنة وصلا ووقفا وهم على أصولهم في المد ولحمزة في الوقف عليه تسهيل الهمزة مع المد والقصر.")];
    if (surah == 28 && text == _qasasFirst)
      return const [BudurReference(21, 'أئمة')];
    if (surah == 28 && text == _qasasLater)
      return const [BudurReference(28, 'أئمة', exactText: _qasasFirst)];
    if (surah == 32 && text == _sajda)
      return const [BudurReference(28, 'أئمة', exactText: _qasasFirst)];
    if (surah == 11 && text == "\" أرأيتم \" سبق في يونس.")
      return const [BudurReference(10, 'أرأيتم', exactText: _yunusDetailed)];
    if (surah == 10 && text == "\" أرأيتم \" سبق قريبا.")
      return const [BudurReference(10, 'أرأيتم', exactText: _yunusDetailed)];
    if (surah == 30 &&
        text ==
            "\" يبدؤا \" فيه لحمزة وهشام وقفا خمسة أوجه تقدمت في تفتؤا بيوسف.")
      return const [BudurReference(12, 'تفتؤا')];
    if (surah == 18 && text == "\" للملائكة اسجدوا \" سبق في الإسراء مثله.")
      return const [BudurReference(17, 'للملائكة اسجدوا')];
    if (surah == 16 &&
        text ==
            "\" يتفيؤا \" قرأ البصريان بتاء التأنيث، والباقون بياء التذكير وفيه لهشام وحمزة وقفا ما في تفتؤا لرسم الهمزة على واو.")
      return const [BudurReference(12, 'تفتؤا')];
    if (surah == 24 && text == "\" ويدرؤا \" مثل: تفتؤا وقفا لحمزة وهشام.")
      return const [BudurReference(12, 'تفتؤا')];
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
