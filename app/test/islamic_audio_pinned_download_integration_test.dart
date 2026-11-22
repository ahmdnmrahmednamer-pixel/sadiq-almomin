import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/core/services/islamic_audio_file_integrity.dart';
import 'package:almomin/core/audio/fast_audio_service.dart';
import 'islamic_audio_failed_focus_fallback_test.dart' as playback;
import 'islamic_audio_download_race_test.dart' as http;

class PinnedProbePlayer extends playback.FallbackProbePlayer {
  final paths = <String>[];
  PinnedProbePlayer() {
    takeoverOnVolume = false;
  }
  @override
  Future<Duration?> setFilePath(String path,
      {bool preload = true, Duration? initialPosition, dynamic tag}) async {
    paths.add(path);
    return const Duration(seconds: 1);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final bytes = Uint8List.fromList(List.generate(4096, (i) => i % 251));
  final digest = sha1.convert([
    ...utf8.encode('blob ${bytes.length}\u0000'),
    ...bytes,
  ]).toString();
  late Directory root;
  late Directory audio;
  late IslamicAudioService service;
  late PinnedProbePlayer player;
  HttpOverrides? previous;
  Future<void> Function(IslamicAudioTrack, File)? beforeCheck;
  Future<void> Function(IslamicAudioTrack, File)? afterCheck;
  var checks = 0;
  var disposed = false;

  IslamicAudioTrack track(String id,
          {bool pinned = true, bool remote = true}) =>
      IslamicAudioTrack(
        id: id,
        title: id,
        subtitle: '',
        type: IslamicAudioType.adhan,
        durationFormatted: '',
        remoteUrl: remote ? 'https://fixture.invalid/$id.mp3' : null,
        remoteGitBlobSha1: pinned ? digest : null,
        fileSizeBytes: pinned ? bytes.length : 999999,
      );
  File file(String id) =>
      File('${audio.path}/${IslamicAudioService.downloadFileNameForTrack(id)}');
  void response(List<int> data) {
    http.DynamicHttpOverrides.activeHandler = (method, url, req) async =>
        http.TestHttpClientResponse(Stream.value(data),
            contentLength: data.length);
  }

  List<File> temps() => audio
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.tmp'))
      .toList();

  setUp(() {
    previous = HttpOverrides.current;
    HttpOverrides.global = http.DynamicHttpOverrides();
    SharedPreferences.setMockInitialValues({});
    root = Directory.systemTemp.createTempSync('audio-integrity-integration-');
    audio = Directory('${root.path}/adhkar_audio')..createSync();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => call.method == 'getApplicationDocumentsDirectory'
                ? root.path
                : null);
    beforeCheck = null;
    afterCheck = null;
    checks = 0;
    disposed = false;
    FastAudioService.instance.resetForTesting();
    player = PinnedProbePlayer();
    service = IslamicAudioService.forTesting(
      player,
      catalog: [track('pin'), track('pin2'), track('legacy', pinned: false)],
      fileValidator: (track, file) async {
        checks++;
        await beforeCheck?.call(track, file);
        final checked = await validatedAudioFileStat(track, file);
        await afterCheck?.call(track, file);
        return checked;
      },
    )..disableNativePlayerForTesting = true;
    response(bytes);
  });
  tearDown(() async {
    if (!disposed) {
      await service.deleteAllDownloadedTracks();
      service.dispose();
    }
    FastAudioService.instance.resetForTesting();
    http.DynamicHttpOverrides.activeHandler = null;
    HttpOverrides.global = previous;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('a completed asynchronous scan publishes one coherent notification',
      () async {
    final snapshots = <List<int>>[];
    service.addListener(() {
      snapshots.add([
        service.getDownloadedTracks().length,
        service.unverifiedRecordingCount
      ]);
    });
    file('pin').writeAsBytesSync(bytes);
    await service.init();
    expect(snapshots, [
      [1, 0]
    ]);
    file('pin2').writeAsBytesSync(Uint8List(3000));
    await service.scanDownloadsForTesting(audio);
    expect(snapshots, [
      [1, 0],
      [1, 1]
    ]);
  });

  test(
      'zero and short scanned pinned files stay counted and explicitly deletable',
      () async {
    for (final size in [0, 1000]) {
      file('pin').writeAsBytesSync(Uint8List(size));
      await service.scanDownloadsForTesting(audio);
      expect(service.isDownloaded('pin'), isFalse);
      expect(service.unverifiedRecordingCount, 1);
      expect(service.totalDownloadedBytes, size);
      expect(await service.deleteDownloadedTrack('pin'), isTrue);
      expect(file('pin').existsSync(), isFalse);
    }
  });

  test('disposing during a scan cannot publish or notify after disposal',
      () async {
    await service.init();
    file('pin').writeAsBytesSync(bytes);
    final entered = Completer<void>();
    final release = Completer<void>();
    beforeCheck = (track, target) async {
      entered.complete();
      await release.future;
    };
    final scan = service.scanDownloadsForTesting(audio);
    await entered.future;
    disposed = true;
    service.dispose();
    release.complete();
    await scan;
    expect(service.getDownloadedTracks(), isEmpty);
  });

  test(
      'disposing during download validation cannot publish or notify afterwards',
      () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    beforeCheck = (track, target) async {
      entered.complete();
      await release.future;
    };
    final pending = service.downloadTrack('pin');
    await entered.future;
    disposed = true;
    service.dispose();
    release.complete();
    expect(await pending, isFalse);
    expect(file('pin').existsSync(), isFalse);
    expect(temps(), isEmpty);
  });

  test(
      'public playback hashes canonical bytes before assigning the native file',
      () async {
    expect(await service.downloadTrack('pin'), isTrue);
    final prior = checks;
    service.disableNativePlayerForTesting = false;
    await service.playTrack(track('pin', pinned: false, remote: false));
    expect(checks, prior + 1);
    expect(player.paths, [file('pin').path]);
    expect(player.plays, 1);
  });

  test(
      'public playback never assigns corrupted local bytes using caller metadata',
      () async {
    expect(await service.downloadTrack('pin'), isTrue);
    final entered = Completer<void>();
    final release = Completer<void>();
    beforeCheck = (track, target) async {
      entered.complete();
      await release.future;
    };
    service.disableNativePlayerForTesting = false;
    final playing =
        service.playTrack(track('pin', pinned: false, remote: false));
    await entered.future;
    file('pin').writeAsBytesSync(Uint8List(bytes.length));
    release.complete();
    await playing;
    expect(player.paths, isEmpty);
    expect(player.plays, 0);
    expect(service.getLocalAudioPath('pin'), isNull);
  });

  test('stop during the playback hash cannot later start the old selection',
      () async {
    expect(await service.downloadTrack('pin'), isTrue);
    final entered = Completer<void>();
    final release = Completer<void>();
    beforeCheck = (track, target) async {
      entered.complete();
      await release.future;
    };
    service.disableNativePlayerForTesting = false;
    final playing = service.playTrack(track('pin', remote: false));
    await entered.future;
    await service.stop();
    release.complete();
    await playing;
    expect(player.paths, isEmpty);
    expect(player.plays, 0);
  });

  test('a post-hash file change cannot pass the final publication snapshot',
      () async {
    afterCheck = (track, target) async {
      target.writeAsBytesSync(Uint8List(5000));
    };
    expect(await service.downloadTrack('pin'), isFalse);
    expect(file('pin').existsSync(), isFalse);
    expect(temps(), isEmpty);
  });

  test('a post-hash file change cannot pass the final playback snapshot',
      () async {
    expect(await service.downloadTrack('pin'), isTrue);
    afterCheck = (track, target) async {
      target.writeAsBytesSync(Uint8List(5000));
    };
    expect(await service.validateLocalAudioPathForTesting('pin'), isNull);
    expect(service.isDownloaded('pin'), isFalse);
  });

  test('matching pinned source bytes become a usable offline download',
      () async {
    expect(await service.downloadTrack('pin'), isTrue);
    expect(service.isDownloaded('pin'), isTrue);
    expect(file('pin').readAsBytesSync(), bytes);
    expect(service.getLocalAudioPath('pin'), file('pin').path);
    expect(service.totalDownloadedBytes, bytes.length);
    expect(service.unverifiedRecordingCount, 0);
    expect(temps(), isEmpty);
  });

  test(
      'same-size substitution is not published after a successful HTTP response',
      () async {
    response(Uint8List(bytes.length));
    expect(await service.downloadTrack('pin'), isFalse);
    expect(file('pin').existsSync(), isFalse);
    expect(service.isDownloaded('pin'), isFalse);
    expect(service.isDownloading('pin'), isFalse);
    expect(service.totalDownloadedBytes, 0);
    expect(temps(), isEmpty);
  });

  test('wrong byte counts never publish pinned audio', () async {
    for (final n in [2048, 8192]) {
      response(Uint8List(n));
      expect(await service.downloadTrack('pin'), isFalse);
      expect(file('pin').existsSync(), isFalse);
      expect(temps(), isEmpty);
    }
  });

  test('an invalid replacement preserves an existing verified copy', () async {
    expect(await service.downloadTrack('pin'), isTrue);
    response(Uint8List(bytes.length));
    expect(await service.downloadTrack('pin'), isFalse);
    expect(file('pin').readAsBytesSync(), bytes);
    expect(service.isDownloaded('pin'), isTrue);
    expect(service.totalDownloadedBytes, bytes.length);
    expect(temps(), isEmpty);
  });

  test(
      'startup scans verify pinned bytes and count invalid, legacy and retired storage',
      () async {
    file('pin').writeAsBytesSync(bytes);
    file('pin2').writeAsBytesSync(Uint8List(3000));
    file('legacy').writeAsBytesSync(Uint8List(1510));
    final retired = File('${audio.path}/adhan_hussary.mp3')
      ..writeAsBytesSync(Uint8List(2000));
    final unrelated = File('${audio.path}/keep.txt')..writeAsString('keep');
    await service.init();
    expect(service.getDownloadedTracks().map((t) => t.id), ['pin', 'legacy']);
    expect(service.unverifiedRecordingCount, 1);
    expect(service.retiredRecordingCount, 1);
    expect(service.totalDownloadedBytes, bytes.length + 3000 + 1510 + 2000);
    expect(file('pin2').existsSync(), isTrue);
    expect(await service.deleteAllDownloadedTracks(), isTrue);
    expect(file('pin2').existsSync(), isFalse);
    expect(retired.existsSync(), isFalse);
    expect(unrelated.readAsStringSync(), 'keep');
    expect(service.totalDownloadedBytes, 0);
  });

  test('a rejected scanned file remains available for explicit deletion',
      () async {
    file('pin').writeAsBytesSync(Uint8List(bytes.length));
    await service.init();
    expect(service.isDownloaded('pin'), isFalse);
    expect(service.getLocalAudioPath('pin'), isNull);
    expect(service.unverifiedRecordingCount, 1);
    expect(service.totalDownloadedBytes, bytes.length);
    expect(await service.deleteDownloadedTrack('pin'), isTrue);
    expect(file('pin').existsSync(), isFalse);
    expect(service.unverifiedRecordingCount, 0);
  });

  test(
      'a changed file loses cached eligibility until downloaded and checked again',
      () async {
    expect(await service.downloadTrack('pin'), isTrue);
    file('pin').writeAsBytesSync(Uint8List(5000));
    expect(service.isDownloaded('pin'), isFalse);
    expect(service.getLocalAudioPath('pin'), isNull);
    expect(service.unverifiedRecordingCount, 1);
    expect(service.totalDownloadedBytes, 5000);
    expect(await service.downloadTrack('pin'), isTrue);
    expect(service.isDownloaded('pin'), isTrue);
    expect(service.totalDownloadedBytes, bytes.length);
  });

  test('actual playback eligibility hashes again, not only the cached stat',
      () async {
    expect(await service.downloadTrack('pin'), isTrue);
    final before = checks;
    expect(await service.validateLocalAudioPathForTesting('pin'),
        file('pin').path);
    expect(checks, before + 1);
    final entered = Completer<void>();
    final release = Completer<void>();
    beforeCheck = (track, target) async {
      entered.complete();
      await release.future;
    };
    final pending = service.validateLocalAudioPathForTesting('pin');
    await entered.future;
    file('pin').writeAsBytesSync(Uint8List(bytes.length));
    release.complete();
    expect(await pending, isNull);
    expect(service.isDownloaded('pin'), isFalse);
  });

  test('cancelling during validation preserves the preceding verified file',
      () async {
    expect(await service.downloadTrack('pin'), isTrue);
    final entered = Completer<void>();
    final release = Completer<void>();
    beforeCheck = (track, target) async {
      entered.complete();
      await release.future;
    };
    final pending = service.downloadTrack('pin');
    await entered.future;
    service.cancelDownload('pin');
    release.complete();
    expect(await pending, isFalse);
    expect(file('pin').readAsBytesSync(), bytes);
    expect(service.isDownloaded('pin'), isTrue);
    expect(temps(), isEmpty);
  });

  test('cancelled validation cannot remove a newer successful attempt',
      () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    var first = true;
    beforeCheck = (track, target) async {
      if (first) {
        first = false;
        entered.complete();
        await release.future;
      }
    };
    final old = service.downloadTrack('pin');
    await entered.future;
    service.cancelDownload('pin');
    expect(await service.downloadTrack('pin'), isTrue);
    release.complete();
    expect(await old, isFalse);
    expect(service.isDownloaded('pin'), isTrue);
    expect(file('pin').readAsBytesSync(), bytes);
    expect(temps(), isEmpty);
  });

  for (final all in [false, true]) {
    test(
        'explicit ${all ? 'bulk' : 'single'} deletion cannot be undone by pending validation',
        () async {
      expect(await service.downloadTrack('pin'), isTrue);
      final entered = Completer<void>();
      final release = Completer<void>();
      beforeCheck = (track, target) async {
        entered.complete();
        await release.future;
      };
      final pending = service.downloadTrack('pin');
      await entered.future;
      expect(
          await (all
              ? service.deleteAllDownloadedTracks()
              : service.deleteDownloadedTrack('pin')),
          isTrue);
      release.complete();
      expect(await pending, isFalse);
      expect(file('pin').existsSync(), isFalse);
      expect(service.isDownloaded('pin'), isFalse);
      expect(service.totalDownloadedBytes, 0);
      expect(temps(), isEmpty);
    });
  }

  test('a stale scan cannot overwrite a newer successful download', () async {
    expect(await service.downloadTrack('pin'), isTrue);
    final entered = Completer<void>();
    final release = Completer<void>();
    var first = true;
    beforeCheck = (track, target) async {
      if (first) {
        first = false;
        entered.complete();
        await release.future;
      }
    };
    final scan = service.scanDownloadsForTesting(audio);
    await entered.future;
    expect(await service.downloadTrack('pin2'), isTrue);
    release.complete();
    await scan;
    expect(service.isDownloaded('pin'), isTrue);
    expect(service.isDownloaded('pin2'), isTrue);
    expect(service.totalDownloadedBytes, bytes.length * 2);
  });

  test('scanning while a download is active does not delete its temporary file',
      () async {
    await service.init();
    final listening = Completer<void>();
    final controller = StreamController<List<int>>(onListen: () {
      listening.complete();
    });
    http.DynamicHttpOverrides.activeHandler = (method, url, request) async =>
        http.TestHttpClientResponse(controller.stream,
            contentLength: bytes.length);
    final pending = service.downloadTrack('pin');
    await listening.future;
    await service.scanDownloadsForTesting(audio);
    controller.add(bytes);
    await controller.close();
    expect(await pending, isTrue);
    expect(service.isDownloaded('pin'), isTrue);
    expect(temps(), isEmpty);
  });
}
