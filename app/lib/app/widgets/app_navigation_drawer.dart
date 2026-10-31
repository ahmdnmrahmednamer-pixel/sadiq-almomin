import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/app_theme.dart';
import '../../features/settings/widgets/settings_adhan_voice_modal.dart';

/// القائمة الجانبية الإيمانية الشاملة (Navigation Menu)
/// تضم كافة أقسام التطبيق التي طلبها المستخدم مع تنظيم احترافي وأيقونات واضحة
class AppNavigationDrawer extends StatelessWidget {
  const AppNavigationDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: SettingsService.instance,
      builder: (context, _) {
        final s = SettingsService.instance;

        return Semantics(
          label: 'open navigation menu',
          container: true,
          child: Drawer(
            child: Directionality(
              textDirection: s.textDirection,
              child: Material(
                color: isDark ? const Color(0xFF0F1A15) : Colors.white,
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
                          padding: const EdgeInsets.fromLTRB(18, 44, 18, 16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isDark
                                  ? [
                                      const Color(0xFF0B2B20),
                                      const Color(0xFF071C15),
                                    ]
                                  : [
                                      const Color(0xFF0F5B45),
                                      const Color(0xFF093E2F),
                                    ],
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
                                      color: AppColors.accentGold.withOpacity(0.18),
                                      border: Border.all(
                                          color: AppColors.accentGold, width: 2),
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
                              const SizedBox(height: 12),
                              // Memorial Tribute Banner
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppColors.accentGold.withOpacity(0.35)),
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

                      // 2. Comprehensive Navigation Items
                      Expanded(
                        child: ListView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 10),
                          children: [
                            // ================= 1. قسم القرآن الكريم وقراء التلاوة =================
                            _buildSectionHeader('📖 القرآن الكريم وقراء التلاوة'),

                            _buildDrawerTile(
                              context: context,
                              icon: Icons.menu_book_rounded,
                              title: 'المصحف الشريف وتلاوة الآيات',
                              subtitle: 'قراءة السور بالرسم العثماني والآية متبوعة برقمها',
                              semanticLabel: 'المصحف الشريف وتلاوة الآيات',
                              color: AppColors.primaryGreen,
                              onTap: () {
                                Navigator.pop(context);
                                context.go('/mushaf');
                              },
                            ),

                            _buildDrawerTile(
                              context: context,
                              icon: Icons.record_voice_over_rounded,
                              title: 'قراء القرآن الكريم والاستماع (61 قارئاً) 🎧',
                              subtitle: 'اختيار القارئ من القائمة المنسدلة والاستماع لعينات التلاوة',
                              semanticLabel: 'قراء القرآن الكريم والاستماع',
                              color: AppColors.accentGold,
                              onTap: () {
                                Navigator.pop(context);
                                context.push('/audio');
                              },
                            ),

                            _buildDrawerTile(
                              context: context,
                              icon: Icons.bookmark_added_rounded,
                              title: 'ختمة القرآن الكريم والورد اليومي',
                              subtitle: 'متابعة الختمة وحفظ التقدم وتدبر الآيات',
                              semanticLabel: 'ختمة القرآن الكريم والورد اليومي',
                              color: const Color(0xFF1E8260),
                              onTap: () {
                                Navigator.pop(context);
                                context.push('/khatma');
                              },
                            ),

                            const Divider(height: 18),

                            // ================= 2. قسم الصلاة والأذان والمؤذنون =================
                            _buildSectionHeader('🕌 الصلاة وأصوات الأذان والمؤذنون الـ 7'),

                            _buildDrawerTile(
                              context: context,
                              icon: Icons.mosque_rounded,
                              title: 'أصوات الأذان والمؤذنون الـ 7 🕌',
                              subtitle: 'استماع وتخصيص أذان القطامي، المنشاوي، النقشبندي، عبد الباسط، الحصري، عباد، الدوسري',
                              semanticLabel: 'أصوات الأذان وتخصيص المؤذنين',
                              color: const Color(0xFFD97706),
                              onTap: () {
                                Navigator.pop(context);
                                showSettingsAdhanVoiceModal(context);
                              },
                            ),

                            _buildDrawerTile(
                              context: context,
                              icon: Icons.volume_up_rounded,
                              title: 'دعاء الشيخ الشعراوي بعد الأذان 🎧',
                              subtitle: 'استماع فوري وتفعيل التشغيل التلقائي عقب كل أذان',
                              semanticLabel: 'دعاء الشيخ الشعراوي بعد الأذان',
                              color: AppColors.accentGold,
                              onTap: () {
                                Navigator.pop(context);
                                context.push('/adhan-control');
                              },
                            ),

                            _buildDrawerTile(
                              context: context,
                              icon: Icons.access_time_filled_rounded,
                              title: 'مواقيت الصلاة وبوصلة القبلة 🧭',
                              subtitle: 'المواقيت الدقيقة للصلوات الخمس واتجاه الكعبة',
                              semanticLabel: 'مواقيت الصلاة وبوصلة القبلة',
                              color: const Color(0xFF25739B),
                              onTap: () {
                                Navigator.pop(context);
                                context.go('/prayer');
                              },
                            ),

                            const Divider(height: 18),

                            // ================= 3. قسم مكتبة العلماء والدروس =================
                            _buildSectionHeader('🎙️ مكتبة كبار العلماء والدروس'),

                            _buildDrawerTile(
                              context: context,
                              icon: Icons.mic_external_on_rounded,
                              title: 'مكتبة كبار العلماء والدروس الإسلامية 🎙️',
                              subtitle: 'دروس ومقاطع الشيخ الشعراوي، ابن عثيمين، كشك، حسان، ومصطفى محمود',
                              semanticLabel: 'مكتبة كبار العلماء والدروس الإسلامية',
                              color: const Color(0xFF7C3AED),
                              onTap: () {
                                Navigator.pop(context);
                                context.push('/scholars-audio');
                              },
                            ),

                            const Divider(height: 18),

                            // ================= 4. قسم الأذكار وحصن المسلم والسبحة =================
                            _buildSectionHeader('🤲 الأذكار وحصن المسلم والسبحة'),

                            _buildDrawerTile(
                              context: context,
                              icon: Icons.volunteer_activism_rounded,
                              title: 'أذكار المسلم وحصن المسلم 🤲',
                              subtitle: 'أذكار الصباح والمساء والصلوات وحفظ النفس',
                              semanticLabel: 'أذكار المسلم وحصن المسلم',
                              color: const Color(0xFF059669),
                              onTap: () {
                                Navigator.pop(context);
                                context.go('/adhkar-hub');
                              },
                            ),

                            _buildDrawerTile(
                              context: context,
                              icon: Icons.fingerprint_rounded,
                              title: 'السبحة الإلكترونية الذكية 📿',
                              subtitle: 'عداد التسبيح الذكي مع الاهتزاز وحفظ الأوراد',
                              semanticLabel: 'السبحة الإلكترونية الذكية',
                              color: const Color(0xFF0D9488),
                              onTap: () {
                                Navigator.pop(context);
                                context.push('/tasbih');
                              },
                            ),

                            _buildDrawerTile(
                              context: context,
                              icon: Icons.favorite_rounded,
                              title: 'صيدلية الروح والرقية الشرعية 🌿',
                              subtitle: 'أدعية الشفاء وسكينة القلب والمأثورات',
                              semanticLabel: 'صيدلية الروح والرقية الشرعية',
                              color: const Color(0xFF16A34A),
                              onTap: () {
                                Navigator.pop(context);
                                context.push('/spiritual-mood');
                              },
                            ),

                            const Divider(height: 18),

                            // ================= 5. قسم المكتبة الإسلامية والقصص =================
                            _buildSectionHeader('📚 المكتبة الإسلامية والقصص والفقه'),

                            _buildDrawerTile(
                              context: context,
                              icon: Icons.auto_stories_rounded,
                              title: 'المكتبة الإسلامية والحديث النبوي 📚',
                              subtitle: 'رياض الصالحين، صحيح الحديث، وقصص الأنبياء',
                              semanticLabel: 'المكتبة الإسلامية والحديث النبوي',
                              color: const Color(0xFFB45309),
                              onTap: () {
                                Navigator.pop(context);
                                context.go('/library');
                              },
                            ),

                            _buildDrawerTile(
                              context: context,
                              icon: Icons.balance_rounded,
                              title: 'فقه العبادات والزكاة والمواريث ⚖️',
                              subtitle: 'أحكام الفقه الميسر، حاسبة الزكاة وحساب المواريث',
                              semanticLabel: 'فقه العبادات والزكاة والمواريث',
                              color: const Color(0xFF0284C7),
                              onTap: () {
                                Navigator.pop(context);
                                context.push('/zakat');
                              },
                            ),

                            const Divider(height: 18),

                            // ================= 6. قسم الإعدادات والتواصل والرسالة =================
                            _buildSectionHeader('⚙️ الإعدادات والتواصل والرسالة'),

                            _buildDrawerTile(
                              context: context,
                              icon: Icons.settings_suggest_rounded,
                              title: 'تهيئة الخشوع وإعدادات التطبيق',
                              subtitle: 'تخصيص المظهر، صوت الأذان، دعاء الشعراوي، والخط',
                              semanticLabel: 'تهيئة الخشوع وإعدادات التطبيق',
                              color: const Color(0xFFB8893A),
                              onTap: () {
                                Navigator.pop(context);
                                context.push('/settings');
                              },
                            ),

                            _buildDrawerTile(
                              context: context,
                              icon: Icons.mail_outline_rounded,
                              title: 'التواصل والمقترحات',
                              subtitle: 'إرسال اقتراح، ملاحظة، أو رسالة مباشرة للمطور',
                              semanticLabel: 'التواصل والمقترحات',
                              color: const Color(0xFF25739B),
                              onTap: () {
                                Navigator.pop(context);
                                context.push('/support');
                              },
                            ),

                            _buildDrawerTile(
                              context: context,
                              icon: Icons.info_outline_rounded,
                              title: 'رسالة التطبيق',
                              subtitle: 'عن المطور، رابط GitHub، ورؤية المشروع الإيماني',
                              semanticLabel: 'رسالة التطبيق وعن المطور',
                              color: AppColors.primaryGreen,
                              onTap: () {
                                Navigator.pop(context);
                                context.push('/about-developer');
                              },
                            ),
                          ],
                        ),
                      ),

                      // 3. Clean Footer without overflow
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: isDark
                                  ? const Color(0xFF1A2A22)
                                  : const Color(0xFFE5EDE8),
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Flexible(
                              child: Text(
                                'إصدار رسمي v1.2.2',
                                style: TextStyle(
                                    color: Colors.grey, fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.favorite,
                                    color: AppColors.accentGold, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  'لوجه الله تعالى',
                                  style: TextStyle(
                                    color: isDark
                                        ? AppColors.accentGold
                                        : AppColors.primaryGreen,
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

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: AppColors.primaryGreen,
          letterSpacing: 0.2,
        ),
      ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Semantics(
      label: semanticLabel,
      button: true,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: isDark
              ? const Color(0xFF15221B)
              : const Color(0xFFF7FBF8),
          border: Border.all(
            color: color.withOpacity(0.2),
            width: 1.2,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: ListTile(
            dense: false,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.14),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withOpacity(0.35)),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            title: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle,
                style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            trailing: const Icon(Icons.arrow_forward_ios_rounded,
                size: 14, color: Colors.grey),
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}
