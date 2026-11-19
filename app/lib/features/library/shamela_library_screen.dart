import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/services/settings_service.dart';
import '../../core/services/shamela_epub_service.dart';
import '../../core/services/shamela_library_service.dart';
import '../../core/theme/app_theme.dart';
import 'shamela_book_reader_screen.dart';
import 'shamela_offline_reader_screen.dart';

class ShamelaLibraryScreen extends StatefulWidget {
  final String? initialQuery;
  final ShamelaLibraryService? libraryService;
  final ShamelaEpubService? epubService;

  const ShamelaLibraryScreen({
    super.key,
    this.initialQuery,
    this.libraryService,
    this.epubService,
  });

  @override
  State<ShamelaLibraryScreen> createState() => _ShamelaLibraryScreenState();
}

class _ShamelaLibraryScreenState extends State<ShamelaLibraryScreen>
    with SingleTickerProviderStateMixin {
  late final ShamelaLibraryService _service;
  late final ShamelaEpubService _epubService;
  late final TabController _tabController;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _searchButtonFocusNode = FocusNode();

  bool _isLoading = false;
  bool _hasSearched = false;
  bool _isConnectionError = false;
  String? _errorMessage;
  String _lastSearchedQuery = '';
  List<ShamelaBook> _results = [];

  bool _ignoreTashkeel = true;
  String _filterType = 'all';

  // Saved books management
  List<OfflineShamelaBook> _savedBooks = [];
  Set<int> _savedBookIds = {};
  bool _loadingSavedBooks = false;

  // Active downloads state
  final Map<int, double> _downloadProgress = {};
  final Map<int, CancelToken> _cancelTokens = {};
  final Map<int, String> _downloadErrors = {};

  static const List<String> _suggestedQueries = [
    'صحيح البخاري',
    'تفسير ابن كثير',
    'زاد المعاد',
    'المغني لابن قدامة',
    'رياض الصالحين',
    'صحيح مسلم',
  ];

  @override
  void initState() {
    super.initState();
    _service = widget.libraryService ?? ShamelaLibraryService.instance;
    _epubService = widget.epubService ?? ShamelaEpubService();
    _tabController = TabController(length: 2, vsync: this);

    _loadSavedBooks();

    if (widget.initialQuery != null && widget.initialQuery!.trim().isNotEmpty) {
      _searchController.text = widget.initialQuery!.trim();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _performSearch();
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchButtonFocusNode.dispose();
    for (final token in _cancelTokens.values) {
      token.cancel('Screen disposed');
    }
    super.dispose();
  }

  Future<void> _loadSavedBooks() async {
    setState(() => _loadingSavedBooks = true);
    try {
      final list = await _epubService.listSavedBooks();
      if (mounted) {
        setState(() {
          _savedBooks = list;
          _savedBookIds = list.map((b) => b.id).toSet();
          _loadingSavedBooks = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingSavedBooks = false);
      }
    }
  }

  void _announce(String message) {
    if (message.isEmpty) return;
    try {
      SemanticsService.announce(message, TextDirection.rtl);
    } catch (_) {}
  }

  bool _checkIsConnectionError(dynamic error) {
    if (error == null) return false;
    final errStr = error.toString().toLowerCase();
    return errStr.contains('socket') ||
        errStr.contains('connection') ||
        errStr.contains('timeout') ||
        errStr.contains('network') ||
        errStr.contains('failed host lookup') ||
        errStr.contains('no internet') ||
        errStr.contains('handshake') ||
        errStr.contains('offline');
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      _announce('يرجى إدخال عبارة البحث أولاً');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('يرجى كتابة اسم الكتاب أو المؤلف للبحث'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      _searchFocusNode.requestFocus();
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isConnectionError = false;
      _hasSearched = true;
      _lastSearchedQuery = query;
    });

    _announce('جاري البحث عن $query في الأقسام الشرعية...');

    try {
      final results = await _service.searchBooks(
        query,
        filterType: _filterType,
        ignoreTashkeel: _ignoreTashkeel,
      );

      if (!mounted) return;

      setState(() {
        _results = results;
        _isLoading = false;
      });

      if (results.isEmpty) {
        if (_service.lastError != null) {
          final isConn = _checkIsConnectionError(_service.lastError);
          final msg = isConn
              ? 'تعذر الاتصال بالمكتبة الشاملة، يرجى التحقق من اتصال الإنترنت.'
              : 'حدث خطأ أثناء جلب النتائج، يرجى المحاولة لاحقاً.';
          setState(() {
            _isConnectionError = isConn;
            _errorMessage = msg;
          });
          _announce(msg);
        } else {
          final msg =
              'لم يتم العثور على أي كتب تطابق «$query» في الأقسام الشرعية المعتمدة.';
          setState(() {
            _errorMessage = msg;
          });
          _announce(msg);
        }
      } else {
        _announce('تم العثور على ${results.length} كتاب في نتائج البحث.');
      }
    } catch (e) {
      if (!mounted) return;
      final isConn = _checkIsConnectionError(e);
      final msg = isConn
          ? 'تعذر الاتصال بالمكتبة الشاملة، يرجى التحقق من اتصال الإنترنت.'
          : 'حدث خطأ أثناء البحث، يرجى المحاولة لاحقاً.';
      setState(() {
        _isLoading = false;
        _isConnectionError = isConn;
        _errorMessage = msg;
        _results = [];
      });
      _announce(msg);
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _hasSearched = false;
      _results = [];
      _errorMessage = null;
      _isConnectionError = false;
    });
    _announce('تم مسح نص البحث');
    _searchFocusNode.requestFocus();
  }

  void _openOnlineReader(ShamelaBook book) {
    _announce('فتح قارئ كتاب ${book.title} أونلاين');
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShamelaBookReaderScreen(
          bookId: book.id,
          bookTitle: book.title,
          author: book.author,
        ),
      ),
    );
  }

  void _openOfflineReader(OfflineShamelaBook book) {
    _announce('فتح القارئ المحلي لكتاب ${book.title}');
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShamelaOfflineReaderScreen(
          book: book,
          epubService: _epubService,
        ),
      ),
    );
  }

  Future<void> _openSavedBookById(int bookId) async {
    final book = await _epubService.loadSavedBook(bookId);
    if (!mounted) return;
    if (book != null) {
      _openOfflineReader(book);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحميل بيانات الكتاب المحفوظ')),
      );
    }
  }

  Future<void> _downloadBook(ShamelaBook book) async {
    final cancelToken = CancelToken();
    setState(() {
      _cancelTokens[book.id] = cancelToken;
      _downloadProgress[book.id] = 0.0;
      _downloadErrors.remove(book.id);
    });
    _announce('بدء تنزيل كتاب ${book.title}');

    try {
      final offlineBook = await _epubService.downloadBook(
        book,
        cancelToken: cancelToken,
        onProgress: (received, total) {
          if (mounted) {
            setState(() {
              if (total > 0) {
                _downloadProgress[book.id] = (received / total).clamp(0.0, 1.0);
              } else {
                _downloadProgress[book.id] = -1.0;
              }
            });
          }
        },
      );

      if (!mounted) return;
      setState(() {
        _savedBookIds.add(book.id);
        _downloadProgress.remove(book.id);
        _cancelTokens.remove(book.id);
      });

      await _loadSavedBooks();
      _announce('تم تنزيل كتاب ${book.title} بنجاح، جاري فتح القارئ');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم حفظ «${book.title}» محلياً')),
        );
        _openOfflineReader(offlineBook);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloadProgress.remove(book.id);
        _cancelTokens.remove(book.id);
      });

      if (cancelToken.isCancelled) {
        _announce('تم إلغاء تنزيل الكتاب');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إلغاء التنزيل')),
        );
        return;
      }

      final errorMsg = e is ShamelaEpubUnavailableException
          ? 'التحميل الرسمي غير متوفر لهذا الكتاب من الشاملة'
          : 'تعذر تنزيل الكتاب: $e';

      setState(() {
        _downloadErrors[book.id] = errorMsg;
      });
      _announce(errorMsg);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: Colors.red.shade800,
        ),
      );
    }
  }

  void _cancelDownload(int bookId) {
    _cancelTokens[bookId]?.cancel('Cancelled by user');
  }

  Future<void> _confirmDeleteSavedBook(OfflineShamelaBook book) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: SettingsService.instance.textDirection,
        child: AlertDialog(
          title: const Text('حذف الكتاب المحفوظ'),
          content: Text(
              'هل أنت متأكد من حذف كتاب «${book.title}» نهائياً من الذاكرة المحلية؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('حذف', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      await _epubService.deleteSavedBook(book.id);
      await _loadSavedBooks();
      _announce('تم حذف الكتاب من المحفوظات');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم حذف «${book.title}»')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: SettingsService.instance.textDirection,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المكتبة الشاملة'),
          centerTitle: false,
          actions: [
            if (_hasSearched && !_isLoading)
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'إعادة البحث',
                onPressed: _performSearch,
              ),
          ],
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'بحث الشاملة'),
              Tab(text: 'كتبي المحفوظة'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            Column(
              children: [
                _buildSearchHeader(isDark),
                _buildLiveStatusIndicator(isDark),
                Expanded(child: _buildMainContent(isDark)),
              ],
            ),
            _buildSavedBooksTab(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildSavedBooksTab(bool isDark) {
    if (_loadingSavedBooks) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryGreen),
      );
    }

    if (_savedBooks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: 64,
                color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              const Text(
                'لا توجد كتب محفوظة محلياً',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'يمكنك البحث عن الكتب في التبويب الأول وتنزيلها لتصفحها بالكامل بدون اتصال بالإنترنت.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadSavedBooks,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _savedBooks.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (ctx, i) {
          final book = _savedBooks[i];
          return Card(
            elevation: 0.8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: isDark
                    ? const Color(0xFF2C3A34)
                    : AppColors.primaryGreen.withValues(alpha: 0.12),
              ),
            ),
            color: isDark ? const Color(0xFF16211D) : Colors.white,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _openOfflineReader(book),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            book.title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Amiri',
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: Colors.redAccent),
                          tooltip: 'حذف من المحفوظات',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _confirmDeleteSavedBook(book),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (book.author.isNotEmpty)
                          Text(
                            book.author,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.accentGold,
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1F2D27)
                                : const Color(0xFFF1EBDD),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${book.pageCount} صفحة',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF16211D) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF2C3A34) : const Color(0xFFE2DCCB),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: 'حقل البحث في كتب المكتبة الشاملة',
            hint: 'أدخل اسم الكتاب أو المؤلف واضغط على زر البحث',
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _performSearch(),
              decoration: InputDecoration(
                hintText: 'ابحث في كتب الشاملة الشرعية ومؤلفيها...',
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: AppColors.primaryGreen,
                ),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 20),
                        tooltip: 'مسح نص البحث',
                        onPressed: _clearSearch,
                      ),
                    Padding(
                      padding: const EdgeInsets.only(left: 6, right: 6),
                      child: IconButton.filled(
                        focusNode: _searchButtonFocusNode,
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.primaryGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.all(10),
                        ),
                        icon: _isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : const Icon(Icons.arrow_forward_rounded, size: 20),
                        tooltip: 'بدء البحث في الشاملة',
                        onPressed: _isLoading ? null : _performSearch,
                      ),
                    ),
                  ],
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                filled: true,
                fillColor:
                    isDark ? const Color(0xFF0F1714) : const Color(0xFFF8FAF8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: AppColors.primaryGreen.withValues(alpha: 0.3),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: isDark
                        ? const Color(0xFF2C3A34)
                        : const Color(0xFFE0E5E0),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: AppColors.primaryGreen,
                    width: 2,
                  ),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final choiceLabelMaxWidth =
                  (constraints.maxWidth - 80).clamp(50.0, double.infinity);
              final filterChipWidth =
                  (constraints.maxWidth - 100).clamp(50.0, double.infinity);

              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    avatar: Icon(
                      _ignoreTashkeel
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 16,
                      color: _ignoreTashkeel
                          ? AppColors.primaryGreen
                          : Colors.grey,
                    ),
                    label: SizedBox(
                      width: filterChipWidth,
                      child: const Text(
                        'تجاهل التشكيل والهمزات',
                        softWrap: true,
                        maxLines: 3,
                        overflow: TextOverflow.visible,
                      ),
                    ),
                    selected: _ignoreTashkeel,
                    selectedColor:
                        AppColors.primaryGreen.withValues(alpha: 0.16),
                    checkmarkColor: AppColors.primaryGreen,
                    onSelected: (val) {
                      setState(() => _ignoreTashkeel = val);
                      _announce(
                        val
                            ? 'تم تفعيل تجاهل التشكيل والهمزات'
                            : 'تم إلغاء تفعيل تجاهل التشكيل',
                      );
                      if (_hasSearched && _searchController.text.isNotEmpty) {
                        _performSearch();
                      }
                    },
                  ),
                  _buildFilterChip('all', 'جميع الحقول',
                      maxWidth: choiceLabelMaxWidth),
                  _buildFilterChip('title', 'العناوين فقط',
                      maxWidth: choiceLabelMaxWidth),
                  _buildFilterChip('author', 'المؤلفون فقط',
                      maxWidth: choiceLabelMaxWidth),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String type, String label, {double? maxWidth}) {
    final isSelected = _filterType == type;
    final textWidget = Text(label,
        softWrap: true, maxLines: 3, overflow: TextOverflow.visible);
    return ChoiceChip(
      label: maxWidth != null
          ? ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: textWidget,
            )
          : textWidget,
      selected: isSelected,
      selectedColor: AppColors.accentGold.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? AppColors.accentGold : null,
      ),
      onSelected: (selected) {
        if (selected) {
          setState(() => _filterType = type);
          _announce('تم تحديد تصفية: $label');
          if (_hasSearched && _searchController.text.isNotEmpty) {
            _performSearch();
          }
        }
      },
    );
  }

  Widget _buildLiveStatusIndicator(bool isDark) {
    String statusText = '';
    Color statusColor = Colors.grey;

    if (_isLoading) {
      statusText = 'جاري البحث في فهارس المكتبة الشاملة...';
      statusColor = AppColors.primaryGreen;
    } else if (_isConnectionError) {
      statusText = 'تعذر الاتصال بالمكتبة الشاملة (تحقق من الشبكة)';
      statusColor = Colors.redAccent;
    } else if (_errorMessage != null) {
      statusText = _errorMessage!;
      statusColor = Colors.orange;
    } else if (_hasSearched) {
      statusText = 'تم العثور على ${_results.length} نتيجة بحث';
      statusColor = AppColors.primaryGreen;
    }

    if (statusText.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      color: statusColor.withValues(alpha: isDark ? 0.15 : 0.08),
      child: Row(
        children: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsetsDirectional.only(end: 8),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Icon(
                _isConnectionError
                    ? Icons.wifi_off_rounded
                    : (_errorMessage != null
                        ? Icons.info_outline_rounded
                        : Icons.check_circle_outline_rounded),
                size: 16,
                color: statusColor,
              ),
            ),
          Expanded(
            child: Text(
              statusText,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(bool isDark) {
    if (_isLoading && _results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppColors.primaryGreen),
            const SizedBox(height: 18),
            Text(
              'جاري الاستعلام المباشر من shamela.ws...',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      );
    }

    if (_isConnectionError) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.wifi_off_rounded,
                  size: 56,
                  color: Colors.redAccent,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'تعذر الاتصال بالمكتبة الشاملة',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'يرجى التأكد من اتصال هاتفك بالإنترنت ثم إعادة المحاولة، أو تصفح كتبك المحفوظة أوفلاين.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('إعادة المحاولة الآن'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _performSearch,
              ),
            ],
          ),
        ),
      );
    }

    if (_hasSearched && _results.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 64,
                color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
              ),
              const SizedBox(height: 14),
              Text(
                'لم نجد نتائج تطابق «$_lastSearchedQuery»',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'جرّب كتابة كلمة مفردة من عنوان الكتاب الشرعي، أو ابحث باسم المؤلف (مثل: البخاري، الطبري، النووي).',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_results.isNotEmpty) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _results.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final book = _results[index];
          return _buildBookResultCard(book, index, isDark);
        },
      );
    }

    return _buildInitialExploreView(isDark);
  }

  Widget _buildBookResultCard(ShamelaBook book, int index, bool isDark) {
    final isSaved = _savedBookIds.contains(book.id);
    final isDownloading = _downloadProgress.containsKey(book.id);
    final progress = _downloadProgress[book.id];

    return Card(
      elevation: 0.8,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark
              ? const Color(0xFF2C3A34)
              : AppColors.primaryGreen.withValues(alpha: 0.12),
        ),
      ),
      color: isDark ? const Color(0xFF16211D) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isDark
                          ? [const Color(0xFF0F3628), const Color(0xFF1B4332)]
                          : [const Color(0xFF0F5B45), const Color(0xFF2D6A4F)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.auto_stories_rounded,
                      color: AppColors.accentGold,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Amiri',
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.person_outline_rounded,
                            size: 15,
                            color: AppColors.accentGold,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              book.author,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.accentGold,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1F2D27)
                        : const Color(0xFFF1EBDD),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '#${book.id}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color:
                          isDark ? Colors.grey.shade400 : AppColors.mutedText,
                    ),
                  ),
                ),
              ],
            ),
            if (isDownloading) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value:
                            progress != null && progress >= 0 ? progress : null,
                        color: AppColors.primaryGreen,
                        backgroundColor:
                            AppColors.primaryGreen.withValues(alpha: 0.15),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.cancel_rounded, size: 20),
                    tooltip: 'إلغاء التنزيل',
                    onPressed: () => _cancelDownload(book.id),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(
                      Icons.chrome_reader_mode_outlined,
                      size: 17,
                      color: AppColors.primaryGreen,
                    ),
                    label: const Text(
                      'قراءة أونلاين',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      side: BorderSide(
                        color: AppColors.primaryGreen.withValues(alpha: 0.35),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => _openOnlineReader(book),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: isSaved
                      ? ElevatedButton.icon(
                          icon: const Icon(
                            Icons.check_circle_rounded,
                            size: 17,
                            color: Colors.white,
                          ),
                          label: const Text(
                            'فتح (محفوظ)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryGreen,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () => _openSavedBookById(book.id),
                        )
                      : ElevatedButton.icon(
                          icon: isDownloading
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.download_for_offline_outlined,
                                  size: 17,
                                ),
                          label: Text(
                            isDownloading ? 'جاري التنزيل...' : 'تنزيل أوفلاين',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDownloading
                                ? Colors.grey
                                : AppColors.accentGold,
                            foregroundColor:
                                isDownloading ? Colors.white : Colors.black87,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed:
                              isDownloading ? null : () => _downloadBook(book),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInitialExploreView(bool isDark) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF0F3628), const Color(0xFF071E16)]
                  : [const Color(0xFF0F5B45), const Color(0xFF1B6B4E)],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppColors.accentGold.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.menu_book_rounded,
                    color: AppColors.accentGold,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'فهارس المكتبة الشاملة الشرعية',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Amiri',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'البحث مقتصر على الأقسام والعلوم الشرعية المعتمدة (القرآن وعلومه، التفسير، كتب السنة وشروحها، الفقه وأصوله، العقيدة، والرقائق) عبر خوادم الشاملة الرسمية.',
                style: TextStyle(
                  color: Color(0xFFFFEFA6),
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'اقتراحات بحث شائعة في الأقسام الشرعية:',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _suggestedQueries.map((query) {
            return ActionChip(
              avatar: const Icon(
                Icons.auto_stories_outlined,
                size: 16,
                color: AppColors.primaryGreen,
              ),
              label: Text(query),
              backgroundColor: isDark
                  ? const Color(0xFF16211D)
                  : AppColors.primaryGreen.withValues(alpha: 0.08),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: AppColors.primaryGreen.withValues(alpha: 0.2),
                ),
              ),
              onPressed: () {
                _searchController.text = query;
                _performSearch();
              },
            );
          }).toList(),
        ),
      ],
    );
  }
}
