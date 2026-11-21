import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/core/notifications/notification_destination.dart';

void main() {
  for (final type in ['adhan', 'iqamah', 'prereminder', 'unknown']) {
    test('$type notification never launches independent audio', () {
      final route =
          Uri.parse(notificationDestination('type=$type&prayer=العصر'));
      expect(route.path, '/adhan-control');
      expect(route.queryParameters['prayer'], 'العصر');
      expect(route.queryParameters['autoPlay'], 'false');
      expect(route.queryParameters['notificationKind'],
          type == 'unknown' ? 'reminder' : type);
      expect(route.queryParameters['isIqamah'], '${type == 'iqamah'}');
    });
  }
  test('encoded prayer cannot inject autoplay or route parameters', () {
    final payload =
        Uri(queryParameters: {'type': 'adhan', 'prayer': 'العصر&autoPlay=true'})
            .query;
    final route = Uri.parse(notificationDestination(payload));
    expect(route.queryParameters['prayer'], 'العصر&autoPlay=true');
    expect(route.queryParameters['autoPlay'], 'false');
  });
  test('missing prayer is not falsely labeled Dhuhr', () {
    final route = Uri.parse(notificationDestination('type=adhan'));
    expect(route.queryParameters['prayer'], 'الصلاة');
    expect(route.queryParameters['autoPlay'], 'false');
  });
  test('short reminders retain settings destination', () {
    expect(notificationDestination('type=short_reminder&kind=salawat'),
        '/settings');
  });
  test('adhkar retains category destinations', () {
    expect(notificationDestination('type=adhkar&category=morning'),
        '/adhkar?index=0');
    expect(notificationDestination('type=adhkar&category=evening'),
        '/adhkar?index=1');
    expect(notificationDestination('type=adhkar&category=sleep'),
        '/adhkar?index=3');
    expect(notificationDestination('type=adhkar&category=other'),
        '/adhkar?index=0');
  });
  test('only known prayer IDs are carried to the screen', () {
    for (final id in [100, 399, 995, 998, 999]) {
      expect(
          Uri.parse(notificationDestination('type=adhan&prayer=العصر',
                  notificationId: id))
              .queryParameters['notificationId'],
          '$id');
    }
    for (final id in [-1, 0, 400, 801, 1000]) {
      expect(
          Uri.parse(notificationDestination('type=adhan&prayer=العصر',
                  notificationId: id))
              .queryParameters
              .containsKey('notificationId'),
          false);
    }
  });
}
