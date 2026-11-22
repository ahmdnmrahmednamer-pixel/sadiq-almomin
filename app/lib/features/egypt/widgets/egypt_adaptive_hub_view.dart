import 'package:flutter/material.dart';
import '../../../core/services/egyptian_heritage_service.dart';
import '../../../core/ui/adaptive_screen_layouts.dart';

/// عارض مهيكلي متكيف لأقسام التراث المصري الثلاثة (يتيح التبديل بين التبويبات، الشبكة، المجلة، والقائمة المدمجة)
class EgyptAdaptiveHubView extends StatelessWidget {
  final ScreenStructureMode mode;
  final ValueChanged<int> onSelectTab;

  const EgyptAdaptiveHubView({
    super.key,
    required this.mode,
    required this.onSelectTab,
  });

  @override
  Widget build(BuildContext context) {
    final service = EgyptianHeritageService.instance;
    final items = [
      StructuredScreenItem(
        id: 'eg_hub_ibtihalat',
        title: 'مدرسة الابتهالات وخواطر الشيخ الشعراوي',
        subtitle:
            '${service.ibtihalat.length} ابتهالات، ${service.shaarawiReflections.length} تسجيلات للشعراوي',
        badgeText: 'صوتيات وكلمات',
        category: 'التراث الروحي',
        icon: Icons.music_note_rounded,
        accentColor: const Color(0xFFB88917),
        onTap: () => onSelectTab(0),
      ),
      StructuredScreenItem(
        id: 'eg_hub_mosques',
        title: 'دليل مساجد مصر التاريخية ومآذن المحروسة',
        subtitle: '${service.historicMosques.length} مساجد',
        badgeText: '١٠ مساجد',
        category: 'المعالم الإسلامية',
        icon: Icons.mosque_rounded,
        accentColor: const Color(0xFF0D5C46),
        onTap: () => onSelectTab(1),
      ),
      StructuredScreenItem(
        id: 'eg_hub_fatwas',
        title: 'موسوعة فتاوى دار الإفتاء المصرية والأزهر',
        subtitle: '${service.darAlIftaRulings.length} موضوعات',
        badgeText: 'دار الإفتاء',
        category: 'الفتاوى المعتمدة',
        icon: Icons.gavel_rounded,
        accentColor: const Color(0xFF1F6E58),
        onTap: () => onSelectTab(2),
      ),
    ];

    return AdaptiveStructuredCollectionView(
      mode: mode,
      items: items,
    );
  }
}
