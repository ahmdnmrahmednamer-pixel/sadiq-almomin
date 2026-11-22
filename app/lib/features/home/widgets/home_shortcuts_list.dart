import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/services/prayer_service.dart';
import '../../../core/services/stories_service.dart';
import '../../../core/theme/app_theme.dart';

/// شبكة «مسارات القرب ورياض المعرفة» المنظمة والهادئة في الصفحة الرئيسية (بجميع اللغات الـ ٦)
class HomeShortcutsList extends StatelessWidget {
  final PrayerData? prayerData;

  const HomeShortcutsList({
    super.key,
    required this.prayerData,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Egyptian heritage recordings and knowledge
        _buildEgyptianHeritageBanner(context, isDark),
        const SizedBox(height: 12),

        // 2. Harmonious 9-Door Spiritual Pathways Grid
        LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth > 350 ? 3 : 2;
            return GridView.count(
              crossAxisCount: crossAxisCount,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.96,
              children: [
                _buildSpiritualDoorTile(
                  context,
                  title: context.tr('spiritual_mood_remedy'),
                  icon: Icons.favorite_rounded,
                  color: const Color(0xFF1E8260),
                  onTap: () => context.push('/spiritual-mood'),
                ),
                _buildSpiritualDoorTile(
                  context,
                  title: context.tr('sunan_rawatib'),
                  icon: Icons.mosque_rounded,
                  color: AppColors.emerald900,
                  onTap: () => context.push('/sunan-rawatib'),
                ),
                _buildSpiritualDoorTile(
                  context,
                  title: context.tr('comparative_tafsir'),
                  icon: Icons.auto_stories_rounded,
                  color: const Color(0xFF8E6C18),
                  onTap: () => context.push('/comparative-tafsir'),
                ),
                _buildSpiritualDoorTile(
                  context,
                  title: context.tr('tadabbur_journal'),
                  icon: Icons.psychology_alt_rounded,
                  color: const Color(0xFF1565C0),
                  onTap: () => context.push('/tadabbur-journal'),
                ),
                _buildSpiritualDoorTile(
                  context,
                  title: context.tr('voluntary_fasting'),
                  icon: Icons.wb_twilight_rounded,
                  color: AppColors.gold500,
                  onTap: () => context.push('/voluntary-fasting'),
                ),
                _buildSpiritualDoorTile(
                  context,
                  title: context.tr('hajj_umrah_companion'),
                  icon: Icons.explore_rounded,
                  color: const Color(0xFF2E5A44),
                  onTap: () => context.push('/hajj-umrah'),
                ),
                _buildSpiritualDoorTile(
                  context,
                  title: context.tr('daily_wird'),
                  icon: Icons.task_alt_rounded,
                  color: const Color(0xFF27AE60),
                  onTap: () => context.push('/daily-wird'),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 14),

        // 3. Daily Prophetic Story Reflection
        _buildDailyStorySpotlight(context, isDark),
      ],
    );
  }

  Widget _buildSpiritualDoorTile(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      elevation: 1.2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? Colors.white10 : color.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, color.withValues(alpha: 0.82)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5,
                  height: 1.25,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEgyptianHeritageBanner(BuildContext context, bool isDark) {
    return Semantics(
      button: true,
      label:
          '${context.tr('egypt_heritage')}، ابتهالات النقشبندي وطوبار، خواطر الشعراوي',
      child: InkWell(
        onTap: () => context.push('/egypt-heritage'),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [AppColors.emerald900, AppColors.night900]
                  : [AppColors.emerald700, AppColors.emerald900],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppColors.accentGold.withValues(alpha: 0.45),
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppColors.accentGold.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: Text('🇪🇬', style: TextStyle(fontSize: 23)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('egypt_heritage'),
                      style: const TextStyle(
                        fontFamily: 'Amiri',
                        fontSize: 16.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'ابتهالات النقشبندي وطوبار • خواطر الشعراوي',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.white70,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const ExcludeSemantics(
                child: Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 15,
                  color: AppColors.accentGold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDailyStorySpotlight(BuildContext context, bool isDark) {
    final storyToday = StoriesService.instance.getStoryOfTheDay();

    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.accentGold.withValues(alpha: 0.35)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/stories'),
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F4E37), Color(0xFF1B5E20)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.auto_stories_rounded,
                    color: AppColors.brightGold, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('home_story_of_day'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '«${storyToday.title}»',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 12.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded,
                  size: 13, color: AppColors.primaryGreen),
            ],
          ),
        ),
      ),
    );
  }
}
