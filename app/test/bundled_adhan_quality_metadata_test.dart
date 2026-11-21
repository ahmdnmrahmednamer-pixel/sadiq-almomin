import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/core/audio/islamic_audio_catalog.dart';

// Read the first MPEG-1 Layer III audio frame, skipping the ID3 tag. Encoding
// is measurable; it does not authenticate the voice or certify listening quality.
int firstFrameKbps(List<int> bytes) {
  var start = 0;
  if (bytes.length >= 10 &&
      bytes[0] == 73 &&
      bytes[1] == 68 &&
      bytes[2] == 51) {
    start = 10 +
        ((bytes[6] & 127) << 21) +
        ((bytes[7] & 127) << 14) +
        ((bytes[8] & 127) << 7) +
        (bytes[9] & 127);
  }
  const rates = [
    0,
    32,
    40,
    48,
    56,
    64,
    80,
    96,
    112,
    128,
    160,
    192,
    224,
    256,
    320,
    0
  ];
  for (var i = start; i + 3 < bytes.length; i++) {
    if (bytes[i] == 255 && bytes[i + 1] & 254 == 250) {
      final rate = rates[bytes[i + 2] >> 4];
      if (rate > 0) return rate;
    }
  }
  throw StateError('No MPEG-1 Layer III frame');
}

void main() {
  const ids = [
    'adhan_makkah',
    'adhan_madinah',
    'adhan_aqsa',
    'adhan_cairo_refaat',
    'adhan_hussary',
    'adhan_fajr'
  ];
  for (final id in ids) {
    test('$id describes measured bundled encoding, not an invented HD master',
        () {
      final track = islamicAudioCatalog.singleWhere((t) => t.id == id);
      final kbps = firstFrameKbps(File(track.assetPath!).readAsBytesSync());
      expect(kbps, 56);
      expect(track.quality, contains('مدمج'));
      expect(track.quality, contains('$kbps'));
      expect(track.quality, contains('أحادي'));
      expect(track.quality, isNot(contains('HD')));
      expect(track.quality, isNot(contains('192')));
      expect(track.quality, isNot(contains('نقي')));
      expect(track.rawNotificationSound, isNotNull);
    });
  }
}
