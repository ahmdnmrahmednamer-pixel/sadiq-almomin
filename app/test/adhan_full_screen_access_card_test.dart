import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/features/prayer/widgets/adhan_full_screen_access_card.dart';

void main() {
  testWidgets(
      'entry is read-only and denied request retains notification fallback',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const query = MethodChannel('almomin/adhan_permissions');
    const plugin = MethodChannel('dexterous.com/flutter/local_notifications');
    var queries = 0;
    var requests = 0;
    m.setMockMethodCallHandler(query, (call) async {
      queries++;
      return false;
    });
    m.setMockMethodCallHandler(plugin, (call) async {
      requests++;
      return false;
    });
    addTearDown(() {
      m.setMockMethodCallHandler(query, null);
      m.setMockMethodCallHandler(plugin, null);
      debugDefaultTargetPlatformOverride = null;
    });
    try {
      await t.pumpWidget(const MaterialApp(
          home: Scaffold(
              body:
                  SingleChildScrollView(child: AdhanFullScreenAccessCard()))));
      await t.pumpAndSettle();
      expect(queries, 1);
      expect(requests, 0);
      expect(find.text('إذن الشاشة الكاملة غير مسموح'), findsOneWidget);
      expect(find.textContaining('الإشعار العادي'), findsOneWidget);
      final request = find.byKey(const ValueKey('adhan_full_screen_request'));
      await t.ensureVisible(request);
      await t.tap(request);
      await t.pumpAndSettle();
      expect(requests, 1);
      expect(queries, 2);
      expect(find.text('إذن الشاشة الكاملة غير مسموح'), findsOneWidget);
      expect(t.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
  testWidgets('resume rechecks revoked access without a permission request',
      (t) async {
    const query = MethodChannel('almomin/adhan_permissions');
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    bool? allowed = true;
    var queries = 0;
    m.setMockMethodCallHandler(query, (call) async {
      queries++;
      return allowed;
    });
    addTearDown(() => m.setMockMethodCallHandler(query, null));
    await t.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(child: AdhanFullScreenAccessCard()))));
    await t.pumpAndSettle();
    expect(find.text('إذن الشاشة الكاملة مسموح'), findsOneWidget);
    allowed = false;
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(queries, 2);
    expect(find.text('إذن الشاشة الكاملة غير مسموح'), findsOneWidget);
    allowed = null;
    await t.tap(find.text('إعادة فحص إذن الشاشة الكاملة'));
    await t.pumpAndSettle();
    expect(find.text('تعذر التحقق من إذن الشاشة الكاملة'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('semantic request uses OS readback and hides request after grant',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const query = MethodChannel('almomin/adhan_permissions');
    const plugin = MethodChannel('dexterous.com/flutter/local_notifications');
    var granted = false;
    var requests = 0;
    m.setMockMethodCallHandler(query, (call) async => granted);
    m.setMockMethodCallHandler(plugin, (call) async {
      requests++;
      granted = true;
      return false;
    });
    addTearDown(() {
      m.setMockMethodCallHandler(query, null);
      m.setMockMethodCallHandler(plugin, null);
      debugDefaultTargetPlatformOverride = null;
    });
    final semantics = t.ensureSemantics();

    await t.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(child: AdhanFullScreenAccessCard()))));
    await t.pumpAndSettle();
    final request = find.byKey(const ValueKey('adhan_full_screen_request'));
    await t.ensureVisible(request);
    await t.pumpAndSettle();
    t.binding.performSemanticsAction(ui.SemanticsActionEvent(
        type: ui.SemanticsAction.tap,
        nodeId: t.getSemantics(request).id,
        viewId: t.view.viewId));
    await t.pumpAndSettle();
    expect(requests, 1);
    expect(find.text('إذن الشاشة الكاملة مسموح'), findsOneWidget);
    expect(request, findsNothing);
    semantics.dispose();
    debugDefaultTargetPlatformOverride = null;
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('stale entry result cannot overwrite a newer resume readback',
      (t) async {
    final pending = Completer<bool?>();
    var calls = 0;
    const query = MethodChannel('almomin/adhan_permissions');
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(query, (call) {
      calls++;
      return calls == 1 ? pending.future : Future.value(true);
    });
    addTearDown(() => m.setMockMethodCallHandler(query, null));
    await t.pumpWidget(
        const MaterialApp(home: Scaffold(body: AdhanFullScreenAccessCard())));
    await t.pump();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(find.text('إذن الشاشة الكاملة مسموح'), findsOneWidget);
    pending.complete(false);
    await t.pumpAndSettle();
    expect(find.text('إذن الشاشة الكاملة مسموح'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
