import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/core/services/support_service.dart';
import 'package:almomin/features/settings/contact_support_screen.dart';
import 'package:almomin/features/settings/settings_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  final originalProvider = SupportService.packageInfoProvider;
  setUp(() {
    SupportService.packageInfoProvider = () async => PackageInfo(
      appName: 'test', packageName: 'org.test', version: '9.8.7', buildNumber: '654');
  });
  tearDown(() { SupportService.packageInfoProvider = originalProvider; });
  group('SupportService Unit Tests', () {
    test('runtime version and overridden build are used in outgoing diagnostics', () async {
      Uri? sent;
      SupportService.urlLauncher = (uri, {mode = LaunchMode.externalApplication}) async {
        sent = uri; return true;
      };
      expect(await SupportService.loadVersionDiagnostic(), 'v9.8.7 (Build 654)');
      expect(await SupportService.sendSupportEmail(subject: 'test', content: 'body',
        category: SupportCategory.inquiry), isTrue);
      expect(sent!.queryParameters['body'], contains('v9.8.7 (Build 654)'));
      expect(sent!.queryParameters['body'], isNot(contains('Build 12')));
    });
    test('missing or failed runtime metadata never claims a hardcoded build', () async {
      SupportService.packageInfoProvider = () async => throw StateError('not available');
      expect(await SupportService.loadVersionDiagnostic(), 'غير متاح');
      SupportService.packageInfoProvider = () async => PackageInfo(
        appName: 'test', packageName: 'test', version: '', buildNumber: '');
      expect(await SupportService.loadVersionDiagnostic(), 'غير متاح');
    });

    test('Developer email is set to ahmdnmrahmednamer@gmail.com', () {
      expect(SupportService.developerEmail, 'ahmdnmrahmednamer@gmail.com');
    });

    test('buildEmailSubject formats subject with Arabic category and app tag', () {
      final subject = SupportService.buildEmailSubject(
        subject: 'إضافة تذكير قيام الليل',
        category: SupportCategory.suggestion,
      );
      expect(subject, '[تطبيق صديق المؤمن - اقتراح تطوير ميزة] إضافة تذكير قيام الليل');
    });

    test('buildEmailBody includes message, diagnostics, and Momin Ibrahim dedication', () {
      final body = SupportService.buildEmailBody(
        content: 'جزاكم الله خيراً، أرجو إضافة إشعار ربع حزب يومياً',
        category: SupportCategory.inquiry,
        senderName: 'عبد الرحمن',
        senderContact: 'abdurrahman@example.com',
      );

      expect(body, contains('السلام عليكم ورحمة الله وبركاته'));
      expect(body, contains('جزاكم الله خيراً، أرجو إضافة إشعار ربع حزب يومياً'));
      expect(body, contains('• التصنيف: استفسار عام أو ملاحظة'));
      expect(body, contains('• اسم الراسل: عبد الرحمن'));
      expect(body, contains('• وسيلة التواصل: abdurrahman@example.com'));
      expect(body, contains('• إصدار تطبيق صديق المؤمن: غير متاح'));
      expect(body, contains('تطبيق «صديق المؤمن»'));
    });

    test('createMailtoUri constructs valid RFC mailto URI with query params', () {
      final uri = SupportService.createMailtoUri(
        subject: 'موضوع تجريبي',
        body: 'محتوى الرسالة',
      );

      expect(uri.scheme, 'mailto');
      expect(uri.path, 'ahmdnmrahmednamer@gmail.com');
      expect(uri.query, contains('subject='));
      expect(uri.query, contains('body='));
    });

    test('sendSupportEmail calls urlLauncher with externalApplication mode', () async {
      Uri? capturedUri;
      LaunchMode? capturedMode;

      SupportService.urlLauncher = (Uri uri, {LaunchMode mode = LaunchMode.externalApplication}) async {
        capturedUri = uri;
        capturedMode = mode;
        return true;
      };

      final result = await SupportService.sendSupportEmail(
        subject: 'اقتراح ميزة',
        content: 'نص المقترح هنا للتجربة',
        category: SupportCategory.suggestion,
        senderName: 'أحمد',
      );

      expect(result, isTrue);
      expect(capturedUri, isNotNull);
      expect(capturedUri!.scheme, 'mailto');
      expect(capturedUri!.path, 'ahmdnmrahmednamer@gmail.com');
      expect(capturedMode, LaunchMode.externalApplication);
    });

    test('sendSupportEmail returns false gracefully on error or failure', () async {
      SupportService.urlLauncher = (Uri uri, {LaunchMode mode = LaunchMode.externalApplication}) async {
        throw Exception('Simulated launcher error');
      };

      final result = await SupportService.sendSupportEmail(
        subject: 'تقرير خطأ',
        content: 'تعذر تشغيل الصوت',
        category: SupportCategory.bugReport,
      );

      expect(result, isFalse);
    });
  });

  group('ContactSupportScreen Widget Tests', () {
    testWidgets('copy path uses runtime metadata and handles disposal while loading', (tester) async {
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
          return null;
        });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.pumpWidget(const MaterialApp(home: ContactSupportScreen()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'test subject');
      await tester.enterText(find.byType(TextFormField).at(1), 'test body');
      final copy = find.text('نسخ الرسالة بالكامل للحافظة');
      await tester.ensureVisible(copy);
      await tester.tap(copy);
      await tester.pumpAndSettle();
      expect(copied, contains('v9.8.7 (Build 654)'));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      copied = null;
      final pending = Completer<PackageInfo>();
      SupportService.packageInfoProvider = () => pending.future;
      await tester.ensureVisible(copy);
      await tester.tap(copy);
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      pending.complete(PackageInfo(appName: 'test', packageName: 'test', version: '1', buildNumber: '2'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(copied, isNull);
    });

    setUp(() {
      SupportService.urlLauncher = (Uri uri, {LaunchMode mode = LaunchMode.externalApplication}) async {
        return true;
      };
    });

    testWidgets('renders all form components, developer email and dedication card', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ContactSupportScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('الدعم والتواصل مع المطور'), findsOneWidget);
      expect(find.textContaining('تطبيق صديق المؤمن — في خدمتكم دوماً لوجه الله تعالى'), findsOneWidget);
      expect(find.text('ahmdnmrahmednamer@gmail.com'), findsOneWidget);
      expect(find.text('نوع الرسالة:'), findsOneWidget);
      expect(find.text('اقتراح تطوير ميزة'), findsOneWidget);
      expect(find.text('إبلاغ عن مشكلة أو خطأ'), findsOneWidget);
      expect(find.text('إرسال الرسالة إلى المطور'), findsOneWidget);
      expect(find.text('نسخ الرسالة بالكامل للحافظة'), findsOneWidget);
    });

    testWidgets('form validation fails when subject or message is empty', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ContactSupportScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final sendBtn = find.text('إرسال الرسالة إلى المطور');
      await tester.ensureVisible(sendBtn);
      await tester.tap(sendBtn);
      await tester.pumpAndSettle();

      expect(find.text('يرجى كتابة عنوان الرسالة أو الموضوع'), findsOneWidget);
      expect(find.text('يرجى كتابة تفاصيل الرسالة'), findsOneWidget);
    });

    testWidgets('successful submit triggers email sending and shows success snackbar', (tester) async {
      bool launcherInvoked = false;
      SupportService.urlLauncher = (Uri uri, {LaunchMode mode = LaunchMode.externalApplication}) async {
        launcherInvoked = true;
        return true;
      };

      await tester.pumpWidget(
        const MaterialApp(
          home: ContactSupportScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Enter subject and message
      final textFields = find.byType(TextFormField);
      await tester.enterText(textFields.at(0), 'إضافة ويدجت لمواقيت الصلاة');
      await tester.enterText(textFields.at(1), 'السلام عليكم، حبذا إضافة ويدجت شاشة رئيسية لمواقيت الصلاة');
      await tester.pumpAndSettle();

      final sendBtn = find.text('إرسال الرسالة إلى المطور');
      await tester.ensureVisible(sendBtn);
      await tester.tap(sendBtn);
      await tester.pumpAndSettle();

      expect(launcherInvoked, isTrue);
      expect(find.textContaining('جاري فتح تطبيق البريد الإلكتروني'), findsOneWidget);
    });

    testWidgets('failed submit opens fallback dialog offering manual copy', (tester) async {
      SupportService.urlLauncher = (Uri uri, {LaunchMode mode = LaunchMode.externalApplication}) async {
        return false;
      };

      await tester.pumpWidget(
        const MaterialApp(
          home: ContactSupportScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final textFields = find.byType(TextFormField);
      await tester.enterText(textFields.at(0), 'استفسار عن تفسير الآية');
      await tester.enterText(textFields.at(1), 'هل يمكن إضافة إمكانية تكبير خط التفسير؟');
      await tester.pumpAndSettle();

      final sendBtn = find.text('إرسال الرسالة إلى المطور');
      await tester.ensureVisible(sendBtn);
      await tester.tap(sendBtn);
      await tester.pumpAndSettle();

      expect(find.text('فتح تطبيق البريد'), findsOneWidget);
      expect(find.textContaining('تعذر فتح تطبيق البريد الإلكتروني تلقائياً'), findsOneWidget);
      expect(find.text('نسخ الرسالة بالكامل'), findsOneWidget);
    });

    testWidgets('SettingsScreen includes Contact Support tile', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('settings_category_5')));
      await tester.pumpAndSettle();
      final tile = find.text('الدعم');
      await tester.scrollUntilVisible(
        tile,
        300,
        scrollable: find.byWidgetPredicate((w) => w is Scrollable && (w.axisDirection == AxisDirection.down || w.axisDirection == AxisDirection.up)),
      );
      expect(tile, findsOneWidget);
      final supportTile = find.ancestor(of: tile, matching: find.byType(ListTile));
      expect(supportTile, findsOneWidget);
      expect(tester.widget<ListTile>(supportTile).subtitle, isNull);
      await tester.ensureVisible(supportTile);
      await tester.pumpAndSettle();
      expect(supportTile.hitTestable(), findsOneWidget);
      await tester.tap(supportTile);
      await tester.pumpAndSettle();
      expect(find.byType(ContactSupportScreen), findsOneWidget);
    });
  });
}
