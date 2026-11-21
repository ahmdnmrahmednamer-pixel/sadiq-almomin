import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/backup_restore_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Map<String, dynamic> envelope(Map<String, dynamic> data) => {
    'app': 'AlMomin',
    'schema_version': 1,
    'checksum': BackupRestoreService.calculateChecksum(
      BackupRestoreService.canonicalJsonEncode(data)),
    'data': data,
  };

  test('malformed section is rejected before replacing existing bookmarks', () async {
    SharedPreferences.setMockInitialValues({'bookmarks': <String>['1:1']});
    final backup = envelope({'bookmarks': ['2:255'], 'settings': ['invalid']});
    final accepted = BackupRestoreService.instance.validateBackup(jsonEncode(backup));
    expect(await BackupRestoreService.instance.restoreBackup(backup), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('bookmarks'), ['1:1']);
    expect(accepted.isValid, isFalse);
  });

  test('non-string bookmark entries are not accepted as a valid backup', () {
    final backup = envelope({'bookmarks': [42]});
    expect(BackupRestoreService.instance.validateBackup(jsonEncode(backup)).isValid, isFalse);
  });
  for (final section in <String>[
    'settings', 'reading_position', 'khatma', 'adhkar', 'location',
    'prayer_tracker', 'zakat_calculation', 'daily_wird_records',
    'fajr_qiyam_alarms', 'scholars_library', 'extended_features',
    'ayah_notes', 'memorization_items', 'hadith_favorites',
    'egyptian_heritage_favorites', 'fiqh_library_favorites',
  ]) {
    test('$section malformed container is refused without writes in both modes', () async {
      for (final replace in [true, false]) {
        SharedPreferences.setMockInitialValues({'bookmarks': <String>['1:1']});
        final backup = envelope({'bookmarks': ['2:255'], section: 42});
        expect(BackupRestoreService.instance.validateBackup(jsonEncode(backup)).isValid, isFalse);
        expect(await BackupRestoreService.instance.restoreBackup(backup, replaceMode: replace), isFalse);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getStringList('bookmarks'), ['1:1']);
        expect(prefs.getKeys(), {'bookmarks'});
      }
    });
  }

  test('legacy missing and null sections remain valid', () {
    expect(BackupRestoreService.instance.validateBackup(jsonEncode(envelope({}))).isValid, isTrue);
    expect(BackupRestoreService.instance.validateBackup(jsonEncode(envelope({
      'settings': null, 'bookmarks': null, 'ayah_notes': null,
    }))).isValid, isTrue);
  });

}
