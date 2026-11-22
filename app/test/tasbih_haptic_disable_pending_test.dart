import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/features/adhkar/tasbih_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/adhkar_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('Cairo')
          ..addFont(rootBundle.load('assets/fonts/Cairo-Regular.ttf')))
        .load();
    await (FontLoader('Amiri')
          ..addFont(rootBundle.load('assets/fonts/Amiri-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Amiri-Bold.ttf')))
        .load();
    final icons = Platform.environment['MATERIAL_ICONS_FONT'];
    if (icons != null)
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(
                ByteData.sublistView(File(icons).readAsBytesSync()))))
          .load();
  });
  final calls = <String?>[];
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AdhkarService.instance.init(forceReload: true);
    await AdhkarService.instance.setTasbihTarget(2);
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate')
        calls.add(call.arguments as String?);
      return null;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
  testWidgets('disable immediately after target cancels both pending pulses',
      (tester) async {
    final service = AdhkarService.instance;
    expect(service.incrementTasbih(step: 2), isTrue);
    await tester.pump();
    expect(calls, ['HapticFeedbackType.heavyImpact']);
    service.toggleHaptic(false);
    await tester.pump(const Duration(milliseconds: 400));
    expect(calls, ['HapticFeedbackType.heavyImpact']);
    expect(service.tasbihCount, 2);
    expect(service.tasbihTotalToday, 2);
    expect((await SharedPreferences.getInstance()).getBool('tasbih_haptic'),
        isFalse);
  });
  testWidgets('disable between pulses cancels remaining pulse', (tester) async {
    final service = AdhkarService.instance;
    service.incrementTasbih(step: 2);
    await tester.pump(const Duration(milliseconds: 150));
    expect(calls, ['HapticFeedbackType.heavyImpact', null]);
    service.toggleHaptic(false);
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, ['HapticFeedbackType.heavyImpact', null]);
  });
  testWidgets(
      'reenabling does not revive canceled pulses but new target still vibrates',
      (tester) async {
    final service = AdhkarService.instance;
    service.incrementTasbih(step: 2);
    await tester.pump();
    service.toggleHaptic(false);
    service.toggleHaptic(true);
    await tester.pump(const Duration(milliseconds: 400));
    expect(calls, ['HapticFeedbackType.heavyImpact']);
    calls.clear();
    service.incrementTasbih(step: 2);
    await tester.pump(const Duration(milliseconds: 140));
    await tester.pump(const Duration(milliseconds: 140));
    expect(calls, [
      'HapticFeedbackType.heavyImpact',
      null,
      'HapticFeedbackType.heavyImpact'
    ]);
  });
  testWidgets(
      'ordinary taps enabled and disabled preserve counts and feedback choice',
      (tester) async {
    final service = AdhkarService.instance;
    expect(service.incrementTasbih(), isFalse);
    await tester.pump();
    expect(calls, ['HapticFeedbackType.lightImpact']);
    service.toggleHaptic(false);
    expect(service.incrementTasbih(), isTrue);
    await tester.pump(const Duration(milliseconds: 400));
    expect(calls, ['HapticFeedbackType.lightImpact']);
    expect(service.tasbihCount, 2);
    expect(service.tasbihTotalToday, 2);
  });
  testWidgets(
      'actual vibration toggle stops pending target pulses and preserves its disabled UI',
      (tester) async {
    await SettingsService.instance.init(forceReload: true);
    tester.view.physicalSize = const Size(412, 950);
    tester.view.devicePixelRatio = 1;
    final service = AdhkarService.instance;
    final boundary = GlobalKey();
    Future<void> capture(String name) async {
      final dir = Platform.environment['HAPTIC_PIXELS'];
      if (dir == null) return;
      await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    try {
      for (final scale in [1.0, 2.0]) {
        service.toggleHaptic(true);
        service.resetTasbih();
        service.resetTasbihTotal();
        await tester.pumpWidget(RepaintBoundary(
            key: boundary,
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: ThemeData(fontFamily: 'Cairo'),
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!),
                home: const TasbihScreen())));
        await tester.pumpAndSettle();
        await capture('enabled-$scale');
        calls.clear();
        service.incrementTasbih(step: 2);
        await tester.pump();
        expect(calls, ['HapticFeedbackType.heavyImpact']);
        await tester.tap(find.byTooltip('الاهتزاز مفعل'));
        await tester.pump(const Duration(milliseconds: 400));
        await capture('disabled-$scale');
        expect(find.byTooltip('الاهتزاز معطل'), findsOneWidget);
        expect(service.hapticEnabled, isFalse);
        expect(calls, ['HapticFeedbackType.heavyImpact']);
        expect(service.tasbihCount, 2);
        expect(service.tasbihTotalToday, 2);
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}
