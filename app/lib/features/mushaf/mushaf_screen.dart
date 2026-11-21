import '../../core/text/arabic_normalizer.dart';
import 'package:flutter/material.dart';
import '../../core/models/surah.dart';
import '../../core/models/juz.dart';
import '../../core/services/quran_repository.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/app_theme.dart';
import '../search/quran_search_screen.dart';
import '../search/widgets/quran_voice_search_sheet.dart';
import 'surah_reader_screen.dart';
import 'page_mode_mushaf_screen.dart';
import '../khatma/khatma_screen.dart';
import 'quran_hub_screen.dart';

enum _MushafHeaderAction {
  pageMode,
  khatma,
  voiceSearch,
  quranHub,
  quickSearch,
}

class MushafScreen extends StatefulWidget {
  /// Optional test seam for verifying compact/2.0x header action callback
  /// dispatch without laying out unrelated destination screens at 2.0x.
  @visibleForTesting
  final WidgetBuilder? Function(String actionId, {String? searchQuery})?
      headerDestinationBuilderForTesting;

  /// Optional test seam for verifying voice search header callback dispatch.
  @visibleForTesting
  final Future<String?> Function(BuildContext context)?
      voiceSearchLauncherForTesting;

  /// 0 surahs, 1 juz, 2 pages, 3 bookmarks.
  final int initialTab;

  const MushafScreen({
    super.key,
    this.initialTab = 0,
    this.headerDestinationBuilderForTesting,
    this.voiceSearchLauncherForTesting,
  });

  @override
  State<MushafScreen> createState() => _MushafScreenState();
}

class _MushafScreenState extends State<MushafScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Surah> _surahs = [];
  List<Surah> _filteredSurahs = [];
  List<Juz> _juzList = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this, initialIndex: widget.initialTab.clamp(0, 3));
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadData() async {
    final surahs = await QuranRepository.loadSurahs();
    final juz = await QuranRepository.loadJuz();
    if (mounted) {
      setState(() {
        _surahs = surahs;
        _filteredSurahs = surahs;
        _juzList = juz;
        _isLoading = false;
      });
    }
  }

  void _filterSurahs(String q) {
    setState(() {
      _searchQuery = q.trim();
      if (_searchQuery.isEmpty) {
        _filteredSurahs = _surahs;
      } else {
        final normQ = ArabicNormalizer.normalize(_searchQuery, loose: true);
        _filteredSurahs = _surahs.where((s) {
          return s.nameAr.contains(_searchQuery) ||
                 ArabicNormalizer.normalize(s.nameAr, loose: true).contains(normQ) ||
                 s.nameSimple.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                 s.id.toString() == normQ;
        }).toList();
      }
    });
  }

  String _toArabicIndic(int number) {
    const arabicDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return number.toString().split('').map((char) {
      final digit = int.tryParse(char);
      return digit != null ? arabicDigits[digit] : char;
    }).join();
  }

  void _openPageMode() {
    final builder =
        widget.headerDestinationBuilderForTesting?.call('pageMode') ??
            (context) => PageModeMushafScreen(
                  initialPage: SettingsService.instance.lastReadPageNumber,
                );
    Navigator.push(
      context,
      MaterialPageRoute(builder: builder),
    );
  }

  void _openKhatma() {
    final builder =
        widget.headerDestinationBuilderForTesting?.call('khatma') ??
            (context) => const KhatmaScreen();
    Navigator.push(
      context,
      MaterialPageRoute(builder: builder),
    );
  }

  Future<void> _openVoiceSearch() async {
    final launcher =
        widget.voiceSearchLauncherForTesting ?? QuranVoiceSearchSheet.show;
    final query = await launcher(context);
    if (!mounted) return;
    if (query != null && query.trim().isNotEmpty) {
      final trimmed = query.trim();
      final builder = widget.headerDestinationBuilderForTesting?.call(
            'voiceSearchResult',
            searchQuery: trimmed,
          ) ??
          (context) => QuranSearchScreen(initialQuery: trimmed);
      Navigator.push(
        context,
        MaterialPageRoute(builder: builder),
      );
    }
  }

  void _openQuranHub() {
    final builder =
        widget.headerDestinationBuilderForTesting?.call('quranHub') ??
            (context) => const QuranHubScreen();
    Navigator.push(
      context,
      MaterialPageRoute(builder: builder),
    );
  }

  void _openQuickSearch() {
    final builder =
        widget.headerDestinationBuilderForTesting?.call('quickSearch') ??
            (context) => const QuranSearchScreen();
    Navigator.push(
      context,
      MaterialPageRoute(builder: builder),
    );
  }

  void _handleHeaderAction(_MushafHeaderAction action) {
    switch (action) {
      case _MushafHeaderAction.pageMode:
        _openPageMode();
        break;
      case _MushafHeaderAction.khatma:
        _openKhatma();
        break;
      case _MushafHeaderAction.voiceSearch:
        _openVoiceSearch();
        break;
      case _MushafHeaderAction.quranHub:
        _openQuranHub();
        break;
      case _MushafHeaderAction.quickSearch:
        _openQuickSearch();
        break;
    }
  }

  PopupMenuItem<_MushafHeaderAction> _buildOverflowItem({
    required _MushafHeaderAction value,
    required IconData icon,
    required String label,
    required Color iconColor,
  }) {
    return PopupMenuItem<_MushafHeaderAction>(
      value: value,
      child: Directionality(
        textDirection: SettingsService.instance.textDirection,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(icon, color: iconColor, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  softWrap: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final textScale = MediaQuery.textScalerOf(context).scale(16) / 16.0;
    final showAllInlineActions = screenWidth >= 600 && textScale < 1.35;
    final showPrimarySearchInline = !showAllInlineActions && screenWidth >= 360 && textScale < 1.35;
    final tabHeight = textScale >= 1.35 ? 60.0 : 46.0;

    final overflowItems = <PopupMenuEntry<_MushafHeaderAction>>[
      if (!showPrimarySearchInline)
        _buildOverflowItem(
          value: _MushafHeaderAction.quickSearch,
          icon: Icons.search,
          label: 'البحث القرآني السريع',
          iconColor: colorScheme.primary,
        ),
      _buildOverflowItem(
        value: _MushafHeaderAction.pageMode,
        icon: Icons.auto_stories_rounded,
        label: 'فتح المصحف بالصفحات الكاملة (604)',
        iconColor: colorScheme.primary,
      ),
      _buildOverflowItem(
        value: _MushafHeaderAction.khatma,
        icon: Icons.bookmark_add_outlined,
        label: 'مخطط الختمات والورد القرآني',
        iconColor: colorScheme.primary,
      ),
      _buildOverflowItem(
        value: _MushafHeaderAction.voiceSearch,
        icon: Icons.mic_rounded,
        label: 'البحث الصوتي عن الآيات',
        iconColor: colorScheme.primary,
      ),
      _buildOverflowItem(
        value: _MushafHeaderAction.quranHub,
        icon: Icons.dashboard_customize_rounded,
        label: 'بوابة علوم القرآن والتفاسير',
        iconColor: colorScheme.primary,
      ),
    ];

    return Directionality(
      textDirection: SettingsService.instance.textDirection,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: showAllInlineActions,
          titleSpacing: showAllInlineActions ? NavigationToolbar.kMiddleSpacing : 4,
          title: Semantics(
            header: true,
            label: 'المصحف الشريف',
            excludeSemantics: true,
            child: const Text('المصحف الشريف'),
          ),
          actions: showAllInlineActions
              ? [
                  IconButton(
                    icon: const Icon(Icons.auto_stories_rounded),
                    tooltip: 'فتح المصحف بالصفحات الكاملة (604)',
                    onPressed: _openPageMode,
                  ),
                  IconButton(
                    icon: const Icon(Icons.bookmark_add_outlined),
                    tooltip: 'مخطط الختمات والورد القرآني',
                    onPressed: _openKhatma,
                  ),
                  IconButton(
                    icon: const Icon(Icons.mic_rounded),
                    tooltip: 'البحث الصوتي عن الآيات',
                    onPressed: _openVoiceSearch,
                  ),
                  IconButton(
                    icon: const Icon(Icons.dashboard_customize_rounded),
                    tooltip: 'بوابة علوم القرآن والتفاسير',
                    onPressed: _openQuranHub,
                  ),
                  IconButton(
                    icon: const Icon(Icons.search),
                    tooltip: 'البحث القرآني السريع',
                    onPressed: _openQuickSearch,
                  ),
                ]
              : [
                  if (showPrimarySearchInline)
                    IconButton(
                      icon: const Icon(Icons.search),
                      tooltip: 'البحث القرآني السريع',
                      onPressed: _openQuickSearch,
                    ),
                  PopupMenuButton<_MushafHeaderAction>(
                    key: const ValueKey('mushaf_header_overflow_menu'),
                    icon: const Icon(Icons.more_vert_rounded),
                    tooltip: 'خيارات المصحف',
                    constraints: BoxConstraints(
                      minWidth: 220,
                      maxWidth: (screenWidth - 32).clamp(220.0, 360.0),
                    ),
                    onSelected: _handleHeaderAction,
                    itemBuilder: (_) => overflowItems,
                  ),
                ],
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: colorScheme.primary,
            indicatorWeight: 3,
            dividerColor: colorScheme.outlineVariant,
            labelColor: colorScheme.primary,
            unselectedLabelColor: colorScheme.onSurfaceVariant,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
            tabs: [
              Tab(height: tabHeight, text: 'السور (١١٤)'),
              Tab(height: tabHeight, text: 'الأجزاء (٣٠)'),
              Tab(height: tabHeight, text: 'صفحات المصحف (٦٠٤)'),
              Tab(height: tabHeight, text: 'العلامات المرجعية'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
            : Column(
                children: [
                  // Prominent Banner to Open 604 Pages Reader Mode
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PageModeMushafScreen(
                              initialPage: SettingsService.instance.lastReadPageNumber,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.primaryGreen, AppColors.secondaryGreen],
                            begin: Alignment.topRight,
                            end: Alignment.bottomLeft,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryGreen.withValues(alpha: 0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.accentGold.withValues(alpha: 0.25),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.menu_book_rounded, color: AppColors.softGold, size: 24),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'عرض صفحات المصحف الشريف (٦٠٤ صفحات)',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'متابعة من صفحة ${SettingsService.instance.lastReadPageNumber} (سورة ${SettingsService.instance.lastReadSurahName})',
                                    style: const TextStyle(color: AppColors.softGold, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios, color: AppColors.softGold, size: 14),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Quick Quran Tools Bar
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          _buildQuickActionChip(
                            icon: Icons.bookmark_add_outlined,
                            label: 'مخطط الختمات',
                            color: AppColors.primaryGreen,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const KhatmaScreen()),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildQuickActionChip(
                            icon: Icons.search_rounded,
                            label: 'البحث القرآني',
                            color: const Color(0xFF1B4332),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const QuranSearchScreen()),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Tab Views
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        // Tab 1: Surahs list (114)
                        Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                              child: TextField(
                                onChanged: _filterSurahs,
                                decoration: InputDecoration(
                                  hintText: 'ابحث باسم السورة أو رقمها...',
                                  prefixIcon: const Icon(Icons.search, size: 20),
                                  contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  filled: true,
                                  fillColor: Colors.grey.withValues(alpha: 0.06),
                                ),
                              ),
                            ),
                            Expanded(
                              child: ListView.separated(
                                itemCount: _filteredSurahs.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final surah = _filteredSurahs[index];
                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: AppColors.primaryGreen.withValues(alpha: 0.08),
                                      child: Text(
                                        '${surah.id}',
                                        style: const TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    title: Text('سورة ${surah.nameAr}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                    subtitle: Text(
                                      '${surah.isMakki ? "مكية" : "مدنية"} — آياتها ${surah.ayahCount} — صفحة ${surah.pageStart}',
                                      style: const TextStyle(fontSize: 13, color: AppColors.mutedText),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.auto_stories, color: AppColors.primaryGreen, size: 20),
                                          tooltip: 'فتح بالصفحات المصحفية',
                                          onPressed: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => PageModeMushafScreen(initialPage: surah.pageStart),
                                              ),
                                            );
                                          },
                                        ),
                                        const Icon(Icons.arrow_forward_ios, size: 14),
                                      ],
                                    ),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => SurahReaderScreen(surah: surah),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        ),

                        // Tab 2: Juz list (30)
                        ListView.separated(
                          itemCount: _juzList.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final juz = _juzList[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppColors.secondaryGreen.withValues(alpha: 0.1),
                                child: Text(
                                  '${juz.id}',
                                  style: const TextStyle(color: AppColors.secondaryGreen, fontWeight: FontWeight.bold),
                                ),
                              ),
                              title: Text('الجزء ${juz.id} (${juz.nameAr})', style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('صفحة ${juz.pageStart} — بداية السورة رقم ${juz.startSurah}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.auto_stories, color: AppColors.secondaryGreen, size: 20),
                                    tooltip: 'فتح بالصفحات',
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => PageModeMushafScreen(initialPage: juz.pageStart),
                                        ),
                                      );
                                    },
                                  ),
                                  const Icon(Icons.arrow_forward_ios, size: 14),
                                ],
                              ),
                              onTap: () async {
                                final surah = await QuranRepository.getSurahById(juz.startSurah);
                                if (mounted && surah != null) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => SurahReaderScreen(surah: surah, initialAyah: juz.startAyah),
                                    ),
                                  );
                                }
                              },
                            );
                          },
                        ),

                        // Tab 3: Pages (1 to 604)
                        ListView.builder(
                          itemCount: 604,
                          itemBuilder: (context, index) {
                            final pageNum = index + 1;
                            return FutureBuilder<PageMetadata?>(
                              future: QuranRepository.getPageMetadata(pageNum),
                              builder: (context, snap) {
                                final meta = snap.data;
                                final surahName = meta?.surahName ?? '...';
                                final juz = meta?.juzNumber ?? 1;

                                return ListTile(
                                  leading: Container(
                                    width: 44,
                                    height: 44,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      border: Border.all(color: AppColors.accentGold),
                                      borderRadius: BorderRadius.circular(10),
                                      color: AppColors.accentGold.withValues(alpha: 0.08),
                                    ),
                                    child: Text(
                                      _toArabicIndic(pageNum),
                                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryGreen),
                                    ),
                                  ),
                                  title: Text('صفحة ${_toArabicIndic(pageNum)} — سورة $surahName', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text('الجزء ${_toArabicIndic(juz)}'),
                                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => PageModeMushafScreen(initialPage: pageNum),
                                      ),
                                    );
                                  },
                                );
                              },
                            );
                          },
                        ),

                        // Tab 4: Real Saved Bookmarks
                        AnimatedBuilder(
                          animation: SettingsService.instance,
                          builder: (context, _) {
                            final bookmarks = SettingsService.instance.bookmarks;
                            if (bookmarks.isEmpty) {
                              return Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.bookmark_border_rounded, size: 64, color: Colors.grey.withValues(alpha: 0.4)),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'لا توجد علامات مرجعية محفوظة بعد',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'لا توجد آيات محفوظة',
                                      style: TextStyle(color: AppColors.mutedText, fontSize: 13),
                                    ),
                                  ],
                                ),
                              );
                            }

                            return FutureBuilder<List<BookmarkDetail>>(
                              future: QuranRepository.getBookmarksDetails(bookmarks),
                              builder: (context, snap) {
                                if (snap.connectionState == ConnectionState.waiting) {
                                  return const Center(child: CircularProgressIndicator());
                                }
                                final details = snap.data ?? [];
                                if (details.isEmpty) {
                                  return const Center(child: Text('جاري تحميل العلامات...'));
                                }

                                return ListView.separated(
                                  padding: const EdgeInsets.all(16),
                                  itemCount: details.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                                  itemBuilder: (context, index) {
                                    final b = details[index];
                                    return Card(
                                      elevation: 2,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      child: ListTile(
                                        leading: const Icon(Icons.bookmark, color: AppColors.accentGold, size: 30),
                                        title: Text('سورة ${b.surahName} — الآية ${_toArabicIndic(b.ayahNumber)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                        subtitle: Text(
                                          '${b.textSnippet}\nصفحة ${_toArabicIndic(b.pageNumber)}',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        trailing: IconButton(
                                          tooltip: 'حذف',
                                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                          onPressed: () async {
                                            await SettingsService.instance.toggleBookmark(b.surahId, b.ayahNumber);
                                            if (!mounted) return;
                                          },
                                        ),
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => PageModeMushafScreen(
                                                initialPage: b.pageNumber,
                                                highlightSurah: b.surahId,
                                                highlightAyah: b.ayahNumber,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    );
                                  },
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildQuickActionChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

