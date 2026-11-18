import '../../core/services/settings_service.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../../core/services/prayer_service.dart';
import '../../core/theme/app_theme.dart';
import 'widgets/prayer_location_banner.dart';

class QiblaCompassScreen extends StatefulWidget {
  final Stream<MagnetometerEvent>? magnetometerStreamForTesting;
  final DateTime Function()? nowProviderForTesting;

  static const Duration sensorHeadingStaleTimeout = Duration(seconds: 5);

  const QiblaCompassScreen({
    super.key,
    this.magnetometerStreamForTesting,
    this.nowProviderForTesting,
  });

  @override
  State<QiblaCompassScreen> createState() => _QiblaCompassScreenState();
}

class _QiblaCompassScreenState extends State<QiblaCompassScreen>
    with SingleTickerProviderStateMixin {
  StreamSubscription<MagnetometerEvent>? _magnetometerSub;
  double _deviceHeading = 0.0;
  double _smoothSin = 0.0;
  double _smoothCos = 1.0;
  bool _hasInitialSample = false;
  DateTime? _lastSensorSampleTime;
  DateTime? _lastUiUpdateTime;
  bool _sensorFailed = false;
  bool _sensorDone = false;
  bool _sensorStale = false;
  Timer? _sensorFreshnessTimer;
  bool _wasAligned = false;
  late AnimationController _pulseController;
  DateTime? _lastIntenseVibeTime;

  DateTime _now() => (widget.nowProviderForTesting ?? DateTime.now)();

  bool get _hasLiveHeading {
    if (_sensorFailed || _sensorDone || _sensorStale || !_hasInitialSample) {
      return false;
    }
    final last = _lastSensorSampleTime;
    if (last == null) return false;
    final age = _now().difference(last);
    if (age.isNegative) return false;
    return age < QiblaCompassScreen.sensorHeadingStaleTimeout;
  }

  void _invalidateSensorHeading({
    bool failed = false,
    bool done = false,
    bool stale = false,
  }) {
    _sensorFreshnessTimer?.cancel();
    _sensorFreshnessTimer = null;
    _hasInitialSample = false;
    _lastSensorSampleTime = null;
    _lastUiUpdateTime = null;
    _wasAligned = false;
    _sensorFailed = failed;
    _sensorDone = done;
    _sensorStale = stale;
  }

  static const double kaabaLat = 21.422487;
  static const double kaabaLng = 39.826206;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PrayerService.instance.checkAndUpdateLocationOnResume();
    });
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _initCompass();
  }

  void _triggerIntenseQiblaVibration() {
    final now = DateTime.now();
    if (_lastIntenseVibeTime != null &&
        now.difference(_lastIntenseVibeTime!).inMilliseconds < 1800) {
      return;
    }
    _lastIntenseVibeTime = now;

    // Distinct, powerful multi-pulse tactile vibration sequence (respecting hapticEnabled)
    if (SettingsService.instance.hapticEnabled) {
      HapticFeedback.vibrate();
      Future.delayed(const Duration(milliseconds: 140), () {
        if (mounted) HapticFeedback.heavyImpact();
      });
      Future.delayed(const Duration(milliseconds: 280), () {
        if (mounted) HapticFeedback.vibrate();
      });
      Future.delayed(const Duration(milliseconds: 440), () {
        if (mounted) HapticFeedback.heavyImpact();
      });
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) HapticFeedback.vibrate();
      });
    }
  }

  void _initCompass() {
    try {
      _magnetometerSub?.cancel();
      final stream =
          widget.magnetometerStreamForTesting ?? magnetometerEventStream();
      _magnetometerSub = stream.listen(
        (MagnetometerEvent event) {
          // Reject non-finite or zero-magnitude magnetometer vectors
          if (!event.x.isFinite ||
              !event.y.isFinite ||
              (event.x == 0.0 && event.y == 0.0)) {
            return;
          }

          final now = _now();
          final wasLive = _hasLiveHeading;

          // Calculate raw heading in radians from magnetic field vector
          final rawRad = atan2(-event.x, event.y);

          // Circular low-pass filter on unit circle (sin/cos EMA) to prevent 0°/360° wrap-around spin & sensor jitter (Bug #11 fix).
          // Reset filter whenever recovering from initial/stale/lost state so no unbounded remembered heading bleeds in.
          const double alpha = 0.18;
          if (!wasLive || !_hasInitialSample) {
            _smoothSin = sin(rawRad);
            _smoothCos = cos(rawRad);
            _hasInitialSample = true;
            _lastUiUpdateTime = null;
          } else {
            _smoothSin = (1 - alpha) * _smoothSin + alpha * sin(rawRad);
            _smoothCos = (1 - alpha) * _smoothCos + alpha * cos(rawRad);
          }

          double heading = atan2(_smoothSin, _smoothCos) * (180.0 / pi);
          if (heading < 0) {
            heading += 360.0;
          }

          _lastSensorSampleTime = now;
          _sensorFailed = false;
          _sensorDone = false;
          _sensorStale = false;

          _sensorFreshnessTimer?.cancel();
          _sensorFreshnessTimer = Timer(
            QiblaCompassScreen.sensorHeadingStaleTimeout,
            () {
              if (!mounted) return;
              setState(() {
                _invalidateSensorHeading(stale: true);
              });
            },
          );

          if (mounted) {
            final qibla = PrayerService.instance.currentData?.qiblaDegrees;
            final bool isAligned;
            if (qibla != null) {
              final diff = (heading - qibla).abs() % 360.0;
              isAligned = diff < 3.5 || diff > 356.5;
            } else {
              isAligned = false;
            }

            if (isAligned && !_wasAligned) {
              _triggerIntenseQiblaVibration();
            }
            _wasAligned = isAligned;

            // Always rebuild immediately when transitioning from non-live -> live;
            // otherwise throttle UI rebuilds to ~25 FPS or >=0.4° angular change.
            double deltaDeg = (heading - _deviceHeading).abs();
            if (deltaDeg > 180.0) deltaDeg = 360.0 - deltaDeg;
            if (!wasLive ||
                _lastUiUpdateTime == null ||
                now.difference(_lastUiUpdateTime!).inMilliseconds >= 40 ||
                deltaDeg >= 0.4) {
              _lastUiUpdateTime = now;
              setState(() {
                _deviceHeading = heading;
              });
            }
          }
        },
        onError: (err) {
          if (mounted) {
            setState(() {
              _invalidateSensorHeading(failed: true);
            });
          }
        },
        onDone: () {
          if (mounted) {
            setState(() {
              _invalidateSensorHeading(done: true);
            });
          }
        },
        cancelOnError: false,
      );
    } catch (_) {
      _invalidateSensorHeading(failed: true);
    }
  }

  @override
  void dispose() {
    _sensorFreshnessTimer?.cancel();
    _magnetometerSub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  double _calculateDistanceToKaaba(double lat, double lng) {
    const earthRadiusKm = 6371.0;
    final dLat = (kaabaLat - lat) * (pi / 180.0);
    final dLon = (kaabaLng - lng) * (pi / 180.0);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat * (pi / 180.0)) * cos(kaabaLat * (pi / 180.0)) *
        sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: Listenable.merge([
        PrayerService.instance,
        SettingsService.instance,
      ]),
      builder: (context, _) {
        final service = PrayerService.instance;
        final prayerData = service.currentData;
        final double? qiblaDegrees = prayerData?.qiblaDegrees;
        final double? distanceKm = prayerData != null
            ? _calculateDistanceToKaaba(
                prayerData.latitude,
                prayerData.longitude,
              )
            : null;
        final freshness = service.locationFreshness;
        final ageLabel = service.cachedFixAgeLabel;

        // Require BOTH verified GPS target AND live fresh sensor heading for needle & alignment guidance
        final bool liveHeading = _hasLiveHeading;
        final bool canShowLiveNeedle = qiblaDegrees != null && liveHeading;
        final double relativeAngle = canShowLiveNeedle
            ? (qiblaDegrees - _deviceHeading) * (pi / 180.0)
            : 0.0;
        final bool isAligned = canShowLiveNeedle &&
            (((qiblaDegrees - _deviceHeading).abs() % 360) < 3.5 ||
                ((qiblaDegrees - _deviceHeading).abs() % 360) > 356.5);
        final bool sensorUnavailable = _sensorFailed || _sensorDone;

        final String guidanceText;
        final String dialUnavailableText;
        final IconData dialUnavailableIcon;
        if (qiblaDegrees == null) {
          guidanceText =
              'البوصلة غير مفعّلة: لا يمكن عرض اتجاه القبلة قبل تحديد موقعك عبر GPS';
          dialUnavailableText = 'لا يوجد اتجاه للقبلة بدون موقع GPS';
          dialUnavailableIcon = Icons.location_off_rounded;
        } else if (sensorUnavailable) {
          guidanceText =
              'حساس البوصلة غير متاح — اعتمد على زاوية القبلة الجغرافية (${qiblaDegrees.toStringAsFixed(0)}°)';
          dialUnavailableText =
              'حساس البوصلة غير متاح — الزاوية الجغرافية ${qiblaDegrees.toStringAsFixed(0)}°';
          dialUnavailableIcon = Icons.sensors_off_rounded;
        } else if (_sensorStale) {
          guidanceText =
              'توقفت قراءات حساس البوصلة — بانتظار قراءة حديثة لتفعيل السهم';
          dialUnavailableText = 'انتهت صلاحية قراءة الحساس — بانتظار قراءة حديثة';
          dialUnavailableIcon = Icons.sensors_off_rounded;
        } else if (!liveHeading) {
          guidanceText =
              'بانتظار قراءة حساس البوصلة لتفعيل السهم (الزاوية الجغرافية ${qiblaDegrees.toStringAsFixed(0)}°)';
          dialUnavailableText = 'بانتظار قراءة حساس البوصلة';
          dialUnavailableIcon = Icons.explore_outlined;
        } else if (isAligned) {
          guidanceText = 'أنت الآن باتجاه القبلة المشرفة 🕋 (اهتزاز تأكيدي نشط)';
          dialUnavailableText = '';
          dialUnavailableIcon = Icons.explore_outlined;
        } else {
          guidanceText = 'حرك الهاتف حتى يشير السهم الذهبي للأعلى';
          dialUnavailableText = '';
          dialUnavailableIcon = Icons.explore_outlined;
        }

        return Directionality(
          textDirection: SettingsService.instance.textDirection,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('بوصلة القبلة التفاعلية'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  tooltip: 'إرشادات الدقة',
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => Directionality(
                        textDirection: SettingsService.instance.textDirection,
                        child: AlertDialog(
                          title: const Text('معايرة البوصلة'),
                          content: const Text(
                            'لضمان أعلى دقة لبوصلة القبلة:\n\n'
                            '١. أمسك الهاتف بشكل أفقي مستوٍ.\n'
                            '٢. ابتعد عن الأجهزة الكهربائية والمغناطيسية والأسطح المعدنية.\n'
                            '٣. حرك الهاتف ببطء في الهواء على شكل رقم 8 لمعايرة الحساس.',
                            style: TextStyle(height: 1.6),
                          ),
                          actions: [
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primaryGreen,
                              ),
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('حسناً'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.only(top: 12, bottom: 20),
                children: [
                  // Location and Bearing Summary Card
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isAligned
                            ? [const Color(0xFF1B4332), const Color(0xFF2D6A4F)]
                            : (isDark
                                ? [
                                    AppColors.darkSurface,
                                    const Color(0xFF263238)
                                  ]
                                : [
                                    AppColors.primaryGreen
                                        .withValues(alpha: 0.08),
                                    AppColors.softGold.withValues(alpha: 0.18)
                                  ]),
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isAligned
                            ? AppColors.accentGold
                            : AppColors.accentGold.withValues(alpha: 0.4),
                        width: isAligned ? 2 : 1,
                      ),
                      boxShadow: isAligned
                          ? [
                              BoxShadow(
                                color:
                                    AppColors.accentGold.withValues(alpha: 0.4),
                                blurRadius: 16,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
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
                                  Icon(
                                    Icons.location_on,
                                    size: 16,
                                    color: isAligned
                                        ? AppColors.accentGold
                                        : AppColors.primaryGreen,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      PrayerService.formatDisplayLocationName(
                                        prayerData,
                                        freshness,
                                        unknownFallback: 'الموقع غير محدد بعد',
                                      ),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: isAligned
                                            ? Colors.white
                                            : (isDark
                                                ? Colors.white
                                                : AppColors.primaryGreen),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              GpsFreshnessChip(
                                freshness: freshness,
                                onDarkSurface: isAligned,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (ageLabel != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              ageLabel,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isAligned
                                    ? Colors.white70
                                    : AppColors.mutedText,
                              ),
                            ),
                          ),
                        if (prayerData == null) ...[
                          Text(
                            GpsLocationActionControls.describeUnavailableReason(
                              service,
                              promptContext: GpsPromptContext.qibla,
                            ),
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: isDark
                                  ? Colors.white70
                                  : AppColors.lightText,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const GpsLocationActionControls(
                            promptContext: GpsPromptContext.qibla,
                          ),
                        ] else ...[
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            spacing: 12,
                            runSpacing: 6,
                            children: [
                              Text(
                                'المسافة إلى مكة: ${distanceKm!.toStringAsFixed(0)} كم',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isAligned
                                      ? AppColors.softGold
                                      : AppColors.mutedText,
                                ),
                              ),
                              Text(
                                'زاوية القبلة: ${qiblaDegrees!.toStringAsFixed(1)}° (${_getDirectionLabel(qiblaDegrees)})',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: isAligned
                                      ? AppColors.accentGold
                                      : AppColors.primaryGreen,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Alignment / Availability Guidance Banner
                  Semantics(
                    key: const ValueKey('qibla_guidance_banner'),
                    container: true,
                    label: guidanceText,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 16,
                      ),
                      decoration: BoxDecoration(
                        gradient: isAligned
                            ? const LinearGradient(
                                colors: [Color(0xFF0F513A), Color(0xFF1B4332)],
                              )
                            : null,
                        color: isAligned
                            ? null
                            : (isDark
                                ? Colors.white10
                                : Colors.black.withValues(alpha: 0.04)),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isAligned
                              ? AppColors.accentGold
                              : Colors.transparent,
                          width: isAligned ? 2.0 : 1.0,
                        ),
                        boxShadow: isAligned
                            ? [
                                BoxShadow(
                                  color: AppColors.accentGold
                                      .withValues(alpha: 0.35),
                                  blurRadius: 12,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ExcludeSemantics(
                            child: Icon(
                              isAligned
                                  ? Icons.vibration
                                  : (!canShowLiveNeedle
                                      ? dialUnavailableIcon
                                      : Icons.explore_outlined),
                              color: AppColors.accentGold,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: ExcludeSemantics(
                              child: Text(
                                guidanceText,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: isAligned
                                      ? Colors.white
                                      : (isDark
                                          ? Colors.white70
                                          : AppColors.lightText),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Interactive Compass Rose Dial
                  Center(
                    child: Opacity(
                      opacity: canShowLiveNeedle ? 1.0 : 0.55,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                    // Outer Compass Rose Rotating with Device Heading (only when live sensor heading exists)
                    Transform.rotate(
                      angle: liveHeading ? -_deviceHeading * (pi / 180.0) : 0.0,
                      child: Container(
                        width: 290,
                        height: 290,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark ? AppColors.darkSurface : Colors.white,
                          border: Border.all(
                            color: isAligned ? AppColors.accentGold : (isDark ? Colors.white24 : Colors.black12),
                            width: isAligned ? 3 : 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isAligned
                                  ? AppColors.accentGold.withValues(alpha: 0.3)
                                  : Colors.black.withValues(alpha: 0.08),
                              blurRadius: 24,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Cardinal Directions: N, E, S, W
                            const Positioned(
                              top: 10,
                              child: Text('ش', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 16)),
                            ),
                            const Positioned(
                              bottom: 10,
                              child: Text('ج', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            ),
                            const Positioned(
                              right: 12,
                              child: Text('ق', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            ),
                            const Positioned(
                              left: 12,
                              child: Text('غ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            ),

                            // Intermediate Degrees Ticks
                            ...List.generate(12, (index) {
                              final angle = index * 30.0;
                              return Transform.rotate(
                                angle: angle * (pi / 180.0),
                                child: Align(
                                  alignment: Alignment.topCenter,
                                  child: Container(
                                    width: index % 3 == 0 ? 3 : 1.5,
                                    height: index % 3 == 0 ? 14 : 8,
                                    margin: const EdgeInsets.only(top: 28),
                                    color: index == 0 ? Colors.red : (isDark ? Colors.white38 : Colors.black26),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),

                    if (!canShowLiveNeedle)
                      // Unavailable / Waiting / Stale Sensor Notice — NEVER render a Qibla needle without BOTH GPS target AND live fresh heading
                      Semantics(
                        container: true,
                        label: dialUnavailableText,
                        child: Container(
                          key: const ValueKey('qibla_unavailable_dial_notice'),
                          width: 196,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1E293B)
                                : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isDark ? Colors.white24 : Colors.black12,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ExcludeSemantics(
                                child: Icon(
                                  dialUnavailableIcon,
                                  size: 22,
                                  color: isDark
                                      ? AppColors.softGold
                                      : AppColors.primaryGreen,
                                ),
                              ),
                              const SizedBox(height: 4),
                              ExcludeSemantics(
                                child: Text(
                                  dialUnavailableText,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11,
                                    height: 1.25,
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? Colors.white
                                        : AppColors.primaryGreen,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else ...[
                      // Qibla Pointer Needle (ONLY when BOTH verified GPS target AND live fresh sensor heading exist)
                      Transform.rotate(
                        key: const ValueKey('qibla_direction_needle'),
                        angle: relativeAngle,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Kaaba Icon at the tip of the needle
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: isAligned ? AppColors.accentGold : AppColors.primaryGreen,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.accentGold.withValues(alpha: 0.5),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: const Text('🕋', style: TextStyle(fontSize: 18)),
                            ),
                            // Gold Indicator Needle
                            CustomPaint(
                              size: const Size(20, 100),
                              painter: _QiblaNeedlePainter(isAligned: isAligned),
                            ),
                            const SizedBox(height: 100), // balance center
                          ],
                        ),
                      ),

                      // Center Hub Pivot
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isAligned ? AppColors.accentGold : AppColors.primaryGreen,
                          border: Border.all(color: Colors.white, width: 2.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

              const SizedBox(height: 16),

              // Bottom Real-time Sensor Status & Degree Readout
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurface : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                ),
                child: Wrap(
                  alignment: WrapAlignment.spaceAround,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _buildCompassStat(
                      key: const ValueKey('qibla_sensor_heading_stat'),
                      title: 'اتجاه الهاتف',
                      value: liveHeading
                          ? '${_deviceHeading.toStringAsFixed(0)}°'
                          : 'غير متاح',
                      isDark: isDark,
                    ),
                    _buildCompassStat(
                      key: const ValueKey('qibla_target_angle_stat'),
                      title: 'زاوية القبلة',
                      value: qiblaDegrees != null
                          ? '${qiblaDegrees.toStringAsFixed(0)}°'
                          : 'غير محدد (يتطلب GPS)',
                      isDark: isDark,
                      highlight: qiblaDegrees != null,
                    ),
                    _buildCompassStat(
                      key: const ValueKey('qibla_sensor_status_stat'),
                      title: 'حالة الحساس',
                      value: sensorUnavailable
                          ? 'غير متاح'
                          : (_sensorStale
                              ? 'قراءة منتهية'
                              : (liveHeading ? 'نشط' : 'بانتظار الحساس')),
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
      },
    );
  }

  static String _getDirectionLabel(double deg) {
    if (deg >= 337.5 || deg < 22.5) return 'الشمال';
    if (deg >= 22.5 && deg < 67.5) return 'شمال شرق';
    if (deg >= 67.5 && deg < 112.5) return 'الشرق';
    if (deg >= 112.5 && deg < 157.5) return 'جنوب شرق';
    if (deg >= 157.5 && deg < 202.5) return 'الجنوب';
    if (deg >= 202.5 && deg < 247.5) return 'جنوب غرب';
    if (deg >= 247.5 && deg < 292.5) return 'الغرب';
    return 'شمال غرب';
  }

  Widget _buildCompassStat({
    Key? key,
    required String title,
    required String value,
    required bool isDark,
    bool highlight = false,
  }) {
    return Semantics(
      container: true,
      label: '$title: $value',
      child: Column(
        key: key,
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white60 : AppColors.mutedText,
              ),
            ),
          ),
          const SizedBox(height: 3),
          ExcludeSemantics(
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: highlight
                    ? AppColors.accentGold
                    : (isDark ? Colors.white : AppColors.primaryGreen),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QiblaNeedlePainter extends CustomPainter {
  final bool isAligned;

  _QiblaNeedlePainter({required this.isAligned});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isAligned ? const Color(0xFFD4AF37) : const Color(0xFF1B4332)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(size.width / 2, 0) // tip
      ..lineTo(size.width, size.height)
      ..lineTo(size.width / 2, size.height * 0.8)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(path, paint);

    // Subtle edge highlight
    final borderPaint = Paint()
      ..color = Colors.white70
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _QiblaNeedlePainter oldDelegate) {
    return oldDelegate.isAligned != isAligned;
  }
}
