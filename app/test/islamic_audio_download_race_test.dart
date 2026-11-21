import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';

typedef HttpRequestHandler = Future<HttpClientResponse> Function(
    String method, Uri url, TestHttpClientRequest request);

class DynamicHttpOverrides extends HttpOverrides {
  static HttpRequestHandler? activeHandler;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return DelegatingHttpClient();
  }
}

class DelegatingHttpClient extends Fake implements HttpClient {
  @override
  Duration idleTimeout = const Duration(seconds: 5);
  @override
  Duration? connectionTimeout = const Duration(seconds: 5);
  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final handler = DynamicHttpOverrides.activeHandler;
    if (handler == null) {
      throw StateError('No active HttpRequestHandler set for test');
    }
    return TestHttpClientRequest(url, handler);
  }
}

class TestHttpClientRequest extends Fake implements HttpClientRequest {
  final Uri url;
  final HttpRequestHandler onOpenUrl;
  void Function()? onAbort;

  TestHttpClientRequest(this.url, this.onOpenUrl);

  @override
  final HttpHeaders headers = TestHttpHeaders();

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  int contentLength = -1;

  @override
  bool persistentConnection = true;

  @override
  Future<HttpClientResponse> close() {
    return onOpenUrl('GET', url, this);
  }

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    onAbort?.call();
  }
}

class TestHttpHeaders extends Fake implements HttpHeaders {
  final Map<String, List<String>> _headers = {};

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    _headers.putIfAbsent(name.toLowerCase(), () => []).add(value.toString());
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _headers[name.toLowerCase()] = [value.toString()];
  }

  @override
  String? value(String name) {
    final list = _headers[name.toLowerCase()];
    return list != null && list.isNotEmpty ? list.last : null;
  }

  @override
  void forEach(void Function(String name, List<String> values) action) {
    _headers.forEach(action);
  }
}

class TestHttpClientResponse extends Stream<List<int>> implements HttpClientResponse {
  final Stream<List<int>> _stream;
  @override
  final int statusCode;
  @override
  final int contentLength;
  @override
  final HttpHeaders headers;

  @override
  bool get isRedirect => false;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  String get reasonPhrase => 'OK';

  TestHttpClientResponse(this._stream, {this.statusCode = 200, this.contentLength = 1000, HttpHeaders? headers})
      : headers = headers ?? TestHttpHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _stream.listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final activeControllers = <StreamController<List<int>>>[];
final activeFutures = <Future<dynamic>>[];

StreamController<List<int>> createTestStreamController() {
  late StreamController<List<int>> controller;
  controller = StreamController<List<int>>(
    onCancel: () {
      if (!controller.isClosed) {
        controller.close();
      }
    },
  );
  activeControllers.add(controller);
  return controller;
}

List<File> getLingeringTempFiles(Directory dir, String trackId) {
  if (!dir.existsSync()) return [];
  return dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.contains('$trackId.') && f.path.endsWith('.tmp'))
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  HttpOverrides? priorHttpOverrides;
  late Directory isolatedTempDir;
  late Directory audioDir;
  final service = IslamicAudioService.instance;
  bool priorDisableNative = false;

  setUpAll(() {
    priorHttpOverrides = HttpOverrides.current;
    isolatedTempDir = Directory.systemTemp.createTempSync('almomin_audio_dl_race_test_');
    audioDir = Directory('${isolatedTempDir.path}/adhkar_audio');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return isolatedTempDir.path;
        }
        return null;
      },
    );

    HttpOverrides.global = DynamicHttpOverrides();
  });

  tearDownAll(() {
    HttpOverrides.global = priorHttpOverrides;
    DynamicHttpOverrides.activeHandler = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );

    if (isolatedTempDir.existsSync()) {
      try {
        isolatedTempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  setUp(() async {
    priorDisableNative = service.disableNativePlayerForTesting;
    SharedPreferences.setMockInitialValues({});
    if (!audioDir.existsSync()) {
      audioDir.createSync(recursive: true);
    }

    service.disableNativePlayerForTesting = true;
    await service.init();
  });

  tearDown(() async {
    DynamicHttpOverrides.activeHandler = null;
    for (final id in [
      'adhan_makkah',
      'adhan_madinah',
      'adhan_essam_bukhari',
      'adhan_naif_feeda',
      'adhan_cairo_refaat',
      'adhan_aqsa',
      'adhan_farooq_hadrawi'
    ]) {
      if (service.isDownloading(id)) {
        service.cancelDownload(id);
      }
    }
    for (final c in activeControllers) {
      if (!c.isClosed) {
        try {
          await c.close().timeout(const Duration(milliseconds: 500));
        } catch (_) {}
      }
    }
    activeControllers.clear();

    for (final f in activeFutures) {
      try {
        await f.timeout(const Duration(seconds: 1));
      } catch (_) {}
    }
    activeFutures.clear();

    service.disableNativePlayerForTesting = priorDisableNative;
  });

  group('IslamicAudioService downloadTrack Controls', () {
    test('unknown ID cannot download another recording or publish a file', () async {
      var requests = 0;
      DynamicHttpOverrides.activeHandler = (method, url, req) async {
        requests++;
        return TestHttpClientResponse(Stream.value(Uint8List(2048)), contentLength: 2048);
      };
      const id = 'not_a_catalog_recording';
      expect(await service.downloadTrack(id), isFalse);
      expect(requests, 0);
      expect(File('${audioDir.path}/$id.mp3').existsSync(), isFalse);
      expect(service.isDownloading(id), isFalse);
      expect(service.isDownloaded(id), isFalse);
    });

    for (final size in [0, 1000]) {
      test('rejects $size byte download without replacing a good copy', () async {
        const id = 'adhan_essam_bukhari';
        DynamicHttpOverrides.activeHandler = (method, url, req) async {
          return TestHttpClientResponse(Stream.value(Uint8List(2048)..fillRange(0, 2048, 37)), contentLength: 2048);
        };
        expect(await service.downloadTrack(id), isTrue);
        final file = File(service.getLocalAudioPath(id)!);
        final oldBytes = file.readAsBytesSync();
        DynamicHttpOverrides.activeHandler = (method, url, req) async {
          return TestHttpClientResponse(Stream.value(Uint8List(size)), contentLength: size);
        };
        try {
          expect(await service.downloadTrack(id), isFalse);
          expect(file.readAsBytesSync(), oldBytes);
          expect(service.isDownloaded(id), isTrue);
          expect(service.isDownloading(id), isFalse);
          expect(getLingeringTempFiles(audioDir, id), isEmpty);
        } finally {
          await service.deleteDownloadedTrack(id);
        }
      });
    }

    test('Control 1: Single successful download completes and marks track downloaded', () async {
      final fakeData = Uint8List(2048);
      DynamicHttpOverrides.activeHandler = (method, url, req) async {
        return TestHttpClientResponse(Stream.value(fakeData), contentLength: fakeData.length);
      };

      const trackId = 'adhan_makkah';
      expect(service.isDownloaded(trackId), isFalse);
      expect(service.isDownloading(trackId), isFalse);

      final dlFuture = service.downloadTrack(trackId);
      activeFutures.add(dlFuture);

      final success = await dlFuture.timeout(const Duration(seconds: 5));
      expect(success, isTrue);
      expect(service.isDownloaded(trackId), isTrue);
      expect(service.isDownloading(trackId), isFalse);
      expect(service.getLocalAudioPath(trackId), isNotNull);
      final localFile = File(service.getLocalAudioPath(trackId)!);
      expect(localFile.existsSync(), isTrue);
      expect(localFile.lengthSync(), 2048);
      expect(getLingeringTempFiles(audioDir, trackId), isEmpty);

      // Clean up downloaded track
      await service.deleteDownloadedTrack(trackId).timeout(const Duration(seconds: 5));
      expect(service.isDownloaded(trackId), isFalse);
    });

    test('Control 2: Standalone cancel aborts download and cleans temp file', () async {
      final reqStarted = Completer<void>();
      final streamController = createTestStreamController();

      DynamicHttpOverrides.activeHandler = (method, url, req) async {
        req.onAbort = () {
          if (!streamController.isClosed) {
            streamController.close();
          }
        };
        reqStarted.complete();
        return TestHttpClientResponse(streamController.stream, contentLength: 5000);
      };

      const trackId = 'adhan_madinah';
      final downloadFuture = service.downloadTrack(trackId);
      activeFutures.add(downloadFuture);

      try {
        await reqStarted.future.timeout(const Duration(seconds: 5));
        // Emit initial chunk so stream/file is actively engaged and progress starts
        streamController.add(Uint8List(100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(service.isDownloading(trackId), isTrue);

        service.cancelDownload(trackId);

        final result = await downloadFuture.timeout(const Duration(seconds: 5));
        expect(result, isFalse);
        expect(service.isDownloaded(trackId), isFalse);
        expect(service.isDownloading(trackId), isFalse);
        expect(getLingeringTempFiles(audioDir, trackId), isEmpty,
            reason: 'Standalone cancel must clean up attempt temp file');
      } finally {
        if (!streamController.isClosed) {
          try {
            await streamController.close().timeout(const Duration(milliseconds: 500));
          } catch (_) {}
        }
        try {
          await downloadFuture.timeout(const Duration(seconds: 1));
        } catch (_) {}
      }
    });

    test('Control 3: Existing downloaded track is preserved on subsequent canceled re-download attempt', () async {
      const trackId = 'adhan_essam_bukhari';
      final initialData = Uint8List(3000);

      // 1. Initially download the track successfully
      DynamicHttpOverrides.activeHandler = (method, url, req) async {
        return TestHttpClientResponse(Stream.value(initialData), contentLength: initialData.length);
      };

      final dlSuccess = await service.downloadTrack(trackId).timeout(const Duration(seconds: 5));
      expect(dlSuccess, isTrue);
      expect(service.isDownloaded(trackId), isTrue);
      final initialPath = service.getLocalAudioPath(trackId);
      expect(initialPath, isNotNull);
      final initialFile = File(initialPath!);
      expect(initialFile.existsSync(), isTrue);
      expect(initialFile.lengthSync(), 3000);

      // 2. Start a second download (e.g. re-download) and cancel it
      final reqStarted = Completer<void>();
      final streamController = createTestStreamController();

      DynamicHttpOverrides.activeHandler = (method, url, req) async {
        req.onAbort = () {
          if (!streamController.isClosed) {
            streamController.close();
          }
        };
        reqStarted.complete();
        return TestHttpClientResponse(streamController.stream, contentLength: 5000);
      };

      final secondDlFuture = service.downloadTrack(trackId);
      activeFutures.add(secondDlFuture);

      try {
        await reqStarted.future.timeout(const Duration(seconds: 5));
        streamController.add(Uint8List(100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(service.isDownloading(trackId), isTrue);

        // Cancel second download
        service.cancelDownload(trackId);

        final secondResult = await secondDlFuture.timeout(const Duration(seconds: 5));
        expect(secondResult, isFalse);

        // Crucial: Original downloaded file must remain valid and intact
        expect(service.isDownloaded(trackId), isTrue);
        expect(service.isDownloading(trackId), isFalse);
        expect(initialFile.existsSync(), isTrue);
        expect(initialFile.lengthSync(), 3000,
            reason: 'Existing downloaded file content and size must not be corrupted by cancelled retry');
        expect(getLingeringTempFiles(audioDir, trackId), isEmpty,
            reason: 'Cancelled re-download must clean up its attempt temp file without leaving .tmp files');

        await service.deleteDownloadedTrack(trackId).timeout(const Duration(seconds: 5));
      } finally {
        if (!streamController.isClosed) {
          try {
            await streamController.close().timeout(const Duration(milliseconds: 500));
          } catch (_) {}
        }
        try {
          await secondDlFuture.timeout(const Duration(seconds: 1));
        } catch (_) {}
      }
    });

    test('Control 5: Network failure during re-download preserves existing valid download and cleans temp files', () async {
      const trackId = 'adhan_naif_feeda';
      final initialData = Uint8List(3500);

      // 1. Initially download the track successfully
      DynamicHttpOverrides.activeHandler = (method, url, req) async {
        return TestHttpClientResponse(Stream.value(initialData), contentLength: initialData.length);
      };

      final dlSuccess = await service.downloadTrack(trackId).timeout(const Duration(seconds: 5));
      expect(dlSuccess, isTrue);
      expect(service.isDownloaded(trackId), isTrue);
      final initialPath = service.getLocalAudioPath(trackId);
      expect(initialPath, isNotNull);
      final initialFile = File(initialPath!);
      expect(initialFile.existsSync(), isTrue);
      expect(initialFile.lengthSync(), 3500);

      // 2. Start re-download that fails due to network/socket error
      final reqStarted = Completer<void>();
      final streamController = createTestStreamController();

      DynamicHttpOverrides.activeHandler = (method, url, req) async {
        req.onAbort = () {
          if (!streamController.isClosed) {
            streamController.close();
          }
        };
        reqStarted.complete();
        return TestHttpClientResponse(streamController.stream, contentLength: 5000);
      };

      final failingDlFuture = service.downloadTrack(trackId);
      activeFutures.add(failingDlFuture);

      try {
        await reqStarted.future.timeout(const Duration(seconds: 5));
        streamController.add(Uint8List(100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(service.isDownloading(trackId), isTrue);

        // Inject network error
        streamController.addError(const SocketException('Connection reset by peer'));

        final failureResult = await failingDlFuture.timeout(const Duration(seconds: 5));
        expect(failureResult, isFalse);

        // Existing file and state remain valid
        expect(service.isDownloaded(trackId), isTrue,
            reason: 'Track must remain marked downloaded after network failure on re-download');
        expect(service.isDownloading(trackId), isFalse);
        expect(initialFile.existsSync(), isTrue);
        expect(initialFile.lengthSync(), 3500,
            reason: 'Existing downloaded file content and size must not be corrupted by network failure');
        expect(getLingeringTempFiles(audioDir, trackId), isEmpty,
            reason: 'Failed re-download must clean up its attempt temp file');

        await service.deleteDownloadedTrack(trackId).timeout(const Duration(seconds: 5));
      } finally {
        if (!streamController.isClosed) {
          try {
            await streamController.close().timeout(const Duration(milliseconds: 500));
          } catch (_) {}
        }
        try {
          await failingDlFuture.timeout(const Duration(seconds: 1));
        } catch (_) {}
      }
    });
  });

  group('IslamicAudioService cancel/re-download race repro', () {
    test('Race 1: Re-download immediately after cancel must not crash on shared temp file or fail early', () async {
      final req1Started = Completer<void>();
      final req1StreamController = createTestStreamController();
      final req2Started = Completer<void>();
      final req2StreamController = createTestStreamController();

      int requestCount = 0;

      DynamicHttpOverrides.activeHandler = (method, url, req) async {
        requestCount++;
        if (requestCount == 1) {
          req.onAbort = () {
            if (!req1StreamController.isClosed) {
              req1StreamController.close();
            }
          };
          req1Started.complete();
          return TestHttpClientResponse(req1StreamController.stream, contentLength: 10000);
        } else {
          req.onAbort = () {
            if (!req2StreamController.isClosed) {
              req2StreamController.close();
            }
          };
          req2Started.complete();
          return TestHttpClientResponse(req2StreamController.stream, contentLength: 10000);
        }
      };

      const trackId = 'adhan_cairo_refaat';

      // 1. Start Request 1
      final req1Future = service.downloadTrack(trackId);
      activeFutures.add(req1Future);

      Future<bool>? req2Future;

      try {
        await req1Started.future.timeout(const Duration(seconds: 5));
        req1StreamController.add(Uint8List(100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(service.isDownloading(trackId), isTrue);

        // 2. Cancel Request 1
        service.cancelDownload(trackId);

        // 3. Immediately start Request 2 (re-download) while Request 1 is still unwinding
        req2Future = service.downloadTrack(trackId);
        activeFutures.add(req2Future);

        // RED Assertion: Request 2 must successfully initialize and begin downloading,
        // without crashing on shared tempFilePath ($id.mp3.tmp) file collision or throwing early.
        final req2Outcome = await Future.any([
          req2Started.future.then((_) => 'started'),
          req2Future.then((res) => 'failed_early: $res'),
        ]).timeout(const Duration(seconds: 5));

        expect(req2Outcome, 'started',
            reason: 'Re-download must not fail early due to shared temp file lock collision or unsettled cancellation');

        // Clean up Request 1
        await req1Future.timeout(const Duration(seconds: 5));

        // Clean up Request 2 with exact bytes (10000 bytes matching contentLength)
        req2StreamController.add(Uint8List(10000));
        await req2StreamController.close().timeout(const Duration(milliseconds: 500));
        await req2Future.timeout(const Duration(seconds: 5));

        expect(getLingeringTempFiles(audioDir, trackId), isEmpty,
            reason: 'No attempt temp files must remain after cancel and retry complete');
      } finally {
        if (!req1StreamController.isClosed) {
          try {
            await req1StreamController.close().timeout(const Duration(milliseconds: 500));
          } catch (_) {}
        }
        if (!req2StreamController.isClosed) {
          try {
            await req2StreamController.close().timeout(const Duration(milliseconds: 500));
          } catch (_) {}
        }
        try {
          await req1Future.timeout(const Duration(seconds: 1));
        } catch (_) {}
        if (req2Future != null) {
          try {
            await req2Future.timeout(const Duration(seconds: 1));
          } catch (_) {}
        }
      }
    });

    test('Race 2: Re-download after cancel must complete successfully without being deleted by old request catch block', () async {
      final req1Started = Completer<void>();
      final req1StreamController = createTestStreamController();
      final req2Started = Completer<void>();
      final req2StreamController = createTestStreamController();

      int requestCount = 0;

      DynamicHttpOverrides.activeHandler = (method, url, req) async {
        requestCount++;
        if (requestCount == 1) {
          req.onAbort = () {
            if (!req1StreamController.isClosed) {
              req1StreamController.close();
            }
          };
          req1Started.complete();
          return TestHttpClientResponse(req1StreamController.stream, contentLength: 5000);
        } else {
          req.onAbort = () {
            if (!req2StreamController.isClosed) {
              req2StreamController.close();
            }
          };
          req2Started.complete();
          return TestHttpClientResponse(req2StreamController.stream, contentLength: 5000);
        }
      };

      const trackId = 'adhan_aqsa';

      // 1. Start Request 1
      final req1Future = service.downloadTrack(trackId);
      activeFutures.add(req1Future);

      Future<bool>? req2Future;

      try {
        await req1Started.future.timeout(const Duration(seconds: 5));
        req1StreamController.add(Uint8List(100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(service.isDownloading(trackId), isTrue);

        // 2. Cancel Request 1
        service.cancelDownload(trackId);

        // 3. Re-download Request 2 immediately
        req2Future = service.downloadTrack(trackId);
        activeFutures.add(req2Future);

        // RED Assertion 1: Request 2 must begin without crashing early
        final req2Outcome = await Future.any([
          req2Started.future.then((_) => 'started'),
          req2Future.then((res) => 'failed_early: $res'),
        ]).timeout(const Duration(seconds: 5));

        expect(req2Outcome, 'started',
            reason: 'Request 2 must successfully start without collision with canceled request');

        // 4. Await Request 1 settling
        final req1Result = await req1Future.timeout(const Duration(seconds: 5));
        expect(req1Result, isFalse, reason: 'Request 1 was canceled and must return false');

        // RED Assertion 2: Request 2 must still be active and downloading after Request 1 settles,
        // proving Request 1's catch block did not wipe Request 2's activeProgress / cancelToken.
        expect(service.isDownloading(trackId), isTrue,
            reason: 'Request 2 must remain actively downloading after Request 1 settles');

        // 5. Send exact bytes (5000 bytes matching contentLength) to complete Request 2
        req2StreamController.add(Uint8List(5000));
        await req2StreamController.close().timeout(const Duration(milliseconds: 500));
        final req2Result = await req2Future.timeout(const Duration(seconds: 5));

        expect(req2Result, isTrue,
            reason: 'Request 2 must download successfully to completion');
        expect(service.isDownloaded(trackId), isTrue,
            reason: 'Track must be marked downloaded after Request 2 finishes');

        // 6. Verify downloaded file validity and exact size
        final localPath = service.getLocalAudioPath(trackId);
        expect(localPath, isNotNull);
        final finalFile = File(localPath!);
        expect(finalFile.existsSync(), isTrue);
        expect(finalFile.lengthSync(), 5000,
            reason: 'Final downloaded file size must match exact content length');
        expect(getLingeringTempFiles(audioDir, trackId), isEmpty,
            reason: 'No attempt temp files must remain after cancel and successful retry');

        await service.deleteDownloadedTrack(trackId).timeout(const Duration(seconds: 5));
      } finally {
        if (!req1StreamController.isClosed) {
          try {
            await req1StreamController.close().timeout(const Duration(milliseconds: 500));
          } catch (_) {}
        }
        if (!req2StreamController.isClosed) {
          try {
            await req2StreamController.close().timeout(const Duration(milliseconds: 500));
          } catch (_) {}
        }
        try {
          await req1Future.timeout(const Duration(seconds: 1));
        } catch (_) {}
        if (req2Future != null) {
          try {
            await req2Future.timeout(const Duration(seconds: 1));
          } catch (_) {}
        }
      }
    });

    test('Control 4: Repeated cancel/retry properly targets new cancel token and cleans up state', () async {
      final req1Started = Completer<void>();
      final req1StreamController = createTestStreamController();
      final req2Started = Completer<void>();
      final req2StreamController = createTestStreamController();

      int requestCount = 0;

      DynamicHttpOverrides.activeHandler = (method, url, req) async {
        requestCount++;
        if (requestCount == 1) {
          req.onAbort = () {
            if (!req1StreamController.isClosed) {
              req1StreamController.close();
            }
          };
          req1Started.complete();
          return TestHttpClientResponse(req1StreamController.stream, contentLength: 4000);
        } else {
          req.onAbort = () {
            if (!req2StreamController.isClosed) {
              req2StreamController.close();
            }
          };
          req2Started.complete();
          return TestHttpClientResponse(req2StreamController.stream, contentLength: 4000);
        }
      };

      const trackId = 'adhan_farooq_hadrawi';

      // 1. Start Request 1
      final req1Future = service.downloadTrack(trackId);
      activeFutures.add(req1Future);

      Future<bool>? req2Future;

      try {
        await req1Started.future.timeout(const Duration(seconds: 5));
        req1StreamController.add(Uint8List(100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(service.isDownloading(trackId), isTrue);

        // 2. Cancel Request 1
        service.cancelDownload(trackId);

        // 3. Immediately start Request 2 (retry)
        req2Future = service.downloadTrack(trackId);
        activeFutures.add(req2Future);

        await req2Started.future.timeout(const Duration(seconds: 5));
        req2StreamController.add(Uint8List(100));
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // 4. Await Request 1 settling
        final req1Result = await req1Future.timeout(const Duration(seconds: 5));
        expect(req1Result, isFalse);

        // 5. Verify Request 2 is actively downloading
        expect(service.isDownloading(trackId), isTrue);

        // 6. Cancel Request 2 - verify it targets new cancel token
        service.cancelDownload(trackId);

        final req2Result = await req2Future.timeout(const Duration(seconds: 5));
        expect(req2Result, isFalse);

        // 7. Verify both requests settled with clean state
        expect(service.isDownloading(trackId), isFalse);
        expect(service.isDownloaded(trackId), isFalse);
        expect(getLingeringTempFiles(audioDir, trackId), isEmpty,
            reason: 'No attempt temp files must remain after repeated cancel/retry');
      } finally {
        if (!req1StreamController.isClosed) {
          try {
            await req1StreamController.close().timeout(const Duration(milliseconds: 500));
          } catch (_) {}
        }
        if (!req2StreamController.isClosed) {
          try {
            await req2StreamController.close().timeout(const Duration(milliseconds: 500));
          } catch (_) {}
        }
        try {
          await req1Future.timeout(const Duration(seconds: 1));
        } catch (_) {}
        if (req2Future != null) {
          try {
            await req2Future.timeout(const Duration(seconds: 1));
          } catch (_) {}
        }
      }
    });
  });
}
