import 'package:flutter/foundation.dart';

/// نموذج القارئ الإمام من القراء العشرة
class QiraatReciter {
  final int orderNumber;
  final String name;
  final String fullBiography;
  final String city; // المدينة، مكة، البصرة، دمشق، الكوفة
  final int deathYearHijri;
  final String individualCode; // رمز الشاطبية الفردي (أ، د، ح، ك، ن، ف، ر...)
  final String durrahCode; // رمز الدرة للقراء الثلاثة المتممين
  final List<QiraatNarrator> narrators;

  const QiraatReciter({
    required this.orderNumber,
    required this.name,
    required this.fullBiography,
    required this.city,
    required this.deathYearHijri,
    required this.individualCode,
    this.durrahCode = '',
    required this.narrators,
  });
}

/// نموذج الراوي عن الإمام
class QiraatNarrator {
  final String name;
  final String code; // رمزه في الشاطبية أو الدرة
  final String title;
  final int deathYearHijri;
  final String characteristics;

  const QiraatNarrator({
    required this.name,
    required this.code,
    required this.title,
    required this.deathYearHijri,
    required this.characteristics,
  });
}

/// نموذج رمز القراءات (حرفي أو كلمي، فردي أو جمعي)
class QiraatSymbol {
  final String symbol;
  final String representation;
  final String type; // 'فردي' أو 'جمعي'
  final String poemSource; // 'الشاطبية (حرز الأماني)' أو 'الدرة المضية'
  final String examplePoemLine;

  const QiraatSymbol({
    required this.symbol,
    required this.representation,
    required this.type,
    required this.poemSource,
    required this.examplePoemLine,
  });
}

/// أصل من أصول القراءات العشر
class QiraatUsulRule {
  final String id;
  final String title;
  final String explanation;
  final String exampleQuranic;
  final String applicableReciters;

  const QiraatUsulRule({
    required this.id,
    required this.title,
    required this.explanation,
    required this.exampleQuranic,
    required this.applicableReciters,
  });
}

/// فرق قرائي فرشي في سورة من سور القرآن
class QiraatSurahDifference {
  final int surahNumber;
  final String surahName;
  final int ayahNumber;
  final String ayahFragment;
  final String readingHafs;
  final String otherReadings;
  final String explanationAndTawjih;

  const QiraatSurahDifference({
    required this.surahNumber,
    required this.surahName,
    required this.ayahNumber,
    required this.ayahFragment,
    required this.readingHafs,
    required this.otherReadings,
    required this.explanationAndTawjih,
  });
}

/// خدمة مصحف الصحابة في القراءات العشر المتواترة من طريق الشاطبية والدرة
/// مستخرجة من المرجع المعتمد: «مصحف القراءات.pdf» (إعداد جمال الدين محمد شرف)
class QiraatService extends ChangeNotifier {
  static final QiraatService instance = QiraatService._internal();
  QiraatService._internal();

  static const String bookTitle =
      'مصحف الصحابة في القراءات العشر المتواترة من طريق الشاطبية والدرة';
  static const String authorName = 'الشيخ جمال الدين محمد شرف';
  static const String bookDescription =
      'المرجع الشامل المحقق لبيان القراءات العشر المتواترة لجميع سور وآيات القرآن الكريم، '
      'يجمع بين طريقي الشاطبية (القراءات السبع) والدرة المضية (القراءات الثلاث المتممة للعشر)، '
      'مع بيان الرموز وأصول القراءات وتوجيه المعاني والبلاغة.';

  /// أئمة القراءات العشر ورواتهم العشرين
  static const List<QiraatReciter> reciters = [
    QiraatReciter(
      orderNumber: 1,
      name: 'الإمام نافع المدني',
      city: 'المدينة المنورة',
      deathYearHijri: 169,
      individualCode: 'أ',
      fullBiography:
          'نافع بن عبد الرحمن بن أبي نعيم المدني، إمام دار الهجرة وأحد القراء السبعة المشهورين، تلقى القراءة عن سبعين من التابعين.',
      narrators: [
        QiraatNarrator(
          name: 'قالون',
          code: 'ب',
          title: 'عيسى بن مينا المدني',
          deathYearHijri: 220,
          characteristics: 'صلة ميم الجمع مع الإسكان، قصر المنفصل وتوسطه، وتسهيل الهمزتين من كلمتين.',
        ),
        QiraatNarrator(
          name: 'ورش',
          code: 'ج',
          title: 'عثمان بن سعيد المصري',
          deathYearHijri: 197,
          characteristics: 'نقل حركة الهمز إلى الساكن قبله، ترقيق الراءات، تغليظ اللامات، وتثليث البدل.',
        ),
      ],
    ),
    QiraatReciter(
      orderNumber: 2,
      name: 'الإمام ابن كثير المكي',
      city: 'مكة المكرمة',
      deathYearHijri: 120,
      individualCode: 'د',
      fullBiography:
          'عبد الله بن كثير الداري المكي، إمام أهل مكة في القراءة، لقي عدداً من الصحابة كعبد الله بن الزبير وأنس بن مالك.',
      narrators: [
        QiraatNarrator(
          name: 'البزي',
          code: 'هـ',
          title: 'أحمد بن محمد بن عبد الله',
          deathYearHijri: 250,
          characteristics: 'صلة هاء الضمير وميم الجمع قولاً واحداً، وإثبات ياءات الزوائد وصلاً ووقفاً.',
        ),
        QiraatNarrator(
          name: 'قنبل',
          code: 'ز',
          title: 'محمد بن عبد الرحمن المخزومي',
          deathYearHijri: 291,
          characteristics: 'موافقة البزي في الأصول مع بعض الفروق في إبدال الهمز والسين في الصراط.',
        ),
      ],
    ),
    QiraatReciter(
      orderNumber: 3,
      name: 'الإمام أبو عمرو البصري',
      city: 'البصرة',
      deathYearHijri: 154,
      individualCode: 'ح',
      fullBiography:
          'زبان بن العلاء البصري، أعلم الناس بالقرآن والعربية والشعر في زمانه، أخذ القراءة بمكة والمدينة والكوفة والبصرة.',
      narrators: [
        QiraatNarrator(
          name: 'الدوري',
          code: 'ط',
          title: 'حفص بن عمر الدوري',
          deathYearHijri: 246,
          characteristics: 'قصر المنفصل وتوسطه، إمالة التوراة وهاء التأنيث في الوقف، والإدغام الكبير.',
        ),
        QiraatNarrator(
          name: 'السوسي',
          code: 'ي',
          title: 'صالح بن زياد السوسي',
          deathYearHijri: 261,
          characteristics: 'انفراده بالإدغام الكبير في المتماثلين والمتجانسين والمتقاربين، وإبدال الهمز الساكن.',
        ),
      ],
    ),
    QiraatReciter(
      orderNumber: 4,
      name: 'الإمام ابن عامر الشامي',
      city: 'دمشق (الشام)',
      deathYearHijri: 118,
      individualCode: 'ك',
      fullBiography:
          'عبد الله بن عامر اليحصبي، إمام أهل الشام وقاضي دمشق في عهد الوليد بن عبد الملك، قرأ على الصحابي الجليل عثمان بن عفان وأبي الدرداء.',
      narrators: [
        QiraatNarrator(
          name: 'هشام',
          code: 'ل',
          title: 'هشام بن عمار الدمشقي',
          deathYearHijri: 245,
          characteristics: 'تسهيل الهمز وإبداله في الوقف، والإمالة في بعض الأفعال.',
        ),
        QiraatNarrator(
          name: 'ابن ذكوان',
          code: 'م',
          title: 'عبد الله بن أحمد بن ذكوان',
          deathYearHijri: 242,
          characteristics: 'السكت على الساكن قبل الهمز في المفصول، وتوسط المنفصل وإشباع المتصل.',
        ),
      ],
    ),
    QiraatReciter(
      orderNumber: 5,
      name: 'الإمام عاصم الكوفي',
      city: 'الكوفة',
      deathYearHijri: 127,
      individualCode: 'ن',
      fullBiography:
          'عاصم بن بهدلة أبي النجود الأسدي، شيخ الإقراء بالكوفة، جمع بين الفصاحة والإتقان وحسن الصوت والتجويد.',
      narrators: [
        QiraatNarrator(
          name: 'شعبة',
          code: 'ص',
          title: 'أبو بكر شعبة بن عياش',
          deathYearHijri: 193,
          characteristics: 'إمالة بعض الألفات، والسكت على عوجا ومرقدنا، ومخالفة حفص في بعض فرش الحروف.',
        ),
        QiraatNarrator(
          name: 'حفص',
          code: 'ع',
          title: 'حفص بن سليمان الكوفي',
          deathYearHijri: 180,
          characteristics: 'الرواية الأكثر انتشاراً وشهرة في العالم الإسلامي، تمتاز بالتحقيق والوضوح وعدم الإمالة إلا في مجراها.',
        ),
      ],
    ),
    QiraatReciter(
      orderNumber: 6,
      name: 'الإمام حمزة الكوفي',
      city: 'الكوفة',
      deathYearHijri: 156,
      individualCode: 'ف',
      fullBiography:
          'حمزة بن حبيب الزيات الكوفي، الإمام الورع العابد المتقن، انتهت إليه مشيخة الإقراء بالكوفة بعد عاصم والأعمش.',
      narrators: [
        QiraatNarrator(
          name: 'خلف عن حمزة',
          code: 'ض',
          title: 'خلف بن هشام البزار',
          deathYearHijri: 229,
          characteristics: 'السكت على الساكن المفصول والموصول (الم وشيء)، وإشمام الصراط في الفاتحة، والإدغام بلا غنة.',
        ),
        QiraatNarrator(
          name: 'خلاد',
          code: 'ق',
          title: 'خلاد بن خالد الكوفي',
          deathYearHijri: 220,
          characteristics: 'ترك السكت على المفصول وتخصيصه بشيء والموصول، وإشمام الحرف الأول من الصراط.',
        ),
      ],
    ),
    QiraatReciter(
      orderNumber: 7,
      name: 'الإمام الكسائي الكوفي',
      city: 'الكوفة / بغداد',
      deathYearHijri: 189,
      individualCode: 'ر',
      fullBiography:
          'علي بن حمزة الكسائي، إمام النحاة بالكوفة وسابع القراء السبعة، مؤدب الأمين والمأمون ابني هارون الرشيد.',
      narrators: [
        QiraatNarrator(
          name: 'أبو الحارث',
          code: 'س',
          title: 'الليث بن خالد البغدادي',
          deathYearHijri: 240,
          characteristics: 'إمالة هاء التأنيث وما قبلها في الوقف بشروطها، وإمالة ذوات الياء والألفات المنقلبة.',
        ),
        QiraatNarrator(
          name: 'الدوري عن الكسائي',
          code: 'ت',
          title: 'حفص بن عمر الدوري (نفس راوي أبي عمرو)',
          deathYearHijri: 246,
          characteristics: 'موافقة أبي الحارث في أكثر الأصول مع إمالة بعض الأسماء والأفعال المخصوصة.',
        ),
      ],
    ),
    QiraatReciter(
      orderNumber: 8,
      name: 'الإمام أبو جعفر المدني',
      city: 'المدينة المنورة',
      deathYearHijri: 130,
      individualCode: 'أ (في الدرة)',
      durrahCode: 'أ',
      fullBiography:
          'يزيد بن القعقاع المخزومي، إمام القراءة بالمدينة المنورة وأحد التابعين الكبار، قرأ على عبد الله بن عباس وأبي هريرة.',
      narrators: [
        QiraatNarrator(
          name: 'ابن وردان',
          code: 'ب (الدرة)',
          title: 'عيسى بن وردان المدني',
          deathYearHijri: 160,
          characteristics: 'تسهيل الهمزتين، صلة ميم الجمع، الإخفاء عند الغين والخاء، وإبدال الهمز الساكن.',
        ),
        QiraatNarrator(
          name: 'ابن جماز',
          code: 'ج (الدرة)',
          title: 'سليمان بن محمد بن جماز',
          deathYearHijri: 170,
          characteristics: 'موافقة ابن وردان غالباً في الأصول مع خلافات يسيرة في فرش الحروف.',
        ),
      ],
    ),
    QiraatReciter(
      orderNumber: 9,
      name: 'الإمام يعقوب الحضرمي',
      city: 'البصرة',
      deathYearHijri: 205,
      individualCode: 'د (في الدرة)',
      durrahCode: 'د',
      fullBiography:
          'يعقوب بن إسحاق الحضرمي البصري، إمام أهل البصرة في زمانه بعد أبي عمرو، انتهت إليه رئاسة الإقراء.',
      narrators: [
        QiraatNarrator(
          name: 'رويس',
          code: 'هـ (الدرة)',
          title: 'محمد بن المتوكل البصري',
          deathYearHijri: 238,
          characteristics: 'الوقف على هاء السكت في جمع المذكر والمؤنث وما الاستفهامية، وتسهيل الهمز.',
        ),
        QiraatNarrator(
          name: 'روح',
          code: 'ز (الدرة)',
          title: 'روح بن عبد المؤمن البصري',
          deathYearHijri: 235,
          characteristics: 'موافقة رويس في أكثر الأصول مع تحقيق بعض الهمزات وترك الإدغام في بعض المواضع.',
        ),
      ],
    ),
    QiraatReciter(
      orderNumber: 10,
      name: 'الإمام خلف العاشر',
      city: 'بغداد / الكوفة',
      deathYearHijri: 229,
      individualCode: 'ح (في الدرة)',
      durrahCode: 'ح',
      fullBiography:
          'خلف بن هشام البزار (نفسه راوي حمزة)، اختار لنفسه قراءة مستندة إلى أئمة القراءة، متمماً للقراءات العشر المتواترة.',
      narrators: [
        QiraatNarrator(
          name: 'إسحاق',
          code: 'ط (الدرة)',
          title: 'إسحاق بن إبراهيم الوراق',
          deathYearHijri: 286,
          characteristics: 'قراءة خلف باختياره، تتفق مع أصول الكوفيين وحمزة وعاصم دون السكت على المفصول.',
        ),
        QiraatNarrator(
          name: 'إدريس',
          code: 'ي (الدرة)',
          title: 'إدريس بن عبد الكريم الحداد',
          deathYearHijri: 292,
          characteristics: 'السكت على الساكن قبل الهمز اختياراً، وموافقة إسحاق في عامة الفرش والأصول.',
        ),
      ],
    ),
  ];

  /// رموز الشاطبية والدرة الجماعية والفردية
  static const List<QiraatSymbol> symbols = [
    QiraatSymbol(
      symbol: 'أ ب ج',
      representation: 'أ = نافع، ب = قالون، ج = ورش',
      type: 'فردي',
      poemSource: 'الشاطبية',
      examplePoemLine: 'جَعَلْتُ أَبَا جَادٍ عَلَى كُلِّ قَارِئٍ ... دَلِيلاً عَلَى المَنْظُومِ أَوَّلَ أَوَّلا',
    ),
    QiraatSymbol(
      symbol: 'د هـ ز',
      representation: 'د = ابن كثير، هـ = البزي، ز = قنبل',
      type: 'فردي',
      poemSource: 'الشاطبية',
      examplePoemLine: 'فَنَافِعٌ الطِّيبُ حَوَى أَبَا جَادٍ ... وَدَلَّ عَلَى المَكِّيِّ هَادٍ وَزَادَ لا',
    ),
    QiraatSymbol(
      symbol: 'ح ط ي',
      representation: 'ح = أبو عمرو، ط = الدوري، ي = السوسي',
      type: 'فردي',
      poemSource: 'الشاطبية',
      examplePoemLine: 'وَأَبُو عَمْرٍو حَصَّلَ حُطِّي بِلَفْظِهَا ... فَطَوْرًا يُنَادِي بِالدُّورِيِّ فَتَكْمُلا',
    ),
    QiraatSymbol(
      symbol: 'ك ل م',
      representation: 'ك = ابن عامر، ل = هشام، م = ابن ذكوان',
      type: 'فردي',
      poemSource: 'الشاطبية',
      examplePoemLine: 'وَابْنُ عَامِرٍ الشَّامِي كَلِمٌ رَمْزُهُ ... وَفِي هِشَامٍ وَابْنِ ذَكْوَانَ نُزِّلا',
    ),
    QiraatSymbol(
      symbol: 'ن ص ع',
      representation: 'ن = عاصم، ص = شعبة، ع = حفص',
      type: 'فردي',
      poemSource: 'الشاطبية',
      examplePoemLine: 'وَعَاصِمٌ الكُوفِيُّ نَصَعَ رَمْزُهُ ... وَبِشُعْبَةَ وَحَفْصٍ ضِيَاءٌ تَهَلَّلا',
    ),
    QiraatSymbol(
      symbol: 'ف ض ق',
      representation: 'ف = حمزة، ض = خلف، ق = خلاد',
      type: 'فردي',
      poemSource: 'الشاطبية',
      examplePoemLine: 'وَحَمْزَةُ فَضَقٌ تَلَتْهُ رُوَاتُهُ ... وَفِي خَلَفٍ وَخَلاَّدٍ ضِيَاءٌ تَأَمَّلا',
    ),
    QiraatSymbol(
      symbol: 'ر س ت',
      representation: 'ر = الكسائي، س = أبو الحارث، ت = الدوري عن الكسائي',
      type: 'فردي',
      poemSource: 'الشاطبية',
      examplePoemLine: 'وَأَمَّا عَلِيٌّ فَالْكِسَائِيُّ رَمْزُهُ ... رَسَتْ بِأَبِي الحَارِثِ وَالدُّورِيِّ أَنْبُلا',
    ),
    QiraatSymbol(
      symbol: 'سما',
      representation: 'أهل الحجاز والشام والبصرة (نافع وابن كثير وأبو عمرو)',
      type: 'جمعي',
      poemSource: 'الشاطبية',
      examplePoemLine: 'وَسَمَّى سَمَا لِلْمَدَنِي وَابْنِ كَثِيرِهِمْ ... وَلِلْبَصْرِيِّ الحَبْرِ العَلِيمِ تَأَصَّلا',
    ),
    QiraatSymbol(
      symbol: 'شفا',
      representation: 'حمزة والكسائي وخلف العاشر (أهل الكوفة عدا عاصم)',
      type: 'جمعي',
      poemSource: 'الشاطبية',
      examplePoemLine: 'وَشَفَا لِحَمْزَةَ وَالكِسَائِي حَيْثُ جَا ... مَعَ خَلَفٍ يَرْوُونَ عِلْمًا مُفَصَّلا',
    ),
    QiraatSymbol(
      symbol: 'حق',
      representation: 'ابن كثير وأبو عمرو',
      type: 'جمعي',
      poemSource: 'الشاطبية',
      examplePoemLine: 'وَحَقٌّ لِمَكِّيٍّ وَبَصْرِيٍّ كِلاَهُمَا ... بِهِ يُعْرَفُ الحَقُّ الصَّرِيحُ مُجَمَّلا',
    ),
    QiraatSymbol(
      symbol: 'نفر',
      representation: 'ابن كثير وأبو عمرو وابن عامر',
      type: 'جمعي',
      poemSource: 'الشاطبية',
      examplePoemLine: 'وَنَفَرٌ حَوَى المَكِّيَّ وَالبَصْرِيَّ مَعًا ... وَالشَّامِيَّ بِالفَضْلِ الكَبِيرِ مُجَلَّلا',
    ),
  ];

  /// أهم أصول القراءات العشر
  static const List<QiraatUsulRule> usulRules = [
    QiraatUsulRule(
      id: 'usul_basmalah',
      title: 'البسملة بين السورتين',
      explanation:
          'لقالون وابن كثير وعاصم والكسائي وأبي جعفر الفصل بالبسملة وجوباً، ولحمزة وخلف العاشر الوصل بلا بسملة، ولهشام وابن ذكوان والدوري والسوسي وورش ويعقوب ثلاثة أوجه: الفصل بالبسملة، والسكت بلا بسملة، والوصل بلا بسملة.',
      exampleQuranic: 'بين سورتي الفاتحة والبقرة أو الضحى والشرح',
      applicableReciters: 'جميع القراء العشرة',
    ),
    QiraatUsulRule(
      id: 'usul_meem_jam',
      title: 'ميم الجمع',
      explanation:
          'يضمها ويصلها بواو لفظية ابن كثير وأبو جعفر ووريس وقالون (بخلف عنه) إذا وقع بعدها ساكن أو متحرك، ويسكنها الباقون.',
      exampleQuranic: '﴿عَلَيْهِمْ غَيْرِ المَغْضُوبِ عَلَيْهِمْ﴾ تُقرأ: «عَلَيْهِمُو»',
      applicableReciters: 'ابن كثير، أبو جعفر، قالون، رويس',
    ),
    QiraatUsulRule(
      id: 'usul_idgham_kabir',
      title: 'الإدغام الكبير',
      explanation:
          'إدغام المتحرك في المتحرك إذا التقى مثلان أو متقاربان أو متجانسان، ينفرد به السوسي عن أبي عمرو ووافقه أبو جعفر ويعقوب في بعض المواضع.',
      exampleQuranic: '﴿الرَّحْمَنِ الرَّحِيمِ * مَالِكِ﴾ تُقرأ: «الرَّحِيمِ مَّالِكِ» بإدغام الميم في الميم',
      applicableReciters: 'السوسي، أبو عمرو، يعقوب',
    ),
    QiraatUsulRule(
      id: 'usul_madd',
      title: 'المد المنفصل والمتصل',
      explanation:
          'يشبع المتصل والمنفصل (٦ حركات) حمزة وورش، ويتوسط المتصل والمنفصل (٤ حركات) عاصم وابن عامر والكسائي وخلف، ويقصر المنفصل (حركتان) ابن كثير والسوسي وأبو جعفر ويعقوب، ولقالون والدوري الوجهان (القصر والتوسط).',
      exampleQuranic: '﴿يَا أَيُّهَا الَّذِينَ آمَنُوا﴾ و ﴿السَّمَاءِ﴾',
      applicableReciters: 'مراتب المد عند القراء العشرة',
    ),
    QiraatUsulRule(
      id: 'usul_imalah',
      title: 'الإمالة والتقليل (بين اللفظين)',
      explanation:
          'الإمالة الكبرى قراءة حمزة والكسائي وخلف في ذوات الياء، والتقليل (بين بين) قراءة ورش وأبي عمرو في رؤوس الآي ورعاية الفواصل.',
      exampleQuranic: '﴿وَالضُّحَى﴾، ﴿وَاللَّيْلِ إِذَا سَجَى﴾، ﴿مَا وَدَّعَكَ رَبُّكَ وَمَا قَلَى﴾',
      applicableReciters: 'حمزة، الكسائي، خلف، ورش، أبو عمرو',
    ),
  ];

  /// نماذج من فرش الحروف لاختلاف القراءات المتواترة
  static const List<QiraatSurahDifference> famousDifferences = [
    QiraatSurahDifference(
      surahNumber: 1,
      surahName: 'الفاتحة',
      ayahNumber: 4,
      ayahFragment: '﴿مَالِكِ يَوْمِ الدِّينِ﴾',
      readingHafs: '«مَالِكِ» بألف بعد الميم (اسم فاعل من الملك بكسر الميم)',
      otherReadings: 'قرأ نافع وابن كثير وأبو عمرو وابن عامر وأبو جعفر ويعقوب: «مَلِكِ» بغير ألف (صفة مشبهة من المُلْك بضم الميم)',
      explanationAndTawjih: 'القراءتان متواتران ولهما كمال البلاغة؛ «مَالِك» تدل على تمام التصرف في الملكيات يوم القيامة، و«مَلِك» تدل على تمام الأمر والنهي والسلطان على الخلائق.',
    ),
    QiraatSurahDifference(
      surahNumber: 1,
      surahName: 'الفاتحة',
      ayahNumber: 6,
      ayahFragment: '﴿اهْدِنَا الصِّرَاطَ الْمُسْتَقِيمَ﴾',
      readingHafs: '«الصِّرَاطَ» بالصاد الخالصة',
      otherReadings: 'قرأ قنبل عن ابن كثير ورويس عن يعقوب: «السِّرَاطَ» بالسين الخالصة، وقرأ خلف عن حمزة بالإشمام (خلط صوت الصاد بالزاي: الزِّراط).',
      explanationAndTawjih: 'الصراط في لغة العرب مأخوذ من السرط وهو الابتلاع؛ فـ«السراط» أصل اللغة، و«الصراط» إبدال لتناسب الطاء المستعلية، والإشمام لغة قيس وتميم.',
    ),
    QiraatSurahDifference(
      surahNumber: 2,
      surahName: 'البقرة',
      ayahNumber: 9,
      ayahFragment: '﴿يُخَادِعُونَ اللَّهَ وَالَّذِينَ آمَنُوا وَمَا يَخْدَعُونَ إِلَّا أَنْفُسَهُمْ﴾',
      readingHafs: '«وَمَا يَخْدَعُونَ» بفتح الياء وسكون الخاء وفتح الدال من الثلاثي',
      otherReadings: 'قرأ نافع وابن كثير وأبو عمرو: «وَمَا يُخَادِعُونَ» بضم الياء وألف بعد الخاء وكسر الدال من باب المفاعلة',
      explanationAndTawjih: '«يخادعون» الأولى تفيد محاولتهم المكر والخداع، و«يخدعون» تفيد تحقق الخدعة وأن وبالها واقع عليهم حصراً لا يتعداهم.',
    ),
    QiraatSurahDifference(
      surahNumber: 3,
      surahName: 'آل عمران',
      ayahNumber: 13,
      ayahFragment: '﴿يَرَوْنَهُمْ مِثْلَيْهِمْ رَأْيَ الْعَيْنِ﴾',
      readingHafs: '«يَرَوْنَهُمْ» بياء الغيبة (أي يرى المشركون المؤمنين مثلي عددهم)',
      otherReadings: 'قرأ نافع ويعقوب: «تَرَوْنَهُمْ» بتاء الخطاب (أي ترون أنتم أيها المسلمون الكفار مثلي عددهم)',
      explanationAndTawjih: 'في الأولى إلقاء الرعب في قلوب الكفار حين رأوا المسلمين أضعافاً، وفي الثانية تثبيت للمؤمنين حين قلل الله المشركين في أعينهم.',
    ),
  ];
}
