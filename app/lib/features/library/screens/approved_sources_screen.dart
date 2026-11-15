import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/widgets/app_navigation_drawer.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/theme/app_theme.dart';

/// شاشة «المصادر والمراجع القرآنية المعتمدة»
/// مستخرجة ومحققة من المجلد المعتمد: «D:\برمجة\صديق المؤمن\app\مصادر»
class ApprovedSourcesScreen extends StatelessWidget {
  const ApprovedSourcesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Directionality(
      textDirection: SettingsService.instance.textDirection,
      child: Scaffold(
        drawer: const AppNavigationDrawer(),
        appBar: AppBar(
          title: const Text('المصادر والمراجع القرآنية المعتمدة'),
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          children: [
            // 1. Introduction Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [const Color(0xFF163224), const Color(0xFF0F2017)]
                      : [const Color(0xFF0F5A44), const Color(0xFF177A5D)],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.accentGold.withValues(alpha: 0.4), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Row(
                children: [
                  Icon(Icons.auto_stories_rounded, color: AppColors.accentGold, size: 36),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'أمهات المراجع القرآنية الموثقة',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'Amiri',
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'مستخرجة ومدمجة بالكامل من مجلد مصادر لخدمة كتاب الله الكريم',
                          style: TextStyle(
                            color: Color(0xFFFFEFA6),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // 2. Source Card 1: مصحف الصحابة في القراءات العشر المتواترة
            _buildSourceCard(
              context,
              isDark: isDark,
              sourceBadge: 'مرجع القراءات المعتمد (٦٠٩ صفحات)',
              title: 'مصحف الصحابة في القراءات العشر المتواترة من طريق الشاطبية والدرة',
              author: 'إعداد وتحقيق: الشيخ والمهندس جمال الدين محمد شرف',
              description:
                  'المرجع الشامل المحقق لبيان القراءات العشر المتواترة، يجمع بين طريقي الشاطبية (القراءات السبع) والدرة المضية (القراءات الثلاث المتممة للعشر)، مع بيان الرموز وأصول القراءات وفرش الحروف لكافة سور القرآن.',
              icon: Icons.menu_book_rounded,
              iconColor: AppColors.primaryGreen,
              actionLabel: 'تصفح مصحف القراءات العشر 📜',
              onTapAction: () => context.push('/qiraat'),
            ),
            const SizedBox(height: 14),

            // 3. Source Card 2: المختصر الصوتي في تفسير القرآن الكريم
            _buildSourceCard(
              context,
              isDark: isDark,
              sourceBadge: 'الموسوعة الصوتية الكاملة (مركز تفسير)',
              title: 'المختصر في تفسير القرآن الكريم صوتياً',
              author: 'مركز تفسير للدراسات القرآنية • أصوات: الأسمري، الغامدي، الشايع',
              description:
                  'مشروع صوتي مبارك لتفسير سور القرآن الـ ١١٤ كاملاً بصوت ثلاثة من كبار المشايخ المتقنين، مع الروابط المباشرة لـ ٥ منصات عالمية (YouTube, Apple Podcasts, SoundCloud, Podbean, Telegram).',
              icon: Icons.record_voice_over_rounded,
              iconColor: Colors.deepPurpleAccent,
              actionLabel: 'الاستماع للمختصر الصوتي 🎧',
              onTapAction: () => context.push('/audio-tafsir'),
            ),
            const SizedBox(height: 14),

            // 4. Source Card 3: تفسير القرآن الكريم وإعرابه وبيانه
            _buildSourceCard(
              context,
              isDark: isDark,
              sourceBadge: 'موسوعة الإعراب واللغة (٧٠٦ صفحات)',
              title: 'تفسير القرآن الكريم وإعرابه وبيانه',
              author: 'تأليف: العلامة الشيخ محمد علي طه الدرة',
              description:
                  'من أجلّ وأدق كتب التفسير اللغوي وإعراب القرآن في العصر الحديث، يقدم الإعراب النحوي التفصيلي لكل كلمة وآية، مع بيان وجوه البلاغة، الفروق اللغوية، وتوجيه المعاني عند أئمة النحو والتفسير.',
              icon: Icons.format_shapes_rounded,
              iconColor: Colors.teal,
              actionLabel: 'فتح إعراب وبيان القرآن الكريم 📐',
              onTapAction: () => context.push('/quran-irab'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceCard(
    BuildContext context, {
    required bool isDark,
    required String sourceBadge,
    required String title,
    required String author,
    required String description,
    required IconData icon,
    required Color iconColor,
    required String actionLabel,
    required VoidCallback onTapAction,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.25)),
                    ),
                    child: Text(
                      sourceBadge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(icon, color: iconColor, size: 24),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'Amiri',
                fontSize: 16.5,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              author,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.accentGold,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
                onPressed: onTapAction,
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: Text(
                  actionLabel,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
