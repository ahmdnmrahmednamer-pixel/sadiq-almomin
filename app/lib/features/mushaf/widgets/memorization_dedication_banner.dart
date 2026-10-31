import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class MemorizationDedicationBanner extends StatelessWidget {
  const MemorizationDedicationBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primaryGreen.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryGreen.withOpacity(0.2)),
      ),
      child: const Row(
        children: [
          Icon(Icons.auto_stories_rounded, color: AppColors.primaryGreen, size: 22),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'محراب التحفيظ والتثبيت القرآني',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primaryGreen),
                ),
                Text(
                  '«خَيْرُكُمْ مَنْ تَعَلَّمَ القُرْآنَ وَعَلَّمَهُ»',
                  style: TextStyle(fontSize: 11, color: AppColors.mutedText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
