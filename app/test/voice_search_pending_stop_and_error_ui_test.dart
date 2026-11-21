import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';
import 'package:almomin/core/services/voice_search_service.dart';
import 'package:almomin/features/search/widgets/quran_voice_search_sheet.dart';
import 'voice_search_native_session_test.dart' show NativeSpeechProbe;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final native = NativeSpeechProbe();
  final service = VoiceSearchService.instance;
  late SpeechToTextPlatform original;
  setUpAll(() async {
    original = SpeechToTextPlatform.instance;
    SpeechToTextPlatform.instance = native;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter.baseflow.com/permissions/methods'),
            (call) async => 1);
    for (final entry in {
      'Cairo': 'assets/fonts/Cairo-Regular.ttf',
      'Amiri': 'assets/fonts/Amiri-Regular.ttf',
      'MaterialIcons':
          '${Platform.resolvedExecutable.split('/bin/cache/').first}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
    }.entries) {
      await (FontLoader(entry.key)
            ..addFont(Future.value(
                ByteData.sublistView(File(entry.value).readAsBytesSync()))))
          .load();
    }
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
  test('Stop during native initialization cannot later start microphone',
      () async {
    native.initializing = Completer<bool>();
    final pending = service.startListening(onResult: (_, __) {});
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(service.status, VoiceSearchStatus.initializing);
    await service.stopListening();
    native.initializing!.complete(true);
    await pending;
    expect(native.starts, 0);
    expect(service.status, VoiceSearchStatus.done);
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets('native no-speech error reaches sheet at text scale $scale',
        (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(390, 900);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetPhysicalSize);
      await t.runAsync(() async {
        await service.initialize();
      });
      final key = GlobalKey();
      await t.pumpWidget(RepaintBoundary(
          key: key,
          child: MaterialApp(
              theme: ThemeData(fontFamily: 'Cairo'),
              home: MediaQuery(
                  data: MediaQueryData(
                      size: const Size(390, 900),
                      textScaler: TextScaler.linear(scale)),
                  child: const Scaffold(body: QuranVoiceSearchSheet())))));
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 100));
      await t.runAsync(() async {
        for (var i = 0; i < 6; i++) {
          await Future<void>.delayed(Duration.zero);
        }
      });
      await t.pump();
      expect(native.starts, 1,
          reason:
              'service state ${service.status}, error ${service.errorMessage}');
      native.onError!(
          jsonEncode({'errorMsg': 'error_speech_timeout', 'permanent': false}));
      await t.pump();
      expect(find.textContaining('لم يتم تمييز أي صوت'), findsOneWidget);
      expect(find.textContaining('يرجى التحقق من الشبكة'), findsNothing);
      expect(t.takeException(), isNull);
      final dir = Platform.environment['VOICE_PIXEL_DIR'];
      if (dir != null) {
        await t.runAsync(() async {
          Directory(dir).createSync(recursive: true);
          final image = await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$dir/native-error-$scale.png')
              .writeAsBytesSync(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      await t.ensureVisible(
          find.byKey(const ValueKey('voice_sheet_retry_button')));
      await t.pump();
      expect(
          find.byKey(const ValueKey('voice_sheet_close_button')).hitTestable(),
          findsOneWidget);
      expect(t.takeException(), isNull);
      if (dir != null) {
        await t.runAsync(() async {
          Directory(dir).createSync(recursive: true);
          final image = await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$dir/native-error-footer-$scale.png')
              .writeAsBytesSync(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      await t.pumpWidget(const SizedBox());
      await t.runAsync(() async {
        await service.cancelListening();
      });
      await t.pump();
    });
  }
}
