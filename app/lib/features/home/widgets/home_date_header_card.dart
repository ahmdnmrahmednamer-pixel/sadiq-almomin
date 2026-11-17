import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router.dart';
import '../../../core/theme/app_theme.dart';
import '../../prayer/hijri_calendar_screen.dart';

class HomeDateHeaderCard extends StatelessWidget {
  final String dayName;
  final String hijriStr;
  final String gregStr;

  const HomeDateHeaderCard({
    super.key,
    required this.dayName,
    required this.hijriStr,
    required this.gregStr,
  });

  void _openCalendar(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.push('/calendar');
    } else {
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => const IsolatedFeatureRouteHost(
            child: HijriCalendarScreen(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    void handleTap() => _openCalendar(context);

    return Semantics(
      button: true,
      excludeSemantics: true,
      label: '$dayName، $hijriStr، $gregStr، فتح التقويم الهجري',
      onTap: handleTap,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: handleTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primaryGreen, AppColors.secondaryGreen],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryGreen.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_today, color: AppColors.softGold, size: 18),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            dayName,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            gregStr,
                            style: const TextStyle(color: AppColors.softGold, fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_forward_ios, color: AppColors.softGold, size: 12),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                hijriStr,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.softGold, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
