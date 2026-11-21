import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';
import 'package:almomin/core/services/voice_search_service.dart';
import 'voice_search_native_session_test.dart' show NativeSpeechProbe;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('latest Retry survives sharing a superseded permission check', () async {
    final permission = Completer<int>();
    final native = NativeSpeechProbe();
    final original = SpeechToTextPlatform.instance;
    SpeechToTextPlatform.instance = native;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter.baseflow.com/permissions/methods'),
            (call) async => permission.future);
    final service = VoiceSearchService.instance;
    try {
      final errors = <String>[];
      final first = service.startListening(onResult: (_, __) {});
      await Future<void>.delayed(Duration.zero);
      final latest =
          service.startListening(onResult: (_, __) {}, onError: errors.add);
      permission.complete(1);
      await first;
      await latest;
      expect(native.starts, 1);
      expect(errors, isEmpty);
      expect(service.status, VoiceSearchStatus.listening);
    } finally {
      await service.cancelListening();
      SpeechToTextPlatform.instance = original;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('flutter.baseflow.com/permissions/methods'),
              null);
    }
  });
}
