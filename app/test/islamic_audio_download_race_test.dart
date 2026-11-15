import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory isolatedTempDir;
  final service = IslamicAudioService.instance;

  setUpAll(() {
    isolatedTempDir = Directory.systemTemp.createTempSync('almomin_audio_dl_race_test_');

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
    HttpOverrides.global = null;
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
    SharedPreferences.setMockInitialValues({});
    final audioDir = Directory('${isolatedTempDir.path}/adhkar_audio');
    if (!audioDir.existsSync()) {
      audioDir.createSync(recursive: true);
    }

    service.disableNativePlayerForTesting = true;
    await service.init();
  });

  tearDown(() async {
    DynamicHttpOverrides.activeHandler = null;
    for (final id in ['adhan_makkah', 'adhan_madinah', 'adhan_cairo', 'adhan_aqsa']) {
      if (service.isDownloading(id)) {
        service.cancelDownload(id);
      }
    }
    for (final c in activeControllers) {
      if (!c.isClosed) {
        c.close();
      }
    }
    activeControllers.clear();
    service.disableNativePlayerForTesting = false;
  });

  group('IslamicAudioService downloadTrack Controls', () {
    test('Control 1: Single successful download completes and marks track downloaded', () async {
      final fakeData = Uint8List(2048);
      DynamicHttpOverrides.activeHandler = (method, url, req) async {
        return TestHttpClientResponse(Stream.value(fakeData), contentLength: fakeData.length);
      };

      const trackId = 'adhan_makkah';
      expect(service.isDownloaded(trackId), isFalse);
      expect(service.isDownloading(trackId), isFalse);

      final success = await service.downloadTrack(trackId).timeout(const Duration(seconds: 5));
      expect(success, isTrue);
      expect(service.isDownloaded(trackId), isTrue);
      expect(service.isDownloading(trackId), isFalse);
      expect(service.getLocalAudioPath(trackId), isNotNull);
      expect(File(service.getLocalAudioPath(trackId)!).existsSync(), isTrue);

      // Clean up downloaded track
      await service.deleteDownloadedTrack(trackId).timeout(const Duration(seconds: 5));
      expect(service.isDownloaded(trackId), isFalse);
    });

    test('Control 2: Standalone cancel aborts download and cleans temp file', () async {
      final reqStarted = Completer<void>();
      final streamController = createTestStreamController();

      DynamicHttpOverrides.activeHandler = (method, url, req) async {
        reqStarted.complete();
        return TestHttpClientResponse(streamController.stream, contentLength: 5000);
      };

      const trackId = 'adhan_madinah';
      final downloadFuture = service.downloadTrack(trackId);

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
          req1Started.complete();
          return TestHttpClientResponse(req1StreamController.stream, contentLength: 10000);
        } else {
          req2Started.complete();
          return TestHttpClientResponse(req2StreamController.stream, contentLength: 10000);
        }
      };

      const trackId = 'adhan_cairo';

      // 1. Start Request 1
      final req1Future = service.downloadTrack(trackId);
      await req1Started.future.timeout(const Duration(seconds: 5));
      req1StreamController.add(Uint8List(100));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(service.isDownloading(trackId), isTrue);

      // 2. Cancel Request 1
      service.cancelDownload(trackId);

      // 3. Immediately start Request 2 (re-download) while Request 1 is still unwinding
      final req2Future = service.downloadTrack(trackId);

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

      // Clean up Request 2
      req2StreamController.add(Uint8List(9900));
      await req2StreamController.close();
      await req2Future.timeout(const Duration(seconds: 5));
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
          req1Started.complete();
          return TestHttpClientResponse(req1StreamController.stream, contentLength: 5000);
        } else {
          req2Started.complete();
          return TestHttpClientResponse(req2StreamController.stream, contentLength: 5000);
        }
      };

      const trackId = 'adhan_aqsa';

      // 1. Start Request 1
      final req1Future = service.downloadTrack(trackId);
      await req1Started.future.timeout(const Duration(seconds: 5));
      req1StreamController.add(Uint8List(100));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // 2. Cancel Request 1
      service.cancelDownload(trackId);

      // 3. Re-download Request 2
      final req2Future = service.downloadTrack(trackId);

      // RED Assertion: Request 2 must begin and complete successfully rather than
      // failing early due to file lock or having its file/state deleted by Request 1 catch block.
      final req2Outcome = await Future.any([
        req2Started.future.then((_) => 'started'),
        req2Future.then((res) => 'failed_early: $res'),
      ]).timeout(const Duration(seconds: 5));

      expect(req2Outcome, 'started',
          reason: 'Request 2 must successfully start without collision with canceled request');

      await req1Future.timeout(const Duration(seconds: 5));

      req2StreamController.add(Uint8List(4900));
      await req2StreamController.close();
      final req2Result = await req2Future.timeout(const Duration(seconds: 5));

      expect(req2Result, isTrue,
          reason: 'Request 2 must download successfully to completion');
      expect(service.isDownloaded(trackId), isTrue,
          reason: 'Track must be marked downloaded after Request 2 finishes');

      await service.deleteDownloadedTrack(trackId).timeout(const Duration(seconds: 5));
    });
  });
}
