import '../../core/services/settings_service.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/models/surah.dart';
import '../../core/models/ayah.dart';
import '../../core/services/quran_repository.dart';
import '../../core/services/quran_search_service.dart';
import '../../core/text/arabic_normalizer.dart';
import '../../core/theme/app_theme.dart';
import '../mushaf/surah_reader_screen.dart';
import '../mushaf/page_mode_mushaf_screen.dart';
import '../mushaf/widgets/tafsir_viewer_sheet.dart';
import 'widgets/quran_voice_search_sheet.dart';

enum SearchScope {
  all,
  ayahs,
  surahs,
}

class QuranSearchScreen extends StatefulWidget {
  final String? initialQuery;

  const QuranSearchScreen({super.key, this.initialQuery});

  @override
  State<QuranSearchScreen> createState() => _QuranSearchScreenState();
}

class _QuranSearchScreenState extends State<QuranSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounceTimer;
  int _searchGeneration = 0;

  SearchScope _scope = SearchScope.all;
  int? _selectedSurahFilter;
  List<Surah> _allSurahs = [];

  QuranReferenceMatch? _referenceMatch;
  Ayah? _referenceAyah;
  Surah? _referenceSurah;

  List<Surah> _surahResults = [];
  List<AyahSearchResult> _ayahResults = [];
  List<String> _history = [];

  bool _isLoading = false;
  String _currentQuery = '';
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _controller.text = widget.initialQuery!;
      _onSearchChanged(widget.initialQuery!);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchGeneration++;
    _controller.dispose();
    super.dispose();
  }

  void _showHistoryError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _loadHistory({bool Function()? isCurrent}) async {
    try {
      final history = await QuranSearchService.instance.getSearchHistory();
      if (mounted && (isCurrent?.call() ?? true)) {
        setState(() => _history = history);
      }
    } catch (_) {
      if (mounted && (isCurrent?.call() ?? true)) {
        _showHistoryError(
            'تعذر تحميل سجل البحث المحفوظ. يمكنك متابعة البحث.');
      }
    }
  }

  Future<void> _loadInitial() async {
    final surahs = await QuranRepository.loadSurahs();
    if (!mounted) return;
    setState(() => _allSurahs = surahs);
    await _loadHistory();
  }

  void _onSearchChanged(String query) {
    _searchGeneration++;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 200), () {
      _executeSearch(query);
    });
  }

  Future<void> _executeSearch(String query) async {
    _debounceTimer?.cancel();
    final generation = ++_searchGeneration;
    if (!mounted) return;
    final surahFilter = _selectedSurahFilter;
    bool isCurrent() => mounted && generation == _searchGeneration;
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      setState(() {
        _currentQuery = '';
        _referenceMatch = null;
        _referenceAyah = null;
        _referenceSurah = null;
        _surahResults = [];
        _ayahResults = [];
        _isLoading = false;
        _loadError = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _currentQuery = cleanQuery;
      _loadError = null;
    });

    try {
      // 1. Check direct reference (2:255, البقرة 255, آية الكرسي)
      final refMatch = await QuranSearchService.instance.parseReference(cleanQuery);
      Ayah? refAyah;
      Surah? refSurah;
      if (refMatch != null) {
        refAyah = await QuranRepository.getAyah(refMatch.surahId, refMatch.ayahNumber);
        if (_allSurahs.isNotEmpty) {
          refSurah = _allSurahs.firstWhere(
            (s) => s.id == refMatch.surahId,
            orElse: () => _allSurahs.first,
          );
        }
      }

      // 2. Search Surahs
      final surahs = await QuranRepository.searchSurahs(cleanQuery);

      // 3. Search Ayahs
      final ayahs = await QuranSearchService.instance.searchAyahs(
        cleanQuery,
        surahFilter: surahFilter,
        limit: 100,
      );

      if (!isCurrent()) return;

      // Search results do not wait for the optional history write or its queue.
      setState(() {
        _referenceMatch = refMatch;
        _referenceAyah = refAyah;
        _referenceSurah = refSurah;
        _surahResults = surahs;
        _ayahResults = ayahs;
        _isLoading = false;
        _loadError = null;
      });

      // Save to history if search produced results
      if (cleanQuery.length >= 2 && (refMatch != null || surahs.isNotEmpty || ayahs.isNotEmpty)) {
        final saved =
            await QuranSearchService.instance.addToHistory(cleanQuery);
        if (!isCurrent()) return;
        if (saved) {
          await _loadHistory(isCurrent: isCurrent);
        } else {
          _showHistoryError(
              'تعذر تأكيد حفظ سجل البحث. يمكنك متابعة البحث.');
        }
      }
    } catch (_) {
      if (isCurrent()) {
        setState(() {
          _referenceMatch = null;
          _referenceAyah = null;
          _referenceSurah = null;
          _surahResults = [];
          _ayahResults = [];
          _isLoading = false;
          _loadError = 'تعذر تحميل بيانات المصحف للبحث. يرجى المحاولة مرة أخرى.';
        });
      }
    }
  }

  void _selectHistoryItem(String item) {
    _controller.text = item;
    _controller.selection = TextSelection.fromPosition(TextPosition(offset: item.length));
    _executeSearch(item);
  }

  void _copyAyah(Ayah ayah, Surah surah) {
    final text = '${ayah.cleanTextUthmani} ﴿${ayah.ayahNumber}﴾ [سورة ${surah.nameAr}]';
    Clipboard.setData(ClipboardData(text: text)).catchError((_) {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ الآية الكريمة بنجاح')),
    );
  }

  void _shareAyah(Ayah ayah, Surah surah) {
    final text = '${ayah.cleanTextUthmani} ﴿${ayah.ayahNumber}﴾\n[سورة ${surah.nameAr} · صفحة ${ayah.page}]\n\nتمت المشاركة من تطبيق صديق المؤمن';
    try {
      Share.share(text);
    } catch (_) {}
  }

  AlMominTokens get _resultTokens =>
      Theme.of(context).extension<AlMominTokens>() ??
      (Theme.of(context).brightness == Brightness.dark
          ? AppColors.darkTokens
          : AppColors.lightTokens);

  List<TextSpan> _buildHighlightedSpans(String text, String query) {
    if (query.trim().isEmpty) {
      return [TextSpan(text: text)];
    }

    final normQuery = ArabicNormalizer.normalize(query, loose: true);
    final words = text.split(' ');
    final List<TextSpan> spans = [];

    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      final normWord = ArabicNormalizer.normalize(word, loose: true);
      final isMatch = normWord.contains(normQuery) || normQuery.contains(normWord);

      if (isMatch) {
        spans.add(
          TextSpan(
            text: '$word ',
            style: TextStyle(
              color: _resultTokens.goldText,
              fontWeight: FontWeight.bold,
              backgroundColor: _resultTokens.ayahSelected,
            ),
          ),
        );
      } else {
        spans.add(TextSpan(text: '$word '));
      }
    }

    return spans;
  }

  Future<void> _openVoiceSearch() async {
    final query = await QuranVoiceSearchSheet.show(context);
    if (query != null && query.trim().isNotEmpty && mounted) {
      _controller.text = query.trim();
      _executeSearch(query.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasReferenceCard =
        _referenceMatch != null && _referenceAyah != null && _referenceSurah != null;
    final hasVisibleSurahs =
        (_scope == SearchScope.all || _scope == SearchScope.surahs) &&
            _surahResults.isNotEmpty;
    final hasVisibleAyahs =
        (_scope == SearchScope.all || _scope == SearchScope.ayahs) &&
            _ayahResults.isNotEmpty;
    final hasVisibleResults =
        hasReferenceCard || hasVisibleSurahs || hasVisibleAyahs;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final isLargeText = textScale >= 1.35;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: isLargeText ? 80.0 : null,
        titleSpacing: isLargeText ? 8 : null,
        title: const Text(
          'البحث في القرآن الكريم',
          maxLines: 2,
          softWrap: true,
          overflow: TextOverflow.visible,
          style: TextStyle(height: 1.2),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.mic_rounded),
            tooltip: 'البحث الصوتي عن الآيات بالميكروفون',
            onPressed: _openVoiceSearch,
          ),
          if (_currentQuery.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث البحث',
              onPressed: () => _executeSearch(_currentQuery),
            ),
        ],
      ),
      body: Directionality(
        textDirection: SettingsService.instance.textDirection,
        child: Column(
          children: [
            // Search Input Field
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _controller,
                autofocus: widget.initialQuery == null,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                onSubmitted: _executeSearch,
                decoration: InputDecoration(
                  hintText: 'ابحث بآية، كلمة، سورة، أو مرجع (مثال: آية الكرسي، 2:255، الكهف)...',
                  hintStyle: const TextStyle(fontSize: 13),
                  prefixIcon: const Icon(Icons.search, color: AppColors.primaryGreen),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_controller.text.isNotEmpty)
                        IconButton(
                          tooltip: 'إغلاق أو مسح',
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _controller.clear();
                            _executeSearch('');
                          },
                        ),
                      IconButton(
                        tooltip: 'البحث الصوتي عن الآيات',
                        icon: const Icon(Icons.mic_rounded, color: AppColors.primaryGreen),
                        onPressed: _openVoiceSearch,
                      ),
                    ],
                  ),
                  filled: true,
                  fillColor: Colors.grey.withValues(alpha: 0.08),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),

            // Scope & Filter Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ChoiceChip(
                          label: const Text('الكل', style: TextStyle(fontSize: 12)),
                          selected: _scope == SearchScope.all,
                          selectedColor: AppColors.primaryGreen,
                          checkmarkColor: Colors.white,
                          labelStyle: TextStyle(
                            color: _scope == SearchScope.all ? Colors.white : (Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87),
                            fontWeight: _scope == SearchScope.all ? FontWeight.bold : FontWeight.normal,
                          ),
                          onSelected: (_) => setState(() => _scope = SearchScope.all),
                        ),
                        ChoiceChip(
                          label: Text(
                            'الآيات ${_ayahResults.isNotEmpty ? "(${_ayahResults.length})" : ""}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: _scope == SearchScope.ayahs,
                          selectedColor: AppColors.primaryGreen,
                          checkmarkColor: Colors.white,
                          labelStyle: TextStyle(
                            color: _scope == SearchScope.ayahs ? Colors.white : (Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87),
                            fontWeight: _scope == SearchScope.ayahs ? FontWeight.bold : FontWeight.normal,
                          ),
                          onSelected: (_) => setState(() => _scope = SearchScope.ayahs),
                        ),
                        ChoiceChip(
                          label: Text(
                            'السور ${_surahResults.isNotEmpty ? "(${_surahResults.length})" : ""}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: _scope == SearchScope.surahs,
                          selectedColor: AppColors.primaryGreen,
                          checkmarkColor: Colors.white,
                          labelStyle: TextStyle(
                            color: _scope == SearchScope.surahs ? Colors.white : (Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87),
                            fontWeight: _scope == SearchScope.surahs ? FontWeight.bold : FontWeight.normal,
                          ),
                          onSelected: (_) => setState(() => _scope = SearchScope.surahs),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Filter by Surah Button
                  PopupMenuButton<int?>(
                    tooltip: 'تصفية حسب السورة',
                    initialValue: _selectedSurahFilter,
                    icon: Icon(
                      Icons.filter_list,
                      color: _selectedSurahFilter != null ? AppColors.accentGold : AppColors.primaryGreen,
                    ),
                    onSelected: (val) {
                      setState(() => _selectedSurahFilter = val);
                      if (_currentQuery.isNotEmpty) _executeSearch(_currentQuery);
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem<int?>(
                        value: null,
                        child: Text('كافة السور (بدون تصفية)'),
                      ),
                      const PopupMenuDivider(),
                      ..._allSurahs.map(
                        (s) => PopupMenuItem<int?>(
                          value: s.id,
                          child: Text('${s.id}. سورة ${s.nameAr}'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 16),

            // Content Area
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: AppColors.primaryGreen),
                          SizedBox(height: 12),
                          Text('جاري البحث في المصحف الشريف...', style: TextStyle(color: AppColors.lightText)),
                        ],
                      ),
                    )
                  : _currentQuery.isEmpty
                      ? _buildInitialState()
                      : _loadError != null
                          ? _buildErrorState()
                          : !hasVisibleResults
                              ? _buildNoResultsState()
                              : _buildResultsList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInitialState() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_history.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Expanded(
                child: Row(
                  children: [
                    Icon(Icons.history, color: AppColors.primaryGreen, size: 20),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'سجل البحث الأخير',
                        softWrap: true,
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () async {
                  final saved =
                      await QuranSearchService.instance.clearHistory();
                  if (!mounted) return;
                  if (!saved) {
                    _showHistoryError(
                        'تعذر تأكيد حفظ مسح سجل البحث. حاول مرة أخرى.');
                    return;
                  }
                  setState(() => _history = []);
                },
                child: Text(
                  'مسح السجل',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFFFF8A80)
                        : const Color(0xFFB71C1C),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _history.map((item) {
              return InputChip(
                label: Text(item, style: const TextStyle(fontSize: 12)),
                backgroundColor: AppColors.primaryGreen.withValues(alpha: 0.06),
                onPressed: () => _selectHistoryItem(item),
                onDeleted: () async {
                  final saved = await QuranSearchService.instance
                      .removeFromHistory(item);
                  if (!mounted) return;
                  if (!saved) {
                    _showHistoryError(
                        'تعذر تأكيد حفظ حذف البحث من السجل. حاول مرة أخرى.');
                    return;
                  }
                  await _loadHistory();
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
        ],

        const Row(
          children: [
            Icon(Icons.star_outline, color: AppColors.accentGold, size: 20),
            SizedBox(width: 8),
            Text('عمليات بحث مقترحة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            'آية الكرسي',
            'الرحمن الرحيم',
            'سورة الكهف',
            'خواتيم البقرة',
            'الله نور السماوات',
            'آية الدين',
            'سورة الملك',
            'سورة يس',
          ].map((item) {
            return ActionChip(
              avatar: const Icon(Icons.search, size: 16, color: AppColors.primaryGreen),
              label: Text(item, style: const TextStyle(fontSize: 12)),
              backgroundColor: AppColors.accentGold.withValues(alpha: 0.12),
              onPressed: () => _selectHistoryItem(item),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),

        // Search Tips Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkCard : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? Colors.white12 : Colors.grey.shade300),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.lightbulb_outline, color: AppColors.accentGold, size: 20),
                  SizedBox(width: 8),
                  Text('إرشادات البحث:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
              SizedBox(height: 6),
              Text('• يمكنك البحث باسم السورة ورقم الآية: "البقرة 255" أو "18:10".', style: TextStyle(fontSize: 12, height: 1.5)),
              Text('• يمكنك البحث بأسماء الآيات الشهيرة: "آية الكرسي"، "آية الدين"، "خواتيم البقرة".', style: TextStyle(fontSize: 12, height: 1.5)),
              Text('• خوارزمية البحث تتجاهل التشكيل والهمزات والتاء المربوطة تلقائياً.', style: TextStyle(fontSize: 12, height: 1.5)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          key: const ValueKey('search_error_scroll_view'),
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight > 48 ? constraints.maxHeight - 48 : 0,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Color(0xFFB71C1C)),
                  const SizedBox(height: 16),
                  Text(
                    _loadError ?? 'تعذر تحميل بيانات المصحف للبحث. يرجى المحاولة مرة أخرى.',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _executeSearch(_currentQuery),
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    label: const Text(
                      'إعادة المحاولة',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNoResultsState() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          key: const ValueKey('search_no_results_scroll_view'),
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight > 48 ? constraints.maxHeight - 48 : 0,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.search_off, size: 64, color: AppColors.mutedText),
                  const SizedBox(height: 16),
                  Text(
                    'لم يتم العثور على نتائج لـ "$_currentQuery"',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'تأكد من كتابة الكلمة بصورة صحيحة أو جرب البحث بكلمة واحدة أو بدون (ال) التعريف.',
                    style: TextStyle(color: AppColors.lightText, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildResultsList() {
    final colors = Theme.of(context).colorScheme;
    final tokens = _resultTokens;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // 1. Prominent Reference Match Card (FR-SRC-002)
        if (_referenceMatch != null && _referenceAyah != null && _referenceSurah != null) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colors.primary.withValues(alpha: 0.08),
                  AppColors.accentGold.withValues(alpha: 0.12),
                ],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.accentGold, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: AppColors.accentGold,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.auto_awesome, color: Colors.black, size: 18),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _referenceMatch!.title,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: colors.primary),
                          ),
                          if (_referenceMatch!.aliasNote != null)
                            Text(
                              _referenceMatch!.aliasNote!,
                              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'صفحة ${_referenceAyah!.page}',
                        style: TextStyle(color: colors.onPrimary, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '${_referenceAyah!.cleanTextUthmani} ﴿${_referenceAyah!.ayahNumber}﴾',
                  style: TextStyle(
                    fontFamily: 'Amiri',
                    fontSize: 18,
                    height: 1.6,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.menu_book, size: 16),
                        label: const Text('فتح في المصحف', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.primary,
                          foregroundColor: colors.onPrimary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PageModeMushafScreen(initialPage: _referenceAyah!.page),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: Icon(Icons.chrome_reader_mode_outlined, size: 16, color: colors.primary),
                        label: Text('التفسير', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colors.primary)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: colors.primary),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          TafsirViewerSheet.show(
                            context,
                            surah: _referenceSurah!,
                            ayah: _referenceAyah!,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],

        // 2. Surah Results Section
        if ((_scope == SearchScope.all || _scope == SearchScope.surahs) && _surahResults.isNotEmpty) ...[
          Row(
            children: [
              Icon(Icons.bookmark_outline, size: 18, color: colors.primary),
              const SizedBox(width: 6),
              Text(
                'نتائج السور (${_surahResults.length})',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: colors.primary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._surahResults.map((surah) {
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: colors.primary.withValues(alpha: 0.1),
                  child: Text('${surah.id}', style: TextStyle(color: colors.primary, fontWeight: FontWeight.bold)),
                ),
                title: Text('سورة ${surah.nameAr}', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${surah.isMakki ? "مكية" : "مدنية"} · آياتها: ${surah.ayahCount} · صفحة ${surah.pageStart}'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SurahReaderScreen(surah: surah),
                    ),
                  );
                },
              ),
            );
          }),
          const SizedBox(height: 16),
        ],

        // 3. Ayahs Results Section
        if ((_scope == SearchScope.all || _scope == SearchScope.ayahs) && _ayahResults.isNotEmpty) ...[
          Row(
            children: [
              Icon(Icons.format_quote, size: 18, color: colors.primary),
              const SizedBox(width: 6),
              Text(
                'نتائج الآيات (${_ayahResults.length})',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: colors.primary),
              ),
              if (_selectedSurahFilter != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.accentGold.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('مصفى حسب السورة', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: colors.primary)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          ..._ayahResults.map((result) {
            final ayah = result.ayah;
            final surah = result.surah;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 1.5,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header: Surah and Ayah Info
                    SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: colors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'سورة ${surah.nameAr} : آية ${ayah.ayahNumber}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                                color: colors.primary,
                              ),
                            ),
                          ),
                          Text(
                            'صفحة ${ayah.page} · جزء ${ayah.juz}',
                            style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Ayah Text with Highlighted Query Words (FR-SRC-003)
                    RichText(
                      text: TextSpan(
                        style: TextStyle(
                          fontFamily: 'Amiri',
                          fontSize: 17,
                          height: 1.6,
                          color: colors.onSurface,
                        ),
                        children: [
                          ..._buildHighlightedSpans(ayah.cleanTextUthmani, result.query),
                          TextSpan(
                            text: ' ﴿${ayah.ayahNumber}﴾',
                            style: TextStyle(color: tokens.goldText, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Action Buttons
                    SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          TextButton.icon(
                            icon: Icon(Icons.chrome_reader_mode_outlined, size: 16, color: colors.primary),
                            label: Text('التفسير', style: TextStyle(fontSize: 11.5, color: colors.primary)),
                            onPressed: () => TafsirViewerSheet.show(context, surah: surah, ayah: ayah),
                          ),
                          TextButton.icon(
                            icon: Icon(Icons.auto_stories_rounded, size: 16, color: colors.primary),
                            label: Text('المصحف', style: TextStyle(fontSize: 11.5, color: colors.primary)),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PageModeMushafScreen(initialPage: ayah.page),
                                ),
                              );
                            },
                          ),
                          IconButton(
                            icon: Icon(Icons.copy, size: 16, color: colors.primary),
                            tooltip: 'نسخ الآية',
                            onPressed: () => _copyAyah(ayah, surah),
                          ),
                          IconButton(
                            icon: Icon(Icons.share, size: 16, color: colors.primary),
                            tooltip: 'مشاركة الآية',
                            onPressed: () => _shareAyah(ayah, surah),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }
}
