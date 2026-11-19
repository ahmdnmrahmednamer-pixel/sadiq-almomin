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
      title: 'إذاعات القرآن الكريم',
      icon: Icons.radio_rounded,
    ),
    IslamicRadioCategory(
      type: IslamicRadioCategoryType.reciters,
      title: 'تلاوات كبار القراء',
      icon: Icons.record_voice_over_rounded,
    ),
    IslamicRadioCategory(
      type: IslamicRadioCategoryType.khushooSurahs,
      title: 'تلاوات خاشعة وسور مختارة',
      icon: Icons.spa_rounded,
    ),
  ];

  /// Catalog retained for saved favorite compatibility. Only Quran categories
  /// are exposed by getStations. Cairo uses its official site's HTTPS player:
  /// https://misrquran.gov.eg/home (verified 2026-11-19).
  /// Other streams: https://mp3quran.net/api/v3/radios?language=ar
  static const List<IslamicRadioStation> defaultStations = [
    // -------------------------------------------------------------
    // ١. إذاعات القرآن العامة والبث المباشر
    // -------------------------------------------------------------
    IslamicRadioStation(
      id: 'radio_cairo_live',
      name: 'إذاعة القرآن الكريم من القاهرة',
      category: IslamicRadioCategoryType.generalLive,
      categoryName: 'إذاعات القرآن الكريم',
      subtitle: 'البث المباشر من الموقع الرسمي لإذاعة القرآن الكريم من القاهرة عبر اتصال مشفر',
      streamUrl: 'https://service.webvideocore.net/CL1olYogIrDWvwqiIKK7eCxOS4PStqG9DuEjAr2ZjZQtvS3d4y9r0cvRhvS17SGN/a_7a4vuubc6mo8.m3u8',
      fallbackUrls: [],
      countryOrOrigin: 'مصر',
      accentColor: Color(0xFF0F5B45),
      icon: Icons.radio_rounded,
      tags: ['القاهرة', 'القرآن الكريم', 'بث مباشر', 'مصر'],
    ),
    // MP3Quran ID: 108
    IslamicRadioStation(
      id: 'radio_general_recitations',
      name: 'الإذاعة العامة — تلاوات متنوعة لمختلف القراء',
      category: IslamicRadioCategoryType.generalLive,
      categoryName: 'إذاعات القرآن الكريم',
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
      categoryName: 'تلاوات كبار القراء',
      subtitle: 'تلاوات مرتلة من المصحف المرتل بصوت الشيخ محمد صديق المنشاوي',
      streamUrl: 'https://backup.qurango.net/radio/mohammed_siddiq_alminshawi',
      fallbackUrls: [
        'https://qurango.net/radio/mohammed_siddiq_alminshawi',
      ],
      countryOrOrigin: 'مصر 🇪🇬',
      accentColor: Color(0xFFC08A3E),
      icon: Icons.record_voice_over_rounded,
      tags: ['المنشاوي', 'مرتل', 'مصر', 'تلاوات خاشعة'],
    ),
    IslamicRadioStation(
      id: 'radio_husary',
      name: 'إذاعة الشيخ محمود خليل الحصري',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'تلاوات كبار القراء',
      subtitle: 'تلاوات مجودة بصوت الشيخ محمود خليل الحصري',
      streamUrl: 'https://qurango.net/radio/mahmoud_khalil_alhussary_mojawwad',
      fallbackUrls: [
        'https://backup.qurango.net/radio/mahmoud_khalil_alhussary_mojawwad',
      ],
      countryOrOrigin: 'مصر 🇪🇬',
      accentColor: Color(0xFF2D6A4F),
      icon: Icons.record_voice_over_rounded,
      tags: ['الحصري', 'مجود', 'المقارئ', 'مصر'],
    ),
    IslamicRadioStation(
      id: 'radio_abdulbasit',
      name: 'إذاعة الشيخ عبد الباسط عبد الصمد',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'تلاوات كبار القراء',
      subtitle: 'تلاوات مرتلة بصوت الشيخ عبد الباسط عبد الصمد',
      streamUrl: 'https://backup.qurango.net/radio/abdulbasit_abdulsamad',
      fallbackUrls: [
        'https://qurango.net/radio/abdulbasit_abdulsamad',
      ],
      countryOrOrigin: 'مصر 🇪🇬',
      accentColor: Color(0xFFD4A373),
      icon: Icons.record_voice_over_rounded,
      tags: ['عبد الباسط', 'مرتل', 'روائع', 'مصر'],
    ),
    IslamicRadioStation(
      id: 'radio_mustafa_ismail',
      name: 'إذاعة الشيخ مصطفى إسماعيل',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'تلاوات كبار القراء',
      subtitle: 'تلاوات قرآنية مجودة بصوت الشيخ مصطفى إسماعيل',
      streamUrl: 'https://qurango.net/radio/mustafa_ismail',
      fallbackUrls: [
        'https://backup.qurango.net/radio/mustafa_ismail',
      ],
      countryOrOrigin: 'مصر 🇪🇬',
      accentColor: Color(0xFF4A7C59),
      icon: Icons.record_voice_over_rounded,
      tags: ['مصطفى إسماعيل', 'تلاوات خاشعة', 'مقامات', 'تجويد'],
    ),
    IslamicRadioStation(
      id: 'radio_tablaway',
      name: 'إذاعة الشيخ محمد محمود الطبلاوي',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'تلاوات كبار القراء',
      subtitle: 'تلاوات قرآنية بصوت الشيخ محمد محمود الطبلاوي',
      streamUrl: 'https://backup.qurango.net/radio/mohammad_altablaway',
      fallbackUrls: [
        'https://qurango.net/radio/mohammad_altablaway',
      ],
      countryOrOrigin: 'مصر 🇪🇬',
      accentColor: Color(0xFFBC6C25),
      icon: Icons.record_voice_over_rounded,
      tags: ['الطبلاوي', 'تلاوات خاشعة', 'مصر', 'تلاوة'],
    ),
    IslamicRadioStation(
      id: 'radio_banna',
      name: 'إذاعة الشيخ محمود علي البنا',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'تلاوات كبار القراء',
      subtitle: 'تلاوات قرآنية بصوت الشيخ محمود علي البنا',
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
      categoryName: 'تلاوات كبار القراء',
      subtitle: 'تلاوات مرتلة بصوت الشيخ مشاري العفاسي',
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
      categoryName: 'تلاوات كبار القراء',
      subtitle: 'تلاوات مرتلة خاشعة بصوت القارئ الشيخ ماهر المعيقلي',
      streamUrl: 'https://backup.qurango.net/radio/maher',
      fallbackUrls: [
        'https://qurango.net/radio/maher',
      ],
      countryOrOrigin: 'قراء وأئمة',
      accentColor: Color(0xFF0077B6),
      icon: Icons.record_voice_over_rounded,
      tags: ['ماهر المعيقلي', 'المصحف المرتل', 'تلاوات خاشعة'],
    ),
    IslamicRadioStation(
      id: 'radio_sudais',
      name: 'إذاعة الشيخ عبد الرحمن السديس',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'تلاوات كبار القراء',
      subtitle: 'تلاوات مرتلة خاشعة بصوت القارئ الشيخ عبد الرحمن السديس',
      streamUrl: 'https://qurango.net/radio/abdulrahman_alsudaes',
      fallbackUrls: [
        'https://backup.qurango.net/radio/abdulrahman_alsudaes',
      ],
      countryOrOrigin: 'قراء وأئمة',
      accentColor: Color(0xFF8338EC),
      icon: Icons.record_voice_over_rounded,
      tags: ['السديس', 'عبد الرحمن السديس', 'المصحف المرتل'],
    ),
    IslamicRadioStation(
      id: 'radio_shuraim',
      name: 'إذاعة الشيخ سعود الشريم',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'تلاوات كبار القراء',
      subtitle: 'تلاوات مرتلة خاشعة بصوت القارئ الشيخ سعود الشريم',
      streamUrl: 'https://qurango.net/radio/saud_alshuraim',
      fallbackUrls: [
        'https://backup.qurango.net/radio/saud_alshuraim',
      ],
      countryOrOrigin: 'قراء وأئمة',
      accentColor: Color(0xFF023E8A),
      icon: Icons.record_voice_over_rounded,
      tags: ['سعود الشريم', 'الشريم', 'المصحف المرتل'],
    ),
    IslamicRadioStation(
      id: 'radio_ali_jaber',
      name: 'إذاعة الشيخ علي جابر',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'تلاوات كبار القراء',
      subtitle: 'تلاوات مرتلة خاشعة بصوت القارئ الشيخ علي جابر',
      streamUrl: 'https://backup.qurango.net/radio/ali_jaber',
      fallbackUrls: [
        'https://qurango.net/radio/ali_jaber',
      ],
      countryOrOrigin: 'قراء وأئمة',
      accentColor: Color(0xFF0096C7),
      icon: Icons.record_voice_over_rounded,
      tags: ['علي جابر', 'المصحف المرتل', 'تلاوات خاشعة'],
    ),
    IslamicRadioStation(
      id: 'radio_fares_abbad',
      name: 'إذاعة الشيخ فارس عباد',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'تلاوات كبار القراء',
      subtitle: 'تلاوات مرتلة بصوت الشيخ فارس عباد',
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
      categoryName: 'تلاوات كبار القراء',
      subtitle: 'تلاوات مرتلة بصوت القارئ الشيخ صلاح البدير',
      streamUrl: 'https://qurango.net/radio/salah_albudair',
      fallbackUrls: [
        'https://backup.qurango.net/radio/salah_albudair',
      ],
      countryOrOrigin: 'قراء وأئمة',
      accentColor: Color(0xFF028090),
      icon: Icons.record_voice_over_rounded,
      tags: ['صلاح البدير', 'المصحف المرتل', 'تلاوات شجية'],
    ),
    IslamicRadioStation(
      id: 'radio_abdullah_aljohany',
      name: 'إذاعة الشيخ عبد الله عواد الجهني',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'تلاوات كبار القراء',
      subtitle: 'تلاوات مرتلة بصوت القارئ الشيخ عبد الله عواد الجهني',
      streamUrl: 'https://backup.qurango.net/radio/abdullah_aljohany',
      fallbackUrls: [
        'https://qurango.net/radio/abdullah_aljohany',
      ],
      countryOrOrigin: 'قراء وأئمة',
      accentColor: Color(0xFF00A896),
      icon: Icons.record_voice_over_rounded,
      tags: ['عبد الله الجهني', 'المصحف المرتل', 'تلاوات خاشعة'],
    ),
    IslamicRadioStation(
      id: 'radio_nasser_alqatami',
      name: 'إذاعة الشيخ ناصر القطامي',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'تلاوات كبار القراء',
      subtitle: 'تلاوات من صلوات التراويح والقيام بصوت الشيخ ناصر القطامي',
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
      categoryName: 'تلاوات كبار القراء',
      subtitle: 'تلاوات مرتلة بصوت القارئ الشيخ ياسر الدوسري',
      streamUrl: 'https://backup.qurango.net/radio/yasser_aldosari',
      fallbackUrls: [
        'https://qurango.net/radio/yasser_aldosari',
      ],
      countryOrOrigin: 'قراء وأئمة',
      accentColor: Color(0xFF2B9348),
      icon: Icons.record_voice_over_rounded,
      tags: ['ياسر الدوسري', 'المصحف المرتل', 'تلاوات خاشعة'],
    ),
    IslamicRadioStation(
      id: 'radio_ajmy',
      name: 'إذاعة الشيخ أحمد بن علي العجمي',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'تلاوات كبار القراء',
      subtitle: 'تلاوات مرتلة بصوت الشيخ أحمد العجمي',
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
      categoryName: 'تلاوات كبار القراء',
      subtitle: 'تلاوات مرتلة بصوت الشيخ أبي بكر الشاطري',
      streamUrl: 'https://qurango.net/radio/shaik_abu_bakr_al_shatri',
      fallbackUrls: [
        'https://backup.qurango.net/radio/shaik_abu_bakr_al_shatri',
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
      categoryName: 'تلاوات كبار القراء',
      subtitle: 'تلاوات وأدعية بصوت الشيخ إدريس أبكر',
      streamUrl: 'https://qurango.net/radio/idrees_abkr',
      fallbackUrls: [
        'https://backup.qurango.net/radio/idrees_abkr',
      ],
      countryOrOrigin: 'الإمارات 🇦🇪',
      accentColor: Color(0xFFAACC00),
      icon: Icons.record_voice_over_rounded,
      tags: ['إدريس أبكر', 'أبكر', 'دعاء', 'قيام الليل', 'تلاوات خاشعة'],
    ),
    IslamicRadioStation(
      id: 'radio_hazza_albalushi',
      name: 'إذاعة الشيخ هزاع البلوشي',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'تلاوات كبار القراء',
      subtitle: 'تلاوات مرتلة بصوت الشيخ هزاع البلوشي',
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
      categoryName: 'تلاوات كبار القراء',
      subtitle: 'تلاوات مرتلة بصوت القارئ الشيخ عبد المحسن القاسم',
      streamUrl: 'https://backup.qurango.net/radio/abdulmohsen_alqasim',
      fallbackUrls: [
        'https://qurango.net/radio/abdulmohsen_alqasim',
      ],
      countryOrOrigin: 'قراء وأئمة',
      accentColor: Color(0xFF62B6CB),
      icon: Icons.record_voice_over_rounded,
      tags: ['عبد المحسن القاسم', 'المصحف المرتل', 'تلاوات خاشعة'],
    ),
    IslamicRadioStation(
      id: 'radio_khalifa_altunaiji',
      name: 'إذاعة الشيخ خليفة الطنيجي',
      category: IslamicRadioCategoryType.reciters,
      categoryName: 'تلاوات كبار القراء',
      subtitle: 'تلاوات مرتلة بصوت الشيخ خليفة الطنيجي',
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
      categoryName: 'تلاوات كبار القراء',
      subtitle: 'تلاوات مرتلة وأدعية بصوت الشيخ هاني الرفاعي',
      streamUrl: 'https://backup.qurango.net/radio/hani_arrifai',
      fallbackUrls: [
        'https://qurango.net/radio/hani_arrifai',
      ],
      countryOrOrigin: 'السعودية 🇸🇦',
      accentColor: Color(0xFF9F86C0),
      icon: Icons.record_voice_over_rounded,
      tags: ['هاني الرفاعي', 'تلاوات خاشعة', 'تضرع', 'تلاوات'],
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
    // MP3Quran ID: 104
    // ملاحظة فنية: خادم المرآة https://qurango.net/radio/eid قد يعيد 502 في بعض الفترات؛ خادم backup.qurango.net الأساسي مستقر ويعيد HTTP 200
    IslamicRadioStation(
      id: 'radio_eid_takbeerat',
      name: 'إذاعة تكبيرات العيد وأيام التشريق',
      category: IslamicRadioCategoryType.adhkarRoqyah,
      categoryName: 'الأذكار والرقية الشرعية',
      subtitle: 'تكبيرات عيد الفطر والأضحى المبارك وأيام التشريق بأصوات جماعية خاشعة',
      streamUrl: 'https://backup.qurango.net/radio/eid',
      fallbackUrls: [
        'https://qurango.net/radio/eid',
      ],
      countryOrOrigin: 'تكبيرات وسنن',
      accentColor: Color(0xFF606C38),
      icon: Icons.celebration_rounded,
      tags: ['تكبيرات العيد', 'العيد', 'تكبيرات', 'أيام التشريق', 'تهليل'],
    ),

    // -------------------------------------------------------------
    // ٦. سور وتلاوات خاشعة مختارة
    // -------------------------------------------------------------
    IslamicRadioStation(
      id: 'radio_albaqarah_continuous',
      name: 'إذاعة سورة البقرة المستمرة',
      category: IslamicRadioCategoryType.khushooSurahs,
      categoryName: 'تلاوات خاشعة وسور مختارة',
      subtitle: 'تلاوة سورة البقرة كاملة بصوت عدد من كبار القراء',
      streamUrl: 'https://qurango.net/radio/albaqarah',
      fallbackUrls: [
        'https://backup.qurango.net/radio/albaqarah',
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
      subtitle: 'تلاوات متكررة لسورة الملك بصوت عدد من كبار القراء',
      streamUrl: 'https://qurango.net/radio/Surah_Al-Mulk',
      fallbackUrls: [
        'https://backup.qurango.net/radio/Surah_Al-Mulk',
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
      subtitle: 'باقة من التلاوات القرآنية الخاشعة المتنوعة',
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
      subtitle: 'ترتيل هادئ وتلاوات مرتلة لمختلف القراء',
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

  static bool isQuranCategory(IslamicRadioCategoryType category) =>
      category == IslamicRadioCategoryType.generalLive ||
      category == IslamicRadioCategoryType.reciters ||
      category == IslamicRadioCategoryType.khushooSurahs;

  /// تصفية المحطات حسب التصنيف والبحث والمفضلة
  List<IslamicRadioStation> getStations({
    IslamicRadioCategoryType category = IslamicRadioCategoryType.all,
    String query = '',
    bool favoritesOnly = false,
  }) {
    final cleanQuery = ArabicNormalizer.normalize(query.trim(), loose: true);

    return defaultStations.where((station) {
      if (!isQuranCategory(station.category)) return false;
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
