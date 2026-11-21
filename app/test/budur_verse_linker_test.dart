import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/models/ayah.dart';
import '../lib/core/models/surah.dart';
import '../lib/core/services/budur_source.dart';
import '../lib/core/services/budur_verse_linker.dart';

List<Ayah> sample(List<String> verses, {int surah = 1}) => [
      for (var i = 0; i < verses.length; i++)
        Ayah.fromRow({
          'id': 9000 + i,
          'surah_id': surah,
          'ayah_number': i + 1,
          'juz': 1,
          'page': 1,
          'text_uthmani': verses[i],
        }),
    ];
void main() {
  test('Uthmani hamza seat is preserved before search normalization',(){
    expect(BudurVerseLinker.normalize('أُو۟لَـٰۤىِٕكَ'),BudurVerseLinker.normalize('أولئك'));
    expect(BudurVerseLinker.normalize('أُو۟لَـٰۤىِٕكَ'),isNot(BudurVerseLinker.normalize('أولاك')));
    final verses=sample(['أُو۟لَـٰۤىِٕكَ']);
    expect(BudurVerseLinker.occurrences('أولئك',verses).single.ayah,1);
  });
  test('repetition requires two immediately adjacent independent anchors', () {
    final ayahs = sample(['مكرر', 'مرساة اولى', 'مكرر', 'مرساة اخيرة', 'مكرر']);
    expect(
        BudurVerseLinker.link([
          '"مرساة اولى"',
          '"مكرر"',
          '"مرساة اخيرة"'
        ], [
          false,
          false,
          false
        ], ayahs, repeatedReviewed: (_) => true),
        [
          [2],
          [3],
          [4]
        ]);
    expect(
        BudurVerseLinker.link(
                ['"مكرر"', '"مرساة اخيرة"'], [false, false], ayahs)
            .first,
        isEmpty);
  });
  test(
      'no inherited anchor, block crossing, reversed anchor or multiple candidates',
      () {
    final ayahs = sample(['مرساة اولى', 'مكرر', 'مكرر', 'مرساة اخيرة']);
    expect(
        BudurVerseLinker.link(['"مرساة اولى"', '"مكرر"', '"مرساة اخيرة"'],
            [false, false, false], ayahs)[1],
        isEmpty);
    expect(
        BudurVerseLinker.link(['"مرساة اخيرة"', '"مكرر"', '"مرساة اولى"'],
            [false, false, false], ayahs)[1],
        isEmpty);
    expect(
        BudurVerseLinker.link(
            ['"مرساة اولى"', 'الممال', '"مكرر"', '"مرساة اخيرة"'],
            [false, true, false, false],
            ayahs)[2],
        isEmpty);
  });
  test('immediate author both label requires exactly two complete occurrences',
      () {
    expect(
        BudurVerseLinker.link(['" لفظ " معا SOURCE'], [false], sample(['لفظ'])),
        [[]]);
    expect(
        BudurVerseLinker.link(
            ['" لفظ " معا SOURCE'], [false], sample(['لفظ لفظ'])),
        [
          [1]
        ]);
    final two = sample(['لفظ', 'لفظ']);
    expect(BudurVerseLinker.link(['" لفظ " معا SOURCE'], [false], two), [
      [1, 2]
    ]);
    expect(BudurVerseLinker.link(['" لفظ " معا SOURCE'], [true], two), [[]]);
    expect(
        BudurVerseLinker.link(
            ['" لفظ " معا SOURCE'], [false], sample(['لفظ', 'لفظ', 'لفظ'])),
        [[]]);
    expect(
        BudurVerseLinker.link(['" لفظ " general prose ثم معا'], [false], two),
        [[]]);
    expect(BudurVerseLinker.link(['" لفظ، آخر " معا'], [false], two), [[]]);
  });
  test('quoted summary item never becomes an ordinary verse heading', () {
    const surah = Surah(
        id: 1,
        nameAr: 'اختبار',
        nameSimple: 'اختبار',
        revelationPlace: 'makkah',
        revelationOrder: 1,
        ayahCount: 3,
        hasBasmala: false,
        pageStart: 1,
        pageEnd: 1);
    const text =
        'سورة اختبار\n"نهاية ثابتة" آخر الربع.\nالممال\n"لفظ قديم" SUMMARY_ONLY\nالمدغم\n"مستأنف" NEXT_SECTION\nالجزء: 1 ¦ الصفحة: 1\nتصويبات للشيخ';
    final results = BudurSource.passages(
        text, surah, sample(['لفظ قديم', 'نهاية ثابتة', 'مستأنف']));
    expect(results.firstWhere((p) => p.text.contains('SUMMARY_ONLY')).ayahs,
        isEmpty);
    expect(
        results.firstWhere((p) => p.text.contains('NEXT_SECTION')).ayahs, [3]);
    final doubtful = BudurSource.passages(
        text.replaceFirst('نهاية ثابتة', 'غير مثبت'),
        surah,
        sample(['لفظ قديم', 'نهاية ثابتة', 'مستأنف']));
    expect(doubtful.firstWhere((p) => p.text.contains('NEXT_SECTION')).ayahs,
        isEmpty);
  });
  test('word boundaries and within-verse repetitions are not unique', () {
    final ayahs = sample(['مرساة اولى', 'مكرر مكرر', 'مرساة اخيرة', 'ومكررون']);
    expect(BudurVerseLinker.occurrences('مكرر', ayahs).length, 2);
    expect(
        BudurVerseLinker.link(['"مرساة اولى"', '"مكرر"', '"مرساة اخيرة"'],
            [false, false, false], ayahs)[1],
        isEmpty);
    expect(BudurVerseLinker.occurrences('كرر', ayahs), isEmpty);
  });
  test('every quote in a multiple-verse paragraph needs its own evidence', () {
    final ayahs = sample(['اول', 'ثان', 'مكرر', 'مكرر']);
    expect(BudurVerseLinker.link(['"اول، ثان"'], [false], ayahs), [
      [1, 2]
    ]);
    expect(BudurVerseLinker.link(['"اول، مكرر"'], [false], ayahs), [[]]);
  });
  test('fingerprinted original quarter marker reopens only later independent headings', () {
    final path=Platform.environment['BUDUR_REFERENCE_SOURCE'];if(path==null)return;
    final src=File(path).readAsStringSync();
    final surah=Surah.fromJson(Map<String,dynamic>.from((jsonDecode(File('assets/data/surahs.json').readAsStringSync())as List)[1]));
    final ayahs=(jsonDecode(File('assets/data/surahs/2.json').readAsStringSync())as List).map((r)=>Ayah.fromRow(Map<String,dynamic>.from(r))).toList();
    final result=BudurSource.passages(src,surah,ayahs);
    expect(result[39].text,startsWith('الممال'));expect(result[39].ayahs,isEmpty);
    expect(result[46].text,startsWith('" الكبير "'));expect(result[46].ayahs,isEmpty);
    expect(result[50].text,startsWith('" أن يضرب "'));expect(result[50].ayahs,[26]);
    // A changed marker or neighbor cannot inherit the metadata grant.
    final changed=BudurSource.passages(src.replaceFirst('منتهى الربع بالإجماع.','منتهى الربع بالإجماع..'),surah,ayahs);
    expect(changed[50].ayahs,isEmpty);
  }, skip:Platform.environment['BUDUR_REFERENCE_SOURCE']==null?'Set original source path':false);
  test('actual source and shipped Quran corpus structural regression', () {
    final sourcePath = Platform.environment['BUDUR_REFERENCE_SOURCE'];
    if (sourcePath == null) return;
    final source = File(sourcePath).readAsStringSync();
    final surahs =
        (jsonDecode(File('assets/data/surahs.json').readAsStringSync()) as List)
            .map((r) => Surah.fromJson(Map<String, dynamic>.from(r)))
            .toList();
    var passages = 0, assigned = 0;
    for (final surah in surahs) {
      final ayahs = (jsonDecode(File('assets/data/surahs/${surah.id}.json')
              .readAsStringSync()) as List)
          .map((r) => Ayah.fromRow(Map<String, dynamic>.from(r)))
          .toList();
      final result = BudurSource.passages(source, surah, ayahs);
      expect(result, isNotEmpty, reason: 'missing chapter ${surah.id}');
      const actualBoth = <int, Map<String, List<int>>>{
        6: {
          'ذكر اسم الله': [118, 119],
          'آلذكرين': [143, 144]
        },
        7: {
          'تأتيهم': [163]
        },
        8: {
          'بالعدوة': [42]
        },
        98: {
          'البرية': [6, 7]
        },
        99: {
          'يره': [7, 8]
        },
      };
      for (final expected
          in (actualBoth[surah.id] ?? const <String, List<int>>{}).entries) {
        final q = BudurVerseLinker.normalize(expected.key);
        final entry = result.singleWhere((p) =>
            BudurVerseLinker.quotes(p.text).length == 1 &&
            BudurVerseLinker.quotes(p.text).single == q &&
            p.text.contains('معا'));
        expect(entry.ayahs, expected.value,
            reason: 'source both ${surah.id} ${expected.key}');
      }
      const reviewedListAyahs = <int, Map<String, List<int>>>{
        2: {
          "\" يؤاخذكم معا \" قرأ ورش وأبو جعفر بإبدال الهمزة واوا خالصة وصلا ووقفا، وحمزة كذلك عند الوقف فقط، ولا خلاف عن ورش في قصره، وكل من يمد حرف المد بعد الهمز استثناه. ولذلك قال ابن الجزري لا خلاف في استثناء يؤاخذ، فإن رواة المد مجمعون على استثنائه.": [225],
          "\" أولادهن رزقهن وكسوتهن \" وقف يعقوب عليه بهاء السكت.": [233],
          "\" فأرهبون وفاتقون \".\r\nقرأ يعقوب بإثبات ياء زائدة فيهما في الحالين، والباقون بالحذف كذلك.": [40, 41],
          "\" اليسر والعسر \" قرأ أبو جعفر بضم السين فيهما، والباقون بالإسكان.":
              [185],
          "\" فيغفر ويعذب \" قرأ الشامي وعاصم وأبو جعفر ويعقوب برفع الراء والباء من الفعلين والباقون بجزمهما.":
              [284],
        },
        3: {
          "\" نؤته منها معا \" قرأ قالون ويعقوب وهشام بخلف عنه بكسر الهاء من غير صلة، وقرأ شعبة والبصري وحمزة وأبو جعفر بإسكان الهاء والباقون بكسرها مع الصلة وهو الوجه الثاني لهشام، وأبدل الهمز ورش والسوسي وأبو جعفر مطلقا وكذلك حمزة عند الوقف.": [145],
          "\" قرح معا \" قرأ شعبة والأخوان وخلف بضم القاف والباقون بفتحها.": [140],
          "\" يؤده معا \" قرأ ورش وأبو جعفر بإبدال الهمزة ووا خالصة في الحالين وكذلك حمزة عند الوقف، وقرأ أبو عمرو وشعبة وحمزة وأبو جعفر بإسكان الهاء وصلا ووقفا. وقرأ قالون ويعقوب وهشام بخلف عنه بالقصر وقد يعبر عنه بالاختلاس، والمراد بالقصر أو الاختلاس في هذا الباب هاء الكناية الإتيان بالحركة كاملة من غير إشباع أي من غير صلة. وقرأ الباقون بالكسرة الكاملة مع الإشباع وهو الوجه الثاني لهشام، ولا يخفى أن من قرأ بالقصر أو الصلة فإنه يقف بالسكون، ومعلوم أن من يقرأ بالصلة يكون المد عنده من قبيل المنفصل فكل يمد حسب مذهبه.": [75],
          "\" تأمنه معا \" إبداله مطلقا وفي الوقف لا يخفى.": [75],
          "\" الميت معا \" قرأ ابن كثير وأبو عمرو وابن عامر وشعبة بتخفيف الياء ساكنة والباقون بتشديدها مكسورة.": [27],
          "\" عليهم الذلة وعليهم المسكنة \" ذكرنا مذاهب القراء فيهما وأمثالهما مرارا.": [112],
        },
        4: {
          "\" بأمانيكم وأماني \" قرأ أبو جعفر بتخفيف الياء ساكنة فيهما، والباقون بتشديدها مكسورة": [123],
          "\" تألمون معا ويألمون \" بالإبدال لورش والسوسي وأبي جعفر مطلقا، ولحمزة وقفا.": [104],
          "\" ندخله جنات، وندخله نارا \" قرأ نافع وأبو جعفر وابن عامر، بالنون فيهما، والباقون بالياء كذلك، ولا يخفى إخفاء أبي جعفر في نارا خالدا.": [13, 14],
          "\" خطأ معا \" لحمزة فيه وقفا التسهيل فقط.": [92],
          "\" فيوفيهم ويهديهم \" ضم الهاء فيهما يعقوب.": [173, 175],
          "\" وقتلهم الأنبياء. وأخذهم الربا \" تقدم مثلهما.": [155, 161],
          "\" نوله ونصله \" قرأ قالون ويعقوب وهشام بخلف عنه بكسر الهاء من غير صلة، وقرأ البصري وشعبة وحمزة وأبو جعفر بإسكانها، والباقون بكسرها مع الصلة، وهو الوجه الثاني لهشام.":
              [115],
        },
        5: {
          "\" يؤاخذكم معا \" قرأ ورش وأبو جعفر بابدال الهمزة واوا خالصة وصلا ووقفا وكذلك قرأ حمزة وقفا.": [89],
          "\" والمحصنات معا \" قرأ الكسائي بكسر الصاد، والباقون بفتحها.": [5],
          "\" والعين والأنف والأذن والسن والجروح \" قرأ نافع وعاصم وحمزة وخلف ويعقوب بنصب الكلمات الخمس وقرأ الكسائي برفعها، وقرأ المكي والبصري والشامي وأبو جعفر بنصب الأربع الأولى ورفع الجروح.": [45],
        },
        6: {
          "\" الميت معا \" قرأ نافع وحفص والأخوان ويعقوب وخلف وأبو جعفر بتشديد الياء مكسورة، والباقون بتخفيفها ساكنة.": [95],
          "\" ولا نكذب. ونكون \" قرأ حفص وحمزة ويعقوب بنصب الباء في الفعل الأول ونصب النون في الثاني. وقرأ ابن عامر بالرفع في الأول والنصب في الثاني. وقرأ الباقون بالرفع في الفعلين معا.": [27],
        },
        7: {
          "\" يتخذوه معا \" وصل المكي هاء الضمير.": [146],
          "\" مبصرون. يقصرون \" فيهما ترقيق الراء لورش.": [201, 202],
          "\" عليهم الطوفان. عليهم الرجز \" تقدم غير مرة.": [133, 134],
        },
        11: {
          "\" إني إذا. نصحي إن \" فتح الياء فيهما المدنيان والبصري، وأسكنها غيرهم.": [31, 34],
        },
        10: {
          "\" ولا أصغر ولا أكبر \" قرأ يعقوب وخلف وحمزة برفع الراء فيهما، والباقون بنصبها فيهما.":
              [61],
        },
        36: {
          "\" سدا، معا \" فتح السين فيهما حفص والأخوان وخلف، وضمها غيرهم.": [9],
        },
        39: {
          "\" وسيق معا \" قرأ ابن عامر والكسائي ورويس بإشمام كسرة السين الضم وغيره بالكسر الخالص.": [71, 73],
          "\" فتحت وفتحت \" خفف التاء فيهما الكوفيون وشددها غيرهم.": [71, 73],
        },
        40: {
          "\" واق هاد \" قرأ المكي بزيادة ياء بعد القاف والدال في الوقف فيهما والباقون بحذفها ولا خلاف بينهم في تنوينهما وصلا.": [21, 33],
        },
        58: {
          "\" اللائي \" سبق بسط الكلام عليه لجميع القراء وصلا ووقفا في سورة الأحزاب.": [2],
          "\" ومعصيت معا \" رسم بالتاء ووقف عليه بالهاء المكي والبصريان والكسائي وغيرهم بالتاء": [8, 9],
        },
        12: {
          "\" إني أراني معا \" فتح الياء المدنيان والبصري وأسكنها غيرهم.": [36],
          "\" غيابت الجب معا \" قرأ المدنيان بألف بعد الباء الموحدة على الجمع ووقفا بالتاء، والباقون نحذفها على الإفراد ووقف بالهاء المكي والبصريان والكسائي، والباقون بالتاء.": [10, 15],
          "\" أراني أعصر وأراني أحمل \" فتح الياء المدنيان والمكي والبصري وأسكنها غيرهم.": [36],
          "\" سنبلات خضر معا \" أخفى التنوين في الخاء مع الغنة أبو جعفر وأظهره غيره.": [43, 46],
        },
        14: {
          "\" نعمت الله معا \" رسم بالتاء ووقف عليهما بالهاء المكي والبصريان والكسائي وغيرهم بالتاء.": [28, 34],
        },
        16: {
          "\" إبراهيم معا \" قرأ هشام بفتح الهاء وألف بعدها وغيره بكسرها وياء بعدها.": [120, 123],
        },
        23: {
          "\" هيهات معا \" قرأ أبو جعفر بكسر التاء فيهما، والباقون بفتحها، ووقف عليهما بالهاء البزي والكسائي، والباقون بالتاء.": [36],
        },
        27: {
          "\" أنا آتيك معا \" أثبت ألف أنا وصلا المدنيان وحذفها غيرهما، واتفق العشرة على إثباتها وقفا.": [39, 40],
        },
        29: {
          "\" يبدئ وينشئ \" فيه لهشام وحمزة وقفا ما في \" يستهزئ\" في البقرة.": [19, 20],
          "\" رسلنا معا \" أسكن السين أبو عمرو وضمها غيره.": [31, 33],
        },
        30: {
          "\" الميت معا \" قرأ المدنيان والأخوان وحفص ويعقوب وخلف بالتشديد وغيرهم بالتخفيف.": [19],
        },
        46: {
          "\" كرها معا \" قرأ المدنيان والمكي والبصري وهشام بفتح الكاف، والباقون بضمها،": [15],
        },
        55: {
          "\" لم يطمثهن معا \" يؤخذ من الشاطبية أن للكسائي من روايتيه ثلاثة مذاهب، المذهب الأول: ضم اللفظ الأول وكسر الثاني من رواية الدوري وكسر الأول وضم الثاني من رواية أبي الحارث، ويؤخذ هذا المذهب من قوله. وكسر ميم يطمث إلخ وقوله: وقال به الليث في الثاني إلخ. وقد قرأ الداني بهذا المذهب على شيخه طاهر بن غلبون. المذهب الثاني: ضم الأول وكسر الثاني لكل من الدوري وأبي الحارث ويؤخذ هذا المذهب من قوله: وكسر ميم يطمث: وقوله: ونص الليث إلخ. والحاصل أنه لما أمر بضم الأول، أي مع كسر الثاني للدوري ثم أخبر بأن شيوخا ذهبوا إلى ضم الثاني وحده. أي مع كسر الأول لأبي الحارث ثم أخبر بأن النص عن أبي الحارث ورد بضم الأول تحصل منه المذهبان المذكوران فكأنه قال: اقرأ للدوري بضم الأول وكسر الثاني واقرأ الثاني واقرأ لأبي الحارث بأحد وجهين، ضم الثاني مع كسر الأول فيكون مخالفا للدوري في الموضعين، وهذا هو المذهب الأول. أو ضم الأول وكسر الثاني فيكون موافقا له فيهما وهذا هو المذهب الثاني وقد قرأ الداني بهذا المذهب على شيخه أبي الفتح فارس. المذهب الثالث التخيير لكل من الراويين في ضم أحدهما بمعنى أنه إذا ضم الأول كسر الثاني وإذا كسر الأول ضم الثاني ويؤخذ هذا المذهب من قوله: وقول الكسائي ضم أيهما تشاء وجيه إلخ ويؤخذ من مجموع المذاهب الثلاثة أنه لا يجوز للدوري ولا لأبي الحارث ضمهما معا ولا كسرهما معا بل لابد من التخالف بينهما في الضم والكسر فاذا ضم الأول تعين كسر الثاني وبالعكس. قال علماء القراءات وإذا أردت قراءتهما للكسائي وجمعهما في التلاوة فاقرأ الأول بالضم ثم الكسر والثاني بالكسر ثم الضم وقرأ الباقون بالكسر فيهما قولا واحدا.": [56, 74],
        },
        60: {
          "\" أسوة معا \" قرأ عاصم بضم الهمزة وغيره بكسر ما.": [4, 6],
        },
        67: {
          "\" السماء أن معا \" أبدل الثانية ياء خالصة المدنيان والمكي والبصري ورويس وحققها الباقون.": [16, 17],
        },
        69: {
          "\" حسابيه معا \" حذف يعقوب الهاء وصلا وأثبتها غيره كذلك ولا خلاف بينهم في إثباتها في الوقف.": [20, 26],
        },
        90: {
          "\" أيحسب معا \" فتح السين فيهما الشامي وعاصم وحمزة وأبو جعفر وكسرها غيرهم.": [5, 7],
        },
        96: {
          "\" اقرأ معا \" أبدل الهمز فيها مطلقا أبو جعفر وعند الوقف فقط حمزة.": [1, 3],
        },
        34: {
          "\" نحشرهم، نقول \" قرأ حفص ويعقوب بالياء التحتية فيهما والباقون بالنون فيهما.": [40],
        },
        45: {
          "\" آيات لقوم يوقنون، آيات لقوم يعقلون \" قرأ الأخوان ويعقوب بنصب التاء بالكسرة فيهما، والباقون برفعها كذلك.": [4, 5],
        },
        9: {
          "\" أسس بنيانه معا \" قرأ نافع وابن عامر بضم الهمزة وكسر السين الأولى في الموضعين ورفع نون بنيانه فيهما. والباقون بفتح الهمزة والسين الأولى في الموضعين ونصب بنيانه فيهما.": [109],
        },
        65: {
          "\" واللائي معا \" تقدم الكلام عليه مبسوطا في سورة الأحزاب.": [4],
        },
        33: {
          "\" اللائي \" قرأ قالون وقنبل ويعقوب بهمزة مكسورة من غير ياء بعدها وصلا ووقفا، ولهم في الوقف عليه ما لهم في الوقف على نحو السماء من الأوجه. وقرأ البزي وأبو عمرو وصلا بتسهيل الهمزة بين بين مع المد والقصر عنهما إبدال الهمزة ياء ساكنة مع المد المشبع لالتقاء الساكنين وصلا أيضا. فإذا وقفا كان لهما ثلاثة أوجه: تسهيل الهمزة بالروم مع المد والقصر وإبدالها ياء ساكنة مع المد المشبع لالتقاء الساكنين أيضا. وقرأ ورش وأبو جعفر بتسهيل الهمزة بين بين مع المد والقصر وصلا فإذا وقفا كان لهما ثلاثة أوجه أيضا: بتسهيل الهمزة بالروم مع المد والقصر، وإبدالها ياء ساكنة مع التطويل وكل على أصله في مقدار المد، وقرأ الشامي والكوفيون بهمزة مكسورة بعدها ياء ساكنة وصلا ووقفا وهم على أصولهم في المد ولحمزة في الوقف عليه تسهيل الهمزة مع المد والقصر.": [4],
        },
        64: {
          "\" يكفر. ويدخله \" قرأ المدنيان والشامي بالنون في الفعلين والباقون بالياء التحتية فيهما.":
              [9],
        },
        71: {
          "\" ويؤخركم لا يؤخر \" أبدل ورش وأبو جعفر الهمزة واوا خالصة مطلقا، وكذلك حمزة عند الوقف.":
              [4],
        },
        75: {
          "\" تحبون وتذرون \" قرأ المكي والبصريان والشامي بياء الغيبة فيهما، والباقون بتاء الخطاب كذلك.":
              [20, 21],
        },
        66: {
          "\" امرأت الثلاثة وابنت \" رسمت كلها بالتاء ووقف عليها بالهاء المكي والبصريان والكسائي، والباقون بالتاء.":
              [10, 11, 12],
        },
        18: {
          "\" فأتبع سببا ثم اتبع سببا معا \" قرأ الشامي والكوفيون بقطع الهمزة وإسكان التاء في الثلاثة وغيرهم بوصل الهمزة وتشديد التاء.": [85, 89, 92],
          "\" بربي أحدا معا \" و \" ربي أن \" فتح الياء المدنيان والمكي والبصري وأسكنها غيرهم.": [38, 40, 42],
          "\" وهيئ. ويهيئ \" أبدل الهمز فيهما أبو جعفر وحده في الحالين وهشام وحمزة في الوقف فقط.":
              [10, 16]
        },
        22: {
          "\" وليوفوا وليطوفوا \" قرأ ابن ذكوان بكسر اللام فيهما، والباقون بالإسكان. وقرأ شعبة بفتح الواو وتشديد الفاء من وليوفوا، والباقون بسكون الواو وتخفيف الفاء.":
              [29]
        },
      };
      for (final expected
          in (reviewedListAyahs[surah.id] ?? const <String, List<int>>{})
              .entries) {
        expect(result.singleWhere((p) => p.text == expected.key).ayahs,
            expected.value);
        final changedText = '${expected.key} UNREVIEWED_LIST_CHANGE';
        final changedSource = BudurSource.passages(
            source.replaceFirst(expected.key, changedText), surah, ayahs);
        expect(changedSource.singleWhere((p) => p.text == changedText).ayahs,
            isEmpty, reason: 'a reviewed list requires the exact original text');
        for (final missing in expected.value.toSet()) {
          final withoutVerse = BudurSource.passages(source, surah,
              ayahs.where((a) => a.ayahNumber != missing).toList());
          expect(withoutVerse.singleWhere((p) => p.text == expected.key).ayahs,
              isEmpty, reason: 'every listed Quran occurrence is required');
        }
        if (expected.key.startsWith('" الميت معا "')) {
          final a = ayahs.singleWhere((a) => a.ayahNumber == expected.value.single);
          // Negative fixture only. The actual Quran asset is never edited.
          final normalized = ' ${BudurVerseLinker.normalize(a.cleanTextUthmani)} ';
          final oneOccurrence = Ayah.fromRow({
            'id': a.id, 'surah_id': a.surahId, 'ayah_number': a.ayahNumber,
            'juz': a.juz, 'page': a.page,
            'text_uthmani': normalized.replaceFirst(' الميت ', ' '),
          });
          final altered = ayahs.map((v) => v.ayahNumber == a.ayahNumber
              ? oneOccurrence : v).toList();
          expect(BudurVerseLinker.occurrences('الميت', altered).length, 1);
          final refused = BudurSource.passages(source, surah, altered);
          expect(refused.singleWhere((p) => p.text == expected.key).ayahs,
              isEmpty, reason: 'both requires two occurrences, not two verses');
        }
      }
      if (surah.id == 66) {
        final reviewed = result
            .singleWhere((p) => p.text.startsWith('" امرأت الثلاثة وابنت "'));
        final changed = BudurSource.passages(
            source.replaceFirst(
                reviewed.text, '${reviewed.text} UNREVIEWED_CHANGE'),
            surah,
            ayahs);
        expect(
            changed
                .singleWhere((p) => p.text.contains('UNREVIEWED_CHANGE'))
                .ayahs,
            isEmpty);
        final noThird = BudurSource.passages(
            source, surah, ayahs.where((a) => a.ayahNumber != 11).toList());
        expect(
            noThird.singleWhere((p) => p.text == reviewed.text).ayahs, isEmpty,
            reason: 'all three source occurrences are required');
      }
      if (surah.id == 36) {
        final withoutEvidence = BudurSource.passages(
            source, surah, ayahs.where((a) => a.ayahNumber != 9).toList());
        final entry = withoutEvidence
            .singleWhere((p) => p.text.startsWith('" سدا، معا "'));
        expect(entry.ayahs, isEmpty,
            reason:
                'reviewed list still requires both actual Quran occurrences');
      }
      passages += result.length;
      assigned += result.where((p) => p.ayahs.isNotEmpty).length;
      for (final p in result) {
        expect(p.ayahs.every((n) => n > 0 && n <= surah.ayahCount), isTrue);
        expect(p.firstPage <= p.lastPage, isTrue);
        if (p.text.startsWith('الممال') || p.text.startsWith('المدغم'))
          expect(p.ayahs, isEmpty);
      }
      if (surah.id == 1) {
        expect(result.where((p) => p.text.startsWith('" الرحيم')).single.ayahs,
            [3]);
        expect(result.where((p) => p.text.startsWith('" الصراط')).single.ayahs,
            isEmpty); // rasm differs, not guessed
      }
      if (surah.id == 2) {
        final p =
            result.firstWhere((p) => p.text.startsWith('" الحساب " آخر الربع'));
        expect(p.text.contains('الأهلة'),
            isFalse); // next block must not inherit verse 202
        final block = result.firstWhere(
            (p) => p.text.startsWith('الممال') && p.text.contains('الأهلة'));
        expect(block.ayahs, isEmpty);
        final repeated =
            result.where((p) => p.text.startsWith('" عليهم')).toList();
        for (final p in repeated)
          expect(p.ayahs.every((a) => a != 9000), isTrue);
      }
    }
    print(
        'Actual-source navigation: $passages passages, $assigned assigned passages; count is not a correctness/coverage percentage.');
  },
      skip: Platform.environment['BUDUR_REFERENCE_SOURCE'] == null
          ? 'Set BUDUR_REFERENCE_SOURCE to the original downloaded text'
          : false);
}
