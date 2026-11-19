import 'package:flutter/material.dart';
import '../../settings/widgets/settings_adhan_voice_modal.dart';

/// Prayer overview. Selection, online listening and download live in one picker.
class PrayerMuezzinSelectorCard extends StatelessWidget {
  final bool isDark;
  const PrayerMuezzinSelectorCard({super.key, required this.isDark});
  @override
  Widget build(BuildContext context) => const Card(
        child: Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('اختيار مؤذن لكل صلاة',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                PrayerVoiceList(),
              ],
            )),
      );
}
