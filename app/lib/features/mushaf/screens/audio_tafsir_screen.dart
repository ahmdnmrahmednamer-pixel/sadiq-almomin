import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../app/widgets/app_navigation_drawer.dart';
import '../../../core/services/audio_tafsir_service.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/theme/app_theme.dart';

/// شاشة «المختصر في تفسير القرآن الكريم صوتياً»
/// مستخرجة من المرجع المعتمد: «ملف_تفسير_القران_الكريم_صوتيا_pdf.pdf»
class AudioTafsirScreen extends StatefulWidget {
  const AudioTafsirScreen({super.key});

  @override
  State<AudioTafsirScreen> createState() => _AudioTafsirScreenState();
}

class _AudioTafsirScreenState extends State<AudioTafsirScreen> {
  int _selectedScholarIndex = 0;

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح الرابط الخارجي تلقائياً')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى التحقق من توفر تطبيق مناسب لفتح الرابط')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const scholars = AudioTafsirService.scholars;
    final activeScholar = scholars[_selectedScholarIndex];

    return Directionality(
      textDirection: SettingsService.instance.textDirection,
      child: Scaffold(
        drawer: const AppNavigationDrawer(),
        appBar: AppBar(
          title: const Text('المختصر الصوتي في التفسير'),
          actions: [
            IconButton(
              icon: const Icon(Icons.send_rounded),
              tooltip: 'قناة التيليجرام العامة للمشروع',
              onPressed: () => _launchUrl(AudioTafsirService.generalTelegramUrl),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          children: [
            // 1. Header Banner
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.accentGold.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.record_voice_over_rounded, color: AppColors.accentGold, size: 28),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AudioTafsirService.projectTitle,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16.5,
                                fontWeight: FontWeight.w900,
                                fontFamily: 'Amiri',
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'إصدار: ${AudioTafsirService.issuingBody}',
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
                  const SizedBox(height: 10),
                  const Text(
                    AudioTafsirService.projectDescription,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12.5,
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // 2. Scholar Selector Tabs
            const Text(
              'اختر الشيخ المفسر 🎙️',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              children: List.generate(scholars.length, (index) {
                final s = scholars[index];
                final isSelected = index == _selectedScholarIndex;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: index < scholars.length - 1 ? 8 : 0),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        setState(() {
                          _selectedScholarIndex = index;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primaryGreen
                              : (isDark ? const Color(0xFF16251C) : Colors.white),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.accentGold
                                : (isDark ? Colors.white12 : Colors.grey.shade300),
                            width: isSelected ? 1.5 : 1,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: AppColors.primaryGreen.withValues(alpha: 0.3),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.person_rounded,
                              size: 22,
                              color: isSelected ? AppColors.accentGold : AppColors.primaryGreen,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              s.name.replaceAll('الشيخ ', ''),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: isSelected ? Colors.white : (isDark ? Colors.white : Colors.black87),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 18),

            // 3. Active Scholar Info Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: AppColors.primaryGreen.withValues(alpha: 0.15),
                          child: const Icon(Icons.menu_book_rounded, color: AppColors.primaryGreen, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                activeScholar.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'تفسير سور القرآن الـ ١١٤ كاملاً',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.accentGold,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      activeScholar.description,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),

            // 4. Platform Listening Links (Extracted from PDF)
            const Text(
              'روابط الاستماع والتحميل المعتمدة (٥ منصات) 🎧',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            _buildPlatformTile(
              context,
              platform: AudioTafsirPlatform.youtube,
              url: activeScholar.youtubePlaylistUrl,
              icon: Icons.smart_display_rounded,
              iconColor: Colors.redAccent,
              badgeText: 'قائمة تشغيل كاملة',
            ),
            _buildPlatformTile(
              context,
              platform: AudioTafsirPlatform.applePodcasts,
              url: activeScholar.applePodcastsUrl,
              icon: Icons.podcasts_rounded,
              iconColor: Colors.deepPurpleAccent,
              badgeText: 'Apple Podcasts',
            ),
            _buildPlatformTile(
              context,
              platform: AudioTafsirPlatform.soundCloud,
              url: activeScholar.soundCloudUrl,
              icon: Icons.cloud_done_rounded,
              iconColor: Colors.orange,
              badgeText: 'SoundCloud HQ',
            ),
            _buildPlatformTile(
              context,
              platform: AudioTafsirPlatform.podbean,
              url: activeScholar.podbeanUrl,
              icon: Icons.radio_rounded,
              iconColor: Colors.teal,
              badgeText: 'Podbean Web & App',
            ),
            if (activeScholar.telegramUrl != null)
              _buildPlatformTile(
                context,
                platform: AudioTafsirPlatform.telegram,
                url: activeScholar.telegramUrl!,
                icon: Icons.telegram_rounded,
                iconColor: Colors.lightBlue,
                badgeText: 'قناة التيليجرام الموثقة',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlatformTile(
    BuildContext context, {
    required AudioTafsirPlatform platform,
    required String url,
    required IconData icon,
    required Color iconColor,
    required String badgeText,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _launchUrl(url),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        platform.title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        platform.subtitle,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? Colors.white60 : AppColors.mutedText,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        badgeText,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryGreen,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.open_in_new_rounded, size: 13, color: AppColors.primaryGreen),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
