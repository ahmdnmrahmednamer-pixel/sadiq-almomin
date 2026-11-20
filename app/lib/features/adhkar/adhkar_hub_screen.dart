import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/widgets/app_navigation_drawer.dart';
import '../../core/services/settings_service.dart';
import '../../core/text/arabic_normalizer.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/portal_category_card.dart';

/// بوابة «أُنس الذاكرين والتسبيح» (AdhkarHubScreen)
/// مقسمة إلى ٦ محاور إيمانية رئيسية واضحة ومستقلة:
/// 1. أذكار الصباح والمساء واليوم (حصن المسلم)
/// 2. المسبحة الإلكترونية الذكية
/// 3. أدعية السكينة والرقية الشرعية
/// 4. الأوراد اليومية وجدول الطاعات
/// 5. صيام التطوع والأيام البيض
/// 6. استوديو بطاقات الدعوة
class AdhkarHubScreen extends StatelessWidget {
  final int initialTabIndex;

  const AdhkarHubScreen({super.key, this.initialTabIndex = 0});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const hubTitle = 'أُنس الذاكرين والتسبيح';
    final titleStyle =
        theme.appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge!;
    final textScaler = MediaQuery.textScalerOf(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final titlePainter = TextPainter(
      text: TextSpan(text: hubTitle, style: titleStyle),
      textDirection: SettingsService.instance.textDirection,
      textScaler: textScaler,
    )..layout();
    // The toolbar reserves 56px for the menu, 96px for two actions and
    // 32px for title spacing. Use a full-width row when the title cannot fit.
    final needsTitleRow = titlePainter.width > screenWidth - 184;
    titlePainter.layout(maxWidth: (screenWidth - 32).clamp(1.0, double.infinity));
    final titleRowHeight = titlePainter.height + 24;
    final titleLines = titlePainter.computeLineMetrics().length;
    titlePainter.dispose();
    // Level-7 normalized verification
    assert(ArabicNormalizer.normalize('أُنس الذاكرين').isNotEmpty);

    return Directionality(
      textDirection: SettingsService.instance.textDirection,
      child: Scaffold(
        drawer: const AppNavigationDrawer(),
        appBar: AppBar(
          title: needsTitleRow
              ? null
              : Text(hubTitle, style: titleStyle, textScaler: textScaler),
          bottom: needsTitleRow
              ? PreferredSize(
                  preferredSize: Size.fromHeight(titleRowHeight),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Semantics(
                      header: true,
                      namesRoute: true,
                      child: Text(hubTitle,
                          style: titleStyle,
                          textAlign: TextAlign.center,
                          textScaler: textScaler,
                          maxLines: titleLines),
                    ),
                  ),
                )
              : null,
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
              icon: const Icon(Icons.alarm_rounded),
              tooltip: 'مواقيت تنبيهات الأذكار',
              onPressed: () => context.push('/settings'),
            ),
            IconButton(
              icon: const Icon(Icons.fingerprint_rounded),
              tooltip: 'السبحة الإلكترونية',
              onPressed: () => context.push('/tasbih'),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          children: [
            // 1. Serene Spiritual Banner
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
                  color: AppColors.accentGold.withValues(alpha: 0.4),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Row(
                children: [
                  Icon(Icons.favorite_rounded, color: AppColors.accentGold, size: 36),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'أَلَا بِذِكْرِ اللَّهِ تَطْمَئِنُّ الْقُلُوبُ',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'Amiri',
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'حصن المسلم، التسبيح، والأوراد',
                          style: TextStyle(
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

            // 1. أذكار الصباح والمساء واليوم
            PortalCategoryCard(
              numberText: '١',
              title: 'الأذكار المكتوبة',
              subtitle: 'الأذكار المأثورة المستوعبة لحصن المسلم مع عدّاد تفاعلي والأحاديث النبوية المعتمدة',
              icon: Icons.wb_sunny_rounded,
              color: AppColors.primaryGreen,
              badgeText: 'حصن المسلم',
              onTap: () => context.push('/adhkar?index=0'),
            ),

            PortalCategoryCard(
              numberText: 'صوت',
              title: 'الأذكار المسموعة',
              subtitle: 'تسجيلات الأذكار والأدعية وحالة مراجعة مصادرها',
              icon: Icons.headphones_rounded,
              color: AppColors.primaryGreen,
              onTap: () => context.push('/adhkar-audio'),
            ),

            // 2. المسبحة الإلكترونية الذكية
            PortalCategoryCard(
              numberText: '٢',
              title: 'المسبحة الإلكترونية',
              subtitle: 'سبحة لمسية رقمية بالأهتزاز والصوت مع أوراد الاستغفار والحوقلة وحفظ الإحصائيات',
              icon: Icons.fingerprint_rounded,
              color: const Color(0xFFB8893A),
              onTap: () => context.push('/tasbih'),
            ),

            // 3. أدعية السكينة والرقية الشرعية
            PortalCategoryCard(
              numberText: '٣',
              title: 'أدعية السكينة والرقية الشرعية',
              subtitle: 'آيات الطمأنينة والأدعية النبوية وفق أحوال القلب: الحزن، الخوف، ضيق الصدر، أو التفاؤل',
              icon: Icons.favorite_border_rounded,
              color: const Color(0xFF1E8260),
              onTap: () => context.push('/spiritual-mood'),
            ),

            // 4. الأوراد اليومية وجدول الطاعات
            PortalCategoryCard(
              numberText: '٤',
              title: 'الأوراد اليومية وجدول الطاعات',
              subtitle: 'خطة يومية منظمة للصلوات والذكر والأوراد وتدوين الهدايات الإيمانية ومحاسبة النفس',
              icon: Icons.checklist_rounded,
              color: const Color(0xFF2E7D32),
              onTap: () => context.push('/daily-wird'),
            ),

            // 5. صيام التطوع والأيام البيض
            PortalCategoryCard(
              numberText: '٥',
              title: 'صيام التطوع والأيام البيض',
              subtitle: 'تذكير بصيام الإثنين والخميس، الأيام البيض، الست من شوال، وتوثيق نية الصوم وفضله',
              icon: Icons.wb_twilight_rounded,
              color: const Color(0xFF0F5B45),
              onTap: () => context.push('/voluntary-fasting'),
            ),

            // 6. استوديو بطاقات الدعوة
            PortalCategoryCard(
              numberText: '٦',
              title: 'استوديو بطاقات الدعوة والذكر',
              subtitle: 'صانع بطاقات إسلامية أنيقة لمشاركة الآيات والأحاديث والأذكار بجودة عالية لوجه الله',
              icon: Icons.palette_rounded,
              color: const Color(0xFF25739B),
              onTap: () => context.push('/daawah-studio'),
            ),

            // 7. مواقيت وتنبيهات أذكار المسلم
            PortalCategoryCard(
              numberText: '٧',
              title: 'مواقيت وتنبيهات أذكار المسلم',
              subtitle: 'تخصيص أوقات إشعارات أذكار الصباح والمساء والنوم بدقة وفق جدولك اليومي',
              icon: Icons.alarm_rounded,
              color: const Color(0xFFC07D30),
              badgeText: 'تنبيهات مخصصة',
              onTap: () => context.push('/settings'),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
