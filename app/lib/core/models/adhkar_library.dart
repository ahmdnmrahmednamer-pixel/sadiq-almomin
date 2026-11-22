import 'dart:convert';

/// Parser for the pinned text library. No network, playback or preference writes.
class ImportedAdhkarLibrary {
  static const sourceNamespace = 'rn0x_adhkar_json';
  static const sourceRepository = 'https://github.com/rn0x/Adhkar-json';
  static const sourceCommit = '93dc3fc489e4291da8816265920b3cb7e2c3b569';
  static const upstreamSha256 =
      'ee0df147cc9fdcbc8bed542703ba2d43f70329baa4d8ee7a99adf7929112a65f';
  static const bundledSha256 =
      '338c931c8cea5bf34936acb0ecedf1ebfbd8868171236427ae8873d74655a7cf';

  final List<ImportedAdhkarCategory> categories;

  const ImportedAdhkarLibrary._(this.categories);

  factory ImportedAdhkarLibrary.parse(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! List || decoded.isEmpty) {
      throw const FormatException('A nonempty category list is required');
    }
    final categoryIds = <int>{};
    final categories = <ImportedAdhkarCategory>[];
    for (final rawCategory in decoded) {
      final category = _object(rawCategory);
      final categoryId = _positiveInt(category['id']);
      if (!categoryIds.add(categoryId)) {
        throw const FormatException('Duplicate category ID');
      }
      final rawItems = category['array'];
      if (rawItems is! List || rawItems.isEmpty) {
        throw const FormatException('A nonempty item list is required');
      }
      final itemIds = <int>{};
      final items = <ImportedDhikrItem>[];
      for (final rawItem in rawItems) {
        final item = _object(rawItem);
        final itemId = _positiveInt(item['id']);
        if (!itemIds.add(itemId)) {
          throw const FormatException('Duplicate item ID within category');
        }
        items.add(
          ImportedDhikrItem._(
            categoryId: categoryId,
            sourceItemId: itemId,
            text: _text(item['text']),
            repeatCount: _positiveInt(item['count']),
            audioRelativePath: _audioPath(item['audio']),
          ),
        );
      }
      categories.add(
        ImportedAdhkarCategory._(
          sourceCategoryId: categoryId,
          title: _text(category['category']),
          audioRelativePath: _audioPath(category['audio']),
          items: List.unmodifiable(items),
        ),
      );
    }
    return ImportedAdhkarLibrary._(List.unmodifiable(categories));
  }

  static Map<String, dynamic> _object(dynamic value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('An object is required');
    }
    return value;
  }

  static int _positiveInt(dynamic value) {
    if (value is! int || value <= 0) {
      throw const FormatException('A positive integer is required');
    }
    return value;
  }

  static String _text(dynamic value) {
    if (value is! String || value.trim().isEmpty) {
      throw const FormatException('Nonempty text is required');
    }
    // Preserve the source's wording and whitespace. Validation is not editing.
    return value;
  }

  static final _allowedAudioPath = RegExp(r'^/audio/[A-Za-z0-9_-]+\.mp3$');

  static String _audioPath(dynamic value) {
    if (value is! String || !_allowedAudioPath.hasMatch(value)) {
      throw const FormatException('A local source audio path is required');
    }
    // No remote location is opened here, and no recording is marked reviewed.
    return value;
  }
}

class ImportedAdhkarCategory {
  final int sourceCategoryId;
  final String title;
  final String audioRelativePath;
  final List<ImportedDhikrItem> items;

  const ImportedAdhkarCategory._({
    required this.sourceCategoryId,
    required this.title,
    required this.audioRelativePath,
    required this.items,
  });
}

class ImportedDhikrItem {
  final int categoryId;
  final int sourceItemId;
  final String text;
  final int repeatCount;
  final String audioRelativePath;

  const ImportedDhikrItem._({
    required this.categoryId,
    required this.sourceItemId,
    required this.text,
    required this.repeatCount,
    required this.audioRelativePath,
  });

  /// Source item IDs repeat across categories and must never be global keys.
  String get progressKey =>
      '${ImportedAdhkarLibrary.sourceNamespace}:$categoryId:$sourceItemId';
}
