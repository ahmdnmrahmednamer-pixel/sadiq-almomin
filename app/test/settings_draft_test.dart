import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/features/settings/models/settings_draft.dart';

void main() {
  test('stage and discard do not save or change live values', () async {
    var live = 1;
    var writes = 0;
    final draft = SettingsDraft();
    final setting = draft.add<int>(
        key: 'size',
        read: () => live,
        write: (value) async {
          writes++;
          live = value;
        });
    setting.stage(2);
    expect(setting.value, 2);
    expect(live, 1);
    expect(writes, 0);
    expect(draft.dirty, isTrue);
    draft.discard();
    expect(setting.value, 1);
    expect(draft.dirty, isFalse);
    expect(writes, 0);
    expect((await draft.apply()).success, isTrue);
    expect(writes, 0);
  });

  test('Apply saves only changed values and verifies readback', () async {
    var live = 1;
    var writes = 0;
    final draft = SettingsDraft();
    final value = draft.add<int>(
        key: 'size',
        read: () => live,
        write: (next) async {
          writes++;
          live = next;
        });
    draft.add<bool>(
        key: 'unchanged',
        read: () => true,
        write: (_) async => fail('unchanged value must not be saved'));
    value.stage(2);
    final result = await draft.apply();
    expect(result.success, isTrue);
    expect(result.appliedKeys, ['size']);
    expect(live, 2);
    expect(writes, 1);
    expect(draft.dirty, isFalse);
    await draft.apply();
    expect(writes, 1);
  });

  test('reverting a draft value clears its pending change', () {
    final draft = SettingsDraft();
    final value =
        draft.add<double>(key: 'speed', read: () => 1.1, write: (_) async {});
    expect(value.value, 1.1);
    value.stage(1.25);
    value.stage(1.1);
    expect(draft.pendingKeys, isEmpty);
  });

  test('external conflict blocks all writes, including earlier entries',
      () async {
    var first = false;
    var live = 1;
    final draft = SettingsDraft();
    draft
        .add<bool>(
            key: 'first',
            read: () => first,
            write: (value) async {
              first = value;
            })
        .stage(true);
    draft
        .add<int>(
            key: 'conflict',
            read: () => live,
            write: (value) async {
              live = value;
            })
        .stage(2);
    live = 3;
    final result = await draft.apply();
    expect(result.success, isFalse);
    expect(result.conflict, isTrue);
    expect(result.failedKey, 'conflict');
    expect(result.appliedKeys, isEmpty);
    expect(first, isFalse);
    expect(live, 3);
  });

  test('partial failure stays pending and retry does not repeat earlier saves',
      () async {
    var first = 1;
    var second = 1;
    var firstWrites = 0;
    var failSecond = true;
    final draft = SettingsDraft();
    draft
        .add<int>(
            key: 'first',
            read: () => first,
            write: (value) async {
              firstWrites++;
              first = value;
            })
        .stage(2);
    draft
        .add<int>(
            key: 'second',
            read: () => second,
            write: (value) async {
              if (failSecond) throw StateError('save failed');
              second = value;
            })
        .stage(2);
    final result = await draft.apply();
    expect(result.success, isFalse);
    expect(result.appliedKeys, ['first']);
    expect(result.failedKey, 'second');
    expect(draft.pendingKeys, ['second']);
    failSecond = false;
    expect((await draft.apply()).success, isTrue);
    expect(firstWrites, 1);
    expect(second, 2);
    expect(draft.dirty, isFalse);
  });

  test('a rejected setting never reports a successful Apply', () async {
    final draft = SettingsDraft();
    draft
        .add<bool>(key: 'permission', read: () => false, write: (_) async {})
        .stage(true);
    final result = await draft.apply();
    expect(result.success, isFalse);
    expect(result.failedKey, 'permission');
    expect(draft.dirty, isTrue);
    expect(draft.applying, isFalse);
  });
  test('a change arriving during Apply cannot overwrite a later setting',
      () async {
    var first = 1;
    var second = 1;
    final draft = SettingsDraft();
    draft
        .add<int>(
            key: 'first',
            read: () => first,
            write: (value) async {
              first = value;
              second = 3;
            })
        .stage(2);
    draft
        .add<int>(
            key: 'second',
            read: () => second,
            write: (value) async {
              second = value;
            })
        .stage(2);
    final result = await draft.apply();
    expect(result.conflict, isTrue);
    expect(result.appliedKeys, ['first']);
    expect(result.failedKey, 'second');
    expect(second, 3);
  });

  test('edits and overlapping Apply are rejected while saving', () async {
    var live = 1;
    final completer = Completer<void>();
    final draft = SettingsDraft();
    final setting = draft.add<int>(
        key: 'size',
        read: () => live,
        write: (value) async {
          await completer.future;
          live = value;
        });
    setting.stage(2);
    final save = draft.apply();
    expect(draft.applying, isTrue);
    expect(() => setting.stage(3), throwsStateError);
    expect(() => draft.discard(), throwsStateError);
    await expectLater(draft.apply(), throwsStateError);
    completer.complete();
    expect((await save).success, isTrue);
    expect(live, 2);
  });

  test('a retry accepts an already-saved value without repeating its writer',
      () async {
    var live = 1;
    var writes = 0;
    final draft = SettingsDraft();
    draft
        .add<int>(
            key: 'size',
            read: () => live,
            write: (value) async {
              writes++;
              live = value;
              throw StateError('failed after persistence');
            })
        .stage(2);
    expect((await draft.apply()).success, isFalse);
    expect(draft.dirty, isTrue);
    expect((await draft.apply()).success, isTrue);
    expect(writes, 1);
  });

  test('failed persistent readback stays pending even after in-memory change',
      () async {
    var live = 1;
    var persisted = 1;
    var backendWorks = false;
    var writes = 0;
    final draft = SettingsDraft();
    draft
        .add<int>(
            key: 'size',
            read: () => live,
            write: (value) async {
              live = value;
              writes++;
              if (backendWorks) persisted = value;
            },
            verify: (value) async => persisted == value)
        .stage(2);
    expect((await draft.apply()).success, isFalse);
    expect(draft.dirty, isTrue);
    backendWorks = true;
    expect((await draft.apply()).success, isTrue);
    expect(writes, 2);
    expect(persisted, 2);
  });
}
