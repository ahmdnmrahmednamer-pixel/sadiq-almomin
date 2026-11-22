import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/audio/kiwifu_adhan_catalog.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/notifications/prayer_notification_service.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/features/settings/widgets/adhan_voice_option.dart';
import 'package:almomin/features/settings/widgets/settings_adhan_voice_modal.dart';
import 'prayer_voice_preview_ownership_test.dart' show VoicePreviewPlayer;

Future<void> capture(WidgetTester t, GlobalKey key, String name) async {
  const directory = String.fromEnvironment('KIWIFU_PIXELS');
  if (directory.isEmpty) return;
  await t.pumpAndSettle();
  await t.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
            .toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(directory).createSync(recursive: true);
    await File('$directory/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('Cairo');
    for (final weight in ['Regular', 'Bold']) {
      final file = File('assets/fonts/Cairo-$weight.ttf');
      if (file.existsSync()) {
        font.addFont(
            Future.value(ByteData.sublistView(file.readAsBytesSync())));
      }
    }
    await font.load();
    const icons = String.fromEnvironment('MATERIAL_ICONS_FONT');
    if (icons.isNotEmpty) {
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(
                ByteData.sublistView(File(icons).readAsBytesSync()))))
          .load();
    }
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'app_language': 'ar', 'notif_master_enabled': false});
    await SettingsService.instance.init(forceReload: true);
    IslamicAudioService.instance.disableNativePlayerForTesting = true;
  });
  tearDown(() async {
    await IslamicAudioService.instance.stop();
    IslamicAudioService.instance.disableNativePlayerForTesting = false;
  });
  final longest = kiwifuAdhanCatalog
      .reduce((a, b) => a.title.length > b.title.length ? a : b);
  for (final mode in AppThemeMode.values) {
    testWidgets(
        'long source filename has reachable independent actions at 2x ${mode.name}',
        (t) async {
      t.view.physicalSize = const Size(360, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final semantics = t.ensureSemantics();
      try {
        var listen = 0, download = 0, assign = 0;
        final key = GlobalKey();
        await t.pumpWidget(RepaintBoundary(
            key: key,
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AppTheme.of(mode),
                builder: (c, child) => MediaQuery(
                    data: MediaQuery.of(c)
                        .copyWith(textScaler: const TextScaler.linear(2)),
                    child: Directionality(
                        textDirection: TextDirection.rtl, child: child!)),
                home: Scaffold(
                    body: Directionality(
                        textDirection: TextDirection.rtl,
                        child: SingleChildScrollView(
                            child: AdhanVoiceOption(
                                name: adhanVoiceLabel(longest),
                                semanticName:
                                    '${longest.title}، اسم حسب المصدر غير موثق',
                                sourceDetails: adhanSourceDetails(longest),
                                assignmentUnavailableMessage:
                                    'للاستماع والتحميل فقط',
                                selected: false,
                                playing: false,
                                downloaded: false,
                                downloading: false,
                                assignmentUnavailableReason:
                                    PrayerNotificationService
                                        .adhanAssignmentUnavailableReason(
                                            longest.id),
                                onListen: () => listen++,
                                onDownload: () => download++,
                                onAssign: () => assign++)))))));
        await t.pumpAndSettle();
        expect(find.text(longest.title), findsOneWidget);
        expect(t.takeException(), isNull);
        expect(find.text('للاستماع والتحميل فقط'), findsOneWidget);
        expect(
            find.bySemanticsLabel('${longest.title}، اسم حسب المصدر غير موثق'),
            findsOneWidget);
        await t.tap(find.byTooltip('معلومات المصدر'));
        await t.pumpAndSettle();
        expect(
            find.textContaining(longest.sourceFileNames.first), findsOneWidget);
        await capture(t, key, 'source-details-${mode.name}');
        await t.tap(find.text('إغلاق'));
        await t.pumpAndSettle();
        expect(t.widget<Text>(find.text(longest.title)).maxLines, isNull);
        expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed,
            isNull);
        await capture(t, key, 'longest-${mode.name}-top');
        await t.scrollUntilVisible(find.text('تحميل'), 150);
        await t.pumpAndSettle();
        await t.tap(find.text('استماع'));
        await t.tap(find.text('تحميل'));
        expect(listen, 1);
        expect(download, 1);
        expect(assign, 0);
        expect(t.takeException(), isNull);
        await capture(t, key, 'longest-${mode.name}-actions');
        await t.pumpWidget(const SizedBox());
      } finally {
        semantics.dispose();
      }
    });
  }
  testWidgets(
      'real prayer picker finds all 230 source recordings without assigning one',
      (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final key = GlobalKey();
    final prefs = await SharedPreferences.getInstance();
    final before = {for (final k in prefs.getKeys()) k: prefs.get(k)};
    await t.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.darkTheme,
            builder: (c, child) => MediaQuery(
                data: MediaQuery.of(c)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: Directionality(
                    textDirection: TextDirection.rtl, child: child!)),
            home: Scaffold(
                body: Builder(
                    builder: (context) => TextButton(
                        onPressed: () => showPrayerMuezzinDropdownPicker(
                            context, 'الظهر',
                            previewPlayerFactory: () => VoicePreviewPlayer()),
                        child: const Text('فتح الأصوات')))))));
    await t.tap(find.text('فتح الأصوات'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'Kiwifu');
    await t.pumpAndSettle();
    final list = t.widget<ListView>(find.byType(ListView).last);
    expect(
        (list.childrenDelegate as SliverChildBuilderDelegate).childCount, 230);
    expect(find.text(kiwifuAdhanCatalog.first.title), findsOneWidget);
    expect(t.widget<FilledButton>(find.byType(FilledButton).first).onPressed,
        isNull);
    expect({for (final k in prefs.getKeys()) k: prefs.get(k)}, before);
    expect(t.takeException(), isNull);
    await capture(t, key, 'picker-dark-2x');
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  });
}
