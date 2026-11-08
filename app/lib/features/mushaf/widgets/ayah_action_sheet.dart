import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/surah.dart';
import '../../../core/models/ayah.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/services/ayah_notes_service.dart';
import '../../../core/audio/ayah_audio_player.dart';
import 'tafsir_viewer_sheet.dart';
import 'ayah_note_edit_dialog.dart';
import 'ayah_linguistics_sheet.dart';
import 'ayah_card_share_sheet.dart';
import '../memorization_screen.dart';
import '../comparative_tafsir_screen.dart';
import '../tadabbur_journal_screen.dart';
import '../screens/audio_tafsir_screen.dart';
import '../screens/qiraat_mushaf_screen.dart';
import '../screens/quran_irab_screen.dart';
import '../../settings/widgets/settings_reciter_modal.dart';

class AyahActionSheet extends StatefulWidget {
  final Surah surah;
  final Ayah ayah;

  const AyahActionSheet({
    super.key,
    required this.surah,
    required this.ayah,
  });

  static void show(BuildContext context, {required Surah surah, required Ayah ayah}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AyahActionSheet(surah: surah, ayah: ayah),
    );
  }

  @override
  State<AyahActionSheet> createState() => _AyahActionSheetState();
}

class _AyahActionSheetState extends State<AyahActionSheet> {
  void _copyAyah() {
    final textToCopy = '${widget.ayah.cleanTextUthmani} ﴿${widget.ayah.ayahNumber}﴾ [سورة ${widget.surah.nameAr}]';
    Clipboard.setData(ClipboardData(text: textToCopy)).catchError((_) {});
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ الآية الكريمة بنجاح')),
    );
  }

  void _shareAyah() {
    Navigator.pop(context);
    final textToShare = '${widget.ayah.cleanTextUthmani} ﴿${widget.ayah.ayahNumber}﴾\n[سورة ${widget.surah.nameAr}]\n\n— تطبيق نور المؤمن (بدون إنترنت وبدون إعلانات)';
    try {
      Share.share(textToShare);
    } catch (_) {}
  }

  void _showTafseer() {
    Navigator.pop(context);
    TafsirViewerSheet.show(context, surah: widget.surah, ayah: widget.ayah);
  }

  void _showComparativeTafsir() {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ComparativeTafsirScreen(
          initialSurahId: widget.surah.id,
          initialAyahNumber: widget.ayah.ayahNumber,
        ),
      ),
    );
  }

  void _showLinguistics({int initialTab = 0}) {
    Navigator.pop(context);
    AyahLinguisticsSheet.show(
      context,
      surah: widget.surah,
      ayah: widget.ayah,
      initialTabIndex: initialTab,
    );
  }

  void _showDetailedIrab() {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuranIrabScreen(
          initialSurahId: widget.surah.id,
          initialAyah: widget.ayah.ayahNumber,
        ),
      ),
    );
  }

  void _showQiraat() {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const QiraatMushafScreen(),
      ),
    );
  }

  void _showAudioTafsir() {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AudioTafsirScreen(),
      ),
    );
  }

  void _showMemorization() {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MemorizationScreen(
          initialSurahId: widget.surah.id,
          initialFromAyah: widget.ayah.ayahNumber,
          initialToAyah: (widget.ayah.ayahNumber + 2).clamp(1, widget.surah.ayahCount),
        ),
      ),
    );
  }

  void _showTadabburNote() {
    Navigator.pop(context);
    AyahNoteEditDialog.show(context, surah: widget.surah, ayah: widget.ayah);
  }

  void _showTadabburJournal() {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const TadabburJournalScreen(),
      ),
    );
  }

  void _showCardShare() {
    Navigator.pop(context);
    AyahCardShareSheet.show(context, surah: widget.surah, ayah: widget.ayah);
  }

  void _showReciterSelector() {
    showSettingsReciterModal(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isBookmarked = SettingsService.instance.isBookmarked(widget.surah.id, widget.ayah.ayahNumber);
    final hasNote = AyahNotesService.instance.hasNote(widget.surah.id, widget.ayah.ayahNumber);
    final currentReciter = SettingsService.instance.currentReciter;
    final ayahKey = '${widget.surah.id}:${widget.ayah.ayahNumber}';

    return Directionality(
      textDirection: SettingsService.instance.textDirection,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag Handle
            Center(
              child: Container(
                width: 44,
                height: 4.5,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),

            // Top Header: Surah, Ayah Number & Quick Icons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'سورة ${widget.surah.nameAr} — آية ${widget.ayah.ayahNumber}',
                          style: const TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryGreen,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'صفحة ${widget.ayah.page} · جزء ${widget.ayah.juz} · حزب ${widget.ayah.hizb}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.mutedText,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Quick Action Icons in Header
                  IconButton(
                    iconSize: 22,
                    tooltip: isBookmarked ? 'إزالة من المفضلة' : 'حفظ في المفضلة',
                    icon: Icon(
                      isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                      color: isBookmarked ? AppColors.accentGold : AppColors.primaryGreen,
                    ),
                    onPressed: () async {
                      final added = await SettingsService.instance.toggleBookmark(widget.surah.id, widget.ayah.ayahNumber);
                      setState(() {});
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(added ? 'تمت إضافة الآية إلى المفضلة والمرجعيات' : 'تمت إزالة الآية من المفضلة'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      }
                    },
                  ),
                  IconButton(
                    iconSize: 22,
                    tooltip: 'نسخ الآية',
                    icon: const Icon(Icons.copy_rounded, color: AppColors.primaryGreen),
                    onPressed: _copyAyah,
                  ),
                  IconButton(
                    iconSize: 22,
                    tooltip: 'مشاركة الآية',
                    icon: const Icon(Icons.share_rounded, color: AppColors.primaryGreen),
                    onPressed: _shareAyah,
                  ),
                  IconButton(
                    iconSize: 22,
                    tooltip: 'إغلاق',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            const Divider(height: 8),

            // Scrollable Options Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. Ayah Text Display Card
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E2621)
                            : AppColors.primaryGreen.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark
                              ? AppColors.primaryGreen.withValues(alpha: 0.3)
                              : AppColors.primaryGreen.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Text(
                        '${widget.ayah.cleanTextUthmani} ﴿${SettingsService.instance.formatAyahNumber(widget.ayah.ayahNumber)}﴾',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          height: 2.1,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : AppColors.emerald900,
                          fontFamilyFallback: const [
                            'Traditional Arabic',
                            'Scheherazade New',
                            'Amiri',
                            'serif',
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // 2. Audio Recitation Bar
                    ValueListenableBuilder<String?>(
                      valueListenable: AyahAudioPlayer.instance.currentPlayingKey,
                      builder: (context, playingKey, _) {
                        final isPlayingThisAyah = playingKey == ayahKey;

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isPlayingThisAyah
                                ? AppColors.accentGold.withValues(alpha: 0.12)
                                : (isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.shade100),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isPlayingThisAyah
                                  ? AppColors.accentGold
                                  : Colors.grey.withValues(alpha: 0.2),
                              width: isPlayingThisAyah ? 1.5 : 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              // Play / Stop Icon Button
                              InkWell(
                                onTap: () {
                                  if (isPlayingThisAyah) {
                                    AyahAudioPlayer.instance.stop();
                                  } else {
                                    AyahAudioPlayer.instance.playAyah(
                                      context,
                                      widget.surah.id,
                                      widget.ayah.ayahNumber,
                                      surahName: widget.surah.nameAr,
                                    );
                                  }
                                },
                                borderRadius: BorderRadius.circular(24),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isPlayingThisAyah ? AppColors.accentGold : AppColors.primaryGreen,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isPlayingThisAyah ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    color: isPlayingThisAyah ? Colors.black : Colors.white,
                                    size: 24,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),

                              // Playback label & Current Reciter
                              Expanded(
                                child: InkWell(
                                  onTap: () {
                                    if (isPlayingThisAyah) {
                                      AyahAudioPlayer.instance.stop();
                                    } else {
                                      AyahAudioPlayer.instance.playAyah(
                                        context,
                                        widget.surah.id,
                                        widget.ayah.ayahNumber,
                                        surahName: widget.surah.nameAr,
                                      );
                                    }
                                  },
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isPlayingThisAyah ? 'إيقاف تلاوة الآية' : 'استماع للآية الكريمة',
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.bold,
                                          color: isPlayingThisAyah ? AppColors.accentGold : AppColors.primaryGreen,
                                        ),
                                      ),
                                      Text(
                                        'بصوت: ${currentReciter.nameAr}',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: isDark ? Colors.white70 : Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // Change Reciter Button
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  backgroundColor: isDark ? Colors.white10 : Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                                  ),
                                ),
                                icon: const Icon(Icons.person_search_rounded, size: 16, color: AppColors.primaryGreen),
                                label: const Text(
                                  'تغيير القارئ',
                                  style: TextStyle(fontSize: 11.5, color: AppColors.primaryGreen, fontWeight: FontWeight.bold),
                                ),
                                onPressed: _showReciterSelector,
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 16),

                    // Section 1: 📖 التفاسير وعلوم القرآن
                    _buildSectionHeader('📖 التفاسير وعلوم القرآن الكريم', AppColors.primaryGreen),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.spaceAround,
                      spacing: 8,
                      runSpacing: 10,
                      children: [
                        _buildFeatureButton(
                          icon: Icons.menu_book_rounded,
                          label: 'التفسير والشروح',
                          subtitle: 'الميسر وابن كثير',
                          color: AppColors.primaryGreen,
                          onTap: _showTafseer,
                        ),
                        _buildFeatureButton(
                          icon: Icons.compare_arrows_rounded,
                          label: 'مقارنة التفاسير',
                          subtitle: 'شاشة مقارنة الآية',
                          color: AppColors.secondaryGreen,
                          onTap: _showComparativeTafsir,
                        ),
                        _buildFeatureButton(
                          icon: Icons.auto_stories_rounded,
                          label: 'معاني الكلمات',
                          subtitle: 'غريب القرآن',
                          color: AppColors.primaryGreen,
                          onTap: () => _showLinguistics(initialTab: 0),
                        ),
                        _buildFeatureButton(
                          icon: Icons.history_edu_rounded,
                          label: 'أسباب النزول',
                          subtitle: 'سياق الآية',
                          color: AppColors.primaryGreen,
                          onTap: () => _showLinguistics(initialTab: 1),
                        ),
                        _buildFeatureButton(
                          icon: Icons.spellcheck_rounded,
                          label: 'إعراب الآية',
                          subtitle: 'الإعراب المفصل',
                          color: AppColors.primaryGreen,
                          onTap: _showDetailedIrab,
                        ),
                        _buildFeatureButton(
                          icon: Icons.record_voice_over_rounded,
                          label: 'القراءات العشر',
                          subtitle: 'ورش وقالون',
                          color: AppColors.secondaryGreen,
                          onTap: _showQiraat,
                        ),
                        _buildFeatureButton(
                          icon: Icons.graphic_eq_rounded,
                          label: 'التفسير الصوتي',
                          subtitle: 'خواطر الشعراوي',
                          color: AppColors.accentGold,
                          onTap: _showAudioTafsir,
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    // Section 2: ✍️ الحفظ والتدبر والملاحظات
                    _buildSectionHeader('✍️ الحفظ والتدبر والخواطر', AppColors.secondaryGreen),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.spaceAround,
                      spacing: 8,
                      runSpacing: 10,
                      children: [
                        _buildFeatureButton(
                          icon: Icons.repeat_one_rounded,
                          label: 'تحفيظ وتكرار',
                          subtitle: 'تثبيت الآية',
                          color: AppColors.secondaryGreen,
                          onTap: _showMemorization,
                        ),
                        _buildFeatureButton(
                          icon: hasNote ? Icons.rate_review : Icons.rate_review_outlined,
                          label: hasNote ? 'تعديل الخاطرة' : 'تدبر وخاطرة',
                          subtitle: 'تأملاتك بالآية',
                          color: hasNote ? AppColors.accentGold : AppColors.primaryGreen,
                          onTap: _showTadabburNote,
                        ),
                        _buildFeatureButton(
                          icon: Icons.collections_bookmark_rounded,
                          label: 'سجل التدبرات',
                          subtitle: 'دفتر الخواطر',
                          color: AppColors.secondaryGreen,
                          onTap: _showTadabburJournal,
                        ),
                        _buildFeatureButton(
                          icon: isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                          label: isBookmarked ? 'محفوظة' : 'إشارة مرجعية',
                          subtitle: 'حفظ الموضع',
                          color: isBookmarked ? AppColors.accentGold : AppColors.primaryGreen,
                          onTap: () async {
                            final added = await SettingsService.instance.toggleBookmark(widget.surah.id, widget.ayah.ayahNumber);
                            setState(() {});
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(added ? 'تمت إضافة الآية إلى المفضلة والمرجعيات' : 'تمت إزالة الآية من المفضلة'),
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    // Section 3: 🎨 المشاركة والتصميم الدعوي
                    _buildSectionHeader('🎨 النشر والتصميم الدعوي', AppColors.accentGold),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.spaceAround,
                      spacing: 8,
                      runSpacing: 10,
                      children: [
                        _buildFeatureButton(
                          icon: Icons.brush_rounded,
                          label: 'بطاقة دعوية (صورة)',
                          subtitle: 'تصميم فني فاخر',
                          color: AppColors.accentGold,
                          onTap: _showCardShare,
                        ),
                        _buildFeatureButton(
                          icon: Icons.copy_rounded,
                          label: 'نسخ الآية',
                          subtitle: 'نص موثق',
                          color: AppColors.primaryGreen,
                          onTap: _copyAyah,
                        ),
                        _buildFeatureButton(
                          icon: Icons.share_rounded,
                          label: 'مشاركة',
                          subtitle: 'عبر التطبيقات',
                          color: AppColors.primaryGreen,
                          onTap: _shareAyah,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Row(
      children: [
        Container(
          width: 3.5,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
    Color color = AppColors.primaryGreen,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 102,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: isDark ? 0.08 : 0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.2), width: 1.0),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppColors.emerald900,
                  height: 1.15,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9.5,
                  color: isDark ? Colors.white60 : Colors.black45,
                  height: 1.1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
