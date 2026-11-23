import 'dart:async';
import 'package:adhan_dart/adhan_dart.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../logging/app_logger.dart';
import '../models/arab_countries.dart';
import '../models/prayer_data.dart';
import '../notifications/prayer_notification_service.dart';
import 'fajr_qiyam_alarm_service.dart';
import 'prayer_schedule_calculator.dart';
import 'settings_service.dart';

export '../models/arab_countries.dart';
export '../models/prayer_data.dart';

class HijriDateHelper {
  static const List<String> hijriMonths = [
    'المحرم', 'صفر', 'ربيع الأول', 'ربيع الآخر',
    'جمادى الأولى', 'جمادى الآخرة', 'رجب', 'شعبان',
    'رمضان', 'شوال', 'ذو القعدة', 'ذو الحجة'
  ];

  static const List<String> gregorianMonths = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
  ];

  static const List<String> arabicDays = [
    'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'
  ];

  /// Converts Gregorian DateTime to Hijri (year, month, day)
  /// Applies [adjustmentDays] (or persisted SettingsService.hijriAdjustmentDays)
  static Map<String, int> toHijri(DateTime date, {int? adjustmentDays}) {
    final int adj = adjustmentDays ?? SettingsService.instance.hijriAdjustmentDays;
    final DateTime effective = adj == 0 ? date : date.add(Duration(days: adj));

    int y = effective.year;
    int m = effective.month;
    int d = effective.day;

    if (m <= 2) {
      y -= 1;
      m += 12;
    }
    int a = y ~/ 100;
    int b = 2 - a + (a ~/ 4);
    int jd = (365.25 * (y + 4716)).floor() + (30.6001 * (m + 1)).floor() + d + b - 1524;
    int l = jd - 1948440 + 10632;
    int n = (l - 1) ~/ 10631;
    l = l - 10631 * n + 354;
    int j = (((10985 - l) ~/ 5316) * ((50 * l) ~/ 17719)) + ((l ~/ 5670) * ((43 * l) ~/ 15238));
    l = l - (((30 - j) ~/ 15) * ((17719 * j) ~/ 50)) - ((j ~/ 16) * ((15238 * j) ~/ 43)) + 29;
    int hm = (24 * l) ~/ 709;
    int hd = l - (709 * hm) ~/ 24;
    int hy = 30 * n + j - 30;

    return {'year': hy, 'month': hm.clamp(1, 12), 'day': hd.clamp(1, 30)};
  }

  /// Returns full Hijri text: e.g. "4 جمادى الأولى 1448 هـ"
  static String getHijriDateString([DateTime? date]) {
    final d = date ?? DateTime.now();
    final h = toHijri(d);
    final monthName = hijriMonths[h['month']! - 1];
    return '${h['day']} $monthName ${h['year']} هـ';
  }

  /// Returns full Gregorian text: e.g. "16 أكتوبر 2026 م"
  static String getGregorianDateString([DateTime? date]) {
    final d = date ?? DateTime.now();
    final monthName = gregorianMonths[d.month - 1];
    return '${d.day} $monthName ${d.year} م';
  }

  /// Returns day of the week: e.g. "الجمعة"
  static String getDayOfWeek([DateTime? date]) {
    final d = date ?? DateTime.now();
    return arabicDays[d.weekday - 1];
  }
}

enum LocationErrorType {
  none,
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  timeout,
  unavailable,
}

enum LocationFreshness {
  unknown,
  current,
  cachedStale,
}

/// Injectable seam around platform location APIs so GPS/permission/settings
/// flows can be verified deterministically in tests without live device GPS.
abstract class PrayerLocationProvider {
  Future<bool> isLocationServiceEnabled();
  Future<LocationPermission> checkPermission();
  Future<LocationPermission> requestPermission();
  Future<bool> openLocationSettings();
  Future<bool> openAppSettings();
  Future<Position?> getLastKnownPosition();
  Future<Position> getCurrentPosition({
    required LocationAccuracy desiredAccuracy,
    required Duration timeLimit,
  });
  Stream<Position> getPositionStream({
    required LocationSettings locationSettings,
  });
  double distanceBetween(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  );
}

class _GeolocatorLocationProvider implements PrayerLocationProvider {
  const _GeolocatorLocationProvider();

  @override
  Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  @override
  Future<Position?> getLastKnownPosition() => Geolocator.getLastKnownPosition();

  @override
  Future<Position> getCurrentPosition({
    required LocationAccuracy desiredAccuracy,
    required Duration timeLimit,
  }) {
    return Geolocator.getCurrentPosition(
      desiredAccuracy: desiredAccuracy,
      timeLimit: timeLimit,
    );
  }

  @override
  Stream<Position> getPositionStream({
    required LocationSettings locationSettings,
  }) {
    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }

  @override
  double distanceBetween(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) {
    return Geolocator.distanceBetween(
      startLatitude,
      startLongitude,
      endLatitude,
      endLongitude,
    );
  }
}

class PrayerService extends ChangeNotifier {
  static final PrayerService instance = PrayerService._internal();
  PrayerService._internal();

  /// Read-only geographic reference catalog used strictly to assign a human
  /// label to verified GPS coordinates (never for manual city selection).
  static List<CityCoordinate> get famousCities => ArabCountriesData.allCities;

  static const String locationSourceKey = 'location_source';
  static const String locationSourceGps = 'gps';
  static const String locationUpdatedAtMsKey = 'location_updated_at_ms';
  static const Duration gpsCacheStaleThreshold = Duration(minutes: 15);

  /// Strict zero-future skew policy: any GPS or persisted timestamp strictly
  /// after the current device clock (`epochMs > nowUtcMs`) is rejected so a
  /// future-dated fix is never accepted, persisted, or claimed as current.
  static const Duration maxAllowedFutureSkew = Duration.zero;
  static const int minValidFixEpochMs = 946684800000; // 2000-01-01T00:00:00Z

  static bool isValidFixTimestampMs(int? epochMs, {DateTime? now}) {
    if (epochMs == null || epochMs < minValidFixEpochMs) return false;
    final nowUtcMs = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    return epochMs <= nowUtcMs + maxAllowedFutureSkew.inMilliseconds;
  }

  bool isValidFixTimestampMsNow(int? epochMs) =>
      isValidFixTimestampMs(epochMs, now: _nowProvider());

  PrayerLocationProvider _locationProvider = const _GeolocatorLocationProvider();
  DateTime Function() _nowProvider = DateTime.now;
  PrayerData? _currentData;
  DateTime? _lastGpsFixTime;
  bool _isFromLiveFixThisSession = false;
  bool _isLoading = false;
  bool _isInitialized = false;
  String? _errorMessage;
  LocationErrorType _lastLocationError = LocationErrorType.none;
  int _locationRequestGeneration = 0;
  Future<void>? _activeLocationMutation;
  Timer? _tickerTimer;
  StreamSubscription<Position>? _positionStreamSubscription;
  String _lastCalculationMethod = '';

  /// Lightweight 1-second notifier for countdown badges so the entire HomeScreen
  /// does not rebuild 86,400 times per day (Bug #2 fix).
  final ValueNotifier<Duration> countdownNotifier =
      ValueNotifier<Duration>(Duration.zero);

  PrayerData? get currentData => _currentData;
  bool get hasVerifiedGpsLocation => _currentData != null;
  DateTime? get lastGpsFixTime => _lastGpsFixTime;
  bool get isLocationStale {
    if (_currentData == null) return false;
    if (!_isFromLiveFixThisSession) return true;
    final fixTime = _lastGpsFixTime;
    if (fixTime == null) return true;
    final now = _nowProvider();
    if (!isValidFixTimestampMs(fixTime.toUtc().millisecondsSinceEpoch, now: now)) {
      return true;
    }
    return now.difference(fixTime) >= gpsCacheStaleThreshold;
  }

  LocationFreshness get locationFreshness {
    if (_currentData == null) return LocationFreshness.unknown;
    return isLocationStale
        ? LocationFreshness.cachedStale
        : LocationFreshness.current;
  }

  /// Formats a truthful location headline that explicitly labels cached/stale
  /// fixes as saved locations (`موقع محفوظ`) instead of claiming current live
  /// location (`موقعك الفعلي`).
  static String formatDisplayLocationName(
    PrayerData? data,
    LocationFreshness freshness, {
    String unknownFallback = 'الموقع الجغرافي غير محدد بعد',
  }) {
    if (data == null) return unknownFallback;
    final raw = data.locationName;
    if (freshness == LocationFreshness.cachedStale) {
      if (raw.contains('موقعك الفعلي')) {
        return raw.replaceAll('موقعك الفعلي', 'موقع محفوظ');
      }
      if (raw.contains('موقع محفوظ')) {
        return raw;
      }
      return 'موقع محفوظ: $raw';
    }
    return raw;
  }

  String? get cachedFixAgeLabel {
    final fixTime = _lastGpsFixTime;
    if (_currentData == null || fixTime == null) return null;
    final diff = _nowProvider().difference(fixTime);
    if (diff.isNegative || diff.inMinutes < 1) {
      return 'تم التحديث للتو';
    }
    if (diff.inMinutes < 60) {
      return 'آخر تحديث منذ ${diff.inMinutes} دقيقة';
    }
    if (diff.inHours < 24) {
      return 'آخر تحديث منذ ${diff.inHours} ساعة';
    }
    return 'آخر تحديث منذ ${diff.inDays} يوم';
  }

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  LocationErrorType get lastLocationError => _lastLocationError;

  @visibleForTesting
  void setLocationProviderForTesting(PrayerLocationProvider? provider) {
    _locationRequestGeneration++;
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _locationProvider = provider ?? const _GeolocatorLocationProvider();
  }

  @visibleForTesting
  void setClockForTesting(DateTime Function()? nowProvider) {
    _nowProvider = nowProvider ?? DateTime.now;
  }

  Future<bool> openLocationSettings() async {
    try {
      return await _locationProvider.openLocationSettings();
    } catch (e, stack) {
      AppLogger.warn('PrayerService.openLocationSettings', e, stack);
      return false;
    }
  }

  Future<bool> openAppSettings() async {
    try {
      return await _locationProvider.openAppSettings();
    } catch (e, stack) {
      AppLogger.warn('PrayerService.openAppSettings', e, stack);
      return false;
    }
  }

  /// Serializes location preference writes and state publication so concurrent
  /// GPS, stream, migration, and clear mutations cannot interleave persistence
  /// writes or publish stale state out of order.
  Future<T> _serializeLocationMutation<T>(Future<T> Function() action) async {
    final previous = _activeLocationMutation;
    final currentGate = Completer<void>();
    _activeLocationMutation = currentGate.future;
    if (previous != null) {
      try {
        await previous;
      } catch (e, stack) {
        AppLogger.warn('PrayerService._serializeLocationMutation', e, stack);
      }
    }
    try {
      return await action();
    } finally {
      if (identical(_activeLocationMutation, currentGate.future)) {
        _activeLocationMutation = null;
      }
      if (!currentGate.isCompleted) {
        currentGate.complete();
      }
    }
  }

  static bool _isValidCoordinate(double lat, double lng) {
    return lat.isFinite &&
        lng.isFinite &&
        lat >= -90.0 &&
        lat <= 90.0 &&
        lng >= -180.0 &&
        lng <= 180.0;
  }

  DateTime? _validatedFixTime(DateTime rawTimestamp) {
    final utcMs = rawTimestamp.toUtc().millisecondsSinceEpoch;
    if (!isValidFixTimestampMs(utcMs, now: _nowProvider())) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(utcMs, isUtc: true).toLocal();
  }

  void _setLocationError(LocationErrorType type, String message) {
    _lastLocationError = type;
    _errorMessage = message;
    notifyListeners();
  }

  void _clearLocationError() {
    _lastLocationError = LocationErrorType.none;
    _errorMessage = null;
  }

  Future<void> _removeLegacyManualKeys(SharedPreferences prefs) async {
    await prefs.remove('is_manual_location');
    await prefs.remove('auto_location_enabled');
    await prefs.remove('last_country');
  }

  Future<void> _removeAllPersistedLocationKeys(SharedPreferences prefs) async {
    await _removeLegacyManualKeys(prefs);
    await prefs.remove('last_latitude');
    await prefs.remove('last_longitude');
    await prefs.remove('last_city');
    await prefs.remove(locationSourceKey);
    await prefs.remove(locationUpdatedAtMsKey);
  }

  Future<void> _cancelDerivedNotificationsForUnknown() async {
    try {
      await PrayerNotificationService.instance
          .cancelLocationDerivedNotifications(cancelStaleAdhanSnooze: true);
    } catch (e, stack) {
      AppLogger.warn('PrayerService._cancelDerivedNotificationsForUnknown.notif', e, stack);
    }
    try {
      await FajrQiyamAlarmService.instance.syncWithLocationAvailability();
    } catch (e, stack) {
      AppLogger.warn('PrayerService._cancelDerivedNotificationsForUnknown.alarm', e, stack);
    }
  }

  ({String locationName, String? calculationMethod}) _resolveCityMatch(
    double lat,
    double lng,
  ) {
    double minDistanceKm = double.infinity;
    CityCoordinate? closestCity;

    for (final c in famousCities) {
      final distKm =
          _locationProvider.distanceBetween(lat, lng, c.latitude, c.longitude) /
              1000.0;
      if (distKm < minDistanceKm) {
        minDistanceKm = distKm;
        closestCity = c;
      }
    }

    if (closestCity != null && minDistanceKm <= 150.0) {
      return (
        locationName: '${closestCity.name}، ${closestCity.country} (موقعك الفعلي)',
        calculationMethod:
            closestCity.method.isNotEmpty ? closestCity.method : null,
      );
    }

    return (
      locationName:
          'موقعك الفعلي (${lat.toStringAsFixed(2)}°, ${lng.toStringAsFixed(2)}°)',
      calculationMethod: null,
    );
  }

  String identifyCity(double lat, double lng) {
    return _resolveCityMatch(lat, lng).locationName;
  }

  Future<void> init({bool forceRefresh = false, bool forceReload = false}) async {
    if (_isInitialized && !forceRefresh && !forceReload && _currentData != null) {
      return;
    }

    final int initGeneration =
        forceReload ? ++_locationRequestGeneration : _locationRequestGeneration;
    if (forceReload) {
      _positionStreamSubscription?.cancel();
      _positionStreamSubscription = null;
      _clearLocationError();
    }

    await _serializeLocationMutation<void>(() async {
      if (initGeneration != _locationRequestGeneration) return;
      final prefs = await SharedPreferences.getInstance();
      if (initGeneration != _locationRequestGeneration) return;

      final source = prefs.getString(locationSourceKey);
      final legacyManual = prefs.getBool('is_manual_location');
      final savedLat = prefs.getDouble('last_latitude');
      final savedLng = prefs.getDouble('last_longitude');
      final savedCity = prefs.getString('last_city');
      final updatedAtMs = prefs.getInt(locationUpdatedAtMsKey);

      _lastCalculationMethod = SettingsService.instance.calculationMethod;
      SettingsService.instance.removeListener(_onSettingsChanged);
      SettingsService.instance.addListener(_onSettingsChanged);

      final bool hasVerifiedPersistedGps = source == locationSourceGps &&
          legacyManual != true &&
          savedLat != null &&
          savedLng != null &&
          _isValidCoordinate(savedLat, savedLng) &&
          savedCity != null &&
          savedCity.trim().isNotEmpty &&
          isValidFixTimestampMs(updatedAtMs, now: _nowProvider());

      if (hasVerifiedPersistedGps) {
        await _removeLegacyManualKeys(prefs);
        if (initGeneration != _locationRequestGeneration) return;
        _isFromLiveFixThisSession = false;
        _lastGpsFixTime =
            DateTime.fromMillisecondsSinceEpoch(updatedAtMs!, isUtc: true)
                .toLocal();
        _calculatePrayers(savedLat, savedLng, savedCity);
      } else {
        final bool hadAnyLegacyOrInvalidLocation = savedLat != null ||
            savedLng != null ||
            savedCity != null ||
            source != null ||
            updatedAtMs != null ||
            legacyManual != null ||
            prefs.containsKey('auto_location_enabled') ||
            prefs.containsKey('last_country');
        if (hadAnyLegacyOrInvalidLocation) {
          await _removeAllPersistedLocationKeys(prefs);
          if (initGeneration != _locationRequestGeneration) return;
        }
        _currentData = null;
        _lastGpsFixTime = null;
        _isFromLiveFixThisSession = false;
        countdownNotifier.value = Duration.zero;
        await _cancelDerivedNotificationsForUnknown();
        notifyListeners();
      }
    });

    if (initGeneration != _locationRequestGeneration) return;

    // Setup continuous live ticking every 1 second to update countdown and prayers dynamically
    _startLiveTicker();
    _isInitialized = true;

    // Silently check GPS if permission is already granted (NEVER auto-prompts permission)
    unawaited(checkAndUpdateLocationOnResume(isUserTriggered: false));
  }

  /// Resets location state to UNKNOWN (e.g., on replace-mode backup restore)
  /// without ever importing unverified coordinates as GPS.
  Future<void> clearLocationToUnknown() async {
    final int generation = ++_locationRequestGeneration;
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _clearLocationError();
    _currentData = null;
    _lastGpsFixTime = null;
    _isFromLiveFixThisSession = false;
    countdownNotifier.value = Duration.zero;

    await _serializeLocationMutation<void>(() async {
      if (generation != _locationRequestGeneration) return;
      final prefs = await SharedPreferences.getInstance();
      if (generation != _locationRequestGeneration) return;
      await _removeAllPersistedLocationKeys(prefs);
      if (generation != _locationRequestGeneration) return;
      await _cancelDerivedNotificationsForUnknown();
    });
    notifyListeners();
  }

  void _onSettingsChanged() {
    final currentMethod = SettingsService.instance.calculationMethod;
    if (currentMethod != _lastCalculationMethod) {
      _lastCalculationMethod = currentMethod;
      recalculateWithCurrentSettings();
    }
  }

  /// Recalculates prayer times immediately when calculation method or settings change (Bug #3 fix)
  void recalculateWithCurrentSettings() {
    if (_currentData == null) return;
    _calculatePrayers(
      _currentData!.latitude,
      _currentData!.longitude,
      _currentData!.locationName,
    );
  }

  void _startLiveTicker() {
    _tickerTimer?.cancel();
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_currentData != null) {
        _tickContinuousCountdown();
      }
    });
  }

  /// Cancels live ticker countdown timer (used during testing and cleanup)
  void stopLiveTicker() {
    _tickerTimer?.cancel();
    _tickerTimer = null;
  }

  void _tickContinuousCountdown() {
    if (_currentData == null) return;
    final now = _nowProvider();

    // If date rolled over past midnight, recalculate entire day
    if (now.day != _currentData!.lastUpdated.day) {
      _calculatePrayers(_currentData!.latitude, _currentData!.longitude, _currentData!.locationName);
      return;
    }

    if (_currentData!.nextPrayer != null) {
      final pTime = _currentData!.nextPrayer!.time;
      final diff = pTime.difference(now);

      // When the countdown reaches zero or prayer time arrives, recalculate immediately to shift to next prayer
      if (diff.isNegative || diff.inSeconds <= 0) {
        // This is a display-only countdown transition. Rebuilding the alarm
        // range here can cancel the due native alarm before Android delivers it.
        _calculatePrayers(_currentData!.latitude, _currentData!.longitude, _currentData!.locationName, updateSchedules: false);
        return;
      }

      // Update timeToNextPrayer and lightweight countdownNotifier second-by-second
      _currentData = PrayerData(
        latitude: _currentData!.latitude,
        longitude: _currentData!.longitude,
        locationName: _currentData!.locationName,
        prayers: _currentData!.prayers,
        notificationPrayers: _currentData!.notificationPrayers,
        previousMaghribTime: _currentData!.previousMaghribTime,
        nextPrayer: _currentData!.nextPrayer,
        timeToNextPrayer: diff,
        qiblaDegrees: _currentData!.qiblaDegrees,
        lastUpdated: _currentData!.lastUpdated,
      );
      countdownNotifier.value = diff;

      // Only trigger global ChangeNotifier listeners once per minute instead of every second (Bug #2 fix)
      if (diff.inSeconds % 60 == 0) {
        notifyListeners();
      }
    }
  }

  CalculationParameters _getParams() {
    final method = SettingsService.instance.calculationMethod;
    switch (method) {
      case 'makkah':
        return CalculationMethodParameters.ummAlQura();
      case 'mwl':
        return CalculationMethodParameters.muslimWorldLeague();
      case 'isna':
        return CalculationMethodParameters.northAmerica();
      case 'karachi':
        return CalculationMethodParameters.karachi();
      case 'egyptian':
      default:
        return CalculationMethodParameters.egyptian();
    }
  }

  /// Checks and automatically adapts verified GPS location on launch/resume.
  /// When [isUserTriggered] is false, this checks service/permission only and
  /// NEVER triggers an automatic OS permission prompt.
  Future<bool> checkAndUpdateLocationOnResume({
    bool isUserTriggered = false,
  }) async {
    final int startGeneration =
        isUserTriggered ? ++_locationRequestGeneration : _locationRequestGeneration;

    bool isStaleRequest() => startGeneration != _locationRequestGeneration;

    try {
      final serviceEnabled = await _locationProvider.isLocationServiceEnabled();
      if (isStaleRequest()) return false;
      if (!serviceEnabled) {
        _setLocationError(
          LocationErrorType.serviceDisabled,
          'خدمات تحديد الموقع (GPS) غير مفعلة على الهاتف',
        );
        return false;
      }

      LocationPermission permission = await _locationProvider.checkPermission();
      if (isStaleRequest()) return false;
      if (permission == LocationPermission.denied) {
        if (!isUserTriggered) {
          _setLocationError(
            LocationErrorType.permissionDenied,
            'يلزم منح إذن الوصول إلى الموقع الجغرافي (GPS) لتحديد موقعك',
          );
          return false;
        }
        permission = await _locationProvider.requestPermission();
        if (isStaleRequest()) return false;
      }

      if (permission == LocationPermission.deniedForever) {
        _setLocationError(
          LocationErrorType.permissionDeniedForever,
          'تم رفض إذن الموقع بشكل دائم، يرجى تفعيله من إعدادات التطبيق',
        );
        return false;
      }

      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        _setLocationError(
          LocationErrorType.permissionDenied,
          'تم رفض إذن الوصول إلى الموقع الجغرافي',
        );
        return false;
      }

      // Fast check OS cached position first, validating BOTH coords AND true acquisition timestamp
      Position? cachedPosition = await _locationProvider.getLastKnownPosition();
      if (isStaleRequest()) return false;
      DateTime? cachedFixTime;
      if (cachedPosition != null) {
        final validatedTs = _validatedFixTime(cachedPosition.timestamp);
        if (!_isValidCoordinate(
              cachedPosition.latitude,
              cachedPosition.longitude,
            ) ||
            validatedTs == null) {
          cachedPosition = null;
        } else {
          cachedFixTime = validatedTs;
        }
      }

      final bool cachedIsFreshAndAccurate = cachedPosition != null &&
          cachedFixTime != null &&
          cachedPosition.accuracy <= 100 &&
          _nowProvider().difference(cachedFixTime) < gpsCacheStaleThreshold;

      Position? position;
      DateTime? acquisitionTime;
      bool usedOsCache = false;

      if (!isUserTriggered && cachedIsFreshAndAccurate) {
        position = cachedPosition;
        acquisitionTime = cachedFixTime;
        usedOsCache = true;
      } else {
        try {
          final livePosition = await _locationProvider.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 15),
          );
          if (isStaleRequest()) return false;
          final liveFixTime = _validatedFixTime(livePosition.timestamp);
          if (!_isValidCoordinate(
                livePosition.latitude,
                livePosition.longitude,
              ) ||
              liveFixTime == null) {
            if (!isStaleRequest()) {
              _setLocationError(
                LocationErrorType.unavailable,
                'تعذر الحصول على إحداثيات أو توقيت صالح من نظام تحديد الموقع',
              );
            }
            return false;
          }
          position = livePosition;
          acquisitionTime = liveFixTime;
          usedOsCache = false;
        } on TimeoutException {
          if (!isUserTriggered &&
              cachedPosition != null &&
              cachedFixTime != null) {
            // Preserve old OS cache with its TRUE old acquisition timestamp (visibly saved/cached, never renewed)
            position = cachedPosition;
            acquisitionTime = cachedFixTime;
            usedOsCache = true;
          } else {
            rethrow;
          }
        } catch (e, stack) {
          AppLogger.warn('PrayerService.determinePosition.getCurrentPosition', e, stack);
          if (!isUserTriggered &&
              cachedPosition != null &&
              cachedFixTime != null) {
            position = cachedPosition;
            acquisitionTime = cachedFixTime;
            usedOsCache = true;
          } else {
            rethrow;
          }
        }
      }

      final Position validPosition = position;
      final DateTime validFixTime = acquisitionTime;
      final bool committed = await _serializeLocationMutation<bool>(() async {
        if (isStaleRequest()) return false;

        final existing = _currentData;
        final existingFixTime = _lastGpsFixTime;
        final int acquisitionUtcMs = validFixTime.toUtc().millisecondsSinceEpoch;

        // Never regress or renew an existing fix with an older or identical timestamp
        if (existing != null &&
            existingFixTime != null &&
            !validFixTime.isAfter(existingFixTime)) {
          _clearLocationError();
          _startPositionStream(startGeneration);
          notifyListeners();
          return true;
        }

        final double distMeters = existing == null
            ? double.infinity
            : _locationProvider.distanceBetween(
                existing.latitude,
                existing.longitude,
                validPosition.latitude,
                validPosition.longitude,
              );

        final resolved =
            _resolveCityMatch(validPosition.latitude, validPosition.longitude);
        final newLocName = resolved.locationName;
        final oldLocName = existing?.locationName ?? '';

        final prefs = await SharedPreferences.getInstance();
        if (isStaleRequest()) return false;

        // If no current verified location yet, moved >= 2.5km, city changed, or user-triggered
        if (existing == null ||
            distMeters >= 2500 ||
            newLocName != oldLocName ||
            isUserTriggered) {
          await _removeLegacyManualKeys(prefs);
          if (isStaleRequest()) return false;
          await prefs.setString(locationSourceKey, locationSourceGps);
          if (isStaleRequest()) return false;
          await prefs.setInt(locationUpdatedAtMsKey, acquisitionUtcMs);
          if (isStaleRequest()) return false;
          await prefs.setDouble('last_latitude', validPosition.latitude);
          if (isStaleRequest()) return false;
          await prefs.setDouble('last_longitude', validPosition.longitude);
          if (isStaleRequest()) return false;
          await prefs.setString('last_city', newLocName);
          if (isStaleRequest()) return false;

          final matchedMethod = resolved.calculationMethod;
          if (matchedMethod != null && matchedMethod != _lastCalculationMethod) {
            _lastCalculationMethod = matchedMethod;
            await SettingsService.instance.setCalculationMethod(matchedMethod);
            if (isStaleRequest()) return false;
          }

          _lastGpsFixTime = validFixTime;
          _isFromLiveFixThisSession = !usedOsCache;
          _clearLocationError();
          _calculatePrayers(
            validPosition.latitude,
            validPosition.longitude,
            newLocName,
          );
          notifyListeners();
        } else {
          // Confirmed still at same verified GPS location with a strictly newer acquisition timestamp
          await prefs.setString(locationSourceKey, locationSourceGps);
          if (isStaleRequest()) return false;
          await prefs.setInt(locationUpdatedAtMsKey, acquisitionUtcMs);
          if (isStaleRequest()) return false;

          final matchedMethod = resolved.calculationMethod;
          if (matchedMethod != null && matchedMethod != _lastCalculationMethod) {
            _lastCalculationMethod = matchedMethod;
            await SettingsService.instance.setCalculationMethod(matchedMethod);
            if (isStaleRequest()) return false;
          }

          _lastGpsFixTime = validFixTime;
          _isFromLiveFixThisSession = !usedOsCache;
          _clearLocationError();
          notifyListeners();
        }

        // Start movement listener for continuous highway/train travel updates
        _startPositionStream(startGeneration);
        return true;
      });
      return committed;
    } on TimeoutException {
      if (!isStaleRequest()) {
        _setLocationError(
          LocationErrorType.timeout,
          'انتهت مهلة تحديد الموقع الجغرافي، يرجى المحاولة مرة أخرى',
        );
      }
      return false;
    } catch (e, stack) {
      AppLogger.warn('PrayerService.determinePosition', e, stack);
      if (!isStaleRequest()) {
        _setLocationError(
          LocationErrorType.unavailable,
          'تعذر تحديد الموقع الجغرافي حالياً، يرجى المحاولة مرة أخرى',
        );
      }
      return false;
    }
  }

  void _startPositionStream(int streamGeneration) {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    if (streamGeneration != _locationRequestGeneration) {
      return;
    }
    try {
      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 1000, // Trigger when moved by 1 km with high GPS accuracy
      );
      _positionStreamSubscription = _locationProvider.getPositionStream(
        locationSettings: locationSettings,
      ).listen((Position position) {
        if (streamGeneration != _locationRequestGeneration) {
          return;
        }
        if (!_isValidCoordinate(position.latitude, position.longitude)) return;
        final validFixTime = _validatedFixTime(position.timestamp);
        if (validFixTime == null) return;

        unawaited(_serializeLocationMutation<void>(() async {
          bool isStaleStreamEvent() =>
              streamGeneration != _locationRequestGeneration;

          if (isStaleStreamEvent()) return;
          final existing = _currentData;
          final existingFixTime = _lastGpsFixTime;
          // Reject old or replayed stream events that are not strictly newer than current fix
          if (existingFixTime != null && !validFixTime.isAfter(existingFixTime)) {
            return;
          }

          final distMeters = existing == null
              ? double.infinity
              : _locationProvider.distanceBetween(
                  existing.latitude,
                  existing.longitude,
                  position.latitude,
                  position.longitude,
                );
          final resolved =
              _resolveCityMatch(position.latitude, position.longitude);
          final newLocName = resolved.locationName;
          final oldLocName = existing?.locationName ?? '';
          final acquisitionUtcMs = validFixTime.toUtc().millisecondsSinceEpoch;

          if (existing == null || distMeters >= 2500 || newLocName != oldLocName) {
            final prefs = await SharedPreferences.getInstance();
            if (isStaleStreamEvent()) return;
            await _removeLegacyManualKeys(prefs);
            if (isStaleStreamEvent()) return;
            await prefs.setString(locationSourceKey, locationSourceGps);
            if (isStaleStreamEvent()) return;
            await prefs.setInt(locationUpdatedAtMsKey, acquisitionUtcMs);
            if (isStaleStreamEvent()) return;
            await prefs.setDouble('last_latitude', position.latitude);
            if (isStaleStreamEvent()) return;
            await prefs.setDouble('last_longitude', position.longitude);
            if (isStaleStreamEvent()) return;
            await prefs.setString('last_city', newLocName);
            if (isStaleStreamEvent()) return;

            final matchedMethod = resolved.calculationMethod;
            if (matchedMethod != null &&
                matchedMethod != _lastCalculationMethod) {
              _lastCalculationMethod = matchedMethod;
              await SettingsService.instance
                  .setCalculationMethod(matchedMethod);
              if (isStaleStreamEvent()) return;
            }

            _lastGpsFixTime = validFixTime;
            _isFromLiveFixThisSession = true;
            _clearLocationError();
            _calculatePrayers(position.latitude, position.longitude, newLocName);
            notifyListeners();
          } else {
            // Strictly newer same-place streamed fix: refresh GPS provenance,
            // true acquisition timestamp, and live freshness without
            // unnecessary prayer recalculation, preserving clear-race safety.
            final prefs = await SharedPreferences.getInstance();
            if (isStaleStreamEvent()) return;
            await prefs.setString(locationSourceKey, locationSourceGps);
            if (isStaleStreamEvent()) return;
            await prefs.setInt(locationUpdatedAtMsKey, acquisitionUtcMs);
            if (isStaleStreamEvent()) return;

            _lastGpsFixTime = validFixTime;
            _isFromLiveFixThisSession = true;
            _clearLocationError();
            notifyListeners();
          }
        }));
      }, onError: (Object err, StackTrace stack) {
        AppLogger.warn('PrayerService.initGeolocatorStream.onError', err, stack);
      });
    } catch (e, stack) {
      AppLogger.warn('PrayerService.initGeolocatorStream', e, stack);
    }
  }

  Future<bool> requestGpsLocation({bool isAutoInit = false}) async {
    final isUserTriggered = !isAutoInit;
    _isLoading = true;
    if (isUserTriggered) {
      _clearLocationError();
    }
    notifyListeners();

    final result = await checkAndUpdateLocationOnResume(
      isUserTriggered: isUserTriggered,
    );
    _isLoading = false;
    notifyListeners();
    return result;
  }

  void _calculatePrayers(double lat, double lng, String locName, {bool updateSchedules = true}) {
    _currentData = PrayerScheduleCalculator.calculate(
      latitude: lat,
      longitude: lng,
      locationName: locName,
      now: _nowProvider(),
      parameters: _getParams(),
    );
    countdownNotifier.value = _currentData!.timeToNextPrayer;
    if (updateSchedules) {
      try {
        PrayerNotificationService.instance.schedulePrayerNotifications(_currentData!);
      } catch (e, stack) {
        AppLogger.warn('PrayerService._calculatePrayers.notifications', e, stack);
      }
      try {
        FajrQiyamAlarmService.instance.syncWithLocationAvailability(_currentData!);
      } catch (e, stack) {
        AppLogger.warn('PrayerService._calculatePrayers.alarm', e, stack);
      }
    }
    notifyListeners();
  }

  String formatCountdown(Duration d) {
    if (d.isNegative) return 'حان الآن';
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  void dispose() {
    _tickerTimer?.cancel();
    _positionStreamSubscription?.cancel();
    SettingsService.instance.removeListener(_onSettingsChanged);
    countdownNotifier.dispose();
    super.dispose();
  }
}
