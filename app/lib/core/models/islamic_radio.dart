import 'package:flutter/material.dart';

/// تصنيفات الإذاعات الإسلامية
enum IslamicRadioCategoryType {
  all,
  generalLive,
  reciters,
  tafseerFatwa,
  adhkarRoqyah,
  khushooSurahs,
}

/// تصنيف الإذاعة مع الأيقونة والاسم
class IslamicRadioCategory {
  final IslamicRadioCategoryType type;
  final String title;
  final IconData icon;

  const IslamicRadioCategory({
    required this.type,
    required this.title,
    required this.icon,
  });
}

/// نموذج محطة الإذاعة الإسلامية للبث المباشر
class IslamicRadioStation {
  final String id;
  final String name;
  final IslamicRadioCategoryType category;
  final String categoryName;
  final String subtitle;
  final String streamUrl;
  final List<String> fallbackUrls;
  final String countryOrOrigin;
  final Color accentColor;
  final IconData icon;
  final bool isLive;
  final List<String> tags;

  const IslamicRadioStation({
    required this.id,
    required this.name,
    required this.category,
    required this.categoryName,
    required this.subtitle,
    required this.streamUrl,
    this.fallbackUrls = const [],
    required this.countryOrOrigin,
    required this.accentColor,
    required this.icon,
    this.isLive = true,
    this.tags = const [],
  });

  /// جميع الروابط المتاحة للبث مع الترتيب
  List<String> get allStreamUrls => [streamUrl, ...fallbackUrls];
}
