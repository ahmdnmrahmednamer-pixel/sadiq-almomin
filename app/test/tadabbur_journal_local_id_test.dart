import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/journal_merge_util.dart';
import 'package:almomin/core/services/tadabbur_journal_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('deterministic local entry ID allocation', () {
    const base = 'tadabbur_1795320000000';
    test('keeps the existing timestamp format when unoccupied', () {
      expect(JournalMergeUtil.allocateLocalEntryId(base, []), base);
    });
    test('same timestamp allocates one hundred distinct IDs', () {
      final occupied = <String>[];
      for (var i = 0; i < 100; i++) {
        occupied.add(JournalMergeUtil.allocateLocalEntryId(base, occupied));
      }
      expect(occupied.toSet(), hasLength(100));
      expect(occupied.first, base);
      expect(occupied[1], '$base-2');
      expect(occupied.last, '$base-100');
    });
    test('skips restored base and occupied numeric suffixes', () {
      expect(
          JournalMergeUtil.allocateLocalEntryId(
              base, [base, '$base-2', '$base-3']),
          '$base-4');
    });
    test('uses the first free suffix without renaming later occupants', () {
      final occupied = [base, '$base-3', '$base-5'];
      expect(JournalMergeUtil.allocateLocalEntryId(base, occupied), '$base-2');
      expect(occupied, [base, '$base-3', '$base-5']);
    });
    test('does not treat other timestamp prefixes as collisions', () {
      expect(
          JournalMergeUtil.allocateLocalEntryId(
              base, ['${base}0', '$base-extra']),
          base);
    });
    test('preserves duplicate legacy IDs and source list ordering', () {
      final occupied = ['seed_1', base, base, '$base-2', 'restored_abc'];
      final original = List<String>.of(occupied);
      expect(JournalMergeUtil.allocateLocalEntryId(base, occupied), '$base-3');
      expect(occupied, original);
    });
    test('clock rollback cannot reuse a still-occupied timestamp ID', () {
      final occupied = [base, 'tadabbur_1795320000001'];
      expect(JournalMergeUtil.allocateLocalEntryId(base, occupied), '$base-2');
    });
    test('handles long occupied suffix chains and lazy iterables', () {
      final occupied = [base, for (var i = 2; i <= 10000; i++) '$base-$i'];
      expect(
          JournalMergeUtil.allocateLocalEntryId(base, occupied.map((id) => id)),
          '$base-10001');
    });
  });
  Future<JournalOperationResult> add(int index) =>
      TadabburJournalService.instance.addReflection(
        surahId: 1,
        surahName: 'probe',
        ayahNumber: 1,
        ayahSnippet: 'probe',
        faithMessage: 'reflection-$index',
        practicalAction: 'probe',
        derivedDua: 'probe',
      );
  test(
      'queued additions keep distinct persisted IDs and delete only one new note',
      () async {
    SharedPreferences.setMockInitialValues({
      'tadabbur_journal_entries_v1': '[]',
    });
    final service = TadabburJournalService.instance;
    await service.init(forceReload: true);
    final results = await Future.wait(List.generate(100, add));
    expect(results.every((r) => r.status == JournalOperationStatus.persisted),
        isTrue);
    expect(service.entries, hasLength(100));
    expect(service.entries.map((entry) => entry.id).toSet(), hasLength(100));
    expect(service.entries.map((entry) => entry.faithMessage).toSet(),
        {for (var i = 0; i < 100; i++) 'reflection-$i'});
    final prefs = await SharedPreferences.getInstance();
    final raw = json.decode(prefs.getString('tadabbur_journal_entries_v1')!)
        as List<dynamic>;
    expect(raw.map((entry) => entry['id']).toSet(), hasLength(100));
    final removed = service.entries.first.id;
    final survivors =
        service.entries.skip(1).map((entry) => entry.toJson()).toList();
    expect((await service.deleteReflection(removed)).status,
        JournalOperationStatus.persisted);
    expect(service.entries.map((entry) => entry.toJson()).toList(), survivors);
    await service.init(forceReload: true);
    expect(service.entries.map((entry) => entry.toJson()).toList(), survivors);
  });
  test('adding does not silently migrate already-persisted duplicate IDs',
      () async {
    final now = DateTime.utc(2026, 11, 20);
    final originals = [
      for (var i = 0; i < 2; i++)
        TadabburReflectionItem(
          id: 'legacy_duplicate',
          surahId: 1,
          surahName: 'probe',
          ayahNumber: 1,
          ayahSnippet: 'probe',
          faithMessage: 'legacy-$i',
          practicalAction: 'probe',
          derivedDua: 'probe',
          createdAt: now,
        ),
    ];
    SharedPreferences.setMockInitialValues({
      'tadabbur_journal_entries_v1':
          json.encode(originals.map((entry) => entry.toJson()).toList()),
    });
    final service = TadabburJournalService.instance;
    await service.init(forceReload: true);
    final before = service.entries.map((entry) => entry.toJson()).toList();
    expect((await add(2)).status, JournalOperationStatus.persisted);
    expect(service.entries.skip(1).map((entry) => entry.toJson()).toList(),
        before);
    expect(service.entries.skip(1).map((entry) => entry.id),
        ['legacy_duplicate', 'legacy_duplicate']);
    expect(service.entries.first.id, isNot('legacy_duplicate'));
  });
}
