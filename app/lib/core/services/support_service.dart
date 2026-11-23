import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../theme/app_theme.dart';

enum SupportCategory {
  suggestion('اقتراح تطوير ميزة'),
  bugReport('إبلاغ عن مشكلة أو خطأ'),
  inquiry('استفسار عام أو ملاحظة'),
  appreciation('شكر وتقدير للمطور');

  final String titleAr;
  const SupportCategory(this.titleAr);
}

class SupportService {
  static const String developerName = 'أحمد إبراهيم (Ahmed Ibrahim)';
  static const String developerEmail = 'ahmdnmrahmednamer@gmail.com';
  @visibleForTesting
  static Future<PackageInfo> Function() packageInfoProvider = PackageInfo.fromPlatform;

  static Future<String> loadVersionDiagnostic() async {
    try {
      final info = await packageInfoProvider();
      final version = info.version.trim();
      final build = info.buildNumber.trim();
      if (version.isNotEmpty && build.isNotEmpty) return 'v$version (Build $build)';
    } catch (_) {}
    return 'غير متاح';
  }
  static const String githubRepoUrl =
      'https://github.com/ahmdnmrahmednamer-pixel/sadiq-almomin.git';
  static const String developerPlayStoreUrl =
      'https://play.google.com/store/apps/developer?id=Ahmed+Ibrahim';
  static const String developerPlayStoreMarketUri =
      'market://search?q=pub:Ahmed+Ibrahim';
  static const String developerFacebookUrl =
      'https://www.facebook.com/ahmdnmrahmednamer';

  /// URL launcher delegate for testability
  static Future<bool> Function(Uri uri, {LaunchMode mode}) urlLauncher =
      (Uri uri, {LaunchMode mode = LaunchMode.externalApplication}) =>
          launchUrl(uri, mode: mode);

  /// Opens developer apps on Google Play Store with fallback to clipboard
  static Future<bool> openDeveloperPlayStore({required BuildContext context}) async {
    final marketUri = Uri.parse(developerPlayStoreMarketUri);
    final webUri = Uri.parse(developerPlayStoreUrl);

    try {
      final launchedMarket = await urlLauncher(marketUri);
      if (launchedMarket) return true;
    } catch (_) {}

    try {
      final launchedWeb = await urlLauncher(webUri);
      if (launchedWeb) return true;
    } catch (_) {}

    if (!context.mounted) return false;

    await copyWithFeedback(
      context: context, text: developerPlayStoreUrl,
      successMessage: 'تم نسخ رابط برامج المطور على متجر Google Play إلى الحافظة بنجاح',
    );
    return false;
  }

  /// Opens developer Facebook account with fallback to clipboard
  static Future<bool> openDeveloperFacebook({required BuildContext context}) async {
    final webUri = Uri.parse(developerFacebookUrl);

    try {
      final launched = await urlLauncher(webUri);
      if (launched) return true;
    } catch (_) {}

    if (!context.mounted) return false;

    await copyWithFeedback(
      context: context, text: developerFacebookUrl,
      successMessage: 'تم نسخ رابط حساب المطور على فيسبوك إلى الحافظة بنجاح',
    );
    return false;
  }

  /// Builds a formatted email subject
  static String buildEmailSubject({
    required String subject,
    required SupportCategory category,
  }) {
    final cleanSubject = subject.trim();
    return '[تطبيق صديق المؤمن - ${category.titleAr}] $cleanSubject';
  }

  /// Builds a rich, structured email body including dedication and diagnostics
  static String buildEmailBody({
    required String content,
    required SupportCategory category,
    String? senderName,
    String? senderContact,
    String versionDiagnostic = 'غير متاح',
  }) {
    final buffer = StringBuffer();
    buffer.writeln('السلام عليكم ورحمة الله وبركاته،');
    buffer.writeln();
    buffer.writeln(content.trim());
    buffer.writeln();
    buffer.writeln('--------------------------------------------------');
    buffer.writeln('📋 بيانات الرسالة والدعم الفني:');
    buffer.writeln('• التصنيف: ${category.titleAr}');
    if (senderName != null && senderName.trim().isNotEmpty) {
      buffer.writeln('• اسم الراسل: ${senderName.trim()}');
    }
    if (senderContact != null && senderContact.trim().isNotEmpty) {
      buffer.writeln('• وسيلة التواصل: ${senderContact.trim()}');
    }
    buffer.writeln('• إصدار تطبيق صديق المؤمن: $versionDiagnostic');
    try {
      buffer.writeln('• نظام التشغيل: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    } catch (_) {
      buffer.writeln('• نظام التشغيل: Android / Mobile Platform');
    }
    buffer.writeln('• تاريخ الإرسال: ${DateTime.now().toString().split('.').first}');
    buffer.writeln('--------------------------------------------------');
    buffer.writeln('تطبيق «صديق المؤمن» — رفيقك اليومي للقرآن والعبادات');

    return buffer.toString();
  }

  /// Encodes query parameters safely for mailto RFC
  static String? encodeQueryParameters(Map<String, String> params) {
    return params.entries
        .map((MapEntry<String, String> e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
  }

  /// Constructs the mailto Uri
  static Uri createMailtoUri({
    required String subject,
    required String body,
    String recipient = developerEmail,
  }) {
    return Uri(
      scheme: 'mailto',
      path: recipient,
      query: encodeQueryParameters(<String, String>{
        'subject': subject,
        'body': body,
      }),
    );
  }

  /// Launches the user's default email client
  static Future<bool> sendSupportEmail({
    required String subject,
    required String content,
    required SupportCategory category,
    String? senderName,
    String? senderContact,
  }) async {
    final formattedSubject = buildEmailSubject(
      subject: subject,
      category: category,
    );

    final formattedBody = buildEmailBody(
      content: content,
      category: category,
      senderName: senderName,
      senderContact: senderContact,
      versionDiagnostic: await loadVersionDiagnostic(),
    );

    final uri = createMailtoUri(
      subject: formattedSubject,
      body: formattedBody,
      recipient: developerEmail,
    );

    try {
      return await urlLauncher(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// Copies support email or full text to clipboard
  static Future<bool> copyToClipboard(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Announce the result only after the platform confirms the clipboard write.
  static Future<bool> copyWithFeedback({
    required BuildContext context,
    required String text,
    required String successMessage,
  }) async {
    final copied = await copyToClipboard(text);
    if (!context.mounted) return copied;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(copied ? successMessage : 'تعذر النسخ إلى الحافظة. لم تُنسخ البيانات. حاول مرة أخرى.'),
      backgroundColor: copied ? AppColors.primaryGreen : Colors.red.shade700,
      duration: Duration(seconds: copied ? 3 : 8),
    ));
    return copied;
  }
}
