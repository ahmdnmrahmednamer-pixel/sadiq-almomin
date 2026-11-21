import 'package:dio/dio.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'budur_quarter_boundaries.dart';
import 'budur_bounded_quarters.dart';
import 'budur_shared_contexts.dart';
import '../models/ayah.dart';
import '../models/surah.dart';
import 'bundled_original_book.dart';
import 'installed_original_books.dart';
import 'budur_verse_linker.dart';

class BudurPassage {
  final String text;
  final int firstPage, lastPage;
  final List<int> ayahs;
  final String contextNote;
  const BudurPassage(this.text, this.firstPage, this.lastPage, this.ayahs,
      {this.contextNote = ''});
}

/// Reads the original book only, stopping before the separately added corrections.
/// Quotations and independently bounded repetitions provide navigation only.
class BudurSource {
  static const bookUrl = 'https://shamela.ws/book/57';
  static const textUrl =
      'https://www-archiv.fdm.uni-hamburg.de/islamicempire/texts/57.txt';
  final Dio dio;
  final BundledOriginalBook? bundledOriginal;
  BudurSource({Dio? dio, BundledOriginalBook? bundledOriginal, bool useBundled = true})
      : bundledOriginal = bundledOriginal ?? (useBundled ? InstalledOriginalBooks.budur() : null),
        dio = dio ??
            Dio(BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 30)));
  String? _sessionText;
  Future<String> load() async {
    if (_sessionText != null) return _sessionText!;
    final value = bundledOriginal != null
        ? await bundledOriginal!.load()
        : (await dio.get<String>(textUrl,
            options: Options(responseType: ResponseType.plain))).data;
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

  /// Original quarter summaries may physically follow another surah. Return
  /// them as clearly marked shared context, never as ordinary ayah matches.
  /// Full physical-chapter reading already includes its own original summary.
  static List<BudurPassage> sharedContexts(String source,
      {required int surahId, required int ayahNumber}) {
    final result = <BudurPassage>[];
    for (final grant in _validSharedGrants(source)) {
      if (ayahNumber == 0 && surahId == grant.physicalSurah) continue;
      if (!grant.ranges.any((r) => r.$1 == surahId &&
          (ayahNumber == 0 || (r.$2 <= ayahNumber && ayahNumber <= r.$3)))) continue;
      final raw = source.substring(grant.start, grant.end);
      final text = raw.replaceAll(
          RegExp(r'\s*الجزء:\s*\d+\s*¦\s*الصفحة:\s*\d+\s*'), '\n\n').trim();
      result.add(BudurPassage(text, grant.firstPage, grant.lastPage, const [],
          contextNote: grant.note));
    }
    return result;
  }

  static Iterable<BudurSharedContextGrant> _validSharedGrants(String source) sync* {
    for (final grant in budurSharedContextGrants) {
      if (grant.start < 0 || grant.end > source.length ||
          grant.labelStart < 0 || grant.labelEnd > grant.start) continue;
      final label = source.substring(grant.labelStart, grant.labelEnd);
      final raw = source.substring(grant.start, grant.end);
      if (sha256.convert(utf8.encode(label)).toString() != grant.labelSha256 ||
          sha256.convert(utf8.encode(raw)).toString() != grant.sha256) continue;
      yield grant;
    }
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
    final verseIndex=BudurVerseIndex(ayahs);
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
    final sharedBlocks = <bool>[];
    final sharedGrants = _validSharedGrants(source)
        .where((g) => g.physicalSurah == surah.id).toList();
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
      final contentStart = a + raw.length - raw.trimLeft().length;
      final contentEnd = b - raw.length + raw.trimRight().length;
      final shared = sharedGrants.any(
          (g) => contentStart < g.end && contentEnd > g.start);
      sharedBlocks.add(shared);
      blocks.add(q.isEmpty || shared);
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

    // A summary after an author's end-of-quarter marker describes the
    // preceding range. Quoted items inside that summary are not normal verse
    // headings. Resume only when the full next quotation is proved to occur
    // strictly after a uniquely identified source marker. A doubtful marker
    // keeps the summary unassigned. The metadata registry accepts only exact
    // source end labels independently checked against quarter endings and
    // fingerprinted together with both neighboring original paragraphs.
    // An ambiguous end label may be bounded by two independent seed labels.
    // Validate every source fingerprint and both Quran occurrences afresh.
    // These grants do not create ordinary verse links or recursive anchors.
    // Edge passages have no neighbor on one side; the registry fingerprints
    // those contexts with an empty neighbor string (verified for 63:0, the
    // only edge entry, whose stored fingerprint reproduces exactly).
    String? contextAt(int i) => i >= 0 && i < texts.length
        ? sha256.convert(utf8.encode([
            if (i > 0) texts[i - 1] else '',
            texts[i],
            if (i + 1 < texts.length) texts[i + 1] else '',
          ].join('\u0000'))).toString()
        : null;
    int? independentEnd(int i) {
      final seed = budurReviewedQuarterEnds['${surah.id}:$i'];
      if (seed == null || contextAt(i) != seed.$2) return null;
      final qs = BudurVerseLinker.quotes(texts[i]);
      return qs.any((q) => verseIndex.occurrences(q)
          .any((c) => c.ayah == seed.$1)) ? seed.$1 : null;
    }
    int? passageIndexedEnd(int i) {
      final grant = budurPassageIndexedQuarterEnds['${surah.id}:$i'];
      if (grant == null || contextAt(i) != grant.$2 ||
          !texts[i].contains(grant.$3)) return null;
      // The independently identified end phrase must remain unique in the
      // current Quran and actually terminate the target verse. The source
      // paragraph remains unchanged and does not acquire an ordinary link.
      final hits = verseIndex.occurrences(grant.$4);
      if (hits.length != 1 || hits.single.ayah != grant.$1) return null;
      final target = ayahs.where((a) => a.ayahNumber == grant.$1).toList();
      if (target.length != 1 || !BudurVerseLinker.normalize(
          target.single.textUthmani).endsWith(grant.$4)) return null;
      return grant.$1;
    }
    int? boundedEnd(int i) {
      final grant = budurBoundedQuarterEnds['${surah.id}:$i'];
      if (grant == null || contextAt(i) != grant.$2 ||
          !(grant.$3 < i && i < grant.$4)) return null;
      final lower = independentEnd(grant.$3);
      final upper = independentEnd(grant.$4);
      if (lower == null || upper == null ||
          !(lower < grant.$1 && grant.$1 < upper)) return null;
      return BudurVerseLinker.quotes(texts[i]).any((q) =>
          verseIndex.occurrences(q).any((c) => c.ayah == grant.$1))
          ? grant.$1 : null;
    }
    var summary = false;
    int? quarterEnd;
    for (var i = 0; i < texts.length; i++) {
      final text = texts[i];
      // An inspected, fingerprinted line-wrap artifact keeps its text and
      // position but never classifies as a structural summary marker.
      final nonSummary = budurNonSummaryMarkers['${surah.id}:$i'];
      if (!(nonSummary != null && contextAt(i) == nonSummary) &&
          (text.startsWith('الممال') || text.startsWith('المدغم')))
        summary = true;
      final qs = BudurVerseLinker.quotes(text);
      if (summary && !sharedBlocks[i] && qs.isNotEmpty && quarterEnd != null) {
        final candidates =
            qs.expand((q) => verseIndex.occurrences(q)).toList();
        if (candidates.isNotEmpty &&
            qs.every(
                (q) => verseIndex.occurrences(q).isNotEmpty) &&
            candidates.every((c) => c.ayah > quarterEnd!)) summary = false;
      }
      if (summary) blocks[i] = true;
      if (text.contains('آخر الربع') || text.contains('منتهى الربع')) {
        final candidates =
            qs.expand((q) => verseIndex.occurrences(q)).toList();
        quarterEnd = candidates.length == 1 ? candidates.single.ayah : null;
        quarterEnd = independentEnd(i) ?? boundedEnd(i) ??
            passageIndexedEnd(i) ?? quarterEnd;
      }
    }
    final links = BudurVerseLinker.link(texts, blocks, ayahs,
        repeatedReviewed: verifiedRepeat,verseIndex:verseIndex);
    // Hud's source separates the vocative from the following noun. The
    // stored Uthmani form joins them and its dagger-alif normalization differs.
    // Only this exact source context may use the inspected Quran-side spelling;
    // no global spacing or spelling rule, inferred anchor, or source edit.
    if (surah.id == 11 && texts.length > 54 && !blocks[54] &&
        contextAt(54) ==
            '80f2648fbf00140a46277a0e49aad50535d9f6286f34cd8e89304a866d407aad') {
      final hits = verseIndex.occurrences('ويسماء اقلعي');
      if (hits.length == 1 && hits.single.ayah == 44) links[54] = [44];
    }
    // Baqara's source groups the two mentions of الأرض in 255 (ما في الأرض
    // and والأرض) under one "معا" label together with بإذنه, written in the
    // book's listing conjunction. The stored Uthmani text carries الأرض then
    // بإذنه in this order only inside 255. Source review confirmed the
    // passage's position and quote order: an unbroken 402-406 run between
    // anchors 254 and 256. The "معا" count is the author's own grouping. Only this exact source context may use the inspected joined Quran
    // phrase; no global tokenization change, no inferred anchor, no source
    // edit.
    if (surah.id == 2 && texts.length > 402 && !blocks[402] &&
        contextAt(402) ==
            '975dfb3d47b1358132c688fb41fa04127b75d4f68080725fcfc9ebf43a40c214') {
      final hits =
          verseIndex.occurrences('الارض من ذا الذي يشفع عنده الا باذنه');
      if (hits.length == 1 && hits.single.ayah == 255) links[402] = [255];
    }
    // These three standalone author-reference paragraphs were inspected in
    // their original source context. Exact paragraph identity plus a unique
    // Quran occurrence permits their own navigation, not reopening a summary
    // or supplying an inferred anchor to any other entry. In Maida the source
    // heading is retained verbatim; its inspected local context corresponds to
    // "وتبرئ" in verse 110, not the wording of the parallel verse in Al Imran.
    const reviewedReferences = <int, Map<String, (int, String)>>{
      3: {
        "\" وأبرئ \" الوقف عليها كالوقف على يستهزئ بالبقرة. \" وأنبئكم \" فيها لحمزة تحقيق الأولى وتسهيلها، وعلى كل تسهيل الثانية وإبدالها ياء خالصة.":
            (49, 'وأبرئ'),
      },
      5: {
        "\" فمن اضطر \" تقدم ما فيه لكل القراء في سورة البقرة.": (
          3,
          'فمن اضطر'
        ),
        "\" وأبرئ \" فيه لحمزة وهشام وقفا ما في يستهزئ بالبقرة.": (
          110,
          'وتبرئ'
        ),
      },
    };
    for (var i = 0; i < texts.length; i++) {
      final expected = reviewedReferences[surah.id]?[texts[i]];
      if (expected == null) continue;
      final qs = BudurVerseLinker.quotes(texts[i]);
      if (qs.length != 1) continue;
      final hits = verseIndex.occurrences(expected.$2);
      if (hits.length == 1 && hits.single.ayah == expected.$1)
        links[i] = [expected.$1];
    }
    // Three further standalone references were inspected against the two
    // distinct Qasas loci and the Sajda locus. Context phrases are exact
    // whole-token evidence, not a first-match search for the repeated word.
    const reviewedAima = <int, Map<String, (int, String)>>{
      28: {
        "\" أئمة \" تقدم نظيره في سورة الأنبياء.": (5, 'ونجعلهم أئمة'),
        "\" أئمة \" تقدم أول السورة.": (41, 'أئمة يدعون'),
      },
      32: {
        "\" أئمة \" سبق حكمها قريبا في القصص.": (24, 'أئمة يهدون'),
      },
    };
    for (var i = 0; i < texts.length; i++) {
      final expected = reviewedAima[surah.id]?[texts[i]];
      if (expected == null) continue;
      final hits = verseIndex.occurrences(expected.$2);
      if (hits.length == 1 && hits.single.ayah == expected.$1)
        links[i] = [expected.$1];
    }
    // Repeated headings here are disambiguated only by inspected adjacent
    // original source entries, not a default first-occurrence rule.
    const reviewedContexts = <int, Map<String, (int, String, String)>>{
      10: {
        "\" أرأيتم \" سبق قريبا.": (
          59,
          'ما أنزل الله لكم من رزق',
          '" قل آلله "'
        )
      },
      11: {"\" أرأيتم \" سبق في يونس.": (28, 'فعميت عليكم', '" وآتاني "')},
      18: {
        "\" للملائكة اسجدوا \" سبق في الإسراء مثله.": (
          50,
          'للملائكة اسجدوا',
          '" بدلا "'
        )
      },
      30: {
        "\" يبدؤا \" فيه لحمزة وهشام وقفا خمسة أوجه تقدمت في تفتؤا بيوسف.": (
          11,
          'ثم إليه ترجعون',
          '" ترجعون "'
        )
      },
    };
    for (var i = 0; i + 1 < texts.length; i++) {
      final expected = reviewedContexts[surah.id]?[texts[i]];
      if (expected == null || !texts[i + 1].startsWith(expected.$3)) continue;
      final hits = verseIndex.occurrences(expected.$2);
      if (hits.length == 1 && hits.single.ayah == expected.$1)
        links[i] = [expected.$1];
    }
    // Inspected list headings name separate Quran words, not a
    // contiguous quotation. Require the original paragraph and every whole-
    // token occurrence (including both occurrences in the same verse).
    // Individually inspected canonical anchors may retain an Uthmani spelling,
    // omit editorial list conjunctions, or use the ya reading explicitly
    // contrasted by the author. Never rewrite source text or infer a new
    // spelling/reading bridge from one of these exact paragraph grants.
    const reviewedLists = <int, Map<String, Map<String, List<int>>>>{
      2: {
        "\" يؤاخذكم معا \" قرأ ورش وأبو جعفر بإبدال الهمزة واوا خالصة وصلا ووقفا، وحمزة كذلك عند الوقف فقط، ولا خلاف عن ورش في قصره، وكل من يمد حرف المد بعد الهمز استثناه. ولذلك قال ابن الجزري لا خلاف في استثناء يؤاخذ، فإن رواة المد مجمعون على استثنائه.": {"يؤاخذكم": [225, 225]},
        "\" أولادهن رزقهن وكسوتهن \" وقف يعقوب عليه بهاء السكت.": {"أولادهن": [233], "رزقهن": [233], "وكسوتهن": [233]},
        "\" فأرهبون وفاتقون \".\r\nقرأ يعقوب بإثبات ياء زائدة فيهما في الحالين، والباقون بالحذف كذلك.": {"فأرهبون": [40], "فاتقون": [41]},
        "\" اليسر والعسر \" قرأ أبو جعفر بضم السين فيهما، والباقون بالإسكان.": {
          "اليسر": [185],
          "العسر": [185],
        },
        "\" فيغفر ويعذب \" قرأ الشامي وعاصم وأبو جعفر ويعقوب برفع الراء والباء من الفعلين والباقون بجزمهما.":
            {
          "فيغفر": [284],
          "ويعذب": [284],
        },
      },
      3: {
        "\" نؤته منها معا \" قرأ قالون ويعقوب وهشام بخلف عنه بكسر الهاء من غير صلة، وقرأ شعبة والبصري وحمزة وأبو جعفر بإسكان الهاء والباقون بكسرها مع الصلة وهو الوجه الثاني لهشام، وأبدل الهمز ورش والسوسي وأبو جعفر مطلقا وكذلك حمزة عند الوقف.": {"نؤته منها": [145, 145]},
        "\" قرح معا \" قرأ شعبة والأخوان وخلف بضم القاف والباقون بفتحها.": {"قرح": [140, 140]},
        "\" يؤده معا \" قرأ ورش وأبو جعفر بإبدال الهمزة ووا خالصة في الحالين وكذلك حمزة عند الوقف، وقرأ أبو عمرو وشعبة وحمزة وأبو جعفر بإسكان الهاء وصلا ووقفا. وقرأ قالون ويعقوب وهشام بخلف عنه بالقصر وقد يعبر عنه بالاختلاس، والمراد بالقصر أو الاختلاس في هذا الباب هاء الكناية الإتيان بالحركة كاملة من غير إشباع أي من غير صلة. وقرأ الباقون بالكسرة الكاملة مع الإشباع وهو الوجه الثاني لهشام، ولا يخفى أن من قرأ بالقصر أو الصلة فإنه يقف بالسكون، ومعلوم أن من يقرأ بالصلة يكون المد عنده من قبيل المنفصل فكل يمد حسب مذهبه.": {"يؤده": [75, 75]},
        "\" تأمنه معا \" إبداله مطلقا وفي الوقف لا يخفى.": {"تأمنه": [75, 75]},
        "\" الميت معا \" قرأ ابن كثير وأبو عمرو وابن عامر وشعبة بتخفيف الياء ساكنة والباقون بتشديدها مكسورة.": {"الميت": [27, 27]},
        "\" عليهم الذلة وعليهم المسكنة \" ذكرنا مذاهب القراء فيهما وأمثالهما مرارا.": {"عليهم الذلة": [112], "عليهم المسكنة": [112]},
      },
      4: {
        "\" بأمانيكم وأماني \" قرأ أبو جعفر بتخفيف الياء ساكنة فيهما، والباقون بتشديدها مكسورة": {"بأمانيكم": [123], "أماني أهل الكتاب": [123]},
        "\" تألمون معا ويألمون \" بالإبدال لورش والسوسي وأبي جعفر مطلقا، ولحمزة وقفا.": {"تألمون": [104, 104], "يألمون": [104]},
        "\" ندخله جنات، وندخله نارا \" قرأ نافع وأبو جعفر وابن عامر، بالنون فيهما، والباقون بالياء كذلك، ولا يخفى إخفاء أبي جعفر في نارا خالدا.": {"يدخله جنات": [13], "يدخله نارا": [14]},
        "\" خطأ معا \" لحمزة فيه وقفا التسهيل فقط.": {"خطأ": [92, 92]},
        "\" فيوفيهم ويهديهم \" ضم الهاء فيهما يعقوب.": {"فيوفيهم": [173], "ويهديهم": [175]},
        "\" وقتلهم الأنبياء. وأخذهم الربا \" تقدم مثلهما.": {"وقتلهم الأنبياء": [155], "وأخذهم الربا": [161]},
        "\" نوله ونصله \" قرأ قالون ويعقوب وهشام بخلف عنه بكسر الهاء من غير صلة، وقرأ البصري وشعبة وحمزة وأبو جعفر بإسكانها، والباقون بكسرها مع الصلة، وهو الوجه الثاني لهشام.":
            {
          "نوله": [115],
          "ونصله": [115],
        },
      },
      5: {
        "\" يؤاخذكم معا \" قرأ ورش وأبو جعفر بابدال الهمزة واوا خالصة وصلا ووقفا وكذلك قرأ حمزة وقفا.": {"يؤاخذكم": [89, 89]},
        "\" والمحصنات معا \" قرأ الكسائي بكسر الصاد، والباقون بفتحها.": {"والمحصنات": [5, 5]},
        "\" والعين والأنف والأذن والسن والجروح \" قرأ نافع وعاصم وحمزة وخلف ويعقوب بنصب الكلمات الخمس وقرأ الكسائي برفعها، وقرأ المكي والبصري والشامي وأبو جعفر بنصب الأربع الأولى ورفع الجروح.": {"والعين": [45], "والأنف": [45], "والأذن": [45], "والسن": [45], "والجروح": [45]},
      },
      6: {
        "\" الميت معا \" قرأ نافع وحفص والأخوان ويعقوب وخلف وأبو جعفر بتشديد الياء مكسورة، والباقون بتخفيفها ساكنة.": {"الميت": [95, 95]},
        "\" ولا نكذب. ونكون \" قرأ حفص وحمزة ويعقوب بنصب الباء في الفعل الأول ونصب النون في الثاني. وقرأ ابن عامر بالرفع في الأول والنصب في الثاني. وقرأ الباقون بالرفع في الفعلين معا.": {"ولا نكذب": [27], "ونكون": [27]},
      },
      7: {
        "\" يتخذوه معا \" وصل المكي هاء الضمير.": {"يتخذوه": [146, 146]},
        "\" مبصرون. يقصرون \" فيهما ترقيق الراء لورش.": {"مبصرون": [201], "يقصرون": [202]},
        "\" عليهم الطوفان. عليهم الرجز \" تقدم غير مرة.": {"عليهم الطوفان": [133], "عليهم الرجز": [134]},
      },
      11: {
        "\" إني إذا. نصحي إن \" فتح الياء فيهما المدنيان والبصري، وأسكنها غيرهم.": {"إني إذا": [31], "نصحي إن": [34]},
        // Reviewer-confirmed against the source context: both وقيل occurrences
        // and the single وغيض occurrence fall in 11:44, between the linked
        // anchors 11:52→43 and 11:55→46.
        "\" وقيل معا، وغيض \" قرأ هشام والكسائي ورويس بإشمام الكسرة الضم، والباقون بالكسرة الكاملة.": {"وقيل": [44, 44], "وغيض": [44]},
      },
      10: {
        "\" ولا أصغر ولا أكبر \" قرأ يعقوب وخلف وحمزة برفع الراء فيهما، والباقون بنصبها فيهما.":
            {
          "ولا أصغر": [61],
          "ولا أكبر": [61],
        },
      },
      36: {
        "\" سدا، معا \" فتح السين فيهما حفص والأخوان وخلف، وضمها غيرهم.": {
          "سدا": [9, 9],
        },
      },
      39: {
        "\" وسيق معا \" قرأ ابن عامر والكسائي ورويس بإشمام كسرة السين الضم وغيره بالكسر الخالص.": {"وسيق": [71, 73]},
        "\" فتحت وفتحت \" خفف التاء فيهما الكوفيون وشددها غيرهم.": {
          "فتحت": [71],
          "وفتحت": [73],
        },
      },
      40: {
        "\" واق هاد \" قرأ المكي بزيادة ياء بعد القاف والدال في الوقف فيهما والباقون بحذفها ولا خلاف بينهم في تنوينهما وصلا.": {"واق": [21], "هاد": [33]},
      },
      58: {
        "\" اللائي \" سبق بسط الكلام عليه لجميع القراء وصلا ووقفا في سورة الأحزاب.": {"ٱلَّـٰۤـِٔی": [2]},
        "\" ومعصيت معا \" رسم بالتاء ووقف عليه بالهاء المكي والبصريان والكسائي وغيرهم بالتاء": {"ومعصيت": [8, 9]},
      },
      12: {
        "\" إني أراني معا \" فتح الياء المدنيان والبصري وأسكنها غيرهم.": {"إِنِّیۤ أَرَىٰنِیۤ": [36, 36]},
        "\" غيابت الجب معا \" قرأ المدنيان بألف بعد الباء الموحدة على الجمع ووقفا بالتاء، والباقون نحذفها على الإفراد ووقف بالهاء المكي والبصريان والكسائي، والباقون بالتاء.": {"غَیَـٰبَتِ ٱلۡجُبِّ": [10, 15]},
        "\" أراني أعصر وأراني أحمل \" فتح الياء المدنيان والمكي والبصري وأسكنها غيرهم.": {"أعصر خمرا": [36], "أحمل فوق رأسي خبزا": [36]},
        "\" سنبلات خضر معا \" أخفى التنوين في الخاء مع الغنة أبو جعفر وأظهره غيره.": {"سنبلات خضر": [43, 46]},
      },
      14: {
        "\" نعمت الله معا \" رسم بالتاء ووقف عليهما بالهاء المكي والبصريان والكسائي وغيرهم بالتاء.": {"نعمت الله": [28, 34]},
      },
      16: {
        "\" إبراهيم معا \" قرأ هشام بفتح الهاء وألف بعدها وغيره بكسرها وياء بعدها.": {"إبراهيم": [120, 123]},
      },
      23: {
        "\" هيهات معا \" قرأ أبو جعفر بكسر التاء فيهما، والباقون بفتحها، ووقف عليهما بالهاء البزي والكسائي، والباقون بالتاء.": {"هيهات": [36, 36]},
      },
      27: {
        "\" أنا آتيك معا \" أثبت ألف أنا وصلا المدنيان وحذفها غيرهما، واتفق العشرة على إثباتها وقفا.": {"أنا آتيك": [39, 40]},
      },
      29: {
        "\" يبدئ وينشئ \" فيه لهشام وحمزة وقفا ما في \" يستهزئ\" في البقرة.": {"يبدئ": [19], "ينشئ": [20]},
        "\" رسلنا معا \" أسكن السين أبو عمرو وضمها غيره.": {"رسلنا": [31, 33]},
      },
      30: {
        "\" الميت معا \" قرأ المدنيان والأخوان وحفص ويعقوب وخلف بالتشديد وغيرهم بالتخفيف.": {"الميت": [19, 19]},
      },
      46: {
        "\" كرها معا \" قرأ المدنيان والمكي والبصري وهشام بفتح الكاف، والباقون بضمها،": {"كرها": [15, 15]},
      },
      55: {
        "\" لم يطمثهن معا \" يؤخذ من الشاطبية أن للكسائي من روايتيه ثلاثة مذاهب، المذهب الأول: ضم اللفظ الأول وكسر الثاني من رواية الدوري وكسر الأول وضم الثاني من رواية أبي الحارث، ويؤخذ هذا المذهب من قوله. وكسر ميم يطمث إلخ وقوله: وقال به الليث في الثاني إلخ. وقد قرأ الداني بهذا المذهب على شيخه طاهر بن غلبون. المذهب الثاني: ضم الأول وكسر الثاني لكل من الدوري وأبي الحارث ويؤخذ هذا المذهب من قوله: وكسر ميم يطمث: وقوله: ونص الليث إلخ. والحاصل أنه لما أمر بضم الأول، أي مع كسر الثاني للدوري ثم أخبر بأن شيوخا ذهبوا إلى ضم الثاني وحده. أي مع كسر الأول لأبي الحارث ثم أخبر بأن النص عن أبي الحارث ورد بضم الأول تحصل منه المذهبان المذكوران فكأنه قال: اقرأ للدوري بضم الأول وكسر الثاني واقرأ الثاني واقرأ لأبي الحارث بأحد وجهين، ضم الثاني مع كسر الأول فيكون مخالفا للدوري في الموضعين، وهذا هو المذهب الأول. أو ضم الأول وكسر الثاني فيكون موافقا له فيهما وهذا هو المذهب الثاني وقد قرأ الداني بهذا المذهب على شيخه أبي الفتح فارس. المذهب الثالث التخيير لكل من الراويين في ضم أحدهما بمعنى أنه إذا ضم الأول كسر الثاني وإذا كسر الأول ضم الثاني ويؤخذ هذا المذهب من قوله: وقول الكسائي ضم أيهما تشاء وجيه إلخ ويؤخذ من مجموع المذاهب الثلاثة أنه لا يجوز للدوري ولا لأبي الحارث ضمهما معا ولا كسرهما معا بل لابد من التخالف بينهما في الضم والكسر فاذا ضم الأول تعين كسر الثاني وبالعكس. قال علماء القراءات وإذا أردت قراءتهما للكسائي وجمعهما في التلاوة فاقرأ الأول بالضم ثم الكسر والثاني بالكسر ثم الضم وقرأ الباقون بالكسر فيهما قولا واحدا.": {"لم يطمثهن": [56, 74]},
      },
      60: {
        "\" أسوة معا \" قرأ عاصم بضم الهمزة وغيره بكسر ما.": {"أسوة": [4, 6]},
      },
      67: {
        "\" السماء أن معا \" أبدل الثانية ياء خالصة المدنيان والمكي والبصري ورويس وحققها الباقون.": {"السماء أن": [16, 17]},
      },
      69: {
        "\" حسابيه معا \" حذف يعقوب الهاء وصلا وأثبتها غيره كذلك ولا خلاف بينهم في إثباتها في الوقف.": {"حسابيه": [20, 26]},
      },
      90: {
        "\" أيحسب معا \" فتح السين فيهما الشامي وعاصم وحمزة وأبو جعفر وكسرها غيرهم.": {"أيحسب": [5, 7]},
      },
      96: {
        "\" اقرأ معا \" أبدل الهمز فيها مطلقا أبو جعفر وعند الوقف فقط حمزة.": {"اقرأ": [1, 3]},
      },
      34: {
        "\" نحشرهم، نقول \" قرأ حفص ويعقوب بالياء التحتية فيهما والباقون بالنون فيهما.": {"يحشرهم جميعا": [40], "ثم يقول": [40]},
      },
      45: {
        "\" آيات لقوم يوقنون، آيات لقوم يعقلون \" قرأ الأخوان ويعقوب بنصب التاء بالكسرة فيهما، والباقون برفعها كذلك.": {"ءَایَـٰتࣱ لِّقَوۡمࣲ یُوقِنُونَ": [4], "ءَایَـٰتࣱ لِّقَوۡمࣲ یَعۡقِلُونَ": [5]},
      },
      9: {
        "\" أسس بنيانه معا \" قرأ نافع وابن عامر بضم الهمزة وكسر السين الأولى في الموضعين ورفع نون بنيانه فيهما. والباقون بفتح الهمزة والسين الأولى في الموضعين ونصب بنيانه فيهما.": {"أَسَّسَ بُنۡیَـٰنَهُۥ": [109, 109]},
      },
      65: {
        "\" واللائي معا \" تقدم الكلام عليه مبسوطا في سورة الأحزاب.": {"وَٱلَّـٰۤـِٔی": [4, 4]},
      },
      33: {
        "\" اللائي \" قرأ قالون وقنبل ويعقوب بهمزة مكسورة من غير ياء بعدها وصلا ووقفا، ولهم في الوقف عليه ما لهم في الوقف على نحو السماء من الأوجه. وقرأ البزي وأبو عمرو وصلا بتسهيل الهمزة بين بين مع المد والقصر عنهما إبدال الهمزة ياء ساكنة مع المد المشبع لالتقاء الساكنين وصلا أيضا. فإذا وقفا كان لهما ثلاثة أوجه: تسهيل الهمزة بالروم مع المد والقصر وإبدالها ياء ساكنة مع المد المشبع لالتقاء الساكنين أيضا. وقرأ ورش وأبو جعفر بتسهيل الهمزة بين بين مع المد والقصر وصلا فإذا وقفا كان لهما ثلاثة أوجه أيضا: بتسهيل الهمزة بالروم مع المد والقصر، وإبدالها ياء ساكنة مع التطويل وكل على أصله في مقدار المد، وقرأ الشامي والكوفيون بهمزة مكسورة بعدها ياء ساكنة وصلا ووقفا وهم على أصولهم في المد ولحمزة في الوقف عليه تسهيل الهمزة مع المد والقصر.": {"ٱلَّـٰۤـِٔی": [4]},
      },
      64: {
        "\" يكفر. ويدخله \" قرأ المدنيان والشامي بالنون في الفعلين والباقون بالياء التحتية فيهما.":
            {
          "يكفر": [9],
          "ويدخله": [9],
        },
      },
      71: {
        "\" ويؤخركم لا يؤخر \" أبدل ورش وأبو جعفر الهمزة واوا خالصة مطلقا، وكذلك حمزة عند الوقف.":
            {
          "ويؤخركم": [4],
          "لا يؤخر": [4],
        },
      },
      75: {
        "\" تحبون وتذرون \" قرأ المكي والبصريان والشامي بياء الغيبة فيهما، والباقون بتاء الخطاب كذلك.":
            {
          "تحبون": [20],
          "وتذرون": [21],
        },
      },
      66: {
        "\" امرأت الثلاثة وابنت \" رسمت كلها بالتاء ووقف عليها بالهاء المكي والبصريان والكسائي، والباقون بالتاء.":
            {
          "امرأت": [10, 11],
          "وامرأت": [10],
          "ابنت": [12],
        },
      },
      18: {
        "\" فأتبع سببا ثم اتبع سببا معا \" قرأ الشامي والكوفيون بقطع الهمزة وإسكان التاء في الثلاثة وغيرهم بوصل الهمزة وتشديد التاء.": {"فأتبع سببا": [85], "ثم أتبع سببا": [89, 92]},
        "\" بربي أحدا معا \" و \" ربي أن \" فتح الياء المدنيان والمكي والبصري وأسكنها غيرهم.": {"بربي أحدا": [38, 42], "ربي أن": [40]},
        "\" وهيئ. ويهيئ \" أبدل الهمز فيهما أبو جعفر وحده في الحالين وهشام وحمزة في الوقف فقط.":
            {
          "وهيئ": [10],
          "ويهيئ": [16]
        }
      },
      22: {
        "\" وليوفوا وليطوفوا \" قرأ ابن ذكوان بكسر اللام فيهما، والباقون بالإسكان. وقرأ شعبة بفتح الواو وتشديد الفاء من وليوفوا، والباقون بسكون الواو وتخفيف الفاء.":
            {
          "وليوفوا": [29],
          "وليطوفوا": [29]
        }
      },
    };
    for (var i = 0; i < texts.length; i++) {
      final words = reviewedLists[surah.id]?[texts[i]];
      if (words == null) continue;
      var verified = true;
      final verses = <int>{};
      for (final word in words.entries) {
        final hits = verseIndex.occurrences(word.key)
            .map((h) => h.ayah)
            .toList();
        if (hits.length != word.value.length ||
            List.generate(hits.length, (j) => hits[j] == word.value[j])
                .contains(false)) {
          verified = false;
          break;
        }
        verses.addAll(hits);
      }
      if (verified) links[i] = verses.toList()..sort();
    }
    return [
      for (var i = 0; i < texts.length; i++)
        BudurPassage(texts[i], ranges[i][0], ranges[i][1],
            sharedBlocks[i] ? const [] : links[i])
    ];
  }
}
