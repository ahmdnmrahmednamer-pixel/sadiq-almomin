import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/audio/kiwifu_adhan_catalog.dart';
import 'package:almomin/core/notifications/prayer_notification_service.dart';
import 'package:almomin/core/services/downloaded_adhan_sound_store.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/features/settings/widgets/adhan_voice_option.dart';
import 'package:almomin/features/settings/widgets/settings_adhan_voice_modal.dart';
import 'prayer_voice_preview_ownership_test.dart' show VoicePreviewPlayer;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final longest = kiwifuAdhanCatalog
      .reduce((a, b) => a.title.length > b.title.length ? a : b);
  final saved = kiwifuAdhanCatalog.first;
  late Directory root;
  setUpAll(() async {
    root = Directory.systemTemp.createTempSync('native-adhan-ui-');
    for (final family in ['Cairo', 'Amiri']) {
      final loader = FontLoader(family);
      for (final weight in ['Regular', 'Bold']) {
        final file = File('assets/fonts/$family-$weight.ttf');
        if (file.existsSync()) {
          loader.addFont(
              Future.value(ByteData.sublistView(file.readAsBytesSync())));
        }
      }
      await loader.load();
    }
    const icons = String.fromEnvironment('MATERIAL_ICONS_FONT');
    if (icons.isNotEmpty) {
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(
                ByteData.sublistView(File(icons).readAsBytesSync()))))
          .load();
    }
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => root.path);
    messenger.setMockMethodCallHandler(
        const MethodChannel('flutter_timezone'), (_) async => 'Africa/Cairo');
    messenger.setMockMethodCallHandler(
        const MethodChannel('dexterous.com/flutter/local_notifications'),
        (call) async {
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'pendingNotificationRequests' ||
          call.method == 'getActiveNotifications') {
        return [];
      }
      return true;
    });
    IslamicAudioService.instance.disableNativePlayerForTesting = true;
  });
  tearDownAll(() async {
    PrayerNotificationService.instance.downloadedAdhanPreparerForTesting = null;
    if (root.existsSync()) root.deleteSync(recursive: true);
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'app_language': 'ar', 'notif_master_enabled': false});
    await SettingsService.instance.init(forceReload: true);
    await PrayerNotificationService.instance.init(forceReload: true);
  });
  test(
      'missing pinned choice never claims a Makkah fallback, while legacy containment remains unchanged',
      () {
    expect(savedAdhanFallbackNotice(saved.id), isNotNull);
    expect(savedAdhanFallbackNotice(saved.id), isNot(contains('مكة')));
    expect(getAdhanVoiceName(saved.id), contains('إعادة تحميل'));
    expect(getAdhanVoiceName(saved.id), isNot(contains('مكة')));
    expect(savedAdhanFallbackNotice('adhan_jamal_aljaafari'), contains('مكة'));
    expect(adhanSourceDetails(saved), contains('دون إنترنت'));
    expect(adhanSourceDetails(saved),
        contains('التأجيل يستخدم تنبيه الجهاز المعتاد'));
  });
  for (final mode in AppThemeMode.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
          'prepared-card actions and real missing-choice picker ${mode.name} ${scale}x',
          (tester) async {
        tester.view.physicalSize = const Size(360, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        final key = GlobalKey();
        Widget app(Widget home) => RepaintBoundary(
            key: key,
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AppTheme.of(mode),
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: Directionality(
                        textDirection: TextDirection.rtl, child: child!)),
                home: home));
        Future<void> capture(String state) async {
          const output = String.fromEnvironment('NATIVE_ADHAN_PIXELS');
          if (output.isEmpty) return;
          await tester.runAsync(() async {
            Directory(output).createSync(recursive: true);
            final image = await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            await File('$output/${mode.name}-${scale}x-$state.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        try {
          // Render an enabled, already-prepared card. The native boundary is
          // mocked here; separate byte/provider/consumer suites verify it.
          PrayerNotificationService.instance.downloadedAdhanPreparerForTesting =
              (_) async => PreparedDownloadedAdhan(
                  uri: Uri(
                      scheme: 'content',
                      host: DownloadedAdhanSoundStore.authority,
                      pathSegments: [
                        'v1',
                        longest.remoteGitBlobSha1!,
                        longest.fileSizeBytes.toString()
                      ]).toString(),
                  blobSha1: longest.remoteGitBlobSha1!,
                  sizeBytes: longest.fileSizeBytes!);
          Future<void>? assignment;
          var listens = 0;
          await tester.pumpWidget(app(Scaffold(
              body: SingleChildScrollView(
                  child: AdhanVoiceOption(
            name: adhanVoiceLabel(longest),
            semanticName: '${longest.title}، اسم حسب المصدر غير موثق',
            sourceDetails: adhanSourceDetails(longest),
            selected: false,
            playing: false,
            downloaded: true,
            downloading: false,
            onListen: () => listens++,
            onDownload: () => fail('Already downloaded'),
            onAssign: () {
              assignment = PrayerNotificationService.instance
                  .setPrayerVoice('الظهر', longest.id);
            },
          )))));
          await tester.pumpAndSettle();
          await capture('prepared-card');
          expect(tester.takeException(), isNull);
          expect(find.text('تحميل'), findsNothing);
          await tester.ensureVisible(find.text('تعيين'));
          await tester.pumpAndSettle();
          final assign = find.widgetWithText(FilledButton, 'تعيين');
          final node = tester.getSemantics(assign);
          expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
              isTrue);
          tester.binding.pipelineOwner.semanticsOwner!
              .performAction(node.id, ui.SemanticsAction.tap);
          await tester.pumpAndSettle();
          await assignment;
          expect(PrayerNotificationService.instance.getPrayerVoice('الظهر'),
              longest.id);
          await tester.tap(find.text('استماع'));
          expect(listens, 1);
          await tester.tap(find.byTooltip('معلومات المصدر'));
          await tester.pumpAndSettle();
          await capture('source-details');
          final detailsScroll = find
              .descendant(
                  of: find.byType(AlertDialog),
                  matching: find.byType(Scrollable))
              .first;
          await tester.drag(detailsScroll, const Offset(0, -10000));
          await tester.pumpAndSettle();
          expect(
              tester.state<ScrollableState>(detailsScroll).position.extentAfter,
              closeTo(0, 0.1));
          await capture('source-details-end');
          expect(find.textContaining('التأجيل يستخدم تنبيه الجهاز المعتاد'),
              findsOneWidget);
          await tester.tap(find.text('إغلاق'));
          await tester.pumpAndSettle();
          await tester.pumpWidget(const SizedBox());
          var staged = 0;
          await tester.pumpWidget(app(Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                      onPressed: () => showPrayerMuezzinDropdownPicker(
                          context, 'الظهر',
                          selectedVoice: saved.id,
                          previewPlayerFactory: () => VoicePreviewPlayer(),
                          onStage: (_) => staged++),
                      child: const Text('فتح الأصوات'))))));
          await tester.tap(find.text('فتح الأصوات'));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), 'Kiwifu');
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('saved_adhan_fallback_notice')),
              findsOneWidget);
          expect(find.textContaining('لا نستبدله بصوت آخر'), findsOneWidget);
          await capture('missing-saved-choice');
          final firstCard = find.byKey(ValueKey('voice_${saved.id}'));
          await tester.scrollUntilVisible(firstCard, 120,
              scrollable: find.byType(Scrollable).last);
          await tester.pumpAndSettle();
          final disabled = find.descendant(
              of: firstCard, matching: find.byType(FilledButton));
          expect(tester.widget<FilledButton>(disabled).onPressed, isNull);
          expect(staged, 0);
          expect(tester.takeException(), isNull);
          await capture('missing-download-first');
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        } finally {
          semantics.dispose();
        }
      });
    }
  }
}
