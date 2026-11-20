import 'package:flutter/foundation.dart';

/// A settings session never calls a persistent writer until Apply is requested.
class SettingsDraft extends ChangeNotifier {
  final Map<String, _DraftEntry> _entries = {};
  bool _applying = false;
  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  bool get applying => _applying;
  bool get dirty => _entries.values.any((entry) => entry.dirty);
  List<String> get pendingKeys => _entries.entries
      .where((entry) => entry.value.dirty)
      .map((entry) => entry.key)
      .toList(growable: false);

  DraftSetting<T> add<T>({
    required String key,
    required T Function() read,
    required Future<void> Function(T) write,
    Future<bool> Function(T)? verify,
  }) {
    if (_entries.containsKey(key)) {
      throw ArgumentError.value(key, 'key', 'Duplicate setting');
    }
    final entry = DraftSetting<T>._(this, read, write, verify);
    _entries[key] = entry;
    return entry;
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// Discarding a session changes only its in-memory values.
  void discard() {
    if (_applying) throw StateError('Apply is in progress');
    for (final entry in _entries.values) {
      entry.discard();
    }
    _changed();
  }

  /// A failed apply can have saved earlier entries. The result names them.
  /// Pending entries stay available for retry instead of reporting success.
  Future<DraftApplyResult> apply() async {
    if (_applying) throw StateError('Apply is already in progress');
    _applying = true;
    _changed();
    final applied = <String>[];
    try {
      // Check all values before the first write, avoiding stale overwrites.
      for (final pair in _entries.entries.where((pair) => pair.value.dirty)) {
        final entry = pair.value;
        if (entry.conflict) {
          return DraftApplyResult(applied, failedKey: pair.key, conflict: true);
        }
      }
      for (final pair in _entries.entries) {
        final entry = pair.value;
        if (!entry.dirty) continue;
        if (entry.conflict) {
          return DraftApplyResult(applied, failedKey: pair.key, conflict: true);
        }
        try {
          // A previous failed call or another screen may already have saved it.
          if (!await entry.save()) {
            return DraftApplyResult(applied, failedKey: pair.key);
          }
          applied.add(pair.key);
        } catch (_) {
          return DraftApplyResult(applied, failedKey: pair.key);
        }
      }
      return DraftApplyResult(applied);
    } finally {
      _applying = false;
      _changed();
    }
  }
}

abstract class _DraftEntry {
  bool get dirty;
  bool get conflict;
  void discard();
  Future<bool> save();
}

class DraftSetting<T> implements _DraftEntry {
  DraftSetting._(this._owner, this._read, this._write, this._verify) {
    _baseline = _read();
    _value = _baseline;
  }
  final SettingsDraft _owner;
  final T Function() _read;
  final Future<void> Function(T) _write;
  final Future<bool> Function(T)? _verify;
  late T _baseline;
  late T _value;
  T get value => _value;
  @override
  bool get dirty => _value != _baseline;
  @override
  bool get conflict {
    final current = _read();
    return current != _baseline && current != _value;
  }

  @override
  void discard() {
    _value = _baseline;
  }

  @override
  Future<bool> save() async {
    if (_read() != _value || (_verify != null && !await _verify!(_value))) {
      await _write(_value);
    }
    if (_read() != _value || (_verify != null && !await _verify!(_value))) {
      return false;
    }
    _baseline = _value;
    return true;
  }

  void stage(T value) {
    if (_owner.applying) throw StateError('Cannot edit during Apply');
    if (_value == value) return;
    _value = value;
    _owner._changed();
  }
}

class DraftApplyResult {
  DraftApplyResult(List<String> applied,
      {this.failedKey, this.conflict = false})
      : appliedKeys = List.unmodifiable(applied);
  final List<String> appliedKeys;
  final String? failedKey;
  final bool conflict;
  bool get success => failedKey == null;
}
