import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/adhkar_service.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/features/adhkar/tasbih_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AdhkarService.instance.init();
    AdhkarService.instance.resetTasbih();
    AdhkarService.instance.resetTasbihTotal();
    AdhkarService.instance.setSelectedTasbihPhrase('سُبْحَانَ اللَّهِ');
  });

  Widget buildTestableWidget() {
    return const MaterialApp(
      home: TasbihScreen(),
    );
  }

  group('Tasbih Audio Elimination & Text-Only Celebration Tests', () {
    testWidgets('Reaching target count shows ONLY text dialog and does NOT play any adhan or takbeerat sound', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Set target to 2
      AdhkarService.instance.setTasbihTarget(2);

      await tester.pumpWidget(buildTestableWidget());
      await tester.pumpAndSettle();

      final tasbihButtonFinder = find.byKey(const Key('tasbih_main_button'));
      expect(tasbihButtonFinder, findsOneWidget);

      // Tap 1
      await tester.tap(tasbihButtonFinder);
      await tester.pump();
      expect(AdhkarService.instance.tasbihCount, 1);

      // Tap 2 (target reached)
      await tester.tap(tasbihButtonFinder);
      await tester.pumpAndSettle();

      expect(AdhkarService.instance.tasbihCount, 2);

      // Verify ONLY peaceful textual dialog is presented
      expect(find.text('مبارك! أتممت الورد بنجاح ✨'), findsOneWidget);
      expect(find.text('تقبّل الله طاعتك وأجزل لك المثوبة والأجر 🌸'), findsOneWidget);
      expect(find.text('2 تسبيحة'), findsOneWidget);

      // Verify no adhan audio is playing in IslamicAudioService
      expect(IslamicAudioService.instance.isPlaying, isFalse);

      // Dismiss dialog
      await tester.tap(find.text('متابعة الذكر (دورة جديدة)'));
      await tester.pumpAndSettle();
      expect(find.text('مبارك! أتممت الورد بنجاح ✨'), findsNothing);
    });
  });
}
