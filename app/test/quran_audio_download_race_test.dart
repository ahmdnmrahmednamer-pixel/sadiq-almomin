import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/audio_download_service.dart';
import 'package:almomin/core/services/settings_service.dart';

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

List<File> getLingeringTempFiles(Directory dir, String reciterId, int surahId) {
  if (!dir.existsSync()) return [];
  final prefix = '${reciterId}_${surahId.toString().padLeft(3, '0')}';
  return dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.contains(prefix) && f.path.endsWith('.tmp'))
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  HttpOverrides? priorHttpOverrides;
  late Directory isolatedTempDir;
  late Directory audioDir;
  final service = AudioDownloadService.instance;

  setUpAll(() async {
    priorHttpOverrides = HttpOverrides.current;
    isolatedTempDir = Directory.systemTemp.createTempSync('almomin_surah_dl_race_test_');
    audioDir = Directory('${isolatedTempDir.path}/quran_audio');

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
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init();
    await service.init();
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
    if (!audioDir.existsSync()) {
      audioDir.createSync(recursive: true);
    }
  });

  tearDown(() async {
    DynamicHttpOverrides.activeHandler = null;
    for (final sid in [1, 2, 3, 4, 5, 112, 113, 114]) {
      if (service.isDownloading('mishari_alafasy', sid)) {
        service.cancelDownload('mishari_alafasy', sid);
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
  });

  group('AudioDownloadService Baseline Controls', () {
    test('Control 1: Single successful download completes and marks Surah downloaded', () async {
      const reciterId = 'mishari_alafasy';
      const surahId = 1;
      const surahName = 'الفاتحة';
      final fakeData = Uint8List(2048);

      DynamicHttpOverrides.activeHandler = (method, url, req) async {
        return TestHttpClientResponse(Stream.value(fakeData), contentLength: fakeData.length);
      };

      expect(service.isDownloaded(reciterId, surahId), isFalse);
      expect(service.isDownloading(reciterId, surahId), isFalse);

      final dlFuture = service.downloadSurah(
        reciterId: reciterId,
        surahId: surahId,
        surahName: surahName,
      );
      activeFutures.add(dlFuture);

      final success = await dlFuture.timeout(const Duration(seconds: 5));
      expect(success, isTrue);

      expect(service.isDownloaded(reciterId, surahId), isTrue);
      expect(service.isDownloading(reciterId, surahId), isFalse);
      expect(service.getDownloadProgress(reciterId, surahId), 0.0);

      final localPath = service.getLocalAudioPath(reciterId, surahId);
      expect(localPath, isNotNull);
      final finalFile = File(localPath!);
      expect(finalFile.existsSync(), isTrue);
      expect(finalFile.lengthSync(), fakeData.length);
      expect(getLingeringTempFiles(audioDir, reciterId, surahId), isEmpty);

      await service.deleteDownloadedSurah(reciterId, surahId).timeout(const Duration(seconds: 5));
    });

    test('Control 2: Cancelled download cleans up temp files and returns false', () async {
      const reciterId = 'mishari_alafasy';
      const surahId = 2;
      const surahName = 'البقرة';

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

      final dlFuture = service.downloadSurah(
        reciterId: reciterId,
        surahId: surahId,
        surahName: surahName,
      );
      activeFutures.add(dlFuture);

      try {
        await reqStarted.future.timeout(const Duration(seconds: 5));
        streamController.add(Uint8List(100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(service.isDownloading(reciterId, surahId), isTrue);

        service.cancelDownload(reciterId, surahId);

        final result = await dlFuture.timeout(const Duration(seconds: 5));
        expect(result, isFalse);
        expect(service.isDownloaded(reciterId, surahId), isFalse);
        expect(service.isDownloading(reciterId, surahId), isFalse);
        expect(getLingeringTempFiles(audioDir, reciterId, surahId), isEmpty);
      } finally {
        if (!streamController.isClosed) {
          try {
            await streamController.close().timeout(const Duration(milliseconds: 500));
          } catch (_) {}
        }
      }
    });

    test('Control 3: Pre-existing valid download is preserved when a re-download attempt is cancelled', () async {
      const reciterId = 'mishari_alafasy';
      const surahId = 3;
      const surahName = 'آل عمران';
      final initialData = Uint8List(3000);

      // Initial successful download
      DynamicHttpOverrides.activeHandler = (method, url, req) async {
        return TestHttpClientResponse(Stream.value(initialData), contentLength: initialData.length);
      };

      final initialSuccess = await service.downloadSurah(
        reciterId: reciterId,
        surahId: surahId,
        surahName: surahName,
      ).timeout(const Duration(seconds: 5));
      expect(initialSuccess, isTrue);
      expect(service.isDownloaded(reciterId, surahId), isTrue);

      final initialPath = service.getLocalAudioPath(reciterId, surahId);
      expect(initialPath, isNotNull);
      final initialFile = File(initialPath!);
      expect(initialFile.existsSync(), isTrue);
      expect(initialFile.lengthSync(), 3000);

      // Start re-download
      final reqStarted = Completer<void>();
      final streamController = createTestStreamController();

      DynamicHttpOverrides.activeHandler = (method, url, req) async {
        req.onAbort = () {
          if (!streamController.isClosed) {
            streamController.close();
          }
        };
        reqStarted.complete();
        return TestHttpClientResponse(streamController.stream, contentLength: 6000);
      };

      final secondDlFuture = service.downloadSurah(
        reciterId: reciterId,
        surahId: surahId,
        surahName: surahName,
      );
      activeFutures.add(secondDlFuture);

      try {
        await reqStarted.future.timeout(const Duration(seconds: 5));
        streamController.add(Uint8List(100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(service.isDownloading(reciterId, surahId), isTrue);

        // Cancel second download
        service.cancelDownload(reciterId, surahId);

        final secondResult = await secondDlFuture.timeout(const Duration(seconds: 5));
        expect(secondResult, isFalse);

        // Crucial: Original downloaded file must remain valid and intact
        expect(service.isDownloaded(reciterId, surahId), isTrue);
        expect(service.isDownloading(reciterId, surahId), isFalse);
        expect(initialFile.existsSync(), isTrue);
        expect(initialFile.lengthSync(), 3000,
            reason: 'Existing downloaded file content and size must not be corrupted by cancelled retry');
        expect(getLingeringTempFiles(audioDir, reciterId, surahId), isEmpty,
            reason: 'Cancelled re-download must clean up temp files without leaving .tmp files');

        await service.deleteDownloadedSurah(reciterId, surahId).timeout(const Duration(seconds: 5));
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

    test('Control 4: Network failure during re-download preserves existing valid download and cleans temp files', () async {
      const reciterId = 'mishari_alafasy';
      const surahId = 4;
      const surahName = 'النساء';
      final initialData = Uint8List(3500);

      // 1. Initial download
      DynamicHttpOverrides.activeHandler = (method, url, req) async {
        return TestHttpClientResponse(Stream.value(initialData), contentLength: initialData.length);
      };

      final dlSuccess = await service.downloadSurah(
        reciterId: reciterId,
        surahId: surahId,
        surahName: surahName,
      ).timeout(const Duration(seconds: 5));
      expect(dlSuccess, isTrue);
      expect(service.isDownloaded(reciterId, surahId), isTrue);

      final initialPath = service.getLocalAudioPath(reciterId, surahId);
      expect(initialPath, isNotNull);
      final initialFile = File(initialPath!);
      expect(initialFile.existsSync(), isTrue);
      expect(initialFile.lengthSync(), 3500);

      // 2. Start re-download that fails due to network error
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

      final failingDlFuture = service.downloadSurah(
        reciterId: reciterId,
        surahId: surahId,
        surahName: surahName,
      );
      activeFutures.add(failingDlFuture);

      try {
        await reqStarted.future.timeout(const Duration(seconds: 5));
        streamController.add(Uint8List(100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(service.isDownloading(reciterId, surahId), isTrue);

        // Inject network error
        streamController.addError(const SocketException('Connection reset by peer'));

        final failureResult = await failingDlFuture.timeout(const Duration(seconds: 5));
        expect(failureResult, isFalse);

        // Existing file and state remain valid
        expect(service.isDownloaded(reciterId, surahId), isTrue,
            reason: 'Surah must remain marked downloaded after network failure on re-download');
        expect(service.isDownloading(reciterId, surahId), isFalse);
        expect(initialFile.existsSync(), isTrue);
        expect(initialFile.lengthSync(), 3500,
            reason: 'Existing downloaded file content and size must not be corrupted by network failure');
        expect(getLingeringTempFiles(audioDir, reciterId, surahId), isEmpty,
            reason: 'Failed re-download must clean up its temp file');

        await service.deleteDownloadedSurah(reciterId, surahId).timeout(const Duration(seconds: 5));
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

    test('Control 5: Repeated cancel/retry properly targets new cancel token and cleans up state', () async {
      const reciterId = 'mishari_alafasy';
      const surahId = 5;
      const surahName = 'المائدة';

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

      // 1. Start Request 1
      final req1Future = service.downloadSurah(
        reciterId: reciterId,
        surahId: surahId,
        surahName: surahName,
      );
      activeFutures.add(req1Future);

      Future<bool>? req2Future;

      try {
        await req1Started.future.timeout(const Duration(seconds: 5));
        req1StreamController.add(Uint8List(100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(service.isDownloading(reciterId, surahId), isTrue);

        // 2. Cancel Request 1
        service.cancelDownload(reciterId, surahId);

        // 3. Immediately start Request 2 (retry)
        req2Future = service.downloadSurah(
          reciterId: reciterId,
          surahId: surahId,
          surahName: surahName,
        );
        activeFutures.add(req2Future);

        final req2Outcome = await Future.any([
          req2Started.future.then((_) => 'started'),
          req2Future.then((res) => 'failed_early: $res'),
        ]).timeout(const Duration(seconds: 5));

        expect(req2Outcome, 'started',
            reason: 'Retry request must not fail early due to shared temp file lock collision');

        req2StreamController.add(Uint8List(100));
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // 4. Await Request 1 settling
        final req1Result = await req1Future.timeout(const Duration(seconds: 5));
        expect(req1Result, isFalse);

        // 5. Verify Request 2 is actively downloading
        expect(service.isDownloading(reciterId, surahId), isTrue);

        // 6. Cancel Request 2 - verify it targets new cancel token
        service.cancelDownload(reciterId, surahId);

        final req2Result = await req2Future.timeout(const Duration(seconds: 5));
        expect(req2Result, isFalse);

        // 7. Verify both requests settled with clean state
        expect(service.isDownloading(reciterId, surahId), isFalse);
        expect(service.isDownloaded(reciterId, surahId), isFalse);
        expect(getLingeringTempFiles(audioDir, reciterId, surahId), isEmpty,
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

  group('AudioDownloadService cancel/re-download race repro', () {
    test('Race 1: Re-download immediately after cancel must not crash on shared temp file or fail early', () async {
      const reciterId = 'mishari_alafasy';
      const surahId = 112;
      const surahName = 'الإخلاص';

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

      // 1. Start Request 1
      final req1Future = service.downloadSurah(
        reciterId: reciterId,
        surahId: surahId,
        surahName: surahName,
      );
      activeFutures.add(req1Future);

      Future<bool>? req2Future;

      try {
        await req1Started.future.timeout(const Duration(seconds: 5));
        req1StreamController.add(Uint8List(100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(service.isDownloading(reciterId, surahId), isTrue);

        // 2. Cancel Request 1
        service.cancelDownload(reciterId, surahId);

        // 3. Immediately start Request 2 (re-download) while Request 1 is still unwinding
        req2Future = service.downloadSurah(
          reciterId: reciterId,
          surahId: surahId,
          surahName: surahName,
        );
        activeFutures.add(req2Future);

        // RED Assertion: Request 2 must successfully initialize and begin downloading,
        // without crashing on shared tempFilePath ($filePath.tmp) file collision or throwing early.
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

        expect(getLingeringTempFiles(audioDir, reciterId, surahId), isEmpty,
            reason: 'No attempt temp files must remain after cancel and retry complete');

        await service.deleteDownloadedSurah(reciterId, surahId).timeout(const Duration(seconds: 5));
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
      const reciterId = 'mishari_alafasy';
      const surahId = 113;
      const surahName = 'الفلق';

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

      // 1. Start Request 1
      final req1Future = service.downloadSurah(
        reciterId: reciterId,
        surahId: surahId,
        surahName: surahName,
      );
      activeFutures.add(req1Future);

      Future<bool>? req2Future;

      try {
        await req1Started.future.timeout(const Duration(seconds: 5));
        req1StreamController.add(Uint8List(100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(service.isDownloading(reciterId, surahId), isTrue);

        // 2. Cancel Request 1
        service.cancelDownload(reciterId, surahId);

        // 3. Re-download Request 2 immediately
        req2Future = service.downloadSurah(
          reciterId: reciterId,
          surahId: surahId,
          surahName: surahName,
        );
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
        expect(service.isDownloading(reciterId, surahId), isTrue,
            reason: 'Request 2 must remain actively downloading after Request 1 settles');

        // 5. Send exact bytes (5000 bytes matching contentLength) to complete Request 2
        req2StreamController.add(Uint8List(5000));
        await req2StreamController.close().timeout(const Duration(milliseconds: 500));
        final req2Result = await req2Future.timeout(const Duration(seconds: 5));

        expect(req2Result, isTrue,
            reason: 'Request 2 must download successfully to completion');
        expect(service.isDownloaded(reciterId, surahId), isTrue,
            reason: 'Surah must be marked downloaded after Request 2 finishes');

        // 6. Verify downloaded file validity and exact size
        final localPath = service.getLocalAudioPath(reciterId, surahId);
        expect(localPath, isNotNull);
        final finalFile = File(localPath!);
        expect(finalFile.existsSync(), isTrue);
        expect(finalFile.lengthSync(), 5000,
            reason: 'Final downloaded file size must match exact content length');
        expect(getLingeringTempFiles(audioDir, reciterId, surahId), isEmpty,
            reason: 'No attempt temp files must remain after cancel and successful retry');

        await service.deleteDownloadedSurah(reciterId, surahId).timeout(const Duration(seconds: 5));
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
