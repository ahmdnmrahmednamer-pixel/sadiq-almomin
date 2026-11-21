import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/services/budur_source.dart';
import '../lib/core/models/ayah.dart';
import '../lib/core/models/surah.dart';
void main() {
 test('nine source-grounded quarter ends release the reviewed 71 keys', () {
 final src = utf8.decode(gzip.decode(File('assets/data/budur-original.gz').readAsBytesSync()));
 final source = src.substring(0,src.indexOf('تصويبات للشيخ'));
 final chapters = (jsonDecode(File('assets/data/surahs.json').readAsStringSync()) as List).map((r)=>Surah.fromJson(Map<String,dynamic>.from(r)));
 final out = <String>[];
 final inventory = <Map<String,dynamic>>[];
 for (final s in chapters) {
 final verses=(jsonDecode(File('assets/data/surahs/${s.id}.json').readAsStringSync()) as List).map((r)=>Ayah.fromRow(Map<String,dynamic>.from(r))).toList();
 final ps=BudurSource.passages(source,s,verses);
 for(var n=0;n<ps.length;n++) {
 final p=ps[n];
 inventory.add({'surah':s.id,'n':n,'text':p.text,'assigned':p.ayahs});
 if(p.ayahs.isNotEmpty) out.add('${s.id}:$n=${p.ayahs.join(",")}');
 }
 }
 final assigned = {for (final e in inventory) '${e['surah']}:${e['n']}': (e['assigned'] as List<int>)};
 // Expected values transcribed from the independent per-key source ledger,
 // not inferred from the runtime dump being tested.
 final expected = <String, List<int>>{
  '5:152': [110],
  '5:154': [110],
  '5:158': [110],
  '5:159': [112],
  '5:162': [115],
  '5:163': [115],
  '5:165': [116],
  '5:166': [116],
  '5:168': [117],
  '5:170': [119],
  '6:22': [14],
  '6:23': [15],
  '6:24': [16],
  '6:25': [19],
  '6:26': [19],
  '6:27': [19],
  '6:30': [23],
  '6:31': [23],
  '6:32': [25],
  '6:37': [32],
  '6:39': [33],
  '6:40': [33],
  '6:42': [35],
  '6:43': [35],
  '7:111': [117],
  '7:112': [117],
  '7:113': [118],
  '7:115': [127],
  '7:118': [137],
  '7:119': [137],
  '7:120': [138],
  '7:121': [141],
  '7:122': [141],
  '7:127': [142],
  '7:128': [143],
  '7:129': [143],
  '7:130': [143],
  '7:131': [143],
  '7:132': [144],
  '7:133': [144],
  '7:136': [146],
  '7:138': [147],
  '7:139': [148],
  '7:141': [149],
  '7:142': [150],
  '7:143': [150],
  '7:145': [150],
  '7:146': [155],
  '7:147': [155],
  '17:86': [99],
  '17:87': [100],
  '17:89': [102],
  '17:90': [102],
  '17:91': [110],
  '33:50': [51],
  '33:52': [52],
  '33:53': [52],
  '33:54': [53],
  '33:55': [53],
  '33:61': [60],
  '33:62': [66],
  '33:63': [67],
  '33:64': [68],
  '42:9': [13],
  '42:10': [13],
  '42:12': [20],
  '42:13': [21],
  '42:14': [23],
  '42:17': [25],
  '47:24': [34],
  '47:25': [35],
};
 for (final e in expected.entries) {
   expect(assigned[e.key], e.value, reason: e.key);
 }
 // True summary labels and the two unpromoted special-end blocks must not
 // become ordinary verse links as a side effect of these nine grants.
 for (final key in ['5:147','5:148','7:107','7:108','12:34','15:11']) {
   expect(assigned[key], isEmpty, reason: key);
 }
 });
}
