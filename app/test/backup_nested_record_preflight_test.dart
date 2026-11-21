import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:almomin/core/services/backup_restore_service.dart';
import 'package:almomin/core/models/ayah_note.dart';
import 'package:almomin/core/models/memorization_item.dart';

class PreflightStore extends InMemorySharedPreferencesStore {
  PreflightStore()
      : super.withData({
          'flutter.bookmarks': <String>['1:1']
        });
  int writes = 0;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    writes++;
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = BackupRestoreService.instance;
  late PreflightStore store;
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'bookmarks': <String>['1:1']
    });
    store = PreflightStore();
    SharedPreferencesStorePlatform.instance = store;
  });
  Map<String, dynamic> envelope(Map<String, dynamic> data) => {
        'app': 'AlMomin',
        'schema_version': 1,
        'data': data,
        'checksum': BackupRestoreService.calculateChecksum(
            BackupRestoreService.canonicalJsonEncode(data)),
      };
  final wrongNoteFields = {
    'id': 42,
    'surahId': 'invalid',
    'surahName': 42,
    'ayahNumber': 'invalid',
    'ayahText': 42,
    'noteText': 42,
    'createdAt': 42,
    'updatedAt': 42,
    'pageNumber': 'invalid',
  };
  final wrongMemFields = {
    'id': 42,
    'surah_id': 'invalid',
    'ayah_number': 'invalid',
    'surah_name': 42,
    'leitner_box': 'invalid',
    'last_reviewed_at': 42,
    'next_review_due': 42,
    'times_reviewed': 'invalid',
    'times_correct': 'invalid',
  };
  for (final section in ['ayah_notes', 'memorization_items']) {
    final fields = section == 'ayah_notes' ? wrongNoteFields : wrongMemFields;
    final badRows = <String, dynamic>{
      'non-map row': 42,
      'null row': null,
      for (final e in fields.entries) e.key: {e.key: e.value},
    };
    for (final bad in badRows.entries) {
      test(
          '$section ${bad.key} refuses preview and both restore modes before writes',
          () async {
        final backup = envelope({
          'bookmarks': ['2:255'],
          section: [bad.value]
        });
        expect(service.validateBackup(jsonEncode(backup)).isValid, false);
        for (final replace in [true, false]) {
          expect(
              await service.restoreBackup(backup, replaceMode: replace), false);
          expect(store.writes, 0);
          final prefs = await SharedPreferences.getInstance();
          await prefs.reload();
          expect(prefs.getStringList('bookmarks'), ['1:1']);
        }
      });
    }
  }
  test(
      'canonical model exports, optional defaults and unknown fields remain valid',
      () {
    final data = {
      'ayah_notes': [
        AyahNote(
                id: '2_255',
                surahId: 2,
                surahName: 'البقرة',
                ayahNumber: 255,
                ayahText: 'النص',
                noteText: 'ملاحظة',
                createdAt: DateTime(2026, 11, 21),
                updatedAt: DateTime(2026, 11, 21),
                pageNumber: 42)
            .toJson(),
        <String, dynamic>{},
        {
          'id': null,
          'future_extension': {'keep': true}
        },
      ],
      'memorization_items': [
        MemorizationItem(
                id: '2:255',
                surahId: 2,
                ayahNumber: 255,
                surahName: 'البقرة',
                leitnerBox: 2,
                lastReviewedAt: DateTime(2026, 11, 21),
                nextReviewDue: DateTime(2026, 11, 22),
                timesReviewed: 2,
                timesCorrect: 1)
            .toJson(),
        <String, dynamic>{},
        {
          'id': null,
          'future_extension': {'keep': true}
        },
      ],
    };
    final result = service.validateBackup(jsonEncode(envelope(data)));
    expect(result.isValid, true);
    expect(result.notesCount, 3);
    expect(result.memorizationCount, 3);
    expect(result.rawData!['data'], data);
  });
  test('legacy model-compatible numeric and date fallbacks are not changed',
      () {
    final backup = envelope({
      'ayah_notes': [
        {'createdAt': 'legacy date', 'updatedAt': null}
      ],
      'memorization_items': [
        {
          'surah_id': 2.0,
          'ayah_number': 255.0,
          'leitner_box': 3.0,
          'last_reviewed_at': 'legacy date',
          'last_rating': 'unknown'
        }
      ],
    });
    expect(service.validateBackup(jsonEncode(backup)).isValid, true);
  });
}
