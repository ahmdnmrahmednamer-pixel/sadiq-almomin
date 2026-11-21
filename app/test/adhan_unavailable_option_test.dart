import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/features/settings/widgets/settings_adhan_voice_modal.dart';
import 'prayer_voice_preview_ownership_test.dart' show VoicePreviewPlayer;
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/core/notifications/prayer_notification_service.dart';
import 'package:almomin/features/settings/widgets/adhan_voice_option.dart';

void main() {
  setUpAll(() async {
    const icons = String.fromEnvironment('MATERIAL_ICONS_FONT');
    if (icons.isNotEmpty) await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(File(icons).readAsBytesSync())))).load();
    await (FontLoader('Cairo')..addFont(Future.value(ByteData.sublistView(File('assets/fonts/Cairo-Regular.ttf').readAsBytesSync())))).load();
  });
  testWidgets('unavailable selected voice remains visible with disabled independent actions', (tester) async {
    tester.view.physicalSize = const Size(320, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var calls = 0;
    const key = ValueKey('unavailable_option_capture');
    await tester.pumpWidget(MaterialApp(theme: ThemeData(fontFamily: 'Cairo'), home: Scaffold(body:
      Directionality(textDirection: TextDirection.rtl, child: MediaQuery(data: const MediaQueryData(textScaler: TextScaler.linear(2)), child:
      RepaintBoundary(key: key, child: SingleChildScrollView(child: AdhanVoiceOption(
        name: 'القارئ هزاع البلوشي', selected: true, playing: false,
        downloaded: false, downloading: false,
        unavailableReason: IslamicAudioService.unavailableRecordingReason('adhan_haza_albalushi'),
        onListen: () => calls++, onAssign: () => calls++, onDownload: () => calls++,
      ))))))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('مواعيد التذكير محفوظة'), findsOneWidget);
    for (final button in tester.widgetList<ButtonStyleButton>(find.byWidgetPredicate((w) => w is ButtonStyleButton))) {
      expect(button.onPressed, isNull);
    }
    expect(calls, 0);
    const capture = String.fromEnvironment('ADHAN_PIXELS_DIR');
    if (capture.isNotEmpty) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory(capture).createSync(recursive: true);
        File('$capture/unavailable-option-320-2x.png').writeAsBytesSync(data!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
  testWidgets('conflicting source warning remains readable with disabled independent actions', (tester) async {
    tester.view.physicalSize = const Size(320, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var calls = 0;
    const key = ValueKey('unavailable_option_capture');
    await tester.pumpWidget(MaterialApp(theme: ThemeData(fontFamily: 'Cairo'), home: Scaffold(body:
      Directionality(textDirection: TextDirection.rtl, child: MediaQuery(data: const MediaQueryData(textScaler: TextScaler.linear(2)), child:
      RepaintBoundary(key: key, child: SingleChildScrollView(child: AdhanVoiceOption(
        name: 'الشيخ عبد الرحمن السديس', selected: true, playing: false,
        downloaded: false, downloading: false,
        unavailableReason: IslamicAudioService.unavailableRecordingReason('adhan_sudais'),
        onListen: () => calls++, onAssign: () => calls++, onDownload: () => calls++,
      ))))))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('مواعيد التذكير محفوظة'), findsOneWidget);
    for (final button in tester.widgetList<ButtonStyleButton>(find.byWidgetPredicate((w) => w is ButtonStyleButton))) {
      expect(button.onPressed, isNull);
    }
    expect(calls, 0);
    const capture = String.fromEnvironment('ADHAN_PIXELS_DIR');
    if (capture.isNotEmpty) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory(capture).createSync(recursive: true);
        File('$capture/conflicting-option-320-2x.png').writeAsBytesSync(data!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
  testWidgets('preview-only recording keeps listen and download usable but blocks assignment', (tester) async {
    tester.view.physicalSize = const Size(320, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var listened = 0;
    var assigned = 0;
    var downloaded = 0;
    const key = ValueKey('preview_only_capture');
    await tester.pumpWidget(MaterialApp(theme: ThemeData(fontFamily: 'Cairo'), home: Scaffold(body:
      Directionality(textDirection: TextDirection.rtl, child: MediaQuery(data: const MediaQueryData(textScaler: TextScaler.linear(2)), child:
      RepaintBoundary(key: key, child: SingleChildScrollView(child: AdhanVoiceOption(
        name: 'الشيخ عمرو صبحي', selected: false, playing: false,
        downloaded: false, downloading: false,
        assignmentUnavailableReason: PrayerNotificationService.adhanAssignmentUnavailableReason('adhan_amr_sobhi'),
        onListen: () => listened++, onAssign: () => assigned++, onDownload: () => downloaded++,
      ))))))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    await tester.tap(find.text('استماع'));
    await tester.tap(find.text('تحميل'));
    expect(listened, 1);
    expect(downloaded, 1);
    expect(assigned, 0);
    const capture = String.fromEnvironment('ADHAN_PIXELS_DIR');
    if (capture.isNotEmpty) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$capture/preview-only-option-320-2x.png').writeAsBytesSync(data!.buffer.asUint8List());
        image.dispose();
      });
    }
  });

  for (final (id, name) in [
    ('adhan_jamal_aljaafari', 'الشيخ جمال عبد الحميد الجعفري'),
    ('adhan_ihsan_aldulaimi', 'المؤذن إحسان حميد الدليمي'),
  ]) {
    testWidgets('new preview voice $id stays readable and independently usable at 2x', (tester) async {
      tester.view.physicalSize = const Size(320, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var listened = 0;
      var downloaded = 0;
      var assigned = 0;
      final key = ValueKey(id);
      await tester.pumpWidget(MaterialApp(theme: ThemeData(fontFamily: 'Cairo'), home: Scaffold(body:
        Directionality(textDirection: TextDirection.rtl, child: MediaQuery(data: const MediaQueryData(textScaler: TextScaler.linear(2)), child:
        RepaintBoundary(key: key, child: SingleChildScrollView(child: AdhanVoiceOption(
          name: name, selected: false, playing: false, downloaded: false, downloading: false,
          assignmentUnavailableReason: PrayerNotificationService.adhanAssignmentUnavailableReason(id),
          onListen: () => listened++, onAssign: () => assigned++, onDownload: () => downloaded++,
        ))))))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(name), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
      await tester.tap(find.text('استماع'));
      await tester.tap(find.text('تحميل'));
      expect(listened, 1);
      expect(downloaded, 1);
      expect(assigned, 0);
      const capture = String.fromEnvironment('ADHAN_PIXELS_DIR');
      if (capture.isNotEmpty) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          Directory(capture).createSync(recursive: true);
          File('$capture/$id-320-2x.png').writeAsBytesSync(data!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }

  testWidgets('a supported native voice keeps its assignment button usable', (tester) async {
    var assigned = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdhanVoiceOption(
      name: 'الشيخ محمود خليل الحصري', selected: false, playing: false,
      downloaded: true, downloading: false,
      assignmentUnavailableReason: PrayerNotificationService.adhanAssignmentUnavailableReason('adhan_hussary'),
      onListen: () {}, onAssign: () => assigned++, onDownload: () {},
    ))));
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
    await tester.tap(find.text('تعيين'));
    expect(assigned, 1);
  });

  group('Saved legacy adhan fallback disclosure', () {

  setUpAll(() async {
    await (FontLoader('Cairo')..addFont(Future.value(ByteData.sublistView(File('assets/fonts/Cairo-Regular.ttf').readAsBytesSync())))).load();
    const icons = String.fromEnvironment('MATERIAL_ICONS_FONT');
    if (icons.isNotEmpty) await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(File(icons).readAsBytesSync())))).load();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'notif_master_enabled': false,
      'notif_selected_adhan': 'adhan_haza_albalushi',
      'notif_prayer_voice_الظهر': 'adhan_haza_albalushi',
    });
    await SettingsService.instance.init(forceReload: true);
    await PrayerNotificationService.instance.init(forceReload: true);
  });

  test('supported label unchanged and old unknown is not mislabeled Makkah', () {
    expect(savedAdhanFallbackNotice('adhan_makkah'), isNull);
    expect(getAdhanVoiceName('adhan_makkah'), isNot(contains('مؤقتًا')));
    expect(getAdhanVoiceName('old_unknown_voice'), startsWith('اختيار صوت قديم غير معروف'));
    for (final key in ['adhan_haza_albalushi', 'adhan_sudais', 'adhan_amr_sobhi', 'old_unknown_voice']) {
      expect(savedAdhanFallbackNotice(key), contains('وضع الصامت والاهتزاز'));
      expect(getAdhanVoiceName(key), contains('صوت مكة مؤقتًا'));
    }
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('saved unavailable picker discloses fallback and preserves preferences at $scale', (tester) async {
      tester.view.physicalSize = const Size(360, 840);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final prefs = await SharedPreferences.getInstance();
      final before = {for (final key in prefs.getKeys()) key: prefs.get(key)};
      final boundary = GlobalKey();
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(RepaintBoundary(key: boundary, child: MaterialApp(
        theme: ThemeData(fontFamily: 'Cairo'),
        builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
        home: Scaffold(body: Builder(builder: (context) => TextButton(
          onPressed: () => showPrayerMuezzinDropdownPicker(context, 'الظهر', previewPlayerFactory: () => VoicePreviewPlayer()),
          child: const Text('فتح'),
        ))),
      )));
      await tester.tap(find.text('فتح'));
      await tester.pumpAndSettle();
      final notice = find.byKey(const ValueKey('saved_adhan_fallback_notice'));
      expect(notice, findsOneWidget);
      expect(tester.getSemantics(notice).label, contains('وليس التسجيل المحفوظ'));
      expect(tester.takeException(), isNull);
      const capture = String.fromEnvironment('ADHAN_PIXELS_DIR');
      if (capture.isNotEmpty) {
        final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(boundary));
        await tester.runAsync(() async {
          final image = await render.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          Directory(capture).createSync(recursive: true);
          File('$capture/saved-fallback-${scale}x.png').writeAsBytesSync(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.enterText(find.byType(TextField), 'لايوجدصوتبهذاالاسم');
      await tester.pumpAndSettle();
      expect(notice, findsOneWidget);
      await tester.tap(find.byTooltip('إغلاق'));
      await tester.pumpAndSettle();
      expect({for (final key in prefs.getKeys()) key: prefs.get(key)}, before);
      expect(PrayerNotificationService.instance.getPrayerVoice('الظهر'), 'adhan_haza_albalushi');
      expect(PrayerNotificationService.instance.masterEnabled, isFalse);
      semantics.dispose();
    });
  }

  });
}
