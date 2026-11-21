import 'package:flutter/material.dart';
import '../notifications/prayer_notification_service.dart';

class NotificationPreferenceError extends StatelessWidget {
  const NotificationPreferenceError({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: PrayerNotificationService.instance,
        builder: (context, _) {
          final error = PrayerNotificationService.instance.preferenceError;
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
