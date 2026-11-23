import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/settings_service.dart';
import '../../core/text/arabic_normalizer.dart';
import '../../core/theme/app_theme.dart';

import 'widgets/reader_bookmarks_sheet.dart';

class _ShamelaPageData {
  final int bookId;
  final int pageId;
  final String fullTitle;
  final String? part;
  final String? pageInPart;
  final List<String> paragraphs;
  final DateTime timestamp;

  const _ShamelaPageData({
    required this.bookId,
    required this.pageId,
    required this.fullTitle,
    this.part,
    this.pageInPart,
    required this.paragraphs,
    required this.timestamp,
  });

  int get pageNumber => pageId;

  Map<String, dynamic> toJson() => {
        'bookId': bookId,
        'pageId': pageId,
        'pageNumber': pageId,
        'fullTitle': fullTitle,
        'part': part,
        'pageInPart': pageInPart,
        'paragraphs': paragraphs,
        'timestamp': timestamp.toIso8601String(),
      };

  factory _ShamelaPageData.fromJson(Map<String, dynamic> json) =>
      _ShamelaPageData(
        bookId: json['bookId'] as int? ?? 0,
        pageId: json['pageId'] as int? ?? json['pageNumber'] as int? ?? 1,
        fullTitle: json['fullTitle'] as String? ?? '',
        part: json['part'] as String?,
        pageInPart: json['pageInPart'] as String?,
        paragraphs: (json['paragraphs'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
      );
}

class ShamelaBookReaderScreen extends StatefulWidget {
  final int bookId;
  final String bookTitle;
  final String? author;
  final int? initialPage;
  final Dio? dio;
  final Directory? rootDir;

  const ShamelaBookReaderScreen({
    super.key,
    required this.bookId,
    required this.bookTitle,
    this.author,
    this.initialPage,
    this.dio,
    this.rootDir,
  });

  @override
  State<ShamelaBookReaderScreen> createState() =>
      _ShamelaBookReaderScreenState();
}

class _ShamelaBookReaderScreenState extends State<ShamelaBookReaderScreen> {
  late final Dio _dio;
  final TextEditingController _jumpController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _jumpFocusNode = FocusNode();

  late int _currentPage;
  bool _isLoading = false;
  bool _isOfflineCache = false;
  String? _errorMessage;

  _ShamelaPageData? _pageData;
  double _fontSize = 19.0;

  static const String _prefsPrefix = 'shamela_last_page_';

  @override
  void initState() {
    super.initState();
    _dio = widget.dio ??
        Dio(
          BaseOptions(
            baseUrl: 'https://shamela.ws',
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 12),
            sendTimeout: const Duration(seconds: 10),
            headers: const {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
              'Referer': 'https://shamela.ws/',
            },
          ),
        );

    _currentPage = widget.initialPage ?? 1;
    _jumpController.text = _currentPage.toString();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initAndLoadInitialPage();
    });
  }

  @override
  void dispose() {
    _jumpController.dispose();
    _scrollController.dispose();
    _jumpFocusNode.dispose();
    if (widget.dio == null) {
      _dio.close(force: true);
    }
    super.dispose();
  }

  void _announce(String message) {
    if (message.isEmpty) return;
    try {
      SemanticsService.announce(message, TextDirection.rtl);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[shamela_book_reader_screen] $e');
      }
    }
  }

  Future<void> _initAndLoadInitialPage() async {
    if (widget.initialPage != null && widget.initialPage! > 0) {
      _loadPage(widget.initialPage!);
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedPage = prefs.getInt('$_prefsPrefix${widget.bookId}');
      if (savedPage != null && savedPage > 0) {
        _currentPage = savedPage;
        _jumpController.text = savedPage.toString();
        _announce(
            'استعادة موضع القراءة السابق لكتاب ${widget.bookTitle}: صفحة $savedPage');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[shamela_book_reader_screen] $e');
      }
    }

    _loadPage(_currentPage);
  }

  Future<void> _saveLastReadPosition(int page) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('$_prefsPrefix${widget.bookId}', page);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[shamela_book_reader_screen] $e');
      }
    }
  }

  Future<File> _getCacheFile(int page) async {
    final baseDir = widget.rootDir ?? await getApplicationDocumentsDirectory();
    final bookCacheDir =
        Directory('${baseDir.path}/shamela_cache/${widget.bookId}');
    if (!await bookCacheDir.exists()) {
      await bookCacheDir.create(recursive: true);
    }
    return File('${bookCacheDir.path}/page_$page.json');
  }

  Future<void> _loadPage(int page) async {
    if (page < 1) return;

    setState(() {
      _currentPage = page;
      _jumpController.text = page.toString();
      _isLoading = true;
      _errorMessage = null;
      _isOfflineCache = false;
    });

    _announce('جارٍ تحميل الصفحة $page');

    final cacheFile = await _getCacheFile(page);

    try {
      final response = await _dio.get(
        '/book/${widget.bookId}/$page',
        options: Options(responseType: ResponseType.plain),
      );

      final realUri = response.realUri;
      final isHttps = realUri.scheme.toLowerCase() == 'https';
      final isShamelaHost = realUri.host.toLowerCase() == 'shamela.ws';
      final segments = realUri.pathSegments.where((s) => s.isNotEmpty).toList();
      final isExactBookPath = segments.length == 3 &&
          segments[0] == 'book' &&
          segments[1] == widget.bookId.toString() &&
          segments[2] == page.toString();

      if (!isHttps || !isShamelaHost || !isExactBookPath) {
        throw DioException(
          requestOptions: response.requestOptions,
          error:
              'Invalid response URL ($realUri). Expected https://shamela.ws/book/${widget.bookId}/$page',
        );
      }

      final html = response.data.toString();
      final parsed = _parseShamelaHtml(html, page);

      try {
        await cacheFile.writeAsString(jsonEncode(parsed.toJson()));
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[shamela_book_reader_screen] $e');
        }
      }

      if (!mounted) return;
      setState(() {
        _pageData = parsed;
        _isLoading = false;
        _isOfflineCache = false;
      });

      await _saveLastReadPosition(page);
      _announcePageContent(parsed, fromCache: false);
      _scrollToTop();
    } catch (e) {
      if (await cacheFile.exists()) {
        try {
          final cachedText = await cacheFile.readAsString();
          final jsonMap = jsonDecode(cachedText) as Map<String, dynamic>;
          final parsed = _ShamelaPageData.fromJson(jsonMap);

          if (parsed.bookId != widget.bookId ||
              parsed.pageId != page ||
              parsed.paragraphs.isEmpty) {
            try {
              await cacheFile.delete();
            } catch (e) {
              if (kDebugMode) {
                debugPrint('[shamela_book_reader_screen] $e');
              }
            }
            throw const FormatException('Cached page corrupted or mismatched');
          }

          if (!mounted) return;
          setState(() {
            _pageData = parsed;
            _isLoading = false;
            _isOfflineCache = true;
          });

          await _saveLastReadPosition(page);
          _announcePageContent(parsed, fromCache: true);
          _scrollToTop();
          return;
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[shamela_book_reader_screen] $e');
          }
        }
      }

      if (!mounted) return;
      const failureMessage =
          'تعذر الاتصال بالشبكة ولا تتوفر نسخة مخزنة مسبقاً لهذه الصفحة.';
      setState(() {
        _isLoading = false;
        _isOfflineCache = false;
        _errorMessage = failureMessage;
        _pageData = null;
      });
      _announce('فشل الاتصال بالشبكة، ولا توجد نسخة محفوظة للصفحة $page.');
    }
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _announcePageContent(_ShamelaPageData data, {required bool fromCache}) {
    final buffer = StringBuffer();
    if (fromCache) {
      buffer.write('قراءة من النسخة المحفوظة أوفلاين. ');
    }
    if (data.part != null && data.pageInPart != null) {
      buffer.write('الجزء ${data.part}، الصفحة ${data.pageInPart}');
    } else if (data.pageInPart != null) {
      buffer.write('الصفحة ${data.pageInPart}');
    } else {
      buffer.write('الصفحة $_currentPage');
    }

    if (data.paragraphs.isNotEmpty) {
      buffer.write('، تم تحميل ${data.paragraphs.length} فقرة');
    }
    _announce(buffer.toString());
  }

  _ShamelaPageData _parseShamelaHtml(String html, int requestPage) {
    final document = html_parser.parse(html);

    final titleElement = document.querySelector('title');
    final rawTitle = titleElement?.text.trim() ?? '';

    String? part;
    String? pageInPart;

    final partMatch = RegExp(r'ج\s*(\d+)').firstMatch(rawTitle);
    if (partMatch != null) {
      part = partMatch.group(1);
    }

    final pageMatch = RegExp(r'ص\s*(\d+)').firstMatch(rawTitle);
    if (pageMatch != null) {
      pageInPart = pageMatch.group(1);
    }

    final nass = document.querySelector('div.nass');
    if (nass == null) {
      throw FormatException(
          'Missing div.nass for book ${widget.bookId} page $requestPage');
    }

    const disallowedTags = {
      'script',
      'style',
      'iframe',
      'object',
      'svg',
      'form',
      'button',
      'noscript',
    };
    for (final tag in disallowedTags) {
      nass.querySelectorAll(tag).forEach((el) => el.remove());
    }

    nass
        .querySelectorAll('.btn_tag, .anchor, .fa-copy')
        .forEach((el) => el.remove());
    for (final a in nass.querySelectorAll('a')) {
      if (a.classes.contains('btn_tag') ||
          a.querySelector('.fa-copy') != null) {
        a.remove();
      }
    }

    const blockTags = {
      'p',
      'div',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'blockquote',
      'li',
      'hr',
      'tr',
      'table',
      'section',
      'article',
    };

    final paragraphs = <String>[];
    StringBuffer currentBuffer = StringBuffer();

    void flushBuffer() {
      final text = currentBuffer.toString().trim();
      if (text.isNotEmpty) {
        paragraphs.add(text);
      }
      currentBuffer = StringBuffer();
    }

    void traverse(dom.Node node) {
      if (node is dom.Text) {
        currentBuffer.write(node.text);
        return;
      }
      if (node is dom.Element) {
        final tag = node.localName?.toLowerCase() ?? '';
        final isBlock = blockTags.contains(tag);
        final isFootnoteBlock = node.classes.contains('footnote') ||
            node.classes.contains('note') ||
            node.classes.contains('fnt');

        if (isBlock || isFootnoteBlock) {
          flushBuffer();
        } else if (tag == 'br') {
          currentBuffer.write('\n');
        }

        for (final child in node.nodes) {
          traverse(child);
        }

        if (isBlock || isFootnoteBlock) {
          flushBuffer();
        }
      }
    }

    for (final node in nass.nodes) {
      traverse(node);
    }
    flushBuffer();

    if (paragraphs.isEmpty) {
      throw FormatException(
          'Empty div.nass content for book ${widget.bookId} page $requestPage');
    }

    return _ShamelaPageData(
      bookId: widget.bookId,
      pageId: requestPage,
      fullTitle: rawTitle,
      part: part,
      pageInPart: pageInPart,
      paragraphs: paragraphs,
      timestamp: DateTime.now(),
    );
  }

  void _jumpToPageInput() {
    final text = _jumpController.text.trim();
    final targetPage = ArabicNormalizer.tryParseInt(text);
    if (targetPage == null || targetPage < 1) {
      _announce('يرجى كتابة رقم صفحة صحيح أكبر من صفر');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال رقم صفحة صحيح'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    _jumpFocusNode.unfocus();
    _loadPage(targetPage);
  }

  void _copyCurrentPageText() {
    if (_pageData == null || _pageData!.paragraphs.isEmpty) {
      _announce('لا يوجد نص في الصفحة لنسخه');
      return;
    }

    final fullText = _pageData!.paragraphs.join('\n\n');
    Clipboard.setData(ClipboardData(text: fullText));
    _announce('تم نسخ نص الصفحة بالكامل إلى الحافظة');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم نسخ نص الصفحة إلى الحافظة بنجاح'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showBookmarks() async {
    final mark = await showReaderBookmarks(context,
      documentId: 'shamela:${widget.bookId}', locationKind: 'online-page',
      page: _currentPage,
      scrollOffset: _scrollController.hasClients ? _scrollController.offset : 0,
      pageLabel: 'الصفحة $_currentPage',
    );
    if (mark == null || !mounted) return;
    await _loadPage(mark.page);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients && _currentPage == mark.page && _errorMessage == null) {
        _scrollController.jumpTo(mark.scrollOffset.clamp(0.0, _scrollController.position.maxScrollExtent));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: SettingsService.instance.textDirection,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.bookTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (widget.author != null && widget.author!.isNotEmpty)
                Text(
                  widget.author!,
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
            IconButton(
              icon: const Icon(Icons.bookmarks_outlined),
              tooltip: 'العلامات المرجعية',
              onPressed: _showBookmarks,
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
            IconButton(
              icon: const Icon(Icons.copy_rounded),
              tooltip: 'نسخ نص الصفحة',
              onPressed: _copyCurrentPageText,
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'إعادة التحميل',
              onPressed: _isLoading ? null : () => _loadPage(_currentPage),
            ),
          ],
        ),
        body: Column(
          children: [
            _buildPositionHeader(isDark),
            Expanded(
              child: _buildBodyContent(isDark),
            ),
            _buildNavigationBottomBar(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildPositionHeader(bool isDark) {
    final part = _pageData?.part;
    final pageInPart = _pageData?.pageInPart;

    final headerText = StringBuffer();
    if (part != null && part.isNotEmpty) {
      headerText.write('الجزء $part  •  ');
    }
    if (pageInPart != null && pageInPart.isNotEmpty) {
      headerText.write('صفحة $pageInPart');
    } else {
      headerText.write('صفحة $_currentPage');
    }

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
          Icon(
            Icons.menu_book_rounded,
            size: 18,
            color: AppColors.primaryGreen.withValues(alpha: 0.9),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              header: true,
              label: 'موضع القراءة الحالي: ${headerText.toString()}',
              child: Text(
                headerText.toString(),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryGreen,
                ),
              ),
            ),
          ),
          if (_isOfflineCache)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: Colors.amber.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_off_rounded,
                    size: 13,
                    color:
                        isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'مخزن أوفلاين',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? Colors.amber.shade200
                          : Colors.amber.shade900,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBodyContent(bool isDark) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              strokeWidth: 3,
              color: AppColors.primaryGreen,
            ),
            const SizedBox(height: 16),
            Text(
              'جارٍ جلب الصفحة $_currentPage...',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.wifi_off_rounded,
                  size: 42,
                  color: Colors.redAccent,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'الصفحة المطلوبة: $_currentPage',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.grey.shade400 : AppColors.mutedText,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('حاول مجدداً'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => _loadPage(_currentPage),
              ),
            ],
          ),
        ),
      );
    }

    final paragraphs = _pageData?.paragraphs ?? [];
    if (paragraphs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            'الصفحة رقم $_currentPage فارغة أو لا تتضمن نصوصاً مسندة.',
            textAlign: TextAlign.center,
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
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        itemCount: paragraphs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final paragraphText = paragraphs[index];

          return Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: SelectableText(
              paragraphText,
              textAlign: TextAlign.justify,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontSize: _fontSize,
                height: 1.85,
                fontFamily: 'Amiri',
                fontWeight: FontWeight.normal,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.94)
                    : const Color(0xFF1B231F),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNavigationBottomBar(bool isDark) {
    final canGoPrevious = _currentPage > 1 && !_isLoading;
    final canGoNext = !_isLoading;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        final baseStyle = Theme.of(context).textTheme.bodyLarge!;
        double measure(String value, double size) {
          final painter = TextPainter(
            text: TextSpan(
              text: value,
              style: baseStyle.copyWith(
                  fontSize: size, fontWeight: FontWeight.bold),
            ),
            textDirection: TextDirection.rtl,
            textScaler: scaler,
          )..layout();
          final width = painter.width;
          painter.dispose();
          return width;
        }

        double buttonWidth(String label) {
          final width = measure(label, 13) + 14 + 8 + 24;
          return width < 64 ? 64 : width;
        }

        var numberWidth = 0.0;
        for (final digit in '0123456789٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹'.split('')) {
          final width = measure(List.filled(6, digit).join(), 14);
          if (width > numberWidth) numberWidth = width;
        }
        final minimumInputWidth =
            numberWidth + measure('ص:', 12) + 6 + 16 + 48 + 4;
        final useTwoRows = constraints.maxWidth <
            buttonWidth('السابق') +
                buttonWidth('التالي') +
                minimumInputWidth +
                16;
        final controls = <Widget>[
          OutlinedButton.icon(
            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
            label: const Text(
              'السابق',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              foregroundColor: scheme.primary,
              side: BorderSide(
                color: scheme.primary.withValues(alpha: 0.35),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: canGoPrevious ? () => _loadPage(_currentPage - 1) : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 8),
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
                  Text(
                    'ص:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _jumpController,
                      focusNode: _jumpFocusNode,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.go,
                      textAlign: TextAlign.center,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9٠-٩۰-۹]'),
                        ),
                      ],
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        hintText: 'رقم الصفحة',
                      ),
                      onSubmitted: (_) => _jumpToPageInput(),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.subdirectory_arrow_left_rounded,
                      color: scheme.primary,
                      size: 20,
                    ),
                    tooltip: 'انتقال',
                    onPressed: _isLoading ? null : _jumpToPageInput,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 48, minHeight: 48),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.arrow_back_ios_rounded, size: 14),
            label: const Text(
              'التالي',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: canGoNext ? () => _loadPage(_currentPage + 1) : null,
          ),
        ];
        if (useTwoRows) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              (controls[2] as Expanded).child,
              const SizedBox(height: 8),
              Row(children: [controls.first, const Spacer(), controls.last]),
            ],
          );
        }
        return Row(children: controls);
      }),
    );
  }
}
