import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:almomin/core/models/ayah.dart';
import 'package:almomin/core/models/surah.dart';
import 'package:almomin/core/services/ayah_notes_service.dart';
import 'package:almomin/features/mushaf/widgets/ayah_note_edit_dialog.dart';
import 'ayah_notes_persistence_failure_test.dart' show NotesTestStore;
import 'package:almomin/features/mushaf/quran_notes_screen.dart';

const surah = Surah(
    id: 1,
    nameAr: 'اختبار',
    nameSimple: 'test',
    revelationPlace: 'makkah',
    revelationOrder: 1,
    ayahCount: 7,
    hasBasmala: true,
    pageStart: 1,
    pageEnd: 1);
const ayah = Ayah(
    id: 1,
    surahId: 1,
    ayahNumber: 1,
    juz: 1,
    hizb: 1,
    rub: 1,
    page: 1,
    sajdah: 0,
    textUthmani: 'نص اختباري',
    textImlaei: 'نص اختباري',
    textSearch: 'نص اختباري');
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('Amiri')
      ..addFont(Future.value(ByteData.sublistView(
          File('assets/fonts/Amiri-Regular.ttf').readAsBytesSync())));
    await loader.load();
  });
  final service = AyahNotesService.instance;
  late NotesTestStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = NotesTestStore();
    SharedPreferencesStorePlatform.instance = store;
    await service.clearAllNotes();
    await service.init(forceReload: true);
  });
  Future<void> open(WidgetTester tester, {GlobalKey? boundary}) async {
    await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: MaterialApp(
            theme: ThemeData(fontFamily: 'Amiri'),
            home: Builder(
                builder: (context) => Scaffold(
                    body: Center(
                        child: TextButton(
                            onPressed: () => AyahNoteEditDialog.show(context,
                                surah: surah, ayah: ayah),
                            child: const Text('Open'))))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'failed save keeps draft open, announces failure, then retry succeeds',
      (tester) async {
    tester.view.physicalSize = const Size(480, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    await open(tester, boundary: boundary);
    await tester.enterText(
        find.byType(TextField), 'مسودة اختبارية محفوظة في المحرر');
    store.fail = true;
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(ElevatedButton, 'حفظ التدبر'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    expect(find.byType(AyahNoteEditDialog), findsOneWidget);
    expect(find.textContaining('تعذر حفظ الخاطرة'), findsOneWidget);
    expect(
        tester
            .widgetList<Semantics>(find.ancestor(
                of: find.textContaining('تعذر حفظ الخاطرة'),
                matching: find.byType(Semantics)))
            .any((s) => s.properties.liveRegion == true),
        isTrue);
    expect(find.textContaining('بنجاح'), findsNothing);
    expect(service.hasNote(1, 1), isFalse);
    await tester.runAsync(() async {
      final image = await (boundary.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      File('/tmp/notes-save-failure-480.png')
          .writeAsBytesSync(data!.buffer.asUint8List());
    });
    store.fail = false;
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(ElevatedButton, 'حفظ التدبر'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    expect(find.byType(AyahNoteEditDialog), findsNothing);
    expect(service.hasNote(1, 1), isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets('dismissing editor during save causes no setState after dispose',
      (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'draft');
    final gate = Completer<void>();
    store.gate = gate;
    await tester.tap(find.widgetWithText(ElevatedButton, 'حفظ التدبر'));
    await tester.pump();
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('failed delete keeps the existing note and editor',
      (tester) async {
    await tester.runAsync(() => service.saveNote(
        surahId: 1,
        surahName: 'اختبار',
        ayahNumber: 1,
        ayahText: 'نص اختباري',
        noteText: 'خاطرة سابقة'));
    await open(tester);
    store.fail = true;
    await tester.tap(find.byTooltip('حذف الخاطرة'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(ElevatedButton, 'حذف'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    expect(find.byType(AyahNoteEditDialog), findsOneWidget);
    expect(service.getNote(1, 1)!.noteText, 'خاطرة سابقة');
    expect(find.textContaining('تعذر حذف الخاطرة'), findsOneWidget);
    expect(find.textContaining('بنجاح'), findsNothing);
  });
  testWidgets('list deletion failure retains card and reports no success',
      (tester) async {
    await tester.runAsync(() => service.saveNote(
        surahId: 1,
        surahName: 'اختبار',
        ayahNumber: 1,
        ayahText: 'نص اختباري',
        noteText: 'خاطرة سابقة'));
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: 'Amiri'), home: const QuranNotesScreen()));
    await tester.pumpAndSettle();
    store.fail = true;
    await tester.tap(find.byTooltip('حذف'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(ElevatedButton, 'حذف'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    expect(find.text('خاطرة سابقة'), findsOneWidget);
    expect(find.textContaining('تعذر حذف الخاطرة'), findsOneWidget);
    expect(find.textContaining('بنجاح'), findsNothing);
    expect(service.hasNote(1, 1), isTrue);
  });
}
