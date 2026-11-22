import 'package:flutter/material.dart';
import '../../core/models/prophet_story.dart';
import '../../core/services/audio_download_service.dart';
import '../../core/services/islamic_audio_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/stories_service.dart';
import '../../core/theme/app_theme.dart';
import '../stories/widgets/prophet_story_player_sheet.dart';
import '../stories/stories_screen.dart';
import 'widgets/islamic_audio_player_sheet.dart';
import 'audio_screen.dart';

enum DownloadFilterType {
  all,
  quran,
  stories,
  adhkar,
}

/// Unified Offline Downloads Hub (مركز التنزيلات والاستماع دون إنترنت)
/// Combines Quran Surah downloads, Prophet Audio Story downloads, and Bundled Adhkar.
class DownloadsManagerScreen extends StatefulWidget {
  const DownloadsManagerScreen({super.key});

  @override
  State<DownloadsManagerScreen> createState() => _DownloadsManagerScreenState();
}

class _DownloadsManagerScreenState extends State<DownloadsManagerScreen> {
  DownloadFilterType _activeFilter = DownloadFilterType.all;

  @override
  void initState() {
    super.initState();
    AudioDownloadService.instance.init();
    StoriesService.instance.init();
    IslamicAudioService.instance.init();
  }

  Future<void> _confirmDeleteAdhkar(IslamicAudioTrack track) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: SettingsService.instance.textDirection,
        child: AlertDialog(
          title: const Text('حذف الذكر المحمل'),
          content: Text(
            'هل تريد حذف ملف "${track.title}" من ذاكرة الهاتف للرجوع إلى البث عبر الإنترنت؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      final deleted = await IslamicAudioService.instance.deleteDownloadedTrack(track.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(deleted ? 'تم حذف ${track.title} بنجاح' : 'تعذر حذف الملف. حاول مرة أخرى.', textAlign: TextAlign.right),
          backgroundColor: deleted ? AppColors.primaryGreen : Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _confirmDeleteSurah(DownloadedSurahInfo info) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: SettingsService.instance.textDirection,
        child: AlertDialog(
          title: const Text('تأكيد حذف التنزيل'),
          content: Text(
            'هل ترغب في حذف ملف تلاوة ${info.surahName} بصوت ${info.reciterName} من ذاكرة الهاتف لتوفير ${info.formattedSize}؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      final deleted = await AudioDownloadService.instance.deleteDownloadedSurah(
        info.reciterId,
        info.surahId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(deleted ? 'تم حذف ${info.surahName} وتحرير المساحة بنجاح' : 'تعذر حذف الملف. حاول مرة أخرى.', textAlign: TextAlign.right),
          backgroundColor: deleted ? AppColors.primaryGreen : Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _confirmDeleteStory(ProphetAudioStory story) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: SettingsService.instance.textDirection,
        child: AlertDialog(
          title: const Text('حذف القصة المحملة'),
          content: Text(
            'هل تريد حذف ملف ${story.title} لتوفير ${story.formattedSize}؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      final deleted = await StoriesService.instance.deleteDownloadedStory(story.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(deleted ? 'تم حذف ${story.characterName} بنجاح' : 'تعذر حذف الملف. حاول مرة أخرى.', textAlign: TextAlign.right),
          backgroundColor: deleted ? AppColors.primaryGreen : Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _confirmDeleteAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: SettingsService.instance.textDirection,
        child: AlertDialog(
          title: const Text('حذف جميع الملفات الصوتية المحملة'),
          content: Text(
            'هل أنت متأكد من حذف كافة السور والقصص والأذكار${IslamicAudioService.instance.retiredRecordingCount > 0 ? ' وملفات التسجيل القديمة' : ''}${IslamicAudioService.instance.unavailableRecordingCount > 0 ? ' وملفات التسجيل غير المتاحة للتشغيل' : ''} المحملة وتحرير كامل المساحة على الهاتف؟\n${IslamicAudioService.instance.unavailableRecordingCount > 0 ? '(قد لا تتمكن من استعادة ملفات التسجيل غير المتاحة${IslamicAudioService.instance.retiredRecordingCount > 0 ? ' أو القديمة' : ''} بعد حذفها.)' : IslamicAudioService.instance.retiredRecordingCount > 0 ? '(قد لا تتمكن من استعادة ملفات التسجيل القديمة بعد حذفها.)' : '(يمكنك إعادة تحميلها أو الاستماع إليها مباشرة عبر الإنترنت في أي وقت).'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text('نعم، حذف الكل'),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      final quranDeleted = await AudioDownloadService.instance.deleteAllDownloads();
      final storiesDeleted = await StoriesService.instance.deleteAllDownloadedStories();
      final adhkarDeleted = await IslamicAudioService.instance.deleteAllDownloadedTracks();
      final deleted = quranDeleted && storiesDeleted && adhkarDeleted;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(deleted ? 'تم حذف جميع التنزيلات بنجاح' : 'تعذر حذف بعض الملفات. حاول مرة أخرى.', textAlign: TextAlign.right),
          backgroundColor: deleted ? AppColors.primaryGreen : Colors.redAccent,
        ),
      );
    }
  }

  String _formatTotalBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = bytes / (1024 * 1024);
    if (mb < 0.1) {
      final kb = bytes / 1024;
      return '${kb.toStringAsFixed(1)} KB';
    }
    if (mb >= 1024) {
      final gb = mb / 1024;
      return '${gb.toStringAsFixed(2)} GB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: SettingsService.instance.textDirection,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: MediaQuery.textScalerOf(context).scale(20) * 4 + 16,
          title: const Text('مركز التنزيلات والاستماع دون إنترنت', softWrap: true, maxLines: 4, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          centerTitle: true,
        ),
        body: AnimatedBuilder(
          animation: Listenable.merge([
            AudioDownloadService.instance,
            StoriesService.instance,
            IslamicAudioService.instance,
          ]),
          builder: (context, _) {
            final quranDownloads = AudioDownloadService.instance.getDownloadedSurahsList();
            final storyDownloads = StoriesService.instance.getDownloadedStories();
            final adhkarDownloads = IslamicAudioService.instance.getDownloadedTracks();

            final totalQuranBytes = AudioDownloadService.instance.totalStorageUsedBytes;
            final totalStoryBytes = StoriesService.instance.totalDownloadedStoriesBytes;
            final totalAdhkarBytes = IslamicAudioService.instance.totalDownloadedBytes;
            final combinedBytes = totalQuranBytes + totalStoryBytes + totalAdhkarBytes;
            final formattedCombined = _formatTotalBytes(combinedBytes);
            final retiredRecordingCount = IslamicAudioService.instance.retiredRecordingCount;
            final unavailableRecordingCount = IslamicAudioService.instance.unavailableRecordingCount;
            final totalCustomDownloadedCount =
                quranDownloads.length + storyDownloads.length + adhkarDownloads.length + retiredRecordingCount + unavailableRecordingCount;

            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              children: [
                // Dedication Banner
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4AF37).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.download_done_rounded, color: Color(0xFFD4AF37), size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'مكتبة التلاوات المحملة — استمع في أي وقت وأي مكان بدون إنترنت',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFB8860B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Overall Storage Card
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.spaceBetween,
                          children: [
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryGreen.withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.sd_storage_rounded,
                                      color: AppColors.primaryGreen, size: 22),
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  'المساحة المستهلكة على الهاتف',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            Text(
                              formattedCombined,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Theme.of(context).colorScheme.onSurface : AppColors.primaryGreen,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.spaceBetween,
                          children: [
                            Text(
                              'إجمالي المحمل: $totalCustomDownloadedCount ملفات (${quranDownloads.length} سور • ${storyDownloads.length} قصص • ${adhkarDownloads.length} أذكار)${retiredRecordingCount > 0 ? ' • $retiredRecordingCount ملفات تسجيل قديمة' : ''}${unavailableRecordingCount > 0 ? ' • $unavailableRecordingCount ملفات تسجيل غير متاحة للتشغيل' : ''}',
                              style: TextStyle(fontSize: 12.5, color: isDark ? Colors.white60 : Colors.grey.shade700),
                            ),
                            if (totalCustomDownloadedCount > 0)
                              TextButton.icon(
                                icon: const Icon(Icons.delete_sweep_rounded, size: 18, color: Colors.redAccent),
                                label: const Text('حذف الكل', style: TextStyle(color: Colors.redAccent, fontSize: 12.5)),
                                onPressed: _confirmDeleteAll,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Category Tabs Filter
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: Text('الكل ($totalCustomDownloadedCount)'),
                        selected: _activeFilter == DownloadFilterType.all,
                        onSelected: (_) => setState(() => _activeFilter = DownloadFilterType.all),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: Text('تلاوات القرآن (${quranDownloads.length})'),
                        selected: _activeFilter == DownloadFilterType.quran,
                        onSelected: (_) => setState(() => _activeFilter = DownloadFilterType.quran),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: Text('قصص الأنبياء (${storyDownloads.length})'),
                        selected: _activeFilter == DownloadFilterType.stories,
                        onSelected: (_) => setState(() => _activeFilter = DownloadFilterType.stories),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: Text('الأذكار والأدعية (${adhkarDownloads.length})'),
                        selected: _activeFilter == DownloadFilterType.adhkar,
                        onSelected: (_) => setState(() => _activeFilter = DownloadFilterType.adhkar),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                if (retiredRecordingCount > 0) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'ملفات تسجيل قديمة محفوظة: $retiredRecordingCount. لا تُشغّل من هنا. يمكنك حذفها باستخدام «حذف الكل» أعلاه، ثم إعادة المحاولة إذا تعذر الحذف.',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                if (unavailableRecordingCount > 0) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'ملفات تسجيل غير متاحة للتشغيل محفوظة: $unavailableRecordingCount. يظل تشغيلها محجوبا حتى مراجعة الاسم والمصدر. يمكنك حذفها باستخدام "حذف الكل" أعلاه، ثم إعادة المحاولة إذا تعذر الحذف.',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                // CONTENT LIST
                if (totalCustomDownloadedCount == 0) ...[
                  _buildEmptyState(context, isDark),
                ] else ...[
                  // 1. Stories downloads
                  if (_activeFilter == DownloadFilterType.all || _activeFilter == DownloadFilterType.stories) ...[
                    if (storyDownloads.isNotEmpty) ...[
                      _buildSectionHeader('قصص الأنبياء الصوتية المحملة (${storyDownloads.length})'),
                      const SizedBox(height: 8),
                      ...storyDownloads.map((s) => _buildStoryDownloadCard(context, s, isDark)),
                      const SizedBox(height: 14),
                    ],
                  ],
                  // 2. Quran downloads
                  if (_activeFilter == DownloadFilterType.all || _activeFilter == DownloadFilterType.quran) ...[
                    if (quranDownloads.isNotEmpty) ...[
                      _buildSectionHeader('تلاوات سور القرآن المحملة (${quranDownloads.length})'),
                      const SizedBox(height: 8),
                      ...quranDownloads.map((q) => _buildQuranDownloadCard(context, q, isDark)),
                      const SizedBox(height: 14),
                    ],
                  ],
                  // 3. Adhkar downloads
                  if (_activeFilter == DownloadFilterType.all || _activeFilter == DownloadFilterType.adhkar) ...[
                    if (adhkarDownloads.isNotEmpty) ...[
                      _buildSectionHeader('الأذكار والأدعية المحملة (${adhkarDownloads.length})'),
                      const SizedBox(height: 8),
                      ...adhkarDownloads.map((track) => _buildAdhkarTrackCard(context, track, isDark)),
                      const SizedBox(height: 14),
                    ],
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14,
        color: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).colorScheme.onSurface : AppColors.primaryGreen),
    );
  }

  Widget _buildStoryDownloadCard(BuildContext context, ProphetAudioStory story, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: Colors.green.withValues(alpha: 0.15),
            child: const Icon(Icons.record_voice_over_rounded, color: Colors.green, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  story.title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'صوت: ${story.narrator} • ${story.duration} • ${story.formattedSize}',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.mutedText),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.play_circle_fill_rounded, color: AppColors.primaryGreen, size: 30),
            tooltip: 'تشغيل القصة الآن أوفلاين',
            onPressed: () => ProphetStoryPlayerSheet.show(context, story),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
            tooltip: 'حذف التنزيل',
            onPressed: () => _confirmDeleteStory(story),
          ),
        ],
      ),
    );
  }

  Widget _buildQuranDownloadCard(BuildContext context, DownloadedSurahInfo info, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primaryGreen.withValues(alpha: 0.12),
            child: Text(
              '${info.surahId}',
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryGreen, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.surahName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
                const SizedBox(height: 2),
                Text(
                  'بصوت: ${info.reciterName} • الحجم: ${info.formattedSize}',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.mutedText),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.headphones_rounded, color: AppColors.primaryGreen, size: 24),
            tooltip: 'فتح في المشغل الصوتي',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AudioScreen()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
            tooltip: 'حذف التنزيل',
            onPressed: () => _confirmDeleteSurah(info),
          ),
        ],
      ),
    );
  }

  Widget _buildAdhkarTrackCard(BuildContext context, IslamicAudioTrack track, bool isDark) {
    if (track.type == IslamicAudioType.adhkar) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.accentGold.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('اسم قديم في الفهرس، غير موثّق: ${track.title}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
            const SizedBox(height: 8),
            Text('ملف محفوظ لم تُراجع مطابقته للاسم. لا يُشغّل من هنا.',
                style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white70 : AppColors.mutedText)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.library_music_rounded),
              label: const Text('فتح الأذكار المسموعة'),
              onPressed: () => IslamicAudioPlayerSheet.show(context, filter: IslamicAudioType.adhkar),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
                tooltip: 'حذف التنزيل',
                onPressed: () => _confirmDeleteAdhkar(track),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accentGold.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.accentGold.withValues(alpha: 0.15),
            child: const Icon(Icons.auto_awesome, color: Color(0xFFB8860B), size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
                const SizedBox(height: 2),
                Text(
                  '${track.subtitle} • ${track.durationFormatted} • محمل أوفلاين ⚡',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.mutedText),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.play_circle_fill_rounded, color: AppColors.primaryGreen, size: 30),
            tooltip: 'استماع للذكر أوفلاين',
            onPressed: () => IslamicAudioPlayerSheet.show(context, filter: track.type),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
            tooltip: 'حذف التنزيل',
            onPressed: () => _confirmDeleteAdhkar(track),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(28),
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.cloud_download_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 14),
          const Text(
            'لا توجد تنزيلات حالياً على الهاتف',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'يمكنك تنزيل سور القرآن وقصص الأنبياء بنقرة واحدة لتستمع إليها في السفر وبدون إنترنت.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.mutedText, height: 1.5),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.headphones_rounded, size: 17),
                label: const Text('تصفح القرآن والصوتيات'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AudioScreen())),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.auto_stories_rounded, size: 17),
                label: const Text('تصفح قصص الأنبياء'),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StoriesScreen())),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
