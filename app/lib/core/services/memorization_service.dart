import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/memorization_item.dart';
import '../utils/serial_task_queue.dart';

class MemorizationStorageException implements Exception {
  final String message;
  const MemorizationStorageException(this.message);
  @override
  String toString() => message;
}

/// Persistent memorization reviews. Live state is published only after saving.
class MemorizationService extends ChangeNotifier {
  static final MemorizationService instance = MemorizationService._internal();
  MemorizationService._internal();
  static const String _storageKey = 'memorization_items_v1';
  final Map<String, MemorizationItem> _items = {};
  Map<String, Map<String, dynamic>> _rawItems = {};
  bool _isInitialized = false;
  bool _historyReadable = true;
  String? _storageError;
  String? get storageError => _storageError;
  static const _readError =
      'تعذرت قراءة سجل الحفظ. لم نغير البيانات المحفوظة. استعد نسخة سليمة أو أعد فتح التطبيق قبل التسجيل.';
  static const _writeError =
      'لم يُحفظ تعديل سجل الحفظ. بقي السجل السابق كما كان. حاول مرة أخرى.';
  final SerialTaskQueue _operations = SerialTaskQueue();

  Future<T> _serialize<T>(Future<T> Function() action) => _operations.run(action);

  bool get isInitialized => _isInitialized;
  int get totalTrackedAyahs => _items.length;
  int get totalMasteredCount =>
      _items.values.where((i) => i.leitnerBox >= 3).length;
  int get dueReviewsCount => _items.values.where((i) => i.isDue).length;

  Future<void> init({bool forceReload = false}) =>
      _serialize(() => _load(forceReload: forceReload));

  Future<void> _load({bool forceReload = false}) async {
    if (_isInitialized && !forceReload) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (forceReload) await prefs.reload();
      final raw = prefs.getString(_storageKey);
      final decoded =
          raw == null || raw.isEmpty ? <dynamic>[] : json.decode(raw);
      if (decoded is! List) throw const FormatException();
      final parsed = <String, MemorizationItem>{};
      final rawItems = <String, Map<String, dynamic>>{};
      for (final row in decoded) {
        if (row is! Map<String, dynamic>) throw const FormatException();
        final item = MemorizationItem.fromJson(row);
        if (parsed.containsKey(item.id)) throw const FormatException();
        parsed[item.id] = item;
        rawItems[item.id] = Map<String, dynamic>.from(row);
      }
      _items
        ..clear()
        ..addAll(parsed);
      _rawItems = rawItems;
      _historyReadable = true;
      _storageError = null;
    } catch (_) {
      _historyReadable = false;
      _storageError = _readError;
    }
    _isInitialized = true;
    notifyListeners();
  }

  bool hasItem(int surahId, int ayahNumber) =>
      _items.containsKey(MemorizationItem.generateId(surahId, ayahNumber));
  MemorizationItem? getItem(int surahId, int ayahNumber) =>
      _items[MemorizationItem.generateId(surahId, ayahNumber)];
  List<MemorizationItem> getItemsForSurah(int surahId) =>
      _items.values.where((i) => i.surahId == surahId).toList();
  List<MemorizationItem> getDueItems() =>
      _items.values.where((i) => i.isDue).toList();

  void _requireReadable() {
    if (!_historyReadable) throw const MemorizationStorageException(_readError);
  }

  Future<void> _save(
      Map<String, MemorizationItem> next, Map<String, Map<String, dynamic>> raw,
      {bool remove = false}) async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      final saved = remove
          ? await prefs.remove(_storageKey)
          : await prefs.setString(
              _storageKey, json.encode(raw.values.toList()));
      if (!saved) throw StateError('Write rejected');
    } catch (_) {
      try {
        await prefs?.reload();
      } catch (_) {}
      _storageError = _writeError;
      notifyListeners();
      throw const MemorizationStorageException(_writeError);
    }
    _items
      ..clear()
      ..addAll(next);
    _rawItems = raw;
    _historyReadable = true;
    _storageError = null;
    notifyListeners();
  }

  Future<MemorizationItem> recordReview({
    required int surahId,
    required int ayahNumber,
    required String surahName,
    required MemorizationRating rating,
  }) =>
      _serialize(() async {
        await _load();
        _requireReadable();
        final id = MemorizationItem.generateId(surahId, ayahNumber);
        final existing = _items[id] ??
            MemorizationItem.createInitial(
                surahId: surahId, ayahNumber: ayahNumber, surahName: surahName);
        final updated = existing.recordReview(rating);
        final next = Map<String, MemorizationItem>.from(_items)..[id] = updated;
        final raw = Map<String, Map<String, dynamic>>.from(_rawItems)
          ..[id] = {...?_rawItems[id], ...updated.toJson()};
        await _save(next, raw);
        return updated;
      });

  Future<bool> deleteItem(int surahId, int ayahNumber) => _serialize(() async {
        await _load();
        _requireReadable();
        final id = MemorizationItem.generateId(surahId, ayahNumber);
        if (!_items.containsKey(id)) return false;
        final next = Map<String, MemorizationItem>.from(_items)..remove(id);
        final raw = Map<String, Map<String, dynamic>>.from(_rawItems)
          ..remove(id);
        await _save(next, raw);
        return true;
      });

  List<Map<String, dynamic>> exportData() {
    _requireReadable();
    return _rawItems.values.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<int> importData(List<dynamic> list, {bool merge = true}) =>
      _serialize(() async {
        await _load();
        if (merge) _requireReadable();
        final next = merge
            ? Map<String, MemorizationItem>.from(_items)
            : <String, MemorizationItem>{};
        final raw = merge
            ? Map<String, Map<String, dynamic>>.from(_rawItems)
            : <String, Map<String, dynamic>>{};
        var count = 0;
        for (final row in list) {
          if (row is! Map<String, dynamic>)
            throw const FormatException('Invalid memorization record');
          final item = MemorizationItem.fromJson(row);
          if (!merge ||
              !next.containsKey(item.id) ||
              item.lastReviewedAt.isAfter(next[item.id]!.lastReviewedAt)) {
            next[item.id] = item;
            raw[item.id] = {...?raw[item.id], ...row};
            count++;
          }
        }
        await _save(next, raw);
        return count;
      });

  Future<void> clearAll() => _serialize(() async {
        await _load();
        _requireReadable();
        await _save({}, {}, remove: true);
      });
}
