import '../models/ayah.dart';
import '../text/arabic_normalizer.dart';

/// Structural navigation only. No reading or ruling is generated here.
class BudurVerseLinker {
  // Use the app's already-tested Uthmani/Imlaei search conversion. It changes
  // comparison keys only, never the displayed Quran or source-book text.
  static String normalize(String value) =>
      ArabicNormalizer.normalizeForQuranSearch(value)
          // The stored Uthmani form of ula'ika has a dagger alif before its
          // hamza seat. Search canonicalization otherwise leaves "اولايك".
          // Restrict this spelling bridge to the whole demonstrative token.
          .replaceAllMapped(RegExp(r'(^|\s)([وفبلك]?)اولايك(?=\s|$)'),
              (m) => '${m.group(1)}${m.group(2)}اوليك')
          .replaceAll(RegExp('[^ء-ي ]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

  static const structural = {
    'الكبير',
    'الصغير',
    'الممال',
    'المدغم',
    'جلي',
    'واضح',
    'رءوس الاي الممالة',
    'ما ليس براس اية',
  };

  /// Each quote must have its own evidence. A combined paragraph may refer to
  /// several verses, but its entire text is not a separate ruling for each one.
  static List<String> quotes(String text) {
    var rest = text.trimLeft();
    final result = <String>[];
    var first = true;
    while (true) {
      final m =
          RegExp(first ? r'^"\s*([^"\n]+)\s*"' : r'^\s*و\s*"\s*([^"\n]+)\s*"')
              .firstMatch(rest);
      if (m == null) break;
      for (final part in m.group(1)!.split('،')) {
        final q = normalize(part);
        if (q.isNotEmpty && !structural.contains(q)) result.add(q);
      }
      rest = rest.substring(m.end);
      first = false;
    }
    return result;
  }

  /// Returns all whole-token occurrences, including repeated occurrences in one
  /// verse. Never use global Quran ids as within-surah verse numbers.
  static List<BudurOccurrence> occurrences(String quote, List<Ayah> ayahs) {
    return BudurVerseIndex(ayahs).occurrences(quote);
  }

  /// Independent anchors are quotations occurring once in this surah, not
  /// guesses inherited from other sequential matches. Repeated quotations are
  /// linked only when two immediate independent anchors leave one occurrence.
  /// Bounds never cross a structural block, an unresolved quotation, reversed
  /// order, or an intervening repeated/derived match.
  static List<List<int>> link(
      List<String> texts, List<bool> blocks, List<Ayah> ayahs,
      {bool Function(int index)? repeatedReviewed, BudurVerseIndex? verseIndex}) {
    final index=verseIndex??BudurVerseIndex(ayahs);
    final quoted = texts.map(quotes).toList();
    final all = quoted
        .map((qs) => qs.map((q) => index.occurrences(q)).toList())
        .toList();
    final authorBoth = texts
        .map(
            (text) => RegExp(r'^\s*"[^"\n]+"\s*معا(?:[.،\s]|$)').hasMatch(text))
        .toList();
    final anchor = List<BudurOccurrence?>.filled(texts.length, null);
    for (var i = 0; i < texts.length; i++) {
      if (!blocks[i] &&
          !authorBoth[i] &&
          all[i].length == 1 &&
          all[i].single.length == 1) {
        anchor[i] = all[i].single.single;
      }
    }
    final linked = List<List<int>>.generate(texts.length, (_) => []);
    for (var i = 0; i < texts.length; i++) {
      if (blocks[i] || all[i].isEmpty) continue;
      final resolved = <int>{};
      var complete = true;
      for (final candidates in all[i]) {
        // The author's immediate "both" label must agree with exactly two
        // complete occurrences. A single normalized match is not enough and
        // must not become an independent anchor for another passage.
        if (authorBoth[i]) {
          if (all[i].length != 1 || candidates.length != 2) {
            complete = false;
            break;
          }
          resolved.addAll(candidates.map((c) => c.ayah));
          continue;
        }
        if (candidates.length == 1) {
          resolved.add(candidates.single.ayah);
          continue;
        }
        // The immediate neighboring source entries must themselves be
        // independent unique quotations, not previously inferred neighbors.
        if (i == 0 ||
            i + 1 >= texts.length ||
            anchor[i - 1] == null ||
            anchor[i + 1] == null) {
          complete = false;
          break;
        }
        if (repeatedReviewed == null || !repeatedReviewed(i)) {
          complete = false;
          break;
        }
        final before = anchor[i - 1]!;
        final after = anchor[i + 1]!;
        if (before.end >= after.start) {
          complete = false;
          break;
        }
        final bounded = candidates
            .where((c) => c.start > before.end && c.end < after.start)
            .toList();
        if (bounded.length != 1) {
          complete = false;
          break;
        }
        resolved.add(bounded.single.ayah);
      }
      if (complete) linked[i] = resolved.toList()..sort();
    }
    return linked;
  }
}

class BudurOccurrence {
  final int ayah, start, end;
  const BudurOccurrence(this.ayah, this.start, this.end);
}

/// One immutable normalized Quran search view per source chapter. Display text
/// stays unchanged. Offsets match the original whole-token occurrence method.
class BudurVerseIndex {
  final List<(int,int,String)> _verses=[];
  final Map<String,List<BudurOccurrence>> _cache={};
  BudurVerseIndex(List<Ayah> ayahs){
    var offset=0;
    for(final ayah in ayahs){
      var words=BudurVerseLinker.normalize(ayah.cleanTextUthmani);
      if(ayah.ayahNumber==1&&ayah.surahId!=1&&ayah.surahId!=9){
        words=words.replaceFirst(RegExp(r'^بسم الله الرحمن الرحيم\s*'),'');
      }
      final padded=' $words ';
      _verses.add((ayah.ayahNumber,offset,padded));offset+=padded.length;
    }
  }
  List<BudurOccurrence> occurrences(String quote){
    final q=BudurVerseLinker.normalize(quote);if(q.isEmpty)return const [];
    return _cache.putIfAbsent(q,(){
      final result=<BudurOccurrence>[];
      for(final verse in _verses){
        var from=0;
        while(true){
          final at=verse.$3.indexOf(' $q ',from);if(at<0)break;
          result.add(BudurOccurrence(verse.$1,verse.$2+at,verse.$2+at+q.length));from=at+1;
        }
      }
      return List.unmodifiable(result);
    });
  }
}
