import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/core/audio/islamic_audio_catalog.dart';
import 'package:almomin/core/audio/islamic_audio_models.dart' as model;

void main() {
  test('catalog prefix retains every reviewed legacy field and order', () {
    const tracks = IslamicAudioService.allTracks;
    final snapshot = tracks.take(93).map((t) => [
      t.id, t.title, t.subtitle, t.type.name, t.assetPath, t.remoteUrl,
      t.fallbackUrls, t.durationFormatted, t.rawNotificationSound, t.quality,
      t.fileSizeBytes, t.categoryAr, t.muezzinName, t.imageUrl, t.surahNumber,
      t.reciterId, t.isBundled,
    ]).toList();
    final digest = sha256.convert(utf8.encode(jsonEncode(snapshot))).toString();
    expect(tracks, hasLength(323));
    expect(snapshot, hasLength(93));
    expect(digest, '93b19d01ae6b87f67faab8e8eea4bc696aa6695729428b2c7b7e9b5e67391882');
  });
  test('service retains the identical immutable const list and re-exported model types', () {
    const fromService = IslamicAudioService.allTracks;
    expect(identical(fromService, islamicAudioCatalog), isTrue);
    expect(() => fromService.clear(), throwsUnsupportedError);
    const IslamicAudioTrack compatible = model.IslamicAudioTrack(
      id: 'contract', title: 'title', subtitle: 'subtitle',
      type: model.IslamicAudioType.adhan, durationFormatted: '00:01',
    );
    expect(compatible.type, IslamicAudioType.adhan);
    expect(compatible.isBundled, isFalse);
    expect(compatible.fallbackUrls, isEmpty);
    expect(identical(PlaybackLoopMode.all, model.PlaybackLoopMode.all), isTrue);
    expect(identical(AudioClarityPreset.studioHd, model.AudioClarityPreset.studioHd), isTrue);
  });

  test('enum order and preset identifiers gains labels and fallback retain existing values', () {
    expect(IslamicAudioType.values.map((v) => v.name), ['adhan', 'iqamah', 'adhkar', 'tasbih', 'quran', 'story', 'lesson']);
    expect(PlaybackLoopMode.values.map((v) => v.name), ['off', 'all', 'single']);
    expect(AudioClarityPreset.values.map((v) => v.id), ['studio_hd', 'mosque_echo', 'warm_voice', 'clear_speech']);
    expect(AudioClarityPreset.values.map((v) => v.volumeGain), everyElement(1.0));
    for (final value in AudioClarityPreset.values) {
      expect(AudioClarityPreset.fromId(value.id), same(value));
    }
    expect(AudioClarityPreset.fromId('unknown'), AudioClarityPreset.studioHd);
  });

}
