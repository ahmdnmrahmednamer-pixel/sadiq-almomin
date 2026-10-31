import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/widgets/app_navigation_drawer.dart';
import '../../core/services/prayer_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/portal_category_card.dart';

/// بوابة «محراب الصلاة والقبلة» (PrayerScreen)
/// مقسمة إلى ٦ محاور رئيسية واضحة ومستقلة:
/// 1. مواقيت الصلاة والأذان
/// 2. بوصلة القبلة
/// 3. منبه الفجر وقيام الليل
/// 4. متابعة وسجل الصلوات
/// 5. السنن الرواتب
/// 6. التقويم الهجري والمناسبات
class PrayerScreen extends StatelessWidget {
  final int initialTabIndex;

  const PrayerScreen({super.key, this.initialTabIndex = 0});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: Listenable.merge([
        PrayerService.instance,
        SettingsService.instance,
      ]),
      builder: (context, _) {
        final s = SettingsService.instance;
        final prayerData = PrayerService.instance.currentData;

        return Directionality(
          textDirection: s.textDirection,
          child: Scaffold(
            drawer: const AppNavigationDrawer(),
            appBar: AppBar(
              title: const Text('محراب الصلاة والقبلة'),
              leading: Builder(
                builder: (ctx) => Semantics(
                  label: 'open navigation menu',
                  button: true,
                  hint: 'افتح قائمة التنقل',
                  child: IconButton(
                    icon: const Icon(Icons.menu_rounded),
                    tooltip: 'open navigation menu',
                    onPressed: () => Scaffold.of(ctx).openDrawer(),
                  ),
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.explore_rounded),
                  tooltip: 'بوصلة القبلة',
                  onPressed: () => context.push('/qibla'),
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              children: [
                // 1. Serene Prayer Banner
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isDark
                          ? [const Color(0xFF0F3628), const Color(0xFF071E16)]
                          : [const Color(0xFF0F5B45), const Color(0xFF1B6B4E)],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.accentGold.withOpacity(0.4),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.35 : 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.mosque_rounded, color: AppColors.accentGold, size: 36),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'إِنَّ الصَّلَاةَ كَانَتْ عَلَى الْمُؤْمِنِينَ كِتَاباً مَوْقُوتاً',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                fontFamily: 'Amiri',
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              prayerData?.nextPrayer != null
                                  ? 'الصلاة القادمة: ${prayerData!.nextPrayer!.name} (${prayerData.nextPrayer!.formattedTime})'
                                  : 'مواقيت منضبطة، أذان الحرمين، واتجاه القبلة',
                              style: const TextStyle(
                                color: Color(0xFFFFEFA6),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // 1. مواقيت الصلاة والأذان
                PortalCategoryCard(
                  numberText: '١',
                  title: 'مواقيت الصلاة واستوديو الأذان',
                  subtitle: 'حساب فلكي دقيق لمواقيت الصلوات الخمس مع نداء الأذان والإقامة بأصوات مؤذني الحرمين',
                  icon: Icons.access_time_filled_rounded,
                  color: AppColors.primaryGreen,
                  badgeText: prayerData?.nextPrayer?.formattedTime,
                  onTap: () => context.push('/prayer-times-detail'),
                ),

                // 2. بوصلة القبلة
                PortalCategoryCard(
                  numberText: '٢',
                  title: 'بوصلة القبلة المشرفة',
                  subtitle: 'تحديد دقيق لاتجاه الكعبة المشرفة في مكة المكرمة عبر الحساسات والمستشعرات والمغناطيسية',
                  icon: Icons.explore_rounded,
                  color: const Color(0xFFB8893A),
                  onTap: () => context.push('/qibla'),
                ),

                // 3. منبه الفجر وقيام الليل
                PortalCategoryCard(
                  numberText: '٣',
                  title: 'منبه الفجر وقيام الليل',
                  subtitle: 'إيقاظ ذكي لصلاة الفجر مع تنبيهات قيام الليل والسحر وركعتي الفجر',
                  icon: Icons.alarm_on_rounded,
                  color: const Color(0xFF1E8260),
                  onTap: () => context.push('/fajr-qiyam-alarm'),
                ),

                // 4. متابعة وسجل الصلوات
                PortalCategoryCard(
                  numberText: '٤',
                  title: 'متابعة وسجل الصلوات',
                  subtitle: 'سجل يومي وأسبوعي وشهري لإحصاء الصلوات المؤداة في وقتها وتدارك ما فات',
                  icon: Icons.fact_check_rounded,
                  color: const Color(0xFF2E7D32),
                  onTap: () => context.push('/prayer-tracker'),
                ),

                // 5. السنن الرواتب
                PortalCategoryCard(
                  numberText: '٥',
                  title: 'السنن الرواتب',
                  subtitle: 'ثنتا عشرة ركعة في اليوم والليلة، فضلها ومواقيتها، ليبني الله لك بها بيتاً في الجنة',
                  icon: Icons.stars_rounded,
                  color: const Color(0xFF0F5B45),
                  onTap: () => context.push('/sunan-rawatib'),
                ),

                // 6. التقويم الهجري والمناسبات
                PortalCategoryCard(
                  numberText: '٦',
                  title: 'التقويم الهجري والمناسبات',
                  subtitle: 'عرض الشهر الهجري والميلادي ومواقيت المناسبات الإسلامية (رمضان، الأعياد، يوم عرفة)',
                  icon: Icons.calendar_month_rounded,
                  color: const Color(0xFF25739B),
                  onTap: () => context.push('/calendar'),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}
