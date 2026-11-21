import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/islamic_libraries_models.dart';

/// خدمة «الورد اليومي الذكي وخطة الطاعات المتكاملة»
class DailyWirdService extends ChangeNotifier {
  static final DailyWirdService instance = DailyWirdService._internal();
  DailyWirdService._internal();

  static const String _prefKey = 'daily_wird_records_v1';
  bool _initialized = false;
  Future<void> _operations = Future<void>.value();

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _operations.then((_) => action());
    _operations =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  /// Map of YYYY-MM-DD -> List of completed task IDs
  final Map<String, Set<String>> _dailyRecords = {};

  static const List<DailyWirdTaskItem> defaultTasks = [
    DailyWirdTaskItem(
      id: 'wird_fajr_sunnah',
      title: 'ركعتا سنة الفجر وصلاة الفجر في وقتها',
      subtitle: '«ركعتا الفجر خير من الدنيا وما فيها»',
      timeSlot: 'الفجر والصباح',
      rewardPoints: 20,
      icon: Icons.wb_twilight_rounded,
    ),
    DailyWirdTaskItem(
      id: 'wird_morning_adhkar',
      title: 'أذكار الصباح كاملة مع آية الكرسي والمعوذات',
      subtitle: 'حصن المؤمن وأمانه وطمأنينة قلبه في بداية اليوم',
      timeSlot: 'الفجر والصباح',
      rewardPoints: 15,
      icon: Icons.wb_sunny_rounded,
    ),
    DailyWirdTaskItem(
      id: 'wird_duha_prayer',
      title: 'صلاة الضحى (صلاة الأوابين)',
      subtitle: 'تجزئ عن ٣٦٠ صدقة على كل سلامى منابن آدم',
      timeSlot: 'الفجر والصباح',
      rewardPoints: 15,
      icon: Icons.light_mode_rounded,
    ),
    DailyWirdTaskItem(
      id: 'wird_quran_portion',
      title: 'ورد التلاوة اليومي من القرآن الكريم (صفحتان أو حزب)',
      subtitle: 'قراءة بتدبر وترتيل مع متابعة ختمة القرآن',
      timeSlot: 'الظهيرة والعصر',
      rewardPoints: 25,
      icon: Icons.menu_book_rounded,
    ),
    DailyWirdTaskItem(
      id: 'wird_rawatib_sunnah',
      title: 'السنن الرواتب المؤكدة (١٢ ركعة في اليوم والليلة)',
      subtitle: 'يبني الله لمن واظب عليها بيتاً في الجنة',
      timeSlot: 'الظهيرة والعصر',
      rewardPoints: 20,
      icon: Icons.mosque_rounded,
    ),
    DailyWirdTaskItem(
      id: 'wird_evening_adhkar',
      title: 'أذكار المساء والاستغفار (١٠٠ مرة) والصلاة على النبي ﷺ',
      subtitle: 'تفريج الهموم وزيادة الإيمان والبركة',
      timeSlot: 'العصر والمساء',
      rewardPoints: 15,
      icon: Icons.nights_stay_rounded,
    ),
    DailyWirdTaskItem(
      id: 'wird_knowledge_reading',
      title: 'فائدة علمية يومية (حديث نبوي أو مسألة فقهية)',
      subtitle: '«من يرد الله به خيراً يفقهه في الدين»',
      timeSlot: 'العصر والمساء',
      rewardPoints: 15,
      icon: Icons.auto_stories_rounded,
    ),
    DailyWirdTaskItem(
      id: 'wird_witr_mulk_sleep',
      title: 'صلاة الوتر، سورة الملك، وأذكار النوم',
      subtitle: 'ختام اليوم بالوتر والنجاة من عذاب القبر',
      timeSlot: 'الليل والوتر',
      rewardPoints: 20,
      icon: Icons.bedtime_rounded,
    ),
  ];

  String _todayKey([DateTime? date]) {
    final d = date ?? DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> init({bool forceReload = false}) {
    if (_initialized && !forceReload) return Future<void>.value();
    return _serialize(() async {
      await _load(forceReload: forceReload);
    });
  }

  Future<bool> _load({bool forceReload = false}) async {
    if (_initialized && !forceReload) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (forceReload) await prefs.reload();
      final raw = prefs.getString(_prefKey);
      final next = <String, Set<String>>{};
      if (raw != null && raw.isNotEmpty) {
        final decoded = json.decode(raw) as Map<String, dynamic>;
        decoded.forEach((k, v) {
          if (v is List) next[k] = v.map((e) => e.toString()).toSet();
        });
      }
      _dailyRecords
        ..clear()
        ..addAll(next);
      _initialized = true;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('DailyWirdService load error: $e');
      return false;
    }
  }

  Set<String> getCompletedToday([DateTime? date]) {
    final key = _todayKey(date);
    return Set.unmodifiable(_dailyRecords[key] ?? const <String>{});
  }

  bool isCompleted(String taskId, [DateTime? date]) {
    final key = _todayKey(date);
    return _dailyRecords[key]?.contains(taskId) ?? false;
  }

  double getTodayCompletionRatio([DateTime? date]) {
    if (defaultTasks.isEmpty) return 0.0;
    final done = getCompletedToday(date).length;
    return (done / defaultTasks.length).clamp(0.0, 1.0);
  }

  int getTodayPoints([DateTime? date]) {
    final done = getCompletedToday(date);
    return defaultTasks
        .where((t) => done.contains(t.id))
        .fold(0, (sum, t) => sum + t.rewardPoints);
  }

  int getCurrentStreakDays() {
    int streak = 0;
    final now = DateTime.now();
    for (int i = 0; i < 365; i++) {
      final d = now.subtract(Duration(days: i));
      final key = _todayKey(d);
      final completed = _dailyRecords[key];
      if (completed != null && completed.isNotEmpty) {
        streak++;
      } else if (i > 0) {
        break;
      }
    }
    return streak;
  }

  Future<bool> toggleTask(String taskId, [DateTime? date]) {
    // Capture the requested day before waiting in the queue (including midnight).
    final key = _todayKey(date);
    return _serialize(() async {
      if (!await _load()) return false;
      final next = _copyRecords();
      final tasks = next.putIfAbsent(key, () => <String>{});
      if (!tasks.add(taskId)) tasks.remove(taskId);
      return _persist(next);
    });
  }

  Map<String, Set<String>> _copyRecords() =>
      _dailyRecords.map((k, v) => MapEntry(k, Set<String>.of(v)));

  Future<bool> _persist(Map<String, Set<String>> next) async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      final serializable = next.map((k, v) => MapEntry(k, v.toList()));
      if (!await prefs.setString(_prefKey, json.encode(serializable))) {
        throw StateError('Daily wird write rejected');
      }
      _dailyRecords
        ..clear()
        ..addAll(next);
      notifyListeners();
      return true;
    } catch (e) {
      // The plugin cache changes before the platform result is known.
      try {
        await prefs?.reload();
      } catch (reloadError) {
        debugPrint('DailyWirdService cache reload error: $reloadError');
      }
      debugPrint('DailyWirdService save error: $e');
      return false;
    }
  }

  Map<String, dynamic> exportData() =>
      _dailyRecords.map((k, v) => MapEntry(k, v.toList()));

  Future<void> importData(Map<String, dynamic> imported,
      {bool replace = false}) {
    // Snapshot caller-owned lists before another queued operation can delay us.
    final incoming = <String, Set<String>>{};
    imported.forEach((k, v) {
      if (v is List) incoming[k] = v.map((e) => e.toString()).toSet();
    });
    return _serialize(() async {
      if (!await _load()) throw StateError('Daily wird could not be loaded');
      final next = replace ? <String, Set<String>>{} : _copyRecords();
      incoming.forEach((k, v) {
        next.putIfAbsent(k, () => <String>{}).addAll(v);
      });
      if (!await _persist(next)) {
        throw StateError('Daily wird could not be saved');
      }
    });
  }
}
