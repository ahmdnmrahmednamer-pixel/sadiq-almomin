import 'package:flutter/material.dart';
import '../../core/services/prayer_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/app_theme.dart';
import 'widgets/prayer_audio_quick_card.dart';
import 'widgets/prayer_date_card.dart';
import 'widgets/prayer_location_banner.dart';
import 'widgets/prayer_muezzin_selector_card.dart';
import 'widgets/prayer_times_card.dart';

/// شاشة تفاصيل مواقيت الصلاة والأذان — تعتمد كلياً على التحديد التلقائي للموقع الفعلي
class PrayerTimesDetailScreen extends StatefulWidget {
  const PrayerTimesDetailScreen({super.key});

  @override
  State<PrayerTimesDetailScreen> createState() => _PrayerTimesDetailScreenState();
}

class _PrayerTimesDetailScreenState extends State<PrayerTimesDetailScreen> {
  @override
  void initState() {
    super.initState();
    PrayerService.instance.init();
  }

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
            appBar: AppBar(
              title: const Text('مواقيت الصلاة والأذان'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.my_location_rounded),
                  tooltip: 'تحديث الموقع الفعلي عبر GPS',
                  onPressed: () async {
                    final ok = await PrayerService.instance.requestGpsLocation();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok
                                ? 'تم تحديث الموقع ومواقيت الصلاة بنجاح عبر GPS'
                                : (PrayerService.instance.errorMessage ?? 'تعذر تحديث الموقع'),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          backgroundColor: ok ? AppColors.primaryGreen : Colors.redAccent,
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                // 1. Date Card
                const PrayerDateCard(),
                const SizedBox(height: 12),

                // 2. Location Banner (Automatic Physical Location)
                PrayerLocationBanner(data: prayerData),
                const SizedBox(height: 12),

                // 3. Audio Quick Action Card (Adhan Test)
                PrayerAudioQuickCard(isDark: isDark),
                const SizedBox(height: 14),

                // 4. Prayer Times Cards
                PrayerTimesCard(
                  data: prayerData,
                  isDark: isDark,
                ),
                const SizedBox(height: 14),

                // 5. Muezzin Selector Card
                PrayerMuezzinSelectorCard(isDark: isDark),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }
}
