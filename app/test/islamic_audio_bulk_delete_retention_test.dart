import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'bulk delete retains current and retired files independently after errors',
      () async {
    final service = IslamicAudioService.instance;
    for (final retained in ['both', 'current', 'retired']) {
      final dir =
          Directory.systemTemp.createTempSync('islamic-bulk-retention-');
      const id = 'adhan_hussary';
      final current = File(
          '${dir.path}/${IslamicAudioService.downloadFileNameForTrack(id)}')
        ..writeAsBytesSync(List.filled(4096, 1));
      final retired = File('${dir.path}/$id.mp3')
        ..writeAsBytesSync(List.filled(2048, 1));
      final missing = File('${dir.path}/adhkar_morning.mp3')
        ..writeAsBytesSync(List.filled(1024, 1));
      final snapshots = <int>[];
      void listener() => snapshots.add(service.totalDownloadedBytes);
      try {
        await service.scanDownloadsForTesting(dir);
        expect(service.totalDownloadedBytes, 7168);
        expect(service.isDownloaded(id), isTrue);
        missing.deleteSync();
        if (retained == 'current') retired.deleteSync();
        if (retained == 'retired') current.deleteSync();
        expect(Process.runSync('chmod', ['0555', dir.path]).exitCode, 0);
        service.addListener(listener);
        final expected = retained == 'both'
            ? 6144
            : retained == 'current'
                ? 4096
                : 2048;
        await service.deleteAllDownloadedTracks();
        expect(service.totalDownloadedBytes, expected,
            reason: 'Failed current/retired deletion must retain its own size');
        expect(current.existsSync(), retained != 'retired');
        expect(retired.existsSync(), retained != 'current');
        expect(service.isDownloaded(id), retained != 'retired');
        expect(service.getLocalAudioPath(id),
            retained == 'retired' ? null : current.path);
        expect(service.isDownloaded('adhkar_morning'), isFalse);
        expect(snapshots, [expected]);
        expect(Process.runSync('chmod', ['0755', dir.path]).exitCode, 0);
        await service.deleteAllDownloadedTracks();
        expect(current.existsSync(), isFalse);
        expect(retired.existsSync(), isFalse);
        expect(service.totalDownloadedBytes, 0);
        expect(service.getDownloadedTracks(), isEmpty);
        expect(snapshots, [expected, 0]);
        await service.deleteAllDownloadedTracks();
        expect(service.totalDownloadedBytes, 0);
      } finally {
        service.removeListener(listener);
        Process.runSync('chmod', ['0755', dir.path]);
        await service.deleteAllDownloadedTracks();
        dir.deleteSync(recursive: true);
      }
    }
  });
}
