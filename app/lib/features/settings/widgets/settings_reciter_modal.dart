import '../../../core/text/arabic_normalizer.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/audio/ayah_audio_player.dart';

void showSettingsReciterModal(BuildContext context, {String? selectedReciter, ValueChanged<String>? onStage}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ReciterSelectionSheet(selectedReciter: selectedReciter, onStage: onStage),
  );
}

class _ReciterSelectionSheet extends StatefulWidget {
  const _ReciterSelectionSheet({this.selectedReciter, this.onStage});
  final String? selectedReciter;
  final ValueChanged<String>? onStage;

  @override
  State<_ReciterSelectionSheet> createState() => _ReciterSelectionSheetState();
}

class _ReciterSelectionSheetState extends State<_ReciterSelectionSheet> {
  String _searchQuery = '';
  String _selectedCategory = 'الكل';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final textScale = media.textScaler.scale(1.0);
    final isLargeText = textScale >= 1.35;
    final bottomInset = media.viewInsets.bottom;
    final availableHeight = (media.size.height - bottomInset).clamp(240.0, media.size.height);
    final sheetHeight = bottomInset > 0
        ? availableHeight * 0.94
        : media.size.height * (isLargeText ? 0.90 : 0.85);

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentReciterId = widget.selectedReciter ?? SettingsService.instance.selectedReciterId;

    const allReciters = SettingsService.availableReciters;
    final normRecQ = ArabicNormalizer.normalize(_searchQuery, loose: true);
    final filteredReciters = allReciters.where((r) {
      final matchesQuery = _searchQuery.isEmpty ||
          r.nameAr.contains(_searchQuery) ||
          ArabicNormalizer.normalize(r.nameAr, loose: true).contains(normRecQ) ||
          r.style.contains(_searchQuery) ||
          ArabicNormalizer.normalize(r.style, loose: true).contains(normRecQ) ||
          r.id.contains(_searchQuery.toLowerCase());
      final matchesCategory = _selectedCategory == 'الكل' || r.style == _selectedCategory;
      return matchesQuery && matchesCategory;
    }).toList();

    final countBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.accentGold.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '${filteredReciters.length} قارئ',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: AppColors.primaryGreen,
        ),
      ),
    );

    final headerIcon = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.primaryGreen.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.record_voice_over_rounded,
        color: AppColors.primaryGreen,
        size: 22,
      ),
    );

    final headerSection = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: isLargeText
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    headerIcon,
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'اختر القارئ الافتراضي للتلاوة',
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primaryGreen,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'القارئ الحالي: ${SettingsService.availableReciters.firstWhere((r) => r.id == currentReciterId, orElse: () => SettingsService.availableReciters.first).nameAr}',
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isDark ? Colors.white70 : AppColors.mutedText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    countBadge,
                  ],
                ),
              ],
            )
          : Row(
              children: [
                headerIcon,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'اختر القارئ الافتراضي للتلاوة',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primaryGreen,
                        ),
                      ),
                      Text(
                        'القارئ الحالي: ${SettingsService.availableReciters.firstWhere((r) => r.id == currentReciterId, orElse: () => SettingsService.availableReciters.first).nameAr}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isDark ? Colors.white70 : AppColors.mutedText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                countBadge,
              ],
            ),
    );

    final searchSection = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'ابحث باسم القارئ (مثل: المنشاوي، الحصري، عبد الباسط)...',
          hintStyle: const TextStyle(fontSize: 13),
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primaryGreen, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  tooltip: 'إغلاق أو مسح',
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: isDark ? const Color(0xFF1E2522) : AppColors.primaryGreen.withValues(alpha: 0.06),
          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (val) {
          setState(() => _searchQuery = val.trim());
        },
      ),
    );

    final chipsSection = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: ['الكل', 'مرتل', 'مجود', 'المعلم', 'تلاوة خاشعة'].map((cat) {
          final isCatSelected = _selectedCategory == cat;
          return Padding(
            padding: const EdgeInsets.only(left: 6),
            child: FilterChip(
              label: Text(
                cat,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isCatSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isCatSelected ? Colors.white : AppColors.primaryGreen,
                ),
              ),
              selected: isCatSelected,
              selectedColor: AppColors.primaryGreen,
              backgroundColor: isDark ? const Color(0xFF242A27) : AppColors.primaryGreen.withValues(alpha: 0.08),
              checkmarkColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              onSelected: (_) {
                setState(() => _selectedCategory = cat);
              },
            ),
          );
        }).toList(),
      ),
    );

    final emptyState = Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.withValues(alpha: 0.5)),
            const SizedBox(height: 10),
            Text(
              'لم يتم العثور على قارئ يطابق "$_searchQuery"',
              textAlign: TextAlign.center,
              softWrap: true,
              style: const TextStyle(color: AppColors.mutedText, fontSize: 13.5),
            ),
          ],
        ),
      ),
    );

    Widget buildReciterCard(int index) {
      final r = filteredReciters[index];
      final isSelected = currentReciterId == r.id;
      final isMinshawi = r.id == 'minshawi_murattal';

      final selectedBadge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.accentGold.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text(
          'محدد 🎧',
          style: TextStyle(
            color: AppColors.primaryGreen,
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
      );

      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryGreen.withValues(alpha: 0.10)
              : (isDark ? const Color(0xFF1B221E) : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppColors.accentGold
                : (isDark ? Colors.white12 : Colors.grey.shade200),
            width: isSelected ? 1.8 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.accentGold.withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: Semantics(
            button: true,
            selected: isSelected,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () async {
                if (widget.onStage != null) {
                  widget.onStage!(r.id);
                  Navigator.pop(context);
                  return;
                }
                await SettingsService.instance.setSelectedReciter(r.id);
                final playing = await AyahAudioPlayer.instance.playReciterPreview(r);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        playing
                            ? 'تم اعتماد القارئ: ${r.nameAr}، تم تشغيل عينته.'
                            : 'تم اعتماد القارئ: ${r.nameAr}، والعينة متوقفة أو غير متاحة. يمكنك إعادة المحاولة أو اختيار قارئ آخر بنفسك؛ لم يتم تشغيل قارئ بديل.',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      backgroundColor: AppColors.primaryGreen,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: isSelected
                            ? const LinearGradient(
                                colors: [Color(0xFFD4AF37), Color(0xFFB89628)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        color: isSelected
                            ? null
                            : (isDark ? const Color(0xFF28342E) : AppColors.primaryGreen.withValues(alpha: 0.08)),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isSelected ? Icons.check_rounded : Icons.person_rounded,
                        color: isSelected ? Colors.white : AppColors.primaryGreen,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            r.nameAr,
                            softWrap: true,
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                              fontSize: 14.5,
                              color: isSelected ? AppColors.primaryGreen : null,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white10 : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  r.style,
                                  style: const TextStyle(fontSize: 11, color: AppColors.mutedText),
                                ),
                              ),
                              const Text(
                                'رواية حفص عن عاصم',
                                softWrap: true,
                                style: TextStyle(fontSize: 11, color: AppColors.mutedText),
                              ),
                              if (isMinshawi)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.accentGold.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'الافتراضي ⭐',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primaryGreen,
                                    ),
                                  ),
                                ),
                              if (isSelected && isLargeText) selectedBadge,
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (isSelected && !isLargeText) ...[
                      const SizedBox(width: 8),
                      selectedBadge,
                    ] else if (!isSelected) ...[
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14,
                        color: Colors.grey,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final useUnifiedScroll = isLargeText || bottomInset > 0;

    return Directionality(
      textDirection: SettingsService.instance.textDirection,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Container(
          height: sheetHeight,
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              if (useUnifiedScroll)
                Expanded(
                  child: CustomScrollView(
                    key: const ValueKey('reciter_modal_scroll_view'),
                    slivers: [
                      SliverToBoxAdapter(child: headerSection),
                      SliverToBoxAdapter(child: searchSection),
                      SliverToBoxAdapter(child: chipsSection),
                      const SliverToBoxAdapter(child: SizedBox(height: 6)),
                      if (filteredReciters.isEmpty)
                        SliverToBoxAdapter(child: emptyState)
                      else
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          sliver: SliverList.builder(
                            itemCount: filteredReciters.length,
                            itemBuilder: (ctx, index) => buildReciterCard(index),
                          ),
                        ),
                    ],
                  ),
                )
              else ...[
                headerSection,
                searchSection,
                chipsSection,
                const SizedBox(height: 6),
                Expanded(
                  child: filteredReciters.isEmpty
                      ? SingleChildScrollView(child: emptyState)
                      : ListView.builder(
                          key: const ValueKey('reciter_modal_scroll_view'),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          itemCount: filteredReciters.length,
                          itemBuilder: (ctx, index) => buildReciterCard(index),
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
