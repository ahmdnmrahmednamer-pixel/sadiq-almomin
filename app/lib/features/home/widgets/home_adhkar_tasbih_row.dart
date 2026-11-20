import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router.dart';
import '../../../core/theme/app_theme.dart';
import '../../adhkar/adhkar_screen.dart';
import '../../adhkar/tasbih_screen.dart';

class HomeAdhkarTasbihRow extends StatelessWidget {
  const HomeAdhkarTasbihRow({super.key});

  void _openAdhkar(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.push('/adhkar?index=0');
    } else {
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (context) => const IsolatedFeatureRouteHost(
            child: AdhkarScreen(),
          ),
        ),
      );
    }
  }

  void _openTasbih(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.push('/tasbih');
    } else {
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (context) => const IsolatedFeatureRouteHost(
            child: TasbihScreen(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    void handleAdhkarTap() => _openAdhkar(context);
    void handleTasbihTap() => _openTasbih(context);

    final adhkarCard = Semantics(
      button: true,
      excludeSemantics: true,
      label: 'حصن المسلم، الأذكار والأدعية',
      onTap: handleAdhkarTap,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: InkWell(
          key: const ValueKey('home_adhkar_card'),
          borderRadius: BorderRadius.circular(18),
          onTap: handleAdhkarTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primaryGreen.withValues(alpha: 0.16),
                        AppColors.emeraldLight.withValues(alpha: 0.12),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.2)),
                  ),
                  child: const Icon(Icons.menu_book_rounded, color: AppColors.primaryGreen, size: 26),
                ),
                const SizedBox(height: 8),
                const Text(
                  'حصن المسلم',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5),
                ),
                const SizedBox(height: 3),
                const Text(
                  'الأذكار والأدعية',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.mutedText),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final tasbihCard = Semantics(
      button: true,
      excludeSemantics: true,
      label: 'السبحة، عداد الورد والتسبيح',
      onTap: handleTasbihTap,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: InkWell(
          key: const ValueKey('home_tasbih_card'),
          borderRadius: BorderRadius.circular(18),
          onTap: handleTasbihTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFD4AF37), Color(0xFFB89628)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accentGold.withValues(alpha: 0.35),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.fingerprint_rounded, color: Colors.white, size: 26),
                ),
                const SizedBox(height: 8),
                const Text(
                  'السبحة',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5),
                ),
                const SizedBox(height: 3),
                const Text(
                  'عداد الورد والتسبيح',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.mutedText),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14.0;
        if (constraints.maxWidth < 340 && textScale >= 1.6) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              adhkarCard,
              const SizedBox(height: 10),
              tasbihCard,
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: adhkarCard),
              const SizedBox(width: 10),
              Expanded(child: tasbihCard),
            ],
          ),
        );
      },
    );
  }
}
