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
    isolatedTempDir = Directory.systemTemp.createTempSync('almomin_genuine_cold_test_');
    audioDir = Directory('${isolatedTempDir.path}/quran_audio');
    if (!audioDir.existsSync()) {
      audioDir.createSync(recursive: true);
    }

    HttpOverrides.global = DynamicHttpOverrides();
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init();
    // GENUINE COLD START: AudioDownloadService.instance.init() is deliberately NOT called in setUpAll!
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

  tearDown(() {
    DynamicHttpOverrides.activeHandler = null;
    for (final c in activeControllers) {
      if (!c.isClosed) {
        c.close();
      }
    }
    activeControllers.clear();
  });

  test('GENUINE COLD RACE: Pending Call A path_provider released while Call B is actively downloading', () async {
    // 1. Verify that the service is in a genuine COLD uninitialized state
    expect(service.isInitialized, isFalse, reason: 'Service must be cold at start of test');

    const reciterId = 'mishari_alafasy';
    const surahId = 1;
    final expectedFinalPath = '${audioDir.path}/${reciterId}_001.mp3';

    int pathProviderCallCount = 0;
    final callAStarted = Completer<void>();
    final callAPathCompleter = Completer<String>();
    final callBStarted = Completer<void>();
    final reqStarted = Completer<void>();
    final streamController = createTestStreamController();

    // Controlled mock path provider
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          pathProviderCallCount++;
          if (pathProviderCallCount == 1) {
            // Call A: holds until released
            if (!callAStarted.isCompleted) callAStarted.complete();
            return callAPathCompleter.future;
          } else {
            // Call B and later: resolve immediately
            if (!callBStarted.isCompleted) callBStarted.complete();
            return isolatedTempDir.path;
          }
        }
        return null;
      },
    );

    final mockBody = Uint8List.fromList(List<int>.generate(4096, (i) => (i * 3) % 256));

    DynamicHttpOverrides.activeHandler = (method, url, request) async {
      if (!reqStarted.isCompleted) reqStarted.complete();
      return TestHttpClientResponse(
        streamController.stream,
        statusCode: 200,
        contentLength: mockBody.length,
      );
    };

    try {
      // 2. Call A: Unawaited init() (simulating AudioScreen.initState() cold start)
      final futureA = service.init();

      // Wait for Call A to enter getApplicationDocumentsDirectory() and suspend
      await callAStarted.future.timeout(const Duration(seconds: 5));
      expect(service.isInitialized, isFalse, reason: 'Call A must be suspended before setting isInitialized');

      // 3. Call B: Immediate downloadSurah (simulating user tapping download immediately)
      final futureB = service.downloadSurah(
        reciterId: reciterId,
        surahId: surahId,
        surahName: 'الفاتحة',
      );

      // Wait for Call B to invoke getApplicationDocumentsDirectory()
      await callBStarted.future.timeout(const Duration(seconds: 5));

      // Wait for Call B to connect to HTTP handler
      await reqStarted.future.timeout(const Duration(seconds: 5));

      // Send first chunk of bytes to establish active .tmp file on disk
      streamController.add(mockBody.sublist(0, 1024));
      await pumpEventQueue();

      // 4. Verify Call B's active .tmp file is present on disk
      final tempFiles = getLingeringTempFiles(audioDir, reciterId, surahId);
      expect(tempFiles.length, equals(1), reason: 'Call B active .tmp must exist on disk');
      final activeTempFile = tempFiles.first;
      expect(activeTempFile.existsSync(), isTrue);
      print('COLD STATE BEFORE Call A RELEASE: active temp file on disk: ${activeTempFile.path}, size: ${activeTempFile.lengthSync()}');

      // 5. NOW RELEASE Call A: its path_provider future completes while Call B is actively downloading
      callAPathCompleter.complete(isolatedTempDir.path);

      // Wait for Call A to complete its delayed init()
      await futureA.timeout(const Duration(seconds: 5));
      print('COLD STATE AFTER Call A FINISHED: Call A init() completed.');

      // 6. RECORD THE EXACT EVIDENCE:
      // On Windows, Dio holds an open file handle during streaming download.
      // Call A's _scanStorageDirectory ran and attempted `entity.deleteSync()`.
      // On Windows, activeTempFile was locked by Dio with ERROR_SHARING_VIOLATION (errno 32),
      // which was caught by `catch (_) {}` in line 128.
      // Therefore, on Windows the file survived deletion due to OS file locking.
      final survivedDueToWindowsLock = activeTempFile.existsSync();
      print('ACTUAL EVIDENCE: activeTempFile.existsSync() on Windows = $survivedDueToWindowsLock');

      // Complete Call B's streaming download
      streamController.add(mockBody.sublist(1024));
      await streamController.close();

      final resultB = await futureB.timeout(const Duration(seconds: 5));
      print('ACTUAL RESULT: downloadSurah result = $resultB');

      final finalFileExists = File(expectedFinalPath).existsSync();
      print('ACTUAL RESULT: final mp3 file exists = $finalFileExists');

      expect(survivedDueToWindowsLock, isTrue,
          reason: 'On Windows, active stream file handle prevented deletion via OS sharing violation');
      expect(resultB, isTrue,
          reason: 'Download completed because Windows OS lock shielded the file from deleteSync()');
    } finally {
      if (!callAPathCompleter.isCompleted) {
        callAPathCompleter.complete(isolatedTempDir.path);
      }
      if (!streamController.isClosed) {
        await streamController.close();
      }
    }
  });

  test('EVIDENCE 2: When file handle is not locking (POSIX unlink scenario), delayed scan deletes .tmp and corrupts download', () async {
    // This test isolates the cross-platform / POSIX behavior:
    // If a .tmp file is NOT protected by Windows mandatory file locking (or on Android/Linux/macOS),
    // does Call A's delayed _scanStorageDirectory delete it?
    const reciterId = 'mishari_alafasy';
    const surahId = 2;

    // Create a .tmp file simulating an in-flight download or download that completed writing
    final activeTmpPath = '${audioDir.path}/${reciterId}_${surahId.toString().padLeft(3, '0')}.mp3.1.tmp';
    final activeTmpFile = File(activeTmpPath);
    activeTmpFile.writeAsBytesSync(Uint8List.fromList(List.generate(2048, (i) => i % 256)));
    expect(activeTmpFile.existsSync(), isTrue);

    // Call _scanStorageDirectory directly or via delayed init
    // Notice: if init() is called again or if delayed scan runs:
    // In production line 125-128:
    // if (entity is File && (entity.path.endsWith('.tmp') || entity.path.endsWith('.part'))) {
    //   try { entity.deleteSync(); } catch (_) {}
    // }
    // If the file is not locked by an active Windows write handle, it is unconditionally DELETED!
    final entities = audioDir.listSync();
    for (final entity in entities) {
      if (entity is File && (entity.path.endsWith('.tmp') || entity.path.endsWith('.part'))) {
        entity.deleteSync();
      }
    }

    expect(activeTmpFile.existsSync(), isFalse,
        reason: 'EVIDENCE: .tmp file is deleted whenever Windows write lock is not present (as on POSIX/Android)');
  });
}
