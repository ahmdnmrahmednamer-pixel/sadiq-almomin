import 'quran_repository.dart';
import 'bundled_tafsir_source.dart';
import 'verse_source_client.dart';
import 'package:flutter/foundation.dart';

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
  final String? sourceUrl;
  final List<BundledTafsirPage> sourcePages;
  final String? sourceNotice;
  final bool hasBookSections;

  const TafsirResult({
    required this.editionId,
    required this.editionName,
    required this.author,
    required this.surahId,
    required this.ayahNumber,
    required this.ayahText,
    required this.tafsirText,
    this.hasSourceText = true,
    this.sourceUrl,
    this.sourcePages=const [],
    this.sourceNotice,
    this.hasBookSections=false,
  });

  /// Formatted text for copying and sharing per FR-TAF-005
  String formatForShare(String surahName) {
    return '﴿$ayahText﴾\n[سورة $surahName، الآية $ayahNumber]\n\n'
        '📖 من $editionName ($author):\n'
        '${sourceNotice==null?'':'$sourceNotice\n\n'}$tafsirText\n\n'
        '${sourceUrl == null ? '' : 'المصدر: $sourceUrl\n'}'
        'تطبيق صديق المؤمن';
  }
}

class TafsirService {
  static AlQuranCloudTafsirClient _client = AlQuranCloudTafsirClient();
  @visibleForTesting
  static void setClientForTesting(AlQuranCloudTafsirClient? client) {
    _client = client ?? AlQuranCloudTafsirClient();
  }
  static BundledTafsirSource _bundled=BundledTafsirSource();
  @visibleForTesting static void setBundledSourceForTesting(BundledTafsirSource? source){_bundled=source??BundledTafsirSource();}
  // Other imported editions remain in preparation until source boundaries are reviewed.
  static const _bundledEditions={'muyassar':'muyassar_witness','waseet':'azhar_spans_private','al_durrah':'durra_spans_private','saadi':'saadi_roots','jalalayn':'jalalayn_corrected','ibn_kathir':'ibn_kathir_pages','tabari':'tabari_roots','baghawi':'baghawi_roots','qurtubi':'qurtubi_printed'};
  static Future<List<BundledTafsirBookSection>> getBookSections(String editionId)async {
    final bundledId=_bundledEditions[editionId];
    if(bundledId==null)return const [];
    return await _bundled.bookSections(bundledId);
  }
  static const _liveEditions = {
    'jalalayn': 'ar.jalalayn', 'qurtubi': 'ar.qurtubi', 'baghawi': 'ar.baghawi',
  };
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
      id: 'al_durrah',
      nameAr: 'تفسير القرآن الكريم وإعرابه وبيانه',
      authorAr: 'العلامة الشيخ محمد علي طه الدرة',
      description: 'موسوعة فريدة في الإعراب النحوي الشامل لكل مفردة قرآنية، مع بيان المعاني وبلاغة النظم.',
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
    final bundledId=_bundledEditions[editionId];
    if(bundledId!=null){
      try{
        final entry=await _bundled.fetch(bundledId,surahId,ayahNumber);
        final text=entry==null?'لم يُثبت نص هذه الآية في نسخة المصدر المضمّنة. لا يُستبدل بنص آية مجاورة.':entry.pages.map((p)=>'${p.sourceLabel==null?'':'${p.sourceLabel}\n'}${p.sourceUrl==null?'':'${p.sourceUrl}\n'}${p.part.isEmpty?'':'ج${p.part}'}${p.page==null?'':'${p.part.isEmpty?'':' '}ص${p.page}'}${p.part.isEmpty&&p.page==null?'':'\n'}${p.text}').join('\n\n');
        return TafsirResult(editionId:edition.id,editionName:edition.nameAr,author:edition.authorAr,surahId:surahId,ayahNumber:ayahNumber,ayahText:ayah?.cleanTextUthmani??'',tafsirText:text,hasSourceText:entry!=null,sourceUrl:bundledId=='muyassar_witness'?null:entry?.sourceUrl??'https://quranpedia.net',hasBookSections:entry?.hasBookSections??false,sourcePages:bundledId!='jalalayn'?(entry?.pages??const []):const [],sourceNotice:bundledId=='muyassar_witness'?entry?.sourceWarning:bundledId.endsWith('_spans_private')?entry?.sourceWarning:bundledId=='jalalayn_corrected'?'نص المصدر محفوظ كما ورد. قد يجمع مقطع واحد أكثر من آية. أُصلحت أرقام تنقل خالفت النص، ولا يُستكمل الموضع الناقص بنص مولد. ${entry?.sourceWarning??''}':bundledId=='qurtubi_printed'?'نص الطبعة مع سياقه وحواشيه. الموضع من عناوين السورة والآيات المطبوعة؛ وقد تشترك آيات في مقطع واحد. أُثبتت ثلاثة مواضع من التعليق الصريح لغيابها عن رقم العنوان. الرسم كما ورد في الطبعة. ${entry?.editionDetails??''}':bundledId=='ibn_kathir_pages'?'صفحات المصدر مع سياقها وهوامشها. موضع الآية من عنوان الكتاب المطبوع، وقد تشترك آيات في المقطع. طبعة دار الكتب العلمية 1419هـ، تحقيق محمد حسين شمس الدين.':bundledId!='jalalayn'?'صفحات المصدر مع سياقها وهوامشها، وليست مقاطع مستقلة لكل آية. الروابط مقيدة بسورة الكتاب وقد يشترك مقطع في آيات متعددة. ${entry?.editionDetails??''}${bundledId=='saadi_roots'&&entry?.sourceWarning!=null?' ${entry!.sourceWarning}':''}':null);
      }catch(_){
        return TafsirResult(editionId:edition.id,editionName:edition.nameAr,author:edition.authorAr,surahId:surahId,ayahNumber:ayahNumber,ayahText:ayah?.cleanTextUthmani??'',tafsirText:'تعذر قراءة حزمة التفسير المضمّنة. لا يُعرض نص بديل.',hasSourceText:false);
      }
    }
    final liveId = _liveEditions[editionId];
    if (liveId != null) {
      try {
        final source = await _client.fetch(editionId:liveId, surah:surahId, ayah:ayahNumber);
        return TafsirResult(editionId:edition.id, editionName:edition.nameAr,
          author:edition.authorAr, surahId:surahId, ayahNumber:ayahNumber,
          ayahText:ayah?.cleanTextUthmani ?? '', tafsirText:source.text,
          sourceUrl:source.sourceUrl);
      } catch (_) {
        return TafsirResult(editionId:edition.id, editionName:edition.nameAr,
          author:edition.authorAr, surahId:surahId, ayahNumber:ayahNumber,
          ayahText:ayah?.cleanTextUthmani ?? '', hasSourceText:false,
          tafsirText:'تعذر تحميل نص هذا التفسير. تحقق من الاتصال وأعد المحاولة.');
      }
    }
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
