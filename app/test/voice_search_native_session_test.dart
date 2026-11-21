import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';
import 'package:almomin/core/services/voice_search_service.dart';

class NativeSpeechProbe extends SpeechToTextPlatform {
  Completer<bool>? initializing;
  int starts = 0;
  Completer<void>? stopping;
  Completer<void>? canceling;
  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<bool> initialize(
      {debugLogging = false, List<SpeechConfigOption>? options}) async {
    if (initializing != null) return await initializing!.future;
    return true;
  }

  @override
  Future<List<dynamic>> locales() async => ['ar_EG:Arabic Egypt'];
  @override
  Future<bool> listen(
      {String? localeId,
      partialResults = true,
      onDevice = false,
      int listenMode = 0,
      sampleRate = 0,
      SpeechListenOptions? options}) async {
    starts++;
    onStatus?.call('listening');
    return true;
  }

  @override
  Future<void> stop() async {
    if (stopping != null) await stopping!.future;
    onStatus?.call('notListening');
  }

  @override
  Future<void> cancel() async {
    if (canceling != null) await canceling!.future;
    onStatus?.call('notListening');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final native = NativeSpeechProbe();
  final service = VoiceSearchService.instance;
  late SpeechToTextPlatform original;
  setUpAll(() {
    original = SpeechToTextPlatform.instance;
    SpeechToTextPlatform.instance = native;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter.baseflow.com/permissions/methods'),
            (call) async => 1);
  });
  tearDown(() async {
    native.initializing = null;
    native.stopping = null;
    native.canceling = null;
    await service.cancelListening();
    native.starts = 0;
  });
  tearDownAll(() {
    SpeechToTextPlatform.instance = original;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter.baseflow.com/permissions/methods'),
            null);
  });
  test('cancel during native initialization cannot start microphone later',
      () async {
    native.initializing = Completer<bool>();
    final pending = service.startListening(onResult: (_, __) {});
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(service.status, VoiceSearchStatus.initializing);
    await service.cancelListening();
    native.initializing!.complete(true);
    await pending;
    expect(native.starts, 0);
    expect(service.status, VoiceSearchStatus.idle);
  });
  test(
      'native recognition error reaches active caller and reports no speech, not network',
      () async {
    final errors = <String>[];
    await service.startListening(onResult: (_, __) {}, onError: errors.add);
    native.onError!(
        jsonEncode({'errorMsg': 'error_speech_timeout', 'permanent': false}));
    await Future<void>.delayed(Duration.zero);
    expect(errors, hasLength(1));
    expect(errors.single, contains('لم يتم تمييز أي صوت'));
    expect(service.status, VoiceSearchStatus.error);
  });
  test('late result after cancel neither calls old caller nor resurrects words',
      () async {
    final words = <String>[];
    await service.startListening(onResult: (w, _) => words.add(w));
    await service.cancelListening();
    native.onTextRecognition!(jsonEncode({
      'alternates': [
        {'recognizedWords': 'سورة الرحمن', 'confidence': 0.9}
      ],
      'resultType': 1
    }));
    expect(words, isEmpty);
    expect(service.lastRecognizedWords, isEmpty);
    expect(service.status, VoiceSearchStatus.idle);
  });
  test('new listen waits for pending native Stop and keeps its own status',
      () async {
    await service.startListening(onResult: (_, __) {});
    expect(native.starts, 1);
    native.stopping = Completer<void>();
    final stopped = service.stopListening();
    await Future<void>.delayed(Duration.zero);
    final newest = service.startListening(onResult: (_, __) {});
    await Future<void>.delayed(Duration.zero);
    expect(native.starts, 1);
    native.stopping!.complete();
    await stopped;
    await newest;
    expect(native.starts, 2);
    expect(service.status, VoiceSearchStatus.listening);
  });
  test(
      'late native error after cancel cannot change idle or contact old caller',
      () async {
    final errors = <String>[];
    await service.startListening(onResult: (_, __) {}, onError: errors.add);
    await service.cancelListening();
    native.onError!(
        jsonEncode({'errorMsg': 'error_network', 'permanent': false}));
    await Future<void>.delayed(Duration.zero);
    expect(errors, isEmpty);
    expect(service.status, VoiceSearchStatus.idle);
  });
  test('network and permission recognition errors retain distinct messages',
      () async {
    for (final input in {
      'error_network_timeout': 'الشبكة',
      'error_permission_denied': 'الميكروفون',
      'error_no_match': 'لم يتم تمييز أي صوت'
    }.entries) {
      final errors = <String>[];
      await service.startListening(onResult: (_, __) {}, onError: errors.add);
      native.onError!(jsonEncode({'errorMsg': input.key, 'permanent': false}));
      await Future<void>.delayed(Duration.zero);
      expect(errors, hasLength(1));
      expect(errors.single, contains(input.value));
    }
  });
}
