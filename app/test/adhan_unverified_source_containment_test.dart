import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/core/notifications/prayer_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const held = [
    'adhan_azhar', 'adhan_morocco_qarawiyyin', 'adhan_tunis_zaytouna',
    'adhan_khalil_aqsa', 'adhan_fatih_istanbul', 'adhan_alzamil',
    'adhan_fares_abbad', 'adhan_sudais', 'adhan_shuraim', 'adhan_bosnia',
  ];
  test('unavailable or conflicting sources retain identity without playable candidates', () {
    for (final id in held) {
      final track = IslamicAudioService.allTracks.singleWhere((t) => t.id == id);
      expect(track.remoteUrl, isNull, reason: id);
      expect(track.fallbackUrls, isEmpty, reason: id);
      expect(IslamicAudioService.isHeldRecording(track), isTrue, reason: id);
      expect(IslamicAudioService.unavailableRecordingReason(id), contains('مواعيد التذكير محفوظة'));
      expect(PrayerNotificationService.adhanAssignmentUnavailableReason(id), isNotNull);
    }
    for (final id in ['adhan_makkah', 'adhan_hussary', 'adhan_cairo_refaat', 'adhan_madinah', 'adhan_aqsa']) {
      expect(IslamicAudioService.unavailableRecordingReason(id), isNull);
    }
  });

  test('held downloaded bytes remain counted, preserved, and inaccessible to playback', () async {
    final service = IslamicAudioService.forTesting(_UnusedPlayer());
    final dir = await Directory.systemTemp.createTemp('adhan-source-hold-');
    try {
      for (final id in held) {
        File('${dir.path}/$id.mp3').writeAsBytesSync(List.filled(2048, 3));
      }
      await service.scanDownloadsForTesting(dir);
      expect(service.totalDownloadedBytes, held.length * 2048);
      for (final id in held) {
        final track = IslamicAudioService.allTracks.singleWhere((t) => t.id == id);
        expect(service.isDownloaded(id), isFalse);
        expect(service.getLocalAudioPath(id), isNull);
        expect(await service.downloadTrack(id), isFalse);
        expect(await service.playOnlinePreview(track), isFalse);
        await service.playTrack(track);
        expect(service.currentTrack, isNull);
        expect(service.isPlaying, isFalse);
        expect(File('${dir.path}/$id.mp3').readAsBytesSync(), everyElement(3));
      }
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
