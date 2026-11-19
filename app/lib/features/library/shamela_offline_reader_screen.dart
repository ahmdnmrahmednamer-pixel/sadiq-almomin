import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../core/services/settings_service.dart';
import '../../core/services/shamela_epub_service.dart';
import '../../core/theme/app_theme.dart';

class ShamelaOfflineReaderScreen extends StatefulWidget {
  final OfflineShamelaBook book;
  final int? initialIndex;
  final ShamelaEpubService? epubService;

  const ShamelaOfflineReaderScreen({
    super.key,
    required this.book,
    this.initialIndex,
    this.epubService,
  });

  @override
  State<ShamelaOfflineReaderScreen> createState() =>
      _ShamelaOfflineReaderScreenState();
}

class _ShamelaOfflineReaderScreenState
    extends State<ShamelaOfflineReaderScreen> {
  late final ShamelaEpubService _epubService;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _jumpController = TextEditingController();
  final FocusNode _jumpFocusNode = FocusNode();

  final Map<int, double> _scrollOffsets = {};
  int _currentIndex = 0;
  double _fontSize = 19.0;
  bool _isRestoringPosition = true;

  @override
  void initState() {
    super.initState();
    _epubService = widget.epubService ?? ShamelaEpubService();
    _initPosition();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _jumpController.dispose();
    _jumpFocusNode.dispose();
    super.dispose();
  }

  Future<void> _initPosition() async {
    int targetIndex = widget.initialIndex ?? 0;
    if (widget.initialIndex == null) {
      try {
        final saved = await _epubService.getLastPosition(widget.book.id);
        if (saved != null && saved >= 0 && saved < widget.book.pageCount) {
          targetIndex = saved;
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _currentIndex = _clampIndex(targetIndex);
      _jumpController.text = (_currentIndex + 1).toString();
      _isRestoringPosition = false;
    });

    _announcePage(_currentIndex);
  }

  int _clampIndex(int index) {
    if (widget.book.pageCount <= 0) return 0;
    if (index < 0) return 0;
    if (index >= widget.book.pageCount) return widget.book.pageCount - 1;
    return index;
  }

  void _announce(String message) {
    if (message.isEmpty) return;
    try {
      SemanticsService.announce(message, TextDirection.rtl);
    } catch (_) {}
  }

  void _announcePage(int index) {
    final page = widget.book.getPage(index);
    final buffer = StringBuffer();
    buffer.write('الصفحة ${index + 1} من ${widget.book.pageCount}');
    if (page != null) {
      if (page.volume != null && page.volume!.isNotEmpty) {
        buffer.write('، ${page.volume}');
      }
      if (page.pageNumber != null && page.pageNumber!.isNotEmpty) {
        buffer.write('، ص ${page.pageNumber}');
      }
      if (page.title.isNotEmpty) {
        buffer.write('، ${page.title}');
      }
    }
    _announce(buffer.toString());
  }

  void _goToIndex(int targetIndex) {
    final clamped = _clampIndex(targetIndex);
    if (clamped == _currentIndex && !_isRestoringPosition) return;

    if (_scrollController.hasClients) {
      _scrollOffsets[_currentIndex] = _scrollController.offset;
    }

    setState(() {
      _currentIndex = clamped;
      _jumpController.text = (clamped + 1).toString();
    });

    _epubService.saveLastPosition(widget.book.id, clamped);
    _announcePage(clamped);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final previousOffset = _scrollOffsets[clamped] ?? 0.0;
        _scrollController.jumpTo(previousOffset);
      }
    });
  }

  void _jumpToInput() {
    final text = _jumpController.text.trim();
    final pageNum = int.tryParse(text);
    if (pageNum == null || pageNum < 1 || pageNum > widget.book.pageCount) {
      _announce('يرجى إدخال رقم صفحة بين 1 و ${widget.book.pageCount}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('يرجى إدخال رقم صفحة بين 1 و ${widget.book.pageCount}'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    _jumpFocusNode.unfocus();
    _goToIndex(pageNum - 1);
  }

  void _showTocBottomSheet() {
    final tocEntries = widget.book.flattenedToc;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Directionality(
          textDirection: SettingsService.instance.textDirection,
          child: SafeArea(
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.75,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Theme.of(ctx).dividerColor,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'فهرس الكتاب',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: tocEntries.isEmpty
                        ? const Center(
                            child: Text('لا يوجد فهرس معتمد متاح لهذا الكتاب'),
                          )
                        : ListView.builder(
                            itemCount: tocEntries.length,
                            itemBuilder: (c, i) {
                              final entry = tocEntries[i];
                              final isValid = entry.spineIndex >= 0 &&
                                  entry.spineIndex < widget.book.pageCount;
                              final isCurrent =
                                  entry.spineIndex == _currentIndex;

                              return Padding(
                                padding: EdgeInsetsDirectional.only(
                                  start: (entry.depth * 16.0).clamp(0.0, 64.0),
                                ),
                                child: ListTile(
                                  enabled: isValid,
                                  selected: isCurrent,
                                  dense: true,
                                  title: Text(
                                    entry.label.isNotEmpty
                                        ? entry.label
                                        : 'قسم بدون عنوان',
                                    style: TextStyle(
                                      fontWeight: isCurrent
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: isCurrent
                                          ? AppColors.primaryGreen
                                          : null,
                                    ),
                                  ),
                                  subtitle: isValid
                                      ? Text('صفحة ${entry.spineIndex + 1}')
                                      : const Text('غير متوفر'),
                                  trailing: isValid
                                      ? const Icon(
                                          Icons.arrow_forward_ios_rounded,
                                          size: 12)
                                      : null,
                                  onTap: isValid
                                      ? () {
                                          Navigator.of(ctx).pop();
                                          _goToIndex(entry.spineIndex);
                                        }
                                      : null,
                                ),
                              );
                            },
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final page = widget.book.getPage(_currentIndex);

    return Directionality(
      textDirection: SettingsService.instance.textDirection,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.book.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (widget.book.author.isNotEmpty)
                Text(
                  widget.book.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey.shade400 : AppColors.mutedText,
                  ),
                ),
            ],
          ),
          actions: [
            Semantics(
              button: true,
              enabled: true,
              label: 'الفهرس',
              excludeSemantics: true,
              onTap: _showTocBottomSheet,
              child: IconButton(
                icon: const Icon(Icons.list_alt_rounded),
                tooltip: 'الفهرس',
                onPressed: _showTocBottomSheet,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.text_decrease_rounded),
              tooltip: 'تصغير الخط',
              onPressed: _fontSize > 14
                  ? () {
                      setState(() => _fontSize -= 1.5);
                      _announce('حجم الخط $_fontSize');
                    }
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.text_increase_rounded),
              tooltip: 'تكبير الخط',
              onPressed: _fontSize < 34
                  ? () {
                      setState(() => _fontSize += 1.5);
                      _announce('حجم الخط $_fontSize');
                    }
                  : null,
            ),
          ],
        ),
        body: Column(
          children: [
            _buildPositionHeader(page, isDark),
            Expanded(
              child: _buildPageBody(page, isDark),
            ),
            _buildBottomNav(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildPositionHeader(OfflineShamelaPage? page, bool isDark) {
    final buffer =
        StringBuffer('الصفحة ${_currentIndex + 1} من ${widget.book.pageCount}');
    if (page != null && page.volume != null && page.volume!.trim().isNotEmpty) {
      final v = page.volume!.trim();
      buffer.write('، ${v.startsWith("الجزء") ? v : "الجزء $v"}');
    }
    if (page != null && page.pageNumber != null && page.pageNumber!.trim().isNotEmpty) {
      final p = page.pageNumber!.trim();
      buffer.write(
          '، ${p.startsWith("الصفحة المطبوعة") ? p : "الصفحة المطبوعة $p"}');
    }
    final positionLabel = buffer.toString();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2822) : const Color(0xFFF1F6F2),
        border: Border(
          bottom: BorderSide(
            color: AppColors.primaryGreen.withValues(alpha: 0.15),
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.menu_book_rounded,
            size: 18,
            color: AppColors.primaryGreen,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              header: true,
              label: positionLabel,
              child: Text(
                positionLabel,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryGreen,
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'أوفلاين',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryGreen,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageBody(OfflineShamelaPage? page, bool isDark) {
    if (_isRestoringPosition) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryGreen),
      );
    }

    if (page == null || page.text.trim().isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            'الصفحة رقم ${_currentIndex + 1} فارغة أو غير متوفرة',
            style: TextStyle(
              fontSize: 15,
              color: isDark ? Colors.grey.shade400 : AppColors.mutedText,
            ),
          ),
        ),
      );
    }

    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (page.title.isNotEmpty) ...[
              Text(
                page.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Amiri',
                  color: AppColors.accentGold,
                ),
              ),
              const SizedBox(height: 14),
            ],
            SelectableText(
              page.text,
              textAlign: TextAlign.justify,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontSize: _fontSize,
                height: 1.85,
                fontFamily: 'Amiri',
                color: isDark
                    ? Colors.white.withValues(alpha: 0.94)
                    : const Color(0xFF1B231F),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav(bool isDark) {
    final canGoPrev = _currentIndex > 0;
    final canGoNext = _currentIndex < widget.book.pageCount - 1;

    return Container(
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141D19) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.grey.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            enabled: canGoPrev,
            label: 'السابق',
            excludeSemantics: true,
            onTap: canGoPrev ? () => _goToIndex(_currentIndex - 1) : null,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              label: const Text(
                'السابق',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                foregroundColor: AppColors.primaryGreen,
                side: BorderSide(
                  color: AppColors.primaryGreen.withValues(alpha: 0.35),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: canGoPrev ? () => _goToIndex(_currentIndex - 1) : null,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF1E2822) : const Color(0xFFF3F5F3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.grey.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  const Text(
                    'ص:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Semantics(
                      label: 'رقم الصفحة للانتقال السريع',
                      textField: true,
                      child: TextField(
                        controller: _jumpController,
                        focusNode: _jumpFocusNode,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.go,
                        textAlign: TextAlign.center,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onSubmitted: (_) => _jumpToInput(),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.subdirectory_arrow_left_rounded,
                      color: AppColors.primaryGreen,
                      size: 18,
                    ),
                    tooltip: 'انتقال',
                    onPressed: _jumpToInput,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Semantics(
            button: true,
            enabled: canGoNext,
            label: 'التالي',
            excludeSemantics: true,
            onTap: canGoNext ? () => _goToIndex(_currentIndex + 1) : null,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.arrow_back_ios_rounded, size: 14),
              label: const Text(
                'التالي',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: canGoNext ? () => _goToIndex(_currentIndex + 1) : null,
            ),
          ),
        ],
      ),
    );
  }
}
