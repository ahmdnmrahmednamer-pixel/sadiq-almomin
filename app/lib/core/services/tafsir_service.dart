import 'quran_repository.dart';

class TafsirEdition {
  final String id;
  final String nameAr;
  final String authorAr;
  final String description;

  const TafsirEdition({
    required this.id,
    required this.nameAr,
    required this.authorAr,
    required this.description,
  });
}

class TafsirResult {
  final String editionId;
  final String editionName;
  final String author;
  final int surahId;
  final int ayahNumber;
  final String ayahText;
  final String tafsirText;
  final bool hasSourceText;

  const TafsirResult({
    required this.editionId,
    required this.editionName,
    required this.author,
    required this.surahId,
    required this.ayahNumber,
    required this.ayahText,
    required this.tafsirText,
    this.hasSourceText = true,
  });

  /// Formatted text for copying and sharing per FR-TAF-005
  String formatForShare(String surahName) {
    return '﴿$ayahText﴾\n[سورة $surahName، الآية $ayahNumber]\n\n'
        '📖 من $editionName ($author):\n'
        '$tafsirText\n\n'
        'تطبيق صديق المؤمن';
  }
}

class TafsirService {
  static const List<TafsirEdition> availableEditions = [
    TafsirEdition(
      id: 'muyassar',
      nameAr: 'التفسير الميسر',
      authorAr: 'نخبة من العلماء بإشراف مجمع الملك فهد',
      description: 'تفسير مختصر معتمد يتميز ببيان المعاني المباشرة بوضوح وإيجاز.',
    ),
    TafsirEdition(
      id: 'saadi',
      nameAr: 'تفسير السعدي (تيسير الكريم الرحمن)',
      authorAr: 'العلامة عبد الرحمن بن ناصر السعدي',
      description: 'تفسير جليل يُعنى بالمقاصد الإيمانية، وسهولة العبارة، والهدايات العملية.',
    ),
    TafsirEdition(
      id: 'ibn_kathir',
      nameAr: 'تفسير القرآن العظيم (ابن كثير)',
      authorAr: 'الحافظ عماد الدين إسماعيل بن كثير الدمشقي',
      description: 'عمدة التفاسير بالمأثور وتفسير القرآن بالقرآن وبالسنة النبوية وأقوال السلف.',
    ),
    TafsirEdition(
      id: 'jalalayn',
      nameAr: 'تفسير الجلالين',
      authorAr: 'جلال الدين المحلي وجلال الدين السيوطي',
      description: 'تفسير وجيز دقيق العبارة يعتني ببيان الألفاظ والإعراب والوجوه البلاغية.',
    ),
    TafsirEdition(
      id: 'qurtubi',
      nameAr: 'الجامع لأحكام القرآن (القرطبي)',
      authorAr: 'الإمام أبو عبد الله محمد بن أحمد القرطبي',
      description: 'موسوعة التفسير الفقهي واستنباط الأحكام الشرعية والقراءات واللغة.',
    ),
    TafsirEdition(
      id: 'tabari',
      nameAr: 'جامع البيان عن تأويل آي القرآن (الطبري)',
      authorAr: 'إمام المفسرين محمد بن جرير الطبري',
      description: 'أجلّ كتب التفسير بالمأثور والترجيح اللغوي والنحوي بين أقوال السلف.',
    ),
    TafsirEdition(
      id: 'baghawi',
      nameAr: 'تفسير البغوي (معالم التنزيل)',
      authorAr: 'الإمام الحسين بن مسعود البغوي',
      description: 'تفسير معتدل يورد الآثار الصحيحة وأقوال الصحابة والتابعين بأمانة علمية.',
    ),
    TafsirEdition(
      id: 'waseet',
      nameAr: 'التفسير الوسيط للأزهر الشريف',
      authorAr: 'مجمع البحوث الإسلامية بالأزهر الشريف',
      description: 'شرح منهجي وافٍ لأسرار النظم القرآني ولطائف البلاغة والتوجيه التربوي.',
    ),
    TafsirEdition(
      id: 'shaarawi',
      nameAr: 'خواطر الإمام محمد متولي الشعراوي',
      authorAr: 'إمام الدعاة الشيخ محمد متولي الشعراوي رحمه الله',
      description: 'خواطر إيمانية وبيانية تكشف دقائق الفروق اللغوية وأسرار الإعجاز القرآني.',
    ),
    TafsirEdition(
      id: 'al_durrah',
      nameAr: 'تفسير القرآن الكريم وإعرابه وبيانه',
      authorAr: 'العلامة الشيخ محمد علي طه الدرة',
      description: 'موسوعة فريدة في الإعراب النحوي الشامل لكل مفردة قرآنية، مع بيان المعاني وبلاغة النظم.',
    ),
    TafsirEdition(
      id: 'almukhtasar_audio',
      nameAr: 'المختصر الصوتي في تفسير القرآن الكريم',
      authorAr: 'مركز تفسير للدراسات القرآنية (الأسمري، الغامدي، الشايع)',
      description: 'المشروع المعتمد لتقريب معاني التنزيل صوتياً ومرئياً عبر يوتيوب والبودكاست وتيليجرام.',
    ),
  ];

  static TafsirEdition getEdition(String id) {
    return availableEditions.firstWhere(
      (e) => e.id == id,
      orElse: () => availableEditions.first,
    );
  }

  /// Resolves the tafsir text for a given ayah and edition
  static Future<TafsirResult> getTafsir({
    required int surahId,
    required int ayahNumber,
    String editionId = 'muyassar',
  }) async {
    final ayah = await QuranRepository.getAyah(surahId, ayahNumber);
    final edition = getEdition(editionId);
    final rawTafseer = ayah?.tafseer;
    // The bundled text is only the existing Muyassar. Never rename it as
    // another book or append generated explanation to it.
    final content = editionId == 'muyassar' && rawTafseer != null && rawTafseer.trim().isNotEmpty
        ? rawTafseer
        : 'لم يُربط نص هذا التفسير بهذه الآية بعد.';

    return TafsirResult(
      editionId: edition.id,
      editionName: edition.nameAr,
      author: edition.authorAr,
      surahId: surahId,
      ayahNumber: ayahNumber,
      ayahText: ayah?.cleanTextUthmani ?? '',
      tafsirText: content,
      hasSourceText: editionId == 'muyassar' && rawTafseer != null && rawTafseer.trim().isNotEmpty,
    );
  }
}
