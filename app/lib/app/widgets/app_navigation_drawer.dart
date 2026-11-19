import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/support_service.dart';
import '../../core/text/arabic_normalizer.dart';
import '../../core/theme/app_theme.dart';
import '../../features/settings/widgets/settings_about_modal.dart';
import '../../features/settings/widgets/settings_adhan_voice_modal.dart';

class _DrawerItemData {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String categoryKey;
  final String semanticLabel;
  final VoidCallback onTap;
  final List<String> keywords;

  const _DrawerItemData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.categoryKey,
    required this.semanticLabel,
    required this.onTap,
    this.keywords = const [],
  });
}

/// القائمة الجانبية الإيمانية الشاملة والذكية (Navigation Menu)
/// تدعم البحث اللحظي، والتنقل المنظم بين الأقسام، والفهرسة الكاملة
class AppNavigationDrawer extends StatefulWidget {
  const AppNavigationDrawer({super.key});

  @override
  State<AppNavigationDrawer> createState() => _AppNavigationDrawerState();
}

class _AppNavigationDrawerState extends State<AppNavigationDrawer> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_DrawerItemData> _buildAllItems(BuildContext context) {
    return [
      // ================= 1. قسم القرآن الكريم وقراء التلاوة =================
      _DrawerItemData(
        title: 'المصحف الشريف وتلاوة الآيات',
        subtitle: 'قراءة السور بالرسم العثماني والآية متبوعة برقمها',
        semanticLabel: 'المصحف الشريف وتلاوة الآيات',
        icon: Icons.menu_book_rounded,
        color: AppColors.primaryGreen,
        categoryKey: 'quran',
        keywords: ['مصحف', 'قرآن', 'سور', 'تلاوة', 'آيات', 'أجزاء'],
        onTap: () {
          Navigator.pop(context);
          context.go('/mushaf');
        },
      ),
      _DrawerItemData(
        title: 'بوابة القرآن الكريم وعلومه الشاملة 📖',
        subtitle: 'المحاور الـ ٦: التلاوة، التفسير، الإعراب، وأسباب النزول',
        semanticLabel: 'بوابة القرآن الكريم وعلومه الشاملة',
        icon: Icons.dashboard_customize_rounded,
        color: const Color(0xFF1B6B4E),
        categoryKey: 'quran',
        keywords: ['بوابة', 'محاور', 'علوم', 'تفسير', 'إعراب', 'أسباب النزول'],
        onTap: () {
          Navigator.pop(context);
          context.push('/quran-hub');
        },
      ),
      _DrawerItemData(
        title: 'قراء القرآن الكريم والاستماع (61 قارئاً) 🎧',
        subtitle: 'اختيار القارئ من القائمة المنسدلة والاستماع لعينات التلاوة',
        semanticLabel: 'قراء القرآن الكريم والاستماع',
        icon: Icons.record_voice_over_rounded,
        color: AppColors.accentGold,
        categoryKey: 'quran',
        keywords: ['قراء', 'استماع', 'صوتيات', 'مشايخ', 'تلاوات'],
        onTap: () {
          Navigator.pop(context);
          context.push('/audio');
        },
      ),
      _DrawerItemData(
        title: 'ختمة القرآن الكريم والورد اليومي',
        subtitle: 'متابعة الختمة وحفظ التقدم وتدبر الآيات',
        semanticLabel: 'ختمة القرآن الكريم والورد اليومي',
        icon: Icons.bookmark_added_rounded,
        color: const Color(0xFF1E8260),
        categoryKey: 'quran',
        keywords: ['ختمة', 'ورد', 'حفظ', 'متابعة'],
        onTap: () {
          Navigator.pop(context);
          context.push('/khatma');
        },
      ),
      _DrawerItemData(
        title: 'مصحف الصحابة في القراءات العشر 📜',
        subtitle: 'القراءات العشر المتواترة من طريق الشاطبية والدرة وتوجيهها',
        semanticLabel: 'مصحف الصحابة في القراءات العشر',
        icon: Icons.auto_stories_rounded,
        color: const Color(0xFF0F766E),
        categoryKey: 'quran',
        keywords: ['قراءات', 'عشر', 'شاطبية', 'درة', 'صحابة'],
        onTap: () {
          Navigator.pop(context);
          context.push('/qiraat');
        },
      ),
      _DrawerItemData(
        title: 'المختصر الصوتي في تفسير القرآن 🎧',
        subtitle: 'مركز تفسير للدراسات القرآنية (الأسمري، الغامدي، الشايع)',
        semanticLabel: 'المختصر الصوتي في تفسير القرآن',
        icon: Icons.record_voice_over_rounded,
        color: const Color(0xFF6D28D9),
        categoryKey: 'quran',
        keywords: ['تفسير', 'صوتي', 'مختصر', 'معاني'],
        onTap: () {
          Navigator.pop(context);
          context.push('/audio-tafsir');
        },
      ),

      // ================= 2. قسم الصلاة والأذان والمؤذنون =================
      _DrawerItemData(
        title: 'أصوات الأذان والمؤذنون الـ 7 🕌',
        subtitle: 'استماع وتخصيص أذان القطامي، المنشاوي، النقشبندي، عبد الباسط، الحصري، عباد، الدوسري',
        semanticLabel: 'أصوات الأذان وتخصيص المؤذنين',
        icon: Icons.mosque_rounded,
        color: const Color(0xFFD97706),
        categoryKey: 'prayer',
        keywords: ['أذان', 'مؤذنون', 'مؤذن', 'صوت', 'تخصيص'],
        onTap: () {
          Navigator.pop(context);
          showSettingsAdhanVoiceModal(context);
        },
      ),
      _DrawerItemData(
        title: 'دعاء الشيخ الشعراوي بعد الأذان 🎧',
        subtitle: 'استماع فوري وتفعيل التشغيل التلقائي عقب كل أذان',
        semanticLabel: 'دعاء الشيخ الشعراوي بعد الأذان',
        icon: Icons.volume_up_rounded,
        color: AppColors.accentGold,
        categoryKey: 'prayer',
        keywords: ['شعراوي', 'دعاء', 'أذان', 'تلقائي', 'وسيلة'],
        onTap: () {
          Navigator.pop(context);
          context.push('/adhan-control');
        },
      ),
      _DrawerItemData(
        title: 'مواقيت الصلاة وبوصلة القبلة 🧭',
        subtitle: 'المواقيت الدقيقة للصلوات الخمس واتجاه الكعبة',
        semanticLabel: 'مواقيت الصلاة وبوصلة القبلة',
        icon: Icons.access_time_filled_rounded,
        color: const Color(0xFF25739B),
        categoryKey: 'prayer',
        keywords: ['مواقيت', 'صلاة', 'قبلة', 'كعبة', 'فجر', 'ظهر', 'عصر', 'مغرب', 'عشاء'],
        onTap: () {
          Navigator.pop(context);
          context.go('/prayer');
        },
      ),
      _DrawerItemData(
        title: 'منبه الفجر وقيام الليل الذكي ⏰',
        subtitle: 'إيقاظ دقيق قبل الفجر بنغمات قرآنية وأذكار الاستيقاظ',
        semanticLabel: 'منبه الفجر وقيام الليل',
        icon: Icons.alarm_rounded,
        color: const Color(0xFF3B82F6),
        categoryKey: 'prayer',
        keywords: ['منبه', 'فجر', 'قيام', 'استيقاظ', 'سحر'],
        onTap: () {
          Navigator.pop(context);
          context.push('/fajr-qiyam-alarm');
        },
      ),
      _DrawerItemData(
        title: 'سجل ومتابعة الصلوات والسنن الرواتب 📊',
        subtitle: 'متابعة أداء الفروض والسنن والتشخيص الإيماني الأسبوعي',
        semanticLabel: 'سجل ومتابعة الصلوات',
        icon: Icons.fact_check_rounded,
        color: const Color(0xFF10B981),
        categoryKey: 'prayer',
        keywords: ['سجل', 'متابعة', 'سنن', 'رواتب', 'صلوات'],
        onTap: () {
          Navigator.pop(context);
          context.push('/prayer-tracker');
        },
      ),

      // ================= 3. قسم مكتبة العلماء والدروس =================
      _DrawerItemData(
        title: 'إذاعات القرآن الكريم (MP3Quran) 📻',
        subtitle: 'بث إذاعات القرآن الكريم وتلاوات كبار القراء',
        semanticLabel: 'إذاعات القرآن الكريم',
        icon: Icons.podcasts_rounded,
        color: const Color(0xFF0F5B45),
        categoryKey: 'scholars',
        keywords: ['إذاعات', 'راديو', 'بث', 'قرآن', 'قراء', 'القاهرة', 'المنشاوي', 'الحصري', 'عبد الباسط'],
        onTap: () {
          Navigator.pop(context);
          context.push('/islamic-radio');
        },
      ),
      _DrawerItemData(
        title: 'إذاعة وتراث القرآن الكريم بمصر 📻',
        subtitle: 'تسجيلات نادرة وعبق التلاوة المصرية الخالدة',
        semanticLabel: 'إذاعة وتراث القرآن الكريم',
        icon: Icons.radio_rounded,
        color: const Color(0xFF8B5CF6),
        categoryKey: 'scholars',
        keywords: ['تراث', 'إذاعة', 'مصر', 'تسجيلات', 'نادرة'],
        onTap: () {
          Navigator.pop(context);
          context.push('/egypt-heritage');
        },
      ),

      // ================= 4. قسم الأذكار وحصن المسلم والسبحة =================
      _DrawerItemData(
        title: 'أذكار المسلم وحصن المسلم 🤲',
        subtitle: 'أذكار الصباح والمساء والصلوات وحفظ النفس',
        semanticLabel: 'أذكار المسلم وحصن المسلم',
        icon: Icons.volunteer_activism_rounded,
        color: const Color(0xFF059669),
        categoryKey: 'adhkar',
        keywords: ['أذكار', 'حصن المسلم', 'صباح', 'مساء', 'دعاء'],
        onTap: () {
          Navigator.pop(context);
          context.go('/adhkar-hub');
        },
      ),
      _DrawerItemData(
        title: 'السبحة الإلكترونية الذكية 📿',
        subtitle: 'عداد التسبيح الذكي مع الاهتزاز وحفظ الأوراد',
        semanticLabel: 'السبحة الإلكترونية الذكية',
        icon: Icons.fingerprint_rounded,
        color: const Color(0xFF0D9488),
        categoryKey: 'adhkar',
        keywords: ['سبحة', 'تسبيح', 'استغفار', 'عداد'],
        onTap: () {
          Navigator.pop(context);
          context.push('/tasbih');
        },
      ),
      _DrawerItemData(
        title: 'صيدلية الروح والرقية الشرعية 🌿',
        subtitle: 'أدعية الشفاء وسكينة القلب والمأثورات',
        semanticLabel: 'صيدلية الروح والرقية الشرعية',
        icon: Icons.favorite_rounded,
        color: const Color(0xFF16A34A),
        categoryKey: 'adhkar',
        keywords: ['رقية', 'شفاء', 'سكينة', 'علاج', 'أدعية'],
        onTap: () {
          Navigator.pop(context);
          context.push('/spiritual-mood');
        },
      ),
      _DrawerItemData(
        title: 'مواقيت تنبيهات الأذكار ⏰',
        subtitle: 'تحديد أوقات إشعارات أذكار الصباح والمساء والنوم',
        semanticLabel: 'مواقيت تنبيهات الأذكار',
        icon: Icons.alarm_rounded,
        color: const Color(0xFFD97706),
        categoryKey: 'adhkar',
        keywords: ['تنبيه', 'أذكار', 'مواقيت', 'وقت', 'صباح', 'مساء', 'نوم', 'إشعار', 'ساعة'],
        onTap: () {
          Navigator.pop(context);
          context.push('/settings');
        },
      ),

      // ================= 5. قسم المكتبة الإسلامية والقصص والفقه =================
      _DrawerItemData(
        title: 'رياض العلم',
        subtitle: 'المكتبة والأدوات',
        semanticLabel: 'رياض العلم',
        icon: Icons.auto_stories_rounded,
        color: const Color(0xFFB45309),
        categoryKey: 'library',
        keywords: ['مكتبة', 'حديث', 'سنة', 'رياض الصالحين'],
        onTap: () {
          Navigator.pop(context);
          context.go('/library');
        },
      ),
      _DrawerItemData(
        title: 'فقه العبادات والزكاة والمواريث ⚖️',
        subtitle: 'أحكام الفقه الميسر، حاسبة الزكاة وحساب المواريث',
        semanticLabel: 'فقه العبادات والزكاة والمواريث',
        icon: Icons.balance_rounded,
        color: const Color(0xFF0284C7),
        categoryKey: 'library',
        keywords: ['فقه', 'زكاة', 'مواريث', 'ميراث', 'تركات', 'أحكام'],
        onTap: () {
          Navigator.pop(context);
          context.push('/zakat');
        },
      ),
      _DrawerItemData(
        title: 'المصادر والمراجع القرآنية المعتمدة 📚',
        subtitle: 'مصحف القراءات، تفسير وإعراب الدرة، والمختصر الصوتي',
        semanticLabel: 'المصادر والمراجع القرآنية المعتمدة',
        icon: Icons.library_books_rounded,
        color: const Color(0xFFB45309),
        categoryKey: 'library',
        keywords: ['مصادر', 'مراجع', 'كتب', 'دار الصحابة'],
        onTap: () {
          Navigator.pop(context);
          context.push('/approved-sources');
        },
      ),

      // ================= 6. قسم الإعدادات والتواصل والمطور =================
      _DrawerItemData(
        title: 'الإعدادات',
        subtitle: 'تهيئة الخشوع وإعدادات التطبيق، المظهر، وأوقات الأذكار',
        semanticLabel: 'الإعدادات',
        icon: Icons.settings_suggest_rounded,
        color: const Color(0xFFB8893A),
        categoryKey: 'settings',
        keywords: ['إعدادات', 'مظهر', 'ثيم', 'خط', 'تخصيص', 'أذان', 'أذكار', 'تهيئة الخشوع وإعدادات التطبيق'],
        onTap: () {
          Navigator.pop(context);
          context.push('/settings');
        },
      ),
      _DrawerItemData(
        title: 'عن التطبيق',
        subtitle: 'رؤية مشروع صديق المؤمن، الوقفية، ورسالة التطبيق',
        semanticLabel: 'عن التطبيق',
        icon: Icons.info_outline_rounded,
        color: AppColors.primaryGreen,
        categoryKey: 'settings',
        keywords: ['عن التطبيق', 'معلومات', 'إصدار', 'وقف', 'صدقة جارية', 'رؤية', 'رسالة التطبيق'],
        onTap: () {
          Navigator.pop(context);
          showSettingsAboutModal(context);
        },
      ),
      _DrawerItemData(
        title: 'عن المطور',
        subtitle: 'أحمد إبراهيم، كود المشروع المفتوح، ورابط GitHub',
        semanticLabel: 'عن المطور',
        icon: Icons.person_rounded,
        color: const Color(0xFF1B6B4E),
        categoryKey: 'settings',
        keywords: ['عن المطور', 'مطور', 'أحمد إبراهيم', 'github', 'المطور'],
        onTap: () {
          Navigator.pop(context);
          context.push('/about-developer');
        },
      ),
      _DrawerItemData(
        title: 'تواصل مع المطور',
        subtitle: 'إرسال اقتراح، ملاحظة، والتواصل والمقترحات بريدياً',
        semanticLabel: 'تواصل مع المطور',
        icon: Icons.mail_outline_rounded,
        color: const Color(0xFF25739B),
        categoryKey: 'settings',
        keywords: ['تواصل مع المطور', 'تواصل', 'مقترحات', 'دعم', 'مطور', 'رسالة', 'التواصل والمقترحات'],
        onTap: () {
          Navigator.pop(context);
          context.push('/support');
        },
      ),
      _DrawerItemData(
        title: 'برامج المطور على المتجر',
        subtitle: 'تطبيقات وبرمجيات المطور على متجر Google Play',
        semanticLabel: 'برامج المطور على المتجر',
        icon: Icons.shop_two_rounded,
        color: const Color(0xFF0284C7),
        categoryKey: 'settings',
        keywords: ['برامج المطور على المتجر', 'متجر', 'جوجل بلاي', 'تطبيقات', 'store', 'google play', 'مطور'],
        onTap: () async {
          Navigator.pop(context);
          await SupportService.openDeveloperPlayStore(context: context);
        },
      ),
      _DrawerItemData(
        title: 'حساب المطور على الفيس بوك',
        subtitle: 'الصفحة والحساب الرسمي على Facebook للتواصل والمتابعة',
        semanticLabel: 'حساب المطور على الفيس بوك',
        icon: Icons.facebook_rounded,
        color: const Color(0xFF1877F2),
        categoryKey: 'settings',
        keywords: ['حساب المطور على الفيس بوك', 'فيسبوك', 'فيس بوك', 'facebook', 'مطور', 'تواصل'],
        onTap: () async {
          Navigator.pop(context);
          await SupportService.openDeveloperFacebook(context: context);
        },
      ),
      _DrawerItemData(
        title: 'دليل وفهرس شاشات التطبيق الشامل 📑',
        subtitle: 'فهرسة تفصيلية لجميع الـ ٥٨ شاشة وباباً إيمانياً مع البحث',
        semanticLabel: 'دليل وفهرس شاشات التطبيق',
        icon: Icons.grid_view_rounded,
        color: AppColors.accentGold,
        categoryKey: 'settings',
        keywords: ['دليل', 'فهرس', 'شاشات', 'أبواب', 'خريطة'],
        onTap: () {
          Navigator.pop(context);
          context.push('/app-screen-directory');
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: SettingsService.instance,
      builder: (context, _) {
        final s = SettingsService.instance;
        final allItems = _buildAllItems(context);

        // Filter by search query or category
        final normQuery = ArabicNormalizer.normalize(_searchQuery, loose: true);
        final filteredItems = allItems.where((item) {
          // Category filter
          if (_selectedCategory != 'all' && item.categoryKey != _selectedCategory) {
            return false;
          }
          // Search query filter
          if (normQuery.isEmpty) return true;

          final normTitle = ArabicNormalizer.normalize(item.title, loose: true);
          final normSubtitle = ArabicNormalizer.normalize(item.subtitle, loose: true);
          final normKeywords = item.keywords.map((k) => ArabicNormalizer.normalize(k, loose: true)).join(' ');

          return normTitle.contains(normQuery) ||
              normSubtitle.contains(normQuery) ||
              normKeywords.contains(normQuery);
        }).toList();

        return Semantics(
          label: 'open navigation menu',
          container: true,
          child: Drawer(
            child: Directionality(
              textDirection: s.textDirection,
              child: Material(
                color: theme.colorScheme.surface,
                child: SafeArea(
                  bottom: true,
                  top: false,
                  child: Column(
                    children: [
                      // 1. Serene Header with Tribute Banner
                      Semantics(
                        label: 'open navigation menu header',
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(18, 44, 18, 14),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isDark
                                  ? [AppColors.emerald900, AppColors.night900]
                                  : [AppColors.emerald700, AppColors.emerald900],
                              begin: Alignment.topRight,
                              end: Alignment.bottomLeft,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppColors.accentGold.withValues(alpha: 0.18),
                                      border: Border.all(color: AppColors.accentGold, width: 2),
                                    ),
                                    child: const Icon(
                                      Icons.mosque_rounded,
                                      color: AppColors.accentGold,
                                      size: 26,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          context.tr('app_name'),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 22,
                                            fontWeight: FontWeight.w900,
                                            fontFamily: 'Amiri',
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          context.tr('app_subtitle'),
                                          style: const TextStyle(
                                            color: AppColors.softGold,
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              // Memorial Tribute Banner
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppColors.accentGold.withValues(alpha: 0.35)),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.volunteer_activism_rounded, color: AppColors.accentGold, size: 15),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'الدعاء للمرحوم مؤمن إبراهيم رحمه الله — صدقة جارية',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // 2. Live Navigation Filter & Search Bar
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (val) {
                            setState(() {
                              _searchQuery = val;
                            });
                          },
                          decoration: InputDecoration(
                            hintText: 'ابحث عن أي قسم أو خدمة في التطبيق...',
                            hintStyle: const TextStyle(fontSize: 12),
                            prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primaryGreen, size: 20),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {
                                        _searchQuery = '';
                                      });
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade100,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),

                      // 3. Horizontal Category Filter Chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        child: Row(
                          children: [
                            _buildFilterChip('الكل', 'all'),
                            const SizedBox(width: 6),
                            _buildFilterChip('📖 القرآن', 'quran'),
                            const SizedBox(width: 6),
                            _buildFilterChip('🕌 الصلاة', 'prayer'),
                            const SizedBox(width: 6),
                            _buildFilterChip('🎙️ العلماء', 'scholars'),
                            const SizedBox(width: 6),
                            _buildFilterChip('🤲 الأذكار', 'adhkar'),
                            const SizedBox(width: 6),
                            _buildFilterChip('📚 المكتبة', 'library'),
                            const SizedBox(width: 6),
                            _buildFilterChip('⚙️ الإعدادات والمطور', 'settings'),
                          ],
                        ),
                      ),
                      const Divider(height: 12),

                      // 4. Navigation Items List
                      Expanded(
                        child: filteredItems.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24.0),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.search_off_rounded, size: 40, color: Colors.grey),
                                      const SizedBox(height: 10),
                                      const Text(
                                        'لم نعثر على قسم مطابق لكلمات البحث',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      const SizedBox(height: 6),
                                      TextButton.icon(
                                        icon: const Icon(Icons.grid_view_rounded, size: 16),
                                        label: const Text('فتح الدليل الشامل (٥٨ شاشة)'),
                                        onPressed: () {
                                          Navigator.pop(context);
                                          context.push('/app-screen-directory');
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.builder(
                                physics: const BouncingScrollPhysics(),
                                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
                                itemCount: filteredItems.length,
                                itemBuilder: (context, index) {
                                  final item = filteredItems[index];
                                  return _buildDrawerTile(
                                    context: context,
                                    icon: item.icon,
                                    title: item.title,
                                    subtitle: item.subtitle,
                                    semanticLabel: item.semanticLabel,
                                    color: item.color,
                                    onTap: item.onTap,
                                  );
                                },
                              ),
                      ),

                      // 5. Clean Footer
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Flexible(
                              child: Text(
                                'إصدار رسمي v1.3.0',
                                style: TextStyle(color: Colors.grey, fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.favorite, color: AppColors.accentGold, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  'لوجه الله تعالى',
                                  style: TextStyle(
                                    color: isDark ? AppColors.accentGold : AppColors.primaryGreen,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(String label, String categoryKey) {
    final isSelected = _selectedCategory == categoryKey;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11.5)),
      selected: isSelected,
      selectedColor: AppColors.primaryGreen,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : null,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      visualDensity: VisualDensity.compact,
      onSelected: (selected) {
        setState(() {
          _selectedCategory = categoryKey;
        });
      },
    );
  }

  Widget _buildDrawerTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required String semanticLabel,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Semantics(
      label: semanticLabel,
      button: true,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: isDark
              ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          border: Border.all(
            color: color.withValues(alpha: 0.2),
            width: 1.2,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: ListTile(
            dense: false,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withValues(alpha: 0.35)),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            title: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}
