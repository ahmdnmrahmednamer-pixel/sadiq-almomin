import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../core/models/surah.dart';
import '../../core/models/ayah.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/quran_repository.dart';
import '../../core/services/settings_service.dart';
import '../../core/audio/ayah_audio_player.dart';
import '../../core/gestures/ayah_gesture_recognizer.dart';
import 'widgets/ayah_action_sheet.dart';
import 'widgets/ayah_linguistics_sheet.dart';
import 'widgets/ayah_card_share_sheet.dart';
import 'page_mode_mushaf_screen.dart';
import '../settings/widgets/settings_reciter_modal.dart';
import '../../core/services/khatma_service.dart';
import '../../core/services/quran_accessibility_service.dart';
import '../../core/ui/app_dropdown_field.dart';

enum _SurahReaderMenuAction {
  cycleTheme,
  selectReciter,
  openPageMode,
}

class SurahReaderScreen extends StatefulWidget {
  final Surah surah;
  final int initialAyah;

  const SurahReaderScreen({
    super.key,
    required this.surah,
    this.initialAyah = 1,
  });

  @override
  State<SurahReaderScreen> createState() => _SurahReaderScreenState();
}

class _SurahReaderScreenState extends State<SurahReaderScreen> {
  late double _fontSize;
  late Future<List<Ayah>> _ayahsFuture;
  final List<TapGestureRecognizer> _recognizers = [];
  int _themeModeIndex = 0; // 0: تلقائي/النظام, 1: مصحفي ورقي, 2: ليلي داكن, 3: نهاري أبيض
  String _readingDisplayMode = 'continuous'; // 'continuous' (المصحف المتصل) أو 'cards' (بطاقات الآيات والتفسير)
  final Set<int> _expandedTafseerAyahs = {};

  @override
  void initState() {
    super.initState();
    _fontSize = SettingsService.instance.mushafFontSize;
    _ayahsFuture = QuranRepository.getAyahsForSurah(widget.surah.id);
    SettingsService.instance.saveLastRead(
      surahId: widget.surah.id,
      ayahNumber: widget.initialAyah,
      pageNumber: widget.surah.pageStart,
      surahName: widget.surah.nameAr,
    );
    KhatmaService.instance.updateProgressFromReading(widget.surah.pageStart);
  }

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    super.dispose();
  }

  String _toArabicIndic(int number) {
    const arabicDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return number.toString().split('').map((char) {
      final digit = int.tryParse(char);
      return digit != null ? arabicDigits[digit] : char;
    }).join();
  }

  void _cycleReadingTheme() {
    setState(() {
      _themeModeIndex = (_themeModeIndex + 1) % 4;
    });
    final names = ['تلقائي حسب نظام الهاتف', 'ورقي مصحفي دافئ', 'ليلي مريح للعين', 'نهاري ناصع'];
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('وضع القراءة: ${names[_themeModeIndex]}'),
        duration: const Duration(milliseconds: 900),
      ),
    );
  }

  void _cycleFontSize() {
    setState(() {
      _fontSize = _fontSize >= 34.0 ? 18.0 : _fontSize + 4.0;
    });
    SettingsService.instance.setMushafFontSize(_fontSize);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('حجم الخط: ${_fontSize.toInt()}'),
        duration: const Duration(milliseconds: 600),
      ),
    );
  }

  void _openPageModeMushaf() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PageModeMushafScreen(initialPage: widget.surah.pageStart),
      ),
    );
  }

  void _handleHeaderMenuAction(_SurahReaderMenuAction action) {
    switch (action) {
      case _SurahReaderMenuAction.cycleTheme:
        _cycleReadingTheme();
        break;
      case _SurahReaderMenuAction.selectReciter:
        showSettingsReciterModal(context);
        break;
      case _SurahReaderMenuAction.openPageMode:
        _openPageModeMushaf();
        break;
    }
  }

  Widget _buildReadingControlsBar({
    required BuildContext context,
    required bool isDark,
    required Color headerBg,
    required Color headerBorder,
  }) {
    final controlTheme = Theme.of(context).copyWith(
      brightness: isDark ? Brightness.dark : Brightness.light,
    );

    return Theme(
      data: controlTheme,
      child: Container(
        key: const ValueKey('surah_reader_controls_bar'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: headerBg,
          border: Border(
            bottom: BorderSide(
              color: headerBorder.withValues(alpha: 0.35),
              width: 1,
            ),
          ),
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.start,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AppToolbarDropdown<String>(
              semanticLabel: 'نمط عرض الآيات',
              value: _readingDisplayMode,
              options: const [
                AppDropdownOption(
                  value: 'continuous',
                  label: 'المصحف المتصل',
                  icon: Icons.menu_book_rounded,
                ),
                AppDropdownOption(
                  value: 'cards',
                  label: 'بطاقات الآيات والتفسير',
                  icon: Icons.view_agenda_rounded,
                ),
              ],
              onChanged: (val) {
                setState(() {
                  _readingDisplayMode = val;
                });
              },
            ),
            AppToolbarDropdown<int>(
              semanticLabel: 'مظهر القراءة',
              value: _themeModeIndex,
              options: const [
                AppDropdownOption(
                  value: 0,
                  label: 'تلقائي',
                  icon: Icons.brightness_auto_rounded,
                ),
                AppDropdownOption(
                  value: 1,
                  label: 'ورقي مصحفي',
                  icon: Icons.menu_book_rounded,
                ),
                AppDropdownOption(
                  value: 2,
                  label: 'ليلي مريح',
                  icon: Icons.nightlight_round,
                ),
                AppDropdownOption(
                  value: 3,
                  label: 'نهاري ناصع',
                  icon: Icons.wb_sunny_rounded,
                ),
              ],
              onChanged: (val) {
                setState(() {
                  _themeModeIndex = val;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final textScale = media.textScaler.scale(1.0);
    final isLargeText = textScale >= 1.35;
    final isCompactHeader = media.size.width < 480 || isLargeText;

    final isSysDark = Theme.of(context).brightness == Brightness.dark;
    final isDark = _themeModeIndex == 2 || (_themeModeIndex == 0 && isSysDark);
    final isSepia = _themeModeIndex == 1;

    final Color pageBg = isSepia
        ? const Color(0xFFF7F1E3)
        : (isDark ? const Color(0xFF141716) : const Color(0xFFFCFCFA));

    final Color textColor = isSepia
        ? const Color(0xFF262019)
        : (isDark ? const Color(0xFFF7F7F7) : const Color(0xFF181C1A));

    final Color basmalaColor = isSepia
        ? const Color(0xFF2D5A27)
        : (isDark ? AppColors.softGold : AppColors.primaryGreen);

    final Color headerBg = isSepia
        ? const Color(0xFFEFE6D2)
        : (isDark ? const Color(0xFF1E2522) : AppColors.primaryGreen.withValues(alpha: 0.08));

    final Color headerBorder = isSepia
        ? const Color(0xFFC9A84D)
        : (isDark ? AppColors.accentGold : AppColors.accentGold);

    final Color headerTitleColor = isSepia
        ? const Color(0xFF2D5A27)
        : (isDark ? AppColors.accentGold : AppColors.primaryGreen);

    final IconData themeIcon = _themeModeIndex == 1
        ? Icons.menu_book
        : (_themeModeIndex == 2 ? Icons.nightlight_round : (_themeModeIndex == 3 ? Icons.wb_sunny : Icons.brightness_auto));

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        toolbarHeight: isLargeText ? (textScale >= 1.75 ? 104.0 : 80.0) : null,
        titleSpacing: isLargeText ? 8.0 : null,
        title: Text(
          'سورة ${widget.surah.nameAr}',
          maxLines: 2,
          softWrap: true,
          overflow: TextOverflow.visible,
          style: const TextStyle(height: 1.2),
        ),
        actions: [
          if (!isCompactHeader) ...[
            IconButton(
              icon: Icon(themeIcon),
              tooltip: 'تغيير نمط القراءة',
              onPressed: _cycleReadingTheme,
            ),
            IconButton(
              icon: const Icon(Icons.record_voice_over_rounded),
              tooltip: 'تغيير القارئ للتلاوة',
              onPressed: () => showSettingsReciterModal(context),
            ),
            IconButton(
              icon: const Icon(Icons.auto_stories_rounded),
              tooltip: 'الانتقال إلى نمط صفحات المصحف (604 صفحات)',
              onPressed: _openPageModeMushaf,
            ),
          ],
          IconButton(
            icon: const Icon(Icons.format_size),
            tooltip: 'تغيير حجم الخط',
            onPressed: _cycleFontSize,
          ),
          if (isCompactHeader)
            PopupMenuButton<_SurahReaderMenuAction>(
              tooltip: 'المزيد من خيارات القراءة',
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: _handleHeaderMenuAction,
              itemBuilder: (context) => [
                PopupMenuItem<_SurahReaderMenuAction>(
                  value: _SurahReaderMenuAction.cycleTheme,
                  child: Row(
                    children: [
                      Icon(themeIcon, size: 20),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'تغيير نمط القراءة',
                          softWrap: true,
                        ),
                      ),
                    ],
                  ),
                ),
                const PopupMenuItem<_SurahReaderMenuAction>(
                  value: _SurahReaderMenuAction.selectReciter,
                  child: Row(
                    children: [
                      Icon(Icons.record_voice_over_rounded, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'تغيير القارئ للتلاوة',
                          softWrap: true,
                        ),
                      ),
                    ],
                  ),
                ),
                const PopupMenuItem<_SurahReaderMenuAction>(
                  value: _SurahReaderMenuAction.openPageMode,
                  child: Row(
                    children: [
                      Icon(Icons.auto_stories_rounded, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'الانتقال إلى نمط صفحات المصحف (604 صفحات)',
                          softWrap: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Directionality(
        textDirection: SettingsService.instance.textDirection,
        child: Column(
          children: [
            _buildReadingControlsBar(
              context: context,
              isDark: isDark,
              headerBg: headerBg,
              headerBorder: headerBorder,
            ),
            Expanded(
              child: FutureBuilder<List<Ayah>>(
          future: _ayahsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: AppColors.primaryGreen),
                    SizedBox(height: 16),
                    Text('جاري تحميل آيات السورة الكريمة...', style: TextStyle(color: AppColors.mutedText)),
                  ],
                ),
              );
            }

            if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 12),
                    Text('تعذر تحميل السورة: ${snapshot.error ?? "لا توجد بيانات"}'),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _ayahsFuture = QuranRepository.getAyahsForSurah(widget.surah.id);
                        });
                      },
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              );
            }

            final ayahs = snapshot.data!;

            return ValueListenableBuilder<String?>(
              valueListenable: AyahAudioPlayer.instance.currentPlayingKey,
              builder: (context, playingKey, _) {
                // Clear and dispose old gesture recognizers before creating new ones for this state
                for (final r in _recognizers) {
                  r.dispose();
                }
                _recognizers.clear();

                if (_readingDisplayMode == 'cards' || MediaQuery.accessibleNavigationOf(context)) {
                  return _buildAccessibleAyahList(
                    ayahs: ayahs,
                    playingKey: playingKey,
                    isDark: isDark,
                    isSepia: isSepia,
                    textColor: textColor,
                    pageBg: pageBg,
                  );
                }

                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
                  children: [
                    // Decorative Surah Header Frame
                    Semantics(
                      label: QuranAccessibilityService.buildSurahHeaderSemanticLabel(
                        surahName: widget.surah.nameAr,
                        isMakki: widget.surah.isMakki,
                        ayahCount: widget.surah.ayahCount,
                        revelationOrder: widget.surah.revelationOrder,
                      ),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                        decoration: BoxDecoration(
                          color: headerBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: headerBorder, width: 1.5),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'سورة ${widget.surah.nameAr}',
                              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: headerTitleColor),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${widget.surah.isMakki ? "مكية" : "مدنية"} — آياتها ${widget.surah.ayahCount} — ترتيبها ${widget.surah.revelationOrder}',
                              style: TextStyle(fontSize: 14, color: isDark ? Colors.white70 : AppColors.mutedText),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '💡 اضغط ضغطة عادية للاستماع للآية، وضغطة مطولة لفتح كافة خيارات الآية',
                              style: TextStyle(fontSize: 12, color: isDark ? AppColors.softGold : AppColors.secondaryGreen),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Separate Decorative Basmala (not in Surah 9 At-Tawbah, not separate in Fatihah)
                    if (widget.surah.hasBasmala && widget.surah.id != 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 24.0),
                        child: Semantics(
                          label: 'بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ',
                          child: Text(
                            'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: basmalaColor,
                            ),
                          ),
                        ),
                      ),

                    // Text Mode Ayah Flow: Ayah text followed immediately by its number (e.g. قل هو الله احد 1 الله الصمد 2)
                    RichText(
                      textAlign: TextAlign.justify,
                      text: TextSpan(
                        children: ayahs.expand((ayah) {
                          final isPlaying = playingKey == '${widget.surah.id}:${ayah.ayahNumber}';

                          void handleAyahTap() {
                            if (isPlaying) {
                              AyahAudioPlayer.instance.stop();
                            } else {
                              AyahAudioPlayer.instance.playAyah(
                                context,
                                widget.surah.id,
                                ayah.ayahNumber,
                                surahName: widget.surah.nameAr,
                              );
                            }
                          }

                          void handleAyahLongPress() {
                            AyahActionSheet.show(
                              context,
                              surah: widget.surah,
                              ayah: ayah,
                            );
                          }

                          final rec = AyahGestureRecognizer(
                            onAyahTap: handleAyahTap,
                            onAyahLongPress: handleAyahLongPress,
                          );
                          final recNum = AyahGestureRecognizer(
                            onAyahTap: handleAyahTap,
                            onAyahLongPress: handleAyahLongPress,
                          );
                          _recognizers.add(rec);
                          _recognizers.add(recNum);

                          final formattedNumber = SettingsService.instance.formatAyahNumber(ayah.ayahNumber);

                          return [
                            TextSpan(
                              text: '${ayah.cleanTextUthmani} ',
                              semanticsLabel: QuranAccessibilityService.buildAyahSemanticLabel(
                                surahName: widget.surah.nameAr,
                                ayahNumber: ayah.ayahNumber,
                                uthmaniText: ayah.cleanTextUthmani,
                              ),
                              recognizer: rec,
                              style: TextStyle(
                                fontSize: _fontSize,
                                height: 2.2,
                                color: isPlaying ? AppColors.accentGold : textColor,
                                backgroundColor: isPlaying ? AppColors.accentGold.withValues(alpha: 0.18) : Colors.transparent,
                                fontWeight: isPlaying ? FontWeight.bold : FontWeight.w500,
                                fontFamilyFallback: const [
                                  'Traditional Arabic',
                                  'Scheherazade New',
                                  'Amiri',
                                  'serif',
                                ],
                              ),
                            ),
                            TextSpan(
                              text: '﴿$formattedNumber﴾ ',
                              recognizer: recNum,
                              style: TextStyle(
                                fontSize: _fontSize * 0.95,
                                height: 2.2,
                                color: isPlaying
                                    ? AppColors.accentGold
                                    : (isDark ? AppColors.softGold : AppColors.accentGold),
                                fontWeight: FontWeight.bold,
                                fontFamilyFallback: const [
                                  'Traditional Arabic',
                                  'Scheherazade New',
                                  'Amiri',
                                  'serif',
                                ],
                              ),
                            ),
                          ];
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                );
              },
            );
          },
        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccessibleAyahList({
    required List<Ayah> ayahs,
    required String? playingKey,
    required bool isDark,
    required bool isSepia,
    required Color textColor,
    required Color pageBg,
  }) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 16.0),
      itemCount: ayahs.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2823) : AppColors.primaryGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_stories_rounded, color: AppColors.primaryGreen, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'عرض بطاقات الآيات: اضغط ضغطة عادية للاستماع للآية، وضغطة مطولة لعرض كافة خيارات الآية والتفاسير.',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : AppColors.secondaryGreen,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final ayah = ayahs[index - 1];
        final isPlaying = playingKey == '${widget.surah.id}:${ayah.ayahNumber}';
        final isTafseerExpanded = _expandedTafseerAyahs.contains(ayah.ayahNumber);
        final isBookmarked = SettingsService.instance.isBookmarked(widget.surah.id, ayah.ayahNumber);
        final spokenText = '${QuranAccessibilityService.toScreenReaderText(ayah.cleanTextUthmani)} ${ayah.ayahNumber}';

        return Semantics(
          container: true,
          label: QuranAccessibilityService.buildAyahSemanticLabel(
            surahName: widget.surah.nameAr,
            ayahNumber: ayah.ayahNumber,
            uthmaniText: ayah.cleanTextUthmani,
          ),
          hint: QuranAccessibilityService.ayahSemanticHint,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C221F) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isPlaying
                    ? AppColors.accentGold
                    : (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
                width: isPlaying ? 2.0 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isPlaying ? AppColors.accentGold : AppColors.primaryGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'آية ${_toArabicIndic(ayah.ayahNumber)} / ${_toArabicIndic(widget.surah.ayahCount)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isPlaying ? Colors.black : AppColors.primaryGreen,
                        ),
                      ),
                    ),
                    if (isPlaying)
                      const Row(
                        children: [
                          Icon(Icons.volume_up_rounded, color: AppColors.accentGold, size: 18),
                          SizedBox(width: 4),
                          Text(
                            'جاري الاستماع',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.accentGold),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 10),

                // Quranic Text (Ayah text followed immediately by its rosette number)
                // Single tap plays/stops the Ayah audio; Long press opens full AyahActionSheet.
                InkWell(
                  onTap: () {
                    if (isPlaying) {
                      AyahAudioPlayer.instance.stop();
                    } else {
                      AyahAudioPlayer.instance.playAyah(
                        context,
                        widget.surah.id,
                        ayah.ayahNumber,
                        surahName: widget.surah.nameAr,
                      );
                    }
                  },
                  onLongPress: () {
                    AyahActionSheet.show(
                      context,
                      surah: widget.surah,
                      ayah: ayah,
                    );
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${ayah.cleanTextUthmani} ',
                        style: TextStyle(
                          fontSize: _fontSize,
                          height: 2.1,
                          fontWeight: FontWeight.w600,
                          color: isPlaying ? AppColors.accentGold : textColor,
                          fontFamilyFallback: const [
                            'Traditional Arabic',
                            'Scheherazade New',
                            'Amiri',
                            'serif',
                          ],
                        ),
                      ),
                      TextSpan(
                        text: '﴿${SettingsService.instance.formatAyahNumber(ayah.ayahNumber)}﴾',
                        style: TextStyle(
                          fontSize: _fontSize * 0.95,
                          fontWeight: FontWeight.bold,
                          color: isPlaying
                              ? AppColors.accentGold
                              : (isDark ? AppColors.softGold : AppColors.accentGold),
                          fontFamilyFallback: const [
                            'Traditional Arabic',
                            'Scheherazade New',
                            'Amiri',
                            'serif',
                          ],
                        ),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.justify,
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Phonetic Screen Reader Spoken Guide
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.record_voice_over_outlined, size: 16, color: AppColors.secondaryGreen),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          spokenText,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.grey.shade700,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 18),

                // Accessible Action Buttons Row (WCAG AA Target >= 48px)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    IconButton(
                      iconSize: 22,
                      icon: Icon(
                        isTafseerExpanded ? Icons.menu_book_rounded : Icons.menu_book_outlined,
                        color: isTafseerExpanded ? AppColors.accentGold : AppColors.secondaryGreen,
                      ),
                      tooltip: isTafseerExpanded ? 'إخفاء التفسير الميسر' : 'عرض التفسير الميسر',
                      onPressed: () {
                        setState(() {
                          if (isTafseerExpanded) {
                            _expandedTafseerAyahs.remove(ayah.ayahNumber);
                          } else {
                            _expandedTafseerAyahs.add(ayah.ayahNumber);
                          }
                        });
                      },
                    ),
                    IconButton(
                      iconSize: 22,
                      icon: Icon(
                        isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                        color: isBookmarked ? AppColors.accentGold : Colors.grey,
                      ),
                      tooltip: isBookmarked ? 'إزالة من العلامات المرجعية' : 'حفظ في العلامات المرجعية',
                      onPressed: () async {
                        final added = await SettingsService.instance.toggleBookmark(widget.surah.id, ayah.ayahNumber);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(added ? 'تم حفظ الآية في العلامات المرجعية' : 'تمت إزالة الآية من العلامات'),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        }
                      },
                    ),
                    IconButton(
                      iconSize: 22,
                      icon: const Icon(Icons.history_edu_rounded, color: AppColors.secondaryGreen),
                      tooltip: 'معاني الكلمات، غريب القرآن، وأسباب النزول',
                      onPressed: () {
                        AyahLinguisticsSheet.show(
                          context,
                          surah: widget.surah,
                          ayah: ayah,
                        );
                      },
                    ),
                    IconButton(
                      iconSize: 22,
                      icon: const Icon(Icons.brush_rounded, color: AppColors.accentGold),
                      tooltip: 'تصميم ومشاركة بطاقة دعوية للآية (صورة)',
                      onPressed: () {
                        AyahCardShareSheet.show(
                          context,
                          surah: widget.surah,
                          ayah: ayah,
                        );
                      },
                    ),
                    IconButton(
                      iconSize: 22,
                      icon: const Icon(Icons.more_horiz_rounded, color: AppColors.primaryGreen),
                      tooltip: 'خيارات الآية، التكرار، والنسخ',
                      onPressed: () {
                        AyahActionSheet.show(
                          context,
                          surah: widget.surah,
                          ayah: ayah,
                        );
                      },
                    ),
                  ],
                ),

                // Inline Tafseer Expansion
                if (isTafseerExpanded) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.accentGold.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.accentGold.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.auto_stories_rounded, size: 16, color: AppColors.accentGold),
                            SizedBox(width: 6),
                            Text(
                              'التفسير الميسر:',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.accentGold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          ayah.tafseer ?? 'التفسير غير متوفر لهذه الآية حالياً.',
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.6,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
