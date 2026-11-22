import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/surah.dart';
import '../models/ayah.dart';
import '../text/arabic_normalizer.dart';
import 'quran_repository.dart';
import '../utils/serial_task_queue.dart';

class QuranSearchDataException implements Exception {
  final String message;
  const QuranSearchDataException(this.message);

  @override
  String toString() => 'QuranSearchDataException: $message';
}

class QuranReferenceMatch {
  final int surahId;
  final int ayahNumber;
  final String title;
  final String? aliasNote;

  const QuranReferenceMatch({
    required this.surahId,
    required this.ayahNumber,
    required this.title,
    this.aliasNote,
  });
}

class AyahSearchResult {
  final Ayah ayah;
  final Surah surah;
  final String query;

  const AyahSearchResult({
    required this.ayah,
    required this.surah,
    required this.query,
  });
}

class QuranSearchService {
  static final QuranSearchService instance = QuranSearchService._internal();
  QuranSearchService._internal();

  static const String _historyKey = 'quran_search_history_v1';

  static const Map<String, String> _rawAliases = {
    'آية الكرسي': '2:255',
    'الكرسي': '2:255',
    'آية الدين': '2:282',
    'الدين': '2:282',
    'خواتيم البقرة': '2:285',
    'أواخر البقرة': '2:285',
    'آية النور': '24:35',
    'الله نور السماوات': '24:35',
    'آية السيف': '9:5',
    'آية المباهلة': '3:61',
    'آية التطهير': '33:33',
    'آية المودة': '42:23',
    'آية الحجاب': '33:59',
    'آية العرش': '9:129',
    'آية الصيام': '2:183',
    'كتب عليكم الصيام': '2:183',
    'آية البر': '2:177',
    'آية الوضوء': '5:6',
    'آية التيمم': '4:43',
    'آية القبلة': '2:144',
    'تحويل القبلة': '2:144',
    'آية الربا': '2:275',
    'آية الأمانة': '33:72',
    'إنا عرضنا الأمانة': '33:72',
    'آية الخلافة': '2:30',
    'إني جاعل في الأرض خليفة': '2:30',
    'آية الاسترجاع': '2:156',
    'إنا لله وإنا إليه راجعون': '2:156',
  };

  static Map<String, String>? _normalizedAliasesCache;
  static Map<String, String> get _normalizedAliases {
    _normalizedAliasesCache ??= {
      for (final entry in _rawAliases.entries)
        ArabicNormalizer.normalize(entry.key, loose: true): entry.value
    };
    return _normalizedAliasesCache!;
  }

  /// Cached dual-key normalized Ayah index per Surah ID.
  /// Decorative prefixes follow the existing display getter; raw Ayahs stay unchanged.
  /// - imlaeiKey: search-only Uthmani-to-Imlaei canonical form (fixes U+200A/U+2060, dagger alif, etc.)
  /// - legacyKey: legacy Uthmani-stripped matching over the same displayed text.
  static Map<int, List<({Ayah ayah, String imlaeiKey, String legacyKey})>>?
      _normalizedSurahAyahsCache;

  @visibleForTesting
  static void resetCacheForTesting() {
    _normalizedSurahAyahsCache = null;
  }

  Future<Map<int, List<({Ayah ayah, String imlaeiKey, String legacyKey})>>>
      _ensureNormalizedIndex() async {
    if (_normalizedSurahAyahsCache != null && _normalizedSurahAyahsCache!.isNotEmpty) {
      return _normalizedSurahAyahsCache!;
    }
    final pagesMap = await QuranRepository.loadAllPages();
    final Map<int, List<({Ayah ayah, String imlaeiKey, String legacyKey})>> index = {};
    final seenAyahIds = <int>{};
    for (int page = 1; page <= 604; page++) {
      final ayahs = pagesMap[page] ?? [];
      for (final ayah in ayahs) {
        if (!seenAyahIds.add(ayah.id)) continue;
        final displayedText = ayah.cleanTextUthmani;
        final imlaeiKey = ArabicNormalizer.normalizeForQuranSearch(displayedText);
        final legacyKey = ArabicNormalizer.normalize(displayedText, loose: true);
        index.putIfAbsent(ayah.surahId, () => []).add((
          ayah: ayah,
          imlaeiKey: imlaeiKey,
          legacyKey: legacyKey,
        ));
      }
    }
    if (index.isEmpty) {
      throw const QuranSearchDataException('Failed to load Quran Ayah search index');
    }
    _normalizedSurahAyahsCache = index;
    return index;
  }

  /// Parses input for direct ayah reference e.g. "2:255", "٢:٢٥٥", "البقرة 255",
  /// "البقرة: 255", "سورة البقرة آية ٢٥٥", or common aliases (Bug #16 fix).
  Future<QuranReferenceMatch?> parseReference(String rawInput) async {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) return null;

    final normalized = ArabicNormalizer.normalize(trimmed, loose: true);

    // 1. Check known aliases
    if (_normalizedAliases.containsKey(normalized)) {
      final target = _normalizedAliases[normalized]!;
      final parts = target.split(':');
      final sId = int.tryParse(parts[0]) ?? 1;
      final aNum = int.tryParse(parts[1]) ?? 1;
      final surahs = await QuranRepository.loadSurahs();
      if (surahs.isEmpty) return null;
      final surah = surahs.firstWhere((s) => s.id == sId, orElse: () => surahs.first);
      return QuranReferenceMatch(
        surahId: sId,
        ayahNumber: aNum,
        title: '${surah.nameAr} — آية $aNum',
        aliasNote: 'تسمية مشهورة: $trimmed',
      );
    }

    // 2. Check for format "2:255" or "٢:٢٥٥"
    final colonRegex = RegExp(r'^(\d+)\s*[:：/-]\s*(\d+)$');
    final matchColon = colonRegex.firstMatch(normalized);
    if (matchColon != null) {
      final sId = int.tryParse(matchColon.group(1)!);
      final aNum = int.tryParse(matchColon.group(2)!);
      if (sId != null && aNum != null && sId >= 1 && sId <= 114) {
        final surahs = await QuranRepository.loadSurahs();
        if (surahs.isEmpty) return null;
        final surah = surahs.firstWhere((s) => s.id == sId, orElse: () => surahs.first);
        if (aNum >= 1 && aNum <= surah.ayahCount) {
          return QuranReferenceMatch(
            surahId: sId,
            ayahNumber: aNum,
            title: '${surah.nameAr} — آية $aNum',
            aliasNote: 'مرجع مباشر: $sId:$aNum',
          );
        }
      }
    }

    // 3. Check for format "<SurahName> [:|آية|اية] <AyahNum>" e.g. "البقرة 255", "البقرة: ٢٥٥", "سورة الكهف آية 10"
    final surahs = await QuranRepository.loadSurahs();
    for (final s in surahs) {
      final normSurahName = ArabicNormalizer.normalize(s.nameAr, loose: true);
      final cleanName = normSurahName.replaceAll(RegExp(r'^(?:سوره|سورة)\s+'), '').trim();
      final pattern = RegExp(
        '^(?:(?:سوره|سورة)\\s+)?(?:${RegExp.escape(normSurahName)}|${RegExp.escape(cleanName)})(?:\\s*[:：-]\\s*|\\s+(?:(?:ايه|آيه|آية|اية)\\s+)?)(\\d+)\$',
      );
      final match = pattern.firstMatch(normalized);
      if (match != null) {
        final aNum = int.tryParse(match.group(1)!);
        if (aNum != null && aNum >= 1 && aNum <= s.ayahCount) {
          return QuranReferenceMatch(
            surahId: s.id,
            ayahNumber: aNum,
            title: 'سورة ${s.nameAr} — آية $aNum',
            aliasNote: 'بحث بالاسم والرقم',
          );
        }
      }
    }

    return null;
  }

  /// Searches for Ayahs matching query across all 6,236 Ayahs using dual-key cached index (FR-SRC-001)
  Future<List<AyahSearchResult>> searchAyahs(
    String query, {
    int? surahFilter,
    int limit = 100,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    final imlaeiQuery = ArabicNormalizer.normalizeForQuranSearch(cleanQuery);
    final legacyQuery = ArabicNormalizer.normalize(cleanQuery, loose: true);
    if (imlaeiQuery.isEmpty && legacyQuery.isEmpty) return [];
    final surahs = await QuranRepository.loadSurahs();
    if (surahs.isEmpty) {
      throw const QuranSearchDataException('Failed to load Surahs metadata');
    }
    final surahMap = {for (final s in surahs) s.id: s};
    final index = await _ensureNormalizedIndex();

    final List<AyahSearchResult> results = [];
    bool matchesEntry(({Ayah ayah, String imlaeiKey, String legacyKey}) entry) {
      return (imlaeiQuery.isNotEmpty && entry.imlaeiKey.contains(imlaeiQuery)) ||
          (legacyQuery.isNotEmpty && entry.legacyKey.contains(legacyQuery));
    }

    if (surahFilter != null) {
      final entries = index[surahFilter] ?? [];
      final surah = surahMap[surahFilter] ?? surahs.first;
      for (final entry in entries) {
        if (matchesEntry(entry)) {
          results.add(AyahSearchResult(ayah: entry.ayah, surah: surah, query: cleanQuery));
          if (results.length >= limit) break;
        }
      }
    } else {
      for (int sId = 1; sId <= 114; sId++) {
        final entries = index[sId] ?? [];
        final surah = surahMap[sId] ?? surahs.first;
        for (final entry in entries) {
          if (matchesEntry(entry)) {
            results.add(AyahSearchResult(ayah: entry.ayah, surah: surah, query: cleanQuery));
            if (results.length >= limit) return results;
          }
        }
      }
    }

    return results;
  }

  final SerialTaskQueue _historyQueue = SerialTaskQueue();

  /// Loads confirmed history. Missing storage retains the first-use defaults;
  /// an explicitly saved empty list stays empty.
  Future<List<String>> getSearchHistory() => _historyQueue.run(() async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        return List<String>.of(prefs.getStringList(_historyKey) ?? const [
          'آية الكرسي',
          'الرحمن الرحيم',
          'سورة الكهف',
          'خواتيم البقرة',
          'الله نور السماوات',
        ]);
      });

  Future<bool> _mutateHistory(void Function(List<String>) mutate,
          {bool clearAll = false}) =>
      _historyQueue.run(() async {
        try {
          final prefs = await SharedPreferences.getInstance();
          // Absolute clear needs no prior list, including a damaged one.
          if (!clearAll) await prefs.reload();
          final next = clearAll
              ? <String>[]
              : List<String>.of(
                  prefs.getStringList(_historyKey) ?? const <String>[]);
          mutate(next);
          try {
            if (await prefs.setStringList(_historyKey, next)) return true;
          } catch (_) {}
          // The plugin cache changes even on failure. Only provider readback
          // can confirm a write whose acknowledgement was lost.
          await prefs.reload();
          return listEquals(prefs.getStringList(_historyKey), next);
        } catch (_) {
          return false;
        }
      });

  /// Adds a query without treating history persistence as Quran-search failure.
  Future<bool> addToHistory(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty || trimmed.length < 2) return Future.value(true);
    return _mutateHistory((next) {
      next.remove(trimmed);
      next.insert(0, trimmed);
      if (next.length > 20) next.removeRange(20, next.length);
    });
  }

  /// Removes one stored history item, preserving the remaining order.
  Future<bool> removeFromHistory(String query) =>
      _mutateHistory((next) => next.remove(query));

  /// A confirmed explicit empty list suppresses first-use history defaults.
  Future<bool> clearHistory() =>
      _mutateHistory((next) => next.clear(), clearAll: true);
}
