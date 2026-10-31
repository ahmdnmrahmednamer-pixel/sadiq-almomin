import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

void showMemorizationDedicationDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.auto_stories_rounded, color: AppColors.primaryGreen),
          SizedBox(width: 8),
          Text('إرشادات الحفظ والتثبيت'),
        ],
      ),
      content: const Text(
        '«خَيْرُكُمْ مَنْ تَعَلَّمَ القُرْآنَ وَعَلَّمَهُ»\n\n'
        'استعن بالله وكرر الآيات وأعد الاستماع بتأنٍ لتثبيت الحفظ في الصدر.',
        style: TextStyle(height: 1.6),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('إغلاق'),
        ),
      ],
    ),
  );
}
