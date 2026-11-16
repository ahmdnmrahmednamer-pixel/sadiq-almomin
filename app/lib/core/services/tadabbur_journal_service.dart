import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'journal_merge_util.dart';

class TadabburReflectionItem {
  final String id;
  final int surahId;
  final String surahName;
  final int ayahNumber;
  final String ayahSnippet;
  final String faithMessage; // الرسالة الإيمانية
  final String practicalAction; // العمل التطبيقي
  final String derivedDua; // الدعاء المستنبط
  final DateTime createdAt;

  const TadabburReflectionItem({
    required this.id,
    required this.surahId,
    required this.surahName,
    required this.ayahNumber,
    required this.ayahSnippet,
    required this.faithMessage,
    required this.practicalAction,
    required this.derivedDua,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'surahId': surahId,
        'surahName': surahName,
        'ayahNumber': ayahNumber,
        'ayahSnippet': ayahSnippet,
        'faithMessage': faithMessage,
        'practicalAction': practicalAction,
        'derivedDua': derivedDua,
        'createdAt': createdAt.toIso8601String(),
      };

  factory TadabburReflectionItem.fromJson(Map<String, dynamic> json) {
    return TadabburReflectionItem(
      id: json['id'] as String? ?? 'tadabbur_1',
      surahId: json['surahId'] as int? ?? 1,
      surahName: json['surahName'] as String? ?? 'الفاتحة',
      ayahNumber: json['ayahNumber'] as int? ?? 5,
      ayahSnippet: json['ayahSnippet'] as String? ?? '',
      faithMessage: json['faithMessage'] as String? ?? '',
      practicalAction: json['practicalAction'] as String? ?? '',
      derivedDua: json['derivedDua'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

enum JournalOperationStatus {
  persisted,
  refusedUnreadable,
  writeUnconfirmed,
}

@immutable
class JournalOperationResult {
  final JournalOperationStatus status;
  final bool livePublished;

  const JournalOperationResult({
    required this.status,
    required this.livePublished,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JournalOperationResult &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          livePublished == other.livePublished;

  @override
  int get hashCode => Object.hash(status, livePublished);

  @override
  String toString() =>
      'JournalOperationResult(status: $status, livePublished: $livePublished)';
}

enum JournalRestoreStatus {
  confirmedWrite,
  intentionalSkip,
  writeUnconfirmed,
}

@immutable
class JournalRestoreResult {
  final JournalRestoreStatus status;
  final bool livePublished;

  const JournalRestoreResult({
    required this.status,
    required this.livePublished,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JournalRestoreResult &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          livePublished == other.livePublished;

  @override
  int get hashCode => Object.hash(status, livePublished);

  @override
  String toString() =>
      'JournalRestoreResult(status: $status, livePublished: $livePublished)';
}

enum AccountabilityOperationStatus {
  persisted,
  writeUnconfirmed,
  writeRefusedUnreadable,
}

@immutable
class AccountabilityToggleResult {
  final AccountabilityOperationStatus status;
  final bool livePublished;

  const AccountabilityToggleResult({
    required this.status,
    required this.livePublished,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AccountabilityToggleResult &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          livePublished == other.livePublished;

  @override
  int get hashCode => Object.hash(status, livePublished);

  @override
  String toString() =>
      'AccountabilityToggleResult(status: $status, livePublished: $livePublished)';
}

enum AccountabilityRestoreStatus {
  confirmedWrite,
  intentionalSkip,
  writeUnconfirmed,
}

@immutable
class AccountabilityRestoreResult {
  final AccountabilityRestoreStatus status;
  final bool livePublished;

  const AccountabilityRestoreResult({
    required this.status,
    required this.livePublished,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AccountabilityRestoreResult &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          livePublished == other.livePublished;

  @override
  int get hashCode => Object.hash(status, livePublished);

  @override
  String toString() =>
      'AccountabilityRestoreResult(status: $status, livePublished: $livePublished)';
}

/// الميزة الخامسة الجديدة: دفتر التدبر والعمل بالقرآن ومحاسبة النفس الإيمانية اليومية
class TadabburJournalService extends ChangeNotifier {
  static final TadabburJournalService instance = TadabburJournalService._internal();
  TadabburJournalService._internal() {
    _entries.addAll(_defaultInspiringReflections);
  }

  static const String _storageKey = 'tadabbur_journal_entries_v1';
  static const String _dailyAccountabilityKey = 'tadabbur_daily_accountability_v1';

  bool _isInitialized = false;
  bool _isReadable = true;
  final List<TadabburReflectionItem> _entries = [];
  final Map<String, Set<String>> _dailyAccountability = {};

  bool get isReadable => _isReadable;
  List<TadabburReflectionItem> get entries => List.unmodifiable(_entries);

  Future<void> _queue = Future<void>.value();

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        final result = await action();
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    }).catchError((_) {
      // Prevents failures in previous tasks from wedging the queue
    });
    return completer.future;
  }

  static const List<Map<String, String>> dailyEthicalChecklist = [
    {
      'id': 'birr_walidayn',
      'title': 'بر الوالدين وصلة الرحم وإدخال السرور عليهما',
      'verse': '﴿وَقَضَىٰ رَبُّكَ أَلَّا تَعْبُدُوا إِلَّا إِيَّاهُ وَبِالْوَالِدَيْنِ إِحْسَانًا﴾ [الإسراء: ٢٣]',
    },
    {
      'id': 'hifz_lisan',
      'title': 'حفظ اللسان عن الغيبة والنميمة وقول الخير',
      'verse': '﴿مَّا يَلْفِظُ مِن قَوْلٍ إِلَّا لَدَيْهِ رَقِيبٌ عَتِيدٌ﴾ [ق: ١٨]',
    },
    {
      'id': 'sadaqah_ihsan',
      'title': 'صدقة اليوم أو قضاء حاجة مسلم أو كلمة طيبة',
      'verse': '﴿مَّن ذَا الَّذِي يُقْرِضُ اللَّهَ قَرْضًا حَسَنًا فَيُضَاعِفَهُ لَهُ أَضْعَافًا كَثِيرَةً﴾ [البقرة: ٢٤٥]',
    },
    {
      'id': 'istighfar_tawbah',
      'title': 'تجديد التوبة والاستغفار مائة مرة في اليوم',
      'verse': '﴿وَأَنِ اسْتَغْفِرُوا رَبَّكُمْ ثُمَّ تُوبُوا إِلَيْهِ يُمَتِّعْكُم مَّتَاعًا حَسَنًا﴾ [هود: ٣]',
    },
    {
      'id': 'afk_afw',
      'title': 'العفو والصفح وتطهير القلب من الغل والحسد',
      'verse': '﴿وَلَا تَجْعَلْ فِي قُلُوبِنَا غِلًّا لِّلَّذِينَ آمَنُوا﴾ [الحشر: ١٠]',
    },
  ];

  static final List<TadabburReflectionItem> _defaultInspiringReflections = [
    TadabburReflectionItem(
      id: 'seed_1',
      surahId: 1,
      surahName: 'الفاتحة',
      ayahNumber: 5,
      ayahSnippet: '﴿إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ﴾',
      faithMessage: 'تجمع هذه الآية سر القرآن كله: التبرؤ من الشرك والرياء بـ (إياك نعبد)، والتبرؤ من الحول والقوة إلا بالله بـ (وإياك نستعين).',
      practicalAction: 'أجدد نيتي قبل كل عمل اليوم وأستعين بالله قبل البدء في أي مهمة.',
      derivedDua: 'اللهم أعنّي على ذكرك وشكرك وحسن عبادتك.',
      createdAt: DateTime(2026, 10, 1),
    ),
    TadabburReflectionItem(
      id: 'seed_2',
      surahId: 65,
      surahName: 'الطلاق',
      ayahNumber: 2,
      ayahSnippet: '﴿وَمَن يَتَّقِ اللَّهَ يَجْعَل لَّهُ مَخْرَجًا ۝ وَيَرْزُقْهُ مِنْ حَيْثُ لَا يَحْتَسِبُ﴾',
      faithMessage: 'وعد رباني قاطع بأن تقوى الله في السر والعلن هي مفتاح الفرج من كل ضيق وباب الرزق غير المتوقع.',
      practicalAction: 'مراقبة الله في الكسب والمعاملة والابتعاد عن كل شبهة طمعاً في كفاية الله.',
      derivedDua: 'اللهم ارزقني تقواك في الغيب والشهادة واكفني بحلالك عن حرامك.',
      createdAt: DateTime(2026, 10, 2),
    ),
  ];

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> init({bool forceReload = false}) {
    return _enqueue(() => _initInternal(forceReload: forceReload));
  }

  Future<void> _initInternal({bool forceReload = false}) async {
    try {
      if (_isInitialized && !forceReload && _isReadable) return;
      final prefs = await SharedPreferences.getInstance();

      await _reloadAndSyncFromHost(prefs);

      final rawAcc = prefs.getString(_dailyAccountabilityKey);
      if (rawAcc != null && rawAcc.isNotEmpty) {
        try {
          final Map<String, dynamic> map = json.decode(rawAcc);
          _dailyAccountability.clear();
          map.forEach((k, v) {
            if (v is List) {
              _dailyAccountability[k] = v.map((e) => e.toString()).toSet();
            }
          });
        } catch (_) {}
      }

      _isInitialized = true;
    } catch (_) {
      _isReadable = false;
      notifyListeners();
    }
  }

  /// Common private path for host reload, read, decode, materialize, and publish.
  /// 
  /// Baseline 138e semantics:
  /// - null/EMPTYSTRING => NO decode / live UNTOUCHED. Trusted null/'' marks readable but livePublished = false.
  /// - literal '[]' => decode + CLEAR live, livePublished = true.
  /// - valid non-empty entries => decode + set live, livePublished = true.
  /// - ANY malformed entry => WHOLE list rejected, last good live unchanged, latch unreadable, livePublished = false.
  /// - reload failure / exception => keeps last good live, marks latch unreadable, livePublished = false.
  Future<bool> _reloadAndSyncFromHost(SharedPreferences prefs) async {
    try {
      await prefs.reload();

      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) {
        // null/EMPTYSTRING => NO decode / live UNTOUCHED; trusted null/'' marks readable, livePublished = false
        _isReadable = true;
        notifyListeners();
        return false;
      }

      final decodedList = JournalMergeUtil.safeDecodeJournalEntries(raw);
      if (decodedList == null) {
        // ANY malformed entry => WHOLE list rejected, last good live unchanged, primary bytes untouched, latch unreadable
        _isReadable = false;
        notifyListeners();
        return false;
      }

      // Valid decoded list (including explicit literal '[]' which clears live):
      // Materialize full modelList BEFORE clearing live
      final modelList = decodedList.map((e) => TadabburReflectionItem.fromJson(e)).toList();
      _entries
        ..clear()
        ..addAll(modelList);
      _isReadable = true;
      notifyListeners();
      return true;
    } catch (_) {
      // Catch ENTIRE host read / getString / decode / full model materialization path:
      // keeps last good live, marks latch unreadable
      _isReadable = false;
      notifyListeners();
      return false;
    }
  }

  Future<JournalOperationResult> addReflection({
    required int surahId,
    required String surahName,
    required int ayahNumber,
    required String ayahSnippet,
    required String faithMessage,
    required String practicalAction,
    required String derivedDua,
  }) {
    return _enqueue(() => _addReflectionInternal(
          surahId: surahId,
          surahName: surahName,
          ayahNumber: ayahNumber,
          ayahSnippet: ayahSnippet,
          faithMessage: faithMessage,
          practicalAction: practicalAction,
          derivedDua: derivedDua,
        ));
  }

  Future<JournalOperationResult> _addReflectionInternal({
    required int surahId,
    required String surahName,
    required int ayahNumber,
    required String ayahSnippet,
    required String faithMessage,
    required String practicalAction,
    required String derivedDua,
  }) async {
    try {
      // Refuse before mutation if unreadable
      if (!_isReadable) {
        return const JournalOperationResult(
          status: JournalOperationStatus.refusedUnreadable,
          livePublished: false,
        );
      }

      final item = TadabburReflectionItem(
        id: 'tadabbur_${DateTime.now().millisecondsSinceEpoch}',
        surahId: surahId,
        surahName: surahName,
        ayahNumber: ayahNumber,
        ayahSnippet: ayahSnippet,
        faithMessage: faithMessage,
        practicalAction: practicalAction,
        derivedDua: derivedDua,
        createdAt: DateTime.now(),
      );

      // Compute candidate without live mutation
      final candidateList = [item, ..._entries];
      final candidateJson = json.encode(candidateList.map((e) => e.toJson()).toList());

      final prefs = await SharedPreferences.getInstance();
      bool writeSuccess = false;
      try {
        writeSuccess = await prefs.setString(_storageKey, candidateJson);
      } catch (_) {
        writeSuccess = false;
      }

      if (writeSuccess) {
        _entries
          ..clear()
          ..addAll(candidateList);
        notifyListeners();
        return const JournalOperationResult(
          status: JournalOperationStatus.persisted,
          livePublished: true,
        );
      }

      // false/throw ALWAYS writeUnconfirmed, never inferred success from readback.
      // SAME queue attempt host reload to evict optimistic cache
      final published = await _reloadAndSyncFromHost(prefs);
      return JournalOperationResult(
        status: JournalOperationStatus.writeUnconfirmed,
        livePublished: published,
      );
    } catch (_) {
      _isReadable = false;
      notifyListeners();
      return const JournalOperationResult(
        status: JournalOperationStatus.writeUnconfirmed,
        livePublished: false,
      );
    }
  }

  Future<JournalOperationResult> deleteReflection(String id) {
    return _enqueue(() => _deleteReflectionInternal(id));
  }

  Future<JournalOperationResult> _deleteReflectionInternal(String id) async {
    try {
      if (!_isReadable) {
        return const JournalOperationResult(
          status: JournalOperationStatus.refusedUnreadable,
          livePublished: false,
        );
      }

      final candidateList = _entries.where((e) => e.id != id).toList();
      final candidateJson = json.encode(candidateList.map((e) => e.toJson()).toList());

      final prefs = await SharedPreferences.getInstance();
      bool writeSuccess = false;
      try {
        writeSuccess = await prefs.setString(_storageKey, candidateJson);
      } catch (_) {
        writeSuccess = false;
      }

      if (writeSuccess) {
        _entries
          ..clear()
          ..addAll(candidateList);
        notifyListeners();
        return const JournalOperationResult(
          status: JournalOperationStatus.persisted,
          livePublished: true,
        );
      }

      final published = await _reloadAndSyncFromHost(prefs);
      return JournalOperationResult(
        status: JournalOperationStatus.writeUnconfirmed,
        livePublished: published,
      );
    } catch (_) {
      _isReadable = false;
      notifyListeners();
      return const JournalOperationResult(
        status: JournalOperationStatus.writeUnconfirmed,
        livePublished: false,
      );
    }
  }

  Future<JournalRestoreResult> restoreJournal({
    required String rawImport,
    required bool replaceMode,
  }) {
    return _enqueue(() => _restoreJournalInternal(
          rawImport: rawImport,
          replaceMode: replaceMode,
        ));
  }

  Future<JournalRestoreResult> _restoreJournalInternal({
    required String rawImport,
    required bool replaceMode,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (replaceMode) {
        // restore replace: ignore latch, setString rawVERBATIM incl malformed/nonlist/empty as PR21.
        bool writeSuccess = false;
        try {
          writeSuccess = await prefs.setString(_storageKey, rawImport);
        } catch (_) {
          writeSuccess = false;
        }

        // Storage write confirmed or failed: read back actual host storage
        // Note: Replace '' writes verbatim KEY REMAINS and does NOT clear live per baseline 138e.
        final published = await _reloadAndSyncFromHost(prefs);
        if (writeSuccess) {
          return JournalRestoreResult(
            status: JournalRestoreStatus.confirmedWrite,
            livePublished: published,
          );
        } else {
          return JournalRestoreResult(
            status: JournalRestoreStatus.writeUnconfirmed,
            livePublished: published,
          );
        }
      } else {
        // restore merge: unconditional HOST reload INSIDE queue BEFORE local read;
        // failure => writeUnconfirmed / no write, latch unreadable
        try {
          await prefs.reload();
        } catch (_) {
          _isReadable = false;
          notifyListeners();
          return const JournalRestoreResult(
            status: JournalRestoreStatus.writeUnconfirmed,
            livePublished: false,
          );
        }

        // Validate fresh LOCAL FIRST before malformed IMPORT skip, so known corrupt local cannot stay readable
        final rawLocal = prefs.getString(_storageKey);
        final localList = (rawLocal == null || rawLocal.isEmpty)
            ? <Map<String, dynamic>>[]
            : JournalMergeUtil.safeDecodeJournalEntries(rawLocal);
        if (localList == null) {
          // malformed local must latch unreadable before return so later add cannot overwrite
          _isReadable = false;
          notifyListeners();
          return const JournalRestoreResult(
            status: JournalRestoreStatus.intentionalSkip,
            livePublished: false,
          );
        }

        // Validate IMPORT: unreadable import => whole-key skip per PR 21 / no write
        final importedList = JournalMergeUtil.safeDecodeJournalEntries(rawImport);
        if (importedList == null) {
          // malformed IMPORT skip after readable fresh LOCAL must establish actual host live/latch, actual skip livePublished
          final published = await _reloadAndSyncFromHost(prefs);
          return JournalRestoreResult(
            status: JournalRestoreStatus.intentionalSkip,
            livePublished: published,
          );
        }

        // otherwise exact PR 21 union/remap/inputorder/unknownrawpreservation.
        final merged = JournalMergeUtil.mergeJournalEntries(
          localList: localList,
          importedList: importedList,
        );
        final mergedJson = json.encode(merged);

        // Unchanged raw merge no-write guard:
        // Must perform actual host decode/materialize/publish and return accurate flag without write!
        if (rawLocal != null && rawLocal.isNotEmpty && mergedJson == rawLocal) {
          final published = await _reloadAndSyncFromHost(prefs);
          return JournalRestoreResult(
            status: JournalRestoreStatus.intentionalSkip,
            livePublished: published,
          );
        }

        bool writeSuccess = false;
        try {
          writeSuccess = await prefs.setString(_storageKey, mergedJson);
        } catch (_) {
          writeSuccess = false;
        }

        final published = await _reloadAndSyncFromHost(prefs);
        if (writeSuccess) {
          return JournalRestoreResult(
            status: JournalRestoreStatus.confirmedWrite,
            livePublished: published,
          );
        } else {
          return JournalRestoreResult(
            status: JournalRestoreStatus.writeUnconfirmed,
            livePublished: published,
          );
        }
      }
    } catch (_) {
      _isReadable = false;
      notifyListeners();
      return const JournalRestoreResult(
        status: JournalRestoreStatus.writeUnconfirmed,
        livePublished: false,
      );
    }
  }

  bool isEthicalItemDoneToday(String itemId) {
    return _dailyAccountability[_todayKey()]?.contains(itemId) ?? false;
  }

  static Map<String, List<String>>? safeDecodeAccountability(String raw) {
    try {
      final dynamic decoded = json.decode(raw);
      if (decoded is! Map) return null;
      final result = <String, List<String>>{};
      for (final entry in decoded.entries) {
        if (entry.key is! String) return null;
        if (entry.value is! List) return null;
        final list = entry.value as List;
        final stringList = <String>[];
        for (final item in list) {
          if (item is! String) return null;
          stringList.add(item);
        }
        result[entry.key as String] = stringList;
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  Future<AccountabilityRestoreResult> restoreAccountability({
    required String rawImport,
    required bool replaceMode,
  }) {
    return _enqueue(() => _restoreAccountabilityInternal(
          rawImport: rawImport,
          replaceMode: replaceMode,
        ));
  }

  Future<AccountabilityRestoreResult> restoreAccountabilityReplace(
    String rawImport,
  ) {
    return restoreAccountability(rawImport: rawImport, replaceMode: true);
  }

  Future<AccountabilityRestoreResult> restoreAccountabilityMerge(
    String rawImport,
  ) {
    return restoreAccountability(rawImport: rawImport, replaceMode: false);
  }

  Future<AccountabilityRestoreResult> _restoreAccountabilityInternal({
    required String rawImport,
    required bool replaceMode,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (replaceMode) {
        bool writeSuccess = false;
        try {
          writeSuccess =
              await prefs.setString(_dailyAccountabilityKey, rawImport);
        } catch (_) {
          writeSuccess = false;
        }

        final published = await _reloadAndSyncAccountabilityFromHost(prefs);
        if (writeSuccess) {
          return AccountabilityRestoreResult(
            status: AccountabilityRestoreStatus.confirmedWrite,
            livePublished: published,
          );
        } else {
          return AccountabilityRestoreResult(
            status: AccountabilityRestoreStatus.writeUnconfirmed,
            livePublished: published,
          );
        }
      } else {
        try {
          await prefs.reload();
        } catch (_) {
          return const AccountabilityRestoreResult(
            status: AccountabilityRestoreStatus.writeUnconfirmed,
            livePublished: false,
          );
        }

        final rawLocal = prefs.getString(_dailyAccountabilityKey);
        final localMap = (rawLocal == null || rawLocal.isEmpty)
            ? <String, List<String>>{}
            : safeDecodeAccountability(rawLocal);
        if (localMap == null) {
          final published = await _reloadAndSyncAccountabilityFromHost(prefs);
          return AccountabilityRestoreResult(
            status: AccountabilityRestoreStatus.intentionalSkip,
            livePublished: published,
          );
        }

        final importedMap = safeDecodeAccountability(rawImport);
        if (importedMap == null) {
          final published = await _reloadAndSyncAccountabilityFromHost(prefs);
          return AccountabilityRestoreResult(
            status: AccountabilityRestoreStatus.intentionalSkip,
            livePublished: published,
          );
        }

        final allDates = {...localMap.keys, ...importedMap.keys}.toList()..sort();
        final mergedMap = <String, List<String>>{};
        for (final date in allDates) {
          final localTasks = localMap[date] ?? const <String>[];
          final importTasks = importedMap[date] ?? const <String>[];
          mergedMap[date] = {...localTasks, ...importTasks}.toList();
        }
        final mergedJson = json.encode(mergedMap);

        if (rawLocal != null && rawLocal.isNotEmpty && mergedJson == rawLocal) {
          final published = await _reloadAndSyncAccountabilityFromHost(prefs);
          return AccountabilityRestoreResult(
            status: AccountabilityRestoreStatus.intentionalSkip,
            livePublished: published,
          );
        }

        bool writeSuccess = false;
        try {
          writeSuccess =
              await prefs.setString(_dailyAccountabilityKey, mergedJson);
        } catch (_) {
          writeSuccess = false;
        }

        final published = await _reloadAndSyncAccountabilityFromHost(prefs);
        if (writeSuccess) {
          return AccountabilityRestoreResult(
            status: AccountabilityRestoreStatus.confirmedWrite,
            livePublished: published,
          );
        } else {
          return AccountabilityRestoreResult(
            status: AccountabilityRestoreStatus.writeUnconfirmed,
            livePublished: published,
          );
        }
      }
    } catch (_) {
      return const AccountabilityRestoreResult(
        status: AccountabilityRestoreStatus.writeUnconfirmed,
        livePublished: false,
      );
    }
  }

  Future<bool> _reloadAndSyncAccountabilityFromHost(
      SharedPreferences prefs) async {
    try {
      await prefs.reload();
    } catch (_) {
      return false;
    }
    final rawAcc = prefs.getString(_dailyAccountabilityKey);
    if (rawAcc == null || rawAcc.isEmpty) {
      return false;
    }
    try {
      final decoded = json.decode(rawAcc);
      if (decoded is Map) {
        _dailyAccountability.clear();
        decoded.forEach((k, v) {
          if (v is List) {
            _dailyAccountability[k.toString()] =
                v.map((e) => e.toString()).toSet();
          }
        });
        notifyListeners();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<AccountabilityToggleResult> toggleEthicalItemToday(
      String itemId) {
    return _enqueue(() => _toggleEthicalItemTodayInternal(itemId));
  }

  Future<AccountabilityToggleResult> _toggleEthicalItemTodayInternal(
      String itemId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      try {
        await prefs.reload();
      } catch (_) {
        return const AccountabilityToggleResult(
          status: AccountabilityOperationStatus.writeUnconfirmed,
          livePublished: false,
        );
      }

      final rawAcc = prefs.getString(_dailyAccountabilityKey);
      final Map<String, List<String>> hostDecoded;
      if (rawAcc == null || rawAcc.isEmpty) {
        hostDecoded = <String, List<String>>{};
      } else {
        final decoded = safeDecodeAccountability(rawAcc);
        if (decoded == null) {
          return const AccountabilityToggleResult(
            status: AccountabilityOperationStatus.writeRefusedUnreadable,
            livePublished: false,
          );
        }
        hostDecoded = decoded;
      }

      final candidateMap = <String, List<String>>{};
      for (final entry in hostDecoded.entries) {
        candidateMap[entry.key] = List<String>.from(entry.value);
      }
      final today = _todayKey();
      final todayList =
          List<String>.from(candidateMap[today] ?? const <String>[]);
      if (todayList.contains(itemId)) {
        todayList.removeWhere((item) => item == itemId);
      } else {
        todayList.add(itemId);
      }
      candidateMap[today] = todayList;
      final candidateJson = json.encode(candidateMap);

      bool writeSuccess = false;
      try {
        writeSuccess =
            await prefs.setString(_dailyAccountabilityKey, candidateJson);
      } catch (_) {
        writeSuccess = false;
      }

      if (writeSuccess) {
        _dailyAccountability.clear();
        candidateMap.forEach((k, v) {
          _dailyAccountability[k] = Set<String>.from(v);
        });
        notifyListeners();
        return const AccountabilityToggleResult(
          status: AccountabilityOperationStatus.persisted,
          livePublished: true,
        );
      } else {
        final published = await _reloadAndSyncAccountabilityFromHost(prefs);
        return AccountabilityToggleResult(
          status: AccountabilityOperationStatus.writeUnconfirmed,
          livePublished: published,
        );
      }
    } catch (_) {
      return const AccountabilityToggleResult(
        status: AccountabilityOperationStatus.writeUnconfirmed,
        livePublished: false,
      );
    }
  }
}
