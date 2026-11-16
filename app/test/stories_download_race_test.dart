import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/stories_service.dart';

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

List<File> getLingeringTempFiles(Directory dir, String storyId) {
  if (!dir.existsSync()) return [];
  return dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.contains(storyId) && f.path.endsWith('.tmp'))
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  HttpOverrides? priorHttpOverrides;
  late Directory isolatedTempDir;
  late Directory storiesDir;
  final service = StoriesService.instance;

  setUpAll(() async {
    priorHttpOverrides = HttpOverrides.current;
    isolatedTempDir = Directory.systemTemp.createTempSync('almomin_stories_dl_race_test_');
    storiesDir = Directory('${isolatedTempDir.path}/prophet_stories');

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

  tearDown(() async {
    DynamicHttpOverrides.activeHandler = null;
    for (final sid in ['adam', 'nuh', 'hud_salih', 'ibrahim', 'lut_shuaib', 'yusuf', 'musa']) {
      if (service.isDownloading(sid)) {
        service.cancelDownload(sid);
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
        await f.timeout(const Duration(milliseconds: 300));
      } catch (_) {}
    }
    activeFutures.clear();
  });

  group('StoriesService Baseline Controls', () {
    test('Control 1: Single successful download completes and marks story downloaded', () async {
      const storyId = 'adam';
      final fakeData = Uint8List(2048);

      DynamicHttpOverrides.activeHandler = (method, url, req) async {
        return TestHttpClientResponse(Stream.value(fakeData), contentLength: fakeData.length);
      };

      expect(service.isDownloaded(storyId), isFalse);
      expect(service.isDownloading(storyId), isFalse);

      final dlFuture = service.downloadStory(storyId);
      activeFutures.add(dlFuture);

      final success = await dlFuture.timeout(const Duration(seconds: 5));
      expect(success, isTrue);

      expect(service.isDownloaded(storyId), isTrue);
      expect(service.isDownloading(storyId), isFalse);
      expect(service.getDownloadProgress(storyId), 0.0);

      final localPath = service.getLocalAudioPath(storyId);
      expect(localPath, isNotNull);
      final finalFile = File(localPath!);
      expect(finalFile.existsSync(), isTrue);
      expect(finalFile.lengthSync(), fakeData.length);
      expect(getLingeringTempFiles(storiesDir, storyId), isEmpty);

      final downloadedStories = service.getDownloadedStories();
      expect(downloadedStories.any((s) => s.id == storyId), isTrue);
      expect(service.totalDownloadedStoriesBytes, equals(fakeData.length));

      await service.deleteDownloadedStory(storyId).timeout(const Duration(seconds: 5));
    });

    test('Control 2: Cancelled download cleans up temp files and returns false', () async {
      const storyId = 'nuh';

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

      expect(service.isDownloaded(storyId), isFalse);
      expect(service.isDownloading(storyId), isFalse);

      final dlFuture = service.downloadStory(storyId);
      activeFutures.add(dlFuture);

      try {
        await reqStarted.future.timeout(const Duration(seconds: 5));
        streamController.add(Uint8List(100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(service.isDownloading(storyId), isTrue);

        service.cancelDownload(storyId);

        final result = await dlFuture.timeout(const Duration(seconds: 5));
        expect(result, isFalse);
      } finally {
        if (!streamController.isClosed) {
          await streamController.close().timeout(const Duration(milliseconds: 500));
        }
      }

      expect(service.isDownloaded(storyId), isFalse);
      expect(service.isDownloading(storyId), isFalse);
      expect(service.getDownloadProgress(storyId), 0.0);
      expect(getLingeringTempFiles(storiesDir, storyId), isEmpty);
    });

    test('Control 3: Pre-existing valid download is preserved when a re-download attempt is cancelled', () async {
      const storyId = 'hud_salih';
      final initialData = Uint8List(3000);
      for (int i = 0; i < initialData.length; i++) {
        initialData[i] = (i * 7 + 13) % 251 + 1;
      }

      // Step 1: establish pre-existing download
      DynamicHttpOverrides.activeHandler = (method, url, req) async {
        return TestHttpClientResponse(Stream.value(initialData), contentLength: initialData.length);
      };
      final initialDl = await service.downloadStory(storyId).timeout(const Duration(seconds: 5));
      expect(initialDl, isTrue);
      expect(service.isDownloaded(storyId), isTrue);

      final validPath = service.getLocalAudioPath(storyId);
      expect(validPath, isNotNull);
      final initialFile = File(validPath!);
      expect(initialFile.existsSync(), isTrue);
      expect(initialFile.lengthSync(), initialData.length);
      expect(initialFile.readAsBytesSync(), equals(initialData));

      // Step 2: attempt re-download and cancel mid-flight
      final reqStarted = Completer<void>();
      final streamController = createTestStreamController();

      DynamicHttpOverrides.activeHandler = (method, url, req) async {
        req.onAbort = () {
          if (!streamController.isClosed) {
            streamController.close();
          }
        };
        reqStarted.complete();
        return TestHttpClientResponse(streamController.stream, contentLength: 8000);
      };

      final reDlFuture = service.downloadStory(storyId);
      activeFutures.add(reDlFuture);

      try {
        await reqStarted.future.timeout(const Duration(seconds: 5));
        streamController.add(Uint8List(100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(service.isDownloading(storyId), isTrue);

        service.cancelDownload(storyId);

        final result = await reDlFuture.timeout(const Duration(seconds: 5));
        expect(result, isFalse);
      } finally {
        if (!streamController.isClosed) {
          await streamController.close().timeout(const Duration(milliseconds: 500));
        }
      }

      // CRITICAL ASSERTION: Pre-existing file must be completely untouched and identical
      expect(service.isDownloaded(storyId), isTrue);
      expect(initialFile.existsSync(), isTrue);
      expect(initialFile.lengthSync(), initialData.length);
      expect(initialFile.readAsBytesSync(), equals(initialData));
      expect(getLingeringTempFiles(storiesDir, storyId), isEmpty);

      await service.deleteDownloadedStory(storyId).timeout(const Duration(seconds: 5));
    });

    test('Control 4: Network failure during re-download preserves existing valid download and cleans temp files', () async {
      const storyId = 'ibrahim';
      final initialData = Uint8List(3500);
      for (int i = 0; i < initialData.length; i++) {
        initialData[i] = (i * 11 + 17) % 251 + 1;
      }

      // Step 1: establish initial valid download
      DynamicHttpOverrides.activeHandler = (method, url, req) async {
        return TestHttpClientResponse(Stream.value(initialData), contentLength: initialData.length);
      };
      final initialDl = await service.downloadStory(storyId).timeout(const Duration(seconds: 5));
      expect(initialDl, isTrue);

      final validPath = service.getLocalAudioPath(storyId);
      expect(validPath, isNotNull);
      final initialFile = File(validPath!);
      expect(initialFile.existsSync(), isTrue);
      expect(initialFile.lengthSync(), initialData.length);
      expect(initialFile.readAsBytesSync(), equals(initialData));

      // Step 2: trigger re-download that fails with network error mid-flight
      final reqStarted = Completer<void>();
      final streamController = createTestStreamController();

      DynamicHttpOverrides.activeHandler = (method, url, req) async {
        reqStarted.complete();
        return TestHttpClientResponse(streamController.stream, contentLength: 7000);
      };

      final failFuture = service.downloadStory(storyId);
      activeFutures.add(failFuture);

      try {
        await reqStarted.future.timeout(const Duration(seconds: 5));
        streamController.add(Uint8List(100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(service.isDownloading(storyId), isTrue);

        // Inject network error
        streamController.addError(const SocketException('Connection reset by peer'));
        await streamController.close().timeout(const Duration(milliseconds: 500));

        final result = await failFuture.timeout(const Duration(seconds: 5));
        expect(result, isFalse);
      } finally {
        if (!streamController.isClosed) {
          await streamController.close().timeout(const Duration(milliseconds: 500));
        }
      }

      expect(service.isDownloaded(storyId), isTrue);
      expect(service.isDownloading(storyId), isFalse);
      expect(initialFile.existsSync(), isTrue);
      expect(initialFile.lengthSync(), initialData.length);
      expect(initialFile.readAsBytesSync(), equals(initialData));
      expect(getLingeringTempFiles(storiesDir, storyId), isEmpty);

      await service.deleteDownloadedStory(storyId).timeout(const Duration(seconds: 5));
    });

    test('Control 5: Repeated cancel/retry properly targets new cancel token and cleans up state', () async {
      const storyId = 'lut_shuaib';

      // 1. Start Request 1
      final req1Started = Completer<void>();
      final req1StreamController = createTestStreamController();

      // 2. Prepare handler for Request 2
      final req2Started = Completer<void>();
      final req2StreamController = createTestStreamController();
      int callCount = 0;

      DynamicHttpOverrides.activeHandler = (method, url, req) async {
        callCount++;
        if (callCount == 1) {
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

      final req1Future = service.downloadStory(storyId);
      activeFutures.add(req1Future);

      try {
        await req1Started.future.timeout(const Duration(seconds: 5));
        req1StreamController.add(Uint8List(100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(service.isDownloading(storyId), isTrue);

        // Cancel Request 1
        service.cancelDownload(storyId);

        final req1Result = await req1Future.timeout(const Duration(seconds: 5));
        expect(req1Result, isFalse);
        expect(service.isDownloading(storyId), isFalse);

        // Start Request 2 (retry)
        final req2Future = service.downloadStory(storyId);
        activeFutures.add(req2Future);

        await req2Started.future.timeout(const Duration(seconds: 5));
        req2StreamController.add(Uint8List(5000));
        await req2StreamController.close().timeout(const Duration(milliseconds: 500));

        final req2Result = await req2Future.timeout(const Duration(seconds: 5));
        expect(req2Result, isTrue);
        expect(service.isDownloaded(storyId), isTrue);
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
      }

      await service.deleteDownloadedStory(storyId).timeout(const Duration(seconds: 5));
    });

    test('Control 6: Duplicate download request while download is active returns false', () async {
      const storyId = 'lut_shuaib';
      final reqStarted = Completer<void>();
      final streamController = createTestStreamController();

      DynamicHttpOverrides.activeHandler = (method, url, req) async {
        reqStarted.complete();
        return TestHttpClientResponse(streamController.stream, contentLength: 4000);
      };

      final dlFuture1 = service.downloadStory(storyId);
      activeFutures.add(dlFuture1);

      try {
        await reqStarted.future.timeout(const Duration(seconds: 5));
        expect(service.isDownloading(storyId), isTrue);

        // Attempt duplicate download while dlFuture1 is active
        final dupResult = await service.downloadStory(storyId).timeout(const Duration(seconds: 5));
        expect(dupResult, isFalse, reason: 'Duplicate download attempt must be rejected immediately');

        streamController.add(Uint8List(4000));
        await streamController.close().timeout(const Duration(milliseconds: 500));
        final success1 = await dlFuture1.timeout(const Duration(seconds: 5));
        expect(success1, isTrue);
      } finally {
        if (!streamController.isClosed) {
          try {
            await streamController.close().timeout(const Duration(milliseconds: 500));
          } catch (_) {}
        }
      }

      await service.deleteDownloadedStory(storyId).timeout(const Duration(seconds: 5));
    });
  });

  group('StoriesService cancel/re-download race repro', () {
    test('Race 1: Re-download immediately after cancel must not crash on shared temp file or fail early', () async {
      const storyId = 'yusuf';

      final req1Started = Completer<void>();
      final req1StreamController = createTestStreamController();

      final req2Started = Completer<void>();
      final req2StreamController = createTestStreamController();
      int callCount = 0;

      DynamicHttpOverrides.activeHandler = (method, url, req) async {
        callCount++;
        if (callCount == 1) {
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
      final req1Future = service.downloadStory(storyId);
      activeFutures.add(req1Future);

      try {
        await req1Started.future.timeout(const Duration(seconds: 5));
        req1StreamController.add(Uint8List(100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(service.isDownloading(storyId), isTrue);

        // 2. Cancel Request 1 AND IMMEDIATELY invoke Request 2 without awaiting Request 1 completion
        service.cancelDownload(storyId);

        // Immediate retry invocation (simulating rapid user tap on Download button)
        final req2Future = service.downloadStory(storyId);
        activeFutures.add(req2Future);

        // Wait for Request 1 to finish its cancellation path
        final req1Result = await req1Future.timeout(const Duration(seconds: 5));
        expect(req1Result, isFalse);

        // Request 2 must have started cleanly and must be streaming
        await req2Started.future.timeout(const Duration(seconds: 5));

        req2StreamController.add(Uint8List(100));
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Complete Request 2
        req2StreamController.add(Uint8List(4900));
        await req2StreamController.close().timeout(const Duration(milliseconds: 500));

        final req2Result = await req2Future.timeout(const Duration(seconds: 5));
        expect(req2Result, isTrue, reason: 'Retry request must complete successfully');
        expect(service.isDownloaded(storyId), isTrue);
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
      }

      await service.deleteDownloadedStory(storyId).timeout(const Duration(seconds: 5));
    });

    test('Race 2: Re-download after cancel must complete successfully without being deleted by old request catch block', () async {
      const storyId = 'musa';

      final req1Started = Completer<void>();
      final req1StreamController = createTestStreamController();

      final req2Started = Completer<void>();
      final req2StreamController = createTestStreamController();
      int callCount = 0;

      DynamicHttpOverrides.activeHandler = (method, url, req) async {
        callCount++;
        if (callCount == 1) {
          req.onAbort = () {
            // Keep stream open briefly so old request catch block runs delayed
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
      final req1Future = service.downloadStory(storyId);
      activeFutures.add(req1Future);

      try {
        await req1Started.future.timeout(const Duration(seconds: 5));
        req1StreamController.add(Uint8List(100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(service.isDownloading(storyId), isTrue);

        // 2. Cancel Request 1
        service.cancelDownload(storyId);

        // 3. Immediately launch Request 2
        final req2Future = service.downloadStory(storyId);
        activeFutures.add(req2Future);

        await req2Started.future.timeout(const Duration(seconds: 5));

        // 4. Now close Request 1 stream, causing Request 1's catch block to run
        if (!req1StreamController.isClosed) {
          await req1StreamController.close().timeout(const Duration(milliseconds: 500));
        }
        await req1Future.timeout(const Duration(seconds: 5));

        // 5. Complete Request 2
        req2StreamController.add(Uint8List(10000));
        await req2StreamController.close().timeout(const Duration(milliseconds: 500));
        final req2Result = await req2Future.timeout(const Duration(seconds: 5));

        expect(req2Result, isTrue,
            reason: 'Request 2 must succeed and not have its temp file or state deleted by Request 1 catch block');
        expect(service.isDownloaded(storyId), isTrue);
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
      }

      await service.deleteDownloadedStory(storyId).timeout(const Duration(seconds: 5));
    });
  });
}
