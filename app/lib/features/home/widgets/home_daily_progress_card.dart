import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router.dart';
import '../../../core/services/daily_wird_service.dart';
import '../../../core/services/prayer_tracker_service.dart';
import '../../../core/services/sunan_rawatib_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../prayer/prayer_tracker_screen.dart';
import '../../prayer/sunan_rawatib_screen.dart';
import '../../wird/daily_wird_screen.dart';

/// بطاقة ملخص إنجاز اليوم الفعلية (الفرائض، السنن الرواتب، الورد اليومي)
/// تعرض أرقاماً حقيقية متزامنة لحظياً مع الخدمات الفعلية وتدعم التكبير حتى 2.0x دون فيضان
class HomeDailyProgressCard extends StatelessWidget {
  final DateTime Function()? clock;

  const HomeDailyProgressCard({
    super.key,
    this.clock,
  });

  void _openRoute(BuildContext context, String route, Widget fallbackScreen) {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.push(route);
    } else {
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => IsolatedFeatureRouteHost(child: fallbackScreen),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: Listenable.merge([
        PrayerTrackerService.instance,
        SunanRawatibService.instance,
        DailyWirdService.instance,
      ]),
      builder: (context, _) {
        final now = (clock ?? DateTime.now)();
        final obligatoryDone =
            PrayerTrackerService.instance.getRecordForDate(now).completedObligatoryCount;
        final sunanRakahs =
            SunanRawatibService.instance.getCompletedRawatibRakahs(date: now);
        final wirdDone = DailyWirdService.instance.getCompletedToday(now).length;
        final wirdTotal = DailyWirdService.defaultTasks.length;

        final items = [
          _DailyMetricTileData(
            key: const ValueKey('home_metric_obligatory'),
            title: 'الفرائض',
            countText: '$obligatoryDone من 5',
            unitText: 'صلوات',
            progress: (obligatoryDone / 5.0).clamp(0.0, 1.0),
            icon: Icons.fact_check_rounded,
            color: AppColors.primaryGreen,
            onTap: () => _openRoute(
              context,
              '/prayer-tracker',
              const PrayerTrackerScreen(),
            ),
          ),
          _DailyMetricTileData(
            key: const ValueKey('home_metric_sunan'),
            title: 'الرواتب',
            countText: '$sunanRakahs من 12',
            unitText: 'ركعة',
            progress: (sunanRakahs / 12.0).clamp(0.0, 1.0),
            icon: Icons.mosque_rounded,
            color: const Color(0xFFB45309),
            onTap: () => _openRoute(
              context,
              '/sunan-rawatib',
              const SunanRawatibScreen(),
            ),
          ),
          _DailyMetricTileData(
            key: const ValueKey('home_metric_wird'),
            title: 'الورد اليومي',
            countText: '$wirdDone من $wirdTotal',
            unitText: 'مهام',
            progress: wirdTotal == 0 ? 0.0 : (wirdDone / wirdTotal).clamp(0.0, 1.0),
            icon: Icons.task_alt_rounded,
            color: const Color(0xFF0F766E),
            onTap: () => _openRoute(
              context,
              '/daily-wird',
              const DailyWirdScreen(),
            ),
          ),
        ];

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'إنجاز اليوم',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14.0;
                    final useColumnLayout = constraints.maxWidth < 340 || textScale >= 1.4;

                    if (useColumnLayout) {
                      return Column(
                        children: [
                          for (int i = 0; i < items.length; i++) ...[
                            if (i > 0) const SizedBox(height: 8),
                            _buildHorizontalTile(items[i], isDark),
                          ],
                        ],
                      );
                    }

                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (int i = 0; i < items.length; i++) ...[
                            if (i > 0) const SizedBox(width: 8),
                            Expanded(child: _buildCompactTile(items[i], isDark)),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompactTile(_DailyMetricTileData item, bool isDark) {
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: '${item.title}: ${item.countText} ${item.unitText}',
      onTap: item.onTap,
      child: Material(
        key: item.key,
        color: isDark
            ? item.color.withValues(alpha: 0.14)
            : item.color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: item.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: item.color.withValues(alpha: isDark ? 0.35 : 0.2),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(item.icon, color: item.color, size: 20),
                const SizedBox(height: 6),
                Text(
                  item.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.countText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: item.color,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                Text(
                  item.unitText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark ? Colors.white60 : AppColors.mutedText,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: item.progress,
                    backgroundColor: Colors.grey.withValues(alpha: 0.2),
                    valueColor: AlwaysStoppedAnimation<Color>(item.color),
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHorizontalTile(_DailyMetricTileData item, bool isDark) {
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: '${item.title}: ${item.countText} ${item.unitText}',
      onTap: item.onTap,
      child: Material(
        key: item.key,
        color: isDark
            ? item.color.withValues(alpha: 0.14)
            : item.color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: item.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: item.color.withValues(alpha: isDark ? 0.35 : 0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(item.icon, color: item.color, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${item.countText} ${item.unitText}',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          color: item.color,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: item.progress,
                    backgroundColor: Colors.grey.withValues(alpha: 0.2),
                    valueColor: AlwaysStoppedAnimation<Color>(item.color),
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DailyMetricTileData {
  final Key key;
  final String title;
  final String countText;
  final String unitText;
  final double progress;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _DailyMetricTileData({
    required this.key,
    required this.title,
    required this.countText,
    required this.unitText,
    required this.progress,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}
