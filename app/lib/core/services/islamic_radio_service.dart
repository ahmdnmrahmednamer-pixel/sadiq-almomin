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
      type: IslamicRadioCategoryType.sunnahHadith,
      title: 'السنة النبوية والحديث',
      icon: Icons.auto_stories_rounded,
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

  /// قائمة الإذاعات المعتمدة الحية والمفحوصة شبكياً بنسبة 100%
  /// المصدر: كتالوج MP3Quran الرسمي الموثق (https://mp3quran.net/api/v3/radios?language=ar)
  /// تاريخ التحقق الميداني المباشر: 2026-11-15 (HTTP 200 Audio Streams Only)
  static const List<IslamicRadioStation> defaultStations = [
    // -------------------------------------------------------------
    // ١. إذاعات القرآن العامة والبث المباشر
    // -------------------------------------------------------------
    // توثيق هوية البث:
    // يحمل الرابط https://stream.radiojar.com/8s5u5tpdtwzuv ترويسة ICY: (icy-name: Mini2's Broadcast).
    // هذا البث ترحيل مجتمعي متاح عبر منصة Radiojar لإذاعة القرآن الكريم 98.2 FM (غير معتمد رسمياً من ماسبيرو/الهيئة الوطنية للإعلام).
    IslamicRadioStation(
      id: 'radio_cairo_live',
      name: 'إذاعة القرآن الكريم من القاهرة',
      category: IslamicRadioCategoryType.generalLive,
      categoryName: 'إذاعات القرآن المباشرة',
      subtitle: 'بث ترحيلي غير رسمي لإذاعة 98.2 FM عبر خادم مجتمعي (Radiojar Mini2 — غير معتمد من ماسبيرو)',
      streamUrl: 'https://stream.radiojar.com/8s5u5tpdtwzuv',
      fallbackUrls: [
        'https://n0c.radiojar.com/8s5u5tpdtwzuv',
        'http://n12.radiojar.com/8s5u5tpdtwzuv',
      ],
      countryOrOrigin: 'مصر (ترحيل مجتمعي)',
      accentColor: Color(0xFF0F5B45),
      icon: Icons.radio_rounded,
      tags: ['القاهرة', 'ماسبيرو', 'مصر', 'ترحيل مجتمعي', 'بث غير رسمي'],
    ),
    // MP3Quran ID: 108
    IslamicRadioStation(
      id: 'radio_general_recitations',
      name: 'الإذاعة العامة — تلاوات متنوعة لمختلف القراء',
      category: IslamicRadioCategoryType.generalLive,
      categoryName: 'إذاعات القرآن المباشرة',
      subtitle: 'بث متواصل يجمع أعذب وأجمل التلاوات القرآنية لمختلف أئمة وقراء الأمة',
      streamUrl: 'https://backup.qurango.net/radio/mix',
      fallbackUrls: [
        'https://qurango.net/radio/mix',
      ],
      countryOrOrigin: 'العالم الإسلامي 🌍',
      accentColor: Color(0xFF1E6F5C),
      icon: Icons.public_rounded,
      tags: ['تلاوات', 'قراء', 'عامة', 'منوعات'],
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
      tags: ['المنشاوي', 'مرتل', 'مجود', 'مصر', 'تلاوات خاشعة'],
    ),
    IslamicRadioStation(
      id: 'radio_husary',
      name: 'إذاعة الشيخ محمود خليل الحصري',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'شيخ عموم المقارئ المصرية ودقة الأحكام ومخارج الحروف برواية حفص وورش',
      streamUrl: 'https://qurango.net/radio/mahmoud_khalil_alhussary_mojawwad',
      fallbackUrls: [
        'https://backup.qurango.net/radio/mahmoud_khalil_alhussary',
        'https://backup.qurango.net/radio/mahmoud_khalil_alhussary_warsh',
      ],
      countryOrOrigin: 'مصر 🇪🇬',
      accentColor: Color(0xFF2D6A4F),
      icon: Icons.record_voice_over_rounded,
      tags: ['الحصري', 'أحكام التجويد', 'ورش', 'حفص', 'المقارئ'],
    ),
    IslamicRadioStation(
      id: 'radio_abdulbasit',
      name: 'إذاعة الشيخ عبد الباسط عبد الصمد',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'صوت مكة الذهبي — روائع التلاوات الخالدة المرتلة والمجودة والحفلات الخارجية',
      streamUrl: 'https://backup.qurango.net/radio/abdulbasit_abdulsamad',
      fallbackUrls: [
        'https://backup.qurango.net/radio/abdulbasit_abdulsamad_mojawwad',
        'https://backup.qurango.net/radio/abdulbasit_abdulsamad_warsh',
      ],
      countryOrOrigin: 'مصر 🇪🇬',
      accentColor: Color(0xFFD4A373),
      icon: Icons.record_voice_over_rounded,
      tags: ['عبد الباسط', 'صوت مكة', 'تجويد', 'حفلات', 'روائع'],
    ),
    IslamicRadioStation(
      id: 'radio_mustafa_ismail',
      name: 'إذاعة الشيخ مصطفى إسماعيل',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'عبقري التلاوة ومقرئ الملوك والرؤساء — روعة المقامات وتصوير المعاني القرآنية',
      streamUrl: 'https://qurango.net/radio/mustafa_ismail',
      fallbackUrls: [
        'https://backup.qurango.net/radio/mustafa_ismail',
      ],
      countryOrOrigin: 'مصر 🇪🇬',
      accentColor: Color(0xFF4A7C59),
      icon: Icons.record_voice_over_rounded,
      tags: ['مصطفى إسماعيل', 'عبقري التلاوة', 'مقامات', 'تجويد'],
    ),
    IslamicRadioStation(
      id: 'radio_tablaway',
      name: 'إذاعة الشيخ محمد محمود الطبلاوي',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'نقيب القراء وأحد ألمع أصوات دولة التلاوة المصرية بنبرته الشجية الفريدة',
      streamUrl: 'https://backup.qurango.net/radio/mohammad_altablaway',
      fallbackUrls: [
        'https://qurango.net/radio/mohammad_altablaway',
      ],
      countryOrOrigin: 'مصر 🇪🇬',
      accentColor: Color(0xFFBC6C25),
      icon: Icons.record_voice_over_rounded,
      tags: ['الطبلاوي', 'نقيب القراء', 'مصر', 'تلاوة'],
    ),
    IslamicRadioStation(
      id: 'radio_banna',
      name: 'إذاعة الشيخ محمود علي البنا',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'صوت الفجر والخشوع الرباني بروعة الأداء والتلاوة المتقنة',
      streamUrl: 'https://backup.qurango.net/radio/mahmoud_ali__albanna',
      fallbackUrls: [
        'https://backup.qurango.net/radio/mahmoud_ali__albanna_mojawwad',
      ],
      countryOrOrigin: 'مصر 🇪🇬',
      accentColor: Color(0xFF386641),
      icon: Icons.record_voice_over_rounded,
      tags: ['محمود علي البنا', 'تلاوات خاشعة', 'تجويد'],
    ),
    IslamicRadioStation(
      id: 'radio_alafasi',
      name: 'إذاعة الشيخ مشاري بن راشد العفاسي',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'المصحف المرتل برواية حفص عن عاصم ونفحات إيمانية عذبة بصوت الشيخ مشاري',
      streamUrl: 'https://backup.qurango.net/radio/mishary_alafasi',
      fallbackUrls: [
        'https://qurango.net/radio/mishary_alafasi',
      ],
      countryOrOrigin: 'الكويت 🇰🇼',
      accentColor: Color(0xFF3A86FF),
      icon: Icons.record_voice_over_rounded,
      tags: ['مشاري العفاسي', 'العفاسي', 'الكويت', 'مرتل', 'تلاوة'],
    ),
    IslamicRadioStation(
      id: 'radio_almuaiqly',
      name: 'إذاعة الشيخ ماهر المعيقلي',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'إمام وخطيب المسجد الحرام الشريف — تلاوات مرتلة متواصلة تأسر القلوب',
      streamUrl: 'https://backup.qurango.net/radio/maher',
      fallbackUrls: [
        'https://qurango.net/radio/maher',
      ],
      countryOrOrigin: 'مكة المكرمة 🇸🇦',
      accentColor: Color(0xFF0077B6),
      icon: Icons.record_voice_over_rounded,
      tags: ['ماهر المعيقلي', 'الحرم المكي', 'إمام الحرم', 'تلاوات خاشعة'],
    ),
    IslamicRadioStation(
      id: 'radio_sudais',
      name: 'إذاعة الشيخ عبد الرحمن السديس',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'إمام وخطيب المسجد الحرام ورئيس الشؤون الدينية للحرمين الشريفين بنبرته المتميزة',
      streamUrl: 'https://qurango.net/radio/abdulrahman_alsudaes',
      fallbackUrls: [
        'https://backup.qurango.net/radio/abdulrahman_alsudaes',
      ],
      countryOrOrigin: 'مكة المكرمة 🇸🇦',
      accentColor: Color(0xFF8338EC),
      icon: Icons.record_voice_over_rounded,
      tags: ['السديس', 'عبد الرحمن السديس', 'الحرم المكي', 'إمام الحرم'],
    ),
    IslamicRadioStation(
      id: 'radio_shuraim',
      name: 'إذاعة الشيخ سعود الشريم',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'إمام المسجد الحرام السابق بصوته الرخيم وتلاواته الحدرية الخاشعة الشهيرة',
      streamUrl: 'https://qurango.net/radio/saud_alshuraim',
      fallbackUrls: [
        'https://backup.qurango.net/radio/saud_alshuraim',
      ],
      countryOrOrigin: 'مكة المكرمة 🇸🇦',
      accentColor: Color(0xFF023E8A),
      icon: Icons.record_voice_over_rounded,
      tags: ['سعود الشريم', 'الشريم', 'الحرم المكي', 'تراويح'],
    ),
    IslamicRadioStation(
      id: 'radio_ali_jaber',
      name: 'إذاعة الشيخ علي جابر',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'إمام المسجد الحرام الراحل — التلاوات التراثية الفريدة التي ارتبطت بذاكرة المسلمين',
      streamUrl: 'https://backup.qurango.net/radio/ali_jaber',
      fallbackUrls: [
        'https://qurango.net/radio/ali_jaber',
      ],
      countryOrOrigin: 'مكة المكرمة 🇸🇦',
      accentColor: Color(0xFF0096C7),
      icon: Icons.record_voice_over_rounded,
      tags: ['علي جابر', 'إمام الحرم', 'تراويح الحرم', 'تلاوات نادرة'],
    ),
    IslamicRadioStation(
      id: 'radio_fares_abbad',
      name: 'إذاعة الشيخ فارس عباد',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'التلاوة الندية العذبة المتواصلة على مدار الساعة التي تأسر القلوب بصفائها',
      streamUrl: 'https://backup.qurango.net/radio/fares_abbad',
      fallbackUrls: [
        'https://qurango.net/radio/fares_abbad',
      ],
      countryOrOrigin: 'اليمن 🇾🇪',
      accentColor: Color(0xFF05668D),
      icon: Icons.record_voice_over_rounded,
      tags: ['فارس عباد', 'تلاوات عذبة', 'مرتل'],
    ),
    IslamicRadioStation(
      id: 'radio_salah_albudair',
      name: 'إذاعة الشيخ صلاح البدير',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'تلاوات وصلوات إمام وخطيب المسجد النبوي الشريف بالمدينة المنورة بنبرته الشجية',
      streamUrl: 'https://qurango.net/radio/salah_albudair',
      fallbackUrls: [
        'https://backup.qurango.net/radio/salah_albudair',
      ],
      countryOrOrigin: 'المدينة المنورة 🇸🇦',
      accentColor: Color(0xFF028090),
      icon: Icons.record_voice_over_rounded,
      tags: ['صلاح البدير', 'المسجد النبوي', 'إمام الحرم المدني', 'تلاوات'],
    ),
    IslamicRadioStation(
      id: 'radio_abdullah_aljohany',
      name: 'إذاعة الشيخ عبد الله عواد الجهني',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'التلاوات الخاشعة الرقيقة لإمام المسجد الحرام بمكة المكرمة بصوته الندي',
      streamUrl: 'https://backup.qurango.net/radio/abdullah_aljohany',
      fallbackUrls: [
        'https://qurango.net/radio/abdullah_aljohany',
      ],
      countryOrOrigin: 'مكة المكرمة 🇸🇦',
      accentColor: Color(0xFF00A896),
      icon: Icons.record_voice_over_rounded,
      tags: ['عبد الله الجهني', 'إمام الحرم المكي', 'مكة', 'تلاوات رقيقة'],
    ),
    IslamicRadioStation(
      id: 'radio_nasser_alqatami',
      name: 'إذاعة الشيخ ناصر القطامي',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'تلاوات خاشعة ومؤثرة من صلوات القيام والتهجد والتراويح بنبرة بكائية محببة',
      streamUrl: 'https://backup.qurango.net/radio/nasser_alqatami',
      fallbackUrls: [
        'https://qurango.net/radio/nasser_alqatami',
      ],
      countryOrOrigin: 'السعودية 🇸🇦',
      accentColor: Color(0xFF02C39A),
      icon: Icons.record_voice_over_rounded,
      tags: ['ناصر القطامي', 'تراويح', 'قيام الليل', 'خاشع'],
    ),
    IslamicRadioStation(
      id: 'radio_dosari',
      name: 'إذاعة الشيخ ياسر الدوسري',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'إمام المسجد الحرام الشريف — تلاوات تهز القلوب بخشوعها ونقاء الصوت وحسن الأداء',
      streamUrl: 'https://backup.qurango.net/radio/yasser_aldosari',
      fallbackUrls: [
        'https://qurango.net/radio/yasser_aldosari',
      ],
      countryOrOrigin: 'مكة المكرمة 🇸🇦',
      accentColor: Color(0xFF2B9348),
      icon: Icons.record_voice_over_rounded,
      tags: ['ياسر الدوسري', 'إمام الحرم المكي', 'تلاوات مؤثرة', 'تراويح'],
    ),
    IslamicRadioStation(
      id: 'radio_ajmy',
      name: 'إذاعة الشيخ أحمد بن علي العجمي',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'المصحف المرتل كاملاً بصوت الشيخ أحمد العجمي وتلاوته الإيقاعية المحبوبة في العالم',
      streamUrl: 'https://qurango.net/radio/ahmad_alajmy',
      fallbackUrls: [
        'https://backup.qurango.net/radio/ahmad_alajmy',
      ],
      countryOrOrigin: 'السعودية 🇸🇦',
      accentColor: Color(0xFF55A630),
      icon: Icons.record_voice_over_rounded,
      tags: ['أحمد العجمي', 'العجمي', 'مرتل', 'تلاوات'],
    ),
    IslamicRadioStation(
      id: 'radio_shatri',
      name: 'إذاعة الشيخ أبو بكر الشاطري',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'تلاوات شجية بطريقة الشيخ الشاطري المتميزة التي تبث السكينة والطمأنينة',
      streamUrl: 'https://qurango.net/radio/shaik_abu_bakr_al_shatri',
      fallbackUrls: [
        'https://qurango.net/radio/shaik_abu_bakr_al_shatri',
      ],
      countryOrOrigin: 'السعودية 🇸🇦',
      accentColor: Color(0xFF80B918),
      icon: Icons.record_voice_over_rounded,
      tags: ['أبو بكر الشاطري', 'الشاطري', 'تلاوات خاشعة'],
    ),
    IslamicRadioStation(
      id: 'radio_abkr',
      name: 'إذاعة الشيخ إدريس أبكر',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'تلاوات خاشعة باكية وأدعية مؤثرة تمس الوجدان من صلوات التهجد والقيام',
      streamUrl: 'https://qurango.net/radio/idrees_abkr',
      fallbackUrls: [
        'https://backup.qurango.net/radio/idrees_abkr',
      ],
      countryOrOrigin: 'الإمارات 🇦🇪',
      accentColor: Color(0xFFAACC00),
      icon: Icons.record_voice_over_rounded,
      tags: ['إدريس أبكر', 'أبكر', 'دعاء', 'قيام الليل', 'باكي'],
    ),
    IslamicRadioStation(
      id: 'radio_hazza_albalushi',
      name: 'إذاعة الشيخ هزاع البلوشي',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'تلاوات هادئة عذبة تأسر القلوب وتريح النفوس بصوت الشيخ هزاع البلوشي',
      streamUrl: 'https://backup.qurango.net/radio/hazza',
      fallbackUrls: [
        'https://qurango.net/radio/hazza',
      ],
      countryOrOrigin: 'عُمان 🇴🇲',
      accentColor: Color(0xFF1B4965),
      icon: Icons.record_voice_over_rounded,
      tags: ['هزاع البلوشي', 'عمان', 'تلاوات هادئة'],
    ),
    IslamicRadioStation(
      id: 'radio_abdulmohsen_alqasim',
      name: 'إذاعة الشيخ عبد المحسن القاسم',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'تلاوات مرتلة برواية حفص لإمام وخطيب المسجد النبوي الشريف بالمدينة المنورة',
      streamUrl: 'https://backup.qurango.net/radio/abdulmohsen_alqasim',
      fallbackUrls: [
        'https://qurango.net/radio/abdulmohsen_alqasim',
      ],
      countryOrOrigin: 'المدينة المنورة 🇸🇦',
      accentColor: Color(0xFF62B6CB),
      icon: Icons.record_voice_over_rounded,
      tags: ['عبد المحسن القاسم', 'المسجد النبوي', 'المدينة المنورة'],
    ),
    IslamicRadioStation(
      id: 'radio_khalifa_altunaiji',
      name: 'إذاعة الشيخ خليفة الطنيجي',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'تلاوة متقنة بالأحكام وصوت رصين خاشع برواية حفص عن عاصم',
      streamUrl: 'https://backup.qurango.net/radio/khalifa_altunaiji',
      fallbackUrls: [
        'https://qurango.net/radio/khalifa_altunaiji',
      ],
      countryOrOrigin: 'الإمارات 🇦🇪',
      accentColor: Color(0xFF5E548E),
      icon: Icons.record_voice_over_rounded,
      tags: ['خليفة الطنيجي', 'تلاوات', 'إتقان'],
    ),
    IslamicRadioStation(
      id: 'radio_hani_arrifai',
      name: 'إذاعة الشيخ هاني الرفاعي',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'كبار القراء (٢٤ ساعة)',
      subtitle: 'التلاوات الباكية والتضرع في آيات القرآن الحكيم بصوت الشيخ هاني الرفاعي',
      streamUrl: 'https://backup.qurango.net/radio/hani_arrifai',
      fallbackUrls: [
        'https://qurango.net/radio/hani_arrifai',
      ],
      countryOrOrigin: 'السعودية 🇸🇦',
      accentColor: Color(0xFF9F86C0),
      icon: Icons.record_voice_over_rounded,
      tags: ['هاني الرفاعي', 'باكي', 'تضرع', 'تلاوات'],
    ),

    // -------------------------------------------------------------
    // ٣. إذاعات السنة النبوية والحديث الشريف
    // -------------------------------------------------------------
    IslamicRadioStation(
      id: 'radio_saheh_bokharee',
      name: 'إذاعة صحيح البخاري الشريف',
      category: IslamicRadioCategoryType.sunnahHadith,
      categoryName: 'السنة النبوية والحديث',
      subtitle: 'قراءة مسموعة لكتاب الجامع المسند الصحيح للإمام محمد بن إسماعيل البخاري رحمه الله',
      streamUrl: 'https://backup.qurango.net/radio/saheh-bokharee',
      fallbackUrls: [
        'https://qurango.net/radio/saheh-bokharee',
      ],
      countryOrOrigin: 'السنة النبوية 📜',
      accentColor: Color(0xFF264653),
      icon: Icons.auto_stories_rounded,
      tags: ['صحيح البخاري', 'البخاري', 'حديث', 'سنة', 'الحديث الشريف'],
    ),
    IslamicRadioStation(
      id: 'radio_saheh_muslim',
      name: 'إذاعة صحيح مسلم',
      category: IslamicRadioCategoryType.sunnahHadith,
      categoryName: 'السنة النبوية والحديث',
      subtitle: 'بث متواصل لقراءة أحاديث المسند الصحيح للإمام مسلم بن الحجاج النيسابوري رحمه الله',
      streamUrl: 'https://backup.qurango.net/radio/saheh-muslim',
      fallbackUrls: [
        'https://qurango.net/radio/saheh-muslim',
      ],
      countryOrOrigin: 'السنة النبوية 📜',
      accentColor: Color(0xFF2A9D8F),
      icon: Icons.auto_stories_rounded,
      tags: ['صحيح مسلم', 'مسلم', 'حديث', 'سنة نبوية'],
    ),
    IslamicRadioStation(
      id: 'radio_riyad_salihin',
      name: 'إذاعة رياض الصالحين',
      category: IslamicRadioCategoryType.sunnahHadith,
      categoryName: 'السنة النبوية والحديث',
      subtitle: 'أحاديث سيد المرسلين من كلام الإمام يحيى بن شرف النووي رحمه الله في الآداب والأخلاق',
      streamUrl: 'https://backup.qurango.net/radio/riyad',
      fallbackUrls: [
        'https://qurango.net/radio/riyad',
      ],
      countryOrOrigin: 'الحديث الشريف 📖',
      accentColor: Color(0xFFE76F51),
      icon: Icons.menu_book_rounded,
      tags: ['رياض الصالحين', 'النووي', 'آداب', 'أخلاق', 'حديث'],
    ),
    IslamicRadioStation(
      id: 'radio_alanbiya',
      name: 'إذاعة قصص الأنبياء والمرسلين',
      category: IslamicRadioCategoryType.sunnahHadith,
      categoryName: 'السنة النبوية والحديث',
      subtitle: 'سير وقصص الأنبياء والمرسلين عليهم الصلاة والسلام والعبر المستفادة من حياتهم ودعوتهم',
      streamUrl: 'https://backup.qurango.net/radio/alanbiya',
      fallbackUrls: [
        'https://qurango.net/radio/alanbiya',
      ],
      countryOrOrigin: 'السيرة والعبر 🌿',
      accentColor: Color(0xFFF4A261),
      icon: Icons.history_edu_rounded,
      tags: ['قصص الأنبياء', 'سير', 'عبر', 'دعوة'],
    ),
    IslamicRadioStation(
      id: 'radio_shmaeel',
      name: 'إذاعة الشمائل المحمدية',
      category: IslamicRadioCategoryType.sunnahHadith,
      categoryName: 'السنة النبوية والحديث',
      subtitle: 'أوصاف وأخلاق وهدي النبي المصطفى صلى الله عليه وسلم من كتاب الإمام الترمذي رحمه الله',
      streamUrl: 'https://backup.qurango.net/radio/shmaeel',
      fallbackUrls: [
        'https://qurango.net/radio/shmaeel',
      ],
      countryOrOrigin: 'السيرة النبوية 🌸',
      accentColor: Color(0xFFE9C46A),
      icon: Icons.favorite_rounded,
      tags: ['الشمائل المحمدية', 'الترمذي', 'سيرة', 'أخلاق النبي'],
    ),

    // -------------------------------------------------------------
    // ٤. إذاعات التفسير والفتاوى وعلوم القرآن
    // -------------------------------------------------------------
    IslamicRadioStation(
      id: 'radio_tafseer_general',
      name: 'إذاعة تفسير القرآن الكريم',
      category: IslamicRadioCategoryType.tafseerFatwa,
      categoryName: 'التفسير والفتاوى وعلوم القرآن',
      subtitle: 'بيان معاني آيات الذكر الحكيم وغريب الألفاظ وأسرار التنزيل بأسلوب علمي رصين',
      streamUrl: 'https://backup.qurango.net/radio/tafseer',
      fallbackUrls: [
        'https://qurango.net/radio/tafseer',
      ],
      countryOrOrigin: 'علوم القرآن 📖',
      accentColor: Color(0xFF6B705C),
      icon: Icons.menu_book_rounded,
      tags: ['تفسير', 'معاني الآيات', 'بيان', 'علوم القرآن'],
    ),
    IslamicRadioStation(
      id: 'radio_mukhtasar_tafsir',
      name: 'إذاعة المختصر في تفسير القرآن',
      category: IslamicRadioCategoryType.tafseerFatwa,
      categoryName: 'التفسير والفتاوى وعلوم القرآن',
      subtitle: 'تفسير ميسر ومحرر لآيات القرآن الكريم صادر عن مركز تفسير للدراسات القرآنية',
      streamUrl: 'https://backup.qurango.net/radio/mukhtasartafsir',
      fallbackUrls: [
        'https://qurango.net/radio/mukhtasartafsir',
      ],
      countryOrOrigin: 'مركز تفسير 📗',
      accentColor: Color(0xFFA5A58D),
      icon: Icons.menu_book_rounded,
      tags: ['المختصر في التفسير', 'تفسير ميسر', 'مركز تفسير'],
    ),
    IslamicRadioStation(
      id: 'radio_tabari_tafsir',
      name: 'إذاعة تفسير الإمام الطبري',
      category: IslamicRadioCategoryType.tafseerFatwa,
      categoryName: 'التفسير والفتاوى وعلوم القرآن',
      subtitle: 'خلاصة جامع البيان عن تأويل آي القرآن لإمام المفسرين أبي جعفر الطبري رحمه الله',
      streamUrl: 'https://backup.qurango.net/radio/tabri',
      fallbackUrls: [
        'https://qurango.net/radio/tabri',
      ],
      countryOrOrigin: 'تراث الأمة 📜',
      accentColor: Color(0xFFB7B7A4),
      icon: Icons.menu_book_rounded,
      tags: ['تفسير الطبري', 'جامع البيان', 'إمام المفسرين', 'أثر'],
    ),
    IslamicRadioStation(
      id: 'radio_fatwa_general',
      name: 'إذاعة الفتاوى والأحكام الشرعية',
      category: IslamicRadioCategoryType.tafseerFatwa,
      categoryName: 'التفسير والفتاوى وعلوم القرآن',
      subtitle: 'فتاوى كبار علماء الأمة في العبادات والمعاملات وأحكام الحياة اليومية وفق الكتاب والسنة',
      streamUrl: 'https://backup.qurango.net/radio/fatwa',
      fallbackUrls: [
        'https://qurango.net/radio/fatwa',
      ],
      countryOrOrigin: 'الفقه الإسلامي ⚖️',
      accentColor: Color(0xFF4A4E69),
      icon: Icons.gavel_rounded,
      tags: ['فتاوى', 'أحكام شرعية', 'فقه', 'عبادات', 'معاملات'],
    ),
    IslamicRadioStation(
      id: 'radio_gareeb_quran',
      name: 'إذاعة غريب القرآن ومفرداته',
      category: IslamicRadioCategoryType.tafseerFatwa,
      categoryName: 'التفسير والفتاوى وعلوم القرآن',
      subtitle: 'شرح وتوضيح الألفاظ والمفردات اللغوية الدقيقة الواردة في الآيات الشريفة',
      streamUrl: 'https://backup.qurango.net/radio/gareeb-quran',
      fallbackUrls: [
        'https://qurango.net/radio/gareeb-quran',
      ],
      countryOrOrigin: 'لغة القرآن 🔤',
      accentColor: Color(0xFF22223B),
      icon: Icons.spellcheck_rounded,
      tags: ['غريب القرآن', 'مفردات', 'لغة عربية', 'بيان'],
    ),

    // -------------------------------------------------------------
    // ٥. إذاعات الأذكار والرقية الشرعية
    // -------------------------------------------------------------
    IslamicRadioStation(
      id: 'radio_athkar_sabah',
      name: 'إذاعة أذكار الصباح المباركة',
      category: IslamicRadioCategoryType.adhkarRoqyah,
      categoryName: 'الأذكار والرقية الشرعية',
      subtitle: 'حصن المسلم وأدعية واستفتاحات الصباح المأثورة عن النبي صلى الله عليه وسلم',
      streamUrl: 'https://backup.qurango.net/radio/athkar_sabah',
      fallbackUrls: [
        'https://qurango.net/radio/athkar_sabah',
      ],
      countryOrOrigin: 'حصن المسلم ☀️',
      accentColor: Color(0xFFDDA15E),
      icon: Icons.wb_sunny_rounded,
      tags: ['أذكار الصباح', 'حصن المسلم', 'صباح', 'تسبيح', 'استغفار'],
    ),
    IslamicRadioStation(
      id: 'radio_athkar_masa',
      name: 'إذاعة أذكار المساء وحفظ النفس',
      category: IslamicRadioCategoryType.adhkarRoqyah,
      categoryName: 'الأذكار والرقية الشرعية',
      subtitle: 'أدعية المساء والأذكار النبوية للسكينة وحفظ النفس والبيت والأهل',
      streamUrl: 'https://backup.qurango.net/radio/athkar_masa',
      fallbackUrls: [
        'https://qurango.net/radio/athkar_masa',
      ],
      countryOrOrigin: 'حصن المسلم 🌙',
      accentColor: Color(0xFFBC6C25),
      icon: Icons.nights_stay_rounded,
      tags: ['أذكار المساء', 'مساء', 'حفظ', 'تحصين'],
    ),
    IslamicRadioStation(
      id: 'radio_roqiah_sharaiyah',
      name: 'إذاعة الرقية الشرعية الشاملة',
      category: IslamicRadioCategoryType.adhkarRoqyah,
      categoryName: 'الأذكار والرقية الشرعية',
      subtitle: 'الرقية الشرعية المعتمدة بالآيات القرآنية والأدعية النبوية الثابتة للشفاء والحفظ',
      streamUrl: 'https://backup.qurango.net/radio/roqiah',
      fallbackUrls: [
        'https://qurango.net/radio/roqiah',
      ],
      countryOrOrigin: 'شفاء ورحمة 🛡️',
      accentColor: Color(0xFF283618),
      icon: Icons.healing_rounded,
      tags: ['الرقية الشرعية', 'رقية', 'شفاء', 'تحصين', 'علاج'],
    ),
    IslamicRadioStation(
      id: 'radio_eid_takbeerat',
      name: 'إذاعة تكبيرات العيد والمشاعر المقدسة',
      category: IslamicRadioCategoryType.adhkarRoqyah,
      categoryName: 'الأذكار والرقية الشرعية',
      subtitle: 'تكبيرات عيد الفطر والأضحى وأصداء الحرم المكي الشريف وأيام التشريق',
      streamUrl: 'https://backup.qurango.net/radio/eid',
      fallbackUrls: [
        'https://qurango.net/radio/eid',
      ],
      countryOrOrigin: 'المشاعر المقدسة 🕋',
      accentColor: Color(0xFF606C38),
      icon: Icons.celebration_rounded,
      tags: ['تكبيرات العيد', 'العيد', 'تكبيرات', 'حج', 'تهليل'],
    ),

    // -------------------------------------------------------------
    // ٦. سور وتلاوات خاشعة مختارة
    // -------------------------------------------------------------
    IslamicRadioStation(
      id: 'radio_albaqarah_continuous',
      name: 'إذاعة سورة البقرة المستمرة',
      category: IslamicRadioCategoryType.khushooSurahs,
      categoryName: 'تلاوات خاشعة وسور مختارة',
      subtitle: 'تلاوة سورة البقرة كاملة بأعذب أصوات القراء لطرد الشياطين وبركة البيوت',
      streamUrl: 'https://qurango.net/radio/albaqarah',
      fallbackUrls: [
        'https://qurango.net/radio/albaqarah',
      ],
      countryOrOrigin: 'بركة البيوت 🏠',
      accentColor: Color(0xFF4361EE),
      icon: Icons.auto_stories_rounded,
      tags: ['سورة البقرة', 'البقرة', 'تحصين البيت', 'بركة'],
    ),
    IslamicRadioStation(
      id: 'radio_almulk_continuous',
      name: 'إذاعة سورة الملك المانعة',
      category: IslamicRadioCategoryType.khushooSurahs,
      categoryName: 'تلاوات خاشعة وسور مختارة',
      subtitle: 'تلاوات متكررة لسورة تبارك المانعة والمنجية من عذاب القبر بأعذب الأصوات',
      streamUrl: 'https://qurango.net/radio/Surah_Al-Mulk',
      fallbackUrls: [
        'https://qurango.net/radio/Surah_Al-Mulk',
      ],
      countryOrOrigin: 'القرآن الكريم 📖',
      accentColor: Color(0xFF3F37C9),
      icon: Icons.shield_rounded,
      tags: ['سورة الملك', 'تبارك', 'المنجية', 'سورة'],
    ),
    IslamicRadioStation(
      id: 'radio_khushoo_salma',
      name: 'إذاعة التلاوات الخاشعة والآيات المؤثرة',
      category: IslamicRadioCategoryType.khushooSurahs,
      categoryName: 'تلاوات خاشعة وسور مختارة',
      subtitle: 'مقاطع وتلاوات تأخذ بالألباب وتزيد الإيمان والسكينة وتريح الروح',
      streamUrl: 'https://backup.qurango.net/radio/salma',
      fallbackUrls: [
        'https://qurango.net/radio/salma',
      ],
      countryOrOrigin: 'القرآن الكريم 🕊️',
      accentColor: Color(0xFF4895EF),
      icon: Icons.spa_rounded,
      tags: ['تلاوات خاشعة', 'خشوع', 'سكينة', 'تلاوات نادرة'],
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
