import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;

/// ==============================================================================
/// خدمة جلب وبحث كتب المكتبة الشاملة الرسمية (shamela.ws)
/// ==============================================================================
///
/// [توثيق تاريخي ومصدري]:
/// توفر الخدمة بحثاً حياً وتصفية دقيقة لكتب التراث والعلوم الإسلامية بالاعتماد على
/// الأقسام الشرعية المعتمدة رسمياً في المكتبة الشاملة.
///
/// [طريقة الاستعلام والبحث]:
/// نقطة النهاية الرسمية للبحث السريع: `GET https://shamela.ws/ajax/books/?term={query}`.
/// يُستخرج ما يصل إلى 12 كتاباً مرشحاً من الإكمال التلقائي، ثم يتم التحقق من تصنيف كل كتاب
/// عبر جلب بيانات الصفحة `https://shamela.ws/book/{id}` واستخراج رابط القسم الشرعي الموثق
/// `https://shamela.ws/category/{id}` باستخدام DOM Parser، بحد أقصى طلبين متزامنين.
///
/// [روابط التحميل]:
/// تم إيقاف توليد روابط التحميل التخمينية (retired guessed routes). تبقى حقول روابط التحميل
/// فارغة افتراضياً ما لم يتم اكتشاف رابط حقيقي معتمد عبر خدمة ShamelaEpubService.
/// ==============================================================================

/// نموذج بيانات كتاب المكتبة الشاملة
class ShamelaBook {
  /// المعرّف الرقمي للكتاب في الشاملة
  final int id;

  /// عنوان الكتاب
  final String title;

  /// اسم المؤلف أو المحقق (أو المصدر الافتراضي)
  final String author;

  /// رابط التحميل الأساسي (فارغ افتراضياً للروابط غير المكتشفة رسمياً)
  final String downloadUrl;

  /// قائمة المسارات البديلة (فارغة افتراضياً للروابط غير المكتشفة رسمياً)
  final List<String> urlCandidates;

  /// معرّف القسم الشرعي المعتمد
  final int? categoryId;

  /// اسم القسم الشرعي المعتمد
  final String? categoryName;

  const ShamelaBook({
    required this.id,
    required this.title,
    required this.author,
    this.downloadUrl = '',
    this.urlCandidates = const [],
    this.categoryId,
    this.categoryName,
  });

  /// معرّف الكتاب كنص
  String get bookId => id.toString();

  /// رقم المجلد المحسوب في الشاملة (ثلاث خانات)
  String get folder => (id ~/ 100).toString().padLeft(3, '0');

  /// إنشاء كائن من القيم الخام مع بقاء روابط التحميل التخمينية فارغة
  factory ShamelaBook.fromRaw({
    required dynamic id,
    required String title,
    String? author,
    String? folder,
    int? categoryId,
    String? categoryName,
  }) {
    final parsedId = id is int ? id : (int.tryParse(id.toString()) ?? 0);
    return ShamelaBook(
      id: parsedId,
      title: title.trim(),
      author: (author != null && author.trim().isNotEmpty)
          ? author.trim()
          : 'المكتبة الشاملة',
      downloadUrl: '',
      urlCandidates: const [],
      categoryId: categoryId,
      categoryName: categoryName,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'downloadUrl': downloadUrl,
        'urlCandidates': urlCandidates,
        if (categoryId != null) 'categoryId': categoryId,
        if (categoryName != null) 'categoryName': categoryName,
      };

  factory ShamelaBook.fromJson(Map<String, dynamic> json) {
    final idVal = json['id'];
    final parsedId =
        idVal is int ? idVal : (int.tryParse(idVal.toString()) ?? 0);
    final rawCandidates = json['urlCandidates'];
    final candidates = (rawCandidates is List)
        ? rawCandidates.map((e) => e.toString()).toList()
        : const <String>[];

    final catIdVal = json['categoryId'];
    final parsedCatId = catIdVal is int
        ? catIdVal
        : (catIdVal != null ? int.tryParse(catIdVal.toString()) : null);

    return ShamelaBook(
      id: parsedId,
      title: json['title']?.toString() ?? '',
      author: json['author']?.toString() ?? 'المكتبة الشاملة',
      downloadUrl: json['downloadUrl']?.toString() ??
          (candidates.isNotEmpty ? candidates.first : ''),
      urlCandidates: candidates,
      categoryId: parsedCatId,
      categoryName: json['categoryName']?.toString(),
    );
  }

  ShamelaBook copyWith({
    int? id,
    String? title,
    String? author,
    String? downloadUrl,
    List<String>? urlCandidates,
    int? categoryId,
    String? categoryName,
  }) {
    return ShamelaBook(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      urlCandidates: urlCandidates ?? this.urlCandidates,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
    );
  }

  @override
  String toString() =>
      'ShamelaBook(id: $id, title: "$title", author: "$author", category: "$categoryName")';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShamelaBook &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// هيكل داخلي لحفظ بيانات الكتاب الخام أثناء معالجة البحث
class _RawBookData {
  final String title;
  final String author;
  const _RawBookData({required this.title, required this.author});
}

/// هيكل داخلي لترتيب وتصفية المرشحين
class _CandidateEntry {
  final int id;
  final _RawBookData raw;
  final int relevance;
  const _CandidateEntry({
    required this.id,
    required this.raw,
    required this.relevance,
  });
}

/// هيكل داخلي لحفظ تصنيف الكتاب الموثق
class _BookCategoryInfo {
  final int? categoryId;
  final String? categoryName;
  final bool isValidReligious;

  const _BookCategoryInfo({
    this.categoryId,
    this.categoryName,
    required this.isValidReligious,
  });
}

/// خدمة المكتبة الشاملة للبحث الحي وإدارة التحقق من الأقسام الشرعية
class ShamelaLibraryService extends ChangeNotifier {
  static final ShamelaLibraryService instance =
      ShamelaLibraryService._internal();

  ShamelaLibraryService._internal({Dio? dio})
      : _dio = dio ?? _createDefaultDio();

  /// منشئ مخصص للاختبار أو لتمرير عميل Dio مخصص
  factory ShamelaLibraryService({Dio? dio}) {
    if (dio != null) return ShamelaLibraryService._internal(dio: dio);
    return instance;
  }

  final Dio _dio;

  bool _isLoading = false;
  String? _lastError;
  List<ShamelaBook> _lastSearchResults = const [];

  /// ذاكرة تخزين مؤقت لتصنيفات وبيانات الكتب الموثقة حسب المعرّف
  final Map<int, _BookCategoryInfo> _metadataCache = {};

  bool get isLoading => _isLoading;
  String? get lastError => _lastError;
  List<ShamelaBook> get lastSearchResults =>
      List.unmodifiable(_lastSearchResults);

  /// النطاق الأساسي للمكتبة الشاملة
  static const String shamelaBaseUrl = 'https://shamela.ws';

  /// نقطة نهاية البحث الحي عبر Ajax
  static const String ajaxSearchEndpoint = 'https://shamela.ws/ajax/books/';

  /// الترويسات الرسمية المطلوبة للطلب
  static const Map<String, String> defaultHeaders = {
    'Referer': 'https://shamela.ws/',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'X-Requested-With': 'XMLHttpRequest',
    'Accept': 'application/json, text/javascript, */*; q=0.01',
  };

  /// خريطة الأقسام الشرعية المعتمدة حصراً
  static const Map<int, String> religiousCategories = {
    1: 'العقيدة',
    2: 'الفرق والردود',
    3: 'التفسير',
    4: 'علوم القرآن وأصول التفسير',
    5: 'التجويد والقراءات',
    6: 'كتب السنة',
    7: 'شروح الحديث',
    8: 'التخريج والأطراف',
    9: 'العلل والسؤلات الحديثية',
    10: 'علوم الحديث',
    11: 'أصول الفقه',
    12: 'علوم الفقه والقواعد الفقهية',
    14: 'الفقه الحنفي',
    15: 'الفقه المالكي',
    16: 'الفقه الشافعي',
    17: 'الفقه الحنبلي',
    18: 'الفقه العام',
    19: 'مسائل فقهية',
    20: 'السياسة الشرعية والقضاء',
    21: 'الفرائض والوصايا',
    22: 'الفتاوى',
    23: 'الرقائق والآداب والأذكار',
    24: 'السيرة النبوية',
  };

  /// تهيئة عميل Dio الافتراضي
  static Dio _createDefaultDio() {
    return Dio(
      BaseOptions(
        baseUrl: shamelaBaseUrl,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 12),
        sendTimeout: const Duration(seconds: 8),
        headers: defaultHeaders,
      ),
    );
  }

  // ==============================================================================
  // معالجة النصوص والتطبيع العربي
  // ==============================================================================

  static final RegExp _tashkeelRegex = RegExp(
    r'[\u0617-\u061A\u064B-\u065F\u0670\u06D6-\u06ED]',
  );

  /// إزالة التشكيل (الحركات) وعلامات الضبط والتطويل (الكشيدة)
  static String stripTashkeel(String text) {
    if (text.isEmpty) return '';
    final withoutDiacritics = text.replaceAll(_tashkeelRegex, '');
    return withoutDiacritics.replaceAll('\u0640', '');
  }

  /// تطبيع الحروف العربية للبحث المرن:
  /// - إزالة التشكيل والتطويل
  /// - توحيد الهمزات والألف (إ، أ، آ، ٱ -> ا)
  /// - تحويل التاء المربوطة (ة -> ه)
  /// - تحويل الألف المقصورة (ى -> ي)
  /// - إزالة محارف التوجيه والتحكم
  /// - دمج المسافات الزائدة
  static String normalizeArabicSearch(String text) {
    if (text.isEmpty) return '';
    var s = stripTashkeel(text);
    s = s.replaceAll(RegExp(r'[إأآٱ]'), 'ا');
    s = s.replaceAll('ة', 'ه');
    s = s.replaceAll('ى', 'ي');
    s = s.replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e]'), '');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  // ==============================================================================
  // مسارات التحميل التاريخية (Deprecated)
  // ==============================================================================

  /// بناء قائمة المسارات البديلة التاريخية (مهملة وغير موثوقة)
  @Deprecated(
      'Historical and not trusted. Guessed download routes are retired.')
  static List<String> downloadCandidates(dynamic bookId, [String? folder]) {
    final bid = bookId.toString().trim();
    final intId = int.tryParse(bid) ?? 0;
    final f = (folder != null && folder.trim().isNotEmpty)
        ? folder.trim()
        : (intId ~/ 100).toString().padLeft(3, '0');

    return [
      'https://old.shamela.ws/epubs/$f/$bid.epub',
      'https://shamela.ws/book/$bid/download/epub',
      'https://shamela.ws/book/$bid/download/pdf',
    ];
  }

  /// دالة نسخة على مستوى الكائن للحصول على المسارات البديلة التاريخية
  @Deprecated(
      'Historical and not trusted. Guessed download routes are retired.')
  List<String> getDownloadCandidates(dynamic bookId, [String? folder]) =>
      downloadCandidates(bookId, folder);

  // ==============================================================================
  // حساب درجة الملاءمة والترتيب (Relevance Scoring)
  // ==============================================================================

  /// حساب مدى تطابق الاستعلام مع العنوان واسم المؤلف (من 0 إلى 100)
  static int computeSearchRelevance(
    String query,
    String title, [
    String author = '',
  ]) {
    final qNorm = normalizeArabicSearch(query).toLowerCase().trim();
    final tNorm = normalizeArabicSearch(title).toLowerCase().trim();
    final aNorm = author.isNotEmpty
        ? normalizeArabicSearch(author).toLowerCase().trim()
        : '';

    if (qNorm.isEmpty || tNorm.isEmpty) return 0;

    int score = 0;

    // تطابق تام مع العنوان
    if (tNorm == qNorm) return 100;

    // العنوان يبدأ بعبارة الاستعلام
    if (tNorm.startsWith(qNorm)) {
      score = 95;
    }

    // عبارة الاستعلام موجودة داخل العنوان
    if (tNorm.contains(qNorm)) {
      final ratio = qNorm.length / (tNorm.isEmpty ? 1 : tNorm.length);
      final s = (80 + 15 * ratio).round();
      if (s > score) score = s;
    }

    // عبارة الاستعلام موجودة في اسم المؤلف
    if (aNorm.isNotEmpty && aNorm.contains(qNorm)) {
      if (85 > score) score = 85;
    }

    // مطابقة الكلمات المنفردة (Token Overlap)
    final qWords =
        qNorm.split(RegExp(r'\s+')).where((w) => w.length > 1).toList();
    final tWords =
        tNorm.split(RegExp(r'\s+')).where((w) => w.length > 1).toList();
    final aWords =
        aNorm.split(RegExp(r'\s+')).where((w) => w.length > 1).toList();

    if (qWords.isNotEmpty) {
      int matchesTitle = 0;
      for (final qw in qWords) {
        if (tWords
            .any((tw) => qw == tw || (qw.length >= 3 && tw.contains(qw)))) {
          matchesTitle++;
        }
      }

      int matchesAuthor = 0;
      for (final qw in qWords) {
        if (aWords
            .any((aw) => qw == aw || (qw.length >= 3 && aw.contains(qw)))) {
          matchesAuthor++;
        }
      }

      final combined = matchesTitle + matchesAuthor;
      final totalMatches = matchesTitle > combined
          ? matchesTitle
          : (combined > qWords.length ? qWords.length : combined);

      final tokenRatio = totalMatches / qWords.length;
      if (tokenRatio == 1.0) {
        if (80 > score) score = 80;
      } else if (tokenRatio >= 0.5) {
        final s = (40 + 35 * tokenRatio).round();
        if (s > score) score = s;
      } else if (tokenRatio > 0) {
        final s = (20 + 20 * tokenRatio).round();
        if (s > score) score = s;
      }
    }

    return score > 100 ? 100 : score;
  }

  // ==============================================================================
  // استخراج وتدقيق التصنيف الشرعي عبر HTML DOM
  // ==============================================================================

  static final Uri _shamelaBaseUri = Uri.parse('https://shamela.ws/');
  static final RegExp _categoryPathRegex = RegExp(r'^/category/(\d+)$');

  /// استخراج معرّف واسم القسم من صفحة الكتاب عبر وسم الرابط https://shamela.ws/category/{id}
  static (int, String)? _extractCategoryFromHtml(String html) {
    if (html.isEmpty) return null;
    try {
      final doc = html_parser.parse(html);
      final anchors = doc.getElementsByTagName('a');
      for (final a in anchors) {
        final rawHref = a.attributes['href']?.trim() ?? '';
        if (rawHref.isEmpty) continue;

        final parsedUri = Uri.tryParse(rawHref);
        if (parsedUri == null) continue;

        final resolvedUri = _shamelaBaseUri.resolveUri(parsedUri);

        // قبول روابط https الصريحة فقط بنطاق shamela.ws ومسار /category/digits دون معاملات أو أجزاء
        if (resolvedUri.scheme != 'https' ||
            resolvedUri.host != 'shamela.ws' ||
            resolvedUri.userInfo.isNotEmpty ||
            resolvedUri.hasQuery ||
            resolvedUri.hasFragment) {
          continue;
        }

        final match = _categoryPathRegex.firstMatch(resolvedUri.path);
        if (match != null) {
          final catId = int.tryParse(match.group(1)!);
          if (catId != null) {
            final catText = a.text.trim();
            final name = catText.isNotEmpty
                ? catText
                : (religiousCategories[catId] ?? '');
            return (catId, name);
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// جلب وتدقيق تصنيف الكتاب مع التخزين المؤقت
  Future<_BookCategoryInfo?> _fetchBookMetadata(int id) async {
    if (_metadataCache.containsKey(id)) {
      return _metadataCache[id];
    }

    try {
      final url = 'https://shamela.ws/book/$id';
      final response = await _dio.get(
        url,
        options: Options(
          headers: defaultHeaders,
          responseType: ResponseType.plain,
        ),
      );

      // التحقق الصارم من العنوان النهائي للاستجابة realUri
      final realUri = response.realUri;
      if (realUri.scheme != 'https' ||
          realUri.host != 'shamela.ws' ||
          realUri.path != '/book/$id' ||
          realUri.userInfo.isNotEmpty) {
        final info = const _BookCategoryInfo(
          categoryId: null,
          categoryName: null,
          isValidReligious: false,
        );
        _metadataCache[id] = info;
        return info;
      }

      final rawData = response.data;
      final html = rawData?.toString() ?? '';
      if (html.isEmpty) {
        final info = const _BookCategoryInfo(
          categoryId: null,
          categoryName: null,
          isValidReligious: false,
        );
        _metadataCache[id] = info;
        return info;
      }

      final cat = _extractCategoryFromHtml(html);
      if (cat != null) {
        final catId = cat.$1;
        final extractedName = cat.$2;
        if (religiousCategories.containsKey(catId)) {
          final officialName = religiousCategories[catId]!;
          final catName =
              extractedName.isNotEmpty ? extractedName : officialName;
          final info = _BookCategoryInfo(
            categoryId: catId,
            categoryName: catName,
            isValidReligious: true,
          );
          _metadataCache[id] = info;
          return info;
        } else {
          // قسم غير ديني (مثل المنطق 13، التاريخ 25، التراجم 26، إلخ)
          final info = _BookCategoryInfo(
            categoryId: catId,
            categoryName: extractedName,
            isValidReligious: false,
          );
          _metadataCache[id] = info;
          return info;
        }
      }

      // لا يوجد رابط تصنيف موثق (غير معروف / غير موثق)
      final info = const _BookCategoryInfo(
        categoryId: null,
        categoryName: null,
        isValidReligious: false,
      );
      _metadataCache[id] = info;
      return info;
    } catch (_) {
      // عدم تخزين الخطأ المؤقت للشبكة لتمكين إعادة المحاولة
      return const _BookCategoryInfo(
        categoryId: null,
        categoryName: null,
        isValidReligious: false,
      );
    }
  }

  /// جلب بيانات ما يصل إلى 12 كتاباً بحد أقصى طلبين متزامنين
  Future<List<_BookCategoryInfo?>> _fetchMetadataWithConcurrency(
    List<int> bookIds, {
    int maxConcurrency = 2,
  }) async {
    if (bookIds.isEmpty) return const [];
    final results = List<_BookCategoryInfo?>.filled(bookIds.length, null);
    int nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        final i = nextIndex++;
        if (i >= bookIds.length) break;
        results[i] = await _fetchBookMetadata(bookIds[i]);
      }
    }

    final workerCount =
        bookIds.length < maxConcurrency ? bookIds.length : maxConcurrency;
    final workers = List.generate(workerCount, (_) => worker());
    await Future.wait(workers);
    return results;
  }

  // ==============================================================================
  // البحث الحي في المكتبة الشاملة (searchBooks / searchShamela)
  // ==============================================================================

  /// بحث حي في المكتبة الشاملة عبر نقطة نهاية term مع توسيع المصطلحات والتحقق الشرعي
  /// [query]: عبارة البحث
  /// [filterType]: نوع التصفية ('all', 'title', 'author')
  /// [limit]: الحد الأقصى للنتائج
  /// [ignoreTashkeel]: تطبيع النص وإهمال التشكيل والهمزات
  /// [religiousOnly]: اقتصار النتائج على الأقسام الدينية المعتمدة رسمياً
  Future<List<ShamelaBook>> searchBooks(
    String query, {
    String filterType = 'all',
    int limit = 100,
    bool ignoreTashkeel = true,
    bool religiousOnly = true,
  }) async {
    final cleanQ = query.trim();
    if (cleanQ.isEmpty) return const [];

    final qNorm =
        ignoreTashkeel ? normalizeArabicSearch(cleanQ) : stripTashkeel(cleanQ);
    if (qNorm.isEmpty) return const [];

    _isLoading = true;
    _lastError = null;
    notifyListeners();

    try {
      // 1. توسيع مصطلحات البحث وفق المرجع الأساسي
      final searchTerms = <String>[cleanQ];
      if (qNorm != cleanQ && !searchTerms.contains(qNorm)) {
        searchTerms.add(qNorm);
      }

      for (final prefix in const [
        'كتاب ',
        'شرح ',
        'تفسير ',
        'ديوان ',
        'مختصر ',
      ]) {
        if (cleanQ.startsWith(prefix) && cleanQ.length > prefix.length + 2) {
          final sub = cleanQ.substring(prefix.length).trim();
          if (!searchTerms.contains(sub)) {
            searchTerms.add(sub);
          }
        }
      }

      final words =
          cleanQ.split(RegExp(r'\s+')).where((w) => w.length > 2).toList();
      if (words.length > 1 &&
          !searchTerms.contains(words.last) &&
          words.last.length >= 3) {
        searchTerms.add(words.last);
      }

      // 2. جلب النتائج بالتوازي لما يصل إلى 3 مصطلحات مع تتبع الأخطاء بدقة
      final termsToFetch = searchTerms.take(3).toList();
      final Map<int, _RawBookData> rawBooks = {};
      int successfulTerms = 0;
      Object? lastDioError;

      await Future.wait(
        termsToFetch.map(
          (term) => _fetchTerm(
            term,
            rawBooks,
            () => successfulTerms++,
            (err) => lastDioError = err,
          ),
        ),
      );

      // في حال فشلت جميع مصطلحات البحث بالكامل (مثل انقطاع الاتصال) يتم إظهار الخطأ الحقيقي
      if (successfulTerms == 0 && termsToFetch.isNotEmpty) {
        _lastError = lastDioError?.toString() ?? 'Network connection failed';
        _lastSearchResults = const [];
        return const [];
      }

      // 3. التصفية الأولية حسب النوع وحساب درجة الملاءمة
      final normFilterQ = normalizeArabicSearch(query).toLowerCase();
      final List<_CandidateEntry> candidateEntries = [];

      for (final entry in rawBooks.entries) {
        final bid = entry.key;
        final raw = entry.value;
        final title = raw.title;
        final author = raw.author;

        final tNorm = normalizeArabicSearch(title).toLowerCase();
        final aNorm = normalizeArabicSearch(author).toLowerCase();

        if (filterType == 'title') {
          final rel = computeSearchRelevance(query, title);
          if (rel < 15 && !tNorm.contains(normFilterQ)) {
            continue;
          }
        } else if (filterType == 'author') {
          final relA = computeSearchRelevance(query, author);
          final relT = computeSearchRelevance(query, title);
          if (relA < 15 &&
              relT < 25 &&
              !aNorm.contains(normFilterQ) &&
              !tNorm.contains(normFilterQ)) {
            continue;
          }
        }

        final rel = computeSearchRelevance(query, title, author);
        candidateEntries
            .add(_CandidateEntry(id: bid, raw: raw, relevance: rel));
      }

      // ترتيب المرشحين حسب الملاءمة تنازلياً
      candidateEntries.sort((a, b) => b.relevance.compareTo(a.relevance));

      // في حال اختبار الإكمال التلقائي الأساسي فقط بدون اشتراط التدقيق الديني
      if (!religiousOnly) {
        final results = candidateEntries
            .map((c) => ShamelaBook(
                  id: c.id,
                  title: c.raw.title,
                  author: c.raw.author,
                  downloadUrl: '',
                  urlCandidates: const [],
                  categoryId: _metadataCache[c.id]?.categoryId,
                  categoryName: _metadataCache[c.id]?.categoryName,
                ))
            .take(limit)
            .toList();

        _lastSearchResults = results;
        return results;
      }

      // 4. أخذ ما يصل إلى 12 كتاباً مرشحاً وجلب التصنيف الشرعي الموثق (حد أقصى طلبين متزامنين)
      final topCandidates = candidateEntries.take(12).toList();
      final metadataList = await _fetchMetadataWithConcurrency(
        topCandidates.map((c) => c.id).toList(),
        maxConcurrency: 2,
      );

      final List<ShamelaBook> verifiedResults = [];
      for (int i = 0; i < topCandidates.length; i++) {
        final c = topCandidates[i];
        final meta = metadataList[i];
        // استبعاد أي كتاب غير موثق أو لا ينتمي لخريطة الأقسام الشرعية المعتمدة
        if (meta != null && meta.isValidReligious && meta.categoryId != null) {
          verifiedResults.add(
            ShamelaBook(
              id: c.id,
              title: c.raw.title,
              author: c.raw.author,
              downloadUrl: '',
              urlCandidates: const [],
              categoryId: meta.categoryId,
              categoryName: meta.categoryName,
            ),
          );
        }
      }

      final finalResults = verifiedResults.length > limit
          ? verifiedResults.sublist(0, limit)
          : verifiedResults;

      _lastSearchResults = finalResults;
      return finalResults;
    } catch (e) {
      _lastError = e.toString();
      _lastSearchResults = const [];
      return const [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// اسم بديل متطابق مع اسم الدالة في المرجع search_shamela
  Future<List<ShamelaBook>> searchShamela(
    String query, {
    String filterType = 'all',
    int limit = 100,
    bool ignoreTashkeel = true,
    bool religiousOnly = true,
  }) =>
      searchBooks(
        query,
        filterType: filterType,
        limit: limit,
        ignoreTashkeel: ignoreTashkeel,
        religiousOnly: religiousOnly,
      );

  /// طلب مصطلح واحد من واجهة الشاملة ومعالجة الاستجابة
  Future<void> _fetchTerm(
    String term,
    Map<int, _RawBookData> rawBooks,
    void Function() onTermSuccess,
    void Function(Object error) onTermError,
  ) async {
    try {
      final qEnc = Uri.encodeComponent(term);
      final url = 'https://shamela.ws/ajax/books/?term=$qEnc';

      final response = await _dio.get(
        url,
        options: Options(
          headers: defaultHeaders,
          responseType: ResponseType.json,
        ),
      );

      dynamic data = response.data;
      if (data is String) {
        data = jsonDecode(data);
      }
      onTermSuccess();

      if (data is! Map) return;

      final results = data['results'];
      if (results is! Map) return;

      final items = results['items'];
      if (items is! List) return;

      for (final it in items) {
        if (it is! Map) continue;

        final bidStr = it['id']?.toString().trim() ?? '';
        final bidInt = int.tryParse(bidStr);

        // استبعاد id = -1 أو أي معرّف غير موجب
        if (bidInt == null || bidInt <= 0) continue;

        if (rawBooks.containsKey(bidInt)) continue;

        final textVal = (it['text']?.toString() ?? '').trim();
        final parts = textVal
            .split(' - ')
            .map((p) => p.trim())
            .where((p) => p.isNotEmpty)
            .toList();

        final title = parts.isNotEmpty ? parts.first : textVal;
        String author = parts.length > 1 ? parts.sublist(1).join(' - ') : '';

        // استخراج اسم المؤلف في حال لم يرد مفصولاً برمز الشارطة
        if (author.isEmpty) {
          final authMatch = RegExp(
            r'(?:لـ?|تأليف\s+|للإمام\s+|للشيخ\s+)([\w\s]+)$',
          ).firstMatch(title);
          if (authMatch != null) {
            author = authMatch.group(1)?.trim() ?? '';
          }
        }

        if (author.isEmpty) {
          author = 'المكتبة الشاملة';
        }

        rawBooks[bidInt] = _RawBookData(title: title, author: author);
      }
    } catch (e) {
      onTermError(e);
    }
  }

  // ==============================================================================
  // تنزيل الملفات مع التبديل التلقائي بين البدائل (تاريخي مهمل)
  // ==============================================================================

  /// تنزيل كتاب مع فحص المسارات البديلة بالترتيب (مهمل وغير موثوق)
  @Deprecated(
      'Historical and not trusted. Guessed download routes are retired.')
  Future<Response<List<int>>?> downloadBookFile({
    required ShamelaBook book,
    Duration timeout = const Duration(seconds: 35),
  }) =>
      downloadFromCandidates(
        candidates: book.urlCandidates,
        timeout: timeout,
      );

  /// محاولة تنزيل الملف بالمرور على الروابط البديلة بالترتيب (مهمل وغير موثوق)
  @Deprecated(
      'Historical and not trusted. Guessed download routes are retired.')
  Future<Response<List<int>>?> downloadFromCandidates({
    required List<String> candidates,
    Duration timeout = const Duration(seconds: 35),
  }) async {
    for (final candUrl in candidates) {
      final cleanUrl = candUrl.trim();
      if (cleanUrl.isEmpty) continue;

      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          final res = await _dio.get<List<int>>(
            cleanUrl,
            options: Options(
              responseType: ResponseType.bytes,
              headers: const {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                'Accept': '*/*',
                'Accept-Encoding': 'identity',
              },
              sendTimeout: timeout,
              receiveTimeout: timeout,
            ),
          );

          final contentType =
              (res.headers.value('content-type') ?? '').toLowerCase();
          final lowerUrl = cleanUrl.toLowerCase().split('?').first;
          final isExplicitHtml =
              lowerUrl.endsWith('.html') || lowerUrl.endsWith('.htm');

          // إذا أعادت الشاملة صفحة HTML بدلاً من ملف الكتاب (EPUB/PDF) نتخطى هذا الرابط
          if (contentType.contains('text/html') && !isExplicitHtml) {
            break;
          }

          if (res.statusCode == 200 &&
              res.data != null &&
              res.data!.isNotEmpty) {
            return res;
          }
        } catch (_) {
          if (attempt == 0) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
        }
      }
    }
    return null;
  }
}

/// دالة مساعدة عامة لبناء المسارات البديلة لتحميل كتب الشاملة (تاريخية مهملة)
@Deprecated('Historical and not trusted. Guessed download routes are retired.')
List<String> downloadCandidates(dynamic bookId, [String? folder]) =>
    ShamelaLibraryService.downloadCandidates(bookId, folder);
