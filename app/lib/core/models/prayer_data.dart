class PrayerInfo {
  final String name;
  final DateTime time;
  final String formattedTime;
  final bool isNext;

  const PrayerInfo({
    required this.name,
    required this.time,
    required this.formattedTime,
    this.isNext = false,
  });
}

class PrayerData {
  final double latitude;
  final double longitude;
  final String locationName;
  final List<PrayerInfo> prayers;

  /// Independently calculated calendar days for a finite OS alarm horizon.
  /// Null keeps explicit single-day callers unchanged.
  final List<PrayerInfo>? notificationPrayers;

  /// Yesterday's independently calculated sunset for the first horizon night.
  /// Not an extra notification and not a repeated wall-clock approximation.
  final DateTime? previousMaghribTime;
  final PrayerInfo? nextPrayer;
  final Duration timeToNextPrayer;
  final double qiblaDegrees;
  final DateTime lastUpdated;

  const PrayerData({
    required this.latitude,
    required this.longitude,
    required this.locationName,
    required this.prayers,
    this.notificationPrayers,
    this.previousMaghribTime,
    this.nextPrayer,
    this.timeToNextPrayer = Duration.zero,
    required this.qiblaDegrees,
    required this.lastUpdated,
  });
}
