import 'dart:convert';

/// Pure utility for canonical encoding, checksum calculation, safe decoding,
/// and deterministic merge of Tadabbur Journal entries (relocated from PR 21).
class JournalMergeUtil {
  /// 64-bit FNV-1a checksum calculation
  static String calculateChecksum(String data) {
    BigInt hash = BigInt.parse('cbf29ce484222325', radix: 16);
    final BigInt fnvPrime = BigInt.parse('100000001b3', radix: 16);
    final BigInt mask64 = BigInt.parse('ffffffffffffffff', radix: 16);

    final bytes = utf8.encode(data);
    for (final b in bytes) {
      hash = (hash ^ BigInt.from(b)) & mask64;
      hash = (hash * fnvPrime) & mask64;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  /// Recursively sorts all Map keys alphabetically so checksums and
  /// canonical equality never fail due to JSON key reordering.
  static String canonicalJsonEncode(dynamic value) {
    if (value is Map) {
      final sortedKeys = value.keys.map((k) => k.toString()).toList()..sort();
      final Map<String, dynamic> sortedMap = {};
      for (final k in sortedKeys) {
        sortedMap[k] = _canonicalizeValue(value[k]);
      }
      return json.encode(sortedMap);
    }
    return json.encode(_canonicalizeValue(value));
  }

  static dynamic _canonicalizeValue(dynamic value) {
    if (value is Map) {
      final sortedKeys = value.keys.map((k) => k.toString()).toList()..sort();
      final Map<String, dynamic> sortedMap = {};
      for (final k in sortedKeys) {
        sortedMap[k] = _canonicalizeValue(value[k]);
      }
      return sortedMap;
    } else if (value is List) {
      return value.map(_canonicalizeValue).toList();
    }
    return value;
  }

  /// Validates and decodes raw JSON string into a list of journal entry maps.
  /// Returns null if raw is not a valid JSON list of maps, or if any entry
  /// violates schema/type constraints (missing/empty ID, wrong types).
  static List<Map<String, dynamic>>? safeDecodeJournalEntries(String raw) {
    try {
      final dynamic decoded = json.decode(raw);
      if (decoded is! List) return null;

      final result = <Map<String, dynamic>>[];
      for (final element in decoded) {
        if (element is! Map) return null;

        final map = <String, dynamic>{};
        for (final entry in element.entries) {
          if (entry.key is! String) return null;
          map[entry.key as String] = entry.value;
        }

        final id = map['id'];
        if (id is! String || id.isEmpty) return null;

        // surahId/ayahNumber int if non-null
        if (map.containsKey('surahId') && map['surahId'] != null) {
          if (map['surahId'] is! int) return null;
        }
        if (map.containsKey('ayahNumber') && map['ayahNumber'] != null) {
          if (map['ayahNumber'] is! int) return null;
        }

        // surahName/ayahSnippet/faithMessage/practicalAction/derivedDua/createdAt String if non-null
        if (map.containsKey('surahName') && map['surahName'] != null) {
          if (map['surahName'] is! String) return null;
        }
        if (map.containsKey('ayahSnippet') && map['ayahSnippet'] != null) {
          if (map['ayahSnippet'] is! String) return null;
        }
        if (map.containsKey('faithMessage') && map['faithMessage'] != null) {
          if (map['faithMessage'] is! String) return null;
        }
        if (map.containsKey('practicalAction') && map['practicalAction'] != null) {
          if (map['practicalAction'] is! String) return null;
        }
        if (map.containsKey('derivedDua') && map['derivedDua'] != null) {
          if (map['derivedDua'] is! String) return null;
        }
        if (map.containsKey('createdAt') && map['createdAt'] != null) {
          if (map['createdAt'] is! String) return null;
        }

        result.add(map);
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> entryContentSansId(Map<String, dynamic> entry) {
    final copy = <String, dynamic>{};
    for (final e in entry.entries) {
      if (e.key != 'id') {
        copy[e.key] = e.value;
      }
    }
    return copy;
  }

  static String canonicalEntryContent(Map<String, dynamic> entry) {
    return canonicalJsonEncode(entryContentSansId(entry));
  }

  /// PR 21 deterministic journal merge algorithm.
  static List<Map<String, dynamic>> mergeJournalEntries({
    required List<Map<String, dynamic>> localList,
    required List<Map<String, dynamic>> importedList,
  }) {
    // 1. Preserve ALL local order, values, duplicates
    final result = <Map<String, dynamic>>[];
    for (final localEntry in localList) {
      result.add(Map<String, dynamic>.from(localEntry));
    }

    // 2. Process imports in sequential input order against growing result
    for (final importEntry in importedList) {
      final originalId = importEntry['id'] as String;
      final importCanonical = canonicalEntryContent(importEntry);

      // Scan ALL occupants with originalId:
      // ANY same content => dedupe; unoccupied => append raw;
      // otherwise baseID = 'restored_' + calculateChecksum(canonicalcontentSansId)
      final occupantsWithOriginalId =
          result.where((e) => e['id'] == originalId).toList();

      if (occupantsWithOriginalId.isNotEmpty) {
        final hasSameContent = occupantsWithOriginalId
            .any((e) => canonicalEntryContent(e) == importCanonical);
        if (hasSameContent) {
          // ANY same content => dedupe
          continue;
        }
      } else {
        // unoccupied => append raw
        result.add(Map<String, dynamic>.from(importEntry));
        continue;
      }

      // Otherwise: occupied only by different content!
      final baseId = 'restored_${calculateChecksum(importCanonical)}';

      // Scan ALL occupants for candidateId:
      // ANY same content => dedupe; occupied only different => try base+'-2','-3',etc;
      // absent => append raw map ONLY id changed
      int suffix = 1;
      while (true) {
        final candidateId = suffix == 1 ? baseId : '$baseId-$suffix';
        final occupantsWithCandidate =
            result.where((e) => e['id'] == candidateId).toList();

        if (occupantsWithCandidate.isNotEmpty) {
          final hasSameContent = occupantsWithCandidate
              .any((e) => canonicalEntryContent(e) == importCanonical);
          if (hasSameContent) {
            // ANY same content => dedupe
            break;
          }
          // Occupied only by different content => try next suffix
          suffix++;
        } else {
          // absent => append raw map ONLY id changed
          final newEntry = Map<String, dynamic>.from(importEntry);
          newEntry['id'] = candidateId;
          result.add(newEntry);
          break;
        }
      }
    }

    return result;
  }
}
