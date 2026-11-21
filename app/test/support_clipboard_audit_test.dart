import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/core/services/support_service.dart';
import 'package:almomin/features/settings/contact_support_screen.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  bool reject = true;
  Completer<void>? pending;
  String? copiedText;
  final originalProvider = SupportService.packageInfoProvider;
  final originalLauncher = SupportService.urlLauncher;
  setUp(() {
    reject = true;
    pending = null;
    copiedText = null;
    SupportService.packageInfoProvider = () async => PackageInfo(
        appName: 'test', packageName: 'test', version: '1', buildNumber: '1');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        if (pending != null) await pending!.future;
        if (reject) throw PlatformException(code: 'unavailable');
        copiedText = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
  });
  tearDown(() {
    SupportService.packageInfoProvider = originalProvider;
    SupportService.urlLauncher = originalLauncher;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
  testWidgets('failed email copy never claims successful clipboard write',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ContactSupportScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('نسخ بريد المطور'));
    await tester.pumpAndSettle();
    expect(find.textContaining('تم نسخ البريد'), findsNothing);
    expect(find.textContaining('تعذر النسخ'), findsOneWidget);
  });
  for (final store in [true, false]) {
    testWidgets('failed link fallback copy is visible store=$store',
        (tester) async {
      SupportService.urlLauncher =
          (uri, {mode = LaunchMode.externalApplication}) async => false;
      late BuildContext context;
      await tester
          .pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) {
        context = c;
        return const Text('host');
      }))));
      if (store) {
        await SupportService.openDeveloperPlayStore(context: context);
      } else {
        await SupportService.openDeveloperFacebook(context: context);
      }
      await tester.pumpAndSettle();
      expect(find.textContaining('تم نسخ رابط'), findsNothing);
      expect(find.textContaining('تعذر النسخ'), findsOneWidget);
    });
  }
  testWidgets('pending copy is silent, then success follows confirmation',
      (tester) async {
    pending = Completer<void>();
    reject = false;
    await tester.pumpWidget(const MaterialApp(home: ContactSupportScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('نسخ بريد المطور'));
    await tester.pump();
    expect(find.textContaining('تم نسخ البريد'), findsNothing);
    expect(copiedText, isNull);
    pending!.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('تم نسخ البريد'), findsOneWidget);
    expect(copiedText, SupportService.developerEmail);
  });
  testWidgets('copy completion after screen disposal stays quiet',
      (tester) async {
    pending = Completer<void>();
    await tester.pumpWidget(const MaterialApp(home: ContactSupportScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('نسخ بريد المطور'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    pending!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  for (final fail in [true, false]) {
    testWidgets('full message waits for clipboard result fail=$fail',
        (tester) async {
      reject = fail;
      pending = Completer<void>();
      await tester.pumpWidget(const MaterialApp(home: ContactSupportScreen()));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Subject');
      await tester.enterText(fields.at(1), 'Message');
      final button = find.text('نسخ الرسالة بالكامل للحافظة');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
          find.textContaining('تم نسخ الرسالة بالكامل وعنوان'), findsNothing);
      pending!.complete();
      await tester.pumpAndSettle();
      if (fail) {
        expect(find.textContaining('تعذر النسخ'), findsOneWidget);
        expect(copiedText, isNull);
      } else {
        expect(find.textContaining('تم نسخ الرسالة بالكامل وعنوان'),
            findsOneWidget);
        expect(copiedText, contains('Subject'));
        expect(copiedText, contains('Message'));
      }
    });
  }
  for (final scale in [1.0, 2.0]) {
    testWidgets('clipboard failure text fits and is exposed at $scale',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await (FontLoader('Cairo')
            ..addFont(Future.value(ByteData.sublistView(
                File('assets/fonts/Cairo-Regular.ttf').readAsBytesSync()))))
          .load();
      const icons = String.fromEnvironment('MATERIAL_ICONS_FONT');
      if (icons.isNotEmpty)
        await (FontLoader('MaterialIcons')
              ..addFont(Future.value(
                  ByteData.sublistView(File(icons).readAsBytesSync()))))
            .load();
      final boundary = GlobalKey();
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(fontFamily: 'Cairo'),
              builder: (c, child) => MediaQuery(
                  data: MediaQuery.of(c)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: const ContactSupportScreen())));
      await tester.pumpAndSettle();
      final copyNode = tester.getSemantics(find.bySemanticsLabel(
          'نسخ بريد المطور: ${SupportService.developerEmail}'));
      expect(copyNode.getSemanticsData().hasAction(ui.SemanticsAction.tap),
          isTrue);
      tester.binding.renderViews.first.owner!.semanticsOwner!
          .performAction(copyNode.id, ui.SemanticsAction.tap);
      await tester.pumpAndSettle();
      final error = find.textContaining('تعذر النسخ');
      expect(error, findsOneWidget);
      expect(tester.getSemantics(error).label, contains('لم تُنسخ البيانات'));
      final rect = tester.getRect(error);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(360));
      expect(rect.bottom, lessThanOrEqualTo(800));
      expect(tester.takeException(), isNull);
      const directory = String.fromEnvironment('SUPPORT_CLIPBOARD_PIXELS');
      if (directory.isNotEmpty)
        await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$directory/copy-failure-$scale.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      semantics.dispose();
    });
  }
}
