import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/backup_restore_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/features/backup/backup_restore_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var primed = false;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init(forceReload: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'), (call) async =>
      call.method == 'getNotificationAppLaunchDetails' ? null : true);
    if (!primed) {
      await BackupRestoreService.instance.exportBackupJson();
      primed = true;
    }
  });
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: BackupRestoreScreen()));
    await tester.pumpAndSettle();
  }

  Future<void> reach(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
  }

  testWidgets('clipboard refusal is not reported as a successful copy',
      (tester) async {
    final attempted = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        attempted.complete();
        throw PlatformException(code: 'clipboard-denied');
      }
      return null;
    });
    await open(tester);
    final copy = find.text('نسخ كود النسخة الاحتياطية إلى الحافظة');
    await reach(tester, copy);
    await tester.tap(copy);
    for (var i = 0; i < 100 && !attempted.isCompleted; i++) {
      await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(attempted.isCompleted, isTrue);
    expect(find.text('تم نسخ بيانات النسخة الاحتياطية إلى الحافظة بنجاح 📋'),
        findsNothing);
    expect(find.text('تعذر نسخ النسخة الاحتياطية إلى الحافظة. حاول مرة أخرى.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('late clipboard completion does not touch a disposed controller',
      (tester) async {
    final gate = Completer<Object?>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return gate.future;
      return null;
    });
    await open(tester);
    final paste = find.byTooltip('لصق من الحافظة');
    await reach(tester, paste);
    await tester.tap(paste);
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    gate.complete({'text': 'late import'});
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('clipboard read failure is caught and retry remains available',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData')
        throw PlatformException(code: 'clipboard-denied');
      return null;
    });
    await open(tester);
    final paste = find.byTooltip('لصق من الحافظة');
    await reach(tester, paste);
    await tester.tap(paste);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('تعذر قراءة الحافظة. حاول مرة أخرى.'), findsOneWidget);
    expect(tester.widget<IconButton>(find.byWidgetPredicate((w) => w is IconButton && w.tooltip == 'لصق من الحافظة')).onPressed, isNotNull);
  });
  testWidgets('restore confirmation locks the reviewed import and mode',
      (tester) async {
    await open(tester);
    final data = {
      'bookmarks': ['2:255']
    };
    final envelope = jsonEncode({
      'app': 'AlMomin',
      'schema_version': 1,
      'checksum': BackupRestoreService.calculateChecksum(
          BackupRestoreService.canonicalJsonEncode(data)),
      'data': data
    });
    final field = find.byType(TextField);
    await reach(tester, field);
    await tester.enterText(field, envelope);
    await tester.pumpAndSettle();
    final restore = find.text('استبدال واستعادة البيانات');
    await reach(tester, restore);
    await tester.tap(restore);
    await tester.pumpAndSettle();
    expect(find.text('تأكيد الاستبدال الكامل'), findsOneWidget);
    expect(tester.widget<TextField>(field).enabled, isFalse);
    expect(
        tester.widget<IconButton>(find.byWidgetPredicate((w) => w is IconButton && w.tooltip == 'لصق من الحافظة')).onPressed,
        isNull);
    for (final radio in tester
        .widgetList<RadioListTile<bool>>(find.byType(RadioListTile<bool>))) {
      expect(radio.onChanged, isNull);
    }
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).enabled, isTrue);
    expect(tester.takeException(), isNull);
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets('paste failure remains visible at $scale text', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {tester.view.resetPhysicalSize();tester.view.resetDevicePixelRatio();});
      final loader = FontLoader('Cairo');
      loader.addFont(Future.value(ByteData.sublistView(File('assets/fonts/Cairo-Regular.ttf').readAsBytesSync())));
      await loader.load();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') throw PlatformException(code: 'test-denied');
          return null;
        });
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(key: key, child: MaterialApp(
        theme: ThemeData(fontFamily: 'Cairo'),
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
        home: const BackupRestoreScreen())));
      await tester.pumpAndSettle();
      await reach(tester, find.byTooltip('لصق من الحافظة'));
      await tester.tap(find.byTooltip('لصق من الحافظة'));
      await tester.pumpAndSettle();
      final error = find.text('تعذر قراءة الحافظة. حاول مرة أخرى.');
      expect(error, findsOneWidget);
      final rect = tester.getRect(error);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(360));
      expect(rect.bottom, lessThanOrEqualTo(800));
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('/tmp/backup1634/paste-failure-$scale.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    });
  }

}
