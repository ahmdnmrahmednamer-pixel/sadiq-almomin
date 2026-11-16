import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/backup_restore_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/services/khatma_service.dart';
import 'package:almomin/core/services/adhkar_service.dart';
import 'package:almomin/core/services/prayer_service.dart';
import 'package:almomin/core/services/islamic_radio_service.dart';
import 'package:almomin/core/services/tadabbur_journal_service.dart';
import 'package:almomin/features/backup/backup_restore_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init();
    await KhatmaService.instance.init();
    await AdhkarService.instance.init();
    await PrayerService.instance.init();
  });

  group('BackupRestoreService Unit Tests (FR-BKM-003 / T-305)', () {
    test('calculateChecksum produces consistent deterministic hex hash', () {
      const sample = '{"test": "data", "app": "AlMomin"}';
      final h1 = BackupRestoreService.calculateChecksum(sample);
      final h2 = BackupRestoreService.calculateChecksum(sample);
      expect(h1, equals(h2));
      expect(h1.length, equals(16));
    });

    test('exportBackupData exports valid envelope with Momin Ibrahim dedication', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('mushaf_font_size', 30.0);
      await prefs.setStringList('bookmarks', ['1:1', '2:255']);
      await SettingsService.instance.init();

      final backup = await BackupRestoreService.instance.exportBackupData();
      expect(backup['app'], equals('AlMomin'));
      expect(backup['schema_version'], equals(1));
      expect(backup['dedicated_to'], contains('تطبيق صديق المؤمن'));
      expect(backup['checksum'], isNotEmpty);

      final data = backup['data'] as Map<String, dynamic>;
      expect(data['settings']['mushaf_font_size'], equals(30.0));
      expect(data['bookmarks'], containsAll(['1:1', '2:255']));
    });

    test('validateBackup handles valid and invalid payloads accurately', () {
      // 1. Empty string
      final resEmpty = BackupRestoreService.instance.validateBackup('');
      expect(resEmpty.isValid, isFalse);
      expect(resEmpty.errorMessage, contains('فارغ'));

      // 2. Corrupt JSON
      final resCorrupt = BackupRestoreService.instance.validateBackup('{ invalid json }');
      expect(resCorrupt.isValid, isFalse);

      // 3. Foreign app
      final resForeign = BackupRestoreService.instance.validateBackup('{"app": "OtherApp", "schema_version": 1, "data": {}}');
      expect(resForeign.isValid, isFalse);
      expect(resForeign.errorMessage, contains('لا ينتمي لتطبيق صديق المؤمن'));

      // 4. Valid payload
      final validEnvelope = {
        'app': 'AlMomin',
        'schema_version': 1,
        'created_at': DateTime.now().toIso8601String(),
        'dedicated_to': 'مؤمن إبراهيم رحمه الله',
        'checksum': '0123456789abcdef',
        'data': {
          'bookmarks': ['2:255', '18:10'],
          'khatma': {'currentPage': 120},
          'location': {'last_city': 'الإسكندرية، مصر'},
        },
      };
      final resValid = BackupRestoreService.instance.validateBackup(json.encode(validEnvelope));
      expect(resValid.isValid, isTrue);
      expect(resValid.bookmarksCount, equals(2));
      expect(resValid.hasKhatma, isTrue);
      expect(resValid.khatmaPage, equals(120));
      expect(resValid.city, equals('الإسكندرية، مصر'));
    });

    test('restoreBackup in replaceMode completely restores state', () async {
      final prefs = await SharedPreferences.getInstance();

      // Setup initial state
      await prefs.setDouble('mushaf_font_size', 22.0);
      await prefs.setStringList('bookmarks', ['1:1']);
      await SettingsService.instance.init();

      final backupEnvelope = {
        'app': 'AlMomin',
        'schema_version': 1,
        'data': {
          'settings': {
            'mushaf_font_size': 36.0,
            'selected_reciter_id': 'husary',
          },
          'bookmarks': ['2:255', '3:10', '18:1'],
          'reading_position': {
            'last_read_surah_id': 18,
            'last_read_ayah_number': 10,
            'last_read_page_number': 294,
            'last_read_surah_name': 'الكهف',
          },
        },
      };

      final restored = await BackupRestoreService.instance.restoreBackup(
        backupEnvelope,
        replaceMode: true,
      );
      expect(restored, isTrue);

      expect(SettingsService.instance.mushafFontSize, equals(36.0));
      expect(SettingsService.instance.selectedReciterId, equals('husary'));
      expect(SettingsService.instance.bookmarks, equals(['2:255', '3:10', '18:1']));
      expect(SettingsService.instance.lastReadSurahName, equals('الكهف'));
      expect(SettingsService.instance.lastReadPageNumber, equals(294));
    });

    test('restoreBackup in mergeMode non-destructively unites bookmarks', () async {
      final prefs = await SharedPreferences.getInstance();

      // Current state has bookmarks A and B
      await prefs.setStringList('bookmarks', ['1:1', '2:255']);
      await SettingsService.instance.init();

      // Backup has bookmarks B and C
      final backupEnvelope = {
        'app': 'AlMomin',
        'schema_version': 1,
        'data': {
          'bookmarks': ['2:255', '18:10'],
        },
      };

      final restored = await BackupRestoreService.instance.restoreBackup(
        backupEnvelope,
        replaceMode: false,
      );
      expect(restored, isTrue);

      // Result should be union [1:1, 2:255, 18:10] without duplicates
      final updatedBookmarks = SettingsService.instance.bookmarks;
      expect(updatedBookmarks.length, equals(3));
      expect(updatedBookmarks, containsAll(['1:1', '2:255', '18:10']));
    });
  });

  group('BackupRestoreScreen Widget Tests', () {
    testWidgets('Renders BackupRestoreScreen with stats, dedication, and controls', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: BackupRestoreScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Check title and noble dedication
      expect(find.text('النسخ الاحتياطي والاستعادة'), findsOneWidget);
      expect(find.textContaining('نسخ احتياطي آمن'), findsOneWidget);

      // Check stat titles
      expect(find.text('العلامات المرجعية'), findsOneWidget);
      expect(find.text('الختمة الحالية'), findsOneWidget);
      expect(find.text('تسبيح اليوم'), findsOneWidget);

      // Check export buttons
      expect(find.textContaining('مشاركة / حفظ ملف النسخة'), findsOneWidget);
      expect(find.textContaining('نسخ كود النسخة الاحتياطية إلى الحافظة'), findsOneWidget);

      // Check import section & modes
      expect(find.text('استعادة نسخة سابقة'), findsOneWidget);
      expect(find.text('استبدال كامل'), findsOneWidget);
      expect(find.text('دمج ذكي'), findsOneWidget);
    });
  });

  group('BackupRestoreService Radio Favorites Integration & Regression Tests', () {
    const cairoId = 'radio_cairo_live';
    const husaryId = 'radio_husary';
    const minshawiId = 'radio_minshawi';

    setUp(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('islamic_radio_favorites');
      await IslamicRadioService.instance.init(forceReload: true);
    });

    tearDown(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('islamic_radio_favorites');
      await IslamicRadioService.instance.init(forceReload: true);
    });

    test('exportBackupData includes radio_favorites from SharedPreferences in extended_features', () async {
      final prefs = await SharedPreferences.getInstance();
      final initialFavs = prefs.getStringList('islamic_radio_favorites');
      addTearDown(() async {
        if (initialFavs != null) {
          await prefs.setStringList('islamic_radio_favorites', initialFavs);
        } else {
          await prefs.remove('islamic_radio_favorites');
        }
        await IslamicRadioService.instance.init(forceReload: true);
        if (initialFavs != null) {
          expect(prefs.getStringList('islamic_radio_favorites'), equals(initialFavs));
          expect(IslamicRadioService.instance.favoriteIds, equals(initialFavs.toSet()));
        } else {
          expect(prefs.getStringList('islamic_radio_favorites'), isNull);
          expect(IslamicRadioService.instance.favoriteIds, isEmpty);
        }
      });

      await prefs.setStringList('islamic_radio_favorites', [cairoId, husaryId]);
      await IslamicRadioService.instance.init(forceReload: true);

      final backup = await BackupRestoreService.instance.exportBackupData();
      expect(backup['checksum'], isNotEmpty);

      final data = backup['data'] as Map<String, dynamic>;
      final ext = data['extended_features'] as Map<String, dynamic>?;
      expect(ext, isNotNull);
      expect(ext!['radio_favorites'], isNotNull);
      final exportedFavs = (ext['radio_favorites'] as List<dynamic>).cast<String>();
      expect(exportedFavs, containsAll([cairoId, husaryId]));
    });

    test('restoreBackup in replaceMode restores radio_favorites, updates live cache and notifies listeners', () async {
      final prefs = await SharedPreferences.getInstance();
      final initialFavs = prefs.getStringList('islamic_radio_favorites');
      addTearDown(() async {
        if (initialFavs != null) {
          await prefs.setStringList('islamic_radio_favorites', initialFavs);
        } else {
          await prefs.remove('islamic_radio_favorites');
        }
        await IslamicRadioService.instance.init(forceReload: true);
        if (initialFavs != null) {
          expect(prefs.getStringList('islamic_radio_favorites'), equals(initialFavs));
          expect(IslamicRadioService.instance.favoriteIds, equals(initialFavs.toSet()));
        } else {
          expect(prefs.getStringList('islamic_radio_favorites'), isNull);
          expect(IslamicRadioService.instance.favoriteIds, isEmpty);
        }
      });

      // Baseline initial state
      await prefs.setStringList('islamic_radio_favorites', [cairoId]);
      await IslamicRadioService.instance.init(forceReload: true);
      expect(IslamicRadioService.instance.isFavorite(cairoId), isTrue);

      var listenerNotified = false;
      void listener() => listenerNotified = true;
      IslamicRadioService.instance.addListener(listener);
      addTearDown(() {
        IslamicRadioService.instance.removeListener(listener);
      });

      final dataPayload = {
        'extended_features': {
          'radio_favorites': [husaryId, minshawiId],
        },
      };
      final checksum = BackupRestoreService.calculateChecksum(
        BackupRestoreService.canonicalJsonEncode(dataPayload),
      );
      final envelope = {
        'app': 'AlMomin',
        'schema_version': 1,
        'created_at': DateTime.now().toIso8601String(),
        'dedicated_to': BackupRestoreService.dedicationNote,
        'checksum': checksum,
        'data': dataPayload,
      };

      // Verify payload is valid
      final validation = BackupRestoreService.instance.validateBackup(json.encode(envelope));
      expect(validation.isValid, isTrue);

      final restored = await BackupRestoreService.instance.restoreBackup(
        envelope,
        replaceMode: true,
      );
      expect(restored, isTrue);

      // Verify SharedPreferences persistence
      final storedPrefs = prefs.getStringList('islamic_radio_favorites');
      expect(storedPrefs, containsAll([husaryId, minshawiId]));
      expect(storedPrefs?.contains(cairoId), isFalse);

      // Verify in-memory live cache sync
      expect(IslamicRadioService.instance.isFavorite(cairoId), isFalse);
      expect(IslamicRadioService.instance.isFavorite(husaryId), isTrue);
      expect(IslamicRadioService.instance.isFavorite(minshawiId), isTrue);
      expect(IslamicRadioService.instance.favoriteIds, equals({husaryId, minshawiId}));

      // Verify listener notification
      expect(listenerNotified, isTrue);
    });

    test('restoreBackup with explicit empty radio_favorites: replaceMode clears, mergeMode preserves', () async {
      final prefs = await SharedPreferences.getInstance();
      final initialFavs = prefs.getStringList('islamic_radio_favorites');
      addTearDown(() async {
        if (initialFavs != null) {
          await prefs.setStringList('islamic_radio_favorites', initialFavs);
        } else {
          await prefs.remove('islamic_radio_favorites');
        }
        await IslamicRadioService.instance.init(forceReload: true);
        if (initialFavs != null) {
          expect(prefs.getStringList('islamic_radio_favorites'), equals(initialFavs));
          expect(IslamicRadioService.instance.favoriteIds, equals(initialFavs.toSet()));
        } else {
          expect(prefs.getStringList('islamic_radio_favorites'), isNull);
          expect(IslamicRadioService.instance.favoriteIds, isEmpty);
        }
      });

      // 1. mergeMode preserves existing favorites when payload has []
      await prefs.setStringList('islamic_radio_favorites', [cairoId]);
      await IslamicRadioService.instance.init(forceReload: true);
      expect(IslamicRadioService.instance.isFavorite(cairoId), isTrue);

      final emptyDataPayload = {
        'extended_features': {
          'radio_favorites': <String>[],
        },
      };
      final emptyChecksum = BackupRestoreService.calculateChecksum(
        BackupRestoreService.canonicalJsonEncode(emptyDataPayload),
      );
      final emptyEnvelope = {
        'app': 'AlMomin',
        'schema_version': 1,
        'created_at': DateTime.now().toIso8601String(),
        'dedicated_to': BackupRestoreService.dedicationNote,
        'checksum': emptyChecksum,
        'data': emptyDataPayload,
      };

      final validation = BackupRestoreService.instance.validateBackup(json.encode(emptyEnvelope));
      expect(validation.isValid, isTrue);

      final restoredMerge = await BackupRestoreService.instance.restoreBackup(
        emptyEnvelope,
        replaceMode: false,
      );
      expect(restoredMerge, isTrue);
      // Verify preserved
      expect(prefs.getStringList('islamic_radio_favorites'), equals([cairoId]));
      expect(IslamicRadioService.instance.isFavorite(cairoId), isTrue);
      expect(IslamicRadioService.instance.favoriteIds, equals({cairoId}));

      // 2. replaceMode clears existing favorites when payload has []
      final restoredReplace = await BackupRestoreService.instance.restoreBackup(
        emptyEnvelope,
        replaceMode: true,
      );
      expect(restoredReplace, isTrue);
      // Verify cleared
      expect(prefs.getStringList('islamic_radio_favorites'), isEmpty);
      expect(IslamicRadioService.instance.isFavorite(cairoId), isFalse);
      expect(IslamicRadioService.instance.favoriteIds, isEmpty);
    });

    test('restoreBackup in mergeMode non-destructively unites radio_favorites and updates live cache', () async {
      final prefs = await SharedPreferences.getInstance();
      final initialFavs = prefs.getStringList('islamic_radio_favorites');
      addTearDown(() async {
        if (initialFavs != null) {
          await prefs.setStringList('islamic_radio_favorites', initialFavs);
        } else {
          await prefs.remove('islamic_radio_favorites');
        }
        await IslamicRadioService.instance.init(forceReload: true);
        if (initialFavs != null) {
          expect(prefs.getStringList('islamic_radio_favorites'), equals(initialFavs));
          expect(IslamicRadioService.instance.favoriteIds, equals(initialFavs.toSet()));
        } else {
          expect(prefs.getStringList('islamic_radio_favorites'), isNull);
          expect(IslamicRadioService.instance.favoriteIds, isEmpty);
        }
      });

      // Baseline initial state has Cairo
      await prefs.setStringList('islamic_radio_favorites', [cairoId]);
      await IslamicRadioService.instance.init(forceReload: true);

      final dataPayload = {
        'extended_features': {
          'radio_favorites': [husaryId],
        },
      };
      final checksum = BackupRestoreService.calculateChecksum(
        BackupRestoreService.canonicalJsonEncode(dataPayload),
      );
      final envelope = {
        'app': 'AlMomin',
        'schema_version': 1,
        'created_at': DateTime.now().toIso8601String(),
        'dedicated_to': BackupRestoreService.dedicationNote,
        'checksum': checksum,
        'data': dataPayload,
      };

      final validation = BackupRestoreService.instance.validateBackup(json.encode(envelope));
      expect(validation.isValid, isTrue);

      final restored = await BackupRestoreService.instance.restoreBackup(
        envelope,
        replaceMode: false,
      );
      expect(restored, isTrue);

      // Verify SharedPreferences contains union [cairoId, husaryId]
      final storedPrefs = prefs.getStringList('islamic_radio_favorites');
      expect(storedPrefs, isNotNull);
      expect(storedPrefs!.length, equals(2));
      expect(storedPrefs, containsAll([cairoId, husaryId]));

      // Verify in-memory live cache sync
      expect(IslamicRadioService.instance.isFavorite(cairoId), isTrue);
      expect(IslamicRadioService.instance.isFavorite(husaryId), isTrue);
      expect(IslamicRadioService.instance.favoriteIds, equals({cairoId, husaryId}));
    });

    test('Old backup control: missing radio_favorites in extended_features passes validation and preserves existing state', () async {
      final prefs = await SharedPreferences.getInstance();
      final initialFavs = prefs.getStringList('islamic_radio_favorites');
      addTearDown(() async {
        if (initialFavs != null) {
          await prefs.setStringList('islamic_radio_favorites', initialFavs);
        } else {
          await prefs.remove('islamic_radio_favorites');
        }
        await IslamicRadioService.instance.init(forceReload: true);
        if (initialFavs != null) {
          expect(prefs.getStringList('islamic_radio_favorites'), equals(initialFavs));
          expect(IslamicRadioService.instance.favoriteIds, equals(initialFavs.toSet()));
        } else {
          expect(prefs.getStringList('islamic_radio_favorites'), isNull);
          expect(IslamicRadioService.instance.favoriteIds, isEmpty);
        }
      });

      await prefs.setStringList('islamic_radio_favorites', [cairoId]);
      await IslamicRadioService.instance.init(forceReload: true);

      // An old v1 backup with extended_features but omitting radio_favorites
      final dataPayload = {
        'bookmarks': ['2:255'],
        'extended_features': {
          'sunan_rawatib': 'some_data',
        },
      };
      final checksum = BackupRestoreService.calculateChecksum(
        BackupRestoreService.canonicalJsonEncode(dataPayload),
      );
      final oldEnvelope = {
        'app': 'AlMomin',
        'schema_version': 1,
        'created_at': DateTime.now().toIso8601String(),
        'dedicated_to': BackupRestoreService.dedicationNote,
        'checksum': checksum,
        'data': dataPayload,
      };

      final validation = BackupRestoreService.instance.validateBackup(json.encode(oldEnvelope));
      expect(validation.isValid, isTrue);

      // In mergeMode: existing radio favorites must remain untouched
      final restoredMerge = await BackupRestoreService.instance.restoreBackup(
        oldEnvelope,
        replaceMode: false,
      );
      expect(restoredMerge, isTrue);
      expect(prefs.getStringList('islamic_radio_favorites'), equals([cairoId]));
      expect(IslamicRadioService.instance.isFavorite(cairoId), isTrue);

      // In replaceMode: safe execution without crash
      final restoredReplace = await BackupRestoreService.instance.restoreBackup(
        oldEnvelope,
        replaceMode: true,
      );
      expect(restoredReplace, isTrue);
    });
  });

  group('BackupRestoreService Core Settings Coverage & Regression Tests', () {
    const coreKeys13 = [
      'keep_screen_on',
      'auto_play_next_ayah',
      'download_wifi_only',
      'auto_silent_prayer',
      'sunan_rawatib_reminder',
      'quran_numbering_style',
      'show_juz_overlay',
      'audio_quality_preset',
      'play_sharawi_duaa_after_adhan',
      'pre_adhan_alert',
      'iqamah_alert',
      'tasbih_cycle_alert',
      'screen_reader_optimized',
    ];

    const default13 = <String, Object>{
      'keep_screen_on': true,
      'auto_play_next_ayah': true,
      'download_wifi_only': false,
      'auto_silent_prayer': false,
      'sunan_rawatib_reminder': true,
      'quran_numbering_style': 'arabic',
      'show_juz_overlay': true,
      'audio_quality_preset': 'studio_hd',
      'play_sharawi_duaa_after_adhan': true,
      'pre_adhan_alert': true,
      'iqamah_alert': true,
      'tasbih_cycle_alert': true,
      'screen_reader_optimized': false,
    };

    const nonDefault13 = <String, Object>{
      'keep_screen_on': false,
      'auto_play_next_ayah': false,
      'download_wifi_only': true,
      'auto_silent_prayer': true,
      'sunan_rawatib_reminder': false,
      'quran_numbering_style': 'indic',
      'show_juz_overlay': false,
      'audio_quality_preset': 'mosque_echo',
      'play_sharawi_duaa_after_adhan': false,
      'pre_adhan_alert': false,
      'iqamah_alert': false,
      'tasbih_cycle_alert': false,
      'screen_reader_optimized': true,
    };

    Future<void> writeValuesToPrefs(
      SharedPreferences prefs,
      Map<String, Object> map,
    ) async {
      for (final entry in map.entries) {
        if (entry.value is bool) {
          await prefs.setBool(entry.key, entry.value as bool);
        } else if (entry.value is String) {
          await prefs.setString(entry.key, entry.value as String);
        }
      }
    }

    Future<void> Function() setupFullPrefsSnapshot(SharedPreferences prefs) {
      final snapshot = <String, Object?>{};
      for (final k in prefs.getKeys()) {
        snapshot[k] = prefs.get(k);
      }
      return () async {
        final currentKeys = prefs.getKeys().toList();
        for (final k in currentKeys) {
          if (!snapshot.containsKey(k)) {
            await prefs.remove(k);
          }
        }
        for (final entry in snapshot.entries) {
          if (entry.value is bool) {
            await prefs.setBool(entry.key, entry.value as bool);
          } else if (entry.value is String) {
            await prefs.setString(entry.key, entry.value as String);
          } else if (entry.value is int) {
            await prefs.setInt(entry.key, entry.value as int);
          } else if (entry.value is double) {
            await prefs.setDouble(entry.key, entry.value as double);
          } else if (entry.value is List<String>) {
            await prefs.setStringList(entry.key, entry.value as List<String>);
          }
        }
        await SettingsService.instance.init(forceReload: true);
      };
    }

    void assertLiveGetters(
      SettingsService s,
      Map<String, Object> expected,
    ) {
      if (expected.containsKey('keep_screen_on')) {
        expect(s.keepScreenOn, equals(expected['keep_screen_on']),
            reason: 'keepScreenOn getter mismatch');
      }
      if (expected.containsKey('auto_play_next_ayah')) {
        expect(s.autoPlayNextAyah, equals(expected['auto_play_next_ayah']),
            reason: 'autoPlayNextAyah getter mismatch');
      }
      if (expected.containsKey('download_wifi_only')) {
        expect(s.downloadOverWifiOnly, equals(expected['download_wifi_only']),
            reason: 'downloadOverWifiOnly getter mismatch');
      }
      if (expected.containsKey('auto_silent_prayer')) {
        expect(s.autoSilentDuringPrayer, equals(expected['auto_silent_prayer']),
            reason: 'autoSilentDuringPrayer getter mismatch');
      }
      if (expected.containsKey('sunan_rawatib_reminder')) {
        expect(s.sunanRawatibReminderEnabled,
            equals(expected['sunan_rawatib_reminder']),
            reason: 'sunanRawatibReminderEnabled getter mismatch');
      }
      if (expected.containsKey('quran_numbering_style')) {
        expect(s.quranNumberingStyle, equals(expected['quran_numbering_style']),
            reason: 'quranNumberingStyle getter mismatch');
      }
      if (expected.containsKey('show_juz_overlay')) {
        expect(s.showJuzOverlay, equals(expected['show_juz_overlay']),
            reason: 'showJuzOverlay getter mismatch');
      }
      if (expected.containsKey('audio_quality_preset')) {
        expect(s.audioQualityPreset, equals(expected['audio_quality_preset']),
            reason: 'audioQualityPreset getter mismatch');
      }
      if (expected.containsKey('play_sharawi_duaa_after_adhan')) {
        expect(s.playSharawiDuaaAfterAdhan,
            equals(expected['play_sharawi_duaa_after_adhan']),
            reason: 'playSharawiDuaaAfterAdhan getter mismatch');
      }
      if (expected.containsKey('pre_adhan_alert')) {
        expect(s.preAdhanAlertEnabled, equals(expected['pre_adhan_alert']),
            reason: 'preAdhanAlertEnabled getter mismatch');
      }
      if (expected.containsKey('iqamah_alert')) {
        expect(s.iqamahAlertEnabled, equals(expected['iqamah_alert']),
            reason: 'iqamahAlertEnabled getter mismatch');
      }
      if (expected.containsKey('tasbih_cycle_alert')) {
        expect(s.tasbihCycleAlertEnabled,
            equals(expected['tasbih_cycle_alert']),
            reason: 'tasbihCycleAlertEnabled getter mismatch');
      }
      if (expected.containsKey('screen_reader_optimized')) {
        expect(s.screenReaderOptimized,
            equals(expected['screen_reader_optimized']),
            reason: 'screenReaderOptimized getter mismatch');
      }
    }

    test('exportBackupData includes all 13 non-default settings and produces valid checksum', () async {
      final prefs = await SharedPreferences.getInstance();
      final snapshot = <String, Object?>{};
      for (final k in coreKeys13) {
        snapshot[k] = prefs.get(k);
      }
      addTearDown(() async {
        for (final entry in snapshot.entries) {
          if (entry.value == null) {
            await prefs.remove(entry.key);
          } else if (entry.value is bool) {
            await prefs.setBool(entry.key, entry.value as bool);
          } else if (entry.value is String) {
            await prefs.setString(entry.key, entry.value as String);
          }
        }
        await SettingsService.instance.init(forceReload: true);
        for (final entry in snapshot.entries) {
          expect(prefs.get(entry.key), equals(entry.value));
        }
      });

      await writeValuesToPrefs(prefs, nonDefault13);
      await SettingsService.instance.init(forceReload: true);

      final backup = await BackupRestoreService.instance.exportBackupData();
      final validation = BackupRestoreService.instance.validateBackup(json.encode(backup));
      expect(validation.isValid, isTrue, reason: 'Exported backup envelope must pass checksum validation');

      final data = backup['data'] as Map<String, dynamic>;
      final settings = data['settings'] as Map<String, dynamic>;

      for (final entry in nonDefault13.entries) {
        expect(settings[entry.key], equals(entry.value),
            reason: 'Exported settings map must contain non-default ${entry.key}');
      }
    });

    test('restoreBackup in replaceMode restores all 13 settings and updates live getters', () async {
      final prefs = await SharedPreferences.getInstance();
      final snapshot = <String, Object?>{};
      for (final k in coreKeys13) {
        snapshot[k] = prefs.get(k);
      }

      var listenerNotified = false;
      void listener() {
        listenerNotified = true;
      }

      SettingsService.instance.addListener(listener);

      addTearDown(() async {
        SettingsService.instance.removeListener(listener);
        for (final entry in snapshot.entries) {
          if (entry.value == null) {
            await prefs.remove(entry.key);
          } else if (entry.value is bool) {
            await prefs.setBool(entry.key, entry.value as bool);
          } else if (entry.value is String) {
            await prefs.setString(entry.key, entry.value as String);
          }
        }
        await SettingsService.instance.init(forceReload: true);
        for (final entry in snapshot.entries) {
          expect(prefs.get(entry.key), equals(entry.value));
        }
      });

      // Clear any prior custom preferences to simulate fresh/clean state
      for (final k in coreKeys13) {
        await prefs.remove(k);
      }
      await SettingsService.instance.init(forceReload: true);

      // Reset listener flag immediately before restoreBackup to eliminate setup false positives
      listenerNotified = false;

      final payload = {
        'settings': nonDefault13,
      };
      final checksum = BackupRestoreService.calculateChecksum(
        BackupRestoreService.canonicalJsonEncode(payload),
      );
      final envelope = {
        'app': 'AlMomin',
        'schema_version': 1,
        'created_at': DateTime.now().toIso8601String(),
        'dedicated_to': BackupRestoreService.dedicationNote,
        'checksum': checksum,
        'data': payload,
      };

      final validation = BackupRestoreService.instance.validateBackup(json.encode(envelope));
      expect(validation.isValid, isTrue);

      final restored = await BackupRestoreService.instance.restoreBackup(
        envelope,
        replaceMode: true,
      );
      expect(restored, isTrue);

      // Verify SharedPreferences persistence for all 13 keys
      for (final entry in nonDefault13.entries) {
        expect(prefs.get(entry.key), equals(entry.value),
            reason: 'SharedPreferences must have restored value for ${entry.key}');
      }

      // Verify live getters on singleton
      assertLiveGetters(SettingsService.instance, nonDefault13);
      expect(listenerNotified, isTrue, reason: 'SettingsService listeners must be notified on reload');
    });

    test('restoreBackup in mergeMode: all 13 absent keys fill from backup, all 13 existing keys are preserved', () async {
      final prefs = await SharedPreferences.getInstance();
      final snapshot = <String, Object?>{};
      for (final k in coreKeys13) {
        snapshot[k] = prefs.get(k);
      }
      addTearDown(() async {
        for (final entry in snapshot.entries) {
          if (entry.value == null) {
            await prefs.remove(entry.key);
          } else if (entry.value is bool) {
            await prefs.setBool(entry.key, entry.value as bool);
          } else if (entry.value is String) {
            await prefs.setString(entry.key, entry.value as String);
          }
        }
        await SettingsService.instance.init(forceReload: true);
        for (final entry in snapshot.entries) {
          expect(prefs.get(entry.key), equals(entry.value));
        }
      });

      // Part A: All 13 absent keys on device must be filled from backup
      for (final k in coreKeys13) {
        await prefs.remove(k);
      }
      await SettingsService.instance.init(forceReload: true);

      final payloadNonDefault = {
        'settings': nonDefault13,
      };
      final checksumA = BackupRestoreService.calculateChecksum(
        BackupRestoreService.canonicalJsonEncode(payloadNonDefault),
      );
      final envelopeA = {
        'app': 'AlMomin',
        'schema_version': 1,
        'created_at': DateTime.now().toIso8601String(),
        'dedicated_to': BackupRestoreService.dedicationNote,
        'checksum': checksumA,
        'data': payloadNonDefault,
      };

      final restoredA = await BackupRestoreService.instance.restoreBackup(
        envelopeA,
        replaceMode: false,
      );
      expect(restoredA, isTrue);

      // Verify all 13 absent keys were filled from payload into SharedPreferences
      for (final entry in nonDefault13.entries) {
        expect(prefs.get(entry.key), equals(entry.value),
            reason: 'Absent ${entry.key} must be filled from backup in mergeMode');
      }
      assertLiveGetters(SettingsService.instance, nonDefault13);

      // Part B: All 13 existing keys on device must be preserved against conflicting backup
      // Device currently has nonDefault13. Conflicting backup has default13.
      final payloadDefault = {
        'settings': default13,
      };
      final checksumB = BackupRestoreService.calculateChecksum(
        BackupRestoreService.canonicalJsonEncode(payloadDefault),
      );
      final envelopeB = {
        'app': 'AlMomin',
        'schema_version': 1,
        'created_at': DateTime.now().toIso8601String(),
        'dedicated_to': BackupRestoreService.dedicationNote,
        'checksum': checksumB,
        'data': payloadDefault,
      };

      final restoredB = await BackupRestoreService.instance.restoreBackup(
        envelopeB,
        replaceMode: false,
      );
      expect(restoredB, isTrue);

      // Verify all 13 existing keys remained unchanged as nonDefault13
      for (final entry in nonDefault13.entries) {
        expect(prefs.get(entry.key), equals(entry.value),
            reason: 'Existing ${entry.key} on device must be preserved in mergeMode');
      }
      assertLiveGetters(SettingsService.instance, nonDefault13);
    });

    test('Old backup control: missing core keys in settings preserves existing device state in both modes', () async {
      final prefs = await SharedPreferences.getInstance();
      final keysToWatch = ['theme_mode', 'mushaf_font_size', ...coreKeys13];
      final snapshot = <String, Object?>{};
      for (final k in keysToWatch) {
        snapshot[k] = prefs.get(k);
      }
      addTearDown(() async {
        for (final entry in snapshot.entries) {
          if (entry.value == null) {
            await prefs.remove(entry.key);
          } else if (entry.value is bool) {
            await prefs.setBool(entry.key, entry.value as bool);
          } else if (entry.value is String) {
            await prefs.setString(entry.key, entry.value as String);
          } else if (entry.value is double) {
            await prefs.setDouble(entry.key, entry.value as double);
          } else if (entry.value is int) {
            await prefs.setInt(entry.key, entry.value as int);
          }
        }
        await SettingsService.instance.init(forceReload: true);
        for (final entry in snapshot.entries) {
          expect(prefs.get(entry.key), equals(entry.value),
              reason: 'Teardown failed to restore legacy control key ${entry.key}');
        }
      });

      // Device starts with customized non-default settings
      await writeValuesToPrefs(prefs, nonDefault13);
      await SettingsService.instance.init(forceReload: true);

      // A legacy backup envelope whose settings map only contains legacy keys
      final legacyPayload = {
        'settings': {
          'theme_mode': 'dark',
          'mushaf_font_size': 26.0,
        },
      };
      final checksum = BackupRestoreService.calculateChecksum(
        BackupRestoreService.canonicalJsonEncode(legacyPayload),
      );
      final legacyEnvelope = {
        'app': 'AlMomin',
        'schema_version': 1,
        'created_at': DateTime.now().toIso8601String(),
        'dedicated_to': BackupRestoreService.dedicationNote,
        'checksum': checksum,
        'data': legacyPayload,
      };

      final validation = BackupRestoreService.instance.validateBackup(json.encode(legacyEnvelope));
      expect(validation.isValid, isTrue);

      // 1. In mergeMode: all 13 customized keys remain preserved
      final restoredMerge = await BackupRestoreService.instance.restoreBackup(
        legacyEnvelope,
        replaceMode: false,
      );
      expect(restoredMerge, isTrue);
      for (final entry in nonDefault13.entries) {
        expect(prefs.get(entry.key), equals(entry.value),
            reason: 'mergeMode with legacy backup must preserve existing ${entry.key}');
      }
      assertLiveGetters(SettingsService.instance, nonDefault13);

      // 2. In replaceMode: omitted keys in payload do NOT clear or wipe existing customized keys
      final restoredReplace = await BackupRestoreService.instance.restoreBackup(
        legacyEnvelope,
        replaceMode: true,
      );
      expect(restoredReplace, isTrue);
      for (final entry in nonDefault13.entries) {
        expect(prefs.get(entry.key), equals(entry.value),
            reason: 'replaceMode with legacy backup must preserve existing ${entry.key}');
      }
      assertLiveGetters(SettingsService.instance, nonDefault13);
    });

    test('Fresh backup roundtrip fallback: absent theme_mode preserves runtime default (system)', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(cleanup);

      await prefs.remove('theme_mode');
      await SettingsService.instance.init(forceReload: true);
      expect(SettingsService.instance.themeMode, equals('system'));

      final backup = await BackupRestoreService.instance.exportBackupData();
      final validation = BackupRestoreService.instance.validateBackup(json.encode(backup));
      expect(validation.isValid, isTrue, reason: 'Checksum must be valid');

      final restored = await BackupRestoreService.instance.restoreBackup(backup, replaceMode: true);
      expect(restored, isTrue);

      expect(SettingsService.instance.themeMode, equals('system'),
          reason: 'After restore, themeMode must remain system');
    });

    test('Fresh backup roundtrip fallback: absent fiqh_madhhab preserves runtime default (shafii_egypt)', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(cleanup);

      await prefs.remove('fiqh_madhhab');
      await SettingsService.instance.init(forceReload: true);
      expect(SettingsService.instance.fiqhMadhhab, equals('shafii_egypt'));

      final backup = await BackupRestoreService.instance.exportBackupData();
      final validation = BackupRestoreService.instance.validateBackup(json.encode(backup));
      expect(validation.isValid, isTrue, reason: 'Checksum must be valid');

      final restored = await BackupRestoreService.instance.restoreBackup(backup, replaceMode: true);
      expect(restored, isTrue);

      expect(SettingsService.instance.fiqhMadhhab, equals('shafii_egypt'),
          reason: 'After restore, fiqhMadhhab must remain shafii_egypt');
    });

    test('Fresh backup roundtrip fallback: absent mushaf_default_mode preserves runtime default (page)', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(cleanup);

      await prefs.remove('mushaf_default_mode');
      await SettingsService.instance.init(forceReload: true);
      expect(SettingsService.instance.mushafDefaultMode, equals('page'));

      final backup = await BackupRestoreService.instance.exportBackupData();
      final validation = BackupRestoreService.instance.validateBackup(json.encode(backup));
      expect(validation.isValid, isTrue, reason: 'Checksum must be valid');

      final restored = await BackupRestoreService.instance.restoreBackup(backup, replaceMode: true);
      expect(restored, isTrue);

      expect(SettingsService.instance.mushafDefaultMode, equals('page'),
          reason: 'After restore, mushafDefaultMode must remain page');
    });

    test('Fresh backup roundtrip fallback: absent screen_layout_mode preserves runtime default (classic)', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(cleanup);

      await prefs.remove('screen_layout_mode');
      await SettingsService.instance.init(forceReload: true);
      expect(SettingsService.instance.screenLayoutMode, equals('classic'));

      final backup = await BackupRestoreService.instance.exportBackupData();
      final validation = BackupRestoreService.instance.validateBackup(json.encode(backup));
      expect(validation.isValid, isTrue, reason: 'Checksum must be valid');

      final restored = await BackupRestoreService.instance.restoreBackup(backup, replaceMode: true);
      expect(restored, isTrue);

      expect(SettingsService.instance.screenLayoutMode, equals('classic'),
          reason: 'After restore, screenLayoutMode must remain classic');
    });

    test('Fresh backup roundtrip fallback: bilingual_display_enabled aligns with AppLanguage normalization and explicit preferences', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(cleanup);

      // Case 1: Arabic ('ar') language with absent bilingual_display_enabled -> runtime default false
      await prefs.setString('app_language', 'ar');
      await prefs.remove('bilingual_display_enabled');
      await SettingsService.instance.init(forceReload: true);
      expect(SettingsService.instance.bilingualDisplayEnabled, isFalse);

      var backup = await BackupRestoreService.instance.exportBackupData();
      var validation = BackupRestoreService.instance.validateBackup(json.encode(backup));
      expect(validation.isValid, isTrue);
      var restored = await BackupRestoreService.instance.restoreBackup(backup, replaceMode: true);
      expect(restored, isTrue);
      expect(SettingsService.instance.bilingualDisplayEnabled, isFalse,
          reason: 'Arabic with absent bilingual preference must remain false after restore');

      // Case 2: English ('en') language with absent bilingual_display_enabled -> runtime default true
      await prefs.setString('app_language', 'en');
      await prefs.remove('bilingual_display_enabled');
      await SettingsService.instance.init(forceReload: true);
      expect(SettingsService.instance.bilingualDisplayEnabled, isTrue);

      backup = await BackupRestoreService.instance.exportBackupData();
      validation = BackupRestoreService.instance.validateBackup(json.encode(backup));
      expect(validation.isValid, isTrue);
      restored = await BackupRestoreService.instance.restoreBackup(backup, replaceMode: true);
      expect(restored, isTrue);
      expect(SettingsService.instance.bilingualDisplayEnabled, isTrue,
          reason: 'English with absent bilingual preference must remain true after restore');

      // Case 3: Invalid language code ('invalid_xyz') normalized via AppLanguage.fromCode -> falls back to Arabic (false)
      await prefs.setString('app_language', 'invalid_xyz');
      await prefs.remove('bilingual_display_enabled');
      await SettingsService.instance.init(forceReload: true);
      expect(SettingsService.instance.bilingualDisplayEnabled, isFalse);

      backup = await BackupRestoreService.instance.exportBackupData();
      validation = BackupRestoreService.instance.validateBackup(json.encode(backup));
      expect(validation.isValid, isTrue);
      restored = await BackupRestoreService.instance.restoreBackup(backup, replaceMode: true);
      expect(restored, isTrue);
      expect(SettingsService.instance.bilingualDisplayEnabled, isFalse,
          reason: 'Invalid language code normalized to Arabic must remain false after restore');

      // Case 4: Explicit stored bilingual_display_enabled = true on Arabic
      await prefs.setString('app_language', 'ar');
      await prefs.setBool('bilingual_display_enabled', true);
      await SettingsService.instance.init(forceReload: true);
      expect(SettingsService.instance.bilingualDisplayEnabled, isTrue);

      backup = await BackupRestoreService.instance.exportBackupData();
      validation = BackupRestoreService.instance.validateBackup(json.encode(backup));
      expect(validation.isValid, isTrue);
      restored = await BackupRestoreService.instance.restoreBackup(backup, replaceMode: true);
      expect(restored, isTrue);
      expect(SettingsService.instance.bilingualDisplayEnabled, isTrue,
          reason: 'Explicit true must be preserved across restore regardless of language');

      // Case 5: Explicit stored bilingual_display_enabled = false on English
      await prefs.setString('app_language', 'en');
      await prefs.setBool('bilingual_display_enabled', false);
      await SettingsService.instance.init(forceReload: true);
      expect(SettingsService.instance.bilingualDisplayEnabled, isFalse);

      backup = await BackupRestoreService.instance.exportBackupData();
      validation = BackupRestoreService.instance.validateBackup(json.encode(backup));
      expect(validation.isValid, isTrue);
      restored = await BackupRestoreService.instance.restoreBackup(backup, replaceMode: true);
      expect(restored, isTrue);
      expect(SettingsService.instance.bilingualDisplayEnabled, isFalse,
          reason: 'Explicit false must be preserved across restore regardless of language');
    });

    test('Explicit stored values control: user-customized preferences are preserved across export/restore', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(cleanup);

      // Explicit stored non-default preferences
      await prefs.setString('theme_mode', 'dark');
      await prefs.setString('fiqh_madhhab', 'hanafi');
      await prefs.setString('mushaf_default_mode', 'surah');
      await prefs.setString('screen_layout_mode', 'comfortable');
      await prefs.setBool('bilingual_display_enabled', true);
      await SettingsService.instance.init(forceReload: true);

      final backup = await BackupRestoreService.instance.exportBackupData();
      final validation = BackupRestoreService.instance.validateBackup(json.encode(backup));
      expect(validation.isValid, isTrue);

      final exportedSettings = (backup['data'] as Map<String, dynamic>)['settings'] as Map<String, dynamic>;
      expect(exportedSettings['theme_mode'], equals('dark'));
      expect(exportedSettings['fiqh_madhhab'], equals('hanafi'));
      expect(exportedSettings['mushaf_default_mode'], equals('surah'));
      expect(exportedSettings['screen_layout_mode'], equals('comfortable'));
      expect(exportedSettings['bilingual_display_enabled'], isTrue);

      final restored = await BackupRestoreService.instance.restoreBackup(backup, replaceMode: true);
      expect(restored, isTrue);

      expect(SettingsService.instance.themeMode, equals('dark'));
      expect(SettingsService.instance.fiqhMadhhab, equals('hanafi'));
      expect(SettingsService.instance.mushafDefaultMode, equals('surah'));
      expect(SettingsService.instance.screenLayoutMode, equals('comfortable'));
      expect(SettingsService.instance.bilingualDisplayEnabled, isTrue);
    });
  });

  group('BackupRestoreService Journal & Daily Accountability Coverage & Regression Tests', () {
    Future<void> Function() setupFullPrefsSnapshot(SharedPreferences prefs) {
      final snapshot = <String, Object?>{};
      for (final k in prefs.getKeys()) {
        snapshot[k] = prefs.get(k);
      }
      return () async {
        final currentKeys = prefs.getKeys().toList();
        for (final k in currentKeys) {
          if (!snapshot.containsKey(k)) {
            await prefs.remove(k);
          }
        }
        for (final entry in snapshot.entries) {
          if (entry.value is bool) {
            await prefs.setBool(entry.key, entry.value as bool);
          } else if (entry.value is String) {
            await prefs.setString(entry.key, entry.value as String);
          } else if (entry.value is int) {
            await prefs.setInt(entry.key, entry.value as int);
          } else if (entry.value is double) {
            await prefs.setDouble(entry.key, entry.value as double);
          } else if (entry.value is List<String>) {
            await prefs.setStringList(entry.key, entry.value as List<String>);
          }
        }
        await SettingsService.instance.init(forceReload: true);
        await TadabburJournalService.instance.init(forceReload: true);
      };
    }

    Map<String, dynamic> createChecksumValidEnvelope(Map<String, dynamic> dataPayload) {
      final checksum = BackupRestoreService.calculateChecksum(
        BackupRestoreService.canonicalJsonEncode(dataPayload),
      );
      return {
        'app': 'AlMomin',
        'schema_version': 1,
        'created_at': DateTime.now().toIso8601String(),
        'dedicated_to': BackupRestoreService.dedicationNote,
        'checksum': checksum,
        'data': dataPayload,
      };
    }

    final localItemA = TadabburReflectionItem(
      id: 'local_item_a',
      surahId: 2,
      surahName: 'البقرة',
      ayahNumber: 255,
      ayahSnippet: 'اللَّهُ لَا إِلَٰهَ إِلَّا هُوَ الْحَيُّ الْقَيُّومُ',
      faithMessage: 'رسالة إيمانية محلية أصلية',
      practicalAction: 'عمل تطبيقي محلي أصلي',
      derivedDua: 'دعاء محلي أصلي',
      createdAt: DateTime(2026, 11, 10, 8, 30),
    );

    final importItemB = TadabburReflectionItem(
      id: 'import_item_b',
      surahId: 3,
      surahName: 'آل عمران',
      ayahNumber: 18,
      ayahSnippet: 'شَهِدَ اللَّهُ أَنَّهُ لَا إِلَٰهَ إِلَّا هُوَ',
      faithMessage: 'رسالة إيمانية مستوردة',
      practicalAction: 'عمل تطبيقي مستورد',
      derivedDua: 'دعاء مستورد',
      createdAt: DateTime(2026, 11, 12, 9, 0),
    );

    test('replaceMode false (merge): distinct local A and import B both survive in prefs and live service', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(() async {
        await cleanup();
        await TadabburJournalService.instance.init(forceReload: true);
      });

      // Seed local entry A
      await prefs.setString(
        'tadabbur_journal_entries_v1',
        json.encode([localItemA.toJson()]),
      );
      await TadabburJournalService.instance.init(forceReload: true);
      expect(TadabburJournalService.instance.entries.map((e) => e.id), contains('local_item_a'));

      // Import envelope containing distinct import entry B
      final dataPayload = {
        'extended_features': {
          'tadabbur_journal': json.encode([importItemB.toJson()]),
        },
      };
      final envelope = createChecksumValidEnvelope(dataPayload);
      final validation = BackupRestoreService.instance.validateBackup(json.encode(envelope));
      expect(validation.isValid, isTrue, reason: 'Checksum-valid fixture must pass validation');

      final restored = await BackupRestoreService.instance.restoreBackup(envelope, replaceMode: false);
      expect(restored, isTrue);

      // Verify SharedPreferences contains both A and B
      final rawStored = prefs.getString('tadabbur_journal_entries_v1');
      expect(rawStored, isNotNull);
      final List<dynamic> decodedList = json.decode(rawStored!);
      final storedIds = decodedList.map((e) => e['id'] as String).toList();
      expect(storedIds, containsAll(['local_item_a', 'import_item_b']),
          reason: 'Distinct local A and import B must both survive in merge mode');

      // Forced reload verification on live singleton
      await TadabburJournalService.instance.init(forceReload: true);
      final liveIds = TadabburJournalService.instance.entries.map((e) => e.id).toList();
      expect(liveIds, containsAll(['local_item_a', 'import_item_b']),
          reason: 'Both items must survive in live service entries after forced reload');
    });

    test('replaceMode false (merge): repeat restore is idempotent without duplicate entries', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(() async {
        await cleanup();
        await TadabburJournalService.instance.init(forceReload: true);
      });

      await prefs.setString(
        'tadabbur_journal_entries_v1',
        json.encode([localItemA.toJson()]),
      );
      await TadabburJournalService.instance.init(forceReload: true);

      final dataPayload = {
        'extended_features': {
          'tadabbur_journal': json.encode([importItemB.toJson()]),
        },
      };
      final envelope = createChecksumValidEnvelope(dataPayload);
      final validation = BackupRestoreService.instance.validateBackup(json.encode(envelope));
      expect(validation.isValid, isTrue);

      // First restore
      final restoredFirst = await BackupRestoreService.instance.restoreBackup(envelope, replaceMode: false);
      expect(restoredFirst, isTrue);

      // Second repeated restore
      final restoredSecond = await BackupRestoreService.instance.restoreBackup(envelope, replaceMode: false);
      expect(restoredSecond, isTrue);

      final rawStored = prefs.getString('tadabbur_journal_entries_v1');
      expect(rawStored, isNotNull);
      final List<dynamic> decodedList = json.decode(rawStored!);
      final storedIds = decodedList.map((e) => e['id'] as String).toList();
      expect(storedIds.where((id) => id == 'local_item_a').length, equals(1));
      expect(storedIds.where((id) => id == 'import_item_b').length, equals(1));
      expect(storedIds.length, equals(2), reason: 'Repeat restore must be idempotent without duplicates');

      await TadabburJournalService.instance.init(forceReload: true);
      final liveIds = TadabburJournalService.instance.entries.map((e) => e.id).toList();
      expect(liveIds.where((id) => id == 'local_item_a').length, equals(1));
      expect(liveIds.where((id) => id == 'import_item_b').length, equals(1));
      expect(liveIds.length, equals(2));
    });

    test('replaceMode false (merge): empty import preserves existing local journal entries', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(() async {
        await cleanup();
        await TadabburJournalService.instance.init(forceReload: true);
      });

      await prefs.setString(
        'tadabbur_journal_entries_v1',
        json.encode([localItemA.toJson()]),
      );
      await TadabburJournalService.instance.init(forceReload: true);

      final dataPayload = {
        'extended_features': {
          'tadabbur_journal': '[]',
        },
      };
      final envelope = createChecksumValidEnvelope(dataPayload);
      final validation = BackupRestoreService.instance.validateBackup(json.encode(envelope));
      expect(validation.isValid, isTrue);

      final restored = await BackupRestoreService.instance.restoreBackup(envelope, replaceMode: false);
      expect(restored, isTrue);

      final rawStored = prefs.getString('tadabbur_journal_entries_v1');
      expect(rawStored, isNotNull);
      final List<dynamic> decodedList = json.decode(rawStored!);
      final storedIds = decodedList.map((e) => e['id'] as String).toList();
      expect(storedIds, contains('local_item_a'),
          reason: 'Empty import list in mergeMode must preserve local entries');

      await TadabburJournalService.instance.init(forceReload: true);
      expect(TadabburJournalService.instance.entries.map((e) => e.id), contains('local_item_a'));
    });

    test('replaceMode true: replaces existing with imported, and empty import clears existing', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(() async {
        await cleanup();
        await TadabburJournalService.instance.init(forceReload: true);
      });

      // Part 1: Replaces
      await prefs.setString(
        'tadabbur_journal_entries_v1',
        json.encode([localItemA.toJson()]),
      );
      await TadabburJournalService.instance.init(forceReload: true);

      final replacePayload = {
        'extended_features': {
          'tadabbur_journal': json.encode([importItemB.toJson()]),
        },
      };
      final envelopeReplace = createChecksumValidEnvelope(replacePayload);
      expect(BackupRestoreService.instance.validateBackup(json.encode(envelopeReplace)).isValid, isTrue);

      final restoredReplace = await BackupRestoreService.instance.restoreBackup(envelopeReplace, replaceMode: true);
      expect(restoredReplace, isTrue);

      final rawReplaced = prefs.getString('tadabbur_journal_entries_v1');
      expect(rawReplaced, isNotNull);
      final List<dynamic> replacedList = json.decode(rawReplaced!);
      final replacedIds = replacedList.map((e) => e['id'] as String).toList();
      expect(replacedIds, equals(['import_item_b']),
          reason: 'replaceMode true must overwrite local entries with imported entries');

      await TadabburJournalService.instance.init(forceReload: true);
      expect(TadabburJournalService.instance.entries.map((e) => e.id), equals(['import_item_b']));

      // Part 2: Empty clears
      final emptyPayload = {
        'extended_features': {
          'tadabbur_journal': '[]',
        },
      };
      final envelopeEmpty = createChecksumValidEnvelope(emptyPayload);
      expect(BackupRestoreService.instance.validateBackup(json.encode(envelopeEmpty)).isValid, isTrue);

      final restoredEmpty = await BackupRestoreService.instance.restoreBackup(envelopeEmpty, replaceMode: true);
      expect(restoredEmpty, isTrue);

      final rawEmpty = prefs.getString('tadabbur_journal_entries_v1');
      expect(rawEmpty, isNotNull);
      final List<dynamic> emptyList = json.decode(rawEmpty!);
      expect(emptyList, isEmpty, reason: 'replaceMode true with empty import must clear entries');

      await TadabburJournalService.instance.init(forceReload: true);
      expect(TadabburJournalService.instance.entries, isEmpty);
    });

    test('replaceMode false (merge): accountability performs same-day task union and preserves different dates', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(() async {
        await cleanup();
        await TadabburJournalService.instance.init(forceReload: true);
      });

      // Local state has date1 (2026-11-15) and date2 (2026-11-16)
      final localAccountability = {
        '2026-11-15': ['birr_walidayn'],
        '2026-11-16': ['hifz_lisan'],
      };
      await prefs.setString(
        'tadabbur_daily_accountability_v1',
        json.encode(localAccountability),
      );
      await TadabburJournalService.instance.init(forceReload: true);

      // Imported state has date2 (same day with different task) and date3 (new date)
      final importAccountability = {
        '2026-11-16': ['sadaqah_ihsan'],
        '2026-11-17': ['istighfar_tawbah'],
      };
      final dataPayload = {
        'extended_features': {
          'tadabbur_daily_accountability': json.encode(importAccountability),
        },
      };
      final envelope = createChecksumValidEnvelope(dataPayload);
      final validation = BackupRestoreService.instance.validateBackup(json.encode(envelope));
      expect(validation.isValid, isTrue);

      final restored = await BackupRestoreService.instance.restoreBackup(envelope, replaceMode: false);
      expect(restored, isTrue);

      final rawAcc = prefs.getString('tadabbur_daily_accountability_v1');
      expect(rawAcc, isNotNull);
      final Map<String, dynamic> storedAcc = json.decode(rawAcc!);

      // Assert date 1 preserved
      expect(storedAcc.containsKey('2026-11-15'), isTrue);
      expect((storedAcc['2026-11-15'] as List).cast<String>(), contains('birr_walidayn'));

      // Assert date 2 has same-day union
      expect(storedAcc.containsKey('2026-11-16'), isTrue);
      final date2Tasks = (storedAcc['2026-11-16'] as List).cast<String>();
      expect(date2Tasks, containsAll(['hifz_lisan', 'sadaqah_ihsan']),
          reason: 'Same-day tasks from local and import must be unioned without loss');

      // Assert date 3 added
      expect(storedAcc.containsKey('2026-11-17'), isTrue);
      expect((storedAcc['2026-11-17'] as List).cast<String>(), contains('istighfar_tawbah'));

      // Repeat restore for idempotence
      final restoredRepeat = await BackupRestoreService.instance.restoreBackup(envelope, replaceMode: false);
      expect(restoredRepeat, isTrue);

      final rawAccRepeat = prefs.getString('tadabbur_daily_accountability_v1');
      final Map<String, dynamic> storedAccRepeat = json.decode(rawAccRepeat!);
      final date2TasksRepeat = (storedAccRepeat['2026-11-16'] as List).cast<String>();
      expect(date2TasksRepeat.where((t) => t == 'hifz_lisan').length, equals(1));
      expect(date2TasksRepeat.where((t) => t == 'sadaqah_ihsan').length, equals(1));
      expect(date2TasksRepeat.length, equals(2), reason: 'Accountability union must be idempotent');

      // Forced reload verification
      await TadabburJournalService.instance.init(forceReload: true);
    });

    test('omitted extended_features keys preserve existing local journal and accountability', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(() async {
        await cleanup();
        await TadabburJournalService.instance.init(forceReload: true);
      });

      // Seed local journal and accountability
      await prefs.setString(
        'tadabbur_journal_entries_v1',
        json.encode([localItemA.toJson()]),
      );
      await prefs.setString(
        'tadabbur_daily_accountability_v1',
        json.encode({'2026-11-15': ['birr_walidayn']}),
      );
      await TadabburJournalService.instance.init(forceReload: true);

      // Backup payload completely omitting journal and accountability
      final dataPayload = {
        'bookmarks': ['1:1'],
        'extended_features': {
          'sunan_rawatib': 'some_data',
        },
      };
      final envelope = createChecksumValidEnvelope(dataPayload);
      expect(BackupRestoreService.instance.validateBackup(json.encode(envelope)).isValid, isTrue);

      // In mergeMode: existing state preserved
      final restoredMerge = await BackupRestoreService.instance.restoreBackup(envelope, replaceMode: false);
      expect(restoredMerge, isTrue);

      final rawJournalMerge = prefs.getString('tadabbur_journal_entries_v1');
      expect(rawJournalMerge, isNotNull);
      final List<dynamic> journalMergeList = json.decode(rawJournalMerge!);
      expect(journalMergeList.map((e) => e['id'] as String), contains('local_item_a'));

      final rawAccMerge = prefs.getString('tadabbur_daily_accountability_v1');
      expect(rawAccMerge, isNotNull);
      final Map<String, dynamic> accMergeMap = json.decode(rawAccMerge!);
      expect((accMergeMap['2026-11-15'] as List).cast<String>(), contains('birr_walidayn'));

      // In replaceMode: omitted keys still preserve existing local data
      final restoredReplace = await BackupRestoreService.instance.restoreBackup(envelope, replaceMode: true);
      expect(restoredReplace, isTrue);

      final rawJournalReplace = prefs.getString('tadabbur_journal_entries_v1');
      expect(rawJournalReplace, isNotNull);
      final List<dynamic> journalReplaceList = json.decode(rawJournalReplace!);
      expect(journalReplaceList.map((e) => e['id'] as String), contains('local_item_a'));

      final rawAccReplace = prefs.getString('tadabbur_daily_accountability_v1');
      expect(rawAccReplace, isNotNull);
      final Map<String, dynamic> accReplaceMap = json.decode(rawAccReplace!);
      expect((accReplaceMap['2026-11-15'] as List).cast<String>(), contains('birr_walidayn'));
    });
  });
}
