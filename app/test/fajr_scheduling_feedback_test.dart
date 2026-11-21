import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/fajr_qiyam_alarm_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/features/prayer/fajr_qiyam_alarm_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final dynamic service = FajrQiyamAlarmService.instance;
  bool fail = true;
  Completer<void>? pending;
  int writes = 0;
  setUp(() async {
    fail = true;
    pending = null;
    writes = 0;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({'wake_qiyam_mode': 'fixed_time'});
    await SettingsService.instance.init(forceReload: true);
    IslamicAudioService.instance.disableNativePlayerForTesting = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'zonedSchedule') {
        writes++;
        if (pending != null) await pending!.future;
        if (fail) throw PlatformException(code: 'denied');
      }
      return null;
    });
    await service.init(forceReload: true);
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test('latest applied result clears failure, failed retry retains it',
      () async {
    expect(service.schedulingError, isNotNull);
    await service.retryScheduling();
    expect(service.schedulingError, isNotNull);
    fail = false;
    await service.retryScheduling();
    expect(service.schedulingError, isNull);
  });
  test('old completion never clears newer failure status', () async {
    pending = Completer<void>();
    fail = false;
    final old = service.retryScheduling();
    final before = writes;
    while (writes == before) {
      await Future<void>.delayed(Duration.zero);
    }
    final latest = service.retryScheduling();
    fail = true;
    pending!.complete();
    expect((await old).toString(), 'AlarmScheduleOutcome.superseded');
    expect((await latest).toString(), 'AlarmScheduleOutcome.failed');
    expect(service.schedulingError, isNotNull);
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets('visible accessible failure and retry at $scale',
        (tester) async {
      for (final family in ['Cairo', 'Amiri']) {
        await (FontLoader(family)
              ..addFont(Future.value(ByteData.sublistView(
                  File('assets/fonts/$family-Regular.ttf').readAsBytesSync()))))
            .load();
      }
      const icons = String.fromEnvironment('MATERIAL_ICONS_FONT');
      if (icons.isNotEmpty)
        await (FontLoader('MaterialIcons')
              ..addFont(Future.value(
                  ByteData.sublistView(File(icons).readAsBytesSync()))))
            .load();
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: key,
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(fontFamily: 'Cairo'),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: const FajrQiyamAlarmScreen())));
      await tester.pumpAndSettle();
      final warning = find.textContaining('تعذر تحديث منبّه الفجر');
      expect(warning, findsOneWidget);
      expect(tester.getSemantics(warning).label,
          contains('قد تكون بعض التنبيهات'));
      final retry = find.byKey(const ValueKey('retry-wakeup-scheduling'));

      final node = tester.getSemantics(retry);
      expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
      expect(tester.takeException(), isNull);
      const directory = String.fromEnvironment('FAJR_FEEDBACK_PIXELS');
      if (directory.isNotEmpty)
        await tester.runAsync(() async {
          final image = await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$directory/failure-$scale.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      fail = false;
      tester.binding.renderViews.first.owner!.semanticsOwner!
          .performAction(node.id, ui.SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(warning, findsNothing);
      expect(service.schedulingError, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('wake_qiyam_mode'), 'fixed_time');
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
