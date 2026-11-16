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

  group('BackupRestoreService Daily Accountability Coverage & Regression Tests', () {
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
        await SettingsService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
        await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
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

    test('replaceMode false (merge): accountability performs same-day task union on today and preserves different dates with public getter', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(() async {
        await cleanup();
        await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      });

      final now = DateTime.now();
      final todayKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final yesterday = now.subtract(const Duration(days: 1));
      final yesterdayKey = '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
      final otherDate = now.add(const Duration(days: 1));
      final otherDateKey = '${otherDate.year}-${otherDate.month.toString().padLeft(2, '0')}-${otherDate.day.toString().padLeft(2, '0')}';

      // Local state has yesterday and today with task 1
      final localAccountability = {
        yesterdayKey: ['birr_walidayn'],
        todayKey: ['hifz_lisan'],
      };
      await prefs.setString(
        'tadabbur_daily_accountability_v1',
        json.encode(localAccountability),
      );
      await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      expect(TadabburJournalService.instance.isEthicalItemDoneToday('hifz_lisan'), isTrue);
      expect(TadabburJournalService.instance.isEthicalItemDoneToday('sadaqah_ihsan'), isFalse);

      // Imported state has today with task 2 (same-day union!) and otherDate with task 3
      final importAccountability = {
        todayKey: ['sadaqah_ihsan'],
        otherDateKey: ['istighfar_tawbah'],
      };
      final dataPayload = {
        'extended_features': {
          'tadabbur_daily_accountability': json.encode(importAccountability),
        },
      };
      final envelope = createChecksumValidEnvelope(dataPayload);
      final validation = BackupRestoreService.instance.validateBackup(json.encode(envelope));
      expect(validation.isValid, isTrue);

      final restored = await BackupRestoreService.instance
          .restoreBackup(envelope, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(restored, isTrue);

      final rawAcc = prefs.getString('tadabbur_daily_accountability_v1');
      expect(rawAcc, isNotNull);
      final Map<String, dynamic> storedAcc = json.decode(rawAcc!);

      // Assert yesterday preserved
      expect(storedAcc.containsKey(yesterdayKey), isTrue);
      expect((storedAcc[yesterdayKey] as List).cast<String>(), contains('birr_walidayn'));

      // Assert today has same-day union
      expect(storedAcc.containsKey(todayKey), isTrue);
      final todayTasks = (storedAcc[todayKey] as List).cast<String>();
      expect(todayTasks, containsAll(['hifz_lisan', 'sadaqah_ihsan']),
          reason: 'Same-day tasks from local and import must be unioned without loss');

      // Assert otherDate added
      expect(storedAcc.containsKey(otherDateKey), isTrue);
      expect((storedAcc[otherDateKey] as List).cast<String>(), contains('istighfar_tawbah'));

      // Forced reload verification on live singleton
      await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));

      // Public getter verification on today's items
      expect(TadabburJournalService.instance.isEthicalItemDoneToday('hifz_lisan'), isTrue,
          reason: 'Local item on today must remain done after merge');
      expect(TadabburJournalService.instance.isEthicalItemDoneToday('sadaqah_ihsan'), isTrue,
          reason: 'Imported item on today must be done after merge');
      expect(TadabburJournalService.instance.isEthicalItemDoneToday('birr_walidayn'), isFalse,
          reason: 'Yesterday item must not report as done today');
    });

    test('replaceMode false (merge): repeat restore is idempotent with exact map and set equality', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(() async {
        await cleanup();
        await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      });

      final now = DateTime.now();
      final todayKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final otherDate = now.add(const Duration(days: 1));
      final otherDateKey = '${otherDate.year}-${otherDate.month.toString().padLeft(2, '0')}-${otherDate.day.toString().padLeft(2, '0')}';

      final localAcc = {
        todayKey: ['hifz_lisan'],
      };
      await prefs.setString(
        'tadabbur_daily_accountability_v1',
        json.encode(localAcc),
      );
      await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));

      final importAccountability = {
        todayKey: ['sadaqah_ihsan'],
        otherDateKey: ['istighfar_tawbah'],
      };
      final dataPayload = {
        'extended_features': {
          'tadabbur_daily_accountability': json.encode(importAccountability),
        },
      };
      final envelope = createChecksumValidEnvelope(dataPayload);
      expect(BackupRestoreService.instance.validateBackup(json.encode(envelope)).isValid, isTrue);

      // First restore
      final restored1 = await BackupRestoreService.instance
          .restoreBackup(envelope, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(restored1, isTrue);

      final rawFirst = prefs.getString('tadabbur_daily_accountability_v1');
      expect(rawFirst, isNotNull);

      // Second repeat restore
      final restored2 = await BackupRestoreService.instance
          .restoreBackup(envelope, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(restored2, isTrue);

      final rawSecond = prefs.getString('tadabbur_daily_accountability_v1');
      expect(rawSecond, isNotNull);

      final Map<String, dynamic> firstMap = json.decode(rawFirst!);
      final Map<String, dynamic> secondMap = json.decode(rawSecond!);

      expect(secondMap.keys.toSet(), equals(firstMap.keys.toSet()));
      for (final date in firstMap.keys) {
        final firstList = (firstMap[date] as List).cast<String>();
        final secondList = (secondMap[date] as List).cast<String>();
        expect(secondList, equals(firstList),
            reason: 'Task list for date $date must be strictly identical across repeat restores');
      }

      await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      expect(TadabburJournalService.instance.isEthicalItemDoneToday('hifz_lisan'), isTrue);
      expect(TadabburJournalService.instance.isEthicalItemDoneToday('sadaqah_ihsan'), isTrue);
    });

    test('replaceMode false (merge): empty import preserves existing local accountability', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(() async {
        await cleanup();
        await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      });

      final now = DateTime.now();
      final todayKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final localAcc = {
        todayKey: ['birr_walidayn'],
      };
      await prefs.setString('tadabbur_daily_accountability_v1', json.encode(localAcc));
      await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      expect(TadabburJournalService.instance.isEthicalItemDoneToday('birr_walidayn'), isTrue);

      final dataPayload = {
        'extended_features': {
          'tadabbur_daily_accountability': '{}',
        },
      };
      final envelope = createChecksumValidEnvelope(dataPayload);
      expect(BackupRestoreService.instance.validateBackup(json.encode(envelope)).isValid, isTrue);

      final restored = await BackupRestoreService.instance
          .restoreBackup(envelope, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(restored, isTrue);

      final rawAcc = prefs.getString('tadabbur_daily_accountability_v1');
      expect(rawAcc, isNotNull);
      final Map<String, dynamic> storedAcc = json.decode(rawAcc!);
      expect(storedAcc.containsKey(todayKey), isTrue);
      expect((storedAcc[todayKey] as List).cast<String>(), contains('birr_walidayn'),
          reason: 'Empty import in mergeMode must preserve local accountability');

      await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      expect(TadabburJournalService.instance.isEthicalItemDoneToday('birr_walidayn'), isTrue);
    });

    test('replaceMode true: replaces existing accountability with imported, and empty import clears accountability', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(() async {
        await cleanup();
        await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      });

      final now = DateTime.now();
      final todayKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final yesterday = now.subtract(const Duration(days: 1));
      final yesterdayKey = '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

      // Part 1: Replaces
      final localAcc = {
        yesterdayKey: ['birr_walidayn'],
      };
      await prefs.setString('tadabbur_daily_accountability_v1', json.encode(localAcc));
      await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));

      final replacePayload = {
        'extended_features': {
          'tadabbur_daily_accountability': json.encode({
            todayKey: ['hifz_lisan'],
          }),
        },
      };
      final envelopeReplace = createChecksumValidEnvelope(replacePayload);
      expect(BackupRestoreService.instance.validateBackup(json.encode(envelopeReplace)).isValid, isTrue);

      final restoredReplace = await BackupRestoreService.instance
          .restoreBackup(envelopeReplace, replaceMode: true)
          .timeout(const Duration(seconds: 5));
      expect(restoredReplace, isTrue);

      final rawReplaced = prefs.getString('tadabbur_daily_accountability_v1');
      expect(rawReplaced, isNotNull);
      final Map<String, dynamic> replacedAcc = json.decode(rawReplaced!);
      expect(replacedAcc.containsKey(yesterdayKey), isFalse, reason: 'Previous date must be cleared in replaceMode true');
      expect(replacedAcc.containsKey(todayKey), isTrue);
      expect((replacedAcc[todayKey] as List).cast<String>(), equals(['hifz_lisan']));

      await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      expect(TadabburJournalService.instance.isEthicalItemDoneToday('hifz_lisan'), isTrue);

      // Part 2: Empty clears
      final emptyPayload = {
        'extended_features': {
          'tadabbur_daily_accountability': '{}',
        },
      };
      final envelopeEmpty = createChecksumValidEnvelope(emptyPayload);
      expect(BackupRestoreService.instance.validateBackup(json.encode(envelopeEmpty)).isValid, isTrue);

      final restoredEmpty = await BackupRestoreService.instance
          .restoreBackup(envelopeEmpty, replaceMode: true)
          .timeout(const Duration(seconds: 5));
      expect(restoredEmpty, isTrue);

      final rawEmpty = prefs.getString('tadabbur_daily_accountability_v1');
      expect(rawEmpty, isNotNull);
      final Map<String, dynamic> emptyAcc = json.decode(rawEmpty!);
      expect(emptyAcc, isEmpty, reason: 'replaceMode true with empty import must clear accountability');

      await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      expect(TadabburJournalService.instance.isEthicalItemDoneToday('hifz_lisan'), isFalse);
    });

    test('omitted extended_features keys preserve existing local accountability in both merge and replace modes', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(() async {
        await cleanup();
        await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      });

      final now = DateTime.now();
      final todayKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      await prefs.setString(
        'tadabbur_daily_accountability_v1',
        json.encode({todayKey: ['birr_walidayn']}),
      );
      await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));

      final dataPayload = {
        'bookmarks': ['1:1'],
        'extended_features': <String, dynamic>{},
      };
      final envelope = createChecksumValidEnvelope(dataPayload);
      expect(BackupRestoreService.instance.validateBackup(json.encode(envelope)).isValid, isTrue);

      // In mergeMode: existing state preserved
      final restoredMerge = await BackupRestoreService.instance
          .restoreBackup(envelope, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(restoredMerge, isTrue);

      final rawAccMerge = prefs.getString('tadabbur_daily_accountability_v1');
      expect(rawAccMerge, isNotNull);
      final Map<String, dynamic> accMergeMap = json.decode(rawAccMerge!);
      expect((accMergeMap[todayKey] as List).cast<String>(), contains('birr_walidayn'));

      // In replaceMode: omitted keys still preserve existing local data
      final restoredReplace = await BackupRestoreService.instance
          .restoreBackup(envelope, replaceMode: true)
          .timeout(const Duration(seconds: 5));
      expect(restoredReplace, isTrue);

      final rawAccReplace = prefs.getString('tadabbur_daily_accountability_v1');
      expect(rawAccReplace, isNotNull);
      final Map<String, dynamic> accReplaceMap = json.decode(rawAccReplace!);
      expect((accReplaceMap[todayKey] as List).cast<String>(), contains('birr_walidayn'));
    });

    test('replaceMode false (merge): malformed imported inner JSON preserves valid local raw prefs and forced live reload', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(() async {
        await cleanup();
        await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      });

      final now = DateTime.now();
      final todayKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final validLocalRaw = json.encode({todayKey: ['birr_walidayn']});
      await prefs.setString('tadabbur_daily_accountability_v1', validLocalRaw);
      await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      expect(TadabburJournalService.instance.isEthicalItemDoneToday('birr_walidayn'), isTrue);

      // Malformed inner JSON string inside valid backup envelope
      final dataPayload = {
        'extended_features': {
          'tadabbur_daily_accountability': '{ not valid json ...',
        },
      };
      final envelope = createChecksumValidEnvelope(dataPayload);
      expect(BackupRestoreService.instance.validateBackup(json.encode(envelope)).isValid, isTrue);

      final restored = await BackupRestoreService.instance
          .restoreBackup(envelope, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(restored, isTrue);

      // Conservative whole-feature skip: raw local prefs MUST remain exact raw bytes
      expect(prefs.getString('tadabbur_daily_accountability_v1'), equals(validLocalRaw),
          reason: 'Malformed imported JSON must not overwrite or corrupt valid local raw bytes');

      await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      expect(TadabburJournalService.instance.isEthicalItemDoneToday('birr_walidayn'), isTrue);
    });

    test('replaceMode false (merge): wrong imported shape (non-map, non-list, or non-string elements) preserves valid local raw prefs and forced live reload', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(() async {
        await cleanup();
        await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      });

      final now = DateTime.now();
      final todayKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final validLocalRaw = json.encode({todayKey: ['birr_walidayn']});
      await prefs.setString('tadabbur_daily_accountability_v1', validLocalRaw);
      await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));

      // Case A: Imported payload is a JSON list instead of a Map
      final envelopeList = createChecksumValidEnvelope({
        'extended_features': {
          'tadabbur_daily_accountability': '["birr_walidayn"]',
        },
      });
      expect(BackupRestoreService.instance.validateBackup(json.encode(envelopeList)).isValid, isTrue);

      final resList = await BackupRestoreService.instance
          .restoreBackup(envelopeList, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(resList, isTrue);
      expect(prefs.getString('tadabbur_daily_accountability_v1'), equals(validLocalRaw),
          reason: 'Non-map imported shape must be conservatively skipped');

      // Case B: Map with non-list value
      final envelopeNonListVal = createChecksumValidEnvelope({
        'extended_features': {
          'tadabbur_daily_accountability': '{"2026-11-16": "not_a_list"}',
        },
      });
      expect(BackupRestoreService.instance.validateBackup(json.encode(envelopeNonListVal)).isValid, isTrue);

      final resNonListVal = await BackupRestoreService.instance
          .restoreBackup(envelopeNonListVal, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(resNonListVal, isTrue);
      expect(prefs.getString('tadabbur_daily_accountability_v1'), equals(validLocalRaw),
          reason: 'Map with non-list values must be conservatively skipped');

      // Case C: Map with list containing non-string elements (do NOT silently drop; skip whole feature)
      final envelopeBadElem = createChecksumValidEnvelope({
        'extended_features': {
          'tadabbur_daily_accountability': '{"2026-11-16": ["valid_task", 12345]}',
        },
      });
      expect(BackupRestoreService.instance.validateBackup(json.encode(envelopeBadElem)).isValid, isTrue);

      final resBadElem = await BackupRestoreService.instance
          .restoreBackup(envelopeBadElem, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(resBadElem, isTrue);
      expect(prefs.getString('tadabbur_daily_accountability_v1'), equals(validLocalRaw),
          reason: 'List with non-string elements must not be silently filtered; skip whole feature');

      await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      expect(TadabburJournalService.instance.isEthicalItemDoneToday('birr_walidayn'), isTrue);
    });

    test('replaceMode false (merge): invalid local accountability raw blob is preserved without overwrite attempt', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(() async {
        await cleanup();
        await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      });

      const invalidLocalRaw = '{ corrupted local raw data, not json';
      await prefs.setString('tadabbur_daily_accountability_v1', invalidLocalRaw);

      final dataPayload = {
        'extended_features': {
          'tadabbur_daily_accountability': json.encode({'2026-11-16': ['sadaqah_ihsan']}),
        },
      };
      final envelope = createChecksumValidEnvelope(dataPayload);
      expect(BackupRestoreService.instance.validateBackup(json.encode(envelope)).isValid, isTrue);

      final restored = await BackupRestoreService.instance
          .restoreBackup(envelope, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(restored, isTrue);

      // Must not overwrite an invalid local blob attempting a repair
      expect(prefs.getString('tadabbur_daily_accountability_v1'), equals(invalidLocalRaw),
          reason: 'Invalid local blob must not be overwritten or repaired during merge');
    });

    test('replaceMode false (merge): absent local raw with imported duplicate tasks performs first-pass dedup and repeat byte idempotence', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(() async {
        await cleanup();
        await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      });

      // Local raw is absent (null)
      await prefs.remove('tadabbur_daily_accountability_v1');
      await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));

      final importPayload = {
        '2026-11-16': ['birr_walidayn', 'birr_walidayn', 'hifz_lisan'],
      };
      final dataPayload = {
        'extended_features': {
          'tadabbur_daily_accountability': json.encode(importPayload),
        },
      };
      final envelope = createChecksumValidEnvelope(dataPayload);
      expect(BackupRestoreService.instance.validateBackup(json.encode(envelope)).isValid, isTrue);

      // First restore: must immediately deduplicate tasks
      final res1 = await BackupRestoreService.instance
          .restoreBackup(envelope, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(res1, isTrue);

      final firstRaw = prefs.getString('tadabbur_daily_accountability_v1');
      expect(firstRaw, isNotNull);
      final Map<String, dynamic> firstDecoded = json.decode(firstRaw!);
      final firstTasks = (firstDecoded['2026-11-16'] as List).cast<String>();
      expect(firstTasks.length, equals(2),
          reason: 'Imported duplicate tasks must be deduplicated on first write when local is absent');
      expect(firstTasks, equals(['birr_walidayn', 'hifz_lisan']));

      // Second repeat restore: must produce identical raw bytes
      final res2 = await BackupRestoreService.instance
          .restoreBackup(envelope, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(res2, isTrue);

      final secondRaw = prefs.getString('tadabbur_daily_accountability_v1');
      expect(secondRaw, equals(firstRaw),
          reason: 'Repeat restore must be byte-for-byte idempotent');
    });

    test('replaceMode false (merge): empty string local raw with imported duplicate tasks performs first-pass dedup and repeat byte idempotence', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(() async {
        await cleanup();
        await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      });

      // Local raw is empty string
      await prefs.setString('tadabbur_daily_accountability_v1', '');
      await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));

      final importPayload = {
        '2026-11-16': ['birr_walidayn', 'birr_walidayn', 'hifz_lisan'],
      };
      final dataPayload = {
        'extended_features': {
          'tadabbur_daily_accountability': json.encode(importPayload),
        },
      };
      final envelope = createChecksumValidEnvelope(dataPayload);
      expect(BackupRestoreService.instance.validateBackup(json.encode(envelope)).isValid, isTrue);

      // First restore: must immediately deduplicate tasks
      final res1 = await BackupRestoreService.instance
          .restoreBackup(envelope, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(res1, isTrue);

      final firstRaw = prefs.getString('tadabbur_daily_accountability_v1');
      expect(firstRaw, isNotNull);
      final Map<String, dynamic> firstDecoded = json.decode(firstRaw!);
      final firstTasks = (firstDecoded['2026-11-16'] as List).cast<String>();
      expect(firstTasks.length, equals(2),
          reason: 'Imported duplicate tasks must be deduplicated on first write when local is empty');
      expect(firstTasks, equals(['birr_walidayn', 'hifz_lisan']));

      // Second repeat restore: must produce identical raw bytes
      final res2 = await BackupRestoreService.instance
          .restoreBackup(envelope, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(res2, isTrue);

      final secondRaw = prefs.getString('tadabbur_daily_accountability_v1');
      expect(secondRaw, equals(firstRaw),
          reason: 'Repeat restore must be byte-for-byte idempotent when local was empty string');
    });

    test('replaceMode false (merge): wrong-shape local accountability (list, date:string, non-string element) preserves exact raw bytes', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(() async {
        await cleanup();
        await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      });

      final validEnvelope = createChecksumValidEnvelope({
        'extended_features': {
          'tadabbur_daily_accountability': json.encode({'2026-11-16': ['sadaqah_ihsan']}),
        },
      });
      expect(BackupRestoreService.instance.validateBackup(json.encode(validEnvelope)).isValid, isTrue);

      // Case A: Local accountability is a JSON list instead of Map
      const localListRaw = '["not_a_map_element"]';
      await prefs.setString('tadabbur_daily_accountability_v1', localListRaw);

      final resList = await BackupRestoreService.instance
          .restoreBackup(validEnvelope, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(resList, isTrue);
      expect(prefs.getString('tadabbur_daily_accountability_v1'), equals(localListRaw),
          reason: 'Local JSON list must be preserved without overwrite');

      // Case B: Local accountability is a Map where a date maps to a string instead of a List
      const localDateStringRaw = '{"2026-11-16": "not_a_list"}';
      await prefs.setString('tadabbur_daily_accountability_v1', localDateStringRaw);

      final resDateString = await BackupRestoreService.instance
          .restoreBackup(validEnvelope, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(resDateString, isTrue);
      expect(prefs.getString('tadabbur_daily_accountability_v1'), equals(localDateStringRaw),
          reason: 'Local map with string date value must be preserved without overwrite');

      // Case C: Local accountability has list with non-string element
      const localBadElemRaw = '{"2026-11-16": ["valid_task", 9999]}';
      await prefs.setString('tadabbur_daily_accountability_v1', localBadElemRaw);

      final resBadElem = await BackupRestoreService.instance
          .restoreBackup(validEnvelope, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(resBadElem, isTrue);
      expect(prefs.getString('tadabbur_daily_accountability_v1'), equals(localBadElemRaw),
          reason: 'Local map with non-string elements in list must be preserved without overwrite');
    });
  });

  group('BackupRestoreService Tadabbur Journal Coverage & Regression Tests', () {
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
        await SettingsService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
        await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
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

    void assertReflectionEquals(TadabburReflectionItem actual, TadabburReflectionItem expected) {
      expect(actual.id, equals(expected.id));
      expect(actual.surahId, equals(expected.surahId));
      expect(actual.surahName, equals(expected.surahName));
      expect(actual.ayahNumber, equals(expected.ayahNumber));
      expect(actual.ayahSnippet, equals(expected.ayahSnippet));
      expect(actual.faithMessage, equals(expected.faithMessage));
      expect(actual.practicalAction, equals(expected.practicalAction));
      expect(actual.derivedDua, equals(expected.derivedDua));
      expect(actual.createdAt.toIso8601String(), equals(expected.createdAt.toIso8601String()));
    }

    void assertJsonReflectionEquals(Map<String, dynamic> actual, TadabburReflectionItem expected) {
      expect(actual['id'], equals(expected.id));
      expect(actual['surahId'], equals(expected.surahId));
      expect(actual['surahName'], equals(expected.surahName));
      expect(actual['ayahNumber'], equals(expected.ayahNumber));
      expect(actual['ayahSnippet'], equals(expected.ayahSnippet));
      expect(actual['faithMessage'], equals(expected.faithMessage));
      expect(actual['practicalAction'], equals(expected.practicalAction));
      expect(actual['derivedDua'], equals(expected.derivedDua));
      expect(actual['createdAt'], equals(expected.createdAt.toIso8601String()));
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

    test('replaceMode false (merge): distinct local A and import B both survive in prefs and live service with exact payload', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(() async {
        await cleanup();
        await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      });

      await prefs.setString(
        'tadabbur_journal_entries_v1',
        json.encode([localItemA.toJson()]),
      );
      await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      expect(TadabburJournalService.instance.entries.map((e) => e.id), contains('local_item_a'));

      final dataPayload = {
        'extended_features': {
          'tadabbur_journal': json.encode([importItemB.toJson()]),
        },
      };
      final envelope = createChecksumValidEnvelope(dataPayload);
      final validation = BackupRestoreService.instance.validateBackup(json.encode(envelope));
      expect(validation.isValid, isTrue);

      final restored = await BackupRestoreService.instance
          .restoreBackup(envelope, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(restored, isTrue);

      final rawStored = prefs.getString('tadabbur_journal_entries_v1');
      expect(rawStored, isNotNull);
      final List<dynamic> decodedList = json.decode(rawStored!);
      expect(decodedList.length, equals(2));
      final itemAMap = decodedList.firstWhere((e) => e['id'] == 'local_item_a') as Map<String, dynamic>;
      final itemBMap = decodedList.firstWhere((e) => e['id'] == 'import_item_b') as Map<String, dynamic>;
      assertJsonReflectionEquals(itemAMap, localItemA);
      assertJsonReflectionEquals(itemBMap, importItemB);

      await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      expect(TadabburJournalService.instance.entries.length, equals(2));
      final liveA = TadabburJournalService.instance.entries.firstWhere((e) => e.id == 'local_item_a');
      final liveB = TadabburJournalService.instance.entries.firstWhere((e) => e.id == 'import_item_b');
      assertReflectionEquals(liveA, localItemA);
      assertReflectionEquals(liveB, importItemB);
    });

    test('replaceMode false (merge): repeat restore is idempotent without duplicate entries', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(() async {
        await cleanup();
        await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      });

      await prefs.setString(
        'tadabbur_journal_entries_v1',
        json.encode([localItemA.toJson()]),
      );
      await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));

      final dataPayload = {
        'extended_features': {
          'tadabbur_journal': json.encode([importItemB.toJson()]),
        },
      };
      final envelope = createChecksumValidEnvelope(dataPayload);
      final validation = BackupRestoreService.instance.validateBackup(json.encode(envelope));
      expect(validation.isValid, isTrue);

      final restoredFirst = await BackupRestoreService.instance
          .restoreBackup(envelope, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(restoredFirst, isTrue);

      final restoredSecond = await BackupRestoreService.instance
          .restoreBackup(envelope, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(restoredSecond, isTrue);

      final rawStored = prefs.getString('tadabbur_journal_entries_v1');
      expect(rawStored, isNotNull);
      final List<dynamic> decodedList = json.decode(rawStored!);
      final storedIds = decodedList.map((e) => e['id'] as String).toList();
      expect(storedIds.where((id) => id == 'local_item_a').length, equals(1));
      expect(storedIds.where((id) => id == 'import_item_b').length, equals(1));
      expect(storedIds.length, equals(2));

      final itemAMap = decodedList.firstWhere((e) => e['id'] == 'local_item_a') as Map<String, dynamic>;
      final itemBMap = decodedList.firstWhere((e) => e['id'] == 'import_item_b') as Map<String, dynamic>;
      assertJsonReflectionEquals(itemAMap, localItemA);
      assertJsonReflectionEquals(itemBMap, importItemB);

      await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      expect(TadabburJournalService.instance.entries.length, equals(2));
    });

    test('replaceMode false (merge): empty import preserves existing local journal entries', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(() async {
        await cleanup();
        await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      });

      await prefs.setString(
        'tadabbur_journal_entries_v1',
        json.encode([localItemA.toJson()]),
      );
      await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));

      final dataPayload = {
        'extended_features': {
          'tadabbur_journal': '[]',
        },
      };
      final envelope = createChecksumValidEnvelope(dataPayload);
      final validation = BackupRestoreService.instance.validateBackup(json.encode(envelope));
      expect(validation.isValid, isTrue);

      final restored = await BackupRestoreService.instance
          .restoreBackup(envelope, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(restored, isTrue);

      final rawStored = prefs.getString('tadabbur_journal_entries_v1');
      expect(rawStored, isNotNull);
      final List<dynamic> decodedList = json.decode(rawStored!);
      final storedIds = decodedList.map((e) => e['id'] as String).toList();
      expect(storedIds, contains('local_item_a'));
      final itemAMap = decodedList.firstWhere((e) => e['id'] == 'local_item_a') as Map<String, dynamic>;
      assertJsonReflectionEquals(itemAMap, localItemA);

      await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      expect(TadabburJournalService.instance.entries.map((e) => e.id), contains('local_item_a'));
      final liveA = TadabburJournalService.instance.entries.firstWhere((e) => e.id == 'local_item_a');
      assertReflectionEquals(liveA, localItemA);
    });

    test('replaceMode false (merge): equal ID and equal content dedupes without adding duplicate entry', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(() async {
        await cleanup();
        await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      });

      await prefs.setString(
        'tadabbur_journal_entries_v1',
        json.encode([localItemA.toJson()]),
      );
      await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));

      final envelope = createChecksumValidEnvelope({
        'extended_features': {
          'tadabbur_journal': json.encode([localItemA.toJson()]),
        },
      });
      expect(BackupRestoreService.instance.validateBackup(json.encode(envelope)).isValid, isTrue);

      final res = await BackupRestoreService.instance
          .restoreBackup(envelope, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(res, isTrue);

      final rawStored = prefs.getString('tadabbur_journal_entries_v1');
      expect(rawStored, isNotNull);
      final List<dynamic> decodedList = json.decode(rawStored!);
      expect(decodedList.length, equals(1), reason: 'Identical ID and content must dedupe to 1 entry');
      assertJsonReflectionEquals(decodedList[0] as Map<String, dynamic>, localItemA);
    });

    test('replaceMode false (merge): same ID with different content preserves local entry and assigns imported restored_<checksum> ID, repeat restore idempotent', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(() async {
        await cleanup();
        await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      });

      final localColliding = {
        'id': 'shared_id',
        'surahId': 2,
        'surahName': 'البقرة',
        'ayahNumber': 255,
        'faithMessage': 'رسالة محلية',
      };

      final importColliding = {
        'id': 'shared_id',
        'surahId': 2,
        'surahName': 'البقرة',
        'ayahNumber': 255,
        'faithMessage': 'رسالة مستوردة مختلفة',
      };

      await prefs.setString('tadabbur_journal_entries_v1', json.encode([localColliding]));
      await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));

      final envelope = createChecksumValidEnvelope({
        'extended_features': {
          'tadabbur_journal': json.encode([importColliding]),
        },
      });
      expect(BackupRestoreService.instance.validateBackup(json.encode(envelope)).isValid, isTrue);

      final res1 = await BackupRestoreService.instance
          .restoreBackup(envelope, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(res1, isTrue);

      final rawStored1 = prefs.getString('tadabbur_journal_entries_v1');
      expect(rawStored1, isNotNull);
      final List<dynamic> list1 = json.decode(rawStored1!);
      expect(list1.length, equals(2), reason: 'Both local and imported entries must be preserved');

      // Index 0: local entry preserved with original ID and content
      final map0 = list1[0] as Map<String, dynamic>;
      expect(map0['id'], equals('shared_id'));
      expect(map0['faithMessage'], equals('رسالة محلية'));

      // Index 1: imported entry assigned restored_<checksum> ID
      final importSansId = Map<String, dynamic>.from(importColliding)..remove('id');
      final expectedDerivedId =
          'restored_${BackupRestoreService.calculateChecksum(BackupRestoreService.canonicalJsonEncode(importSansId))}';

      final map1 = list1[1] as Map<String, dynamic>;
      expect(map1['id'], equals(expectedDerivedId));
      expect(map1['faithMessage'], equals('رسالة مستوردة مختلفة'));

      // Repeat restore (+repeat) must be 100% idempotent
      final res2 = await BackupRestoreService.instance
          .restoreBackup(envelope, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(res2, isTrue);
      expect(prefs.getString('tadabbur_journal_entries_v1'), equals(rawStored1));
    });

    test('replaceMode false (merge): occupied derived base slot triggers numerical suffix (-2, -3) and repeat restore is idempotent', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(() async {
        await cleanup();
        await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      });

      final importColliding = {
        'id': 'shared_id',
        'surahId': 2,
        'faithMessage': 'رسالة مستوردة',
      };
      final importSansId = Map<String, dynamic>.from(importColliding)..remove('id');
      final expectedBaseId =
          'restored_${BackupRestoreService.calculateChecksum(BackupRestoreService.canonicalJsonEncode(importSansId))}';

      final localEntryOriginal = {
        'id': 'shared_id',
        'surahId': 1,
        'faithMessage': 'محتوى محلي أول',
      };
      final localEntryBaseOccupied = {
        'id': expectedBaseId,
        'surahId': 3,
        'faithMessage': 'محتوى محلي يشغل المعرف المشتق الأساسي',
      };

      await prefs.setString(
        'tadabbur_journal_entries_v1',
        json.encode([localEntryOriginal, localEntryBaseOccupied]),
      );
      await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));

      final envelope = createChecksumValidEnvelope({
        'extended_features': {
          'tadabbur_journal': json.encode([importColliding]),
        },
      });
      expect(BackupRestoreService.instance.validateBackup(json.encode(envelope)).isValid, isTrue);

      final res1 = await BackupRestoreService.instance
          .restoreBackup(envelope, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(res1, isTrue);

      final rawStored1 = prefs.getString('tadabbur_journal_entries_v1');
      expect(rawStored1, isNotNull);
      final List<dynamic> list1 = json.decode(rawStored1!);
      expect(list1.length, equals(3));

      // Index 2 should have suffix -2
      final map2 = list1[2] as Map<String, dynamic>;
      expect(map2['id'], equals('$expectedBaseId-2'));
      expect(map2['faithMessage'], equals('رسالة مستوردة'));

      // Repeat restore must be byte-for-byte idempotent
      final res2 = await BackupRestoreService.instance
          .restoreBackup(envelope, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(res2, isTrue);
      expect(prefs.getString('tadabbur_journal_entries_v1'), equals(rawStored1));
    });

    test('replaceMode false (merge): duplicate occupants with same ID: ANY occupant with matching content triggers dedupe', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(() async {
        await cleanup();
        await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      });

      final localD1 = {
        'id': 'dup_id',
        'faithMessage': 'محتوى أول',
      };
      final localD2 = {
        'id': 'dup_id',
        'faithMessage': 'محتوى ثانٍ',
      };

      await prefs.setString(
        'tadabbur_journal_entries_v1',
        json.encode([localD1, localD2]),
      );
      await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));

      final importMatchingD1 = {
        'id': 'dup_id',
        'faithMessage': 'محتوى أول',
      };

      final envelope = createChecksumValidEnvelope({
        'extended_features': {
          'tadabbur_journal': json.encode([importMatchingD1]),
        },
      });
      expect(BackupRestoreService.instance.validateBackup(json.encode(envelope)).isValid, isTrue);

      final res = await BackupRestoreService.instance
          .restoreBackup(envelope, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(res, isTrue);

      final rawStored = prefs.getString('tadabbur_journal_entries_v1');
      expect(rawStored, isNotNull);
      final List<dynamic> list = json.decode(rawStored!);
      expect(list.length, equals(2), reason: 'ANY occupant with same content must dedupe without adding another');
      expect(list[0]['faithMessage'], equals('محتوى أول'));
      expect(list[1]['faithMessage'], equals('محتوى ثانٍ'));
    });

    test('replaceMode false (merge): absent local raw and empty string local raw perform first-pass dedup and repeat byte idempotence', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(() async {
        await cleanup();
        await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      });

      final importDupA = TadabburReflectionItem(
        id: 'import_firstdedup_id',
        surahId: 2,
        surahName: 'البقرة',
        ayahNumber: 255,
        ayahSnippet: 'اللَّهُ لَا إِلَٰهَ إِلَّا هُوَ الْحَيُّ الْقَيُّومُ',
        faithMessage: 'رسالة مستوردة سابقة',
        practicalAction: 'عمل سابق',
        derivedDua: 'دعاء سابق',
        createdAt: DateTime(2026, 11, 10, 8, 0),
      );

      final importDupB = TadabburReflectionItem(
        id: 'import_firstdedup_id',
        surahId: 2,
        surahName: 'البقرة',
        ayahNumber: 255,
        ayahSnippet: 'اللَّهُ لَا إِلَٰهَ إِلَّا هُوَ الْحَيُّ الْقَيُّومُ',
        faithMessage: 'رسالة مستوردة سابقة', // Identical content -> dedupes!
        practicalAction: 'عمل سابق',
        derivedDua: 'دعاء سابق',
        createdAt: DateTime(2026, 11, 10, 8, 0),
      );

      final envelope = createChecksumValidEnvelope({
        'extended_features': {
          'tadabbur_journal': json.encode([importDupA.toJson(), importDupB.toJson()]),
        },
      });
      expect(BackupRestoreService.instance.validateBackup(json.encode(envelope)).isValid, isTrue);

      // Case 1: Local key absent
      await prefs.remove('tadabbur_journal_entries_v1');
      final resAbsent1 = await BackupRestoreService.instance
          .restoreBackup(envelope, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(resAbsent1, isTrue);

      final rawAbsent1 = prefs.getString('tadabbur_journal_entries_v1');
      expect(rawAbsent1, isNotNull);
      final List<dynamic> listAbsent1 = json.decode(rawAbsent1!);
      expect(listAbsent1.length, equals(1));
      assertJsonReflectionEquals(listAbsent1[0] as Map<String, dynamic>, importDupA);

      final resAbsent2 = await BackupRestoreService.instance
          .restoreBackup(envelope, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(resAbsent2, isTrue);
      expect(prefs.getString('tadabbur_journal_entries_v1'), equals(rawAbsent1));

      // Case 2: Local key empty string
      await prefs.setString('tadabbur_journal_entries_v1', '');
      final resEmpty1 = await BackupRestoreService.instance
          .restoreBackup(envelope, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(resEmpty1, isTrue);

      final rawEmpty1 = prefs.getString('tadabbur_journal_entries_v1');
      expect(rawEmpty1, isNotNull);
      final List<dynamic> listEmpty1 = json.decode(rawEmpty1!);
      expect(listEmpty1.length, equals(1));
      assertJsonReflectionEquals(listEmpty1[0] as Map<String, dynamic>, importDupA);

      final resEmpty2 = await BackupRestoreService.instance
          .restoreBackup(envelope, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(resEmpty2, isTrue);
      expect(prefs.getString('tadabbur_journal_entries_v1'), equals(rawEmpty1));
    });

    test('replaceMode false (merge): import containing internal duplicates correctly dedupes identical and re-identifies different content', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(() async {
        await cleanup();
        await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      });

      await prefs.remove('tadabbur_journal_entries_v1');

      final itemIdentical1 = {'id': 'same_id', 'faithMessage': 'نفس المحتوى'};
      final itemIdentical2 = {'id': 'same_id', 'faithMessage': 'نفس المحتوى'};
      final itemDifferentContent = {'id': 'same_id', 'faithMessage': 'محتوى مختلف تماماً'};

      final envelope = createChecksumValidEnvelope({
        'extended_features': {
          'tadabbur_journal': json.encode([itemIdentical1, itemIdentical2, itemDifferentContent]),
        },
      });
      expect(BackupRestoreService.instance.validateBackup(json.encode(envelope)).isValid, isTrue);

      final res1 = await BackupRestoreService.instance
          .restoreBackup(envelope, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(res1, isTrue);

      final rawStored = prefs.getString('tadabbur_journal_entries_v1');
      expect(rawStored, isNotNull);
      final List<dynamic> list = json.decode(rawStored!);
      expect(list.length, equals(2));

      expect(list[0]['id'], equals('same_id'));
      expect(list[0]['faithMessage'], equals('نفس المحتوى'));

      final diffSansId = Map<String, dynamic>.from(itemDifferentContent)..remove('id');
      final expectedBaseId =
          'restored_${BackupRestoreService.calculateChecksum(BackupRestoreService.canonicalJsonEncode(diffSansId))}';
      expect(list[1]['id'], equals(expectedBaseId));
      expect(list[1]['faithMessage'], equals('محتوى مختلف تماماً'));

      // Repeat restore idempotence
      final res2 = await BackupRestoreService.instance
          .restoreBackup(envelope, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(res2, isTrue);
      expect(prefs.getString('tadabbur_journal_entries_v1'), equals(rawStored));
    });

    test('replaceMode false (merge): nested canonical maps sort keys recursively, preserve list order, and treat 2 vs 2.0 distinct', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(() async {
        await cleanup();
        await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      });

      // Case A: Map key ordering in nested structures: {b: 1, a: 2} is canonical identical to {a: 2, b: 1}
      final localNested = {
        'id': 'nested_id',
        'metadata': {'b': 1, 'a': 2},
      };
      await prefs.setString('tadabbur_journal_entries_v1', json.encode([localNested]));

      final importNestedSame = {
        'id': 'nested_id',
        'metadata': {'a': 2, 'b': 1}, // different key order, same content
      };

      final envA = createChecksumValidEnvelope({
        'extended_features': {
          'tadabbur_journal': json.encode([importNestedSame]),
        },
      });
      final resA = await BackupRestoreService.instance.restoreBackup(envA, replaceMode: false);
      expect(resA, isTrue);
      final listA = json.decode(prefs.getString('tadabbur_journal_entries_v1')!) as List;
      expect(listA.length, equals(1), reason: 'Canonical map equality must dedupe despite key order difference');

      // Case B: List order preservation: [1, 2] != [2, 1]
      final localListReversed = {
        'id': 'list_id',
        'tags': [1, 2],
      };
      await prefs.setString('tadabbur_journal_entries_v1', json.encode([localListReversed]));

      final envB = createChecksumValidEnvelope({
        'extended_features': {
          'tadabbur_journal': json.encode([
            {'id': 'list_id', 'tags': [2, 1]}, // different list order!
          ]),
        },
      });
      final resB = await BackupRestoreService.instance.restoreBackup(envB, replaceMode: false);
      expect(resB, isTrue);
      final listB = json.decode(prefs.getString('tadabbur_journal_entries_v1')!) as List;
      expect(listB.length, equals(2), reason: 'Different list order must be treated as different content -> derived ID');

      // Case C: Numeric 2 vs 2.0 distinct
      final localInt = {
        'id': 'num_id',
        'ayahNumber': 2,
      };
      await prefs.setString('tadabbur_journal_entries_v1', json.encode([localInt]));

      final envC = createChecksumValidEnvelope({
        'extended_features': {
          'tadabbur_journal': json.encode([
            {'id': 'num_id', 'custom_num': 2.0},
          ]),
        },
      });
      final resC = await BackupRestoreService.instance.restoreBackup(envC, replaceMode: false);
      expect(resC, isTrue);
      final listC = json.decode(prefs.getString('tadabbur_journal_entries_v1')!) as List;
      expect(listC.length, equals(2), reason: '2 vs 2.0 must be distinct content');
    });

    test('replaceMode false (merge): wrong-shape imported journal (non-JSON, top object, bad element, missing id, empty id, unsafe known field) preserves valid local raw prefs', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(() async {
        await cleanup();
        await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      });

      const validLocalRaw = '[{"id":"local_safe_1","faithMessage":"رسالة آمنة"}]';
      await prefs.setString('tadabbur_journal_entries_v1', validLocalRaw);

      final badPayloads = [
        '{not_valid_json',
        '{"id": "top_object_not_list"}',
        '["string_element_not_map"]',
        '[{"surahName": "missing_id"}]',
        '[{"id": "", "faithMessage": "empty_id"}]',
        '[{"id": 9999, "faithMessage": "int_id"}]',
        '[{"id": "safe_id", "surahId": "string_not_int"}]',
        '[{"id": "safe_id", "ayahNumber": "string_not_int"}]',
        '[{"id": "safe_id", "faithMessage": 12345}]',
        '[{"id": "safe_id", "practicalAction": ["list_not_string"]}]',
        '[{"id": "safe_id", "derivedDua": true}]',
        '[{"id": "safe_id", "createdAt": 20261115}]',
      ];

      for (final bad in badPayloads) {
        final envelope = createChecksumValidEnvelope({
          'extended_features': {
            'tadabbur_journal': bad,
          },
        });
        expect(BackupRestoreService.instance.validateBackup(json.encode(envelope)).isValid, isTrue);

        final res = await BackupRestoreService.instance
            .restoreBackup(envelope, replaceMode: false)
            .timeout(const Duration(seconds: 5));
        expect(res, isTrue);
        expect(prefs.getString('tadabbur_journal_entries_v1'), equals(validLocalRaw),
            reason: 'Whole-feature skip: bad import "$bad" must preserve valid local raw prefs');
      }
    });

    test('replaceMode false (merge): wrong-shape local journal (top object, bad element, missing id, empty id, unsafe known field) preserves raw local bytes without overwrite', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(() async {
        await cleanup();
        await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      });

      final validEnvelope = createChecksumValidEnvelope({
        'extended_features': {
          'tadabbur_journal': json.encode([importItemB.toJson()]),
        },
      });
      expect(BackupRestoreService.instance.validateBackup(json.encode(validEnvelope)).isValid, isTrue);

      final badLocalRawList = [
        '{"top_level": "object_not_list"}',
        '["list_element_not_map"]',
        '[{"surahName": "missing_id"}]',
        '[{"id": "", "surahName": "empty_id"}]',
        '[{"id": 12345}]',
        '[{"id": "local_bad_id", "surahId": "not_int"}]',
        '[{"id": "local_bad_id", "ayahNumber": 3.14}]',
        '[{"id": "local_bad_id", "faithMessage": false}]',
      ];

      for (final badLocal in badLocalRawList) {
        await prefs.setString('tadabbur_journal_entries_v1', badLocal);

        final res = await BackupRestoreService.instance
            .restoreBackup(validEnvelope, replaceMode: false)
            .timeout(const Duration(seconds: 5));
        expect(res, isTrue);
        expect(prefs.getString('tadabbur_journal_entries_v1'), equals(badLocal),
            reason: 'Whole-feature skip: invalid local raw "$badLocal" must be preserved without destructive overwrite');
      }
    });

    test('replaceMode false (merge): nullable backcompat accepts omitted or null known fields', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(() async {
        await cleanup();
        await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      });

      final itemWithNulls = {
        'id': 'nullable_item_1',
        'surahId': null,
        'ayahNumber': null,
        'surahName': null,
        'ayahSnippet': null,
        'faithMessage': null,
        'practicalAction': null,
        'derivedDua': null,
        'createdAt': null,
      };

      final envelope = createChecksumValidEnvelope({
        'extended_features': {
          'tadabbur_journal': json.encode([itemWithNulls]),
        },
      });
      expect(BackupRestoreService.instance.validateBackup(json.encode(envelope)).isValid, isTrue);

      final res = await BackupRestoreService.instance
          .restoreBackup(envelope, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(res, isTrue);

      final raw = prefs.getString('tadabbur_journal_entries_v1');
      expect(raw, isNotNull);
      final List<dynamic> list = json.decode(raw!);
      expect(list.length, equals(1));
      expect(list[0]['id'], equals('nullable_item_1'));
    });

    test('replaceMode true: replaces existing with imported, and empty import clears existing journal entries', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(() async {
        await cleanup();
        await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      });

      // Part 1: Replaces
      await prefs.setString(
        'tadabbur_journal_entries_v1',
        json.encode([localItemA.toJson()]),
      );
      await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));

      final replacePayload = {
        'extended_features': {
          'tadabbur_journal': json.encode([importItemB.toJson()]),
        },
      };
      final envelopeReplace = createChecksumValidEnvelope(replacePayload);
      expect(BackupRestoreService.instance.validateBackup(json.encode(envelopeReplace)).isValid, isTrue);

      final restoredReplace = await BackupRestoreService.instance
          .restoreBackup(envelopeReplace, replaceMode: true)
          .timeout(const Duration(seconds: 5));
      expect(restoredReplace, isTrue);

      final rawReplaced = prefs.getString('tadabbur_journal_entries_v1');
      expect(rawReplaced, isNotNull);
      final List<dynamic> replacedList = json.decode(rawReplaced!);
      final replacedIds = replacedList.map((e) => e['id'] as String).toList();
      expect(replacedIds, equals(['import_item_b']));
      final itemBMap = replacedList.first as Map<String, dynamic>;
      assertJsonReflectionEquals(itemBMap, importItemB);

      await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      expect(TadabburJournalService.instance.entries.length, equals(1));
      assertReflectionEquals(TadabburJournalService.instance.entries.first, importItemB);

      // Part 2: Empty clears
      final emptyPayload = {
        'extended_features': {
          'tadabbur_journal': '[]',
        },
      };
      final envelopeEmpty = createChecksumValidEnvelope(emptyPayload);
      expect(BackupRestoreService.instance.validateBackup(json.encode(envelopeEmpty)).isValid, isTrue);

      final restoredEmpty = await BackupRestoreService.instance
          .restoreBackup(envelopeEmpty, replaceMode: true)
          .timeout(const Duration(seconds: 5));
      expect(restoredEmpty, isTrue);

      final rawEmpty = prefs.getString('tadabbur_journal_entries_v1');
      expect(rawEmpty, isNotNull);
      final List<dynamic> emptyList = json.decode(rawEmpty!);
      expect(emptyList, isEmpty);

      await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      expect(TadabburJournalService.instance.entries, isEmpty);
    });

    test('replaceMode true: malformed/nonlist/empty raw string writes verbatim in replaceMode', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(() async {
        await cleanup();
        await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      });

      const validLocalRaw = '[{"id":"local_safe_replace","faithMessage":"رسالة آمنة"}]';

      // Case A: malformed/invalid JSON string writes verbatim
      await prefs.setString('tadabbur_journal_entries_v1', validLocalRaw);
      const malformedPayload = '{"not_a_valid_json_list';
      final envMalformed = createChecksumValidEnvelope({
        'extended_features': {
          'tadabbur_journal': malformedPayload,
        },
      });
      expect(BackupRestoreService.instance.validateBackup(json.encode(envMalformed)).isValid, isTrue);

      final resMalformed = await BackupRestoreService.instance
          .restoreBackup(envMalformed, replaceMode: true)
          .timeout(const Duration(seconds: 5));
      expect(resMalformed, isTrue);
      expect(prefs.getString('tadabbur_journal_entries_v1'), equals(malformedPayload),
          reason: 'replaceMode true must write raw import string verbatim even if malformed');

      // Case B: non-list JSON string (top-level Object) writes verbatim
      await prefs.setString('tadabbur_journal_entries_v1', validLocalRaw);
      const nonListPayload = '{"id": "top_object_not_list"}';
      final envNonList = createChecksumValidEnvelope({
        'extended_features': {
          'tadabbur_journal': nonListPayload,
        },
      });
      expect(BackupRestoreService.instance.validateBackup(json.encode(envNonList)).isValid, isTrue);

      final resNonList = await BackupRestoreService.instance
          .restoreBackup(envNonList, replaceMode: true)
          .timeout(const Duration(seconds: 5));
      expect(resNonList, isTrue);
      expect(prefs.getString('tadabbur_journal_entries_v1'), equals(nonListPayload),
          reason: 'replaceMode true must write raw import string verbatim even if non-list');

      // Case C: empty list "[]" writes verbatim (clears entries)
      await prefs.setString('tadabbur_journal_entries_v1', validLocalRaw);
      const emptyPayload = '[]';
      final envEmpty = createChecksumValidEnvelope({
        'extended_features': {
          'tadabbur_journal': emptyPayload,
        },
      });
      expect(BackupRestoreService.instance.validateBackup(json.encode(envEmpty)).isValid, isTrue);

      final resEmpty = await BackupRestoreService.instance
          .restoreBackup(envEmpty, replaceMode: true)
          .timeout(const Duration(seconds: 5));
      expect(resEmpty, isTrue);
      expect(prefs.getString('tadabbur_journal_entries_v1'), equals(emptyPayload),
          reason: 'replaceMode true must write empty string list verbatim');
    });

    test('omitted extended_features keys preserve existing local journal entries in both merge and replace modes', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(() async {
        await cleanup();
        await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      });

      await prefs.setString(
        'tadabbur_journal_entries_v1',
        json.encode([localItemA.toJson()]),
      );
      await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));

      final dataPayload = {
        'bookmarks': ['1:1'],
        'extended_features': <String, dynamic>{},
      };
      final envelope = createChecksumValidEnvelope(dataPayload);
      expect(BackupRestoreService.instance.validateBackup(json.encode(envelope)).isValid, isTrue);

      final restoredMerge = await BackupRestoreService.instance
          .restoreBackup(envelope, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(restoredMerge, isTrue);

      final rawJournalMerge = prefs.getString('tadabbur_journal_entries_v1');
      expect(rawJournalMerge, isNotNull);
      final List<dynamic> journalMergeList = json.decode(rawJournalMerge!);
      expect(journalMergeList.map((e) => e['id'] as String), contains('local_item_a'));
      final itemAMergeMap = journalMergeList.firstWhere((e) => e['id'] == 'local_item_a') as Map<String, dynamic>;
      assertJsonReflectionEquals(itemAMergeMap, localItemA);

      final restoredReplace = await BackupRestoreService.instance
          .restoreBackup(envelope, replaceMode: true)
          .timeout(const Duration(seconds: 5));
      expect(restoredReplace, isTrue);

      final rawJournalReplace = prefs.getString('tadabbur_journal_entries_v1');
      expect(rawJournalReplace, isNotNull);
      final List<dynamic> journalReplaceList = json.decode(rawJournalReplace!);
      expect(journalReplaceList.map((e) => e['id'] as String), contains('local_item_a'));
      final itemAReplaceMap = journalReplaceList.firstWhere((e) => e['id'] == 'local_item_a') as Map<String, dynamic>;
      assertJsonReflectionEquals(itemAReplaceMap, localItemA);
    });

    test('replaceMode false (merge): unknown extra fields and non-standard createdAt string are preserved raw without fromJson roundtrip', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(() async {
        await cleanup();
        await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      });

      final rawLocalPayload = json.encode([
        {
          'id': 'local_extra_id',
          'surahId': 1,
          'surahName': 'الفاتحة',
          'ayahNumber': 1,
          'faithMessage': 'رسالة محلية',
          'createdAt': 'custom-local-timestamp-string',
          'unknown_local_key': 'preserved_local_value',
          'tags': ['imaan', 'quran'],
        }
      ]);
      await prefs.setString('tadabbur_journal_entries_v1', rawLocalPayload);

      final rawImportPayload = json.encode([
        {
          'id': 'import_extra_id',
          'surahId': 2,
          'surahName': 'البقرة',
          'ayahNumber': 255,
          'faithMessage': 'رسالة مستوردة',
          'createdAt': 'custom-import-non-iso-date',
          'unknown_import_flag': 1001,
          'metadata': {'schema_subversion': 42},
        }
      ]);

      final envelope = createChecksumValidEnvelope({
        'extended_features': {
          'tadabbur_journal': rawImportPayload,
        },
      });
      expect(BackupRestoreService.instance.validateBackup(json.encode(envelope)).isValid, isTrue);

      final res1 = await BackupRestoreService.instance
          .restoreBackup(envelope, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(res1, isTrue);

      final rawMerged = prefs.getString('tadabbur_journal_entries_v1');
      expect(rawMerged, isNotNull);
      final List<dynamic> list = json.decode(rawMerged!);
      expect(list.length, equals(2));

      final localMap = list[0] as Map<String, dynamic>;
      expect(localMap['id'], equals('local_extra_id'));
      expect(localMap['createdAt'], equals('custom-local-timestamp-string'));
      expect(localMap['unknown_local_key'], equals('preserved_local_value'));
      expect(localMap['tags'], equals(['imaan', 'quran']));

      final importMap = list[1] as Map<String, dynamic>;
      expect(importMap['id'], equals('import_extra_id'));
      expect(importMap['createdAt'], equals('custom-import-non-iso-date'));
      expect(importMap['unknown_import_flag'], equals(1001));
      expect(importMap['metadata'], equals({'schema_subversion': 42}));

      final res2 = await BackupRestoreService.instance
          .restoreBackup(envelope, replaceMode: false)
          .timeout(const Duration(seconds: 5));
      expect(res2, isTrue);
      expect(prefs.getString('tadabbur_journal_entries_v1'), equals(rawMerged));
    });

    test('TESTONLY characterization: init partial state and later-save defect causes raw loss of wrong-typed entry and unknown fields on add and delete', () async {
      final prefs = await SharedPreferences.getInstance();
      final cleanup = setupFullPrefsSnapshot(prefs);
      addTearDown(() async {
        await cleanup();
        await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      });

      // 1. Seed last good live state
      await prefs.setString(
        'tadabbur_journal_entries_v1',
        json.encode([localItemA.toJson()]),
      );
      await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      expect(TadabburJournalService.instance.entries.length, equals(1));
      expect(TadabburJournalService.instance.entries.first.id, equals('local_item_a'));

      // 2. Prepare raw seed: valid first entry with unknown fields + wrong-typed later entry
      final rawValidFirstWithUnknowns = {
        'id': 'valid_first_id',
        'surahId': 1,
        'surahName': 'الفاتحة',
        'ayahNumber': 5,
        'ayahSnippet': '﴿إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ﴾',
        'faithMessage': 'إخلاص العبودية والاستعانة بالله',
        'practicalAction': 'تجديد النية قبل العمل',
        'derivedDua': 'اللهم أعني على ذكرك وشكرك',
        'createdAt': '2026-10-01T00:00:00.000',
        'unknown_meta_string': 'custom_metadata_value',
        'unknown_nested_map': {'sync_flag': true, 'revision': 42},
        'unknown_tags_list': ['imaan', 'quran'],
      };
      final rawWrongTypedLater = {
        'id': 'wrong_typed_later_id',
        'surahId': 'string_not_an_int', // wrong type -> causes TypeError in TadabburReflectionItem.fromJson
        'surahName': 'البقرة',
        'ayahNumber': 255,
        'ayahSnippet': '﴿اللَّهُ لَا إِلَٰهَ إِلَّا هُوَ الْحَيُّ الْقَيُّومُ﴾',
        'faithMessage': 'قيومية الله',
        'practicalAction': 'التوكل على الحي القيوم',
        'derivedDua': 'يا حي يا قيوم',
        'createdAt': '2026-10-02T00:00:00.000',
        'wrong_entry_extra': 'extra_value',
      };

      final rawMixedSeed = json.encode([
        rawValidFirstWithUnknowns,
        rawWrongTypedLater,
      ]);
      await prefs.setString('tadabbur_journal_entries_v1', rawMixedSeed);

      // Verify raw prefs holds both entries and all unknown fields initially
      final rawInitial = prefs.getString('tadabbur_journal_entries_v1');
      expect(rawInitial, equals(rawMixedSeed));
      final List<dynamic> initialDecoded = json.decode(rawInitial!);
      expect(initialDecoded.length, equals(2));
      expect((initialDecoded[0] as Map<String, dynamic>)['unknown_meta_string'], equals('custom_metadata_value'));
      expect((initialDecoded[1] as Map<String, dynamic>)['id'], equals('wrong_typed_later_id'));

      // 3. forceReload: characterizes init partial state defect
      await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));

      // Because _entries..clear()..addAll(list.map(...)) clears _entries and then iterates,
      // valid_first_id is added, then wrong_typed_later_id throws TypeError in fromJson.
      // The exception is caught by catch (_) {}, leaving _entries partially populated with only 1 item.
      expect(TadabburJournalService.instance.entries.length, equals(1),
          reason: 'Defect: init leaves partial in-memory state; subsequent entries are unparsed and missing');
      expect(TadabburJournalService.instance.entries.first.id, equals('valid_first_id'));

      // In raw storage, the unparsed wrong_typed_later_id still exists prior to any save operation
      expect(prefs.getString('tadabbur_journal_entries_v1'), equals(rawMixedSeed));

      // 4. Characterize later-save raw loss on addReflection:
      await TadabburJournalService.instance.addReflection(
        surahId: 112,
        surahName: 'الإخلاص',
        ayahNumber: 1,
        ayahSnippet: '﴿قُلْ هُوَ اللَّهُ أَحَدٌ﴾',
        faithMessage: 'توحيد الله الأحد',
        practicalAction: 'إخلاص العمل',
        derivedDua: 'اللهم إني أسألك التوحيد',
      ).timeout(const Duration(seconds: 5));

      final rawAfterAdd = prefs.getString('tadabbur_journal_entries_v1');
      expect(rawAfterAdd, isNotNull);
      final List<dynamic> listAfterAdd = json.decode(rawAfterAdd!);

      // Defect rawloss 1: wrong_typed_later_id was completely dropped / discarded from raw storage
      expect(listAfterAdd.any((e) => (e as Map<String, dynamic>)['id'] == 'wrong_typed_later_id'), isFalse,
          reason: 'Defect rawloss: unparsed wrong_typed_later_entry is permanently wiped from storage on addReflection');

      // Defect rawloss 2: unknown fields on valid_first_id were completely stripped / discarded
      final validFirstAfterAdd =
          listAfterAdd.firstWhere((e) => (e as Map<String, dynamic>)['id'] == 'valid_first_id') as Map<String, dynamic>;
      expect(validFirstAfterAdd.containsKey('unknown_meta_string'), isFalse,
          reason: 'Defect rawloss: unknown fields on valid entry stripped by TadabburReflectionItem.toJson()');
      expect(validFirstAfterAdd.containsKey('unknown_nested_map'), isFalse);
      expect(validFirstAfterAdd.containsKey('unknown_tags_list'), isFalse);

      // 5. Characterize later-save raw loss on deleteReflection:
      // Re-seed raw with mixed valid + wrong-typed + unknown fields
      await prefs.setString('tadabbur_journal_entries_v1', rawMixedSeed);
      await TadabburJournalService.instance.init(forceReload: true).timeout(const Duration(seconds: 5));
      expect(TadabburJournalService.instance.entries.length, equals(1));

      // Delete the valid entry from in-memory list
      await TadabburJournalService.instance.deleteReflection('valid_first_id').timeout(const Duration(seconds: 5));

      final rawAfterDelete = prefs.getString('tadabbur_journal_entries_v1');
      expect(rawAfterDelete, isNotNull);
      final List<dynamic> listAfterDelete = json.decode(rawAfterDelete!);

      // Defect rawloss 3: wrong_typed_later_id was wiped out completely when _saveEntries wrote the empty in-memory list
      expect(listAfterDelete, isEmpty,
          reason: 'Defect rawloss: wrong_typed_later_entry wiped from storage when deleteReflection saves empty in-memory list');
    });
  });
}
