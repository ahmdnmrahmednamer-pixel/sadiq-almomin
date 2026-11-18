import 'package:flutter/material.dart';
import '../../../core/services/prayer_service.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/theme/app_theme.dart';

/// Context describing why a screen needs GPS so unavailable/permission messages
/// stay relevant to that feature (e.g. compass-only wording on Qibla, never
/// prayer times) without making accuracy promises.
enum GpsPromptContext {
  prayer,
  qibla,
  ramadan,
  general,
}

/// Compact badge visibly distinguishing recent live GPS (< 15m), saved/cached
/// GPS location, and unknown location states without overflowing on narrow/2x viewports.
class GpsFreshnessChip extends StatelessWidget {
  final LocationFreshness freshness;
  final bool onDarkSurface;

  const GpsFreshnessChip({
    super.key,
    required this.freshness,
    this.onDarkSurface = false,
  });

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final String label;
    final Color accent;
    final Color bg;
    final Color textColor;

    switch (freshness) {
      case LocationFreshness.current:
        icon = Icons.gps_fixed_rounded;
        label = 'GPS حديث';
        accent = const Color(0xFF22C55E);
        bg = const Color(0xFF4ADE80).withValues(alpha: onDarkSurface ? 0.18 : 0.15);
        textColor = onDarkSurface ? Colors.white : const Color(0xFF15803D);
        break;
      case LocationFreshness.cachedStale:
        icon = Icons.history_toggle_off_rounded;
        label = 'موقع محفوظ';
        accent = const Color(0xFFF59E0B);
        bg = const Color(0xFFF59E0B).withValues(alpha: onDarkSurface ? 0.24 : 0.16);
        textColor = onDarkSurface ? const Color(0xFFFEF3C7) : const Color(0xFF92400E);
        break;
      case LocationFreshness.unknown:
        icon = Icons.location_off_rounded;
        label = 'الموقع غير محدد';
        accent = onDarkSurface ? AppColors.softGold : const Color(0xFFD97706);
        bg = (onDarkSurface ? Colors.white : const Color(0xFFF59E0B))
            .withValues(alpha: onDarkSurface ? 0.14 : 0.14);
        textColor = onDarkSurface ? Colors.white : const Color(0xFF92400E);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Icon(icon, size: 13, color: accent),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reusable GPS-only action controls offering explicit Enable / Retry /
/// Open Location Settings / Open App Settings affordances based on the live
/// [PrayerService.lastLocationError] state, safe at 360/412 and 2.0x text scale.
class GpsLocationActionControls extends StatelessWidget {
  final bool onDarkSurface;
  final VoidCallback? onLocationUpdated;
  final bool showFeedbackSnackBar;
  final GpsPromptContext promptContext;

  const GpsLocationActionControls({
    super.key,
    this.onDarkSurface = false,
    this.onLocationUpdated,
    this.showFeedbackSnackBar = true,
    this.promptContext = GpsPromptContext.prayer,
  });

  static String describeUnavailableReason(
    PrayerService service, {
    GpsPromptContext promptContext = GpsPromptContext.prayer,
  }) {
    final error = service.lastLocationError;
    if (error == LocationErrorType.permissionDenied) {
      switch (promptContext) {
        case GpsPromptContext.qibla:
          return 'يلزم منح إذن الموقع الجغرافي (GPS) لتحديد اتجاه القبلة عبر البوصلة';
        case GpsPromptContext.ramadan:
          return 'يلزم منح إذن الموقع الجغرافي (GPS) لحساب أوقات الإمساك والإفطار';
        case GpsPromptContext.general:
          return 'يلزم منح إذن الموقع الجغرافي (GPS) لتحديد موقعك';
        case GpsPromptContext.prayer:
          return 'يلزم منح إذن الموقع الجغرافي (GPS) لحساب مواقيت الصلاة';
      }
    }
    if (error == LocationErrorType.none) {
      switch (promptContext) {
        case GpsPromptContext.qibla:
          return 'فعّل تحديد الموقع عبر GPS لحساب اتجاه القبلة على البوصلة';
        case GpsPromptContext.ramadan:
          return 'فعّل تحديد الموقع عبر GPS لحساب أوقات الإمساك والإفطار لموقعك';
        case GpsPromptContext.general:
          return 'فعّل تحديد الموقع عبر GPS لتحديد موقعك الفعلي';
        case GpsPromptContext.prayer:
          return 'فعّل تحديد الموقع عبر GPS لحساب مواقيت الصلاة لموقعك';
      }
    }

    final msg = service.errorMessage;
    if (msg != null && msg.trim().isNotEmpty) {
      return msg;
    }
    switch (error) {
      case LocationErrorType.serviceDisabled:
        return 'خدمات تحديد الموقع (GPS) غير مفعلة على الهاتف';
      case LocationErrorType.permissionDeniedForever:
        return 'تم رفض إذن الموقع بشكل دائم، يرجى تفعيله من إعدادات التطبيق';
      case LocationErrorType.timeout:
        return 'انتهت مهلة تحديد الموقع الجغرافي، يرجى المحاولة مرة أخرى';
      case LocationErrorType.unavailable:
        return 'تعذر تحديد الموقع الجغرافي حالياً، يرجى المحاولة مرة أخرى';
      case LocationErrorType.permissionDenied:
      case LocationErrorType.none:
        return 'فعّل تحديد الموقع عبر GPS لتحديد موقعك';
    }
  }

  Future<void> _handleRequestGps(BuildContext context) async {
    final ok = await PrayerService.instance.requestGpsLocation();
    if (ok) {
      onLocationUpdated?.call();
    }
    if (showFeedbackSnackBar && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'تم تحديث الموقع الفعلي عبر GPS بنجاح'
                : describeUnavailableReason(
                    PrayerService.instance,
                    promptContext: promptContext,
                  ),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          backgroundColor: ok ? AppColors.secondaryGreen : Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = PrayerService.instance;
    final error = service.lastLocationError;
    final isLoading = service.isLoading;

    final primaryBg = onDarkSurface ? AppColors.accentGold : AppColors.primaryGreen;
    final primaryFg = onDarkSurface ? AppColors.primaryGreen : Colors.white;
    final secondaryFg = onDarkSurface ? Colors.white : AppColors.primaryGreen;
    final secondaryBorder = onDarkSurface ? Colors.white54 : AppColors.primaryGreen;

    final String retryLabel = isLoading
        ? 'جاري التحديد...'
        : (error == LocationErrorType.timeout ||
                error == LocationErrorType.unavailable ||
                error == LocationErrorType.serviceDisabled ||
                error == LocationErrorType.permissionDeniedForever
            ? 'إعادة المحاولة'
            : 'تفعيل الموقع (GPS)');

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (error == LocationErrorType.serviceDisabled)
          FilledButton.icon(
            key: const ValueKey('gps_open_location_settings_button'),
            style: FilledButton.styleFrom(
              backgroundColor: primaryBg,
              foregroundColor: primaryFg,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onPressed: isLoading
                ? null
                : () async {
                    await PrayerService.instance.openLocationSettings();
                  },
            icon: const Icon(Icons.settings_outlined, size: 16),
            label: const Text('فتح إعدادات الموقع'),
          ),
        if (error == LocationErrorType.permissionDeniedForever)
          FilledButton.icon(
            key: const ValueKey('gps_open_app_settings_button'),
            style: FilledButton.styleFrom(
              backgroundColor: primaryBg,
              foregroundColor: primaryFg,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onPressed: isLoading
                ? null
                : () async {
                    await PrayerService.instance.openAppSettings();
                  },
            icon: const Icon(Icons.app_settings_alt_rounded, size: 16),
            label: const Text('فتح إعدادات التطبيق'),
          ),
        if (error == LocationErrorType.serviceDisabled ||
            error == LocationErrorType.permissionDeniedForever)
          OutlinedButton.icon(
            key: const ValueKey('gps_retry_button'),
            style: OutlinedButton.styleFrom(
              foregroundColor: secondaryFg,
              side: BorderSide(color: secondaryBorder),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onPressed: isLoading ? null : () => _handleRequestGps(context),
            icon: isLoading
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: secondaryFg,
                    ),
                  )
                : const Icon(Icons.refresh_rounded, size: 16),
            label: Text(retryLabel),
          )
        else
          FilledButton.icon(
            key: const ValueKey('gps_enable_retry_button'),
            style: FilledButton.styleFrom(
              backgroundColor: primaryBg,
              foregroundColor: primaryFg,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onPressed: isLoading ? null : () => _handleRequestGps(context),
            icon: isLoading
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: primaryFg,
                    ),
                  )
                : const Icon(Icons.my_location_rounded, size: 16),
            label: Text(retryLabel),
          ),
      ],
    );
  }
}

/// Location, freshness, calculation method, GPS refresher, and next prayer countdown banner.
/// Strictly GPS-only with truthful unknown / cached-stale / current states.
class PrayerLocationBanner extends StatelessWidget {
  final PrayerData? data;

  const PrayerLocationBanner({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final service = PrayerService.instance;
    final freshness = service.locationFreshness;
    final ageLabel = service.cachedFixAgeLabel;

    return Card(
      color: AppColors.primaryGreen,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const ExcludeSemantics(
                        child: Icon(
                          Icons.my_location_rounded,
                          color: AppColors.softGold,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          PrayerService.formatDisplayLocationName(
                            data,
                            freshness,
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 14.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  GpsFreshnessChip(freshness: freshness, onDarkSurface: true),
                ],
              ),
            ),
            const SizedBox(height: 6),
            if (ageLabel != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  freshness == LocationFreshness.cachedStale
                      ? '$ageLabel — يوصى بتحديث موقعك عبر GPS'
                      : ageLabel,
                  style: const TextStyle(
                    color: Color(0xFFFEF3C7),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Text(
              'طريقة الحساب: ${SettingsService.calculationMethods.firstWhere((m) => m['id'] == SettingsService.instance.calculationMethod, orElse: () => SettingsService.calculationMethods.first)['name']}',
              style: const TextStyle(
                color: AppColors.softGold,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            if (data == null) ...[
              Text(
                GpsLocationActionControls.describeUnavailableReason(service),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              const GpsLocationActionControls(onDarkSurface: true),
            ] else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('banner_gps_refresh_button'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accentGold,
                      foregroundColor: AppColors.primaryGreen,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    onPressed: service.isLoading
                        ? null
                        : () async {
                            final ok =
                                await PrayerService.instance.requestGpsLocation();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    ok
                                        ? 'تم تحديث الموقع الفعلي عبر GPS بنجاح'
                                        : GpsLocationActionControls
                                            .describeUnavailableReason(
                                                PrayerService.instance),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  backgroundColor: ok
                                      ? AppColors.secondaryGreen
                                      : Colors.redAccent,
                                ),
                              );
                            }
                          },
                    icon: service.isLoading
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primaryGreen,
                            ),
                          )
                        : const Icon(Icons.refresh_rounded, size: 16),
                    label: Text(
                      service.isLoading ? 'جاري التحديث...' : 'تحديث الموقع (GPS)',
                    ),
                  ),
                ],
              ),
            ],
            if (data?.nextPrayer != null) ...[
              const Divider(color: Colors.white24, height: 24),
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceAround,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    Column(
                      children: [
                        const Text(
                          'الصلاة القادمة',
                          style: TextStyle(
                            color: AppColors.softGold,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          data!.nextPrayer!.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                          ),
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
                              decoration: BoxDecoration(
                                color: freshness == LocationFreshness.cachedStale
                                    ? const Color(0xFFF59E0B)
                                    : const Color(0xFF4ADE80),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const Flexible(
                              child: Text(
                                'الوقت المتبقي',
                                style: TextStyle(
                                  color: AppColors.softGold,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          PrayerService.instance
                              .formatCountdown(data!.timeToNextPrayer),
                          style: const TextStyle(
                            color: AppColors.accentGold,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
