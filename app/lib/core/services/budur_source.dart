import 'package:dio/dio.dart';
import '../models/ayah.dart';
import '../models/surah.dart';
import 'budur_verse_linker.dart';

class BudurPassage {
  final String text;
  final int firstPage, lastPage;
  final List<int> ayahs;
  const BudurPassage(this.text, this.firstPage, this.lastPage, this.ayahs);
}

/// Reads the original book only, stopping before the separately added corrections.
/// Quotations and independently bounded repetitions provide navigation only.
class BudurSource {
  static const bookUrl = 'https://shamela.ws/book/57';
  static const textUrl =
      'https://www-archiv.fdm.uni-hamburg.de/islamicempire/texts/57.txt';
  final Dio dio;
  BudurSource({Dio? dio})
      : dio = dio ??
            Dio(BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 30)));
  String? _sessionText;
  Future<String> load() async {
    if (_sessionText != null) return _sessionText!;
    final response = await dio.get<String>(textUrl,
        options: Options(responseType: ResponseType.plain));
    final value = response.data;
    if (value == null ||
        !value.contains('عبد الفتاح') ||
        !value.contains('الشاطبية') ||
        !value.contains('الدرة')) {
      throw const FormatException('Book identity mismatch');
    }
    final stop = value.indexOf('تصويبات للشيخ');
    if (stop < 0) throw const FormatException('Original-text boundary missing');
    return _sessionText = value.substring(0, stop);
  }

  static String normalize(String s) => s
      .replaceAll(RegExp('[ً-ٰٟۖ-ۭـ]'), '')
      .replaceAll(RegExp('[أإآٱ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll(RegExp('[^ء-ي ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static List<BudurPassage> passages(
      String source, Surah surah, List<Ayah> ayahs) {
    final stop = source.indexOf('تصويبات للشيخ');
    if (stop >= 0) source = source.substring(0, stop);
    const aliases = {
      'يونس عليه السلام': 10,
      'طه عليه السلام': 20,
      'نوح عليه السلام': 71,
      'المؤمن': 40,
      'ن': 68,
      'الدهر': 76,
      'المنافقين': 63,
      'والطور': 52,
      'والمرسلات': 77,
      'والفجر': 89,
      'والشمس': 91,
      'والليل': 92,
      'والضحى': 93,
      'الم نشرح': 94,
      'والتين': 95,
      'الزلزال': 99,
      'والعاديات': 100,
      'والعصر': 103,
      'سيدنا ومولانا محمد صلي الله عليه وسلم': 47
    };
    final heads = RegExp(
            r'"[ \t]*سورة[ \t]+([^"\n]+)"|^[ \t]*\(?[ \t]*سورة[ \t]+([^\n)]+?)\)?[ \t]*$',
            multiLine: true)
        .allMatches(source)
        .where((m) =>
            !(m.group(1) ?? m.group(2)!).contains('من السور') &&
            !(m.group(1) ?? m.group(2)!).contains('آخر السور'))
        .toList();
    RegExpMatch? heading;
    int end = source.length;
    for (var i = 0; i < heads.length; i++) {
      final n = normalize(heads[i].group(1) ?? heads[i].group(2)!);
      if (n == normalize(surah.nameAr).replaceFirst(RegExp(r'^سورة '), '') ||
          aliases.entries
              .any((e) => normalize(e.key) == n && e.value == surah.id)) {
        heading = heads[i];
        end = i + 1 < heads.length ? heads[i + 1].start : source.length;
        break;
      }
    }
    if (heading == null) return const [];
    // The final chapter ends before the separately headed takbir chapter.
    final takbir = source.indexOf('باب التكبير', heading.end);
    if (takbir >= 0 && takbir < end) end = takbir;
    final chapter = source.substring(heading.end, end);
    // Structural summaries belong to their own source context, not to the
    // preceding quoted verse. Preserve their exact text but do not auto-assign.
    final markers = RegExp(r'^\s*"\s*([^"\n]+)"|^[ \t]*(الممال|المدغم)[ \t]*$',
            multiLine: true)
        .allMatches(chapter)
        .toList();
    final pages = RegExp(r'الجزء:\s*\d+\s*¦\s*الصفحة:\s*(\d+)')
        .allMatches(source)
        .toList();
    int pageAt(int offset) {
      for (final p in pages) {
        if (p.start >= offset) return int.parse(p.group(1)!);
      }
      return 357;
    }

    final starts = <int>[
      heading.end,
      ...markers.map((m) => heading!.end + m.start)
    ];
    final texts = <String>[];
    final ranges = <List<int>>[];
    final blocks = <bool>[];
    for (var i = 0; i < starts.length; i++) {
      final a = starts[i], b = i + 1 < starts.length ? starts[i + 1] : end;
      final raw = source.substring(a, b);
      final text = raw
          .replaceAll(RegExp(r'\s*الجزء:\s*\d+\s*¦\s*الصفحة:\s*\d+\s*'), '\n\n')
          .trim();
      if (text.isEmpty) continue;
      var last = b - 1;
      final included = pages.where((p) => p.start >= a && p.end <= b).toList();
      if (included.isNotEmpty &&
          source.substring(included.last.end, b).trim().isEmpty)
        last = included.last.start - 1;
      texts.add(text);
      ranges.add([pageAt(a), pageAt(last)]);
      final q = BudurVerseLinker.quotes(text);
      blocks.add(q.isEmpty);
    }
    // A monotone window alone is not proof. Only these source contexts were
    // independently inspected in this edition; every other repeated quote
    // remains unassigned pending source review.
    const reviewed = <int, Map<String, List<String>>>{
      1: {
        'الرحيم': ['العالمين', 'مالك يوم الدين']
      },
      2: {
        'بما أنزل': ['رزقناهم', 'وبالآخرة'],
        'عذاب أليم': ['وما يخدعون', 'يكذبون'],
        'أظلم': ['أضاء', 'وأبصارهم'],
        'بأسمائهم': ['أنبئهم', 'أنبأهم'],
      },
    };
    bool verifiedRepeat(int i) {
      if (i == 0 || i + 1 >= texts.length) return false;
      final q = BudurVerseLinker.quotes(texts[i]);
      if (q.length != 1) return false;
      for (final e
          in (reviewed[surah.id] ?? const <String, List<String>>{}).entries) {
        if (BudurVerseLinker.normalize(e.key) != q.single) continue;
        final before = BudurVerseLinker.quotes(texts[i - 1]);
        final after = BudurVerseLinker.quotes(texts[i + 1]);
        return before.length == 1 &&
            after.length == 1 &&
            before.single == BudurVerseLinker.normalize(e.value[0]) &&
            after.single == BudurVerseLinker.normalize(e.value[1]);
      }
      return false;
    }

    final links = BudurVerseLinker.link(texts, blocks, ayahs,
        repeatedReviewed: verifiedRepeat);
    return [
      for (var i = 0; i < texts.length; i++)
        BudurPassage(texts[i], ranges[i][0], ranges[i][1], links[i])
    ];
  }
}
