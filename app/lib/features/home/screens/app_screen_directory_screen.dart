import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/services/support_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/text/arabic_normalizer.dart';
import '../../settings/widgets/settings_about_modal.dart';

/// نموذج بيانات عنصر دليل وفهرس شاشات تطبيق صديق المؤمن
class AppDirectoryItem {
  final String id;
  final String title;
  final String subtitle;
  final String category;
  final String categoryKey;
  final String route;
  final IconData icon;
  final Color color;
  final List<String> keywords;
  final void Function(BuildContext context)? onAction;

  const AppDirectoryItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.categoryKey,
    required this.route,
    required this.icon,
    required this.color,
    this.keywords = const [],
    this.onAction,
  });
}

/// شاشة «دليل وفهرس شاشات وأبواب تطبيق صديق المؤمن الشامل» (AppScreenDirectoryScreen)
/// توفر فهرسة هيكلية كاملة لجميع شاشات وخدمات التطبيق (٦٣ شاشة وباباً إيمانياً)
class AppScreenDirectoryScreen extends StatefulWidget {
  const AppScreenDirectoryScreen({super.key});

  @override
  State<AppScreenDirectoryScreen> createState() =>
      _AppScreenDirectoryScreenState();
}

class _AppScreenDirectoryScreenState extends State<AppScreenDirectoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AppDirectoryItem> _getAllItems(BuildContext context) {
    return [
      // ================= المقام الأول: إشراقة اليوم والمتابعة الروحانية (٥ أبواب) =================
      AppDirectoryItem(
        id: 'home_main',
        title: context.tr('nav_home'),
        subtitle: 'لوحة المتابعة اليومية، مواقيت النور، والزاد اللحظي',
        category: 'إشراقة اليوم',
        categoryKey: 'home',
        route: '/home',
        icon: Icons.wb_sunny_rounded,
        color: AppColors.primaryGreen,
        keywords: ['رئيسية', 'اليوم', 'مواقيت', 'أذكار الوقت', 'إشراقة', 'لوحة التحكم'],
      ),
      AppDirectoryItem(
        id: 'daily_wird',
        title: context.tr('daily_wird'),
        subtitle: 'جدول أوراد العبادات الموزعة ومتابعة العمل الصالح اليومي',
        category: 'إشراقة اليوم',
        categoryKey: 'home',
        route: '/daily-wird',
        icon: Icons.checklist_rtl_rounded,
        color: const Color(0xFF1B6B4E),
        keywords: ['ورد', 'يومي', 'محاسبة', 'جدول', 'طاعة', 'برنامج'],
      ),
      AppDirectoryItem(
        id: 'daawah_studio',
        title: context.tr('daawah_studio'),
        subtitle: 'تصميم بطاقات الآيات والأحاديث النبوية بخطوط وزخارف فاخرة',
        category: 'إشراقة اليوم',
        categoryKey: 'home',
        route: '/daawah-studio',
        icon: Icons.palette_rounded,
        color: AppColors.gold500,
        keywords: ['بطاقات', 'تصميم', 'دعوة', 'مشاركة', 'استوديو', 'صور'],
      ),
      const AppDirectoryItem(
        id: 'momen_duaa',
        title: 'إهداء ودعاء للمرحوم مؤمن إبراهيم',
        subtitle: 'شاشة الدعاء الخالص والصدقة الجارية لروح الفقيد رحمه الله',
        category: 'إشراقة اليوم',
        categoryKey: 'home',
        route: '/duaa',
        icon: Icons.volunteer_activism_rounded,
        color: Color(0xFF0D5C46),
        keywords: ['دعاء', 'مؤمن', 'إهداء', 'رحمه الله', 'صدقة جارية', 'مؤمن إبراهيم'],
      ),
      const AppDirectoryItem(
        id: 'onboarding',
        title: 'دليل البداية والتعريف بالمعالم',
        subtitle: 'جولة استكشافية لمعالم وخصائص تطبيق صديق المؤمن',
        category: 'إشراقة اليوم',
        categoryKey: 'home',
        route: '/onboarding',
        icon: Icons.explore_rounded,
        color: Color(0xFF25739B),
        keywords: ['ترحيب', 'بداية', 'شرح', 'تعليم', 'جولة'],
      ),

      // ================= المقام الثاني: رحاب القرآن الكريم وعلومه (٢٠ باباً) =================
      AppDirectoryItem(
        id: 'quran_hub',
        title: context.tr('holy_quran'),
        subtitle: 'البوابة الجامعة لخدمات وتلاوات وعلوم المصحف الشريف',
        category: 'رحاب القرآن',
        categoryKey: 'quran',
        route: '/mushaf',
        icon: Icons.menu_book_rounded,
        color: AppColors.emerald700,
        keywords: ['مصحف', 'قرآن', 'تلاوة', 'سور', 'أجزاء'],
      ),
      const AppDirectoryItem(
        id: 'mushaf_pages',
        title: 'المصحف برواية حفص (عرض الصفحات ٦٠٤)',
        subtitle: 'المصحف الشريف مطابق لطبعة مجمع الملك فهد بالرسم العثماني',
        category: 'رحاب القرآن',
        categoryKey: 'quran',
        route: '/mushaf-pages',
        icon: Icons.auto_stories_rounded,
        color: AppColors.emerald900,
        keywords: ['صفحات', 'رسم عثماني', 'مجمع الملك فهد', 'قراءة'],
      ),
      const AppDirectoryItem(
        id: 'surah_reader',
        title: 'قارئ السور والتلاوة والتدبر المفصل',
        subtitle: 'تلاوة الآيات متتابعة مع تشغيل الصوت والترتيل والتفسير',
        category: 'رحاب القرآن',
        categoryKey: 'quran',
        route: '/surah-reader',
        icon: Icons.chrome_reader_mode_rounded,
        color: Color(0xFF1B6B4E),
        keywords: ['قارئ', 'آيات', 'تلاوة سورة', 'استماع', 'إعراب'],
      ),
      const AppDirectoryItem(
        id: 'mushaf_interactive',
        title: 'المصحف التفاعلي المتقدم',
        subtitle: 'قراءة القرآن مع تدوين الفوائد واختيار القراء والمقامات',
        category: 'رحاب القرآن',
        categoryKey: 'quran',
        route: '/mushaf-reader',
        icon: Icons.menu_book_rounded,
        color: Color(0xFF135A43),
        keywords: ['مصحف متقدم', 'تفاعل', 'قراءة حرة'],
      ),
      const AppDirectoryItem(
        id: 'qiraat_mushaf',
        title: 'مصحف الصحابة في القراءات العشر المتواترة',
        subtitle: 'القراءات العشر من طريق الشاطبية والدرة مع توجيه القراءات',
        category: 'رحاب القرآن',
        categoryKey: 'quran',
        route: '/qiraat',
        icon: Icons.history_edu_rounded,
        color: Color(0xFF0F766E),
        keywords: ['قراءات', 'عشر', 'شاطبية', 'درة', 'صحابة', 'روايات', 'ورش', 'قالون'],
      ),
      AppDirectoryItem(
        id: 'quran_search',
        title: context.tr('quran_search'),
        subtitle: 'بحث فوري ودقيق في نصوص القرآن بالجذور والتطابق اللفظي',
        category: 'رحاب القرآن',
        categoryKey: 'quran',
        route: '/search',
        icon: Icons.search_rounded,
        color: const Color(0xFF2E7D32),
        keywords: ['بحث', 'كلمات', 'آية', 'تطابق', 'جذور'],
      ),
      AppDirectoryItem(
        id: 'comparative_tafsir',
        title: context.tr('comparative_tafsir'),
        subtitle: 'مقارنة ٩ تفاسير معتمدة (ابن كثير، الطبري، السعدي، القرطبي، إلخ)',
        category: 'رحاب القرآن',
        categoryKey: 'quran',
        route: '/comparative-tafsir',
        icon: Icons.compare_arrows_rounded,
        color: const Color(0xFF8E6C18),
        keywords: ['تفسير', 'مقارنة', 'ابن كثير', 'الطبري', 'السعدي', 'إعراب'],
      ),
      const AppDirectoryItem(
        id: 'audio_tafsir',
        title: 'المختصر الصوتي في تفسير القرآن',
        subtitle: 'تفسير الآيات صوتياً بنخبة من المشايخ عبر مركز تفسير',
        category: 'رحاب القرآن',
        categoryKey: 'quran',
        route: '/audio-tafsir',
        icon: Icons.headphones_rounded,
        color: Color(0xFF6D28D9),
        keywords: ['تفسير صوتي', 'صوتيات', 'مركز تفسير', 'استماع', 'معاني'],
      ),
      AppDirectoryItem(
        id: 'gharib_quran',
        title: context.tr('gharib_quran_dict'),
        subtitle: 'شرح مفردات القرآن الغريبة وجذورها واختبارات قياس الفهم',
        category: 'رحاب القرآن',
        categoryKey: 'quran',
        route: '/gharib-quran',
        icon: Icons.translate_rounded,
        color: const Color(0xFF1565C0),
        keywords: ['غريب', 'معاني الكلمات', 'مفردات', 'لغة القرآن'],
      ),
      const AppDirectoryItem(
        id: 'quran_irab',
        title: 'إعراب القرآن الكريم وبيانه النحوي',
        subtitle: 'الإعراب المفصل لكلمات وآيات التنزيل الحكيم لخدمة المعنى',
        category: 'رحاب القرآن',
        categoryKey: 'quran',
        route: '/quran-irab',
        icon: Icons.spellcheck_rounded,
        color: Color(0xFF0E7490),
        keywords: ['إعراب', 'نحو', 'إعراب القرآن', 'لغة', 'بيان', 'فاعل', 'مفعول'],
      ),
      const AppDirectoryItem(
        id: 'quran_asbab_nuzul',
        title: 'أسباب نزول الآيات وسياق التنزيل',
        subtitle: 'معرفة أسباب ورود الآيات والوقائع التي نزلت فيها',
        category: 'رحاب القرآن',
        categoryKey: 'quran',
        route: '/quran-asbab-nuzul',
        icon: Icons.history_rounded,
        color: Color(0xFFB45309),
        keywords: ['أسباب النزول', 'سياق التنزيل', 'نزول الآيات', 'الواحدي', 'السيوطي'],
      ),
      AppDirectoryItem(
        id: 'tadabbur_journal',
        title: context.tr('tadabbur_journal'),
        subtitle: 'تدوين ثمرات التدبر والعمل بالآيات ومحاسبة النفس الروحية',
        category: 'رحاب القرآن',
        categoryKey: 'quran',
        route: '/tadabbur-journal',
        icon: Icons.psychology_alt_rounded,
        color: const Color(0xFF283593),
        keywords: ['تدبر', 'مفكرة', 'خواطر', 'عمل بالآيات'],
      ),
      AppDirectoryItem(
        id: 'memorization',
        title: context.tr('memorization'),
        subtitle: 'المساعد الذكي للتحفيظ مع تكرار الآيات وتحديد المقاطع',
        category: 'رحاب القرآن',
        categoryKey: 'quran',
        route: '/memorization',
        icon: Icons.school_rounded,
        color: const Color(0xFF00695C),
        keywords: ['حفظ', 'تكرار', 'مراجعة', 'تحفيظ'],
      ),
      AppDirectoryItem(
        id: 'khatma',
        title: context.tr('khatma_tracker'),
        subtitle: 'سجل الختمات الزمنية واحتفالية ختم القرآن الكريم',
        category: 'رحاب القرآن',
        categoryKey: 'quran',
        route: '/khatma',
        icon: Icons.workspace_premium_rounded,
        color: AppColors.accentGold,
        keywords: ['ختمة', 'متابعة', 'دعاء الختم', 'ورد يومي'],
      ),
      const AppDirectoryItem(
        id: 'quran_notes',
        title: 'مفكرة وتدوينات الآيات',
        subtitle: 'سجل الملاحظات الشخصية والفوائد المستنبطة عند كل آية',
        category: 'رحاب القرآن',
        categoryKey: 'quran',
        route: '/notes',
        icon: Icons.note_alt_rounded,
        color: Color(0xFF4E342E),
        keywords: ['ملاحظات', 'فوائد', 'تدوين'],
      ),
      AppDirectoryItem(
        id: 'quran_sciences',
        title: context.tr('quran_sciences'),
        subtitle: 'أسباب النزول، الناسخ والمنسوخ، الوجوه والنظائر، والإعجاز',
        category: 'رحاب القرآن',
        categoryKey: 'quran',
        route: '/quran-sciences',
        icon: Icons.menu_book_rounded,
        color: const Color(0xFF004D40),
        keywords: ['علوم القرآن', 'أسباب النزول', 'الناسخ والمنسوخ'],
      ),
      AppDirectoryItem(
        id: 'tajweed',
        title: context.tr('tajweed_rules'),
        subtitle: 'أحكام التجويد الميسر بالصوت والأمثلة والتطبيقات العملية',
        category: 'رحاب القرآن',
        categoryKey: 'quran',
        route: '/tajweed',
        icon: Icons.record_voice_over_rounded,
        color: const Color(0xFF33691E),
        keywords: ['تجويد', 'أحكام', 'نون ساكنة', 'مدود', 'مخارج'],
      ),
      AppDirectoryItem(
        id: 'quran_topics',
        title: context.tr('quran_topics'),
        subtitle: 'موسوعة الموضوعات القرآنية الجامعة (عقيدة، أخلاق، تشريع)',
        category: 'رحاب القرآن',
        categoryKey: 'quran',
        route: '/topics',
        icon: Icons.category_rounded,
        color: const Color(0xFF1A237E),
        keywords: ['موضوعات', 'عقيدة', 'معاملات', 'قصص القرآن'],
      ),
      const AppDirectoryItem(
        id: 'quran_audio',
        title: 'المكتبة الصوتية لقراء القرآن (٦١ قارئاً)',
        subtitle: 'استماع وتنزيل تلاوات كاملة ومجودة لكبار قراء العالم الإسلامي',
        category: 'رحاب القرآن',
        categoryKey: 'quran',
        route: '/audio',
        icon: Icons.podcasts_rounded,
        color: Color(0xFF004D40),
        keywords: ['صوتيات', 'قراء', 'المنشاوي', 'الحصري', 'عبدالباسط'],
      ),
      const AppDirectoryItem(
        id: 'audio_downloads',
        title: 'مدير التنزيلات الصوتية',
        subtitle: 'إدارة الملفات المحفوظة للاستماع دون اتصال بالإنترنت',
        category: 'رحاب القرآن',
        categoryKey: 'quran',
        route: '/downloads',
        icon: Icons.download_for_offline_rounded,
        color: Color(0xFF37474F),
        keywords: ['تنزيلات', 'بدون نت', 'أوفلاين', 'صوتيات محملة'],
      ),

      // ================= المقام الثالث: محراب الصلاة ومواقيت النور (١٠ أبواب) =================
      AppDirectoryItem(
        id: 'prayer_main',
        title: context.tr('nav_prayer'),
        subtitle: 'مواقيت الصلاة الدقيقة، العد التنازلي، والمدينة الحالية',
        category: 'محراب الصلاة',
        categoryKey: 'prayer',
        route: '/prayer',
        icon: Icons.access_time_filled_rounded,
        color: AppColors.primaryGreen,
        keywords: ['صلاة', 'مواقيت', 'أذان', 'فجر', 'ظهر', 'عصر', 'مغرب', 'عشاء'],
      ),
      const AppDirectoryItem(
        id: 'prayer_times_detail',
        title: 'تفاصيل مواقيت الصلاة والمراحل',
        subtitle: 'أوقات الصلوات مع أوقات الإمساك والشروق والثلث الأخير',
        category: 'محراب الصلاة',
        categoryKey: 'prayer',
        route: '/prayer-times-detail',
        icon: Icons.schedule_rounded,
        color: Color(0xFF1A6B54),
        keywords: ['مواقيت تفصيلية', 'أوقات الصلاة', 'شروق', 'إمساك', 'ثلث أخير'],
      ),
      const AppDirectoryItem(
        id: 'adhan_control',
        title: 'التحكم في الأذان والتنبيهات',
        subtitle: 'اختيار أصوات المؤذنين وضبط تنبيهات الإقامة لكل صلاة',
        category: 'محراب الصلاة',
        categoryKey: 'prayer',
        route: '/adhan-control',
        icon: Icons.notifications_active_rounded,
        color: AppColors.emerald700,
        keywords: ['أذان', 'إقامة', 'منبه', 'مؤذن', 'تنبيه'],
      ),
      AppDirectoryItem(
        id: 'qibla',
        title: context.tr('qibla_compass'),
        subtitle: 'بوصلة بصرية دقيقة لتحديد اتجاه الكعبة المشرفة بمستشعرات الهاتف',
        category: 'محراب الصلاة',
        categoryKey: 'prayer',
        route: '/qibla',
        icon: Icons.explore_rounded,
        color: AppColors.gold500,
        keywords: ['قبلة', 'بوصلة', 'كعبة', 'مكة', 'اتجاه'],
      ),
      AppDirectoryItem(
        id: 'hijri_calendar',
        title: context.tr('hijri_calendar'),
        subtitle: 'التقويم الهجري والميلادي وأيام الفضائل ومواسم الخير',
        category: 'محراب الصلاة',
        categoryKey: 'prayer',
        route: '/calendar',
        icon: Icons.calendar_month_rounded,
        color: const Color(0xFF1E8260),
        keywords: ['تقويم', 'هجري', 'أيام بيض', 'مناسبات', 'أشهر حرم'],
      ),
      AppDirectoryItem(
        id: 'prayer_tracker',
        title: context.tr('prayer_tracker'),
        subtitle: 'سجل متابعة الصلوات الخمس في جماعة وقضاء ما فات بعزيمة',
        category: 'محراب الصلاة',
        categoryKey: 'prayer',
        route: '/prayer-tracker',
        icon: Icons.fact_check_rounded,
        color: AppColors.gold500,
        keywords: ['متابع الصلوات', 'قضاء', 'جماعة', 'محاسبة'],
      ),
      AppDirectoryItem(
        id: 'fajr_qiyam_alarm',
        title: context.tr('dawn_awakening'),
        subtitle: 'منبه إيماني تصاعدي للاستيقاظ لصلاة الفجر وقيام الليل',
        category: 'محراب الصلاة',
        categoryKey: 'prayer',
        route: '/fajr-qiyam-alarm',
        icon: Icons.alarm_on_rounded,
        color: AppColors.emerald700,
        keywords: ['فجر', 'قيام ليل', 'منبه فجر', 'تهجد'],
      ),
      AppDirectoryItem(
        id: 'sunan_rawatib',
        title: context.tr('sunan_rawatib'),
        subtitle: 'ثنتا عشرة ركعة في اليوم والليلة يبني الله لك بها بيتاً في الجنة',
        category: 'محراب الصلاة',
        categoryKey: 'prayer',
        route: '/sunan-rawatib',
        icon: Icons.stars_rounded,
        color: const Color(0xFF1B4332),
        keywords: ['سنن', 'رواتب', 'ركعات', 'جنة', 'نوافل'],
      ),
      AppDirectoryItem(
        id: 'voluntary_fasting',
        title: context.tr('voluntary_fasting'),
        subtitle: 'الإثنين والخميس، الأيام البيض، عاشوراء، والست من شوال',
        category: 'محراب الصلاة',
        categoryKey: 'prayer',
        route: '/voluntary-fasting',
        icon: Icons.wb_twilight_rounded,
        color: AppColors.gold500,
        keywords: ['صيام', 'نوافل', 'أيام بيض', 'عرفة', 'عاشوراء'],
      ),
      const AppDirectoryItem(
        id: 'battery_guide',
        title: 'دليل موثوقية الأذان والبطارية',
        subtitle: 'خطوات استثناء التطبيق من قيود توفير الطاقة لضمان انطلاق الأذان',
        category: 'محراب الصلاة',
        categoryKey: 'prayer',
        route: '/battery-guide',
        icon: Icons.battery_charging_full_rounded,
        color: Color(0xFFE65100),
        keywords: ['بطارية', 'أذان لا يعمل', 'تنبيهات', 'خلفية'],
      ),

      // ================= المقام الرابع: أُنس الذاكرين وسكينة القلوب (٤ أبواب) =================
      AppDirectoryItem(
        id: 'adhkar_hub',
        title: context.tr('adhkar_hub'),
        subtitle: 'البوابة الجامعة لأذكار اليوم والليلة والأدعية النبوية الجامعة',
        category: 'أُنس الذاكرين',
        categoryKey: 'adhkar',
        route: '/adhkar-hub',
        icon: Icons.favorite_rounded,
        color: const Color(0xFF1E8260),
        keywords: ['أذكار', 'تسبيح', 'صباح', 'مساء', 'دعاء'],
      ),
      const AppDirectoryItem(
        id: 'adhkar_screen',
        title: 'موسوعة حصن المسلم الكاملة',
        subtitle: 'أذكار الصباح والمساء، النوم والاستيقاظ، الصلاة، والسفر',
        category: 'أُنس الذاكرين',
        categoryKey: 'adhkar',
        route: '/adhkar',
        icon: Icons.menu_book_rounded,
        color: Color(0xFF135A43),
        keywords: ['حصن المسلم', 'صباح ومساء', 'أذكار النوم'],
      ),
      AppDirectoryItem(
        id: 'tasbih',
        title: context.tr('electronic_tasbih'),
        subtitle: 'المسبحة الإلكترونية الذكية مع ميزة الاهتزاز وحفظ العداد التلقائي',
        category: 'أُنس الذاكرين',
        categoryKey: 'adhkar',
        route: '/tasbih',
        icon: Icons.fingerprint_rounded,
        color: AppColors.accentGold,
        keywords: ['تسبيح', 'مسبحة', 'استغفار', 'عداد'],
      ),
      AppDirectoryItem(
        id: 'spiritual_mood',
        title: context.tr('spiritual_mood_remedy'),
        subtitle: 'طِبّ القلوب وسكينة المشاعر بالآيات والأدعية المناسبة لقلبك',
        category: 'أُنس الذاكرين',
        categoryKey: 'adhkar',
        route: '/spiritual-mood',
        icon: Icons.spa_rounded,
        color: AppColors.emerald700,
        keywords: ['مشاعر', 'حزن', 'ضيق', 'هم', 'سكينة', 'قلوب'],
      ),

      // ================= المقام الخامس: رياض العلم والهدي النبوي (١٧ باباً) =================
      AppDirectoryItem(
        id: 'library_main',
        title: context.tr('islamic_library'),
        subtitle: 'البوابة الكبرى لكنوز العلم الشرعي والحديث النبوي والتراث',
        category: 'رياض العلم',
        categoryKey: 'library',
        route: '/library',
        icon: Icons.auto_stories_rounded,
        color: const Color(0xFF34495E),
        keywords: ['مكتبة', 'علم', 'فقه', 'حديث', 'سيرة'],
      ),
      AppDirectoryItem(
        id: 'stories',
        title: context.tr('prophets_stories'),
        subtitle: 'قصص الأنبياء والصحابة مسموعة ومقروءة بجودة صوتية نقية',
        category: 'رياض العلم',
        categoryKey: 'library',
        route: '/stories',
        icon: Icons.record_voice_over_rounded,
        color: const Color(0xFF1565C0),
        keywords: ['قصص', 'أنبياء', 'صحابة', 'سيرة', 'عبر'],
      ),
      AppDirectoryItem(
        id: 'fiqh_library',
        title: context.tr('fiqh_library'),
        subtitle: 'الموسوعة الفقهية الميسرة: أحكام الطهارة، الصلاة، الجنائز',
        category: 'رياض العلم',
        categoryKey: 'library',
        route: '/fiqh-library',
        icon: Icons.account_balance_rounded,
        color: const Color(0xFF2E7D32),
        keywords: ['فقه', 'طهارة', 'وضوء', 'صلاة', 'أحكام'],
      ),
      AppDirectoryItem(
        id: 'asma_shamail',
        title: context.tr('asma_allah_shamail'),
        subtitle: 'أسماء الله الحسنى ومعانيها، والشمائل والأخلاق المحمدية',
        category: 'رياض العلم',
        categoryKey: 'library',
        route: '/asma-shamail',
        icon: Icons.stars_rounded,
        color: AppColors.accentGold,
        keywords: ['أسماء الله الحسنى', 'شمائل', 'نبي', 'أوصاف'],
      ),
      AppDirectoryItem(
        id: 'islamic_history',
        title: context.tr('islamic_history'),
        subtitle: 'أطلس التاريخ الإسلامي: السيرة النبوية، الخلفاء الراشدون',
        category: 'رياض العلم',
        categoryKey: 'library',
        route: '/islamic-history',
        icon: Icons.timeline_rounded,
        color: const Color(0xFF4E342E),
        keywords: ['تاريخ', 'سيرة', 'خلفاء راشدين', 'فتوحات'],
      ),
      AppDirectoryItem(
        id: 'hajj_umrah',
        title: context.tr('hajj_umrah_companion'),
        subtitle: 'رفيق الحج والعمرة التفاعلي مع عداد أشواط الطواف والسعي',
        category: 'رياض العلم',
        categoryKey: 'library',
        route: '/hajj-umrah',
        icon: Icons.explore_rounded,
        color: AppColors.emerald700,
        keywords: ['حج', 'عمرة', 'طواف', 'سعي', 'مناسك'],
      ),
      AppDirectoryItem(
        id: 'ramadan',
        title: context.tr('ramadan_seasons'),
        subtitle: 'نفحات شهر رمضان المبارك، فقه الصيام، ليلة القدر، والاعتكاف',
        category: 'رياض العلم',
        categoryKey: 'library',
        route: '/ramadan',
        icon: Icons.nightlight_round,
        color: const Color(0xFF1B6B4E),
        keywords: ['رمضان', 'صيام', 'تراويح', 'اعتكاف', 'ليلة القدر'],
      ),
      AppDirectoryItem(
        id: 'zakat',
        title: context.tr('zakat_faraid'),
        subtitle: 'حاسبة الزكاة الذكية: زكاة المال، الذهب والفضة، عروض التجارة',
        category: 'رياض العلم',
        categoryKey: 'library',
        route: '/zakat',
        icon: Icons.calculate_rounded,
        color: const Color(0xFF27AE60),
        keywords: ['زكاة', 'مال', 'ذهب', 'فضة', 'نصاب'],
      ),
      AppDirectoryItem(
        id: 'mawarith_calc',
        title: context.tr('mawarith_calc'),
        subtitle: 'حاسبة المواريث الشرعية: توزيع الأنصبة وحجب الورثة بالأدلة',
        category: 'رياض العلم',
        categoryKey: 'library',
        route: '/mawarith-calculator',
        icon: Icons.balance_rounded,
        color: const Color(0xFF1B4332),
        keywords: ['مواريث', 'تركة', 'أنصبة', 'ميراث', 'سورة النساء'],
      ),
      AppDirectoryItem(
        id: 'kaffarah_fidyah',
        title: context.tr('kaffarah_fidyah_calc'),
        subtitle: 'فقه الكفارات والفدية وزكاة الفطر والصدقات الواجبة',
        category: 'رياض العلم',
        categoryKey: 'library',
        route: '/kaffarah-fidyah',
        icon: Icons.volunteer_activism_rounded,
        color: const Color(0xFF2E7D32),
        keywords: ['كفارة', 'فدية', 'يمين', 'زكاة الفطر'],
      ),
      const AppDirectoryItem(
        id: 'islamic_radio',
        title: 'إذاعات القرآن الكريم (MP3Quran)',
        subtitle: 'بث إذاعات القرآن الكريم وتلاوات كبار القراء',
        category: 'رياض العلم',
        categoryKey: 'library',
        route: '/islamic-radio',
        icon: Icons.podcasts_rounded,
        color: Color(0xFF0F5B45),
        keywords: ['إذاعات', 'راديو', 'بث', 'قرآن', 'قراء', 'القاهرة', 'المنشاوي', 'الحصري', 'عبد الباسط'],
      ),
      AppDirectoryItem(
        id: 'egypt_heritage',
        title: context.tr('egypt_heritage'),
        subtitle: 'إذاعة القرآن الكريم • ابتهالات النقشبندي وطوبار • خواطر الشعراوي',
        category: 'رياض العلم',
        categoryKey: 'library',
        route: '/egypt-heritage',
        icon: Icons.radio_rounded,
        color: const Color(0xFF0D5C46),
        keywords: ['إذاعة القاهرة', 'ابتهالات', 'نقشبندي', 'طوبار', 'شعراوي'],
      ),
      const AppDirectoryItem(
        id: 'approved_sources',
        title: 'المصادر والمراجع المعتمدة',
        subtitle: 'قائمة كتب التفسير والفقه والحديث واللغة المعتمدة بالتطبيق',
        category: 'رياض العلم',
        categoryKey: 'library',
        route: '/approved-sources',
        icon: Icons.verified_rounded,
        color: Color(0xFF0F766E),
        keywords: ['مصادر', 'مراجع', 'كتب معتمدة', 'تحقيق', 'أصول'],
      ),
      const AppDirectoryItem(
        id: 'library_search',
        title: 'الكشاف الجامع في رياض العلم',
        subtitle: 'محرك بحث موحد في كتب الحديث والفقه والتفسير والتاريخ',
        category: 'رياض العلم',
        categoryKey: 'library',
        route: '/library-search',
        icon: Icons.manage_search_rounded,
        color: AppColors.primaryGreen,
        keywords: ['بحث شامل', 'كشاف', 'كتب', 'مكتبة كاملة'],
      ),

      // ================= المقام السادس: تهيئة التطبيق والعناية (٧ أبواب) =================
      AppDirectoryItem(
        id: 'settings',
        title: context.tr('settings_title'),
        subtitle: 'ضبط اللغات، المظهر الداكن، خطوط المصحف، وتنبيهات الأذان',
        category: 'العناية والإعدادات',
        categoryKey: 'settings',
        route: '/settings',
        icon: Icons.tune_rounded,
        color: const Color(0xFF2C5E43),
        keywords: ['إعدادات', 'مظهر', 'خط', 'لغات', 'تهيئة'],
      ),
      AppDirectoryItem(
        id: 'backup',
        title: context.tr('backup_restore'),
        subtitle: 'حفظ واسترجاع سجلات الختمات والملاحظات والصلوات بأمان',
        category: 'العناية والإعدادات',
        categoryKey: 'settings',
        route: '/backup',
        icon: Icons.backup_rounded,
        color: const Color(0xFF5E4E8C),
        keywords: ['نسخ احتياطي', 'استرجاع', 'مزامنة', 'حفظ البيانات'],
      ),
      AppDirectoryItem(
        id: 'support',
        title: context.tr('contact_support'),
        subtitle: 'التواصل المباشر مع المطور وإرسال المقترحات والملاحظات',
        category: 'العناية والإعدادات',
        categoryKey: 'settings',
        route: '/support',
        icon: Icons.headset_mic_rounded,
        color: const Color(0xFF25739B),
        keywords: ['دعم', 'تواصل', 'مقترحات', 'فريق البرمجة'],
      ),
      AppDirectoryItem(
        id: 'about_app',
        title: 'عن تطبيق صديق المؤمن (الإصدار السابع v7.0)',
        subtitle: 'الرؤية الوقفية، المعالم الكبرى، وخلوه التام من الإعلانات والتتبع',
        category: 'العناية والإعدادات',
        categoryKey: 'settings',
        route: '/settings',
        icon: Icons.info_rounded,
        color: AppColors.accentGold,
        keywords: ['عن التطبيق', 'معلومات', 'إصدار', 'وقفي', 'بدون إعلانات', 'v7.0', 'صديق المؤمن'],
        onAction: (ctx) => showSettingsAboutModal(ctx),
      ),
      const AppDirectoryItem(
        id: 'about_developer',
        title: 'عن المطور ورابط المشروع',
        subtitle: 'نبذة عن المهندس أحمد إبراهيم، المشروع الوقفي، ومستودع GitHub',
        category: 'العناية والإعدادات',
        categoryKey: 'settings',
        route: '/about-developer',
        icon: Icons.person_pin_rounded,
        color: AppColors.primaryGreen,
        keywords: ['مطور', 'أحمد إبراهيم', 'جيت هاب', 'github', 'مفتوح المصدر', 'عن المطور'],
      ),
      AppDirectoryItem(
        id: 'developer_apps',
        title: 'برامج وتطبيقات المطور على Google Play',
        subtitle: 'استكشاف باقي البرمجيات والأنظمة الإسلامية للمطور على المتجر',
        category: 'العناية والإعدادات',
        categoryKey: 'settings',
        route: '/about-developer',
        icon: Icons.shop_two_rounded,
        color: const Color(0xFF0284C7),
        keywords: ['برامج المطور', 'متجر', 'جوجل بلاي', 'google play', 'store', 'تطبيقات'],
        onAction: (ctx) => SupportService.openDeveloperPlayStore(context: ctx),
      ),
      AppDirectoryItem(
        id: 'developer_facebook',
        title: 'حساب وصفحة المطور على فيسبوك',
        subtitle: 'التواصل المباشر مع المطور ومتابعة أحدث التحديثات البرمجية',
        category: 'العناية والإعدادات',
        categoryKey: 'settings',
        route: '/about-developer',
        icon: Icons.facebook_rounded,
        color: const Color(0xFF1877F2),
        keywords: ['فيسبوك', 'facebook', 'حساب المطور', 'تواصل', 'صفحة'],
        onAction: (ctx) => SupportService.openDeveloperFacebook(context: ctx),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final allItems = _getAllItems(context);

    final homeCount = allItems.where((i) => i.categoryKey == 'home').length;
    final quranCount = allItems.where((i) => i.categoryKey == 'quran').length;
    final prayerCount = allItems.where((i) => i.categoryKey == 'prayer').length;
    final adhkarCount = allItems.where((i) => i.categoryKey == 'adhkar').length;
    final libraryCount = allItems.where((i) => i.categoryKey == 'library').length;
    final settingsCount = allItems.where((i) => i.categoryKey == 'settings').length;

    // Apply Filter
    final filteredItems = allItems.where((item) {
      final matchesCategory = _selectedCategory == 'all' ||
          item.categoryKey == _selectedCategory;
      if (!matchesCategory) return false;

      if (_searchQuery.isEmpty) return true;

      final normQuery =
          ArabicNormalizer.normalize(_searchQuery, loose: true).toLowerCase();
      final normTitle =
          ArabicNormalizer.normalize(item.title, loose: true).toLowerCase();
      final normSub =
          ArabicNormalizer.normalize(item.subtitle, loose: true).toLowerCase();

      final matchesText = normTitle.contains(normQuery) ||
          normSub.contains(normQuery) ||
          item.keywords.any((k) =>
              ArabicNormalizer.normalize(k, loose: true)
                  .toLowerCase()
                  .contains(normQuery));

      return matchesText;
    }).toList();

    return AnimatedBuilder(
      animation: SettingsService.instance,
      builder: (context, _) {
        final s = SettingsService.instance;

        return Directionality(
          textDirection: s.textDirection,
          child: Scaffold(
            appBar: AppBar(
              title: const Text(
                'فهرس ودليل الشاشات الشامل',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(105),
                child: Column(
                  children: [
                    // Search Field
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (val) =>
                            setState(() => _searchQuery = val.trim()),
                        decoration: InputDecoration(
                          hintText: 'ابحث في كافة أبواب وخدمات التطبيق (${allItems.length} شاشة)...',
                          prefixIcon: const Icon(Icons.search_rounded,
                              size: 20, color: AppColors.primaryGreen),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded,
                                      size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 16),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: isDark
                              ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)
                              : Colors.grey.withValues(alpha: 0.08),
                        ),
                      ),
                    ),

                    // Filter Chips Bar
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      child: Row(
                        children: [
                          _buildFilterChip('الكل (${allItems.length})', 'all',
                              Icons.grid_view_rounded),
                          const SizedBox(width: 6),
                          _buildFilterChip('إشراقة اليوم ($homeCount)', 'home',
                              Icons.wb_sunny_rounded),
                          const SizedBox(width: 6),
                          _buildFilterChip('رحاب القرآن ($quranCount)', 'quran',
                              Icons.menu_book_rounded),
                          const SizedBox(width: 6),
                          _buildFilterChip('محراب الصلاة ($prayerCount)', 'prayer',
                              Icons.access_time_filled_rounded),
                          const SizedBox(width: 6),
                          _buildFilterChip('أُنس الذاكرين ($adhkarCount)', 'adhkar',
                              Icons.favorite_rounded),
                          const SizedBox(width: 6),
                          _buildFilterChip('رياض العلم ($libraryCount)', 'library',
                              Icons.auto_stories_rounded),
                          const SizedBox(width: 6),
                          _buildFilterChip('العناية والإعدادات ($settingsCount)', 'settings',
                              Icons.tune_rounded),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ),
            body: filteredItems.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.search_off_rounded,
                              size: 48, color: Colors.grey),
                          const SizedBox(height: 12),
                          Text(
                            'لم يتم العثور على أبواب تطابق: "$_searchQuery"',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('إعادة عرض كافة الشاشات'),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                                _selectedCategory = 'all';
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: filteredItems.length,
                    itemBuilder: (context, index) {
                      final item = filteredItems[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 4),
                            leading: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: item.color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: item.color.withValues(alpha: 0.3)),
                              ),
                              child: Icon(item.icon,
                                  color: item.color, size: 22),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: item.color.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    item.category,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: item.color,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                item.subtitle,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.grey,
                                  height: 1.35,
                                ),
                              ),
                            ),
                            trailing: const Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 15,
                              color: Colors.grey,
                            ),
                            onTap: () {
                              if (item.onAction != null) {
                                item.onAction!(context);
                              } else if (item.route.isNotEmpty) {
                                context.push(item.route);
                              }
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(String label, String key, IconData icon) {
    final isSelected = _selectedCategory == key;
    return ChoiceChip(
      selected: isSelected,
      showCheckmark: false,
      avatar: Icon(
        icon,
        size: 15,
        color: isSelected ? Colors.white : AppColors.primaryGreen,
      ),
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 11.5,
        fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
        color: isSelected ? Colors.white : null,
      ),
      selectedColor: AppColors.primaryGreen,
      onSelected: (selected) {
        if (selected) {
          setState(() => _selectedCategory = key);
        }
      },
    );
  }
}
