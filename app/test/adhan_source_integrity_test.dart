import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:almomin/core/notifications/prayer_notification_service.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const tracks = IslamicAudioService.allTracks;
  IslamicAudioTrack byId(String id) => tracks.singleWhere((t) => t.id == id);

  test('reviewed named voices use individually sourced adhan recordings', () {
    const expected = <String, String>{
      'adhan_hussary': 'https://dl2.islamweb.net/Audio3/Adan/1030.mp3',
      'adhan_menshawi': 'https://media.assabile.com/assabile/adhan_3435370/a2b25725149e.mp3',
      'adhan_naqshbandi': 'https://media.myhuda.com/download/files/media/11-Anasheed/2-Naqshab_Tawasheeh/11.mp3',
      'adhan_alqatami': 'https://dl2.islamweb.net/Audio3/Adan/317311.mp3',
      'adhan_amr_sobhi': 'https://dl2.islamweb.net/Audio3//Adan/428132.mp3',
      'adhan_wadih_alyamani': 'https://dl2.islamweb.net/Audio3/Adan/425434.mp3',
    };
    for (final entry in expected.entries) {
      expect(byId(entry.key).remoteUrl, entry.value, reason: entry.key);
      expect(byId(entry.key).fallbackUrls, isEmpty,
          reason: 'Do not substitute another recording under the same selection.');
    }
  });

  test('new catalog voices have distinct sourced recordings and honest native limits', () {
    const expected = {
      'adhan_jamal_aljaafari': ('https://dl2.islamweb.net/Audio3/Adan/416974.mp3', 2680899, '02:43'),
      'adhan_ihsan_aldulaimi': ('https://dl2.islamweb.net/Audio3/Adan/421877.mp3', 3481306, '03:33'),
    };
    for (final entry in expected.entries) {
      final track = byId(entry.key);
      expect(track.remoteUrl, entry.value.$1);
      expect(track.fileSizeBytes, entry.value.$2);
      expect(track.durationFormatted, entry.value.$3);
      expect(track.assetPath, isNull);
      expect(track.rawNotificationSound, isNull);
      expect(track.fallbackUrls, isEmpty);
      expect(track.quality, isNot(contains('HD')));
      expect(IslamicAudioService.unavailableRecordingReason(track.id), isNull);
      expect(PrayerNotificationService.adhanAssignmentUnavailableReason(track.id), isNotNull);
      expect(tracks.where((t) => t.remoteUrl == track.remoteUrl), hasLength(1));
    }
    expect(tracks.map((t) => t.id).toSet(), hasLength(tracks.length));
  });

  test('adhan sources never substitute a Quran surah', () {
    for (final track in tracks.where((t) => t.type == IslamicAudioType.adhan)) {
      final urls = [if (track.remoteUrl != null) track.remoteUrl!, ...track.fallbackUrls];
      for (final url in urls) {
        expect(Uri.parse(url).host.endsWith('mp3quran.net'), isFalse,
            reason: '${track.id} must not fall back to a surah as adhan');
      }
    }
  });

  test('reviewed historical recordings do not invent an HD quality claim', () {
    for (final id in ['adhan_hussary', 'adhan_menshawi', 'adhan_naqshbandi', 'adhan_alqatami', 'adhan_wadih_alyamani']) {
      expect(byId(id).quality, isNot(contains('HD')), reason: id);
      expect(byId(id).quality, isNot(contains('320')), reason: id);
      expect(byId(id).durationFormatted, isNotEmpty);
      expect(byId(id).fileSizeBytes, greaterThan(0));
    }
  });

  test('unavailable adhan cannot reach playback preview or download', () async {
    final service = IslamicAudioService.forTesting(_UnusedPlayer());
    final track = byId('adhan_haza_albalushi');
    try {
      expect(track.remoteUrl, isNull);
      expect(track.fallbackUrls, isEmpty);
      expect(IslamicAudioService.unavailableRecordingReason(track.id), isNotNull);
      expect(await service.playOnlinePreview(track), isFalse);
      expect(await service.downloadTrack(track.id), isFalse);
      await service.playTrack(track);
      expect(service.currentTrack, isNull);
      expect(service.heldLegacyTrack?.id, track.id);
      await service.playQueue([track]);
      expect(service.currentTrack, isNull);
      expect(service.isPlaying, isFalse);
    } finally {
      service.dispose();
    }
  });

  test('corrected recordings use new download filenames without deleting old files', () {
    for (final id in ['adhan_hussary', 'adhan_menshawi', 'adhan_naqshbandi', 'adhan_alqatami', 'adhan_wadih_alyamani']) {
      expect(IslamicAudioService.downloadFileNameForTrack(id), '$id.20261121.mp3');
      expect(IslamicAudioService.downloadFileNameForTrack(id), isNot('$id.mp3'));
    }
    expect(IslamicAudioService.downloadFileNameForTrack('adhan_makkah'), 'adhan_makkah.mp3');
  });

  test('unavailable stored file is retained and counted but never exposed for playback', () async {
    final dir = await Directory.systemTemp.createTemp('adhan-unavailable-');
    final service = IslamicAudioService.forTesting(_UnusedPlayer());
    try {
      final stored = File('${dir.path}/adhan_haza_albalushi.mp3')..writeAsBytesSync(List.filled(2048, 5));
      await service.scanDownloadsForTesting(dir);
      expect(service.totalDownloadedBytes, 2048);
      expect(service.isDownloaded('adhan_haza_albalushi'), isFalse);
      expect(service.getLocalAudioPath('adhan_haza_albalushi'), isNull);
      expect(stored.readAsBytesSync(), everyElement(5));
    } finally {
      service.dispose();
      await dir.delete(recursive: true);
    }
  });

  test('storage scan ignores old named files, retains bytes, and recognizes revised downloads', () async {
    final dir = await Directory.systemTemp.createTemp('adhan-recording-revision-');
    final service = IslamicAudioService.forTesting(_UnusedPlayer());
    try {
      final legacy = File('${dir.path}/adhan_hussary.mp3');
      final reviewed = File('${dir.path}/${IslamicAudioService.downloadFileNameForTrack('adhan_hussary')}');
      final unchanged = File('${dir.path}/adhan_makkah.mp3');
      legacy.writeAsBytesSync(List.filled(2048, 7));
      unchanged.writeAsBytesSync(List.filled(2048, 8));
      await service.scanDownloadsForTesting(dir);
      expect(service.totalDownloadedBytes, 4096);
      expect(service.isDownloaded('adhan_hussary'), isFalse);
      expect(service.getLocalAudioPath('adhan_hussary'), isNull);
      expect(service.isDownloaded('adhan_makkah'), isTrue);
      expect(legacy.readAsBytesSync(), everyElement(7));
      reviewed.writeAsBytesSync(List.filled(4096, 9));
      await service.scanDownloadsForTesting(dir);
      expect(service.isDownloaded('adhan_hussary'), isTrue);
      expect(service.getLocalAudioPath('adhan_hussary'), reviewed.path);
      expect(legacy.existsSync(), isTrue);
      expect(legacy.readAsBytesSync(), everyElement(7));
      expect(service.totalDownloadedBytes, 8192);
      expect(await service.deleteDownloadedTrack('adhan_hussary'), isTrue);
      expect(legacy.existsSync(), isFalse);
      expect(reviewed.existsSync(), isFalse);
      expect(unchanged.existsSync(), isTrue);
      expect(service.totalDownloadedBytes, 2048);
    } finally {
      service.dispose();
      await dir.delete(recursive: true);
    }
  });

}


class _UnusedPlayer extends Fake implements AudioPlayer {
  @override
  Future<void> dispose() async {}
}
