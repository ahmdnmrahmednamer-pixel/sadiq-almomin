import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/islamic_radio.dart';
import '../text/arabic_normalizer.dart';

/// خدمة إدارة الإذاعات الإسلامية والبث المباشر
class IslamicRadioService extends ChangeNotifier {
  static final IslamicRadioService instance = IslamicRadioService._internal();
  IslamicRadioService._internal();

  bool _isInitialized = false;
  final Set<String> _favoriteIds = {};

  bool get isInitialized => _isInitialized;
  Set<String> get favoriteIds => Set.unmodifiable(_favoriteIds);

  /// تصنيفات الإذاعات
  static const List<IslamicRadioCategory> categories = [
    IslamicRadioCategory(
      type: IslamicRadioCategoryType.all,
      title: 'جميع الإذاعات',
      icon: Icons.all_inclusive_rounded,
    ),
    IslamicRadioCategory(
      type: IslamicRadioCategoryType.generalLive,
      title: 'إذاعات القرآن المباشرة',
      icon: Icons.radio_rounded,
    ),
    IslamicRadioCategory(
      type: IslamicRadioCategoryType.reciters,
      title: 'كبار القراء (٢٤ ساعة)',
      icon: Icons.record_voice_over_rounded,
    ),
    IslamicRadioCategory(
      type: IslamicRadioCategoryType.tafseerFatwa,
      title: 'التفسير والفتاوى وعلوم القرآن',
      icon: Icons.menu_book_rounded,
    ),
    IslamicRadioCategory(
      type: IslamicRadioCategoryType.adhkarRoqyah,
      title: 'الأذكار والرقية الشرعية',
      icon: Icons.volunteer_activism_rounded,
    ),
    IslamicRadioCategory(
      type: IslamicRadioCategoryType.khushooSurahs,
      title: 'تلاوات خاشعة وسور مختارة',
      icon: Icons.spa_rounded,
    ),
  ];

  /// قائمة الإذاعات المعتمدة مع روابط البث المباشر والبدائل الاحتياطية
  static const List<IslamicRadioStation> defaultStations = [
    // -------------------------------------------------------------
    // ١. إذاعات القرآن العامة والبث المباشر
    // -------------------------------------------------------------
    IslamicRadioStation(
      id: 'radio_cairo_live',
      name: 'إذاعة القرآن الكريم من القاهرة',
      category: IslamicRadioCategoryType.generalLive,
      categoryName: 'إذاعات القرآن المباشرة',
      subtitle: 'البث المباشر لأعرق إذاعة قرآنية في العالم 98.2 FM — تلاوات، برامج، وأذان القاهرة',
      streamUrl: 'https://stream.radiojar.com/8s5u5tpdtwzuv',
      fallbackUrls: [
        'https://n0c.radiojar.com/8s5u5tpdtwzuv',
        'http://n12.radiojar.com/8s5u5tpdtwzuv',
        'https://backup.qurango.net/radio/mix',
      ],
      countryOrOrigin: 'مصر 🇪🇬',
      accentColor: Color(0xFF0F5B45),
      icon: Icons.radio_rounded,
      tags: ['القاهرة', 'ماسبيرو', 'مصر', 'بث مباشر', 'قرآن'],
    ),
    IslamicRadioStation(
      id: 'radio_makkah_live',
      name: 'إذاعة القرآن الكريم — مكة المكرمة والحرمين',
      category: IslamicRadioCategoryType.generalLive,
      categoryName: 'إذاعات القرآن المباشرة',
      subtitle: 'أثير التلاوات الخاشعة من أطهر البقاع وصلوات الحرم المكي الشريف',
      streamUrl: 'https://backup.qurango.net/radio/mix',
      fallbackUrls: [
        'https://qurango.net/radio/mix',
        'https://stream.radiojar.com/8s5u5tpdtwzuv',
      ],
      countryOrOrigin: 'مكة المكرمة 🇸🇦',
      accentColor: Color(0xFFB8893A),
      icon: Icons.mosque_rounded,
      tags: ['مكة', 'الحرم', 'السعودية', 'تلاوات'],
    ),
    IslamicRadioStation(
      id: 'radio_general_recitations',
      name: 'الإذاعة العامة — كوكبة من قراء العالم الإسلامي',
      category: IslamicRadioCategoryType.generalLive,
      categoryName: 'إذاعات القرآن المباشرة',
      subtitle: 'بث متواصل يجمع أعذب وأجمل التلاوات القرآنية لمختلف أئمة وقراء الأمة',
      streamUrl: 'https://backup.qurango.net/radio/mix',
      fallbackUrls: [
        'https://qurango.net/radio/tarateel',
      ],
      countryOrOrigin: 'العالم الإسلامي 🌍',
      accentColor: Color(0xFF1E6F5C),
      icon: Icons.public_rounded,
      tags: ['تلاوات', 'قراء', 'عامة'],
    ),

    // -------------------------------------------------------------
    // ٢. إذاعات كبار القراء على مدار الساعة (24/7)
    // -------------------------------------------------------------
    IslamicRadioStation(
      id: 'radio_minshawi',
      name: 'إذاعة الشيخ محمد صديق المنشاوي',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'الصوت الباكي الخاشع — بث مباشر متواصل لتلاوات الشيخ المرتلة والمجودة',
      streamUrl: 'https://backup.qurango.net/radio/mohammed_siddiq_alminshawi',
      fallbackUrls: [
        'https://backup.qurango.net/radio/mohammed_siddiq_alminshawi_mojawwad',
        'https://qurango.net/radio/mohammed_siddiq_alminshawi',
      ],
      countryOrOrigin: 'مصر 🇪🇬',
      accentColor: Color(0xFFC08A3E),
      icon: Icons.record_voice_over_rounded,
      tags: ['المنشاوي', 'تلاوة خاشعة', 'مصر', 'مرتل', 'مجود'],
    ),
    IslamicRadioStation(
      id: 'radio_husary',
      name: 'إذاعة الشيخ محمود خليل الحصري',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'شيخ عموم المقارئ المصرية — الضبط والترتيل المتقن على مدار اليوم',
      streamUrl: 'https://backup.qurango.net/radio/mahmoud_khalil_alhussary',
      fallbackUrls: [
        'https://backup.qurango.net/radio/mahmoud_khalil_alhussary_mojawwad',
        'https://backup.qurango.net/radio/mahmoud_khalil_alhussary_warsh',
      ],
      countryOrOrigin: 'مصر 🇪🇬',
      accentColor: Color(0xFF1E6F5C),
      icon: Icons.menu_book_rounded,
      tags: ['الحصري', 'مقرئ', 'مصر', 'أزهر'],
    ),
    IslamicRadioStation(
      id: 'radio_abdulbasit',
      name: 'إذاعة الشيخ عبد الباسط عبد الصمد',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'صوت مكة والحنجرة الذهبية — روائع التلاوات الخالدة والتسجيلات النادرة',
      streamUrl: 'https://backup.qurango.net/radio/abdulbasit_abdulsamad',
      fallbackUrls: [
        'https://backup.qurango.net/radio/abdulbasit_abdulsamad_mojawwad',
        'https://backup.qurango.net/radio/abdulbasit_abdulsamad_warsh',
      ],
      countryOrOrigin: 'مصر 🇪🇬',
      accentColor: Color(0xFF996B1E),
      icon: Icons.mic_external_on_rounded,
      tags: ['عبد الباسط', 'صوت مكة', 'تجويد', 'نادر'],
    ),
    IslamicRadioStation(
      id: 'radio_mustafa_ismail',
      name: 'إذاعة الشيخ مصطفى إسماعيل',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'عبقري النغم والتصوير القرآني — تلاوات الجامع الأزهر الشريف والقصر',
      streamUrl: 'https://backup.qurango.net/radio/mustafa_ismail',
      fallbackUrls: [
        'https://qurango.net/radio/mustafa_ismail',
      ],
      countryOrOrigin: 'مصر 🇪🇬',
      accentColor: Color(0xFF2C5E43),
      icon: Icons.graphic_eq_rounded,
      tags: ['مصطفى إسماعيل', 'مقامات', 'تلاوات نادرة'],
    ),
    IslamicRadioStation(
      id: 'radio_tablaway',
      name: 'إذاعة الشيخ محمد محمود الطبلاوي',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'نقيب القراء صاحب النبرة الفريدة وعاشق تلاوة كتاب الله',
      streamUrl: 'https://backup.qurango.net/radio/mohammad_altablaway',
      fallbackUrls: [
        'https://qurango.net/radio/mohammad_altablaway',
      ],
      countryOrOrigin: 'مصر 🇪🇬',
      accentColor: Color(0xFF5B3924),
      icon: Icons.record_voice_over_rounded,
      tags: ['الطبلاوي', 'نقيب القراء', 'مصر'],
    ),
    IslamicRadioStation(
      id: 'radio_banna',
      name: 'إذاعة الشيخ محمود علي البنا',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'أحد أقطاب دولة التلاوة المصرية — صوت شجي وروحانية عالية',
      streamUrl: 'https://backup.qurango.net/radio/mahmoud_ali__albanna',
      fallbackUrls: [
        'https://backup.qurango.net/radio/mahmoud_ali__albanna_mojawwad',
      ],
      countryOrOrigin: 'مصر 🇪🇬',
      accentColor: Color(0xFF3B6B55),
      icon: Icons.library_music_rounded,
      tags: ['البنا', 'تلاوة', 'مصر'],
    ),
    IslamicRadioStation(
      id: 'radio_alafasi',
      name: 'إذاعة الشيخ مشاري بن راشد العفاسي',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'أعذب التلاوات القرآنية الخاشعة والأدعية بصوت الشيخ مشاري العفاسي',
      streamUrl: 'https://backup.qurango.net/radio/mishary_alafasi',
      fallbackUrls: [
        'https://qurango.net/radio/mishary_alafasi',
      ],
      countryOrOrigin: 'الكويت 🇰🇼',
      accentColor: Color(0xFF0F766E),
      icon: Icons.headset_rounded,
      tags: ['العفاسي', 'تلاوات خاشعة', 'الكويت'],
    ),
    IslamicRadioStation(
      id: 'radio_almuaiqly',
      name: 'إذاعة الشيخ ماهر المعيقلي',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'إمام وخطيب المسجد الحرام — ترتيل عذب يلامس القلوب والأفئدة',
      streamUrl: 'https://backup.qurango.net/radio/maher',
      fallbackUrls: [
        'https://qurango.net/radio/maher',
      ],
      countryOrOrigin: 'السعودية 🇸🇦',
      accentColor: Color(0xFFB45309),
      icon: Icons.hearing_rounded,
      tags: ['المعيقلي', 'المسجد الحرام', 'مكة'],
    ),
    IslamicRadioStation(
      id: 'radio_sudais',
      name: 'إذاعة الشيخ عبد الرحمن السديس',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'إمام وخطيب المسجد الحرام — نبرة الحرم المكي الشريف وتلاوات صلاة التراويح',
      streamUrl: 'https://backup.qurango.net/radio/abdulrahman_alsudaes',
      fallbackUrls: [
        'https://qurango.net/radio/abdulrahman_alsudaes',
      ],
      countryOrOrigin: 'السعودية 🇸🇦',
      accentColor: Color(0xFF15803D),
      icon: Icons.mosque_rounded,
      tags: ['السديس', 'الحرم المكي', 'تراويح'],
    ),
    IslamicRadioStation(
      id: 'radio_shuraim',
      name: 'إذاعة الشيخ سعود الشريم',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'تلاوات خاشعة مرتلة من صلوات التراويح والقيام بالمسجد الحرام',
      streamUrl: 'https://backup.qurango.net/radio/saud_alshuraim',
      fallbackUrls: [
        'https://qurango.net/radio/saud_alshuraim',
      ],
      countryOrOrigin: 'السعودية 🇸🇦',
      accentColor: Color(0xFF6D28D9),
      icon: Icons.record_voice_over_rounded,
      tags: ['الشريم', 'الحرم', 'صلاة'],
    ),
    IslamicRadioStation(
      id: 'radio_ghamdi',
      name: 'إذاعة الشيخ سعد الغامدي',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'ترتيل هادئ ورصين لكتاب الله الكريم على مدار الساعة',
      streamUrl: 'https://backup.qurango.net/radio/saad_alghamdi',
      fallbackUrls: [
        'https://qurango.net/radio/saad_alghamdi',
      ],
      countryOrOrigin: 'السعودية 🇸🇦',
      accentColor: Color(0xFF0369A1),
      icon: Icons.surround_sound_rounded,
      tags: ['الغامدي', 'ترتيل', 'سكينة'],
    ),
    IslamicRadioStation(
      id: 'radio_dosari',
      name: 'إذاعة الشيخ ياسر الدوسري',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'إمام المسجد الحرام — تلاوات مؤثرة وتأثر آسر بآيات التنزيل',
      streamUrl: 'https://backup.qurango.net/radio/yasser_aldosari',
      fallbackUrls: [
        'https://qurango.net/radio/yasser_aldosari',
      ],
      countryOrOrigin: 'السعودية 🇸🇦',
      accentColor: Color(0xFF854D0E),
      icon: Icons.record_voice_over_rounded,
      tags: ['الدوسري', 'الحرم المكي', 'تلاوات مؤثرة'],
    ),
    IslamicRadioStation(
      id: 'radio_ajmy',
      name: 'إذاعة الشيخ أحمد بن علي العجمي',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'الصوت الحزين الدافئ — تلاوة مرتلة كاملة للمصحف الشريف',
      streamUrl: 'https://backup.qurango.net/radio/ahmad_alajmy',
      fallbackUrls: [
        'https://qurango.net/radio/ahmad_alajmy',
      ],
      countryOrOrigin: 'السعودية 🇸🇦',
      accentColor: Color(0xFF4338CA),
      icon: Icons.album_rounded,
      tags: ['العجمي', 'تلاوة', 'خشوع'],
    ),
    IslamicRadioStation(
      id: 'radio_shatri',
      name: 'إذاعة الشيخ أبو بكر الشاطري',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'قراءات عذبة منوعة برواية حفص عن عاصم من صلوات القيام',
      streamUrl: 'https://backup.qurango.net/radio/shaik_abu_bakr_al_shatri',
      fallbackUrls: [
        'https://qurango.net/radio/shaik_abu_bakr_al_shatri',
      ],
      countryOrOrigin: 'اليمن 🇾🇪',
      accentColor: Color(0xFF047857),
      icon: Icons.hearing_rounded,
      tags: ['الشاطري', 'تلاوة', 'تراويح'],
    ),
    IslamicRadioStation(
      id: 'radio_abkr',
      name: 'إذاعة الشيخ إدريس أبكر',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'تلاوات تفيض بالخشوع والتضرع وأدعية ختم القرآن المباركة',
      streamUrl: 'https://backup.qurango.net/radio/idrees_abkr',
      fallbackUrls: [
        'https://qurango.net/radio/idrees_abkr',
      ],
      countryOrOrigin: 'السعودية 🇸🇦',
      accentColor: Color(0xFFBE185D),
      icon: Icons.waves_rounded,
      tags: ['إدريس أبكر', 'أدعية', 'خشوع'],
    ),

    // -------------------------------------------------------------
    // ٣. إذاعات التفسير والفتاوى وعلوم الشريعة
    // -------------------------------------------------------------
    IslamicRadioStation(
      id: 'radio_tafseer_general',
      name: 'إذاعة تفسير القرآن الكريم',
      category: IslamicRadioCategoryType.tafseerFatwa,
      categoryName: 'التفسير والفتاوى وعلوم القرآن',
      subtitle: 'بيان معاني الآيات وأسباب النزول ودقائق التفسير القرآني الميسر',
      streamUrl: 'https://backup.qurango.net/radio/tafseer',
      fallbackUrls: [
        'https://qurango.net/radio/tafseer',
      ],
      countryOrOrigin: 'العالم الإسلامي 🌍',
      accentColor: Color(0xFF0D9488),
      icon: Icons.auto_stories_rounded,
      tags: ['تفسير', 'معاني', 'قرآن', 'بيان'],
    ),
    IslamicRadioStation(
      id: 'radio_mukhtasar_tafsir',
      name: 'إذاعة المختصر في تفسير القرآن',
      category: IslamicRadioCategoryType.tafseerFatwa,
      categoryName: 'التفسير والفتاوى وعلوم القرآن',
      subtitle: 'قراءة صوتية لكتاب المختصر في التفسير مع تلاوة الآيات الكريمة',
      streamUrl: 'https://backup.qurango.net/radio/mukhtasartafsir',
      fallbackUrls: [
        'https://qurango.net/radio/mukhtasartafsir',
      ],
      countryOrOrigin: 'العالم الإسلامي 🌍',
      accentColor: Color(0xFF475569),
      icon: Icons.menu_book_rounded,
      tags: ['المختصر', 'تفسير', 'تدبر'],
    ),
    IslamicRadioStation(
      id: 'radio_tabari_tafsir',
      name: 'إذاعة تفسير الإمام الطبري',
      category: IslamicRadioCategoryType.tafseerFatwa,
      categoryName: 'التفسير والفتاوى وعلوم القرآن',
      subtitle: 'الخلاصة المستفادة من جامع البيان في تأويل آي القرآن للإمام الطبري',
      streamUrl: 'https://backup.qurango.net/radio/tabri',
      fallbackUrls: [
        'https://qurango.net/radio/tabri',
      ],
      countryOrOrigin: 'العالم الإسلامي 🌍',
      accentColor: Color(0xFF78350F),
      icon: Icons.history_edu_rounded,
      tags: ['الطبري', 'أثر', 'تفسير'],
    ),
    IslamicRadioStation(
      id: 'radio_fatwa_general',
      name: 'إذاعة الفتاوى والأحكام الشرعية',
      category: IslamicRadioCategoryType.tafseerFatwa,
      categoryName: 'التفسير والفتاوى وعلوم القرآن',
      subtitle: 'إجابات وفتاوى كبار العلماء على أسئلة المسلمين في الفقه والعبادات والمعاملات',
      streamUrl: 'https://backup.qurango.net/radio/fatwa',
      fallbackUrls: [
        'https://qurango.net/radio/fatwa',
      ],
      countryOrOrigin: 'العالم الإسلامي 🌍',
      accentColor: Color(0xFF4F46E5),
      icon: Icons.question_answer_rounded,
      tags: ['فتاوى', 'فقه', 'أحكام', 'سؤال وجواب'],
    ),
    IslamicRadioStation(
      id: 'radio_gareeb_quran',
      name: 'إذاعة غريب القرآن ومفرداته',
      category: IslamicRadioCategoryType.tafseerFatwa,
      categoryName: 'التفسير والفتاوى وعلوم القرآن',
      subtitle: 'إيضاح الألفاظ والكلمات القرآنية الفريدة ولطائف اللغة العربية',
      streamUrl: 'https://backup.qurango.net/radio/gareeb-quran',
      fallbackUrls: [
        'https://qurango.net/radio/gareeb-quran',
      ],
      countryOrOrigin: 'العالم الإسلامي 🌍',
      accentColor: Color(0xFF0284C7),
      icon: Icons.translate_rounded,
      tags: ['غريب القرآن', 'لغة', 'مفردات'],
    ),

    // -------------------------------------------------------------
    // ٤. إذاعات الأذكار والرقية الشرعية والتكبيرات
    // -------------------------------------------------------------
    IslamicRadioStation(
      id: 'radio_athkar_sabah',
      name: 'إذاعة أذكار الصباح المباركة',
      category: IslamicRadioCategoryType.adhkarRoqyah,
      categoryName: 'الأذكار والرقية الشرعية',
      subtitle: 'حصن المسلم وأدعية الصباح المأثورة عن النبي ﷺ بأصوات خاشعة',
      streamUrl: 'https://backup.qurango.net/radio/athkar_sabah',
      fallbackUrls: [
        'https://qurango.net/radio/athkar_sabah',
      ],
      countryOrOrigin: 'العالم الإسلامي 🌍',
      accentColor: Color(0xFFEAB308),
      icon: Icons.wb_sunny_rounded,
      tags: ['صباح', 'أذكار', 'حصن', 'أدعية'],
    ),
    IslamicRadioStation(
      id: 'radio_athkar_masa',
      name: 'إذاعة أذكار المساء وحفظ النفس',
      category: IslamicRadioCategoryType.adhkarRoqyah,
      categoryName: 'الأذكار والرقية الشرعية',
      subtitle: 'أدعية وأذكار المساء لحفظ النفس والبيت ودفع الهم والكرب',
      streamUrl: 'https://backup.qurango.net/radio/athkar_masa',
      fallbackUrls: [
        'https://qurango.net/radio/athkar_masa',
      ],
      countryOrOrigin: 'العالم الإسلامي 🌍',
      accentColor: Color(0xFF4338CA),
      icon: Icons.nightlight_round,
      tags: ['مساء', 'أذكار', 'سكينة'],
    ),
    IslamicRadioStation(
      id: 'radio_roqiah_sharaiyah',
      name: 'إذاعة الرقية الشرعية الشاملة',
      category: IslamicRadioCategoryType.adhkarRoqyah,
      categoryName: 'الأذكار والرقية الشرعية',
      subtitle: 'آيات الشفاء والتحصين من العين والسحر والحسد بصوت نخبة من القراء',
      streamUrl: 'https://backup.qurango.net/radio/roqiah',
      fallbackUrls: [
        'https://qurango.net/radio/roqiah',
      ],
      countryOrOrigin: 'العالم الإسلامي 🌍',
      accentColor: Color(0xFF059669),
      icon: Icons.healing_rounded,
      tags: ['رقية', 'تحصين', 'شفاء', 'عين', 'حسد'],
    ),
    IslamicRadioStation(
      id: 'radio_eid_takbeerat',
      name: 'إذاعة تكبيرات العيد والمشاعر المقدسة',
      category: IslamicRadioCategoryType.adhkarRoqyah,
      categoryName: 'الأذكار والرقية الشرعية',
      subtitle: 'تكبيرات عيد الفطر والأضحى وأيام عشر ذي الحجة من الحرم المكي',
      streamUrl: 'https://backup.qurango.net/radio/eid',
      fallbackUrls: [
        'https://qurango.net/radio/eid',
      ],
      countryOrOrigin: 'الحرمين الشريفين 🕋',
      accentColor: Color(0xFFDC2626),
      icon: Icons.celebration_rounded,
      tags: ['تكبيرات', 'عيد', 'عشر ذي الحجة', 'فرح'],
    ),

    // -------------------------------------------------------------
    // ٥. تلاوات خاشعة وسور مختارة
    // -------------------------------------------------------------
    IslamicRadioStation(
      id: 'radio_albaqarah_continuous',
      name: 'إذاعة سورة البقرة المستمرة',
      category: IslamicRadioCategoryType.khushooSurahs,
      categoryName: 'تلاوات خاشعة وسور مختارة',
      subtitle: 'سورة البقرة متواصلة بأعذب الأصوات لطرد الشياطين وجلب البركة للمنزل',
      streamUrl: 'https://backup.qurango.net/radio/albaqarah',
      fallbackUrls: [
        'https://qurango.net/radio/albaqarah',
      ],
      countryOrOrigin: 'العالم الإسلامي 🌍',
      accentColor: Color(0xFF0F5B45),
      icon: Icons.shield_rounded,
      tags: ['البقرة', 'بركة', 'طرد الشياطين', 'تحصين'],
    ),
    IslamicRadioStation(
      id: 'radio_tarateel_fajr',
      name: 'إذاعة تراتيل الفجر وقيام الليل',
      category: IslamicRadioCategoryType.khushooSurahs,
      categoryName: 'تلاوات خاشعة وسور مختارة',
      subtitle: 'ترتيل هادئ ندي يبعث الطمأنينة لأوقات السحر والخلوة مع الله',
      streamUrl: 'https://backup.qurango.net/radio/tarateel',
      fallbackUrls: [
        'https://qurango.net/radio/tarateel',
      ],
      countryOrOrigin: 'العالم الإسلامي 🌍',
      accentColor: Color(0xFF312E81),
      icon: Icons.nights_stay_rounded,
      tags: ['تراتيل', 'فجر', 'قيام الليل', 'سحر'],
    ),
  ];

  /// تهيئة وتعيين المفضلة من الذاكرة المحلية
  Future<void> init({bool forceReload = false}) async {
    if (_isInitialized && !forceReload) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final favs = prefs.getStringList('islamic_radio_favorites') ?? [];
      _favoriteIds
        ..clear()
        ..addAll(favs);
    } catch (e) {
      debugPrint('IslamicRadioService init error: $e');
    }
    _isInitialized = true;
    notifyListeners();
  }

  /// هل المحطة في المفضلة
  bool isFavorite(String id) => _favoriteIds.contains(id);

  /// تبديل حالة المفضلة للمحطة
  Future<void> toggleFavorite(String id) async {
    if (_favoriteIds.contains(id)) {
      _favoriteIds.remove(id);
    } else {
      _favoriteIds.add(id);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('islamic_radio_favorites', _favoriteIds.toList());
    } catch (_) {}
    notifyListeners();
  }

  /// تصفية المحطات حسب التصنيف والبحث والمفضلة
  List<IslamicRadioStation> getStations({
    IslamicRadioCategoryType category = IslamicRadioCategoryType.all,
    String query = '',
    bool favoritesOnly = false,
  }) {
    final cleanQuery = ArabicNormalizer.normalize(query.trim(), loose: true);

    return defaultStations.where((station) {
      if (favoritesOnly && !_favoriteIds.contains(station.id)) {
        return false;
      }

      if (category != IslamicRadioCategoryType.all && station.category != category) {
        return false;
      }

      if (cleanQuery.isNotEmpty) {
        final normName = ArabicNormalizer.normalize(station.name, loose: true);
        final normSubtitle = ArabicNormalizer.normalize(station.subtitle, loose: true);
        final normOrigin = ArabicNormalizer.normalize(station.countryOrOrigin, loose: true);
        final normCategory = ArabicNormalizer.normalize(station.categoryName, loose: true);

        final matchesName = normName.contains(cleanQuery);
        final matchesSub = normSubtitle.contains(cleanQuery);
        final matchesOrigin = normOrigin.contains(cleanQuery);
        final matchesCat = normCategory.contains(cleanQuery);
        final matchesTags = station.tags.any(
          (t) => ArabicNormalizer.normalize(t, loose: true).contains(cleanQuery),
        );

        if (!matchesName && !matchesSub && !matchesOrigin && !matchesCat && !matchesTags) {
          return false;
        }
      }

      return true;
    }).toList();
  }
}
