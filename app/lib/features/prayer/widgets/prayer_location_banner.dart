import 'package:flutter/material.dart';
import '../../../core/services/prayer_service.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/theme/app_theme.dart';

/// Location, calculation method, GPS refresher, and next prayer countdown banner.
/// Fully automated physical GPS location detection with no manual city pickers.
class PrayerLocationBanner extends StatelessWidget {
  final PrayerData? data;

  const PrayerLocationBanner({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.primaryGreen,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.my_location_rounded, color: AppColors.softGold, size: 18),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              data?.locationName ?? 'جاري تحديد موقعك الفعلي عبر GPS...',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14.5),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'طريقة الحساب: ${SettingsService.calculationMethods.firstWhere((m) => m['id'] == SettingsService.instance.calculationMethod, orElse: () => SettingsService.calculationMethods.first)['name']} (تلقائي)',
                        style: const TextStyle(color: AppColors.softGold, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4ADE80).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF4ADE80), width: 1),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.gps_fixed_rounded, size: 12, color: Color(0xFF4ADE80)),
                          SizedBox(width: 4),
                          Text(
                            'تلقائي عبر GPS',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFD4AF37), Color(0xFFB89628)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: PrayerService.instance.isLoading
                              ? null
                              : () async {
                                  final ok = await PrayerService.instance.requestGpsLocation();
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          ok ? 'تم تحديث الموقع الفعلي عبر GPS بنجاح' : (PrayerService.instance.errorMessage ?? 'فشل التحديث'),
                                          style: const TextStyle(fontWeight: FontWeight.w800),
                                        ),
                                        backgroundColor: ok ? AppColors.secondaryGreen : Colors.redAccent,
                                      ),
                                    );
                                  }
                                },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (PrayerService.instance.isLoading)
                                  const SizedBox(
                                    width: 13,
                                    height: 13,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryGreen),
                                  )
                                else
                                  const Icon(Icons.refresh_rounded, size: 14, color: AppColors.primaryGreen),
                                const SizedBox(width: 5),
                                const Text(
                                  'تحديث الموقع',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.primaryGreen,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (data?.nextPrayer != null) ...[
              const Divider(color: Colors.white24, height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text('الصلاة القادمة', style: TextStyle(color: AppColors.softGold, fontSize: 12.5, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(
                        data!.nextPrayer!.name,
                        style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            margin: const EdgeInsets.only(left: 5),
                            decoration: const BoxDecoration(
                              color: Color(0xFF4ADE80),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const Text('الوقت المتبقي (محدّث لحظياً)', style: TextStyle(color: AppColors.softGold, fontSize: 12, fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        PrayerService.instance.formatCountdown(data!.timeToNextPrayer),
                        style: const TextStyle(color: AppColors.accentGold, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
