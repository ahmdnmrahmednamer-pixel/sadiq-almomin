import 'widgets/scoped_playback_bar.dart';
import '../../core/text/arabic_normalizer.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import '../../core/models/ayah.dart';
import '../../core/models/surah.dart';
import '../../core/services/quran_repository.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/khatma_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/audio/ayah_audio_player.dart';
import '../../core/gestures/ayah_gesture_recognizer.dart';
import 'widgets/ayah_action_sheet.dart';
import 'widgets/ayah_interaction.dart';
import 'widgets/ayah_keyboard_focus.dart';
import 'surah_reader_screen.dart';
import '../../core/services/quran_accessibility_service.dart';
import '../../core/ui/app_dropdown_field.dart';

enum _PageModeMenuAction {
  cycleTheme,
  switchToSurahMode,
  toggleBookmark,
}

class PageModeMushafScreen extends StatefulWidget {
  final int initialPage;
  /// Marks one ayah (for example a saved bookmark) on the opened page.
  final int? highlightSurah;
  final int? highlightAyah;

  const PageModeMushafScreen({
    super.key,
    this.initialPage = 1,
    this.highlightSurah,
    this.highlightAyah,
  });

  @override
  State<PageModeMushafScreen> createState() => _PageModeMushafScreenState();
}

class _PageModeMushafScreenState extends State<PageModeMushafScreen> {
  late int _currentPage;
  late PageController _pageController;
  bool _showControls = true;
  final List<TapGestureRecognizer> _pageRecognizers = [];
  int _themeModeIndex = 0; // 0: تلقائي/نظام, 1: ورقي مصحفي, 2: ليلي داكن, 3: نهاري ناصع
  double _fontSize = 22.0;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage.clamp(1, 604);
    _pageController = PageController(initialPage: _currentPage - 1);
    _fontSize = SettingsService.instance.mushafFontSize;
    _recordCurrentPageRead();
    if (widget.highlightAyah != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        SemanticsService.sendAnnouncement(View.of(context),
            'العلامة المرجعية: الآية ${widget.highlightAyah}', TextDirection.rtl);
      });
    }
  }

  @override
  void dispose() {
    for (final r in _pageRecognizers) {
      r.dispose();
    }
    _pageRecognizers.clear();
    _pageController.dispose();
    super.dispose();
  }

  void _recordCurrentPageRead() async {
    final meta = await QuranRepository.getPageMetadata(_currentPage);
    if (meta != null && mounted) {
      SettingsService.instance.saveLastRead(
        surahId: meta.surahId,
        ayahNumber: meta.startAyah,
        pageNumber: _currentPage,
        surahName: meta.surahName,
      );
      KhatmaService.instance.updateProgressFromReading(_currentPage);
    }
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentPage = index + 1;
    });
    _recordCurrentPageRead();
  }

  void _jumpToPage(int page) {
    final p = page.clamp(1, 604);
    if (_pageController.hasClients) {
      _pageController.jumpToPage(p - 1);
    }
  }

  void _cycleTheme() {
    setState(() {
      _themeModeIndex = (_themeModeIndex + 1) % 4;
    });
    final names = ['تلقائي', 'ورقي مصحفي', 'ليلي داكن', 'نهاري ناصع'];
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('وضع القراءة: ${names[_themeModeIndex]}'),
        duration: const Duration(milliseconds: 700),
      ),
    );
  }

  void _showJumpDialog() {
    final controller = TextEditingController(text: _currentPage.toString());
    double sliderVal = _currentPage.toDouble();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Directionality(
              textDirection: SettingsService.instance.textDirection,
              child: AlertDialog(
                scrollable: true,
                title: const Text('الانتقال إلى صفحة'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('صفحة: ${sliderVal.toInt()} من 604', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),
                    Slider(
                      value: sliderVal.clamp(1.0, 604.0),
                      min: 1,
                      max: 604,
                      divisions: 603,
                      activeColor: AppColors.accentGold,
                      onChanged: (val) {
                        setDialogState(() {
                          sliderVal = val;
                          controller.text = val.toInt().toString();
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    const Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        'رقم الصفحة (1 - 604)',
                        softWrap: true,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Semantics(
                      label: 'رقم الصفحة (1 - 604)',
                      textField: true,
                      child: TextField(
                        controller: controller,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: '1 - 604',
                        ),
                        onChanged: (val) {
                          final parsed = ArabicNormalizer.tryParseInt(val);
                          if (parsed != null && parsed >= 1 && parsed <= 604) {
                            setDialogState(() {
                              sliderVal = parsed.toDouble();
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('إلغاء'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryGreen, foregroundColor: Colors.white),
                    onPressed: () {
                      final p = ArabicNormalizer.tryParseInt(controller.text);
                      if (p != null) {
                        _jumpToPage(p);
                      }
                      Navigator.pop(ctx);
                    },
                    child: const Text('انتقال'),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      Future.delayed(const Duration(milliseconds: 350), controller.dispose);
    });
  }

  String _toArabicIndic(int number) {
    const arabicDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return number.toString().split('').map((char) {
      final digit = int.tryParse(char);
      return digit != null ? arabicDigits[digit] : char;
    }).join();
  }

  Future<void> _openSurahReaderMode() async {
    final meta = await QuranRepository.getPageMetadata(_currentPage);
    if (meta != null && mounted) {
      final surah = await QuranRepository.getSurahById(meta.surahId);
      if (surah != null && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => SurahReaderScreen(
              surah: surah,
              initialAyah: meta.startAyah,
            ),
          ),
        );
      }
    }
  }

  Future<void> _toggleCurrentPageBookmark() async {
    final meta = await QuranRepository.getPageMetadata(_currentPage);
    if (meta != null && mounted) {
      final added = await SettingsService.instance.toggleBookmark(
        meta.surahId,
        meta.startAyah,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              added
                  ? 'تمت إضافة سورة ${meta.surahName} (صفحة $_currentPage) إلى العلامات المرجعية'
                  : 'تمت إزالة العلامة المرجعية',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _handleHeaderMenuAction(_PageModeMenuAction action) {
    switch (action) {
      case _PageModeMenuAction.cycleTheme:
        _cycleTheme();
        break;
      case _PageModeMenuAction.switchToSurahMode:
        _openSurahReaderMode();
        break;
      case _PageModeMenuAction.toggleBookmark:
        _toggleCurrentPageBookmark();
        break;
    }
  }

  Widget _buildReadingControlsBar({
    required BuildContext context,
    required bool isDark,
    required bool isSepia,
    required Color frameColor,
  }) {
    final Color barBg = isSepia
        ? const Color(0xFFEFE6D2)
        : (isDark
            ? const Color(0xFF1E2522)
            : AppColors.primaryGreen.withValues(alpha: 0.08));
    final controlTheme = Theme.of(context).copyWith(
      brightness: isDark ? Brightness.dark : Brightness.light,
    );

    return Theme(
      data: controlTheme,
      child: Container(
        key: const ValueKey('page_mode_controls_bar'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: barBg,
          border: Border(
            bottom: BorderSide(
              color: frameColor.withValues(alpha: 0.35),
              width: 1,
            ),
          ),
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          alignment: WrapAlignment.start,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AppToolbarDropdown<int>(
              semanticLabel: 'مظهر صفحة المصحف',
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
                  label: 'ليلي داكن',
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

    final Color frameColor = isSepia
        ? const Color(0xFFC9A84D)
        : (isDark ? AppColors.accentGold.withValues(alpha: 0.4) : AppColors.accentGold);

    final Color textColor = isSepia
        ? const Color(0xFF262019)
        : (isDark ? const Color(0xFFF7F7F7) : const Color(0xFF181C1A));

    return Directionality(
      textDirection: SettingsService.instance.textDirection,
      child: Scaffold(
        backgroundColor: pageBg,
        bottomNavigationBar: _showControls
            ? FutureBuilder<List<List<Ayah>>>(
                key: ValueKey('page-scope-$_currentPage'),
                future: () async {
                  final page = await QuranRepository.getAyahsForPage(_currentPage);
                  final juz = page.isEmpty ? <Ayah>[] : await QuranRepository.getAyahsForJuz(page.first.juz);
                  return [page, juz];
                }(),
                builder: (context, snap) {
                  final data = snap.data;
                  if (data == null || data[0].isEmpty) return const SizedBox.shrink();
                  List<String> k(List<Ayah> l) => [for (final a in l) '${a.surahId}:${a.ayahNumber}'];
                  return ScopedPlaybackBar(
                    keys: k(data[0]),
                    scopeName: 'الصفحة',
                    alternates: {'الجزء ${data[0].first.juz}': k(data[1])},
                  );
                },
              )
            : null,
        appBar: _showControls
            ? AppBar(
                toolbarHeight: isLargeText
                    ? (textScale >= 1.75 ? 96.0 : 76.0)
                    : null,
                titleSpacing: isLargeText ? 8.0 : null,
                title: Text(
                  'صفحة ${_toArabicIndic(_currentPage)} / ٦٠٤',
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.visible,
                  style: const TextStyle(height: 1.2),
                ),
                actions: [
                  if (!isCompactHeader) ...[
                    IconButton(
                      icon: const Icon(Icons.palette_outlined),
                      tooltip: 'تغيير سمة القراءة',
                      onPressed: _cycleTheme,
                    ),
                    IconButton(
                      icon: const Icon(Icons.swap_horiz_rounded),
                      tooltip: 'الانتقال إلى نمط السور النصي',
                      onPressed: _openSurahReaderMode,
                    ),
                    IconButton(
                      icon: const Icon(Icons.bookmark_border_rounded),
                      tooltip: 'حفظ موضع القراءة الحالي',
                      onPressed: _toggleCurrentPageBookmark,
                    ),
                  ],
                  IconButton(
                    icon: const Icon(Icons.find_in_page_outlined),
                    tooltip: 'الانتقال إلى صفحة...',
                    onPressed: _showJumpDialog,
                  ),
                  if (isCompactHeader)
                    PopupMenuButton<_PageModeMenuAction>(
                      tooltip: 'المزيد من خيارات المصحف',
                      icon: const Icon(Icons.more_vert_rounded),
                      onSelected: _handleHeaderMenuAction,
                      itemBuilder: (context) => const [
                        PopupMenuItem<_PageModeMenuAction>(
                          value: _PageModeMenuAction.cycleTheme,
                          child: Row(
                            children: [
                              Icon(Icons.palette_outlined, size: 20),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'تغيير سمة القراءة',
                                  softWrap: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem<_PageModeMenuAction>(
                          value: _PageModeMenuAction.switchToSurahMode,
                          child: Row(
                            children: [
                              Icon(Icons.swap_horiz_rounded, size: 20),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'الانتقال إلى نمط السور النصي',
                                  softWrap: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem<_PageModeMenuAction>(
                          value: _PageModeMenuAction.toggleBookmark,
                          child: Row(
                            children: [
                              Icon(Icons.bookmark_border_rounded, size: 20),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'حفظ موضع القراءة الحالي',
                                  softWrap: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              )
            : null,
        body: Column(
          children: [
            if (_showControls)
              _buildReadingControlsBar(
                context: context,
                isDark: isDark,
                isSepia: isSepia,
                frameColor: frameColor,
              ),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _showControls = !_showControls;
                  });
                },
                child: Column(
                  children: [
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: 604,
                        onPageChanged: _onPageChanged,
                        itemBuilder: (context, index) {
                          final pageNum = index + 1;
                          return _buildMushafPage(pageNum, pageBg, frameColor, textColor, isDark, isSepia);
                        },
                      ),
                    ),

                    // Navigation reserves space below the readable page.
                    if (_showControls)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E2522).withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                            border: Border.all(color: AppColors.accentGold.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
                                tooltip: 'الصفحة السابقة',
                                onPressed: _currentPage > 1 ? () => _jumpToPage(_currentPage - 1) : null,
                              ),
                              Expanded(
                                child: InkWell(
                                  onTap: _showJumpDialog,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'صفحة ${_toArabicIndic(_currentPage)} من ٦٠٤',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.arrow_forward_ios_rounded, size: 20),
                                tooltip: 'الصفحة التالية',
                                onPressed: _currentPage < 604 ? () => _jumpToPage(_currentPage + 1) : null,
                              ),
                            ],
                          ),
                        ),
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

  Widget _buildMushafPage(
    int pageNum,
    Color pageBg,
    Color frameColor,
    Color textColor,
    bool isDark,
    bool isSepia,
  ) {
    return FutureBuilder<List<Ayah>>(
      future: QuranRepository.getAyahsForPage(pageNum),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
        }

        final ayahs = snapshot.data ?? [];
        if (ayahs.isEmpty) {
          return const Center(child: Text('لا توجد آيات في هذه الصفحة'));
        }

        final firstAyah = ayahs.first;

        return ValueListenableBuilder<String?>(
          valueListenable: AyahAudioPlayer.instance.currentPlayingKey,
          builder: (context, playingKey, _) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: pageBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: frameColor, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Page Header: Surah name & Juz
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'الجزء ${_toArabicIndic(firstAyah.juz)}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isDark ? AppColors.softGold : AppColors.primaryGreen,
                          ),
                        ),
                        Text(
                          'الحزب ${_toArabicIndic(firstAyah.hizb)}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isDark ? AppColors.softGold : AppColors.secondaryGreen,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(color: frameColor.withValues(alpha: 0.4), height: 1, thickness: 1),
                  const SizedBox(height: 8),

                  // Page Content
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _renderPageContent(ayahs, playingKey, textColor, isDark, isSepia),
                      ),
                    ),
                  ),

                  // Page Footer: Page Number in Arabic Ornament
                  const SizedBox(height: 6),
                  Divider(color: frameColor.withValues(alpha: 0.4), height: 1, thickness: 1),
                  const SizedBox(height: 6),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                      decoration: BoxDecoration(
                        border: Border.all(color: frameColor, width: 1.2),
                        borderRadius: BorderRadius.circular(12),
                        color: frameColor.withValues(alpha: 0.12),
                      ),
                      child: Text(
                        '﴿ ${_toArabicIndic(pageNum)} ﴾',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppColors.softGold : AppColors.primaryGreen,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  List<Widget> _renderPageContent(
    List<Ayah> ayahs,
    String? playingKey,
    Color textColor,
    bool isDark,
    bool isSepia,
  ) {
    final List<Widget> widgets = [];
    final Map<int, List<Ayah>> groupedBySurah = {};

    for (final a in ayahs) {
      groupedBySurah.putIfAbsent(a.surahId, () => []).add(a);
    }

    groupedBySurah.forEach((surahId, surahAyahs) {
      final firstInSurah = surahAyahs.first;
      // If surah begins on this page
      if (firstInSurah.ayahNumber == 1) {
        widgets.add(
          FutureBuilder<Surah?>(
            future: QuranRepository.getSurahById(surahId),
            builder: (context, snap) {
              final sName = snap.data?.nameAr ?? 'السورة';
              final isMakki = snap.data?.isMakki ?? true;
              final aCount = snap.data?.ayahCount ?? 0;

              return Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF222C27) : const Color(0xFFF0E8D0),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.accentGold, width: 1.2),
                ),
                child: Column(
                  children: [
                    Text(
                      'سورة $sName',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.accentGold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${isMakki ? "مكية" : "مدنية"} — آياتها ${_toArabicIndic(aCount)}',
                      style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : AppColors.mutedText),
                    ),
                  ],
                ),
              );
            },
          ),
        );

        // Basmala (not in Surah 9 At-Tawbah, not separate in Surah 1 Al-Fatiha)
        if (surahId != 9 && surahId != 1) {
          widgets.add(
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Center(
                child: Text(
                  'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.primaryGreen),
                ),
              ),
            ),
          );
        }
      }

      // A continuous paragraph exposes separate text/number nodes on Android.
      // Screen-reader mode uses one explicit focus target per complete verse.
      if (MediaQuery.accessibleNavigationOf(context)) {
        for (final ayah in surahAyahs) {
          final isPlaying = playingKey == '$surahId:${ayah.ayahNumber}';
          widgets.add(
            AyahInteraction(
              key: ValueKey('page-ayah-$surahId-${ayah.ayahNumber}'),
              label:
                  '${QuranAccessibilityService.toScreenReaderText(ayah.cleanTextUthmani)}، الآية ${ayah.ayahNumber}، السورة $surahId',
              isPlaying: isPlaying,
              onTap: () {
                if (isPlaying) {
                  AyahAudioPlayer.instance.stop();
                } else {
                  AyahAudioPlayer.instance.playAyah(
                    context,
                    ayah.surahId,
                    ayah.ayahNumber,
                  );
                }
              },
              onLongPress: () async {
                final surah = await QuranRepository.getSurahById(ayah.surahId);
                if (surah != null && context.mounted) {
                  AyahActionSheet.show(context, surah: surah, ayah: ayah);
                }
              },
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: isPlaying
                      ? AppColors.accentGold.withValues(alpha: 0.18)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${ayah.cleanTextUthmani} ﴿${SettingsService.instance.formatAyahNumber(ayah.ayahNumber)}﴾',
                  textAlign: TextAlign.justify,
                  style: TextStyle(
                    fontSize: _fontSize,
                    height: 2.1,
                    color: isPlaying ? AppColors.accentGold : textColor,
                    fontWeight: isPlaying ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }
        return;
      }

      // Continuous Ayah RichText: Ayah text followed immediately by its number (e.g. قل هو الله احد 1 الله الصمد 2)
      widgets.add(
        AyahKeyboardFocus(
          initialIndex: widget.highlightAyah != null && widget.highlightSurah == surahId
              ? surahAyahs.indexWhere((a) => a.ayahNumber == widget.highlightAyah)
              : null,
          segmentLengths: [
            for (final a in surahAyahs)
              '${a.cleanTextUthmani} '.length + '﴿${SettingsService.instance.formatAyahNumber(a.ayahNumber)}﴾ '.length,
          ],
          onPlay: (i) {
            final a = surahAyahs[i];
            final key = AyahAudioPlayer.instance.currentPlayingKey.value;
            if (key == '$surahId:${a.ayahNumber}') {
              AyahAudioPlayer.instance.stop();
            } else {
              AyahAudioPlayer.instance.playAyah(context, a.surahId, a.ayahNumber);
            }
          },
          onOpen: (i) async {
            final a = surahAyahs[i];
            final surah = await QuranRepository.getSurahById(a.surahId);
            if (surah != null && context.mounted) {
              AyahActionSheet.show(context, surah: surah, ayah: a);
            }
          },
          builder: (context, activeIndex, paragraphKey) => RichText(
          key: paragraphKey,
          textAlign: TextAlign.justify,
          text: TextSpan(
            children: surahAyahs.asMap().entries.expand((entry) {
              final ayah = entry.value;
              final isKb = activeIndex == entry.key;
              final isPlaying = playingKey == '$surahId:${ayah.ayahNumber}';
              void playOrStopAyah() {
                if (isPlaying) {
                  AyahAudioPlayer.instance.stop();
                } else {
                  AyahAudioPlayer.instance.playAyah(
                    context,
                    ayah.surahId,
                    ayah.ayahNumber,
                  );
                }
              }

              Future<void> openAyahOptions() async {
                final surah = await QuranRepository.getSurahById(ayah.surahId);
                if (surah != null && context.mounted) {
                  AyahActionSheet.show(
                    context,
                    surah: surah,
                    ayah: ayah,
                  );
                }
              }

              final ayahRec = AyahGestureRecognizer(
                onAyahTap: playOrStopAyah,
                onAyahLongPress: openAyahOptions,
              );
              final numRec = AyahGestureRecognizer(
                onAyahTap: playOrStopAyah,
                onAyahLongPress: openAyahOptions,
              );
              _pageRecognizers.add(ayahRec);
              _pageRecognizers.add(numRec);

              final formattedNumber = SettingsService.instance.formatAyahNumber(ayah.ayahNumber);
              final isTarget = widget.highlightAyah != null &&
                  ayah.surahId == widget.highlightSurah &&
                  ayah.ayahNumber == widget.highlightAyah;

              return [
                TextSpan(
                  text: '${ayah.cleanTextUthmani} ',
                  semanticsLabel: '${isTarget ? 'العلامة المرجعية. ' : ''}${QuranAccessibilityService.toScreenReaderText(ayah.cleanTextUthmani)} ${ayah.ayahNumber}',
                  recognizer: ayahRec,
                  style: TextStyle(
                    fontSize: _fontSize,
                    height: 2.1,
                    color: isPlaying ? AppColors.accentGold : textColor,
                    backgroundColor: isPlaying ? AppColors.accentGold.withValues(alpha: 0.18) : (isTarget ? AppColors.accentGold.withValues(alpha: 0.30) : isKb ? AppColors.primaryGreen.withValues(alpha: 0.22) : Colors.transparent),
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
                  recognizer: numRec,
                  style: TextStyle(
                    fontFamily: 'Amiri',
                    fontSize: _fontSize * 0.92,
                    height: 2.1,
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
        ),
      );
    });

    return widgets;
  }
}
