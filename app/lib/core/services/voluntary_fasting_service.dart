import 'dart:convert';
import 'prayer_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// نموذج نوع الصيام التطوعي النبوي
class VoluntaryFastType {
  final String id;
  final String title;
  final String scheduleRule;
  final String propheticVirtue;
  final String hadithSource;
  final String category; // 'أسبوعي', 'شهري', 'موسمي'
  final int targetDaysPerPeriod;

  const VoluntaryFastType({
    required this.id,
    required this.title,
    required this.scheduleRule,
    required this.propheticVirtue,
    required this.hadithSource,
    required this.category,
    required this.targetDaysPerPeriod,
  });
}

/// خدمة تخطيط ومتابعة الصيام التطوعي والأيام البيض والسنن الموسمية
class VoluntaryFastingService extends ChangeNotifier {
  static final VoluntaryFastingService instance =
      VoluntaryFastingService._internal();
  VoluntaryFastingService._internal();

  static const List<VoluntaryFastType> fastTypes = [
    VoluntaryFastType(
      id: 'monday_thursday',
      title: 'صيام يومي الإثنين والخميس',
      scheduleRule: 'كل يوم إثنين وخميس من كل أسبوع',
      propheticVirtue:
          'قال رسول الله ﷺ: «تُعْرَضُ الأَعْمَالُ يَوْمَ الاِثْنَيْنِ وَالْخَمِيسِ، فَأُحِبُّ أَنْ يُعْرَضَ عَمَلِي وَأَنَا صَائِمٌ»',
      hadithSource: 'رواه الترمذي وصححه الألباني',
      category: 'أسبوعي',
      targetDaysPerPeriod: 8,
    ),
    VoluntaryFastType(
      id: 'white_days',
      title: 'صيام الأيام البيض (١٣، ١٤، ١٥ هجرياً)',
      scheduleRule: 'اليوم الثالث عشر والرابع عشر والخامس عشر من كل شهر هجري',
      propheticVirtue:
          'قال رسول الله ﷺ لأبي ذر رضي الله عنه: «يَا أَبَا ذَرٍّ إِذَا صُمْتَ مِنَ الشَّهْرِ ثَلاَثَةَ أَيَّامٍ فَصُمْ ثَلاَثَ عَشْرَةَ وَأَرْبَعَ عَشْرَةَ وَخَمْسَ عَشْرَةَ» — وهي كصيام الدهر.',
      hadithSource: 'متفق على أصل صيام ثلاثة أيام من كل شهر',
      category: 'شهري',
      targetDaysPerPeriod: 3,
    ),
    VoluntaryFastType(
      id: 'six_shawwal',
      title: 'صيام الست من شوال',
      scheduleRule: 'ستة أيام من شهر شوال بعد عيد الفطر (متتابعة أو متفرقة)',
      propheticVirtue:
          'قال رسول الله ﷺ: «مَنْ صَامَ رَمَضَانَ ثُمَّ أَتْبَعَهُ سِتّاً مِنْ شَوَّالٍ كَانَ كَصِيَامِ الدَّهْرِ»',
      hadithSource: 'صحيح مسلم',
      category: 'موسمي',
      targetDaysPerPeriod: 6,
    ),
    VoluntaryFastType(
      id: 'day_of_arafah',
      title: 'صيام يوم عرفة (٩ ذو الحجة لغير الحاج)',
      scheduleRule: 'اليوم التاسع من شهر ذي الحجة',
      propheticVirtue:
          'قال رسول الله ﷺ: «صِيَامُ يَوْمِ عَرَفَةَ أَحْتَسِبُ عَلَى اللَّهِ أَنْ يُكَفِّرَ السَّنَةَ الَّتِي قَبْلَهُ وَالسَّنَةَ الَّتِي بَعْدَهُ»',
      hadithSource: 'صحيح مسلم',
      category: 'موسمي',
      targetDaysPerPeriod: 1,
    ),
    VoluntaryFastType(
      id: 'tasua_ashura',
      title: 'صيام تاسوعاء وعاشوراء (٩ و١٠ محرم)',
      scheduleRule: 'اليوم التاسع والعاشر من شهر الله المحرم',
      propheticVirtue:
          'قال رسول الله ﷺ: «صِيَامُ يَوْمِ عَاشُورَاءَ أَحْتَسِبُ عَلَى اللَّهِ أَنْ يُكَفِّرَ السَّنَةَ الَّتِي قَبْلَهُ» وقال: «لَئِنْ بَقِيتُ إِلَى قَابِلٍ لأَصُومَنَّ التَّاسِعَ»',
      hadithSource: 'صحيح مسلم',
      category: 'موسمي',
      targetDaysPerPeriod: 2,
    ),
    VoluntaryFastType(
      id: 'nine_dhul_hijjah',
      title: 'صيام العشر الأوائل من ذي الحجة (١ - ٩ ذو الحجة)',
      scheduleRule: 'الأيام التسعة الأولى من شهر ذي الحجة',
      propheticVirtue:
          'قال رسول الله ﷺ: «مَا مِنْ أَيَّامٍ الْعَمَلُ الصَّالِحُ فِيهِنَّ أَحَبُّ إِلَى اللَّهِ مِنْ هَذِهِ الأَيَّامِ الْعَشْرِ»',
      hadithSource: 'صحيح البخاري',
      category: 'موسمي',
      targetDaysPerPeriod: 9,
    ),
    VoluntaryFastType(
      id: 'shaban_fasting',
      title: 'الإكثار من الصيام في شهر شعبان',
      scheduleRule: 'أغلب أيام شهر شعبان تمهيداً لشهر رمضان',
      propheticVirtue:
          'قالت عائشة رضي الله عنها: «مَا رَأَيْتُ رَسُولَ اللَّهِ ﷺ أَكْثَرَ صِيَاماً مِنْهُ فِي شَعْبَانَ»',
      hadithSource: 'متفق عليه',
      category: 'موسمي',
      targetDaysPerPeriod: 10,
    ),
  ];

  static const String iftarDua =
      '«ذَهَبَ الظَّمَأُ وَابْتَلَّتِ الْعُرُوقُ، وَثَبَتَ الأَجْرُ إِنْ شَاءَ اللَّهُ» (رواه أبو داود)';

  static const String intentionNote =
      'يجوز في صيام النافلة عقد النية من الليل، ويجوز إنشاؤها من النهار قبل الزوال بشرط ألا يكون قد تناول مفطراً بعد الفجر.';

  final Map<String, int> _completedCounts = {};
  final List<String> _fastedDateLogs = []; // 'YYYY-MM-DD|fastId'
  bool _suhoorReminderEnabled = true;
  bool _progressLoadFailed = false;
  bool get progressLoadFailed => _progressLoadFailed;

  Map<String, int> get completedCounts => Map.unmodifiable(_completedCounts);
  List<String> get fastedDateLogs => List.unmodifiable(_fastedDateLogs);
  bool get suhoorReminderEnabled => _suhoorReminderEnabled;

  int get totalFastedDays =>
      _completedCounts.values.fold<int>(0, (sum, val) => sum + val);

  Future<void> _operations = Future<void>.value();

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _operations.then((_) => action());
    _operations =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  static const _progressKey = 'voluntary_fast_progress_v1';

  _FastingProgress _readProgress(SharedPreferences prefs) {
    final raw = prefs.getString(_progressKey);
    if (raw == null) {
      return _FastingProgress(
        {
          for (final type in fastTypes)
            type.id: prefs.getInt('vfast_count_${type.id}') ?? 0
        },
        List<String>.of(prefs.getStringList('vfast_date_logs') ?? const []),
      );
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] != 1 ||
        decoded['counts'] is! Map ||
        decoded['date_logs'] is! List) {
      throw const FormatException('Invalid fasting progress snapshot');
    }
    final counts = decoded['counts'] as Map;
    final logs = decoded['date_logs'] as List;
    if (counts.entries.any((e) => e.key is! String || e.value is! int) ||
        logs.any((e) => e is! String)) {
      throw const FormatException('Invalid fasting progress values');
    }
    return _FastingProgress(
        Map<String, int>.from(counts), List<String>.from(logs));
  }

  bool _publishProgress(_FastingProgress progress) {
    final counts = {
      for (final type in fastTypes) type.id: progress.counts[type.id] ?? 0,
    };
    final changed = _progressLoadFailed ||
        !mapEquals(_completedCounts, counts) ||
        !listEquals(_fastedDateLogs, progress.logs);
    _progressLoadFailed = false;
    _completedCounts
      ..clear()
      ..addAll(counts);
    _fastedDateLogs
      ..clear()
      ..addAll(progress.logs);
    return changed;
  }

  Future<bool> _saveProgress(
      SharedPreferences prefs, _FastingProgress progress) async {
    final encoded = jsonEncode({'version': 1, ...progress.toBackup()});
    var confirmed = false;
    try {
      confirmed = await prefs.setString(_progressKey, encoded);
    } catch (_) {}
    if (!confirmed) {
      // A lost acknowledgement may follow a committed write. Confirm from the
      // provider, never from the plugin's optimistic cache, before retrying.
      try {
        await prefs.reload();
        if (prefs.getString(_progressKey) != encoded) return false;
      } catch (_) {
        _progressLoadFailed = true;
        notifyListeners();
        return false;
      }
    }
    _publishProgress(progress);
    notifyListeners();
    return true;
  }

  Future<void> init({bool forceReload = false}) => _serialize(() async {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.reload();
          _suhoorReminderEnabled =
              prefs.getBool('voluntary_fast_suhoor_reminder') ?? true;
          final progress = _readProgress(prefs);
          _publishProgress(progress);
        } catch (_) {
          // Never replace an unreadable authoritative snapshot with legacy data.
          _progressLoadFailed = true;
        }
        notifyListeners();
      });

  int getCountForType(String fastId) => _completedCounts[fastId] ?? 0;

  Future<bool> logFastedDay(String fastId, {DateTime? date}) async {
    final d = date ?? DateTime.now();
    final dateStr =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final entry = '$dateStr|$fastId';
    return _serialize(() async {
      if (_progressLoadFailed) return false;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        final progress = _readProgress(prefs);
        if (progress.logs.contains(entry)) {
          if (_publishProgress(progress)) notifyListeners();
          return true;
        }
        progress.logs.insert(0, entry);
        progress.counts[fastId] = (progress.counts[fastId] ?? 0) + 1;
        return await _saveProgress(prefs, progress);
      } catch (_) {
        return false;
      }
    });
  }

  Future<bool> decrementFastCount(String fastId) => _serialize(() async {
        if (_progressLoadFailed) return false;
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.reload();
          final progress = _readProgress(prefs);
          final current = progress.counts[fastId] ?? 0;
          if (current <= 0) {
            if (_publishProgress(progress)) notifyListeners();
            return true;
          }
          progress.counts[fastId] = current - 1;
          final index = progress.logs.indexWhere((e) => e.endsWith('|$fastId'));
          if (index >= 0) progress.logs.removeAt(index);
          return await _saveProgress(prefs, progress);
        } catch (_) {
          return false;
        }
      });

  /// Keep the existing backup shape while reading one consistent durable unit.
  Future<Map<String, dynamic>> exportProgress() => _serialize(() async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        return _readProgress(prefs).toBackup();
      });

  /// Preserve partial replace and max-count/union-log merge semantics.
  Future<bool> restoreProgress(Map data, {required bool replaceMode}) =>
      _serialize(() async {
        final logs = data['date_logs'];
        final counts = data['counts'];
        // A suhoor-only restore does not read or replace fasting progress.
        if (logs is! List && counts is! Map) return true;
        if (_progressLoadFailed) return false;
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.reload();
          final progress = _readProgress(prefs);
          if (logs is List) {
            final imported = logs.map((e) => e.toString()).toList();
            final combined = replaceMode
                ? imported
                : {...progress.logs, ...imported}.toList();
            progress.logs
              ..clear()
              ..addAll(combined);
          }
          if (counts is Map) {
            for (final entry in counts.entries) {
              if (entry.value is! int) continue;
              final id = entry.key.toString();
              final value = entry.value as int;
              if (replaceMode || value > (progress.counts[id] ?? 0)) {
                progress.counts[id] = value;
              }
            }
          }
          return await _saveProgress(prefs, progress);
        } catch (_) {
          return false;
        }
      });

  Future<bool> toggleSuhoorReminder(bool val) => _serialize(() async {
        try {
          final prefs = await SharedPreferences.getInstance();
          if (!await prefs.setBool('voluntary_fast_suhoor_reminder', val)) {
            return false;
          }
          _suhoorReminderEnabled = val;
          notifyListeners();
          return true;
        } catch (_) {
          return false;
        }
      });

  /// Checks if a given Hijri day (1..30) is one of the 3 White Days (13, 14, 15)
  bool isWhiteDay(int hijriDay) =>
      hijriDay == 13 || hijriDay == 14 || hijriDay == 15;

  /// Checks if today (with user's Hijri sighting adjustment) is one of the 3 White Days
  bool isTodayWhiteDay([DateTime? date]) {
    final hijri = HijriDateHelper.toHijri(date ?? DateTime.now());
    return isWhiteDay(hijri['day'] ?? 1);
  }

  /// Returns an automatic recommendation if today matches a Sunnah fast (White Days, Monday/Thursday, Arafah, Ashura)
  String? getTodayHijriFastRecommendation([DateTime? date]) {
    final target = date ?? DateTime.now();
    final hijri = HijriDateHelper.toHijri(target);
    final hMonth = hijri['month'] ?? 1;
    final hDay = hijri['day'] ?? 1;

    if (hMonth == 12 && hDay == 9) {
      return 'اليوم يوم عرفة (٩ ذو الحجة) — صيامه يكفّر السنة الماضية والقادمة';
    }
    if (hMonth == 1 && (hDay == 9 || hDay == 10)) {
      return 'اليوم من أيام تاسوعاء وعاشوراء ($hDay محرم) — صيامه يكفّر السنة الماضية';
    }
    if (isWhiteDay(hDay)) {
      return 'اليوم من الأيام البيض المباركة ($hDay ${HijriDateHelper.hijriMonths[hMonth - 1]}) — صيامها كصيام الدهر';
    }
    if (target.weekday == DateTime.monday ||
        target.weekday == DateTime.thursday) {
      final dayAr = target.weekday == DateTime.monday ? 'الإثنين' : 'الخميس';
      return 'اليوم يوم $dayAr — تعرض فيه الأعمال على الله تعالى';
    }
    return null;
  }
}

class _FastingProgress {
  final Map<String, int> counts;
  final List<String> logs;
  _FastingProgress(this.counts, this.logs);

  Map<String, dynamic> toBackup() => {
        'counts': Map<String, int>.of(counts),
        'date_logs': List<String>.of(logs),
      };
}
