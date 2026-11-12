import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/prayer_service.dart';
import '../../prayer/prayer_screen.dart';

class HomeNextPrayerCard extends StatelessWidget {
  final PrayerData? prayerData;

  const HomeNextPrayerCard({
    super.key,
    required this.prayerData,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lat = prayerData?.latitude;
    final lng = prayerData?.longitude;
    final coordsFormatted = (lat != null && lng != null)
        ? '${lat.toStringAsFixed(3)}°, ${lng.toStringAsFixed(3)}°'
        : null;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const PrayerScreen()),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Precise Location & GPS Status Badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.location_on_rounded, size: 16, color: AppColors.accentGold),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                prayerData?.locationName ?? 'جاري تحديد موقعك الفعلي عبر GPS...',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primaryGreen,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (coordsFormatted != null)
                                Text(
                                  'إحداثيات دقيقة: $coordsFormatted',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isDark ? Colors.white60 : AppColors.mutedText,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // GPS Status & Quick Refresh Pill
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () async {
                      final ok = await PrayerService.instance.requestGpsLocation();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              ok
                                  ? 'تم تحديث موقعك الفعلي بنجاح وبأعلى دقة 📍'
                                  : 'تعذر تحديد الموقع، يرجى تفعيل الـ GPS والتأكد من الصلاحيات',
                            ),
                            duration: const Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4ADE80).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF22C55E), width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            PrayerService.instance.isLoading
                                ? Icons.sync_rounded
                                : Icons.gps_fixed_rounded,
                            size: 13,
                            color: const Color(0xFF16A34A),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            PrayerService.instance.isLoading ? 'جاري التحديد...' : 'GPS فائق الدقة',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF16A34A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10.0),
                child: Divider(height: 1, thickness: 0.8),
              ),

              // 2. Next Prayer and Countdown
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        prayerData?.nextPrayer != null
                            ? 'الصلاة القادمة: ${prayerData!.nextPrayer!.name}'
                            : 'الصلاة القادمة: الظهر',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryGreen,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.timer_outlined, size: 16, color: AppColors.secondaryGreen),
                          const SizedBox(width: 4),
                          ValueListenableBuilder<Duration>(
                            valueListenable: PrayerService.instance.countdownNotifier,
                            builder: (context, duration, _) {
                              final effectiveDuration = duration == Duration.zero && prayerData != null
                                  ? prayerData!.timeToNextPrayer
                                  : duration;
                              return Text(
                                prayerData != null
                                    ? 'متبقي ${PrayerService.instance.formatCountdown(effectiveDuration)}'
                                    : 'جاري الحساب...',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: AppColors.secondaryGreen,
                                  fontWeight: FontWeight.w600,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.accentGold.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.access_time_filled, color: AppColors.primaryGreen, size: 28),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
