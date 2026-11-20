import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:almomin/core/services/ayah_notes_service.dart';

class NotesTestStore extends SharedPreferencesStorePlatform {
  final Map<String, Object> values = {};
  bool fail = false, throwWrite = false;
  Completer<void>? gate;
  int writes = 0;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    writes++;
    final wait = gate;
    gate = null;
    if (wait != null) await wait.future;
    if (throwWrite) throw PlatformException(code: 'synthetic-storage-failure');
    if (fail) return false;
    values[key] = value;
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => Map.of(values);
  @override
  Future<bool> remove(String key) async => values.remove(key) != null;
  @override
  Future<bool> clear() async {
    values.clear();
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = AyahNotesService.instance;
  late NotesTestStore store;
  Future<bool> save(String text, {int ayah = 1}) => service.saveNote(
      surahId: 1,
      surahName: 'اختبار',
      ayahNumber: ayah,
      ayahText: 'نص اختباري',
      noteText: text);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = NotesTestStore();
    SharedPreferencesStorePlatform.instance = store;
    await service.clearAllNotes();
    await service.init(forceReload: true);
  });
  for (final throwWrite in [false, true]) {
    test(
        'failed new write preserves memory and reports false, throwing=$throwWrite',
        () async {
      store.fail = true;
      store.throwWrite = throwWrite;
      expect(await save('draft'), isFalse);
      expect(service.hasNote(1, 1), isFalse);
    });
    test('failed update preserves prior note, throwing=$throwWrite', () async {
      expect(await save('original'), isTrue);
      store.fail = true;
      store.throwWrite = throwWrite;
      expect(await save('changed'), isFalse);
      expect(service.getNote(1, 1)!.noteText, 'original');
    });
    test('failed delete preserves note, throwing=$throwWrite', () async {
      await save('original');
      store.fail = true;
      store.throwWrite = throwWrite;
      expect(await service.deleteNote(1, 1), isFalse);
      expect(service.getNote(1, 1)!.noteText, 'original');
    });
  }
  test('retry succeeds after rejected write', () async {
    store.fail = true;
    expect(await save('draft'), isFalse);
    store.fail = false;
    expect(await save('draft'), isTrue);
    expect(service.getNote(1, 1)!.noteText, 'draft');
  });
  test('failed clear and restore surface failure without losing memory',
      () async {
    await save('original');
    store.fail = true;
    await expectLater(service.clearAllNotes(), throwsA(anything));
    expect(service.hasNote(1, 1), isTrue);
    await expectLater(
        service.restoreNotesList([], replace: true), throwsA(anything));
    expect(service.hasNote(1, 1), isTrue);
  });
  test('writes publish only after storage and serialize concurrent operations',
      () async {
    final gate = Completer<void>();
    store.gate = gate;
    final first = save('first');
    await Future<void>.delayed(Duration.zero);
    expect(service.hasNote(1, 1), isFalse);
    final second = save('second', ayah: 2);
    gate.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    final persisted =
        jsonDecode(store.values['flutter.user_ayah_notes_v1'] as String)
            as List;
    expect(persisted.length, 2);
    expect(service.notesCount, 2);
  });
  test('failed queued operation does not poison later save', () async {
    store.fail = true;
    expect(await save('rejected'), isFalse);
    store.fail = false;
    expect(await save('retained', ayah: 2), isTrue);
    expect(service.hasNote(1, 1), isFalse);
    expect(service.hasNote(1, 2), isTrue);
  });
}
