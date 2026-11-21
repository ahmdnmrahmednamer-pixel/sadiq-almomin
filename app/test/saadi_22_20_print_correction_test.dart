import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

// Expected values: the printed Saadi p.536 reads "يصهر به ما في بطونهم"; the
// pre-correction chapter hash comes from the unchanged baseline (APK 0316).
const baselineSha = 'b75ad03f19a916b451dfcbdf698e8a0db7344875959866fec771194fa5c9a513';
void main() {
  test('Saadi 22:20 has the printed word and nothing else changed in surah 22', () {
    final bytes = GZipDecoder().decodeBytes(base64Decode(File('assets/data/tafsir_saadi_roots_22_1.b64').readAsStringSync().trim()));
    final text = utf8.decode(bytes);
    expect(text.contains('يصهر به ما في بطونهم'), isTrue);
    expect(text.contains('يصهر ما في بطونهم'), isFalse);
    expect('يصهر به ما في بطونهم'.allMatches(text).length, 1);
    final reverted = text.replaceFirst('يصهر به ما في بطونهم', 'يصهر ما في بطونهم');
    expect(sha256.convert(utf8.encode(reverted)).toString(), baselineSha, reason: 'only the one word may differ from the baseline');
    final m = jsonDecode(File('assets/data/tafsir_saadi_roots_manifest.json').readAsStringSync()) as Map;
    expect(m['surahs']['22']['sha256'], sha256.convert(bytes).toString());
  });
}
