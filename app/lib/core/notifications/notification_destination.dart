/// Notification-owned sound must not start another independent audio player.
/// Manual playback routes remain separate and may explicitly opt into audio.
String notificationDestination(String payload, {int? notificationId}) {
  final uri = Uri.parse('app://notification?$payload');
  final type = uri.queryParameters['type'];
  if (type == 'short_reminder') return '/settings';
  if (type == 'adhkar') {
    final index = switch (uri.queryParameters['category']) {
      'evening' => 1,
      'sleep' => 3,
      _ => 0,
    };
    return '/adhkar?index=$index';
  }
  final prayer = uri.queryParameters['prayer'];
  return Uri(path: '/adhan-control', queryParameters: {
    'prayer': prayer == null || prayer.trim().isEmpty ? 'الصلاة' : prayer,
    'isIqamah': '${type == 'iqamah'}',
    'autoPlay': 'false',
    'notificationKind':
        ['adhan', 'iqamah', 'prereminder'].contains(type) ? type! : 'reminder',
    if (notificationId != null &&
        ((notificationId >= 100 && notificationId <= 399) ||
            [995, 998, 999].contains(notificationId)))
      'notificationId': '$notificationId',
  }).toString();
}
