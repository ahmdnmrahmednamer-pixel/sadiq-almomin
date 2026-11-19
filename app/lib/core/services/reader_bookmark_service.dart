import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// A reader location is explicit about its format. An online page number must
/// never be mistaken for an EPUB spine index, even for the same Shamela book.
class ReaderBookmark {
  final String id;
  final String documentId;
  final String locationKind;
  final int page;
  final double scrollOffset;
  final String label;
  final DateTime createdAt;

  const ReaderBookmark({required this.id, required this.documentId,
    required this.locationKind, required this.page, required this.scrollOffset,
    required this.label, required this.createdAt});

  Map<String, Object> toJson() => {'id':id,'documentId':documentId,
    'locationKind':locationKind,'page':page,'scrollOffset':scrollOffset,
    'label':label,'createdAt':createdAt.toUtc().toIso8601String()};

  static ReaderBookmark? fromJson(dynamic value) {
    if (value is! Map) return null;
    try {
      final offset = (value['scrollOffset'] as num).toDouble();
      final page = value['page'] as int;
      final id = value['id'] as String;
      final doc = value['documentId'] as String;
      final kind = value['locationKind'] as String;
      if (id.isEmpty || doc.isEmpty || kind.isEmpty || page < 0 || !offset.isFinite || offset < 0) return null;
      return ReaderBookmark(id:id,documentId:doc,locationKind:kind,page:page,
        scrollOffset:offset,label:value['label'] as String,
        createdAt:DateTime.parse(value['createdAt'] as String));
    } catch (_) { return null; }
  }
}

/// Multiple named marks per document, separate from the last-read position.
class ReaderBookmarkService {
  static const _key = 'reader_bookmarks_v1';
  static Future<void>? _tail;

  Future<List<ReaderBookmark>> list(String documentId, String locationKind) async {
    final prefs = await SharedPreferences.getInstance();
    final all = _decode(prefs.getString(_key));
    return all.where((b) => b.documentId == documentId && b.locationKind == locationKind).toList()
      ..sort((a,b) => a.createdAt.compareTo(b.createdAt));
  }

  List<ReaderBookmark> _decode(String? raw) {
    if (raw == null) return [];
    final value = jsonDecode(raw);
    if (value is! List) throw const FormatException('Invalid bookmark storage');
    final marks = value.map(ReaderBookmark.fromJson).toList();
    if (marks.any((b) => b == null)) throw const FormatException('Invalid bookmark entry');
    return marks.cast<ReaderBookmark>();
  }

  Future<void> _mutate(void Function(List<ReaderBookmark>) change) {
    final next = (_tail ?? Future<void>.value()).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final all = _decode(prefs.getString(_key));
      change(all);
      final saved = await prefs.setString(_key,jsonEncode(all.map((b)=>b.toJson()).toList()));
      if (!saved) throw StateError('Unable to save reader bookmarks');
    });
    late final Future<void> settled;
    void clearTail() { if (identical(_tail, settled)) _tail = null; }
    settled = next.then((_) => clearTail(), onError: (Object _, StackTrace __) => clearTail());
    _tail = settled;
    return next;
  }

  Future<ReaderBookmark> add({required String documentId,required String locationKind,
    required int page,required double scrollOffset,required String label}) async {
    if (documentId.isEmpty || locationKind.isEmpty || page < 0 || !scrollOffset.isFinite || scrollOffset < 0) {
      throw ArgumentError('Invalid document location');
    }
    final now = DateTime.now().toUtc();
    late ReaderBookmark mark;
    await _mutate((all) {
      var suffix = 0;
      var id = '${now.microsecondsSinceEpoch}';
      while (all.any((b)=>b.id == id)) { id = '${now.microsecondsSinceEpoch}-${++suffix}'; }
      mark = ReaderBookmark(id:id,documentId:documentId,locationKind:locationKind,
        page:page,scrollOffset:scrollOffset,label:label.trim(),createdAt:now);
      all.add(mark);
    });
    return mark;
  }

  Future<void> remove(ReaderBookmark bookmark) => _mutate((all) => all.removeWhere((b) =>
    b.id == bookmark.id && b.documentId == bookmark.documentId && b.locationKind == bookmark.locationKind));
}
