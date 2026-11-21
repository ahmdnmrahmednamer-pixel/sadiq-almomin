import 'package:flutter/material.dart';
import '../notifications/prayer_notification_service.dart';
import '../services/adhan_sensor_gesture_service.dart';

class NotificationPreferenceError extends StatelessWidget {
  const NotificationPreferenceError({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([
          PrayerNotificationService.instance,
          AdhanSensorGestureService.instance
        ]),
        builder: (context, _) {
          final errors = [
            PrayerNotificationService.instance.preferenceError,
            AdhanSensorGestureService.instance.preferenceError
          ].whereType<String>();
          final error = errors.isEmpty ? null : errors.join('\n');
          if (error == null) return const SizedBox.shrink();
          final colors = Theme.of(context).colorScheme;
          return Semantics(
            liveRegion: true,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: colors.errorContainer,
                  borderRadius: BorderRadius.circular(12)),
              child:
                  Text(error, style: TextStyle(color: colors.onErrorContainer)),
            ),
          );
        },
      );
}
