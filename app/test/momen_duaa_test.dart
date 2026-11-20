import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/features/home/momen_duaa_screen.dart';
import 'package:almomin/features/settings/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Momen Ibrahim (رحمهُ الله / الله يرحمه) Launch Duaa & Tutorial Screen Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.instance.init();
    });

    test('SettingsService manages showTutorialScreens flag correctly', () async {
      final service = SettingsService.instance;
      expect(service.showTutorialScreens, isTrue);

      await service.setShowTutorialScreens(false);
      expect(service.showTutorialScreens, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('show_tutorial_screens'), isFalse);

      await service.setShowTutorialScreens(true);
      expect(service.showTutorialScreens, isTrue);
      expect(prefs.getBool('show_tutorial_screens'), isTrue);
    });

    testWidgets('MomenDuaaScreen renders with exact name formulation and Amen button', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MomenDuaaScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 1. Verify exact requested name and mercy formula
      expect(find.text('صَدَقَةٌ جَارِيَةٌ'), findsOneWidget);
      expect(find.text('عَنْ رُوحِ المَرْحُومِ بِإِذْنِ اللَّهِ تَعَالَى'), findsOneWidget);
      expect(find.text('مُؤْمِن إِبْرَاهِيم رحمهُ الله'), findsOneWidget);
      expect(find.textContaining('الله يرحمه'), findsOneWidget);

      // 2. Verify Prophetic Duaa and Hadith
      expect(find.textContaining('اللَّهُمَّ يَا حَنَّانُ يَا مَنَّانُ'), findsOneWidget);
      expect(find.textContaining('دُعَاءٌ وَرَجَاءٌ لِرَفِيعِ الدَّرَجَاتِ'), findsOneWidget);
      expect(find.textContaining('إِذَا مَاتَ الإِنْسَانُ انْقَطَعَ عَنْهُ عَمَلُهُ إِلَّا مِنْ ثَلَاثٍ'), findsOneWidget);
      expect(find.textContaining('اللَّهُمَّ احْفَظْ وَالِدَيْهِ'), findsOneWidget);
      expect(find.textContaining('وَأَلْبِسْهُمَا لِبَاسَ الصِّحَّةِ وَالعَافِيَةِ'), findsOneWidget);

      // 3. Verify Bottom Persistent "آمين" Button
      expect(find.text('آمين'), findsOneWidget);
      expect(find.text('اضغط على زر آمين للدخول إلى التطبيق'), findsOneWidget);
    });

    testWidgets('Tapping Amen button in MomenDuaaScreen (from inside app) pops dialog/route', (WidgetTester tester) async {
      bool popped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Navigator(
            onGenerateRoute: (settings) {
              return MaterialPageRoute(
                builder: (context) {
                  return Scaffold(
                    body: Center(
                      child: ElevatedButton(
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const MomenDuaaScreen(isFromInsideApp: true),
                            ),
                          );
                          popped = true;
                        },
                        child: const Text('Open Duaa'),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Open screen
      await tester.tap(find.text('Open Duaa'));
      await tester.pumpAndSettle();

      expect(find.text('مُؤْمِن إِبْرَاهِيم رحمهُ الله'), findsOneWidget);
      expect(find.text('آمين'), findsOneWidget);

      // Tap Amen
      await tester.tap(find.text('آمين'));
      await tester.pumpAndSettle();

      expect(popped, isTrue);
      expect(find.text('Open Duaa'), findsOneWidget);
    });

    testWidgets('Semantic tap on Amen button triggers navigation action and has clean label', (WidgetTester tester) async {
      final semantics = tester.ensureSemantics();
      bool popped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Navigator(
            onGenerateRoute: (settings) {
              return MaterialPageRoute(
                builder: (context) {
                  return Scaffold(
                    body: Center(
                      child: ElevatedButton(
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const MomenDuaaScreen(isFromInsideApp: true),
                            ),
                          );
                          popped = true;
                        },
                        child: const Text('Open Duaa'),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Duaa'));
      await tester.pumpAndSettle();

      final amenFinder = find.widgetWithText(ElevatedButton, 'آمين');
      expect(amenFinder, findsOneWidget);

      // 1. Verify semantic properties of the Amen button
      final SemanticsData semanticsData = tester.getSemantics(amenFinder).getSemanticsData();
      expect(semanticsData.hasAction(SemanticsAction.tap), isTrue);
      expect(semanticsData.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(semanticsData.hasFlag(SemanticsFlag.isEnabled), isTrue);
      // Clean label 'آمين' without emoji
      expect(semanticsData.label, equals('آمين'));

      // 2. Perform semantic tap via SemanticsOwner
      final SemanticsNode node = tester.semantics.find(amenFinder);
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pumpAndSettle();

      // 3. Verify route was popped by Amen pressed
      expect(popped, isTrue);
      expect(find.text('Open Duaa'), findsOneWidget);

      semantics.dispose();
    });

    testWidgets('Amen button expands vertically at textScaler 2.0 without clipping or fixed height constraint', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Scale 1.0: Button meets minHeight of 58
      await tester.pumpWidget(
        const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MediaQuery(
              data: MediaQueryData(
                size: Size(360, 800),
                textScaler: TextScaler.linear(1.0),
              ),
              child: MomenDuaaScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final amenButtonFinder = find.widgetWithText(ElevatedButton, 'آمين');
      final size1 = tester.getSize(amenButtonFinder);
      expect(size1.height, greaterThanOrEqualTo(58.0));

      // Scale 2.0: Button expands beyond 58.0 to comfortably house scaled text without vertical clipping
      await tester.pumpWidget(
        const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MediaQuery(
              data: MediaQueryData(
                size: Size(360, 800),
                textScaler: TextScaler.linear(2.0),
              ),
              child: MomenDuaaScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final size2 = tester.getSize(amenButtonFinder);
      expect(size2.height, greaterThan(size1.height),
          reason: 'Button height must expand at textScaler 2.0 to prevent text clipping');
      expect(tester.takeException(), isNull, reason: 'Zero layout exceptions when button expands at scale 2.0');
    });

    testWidgets('Synthetic Row layout isolation vs repaired Flexible header (state limitation noted)', (WidgetTester tester) async {
      // Note: This test isolates the geometry failure mechanism (unconstrained Row overflow on 360px),
      // but cannot constitute dynamic traversal proof of the historic baseline commit in-situ without checking out old commit state.
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // 1. Synthetic Failure Demonstration: Unconstrained Row on 360px width at text scale 2.0 overflows
      FlutterErrorDetails? caughtError;
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        caughtError = details;
      };

      await tester.pumpWidget(
        const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MediaQuery(
              data: MediaQueryData(
                size: Size(360, 800),
                textScaler: TextScaler.linear(2.0),
              ),
              child: Scaffold(
                body: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('۞ '),
                    Text('دُعَاءٌ وَرَجَاءٌ لِرَفِيعِ الدَّرَجَاتِ'),
                    Text(' ۞'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      FlutterError.onError = originalOnError;
      expect(caughtError, isNotNull, reason: 'Unconstrained row must fail with overflow on 360px at scale 2.0');
      expect(caughtError!.exception.toString(), contains('A RenderFlex overflowed'));

      // 2. Repaired Success: MomenDuaaScreen on 360px at text scale 2.0 has zero overflow
      await tester.pumpWidget(
        const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MediaQuery(
              data: MediaQueryData(
                size: Size(360, 800),
                textScaler: TextScaler.linear(2.0),
              ),
              child: MomenDuaaScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'Repaired screen with Flexible header must fit with zero overflow');
    });

    testWidgets('Accessibility traversal verifies meaningful unique ordered labels at scales 1.0 and 2.0', (WidgetTester tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const expectedLabels = [
        'صَدَقَةٌ جَارِيَةٌ',
        'عَنْ رُوحِ المَرْحُومِ بِإِذْنِ اللَّهِ تَعَالَى',
        'مُؤْمِن إِبْرَاهِيم رحمهُ الله\n«الله يرحمه ويغفر له ويسكنه فسيح جناته»',
        'دُعَاءٌ وَرَجَاءٌ لِرَفِيعِ الدَّرَجَاتِ',
        '«اللَّهُمَّ يَا حَنَّانُ يَا مَنَّانُ، يَا بَدِيعَ السَّمَاوَاتِ وَالأَرْضِ، يَا ذَا الجَلَالِ وَالإِكْرَامِ.. أَنْزِلْ عَلَى عَبْدِكَ "مُؤْمِن إِبْرَاهِيم" الضِّيَاءَ وَالنُّورَ، وَالفُسْحَةَ وَالسُّرُورَ، وَالبَهْجَةَ وَالحُبُورَ، وَاجْعَلْ قَبْرَهُ رَوْضَةً نَدِيَّةً مِنْ رِيَاضِ الجَنَّةِ، تَهَبُّ عَلَيْهِ مِنْ نَسَائِمِهَا وَرَيْحَانِهَا إِلَى يَوْمِ الدِّينِ.»',
        '«اللَّهُمَّ جَازِهِ بِالإِحْسَانِ إِحْسَاناً، وَعَنِ السَّيِّئَاتِ عَفْواً وَغُفْرَاناً، وَأَبْدِلْهُ دَاراً خَيْراً مِنْ دَارِهِ، وَأَهْلاً خَيْراً مِنْ أَهْلِهِ، وَثَبِّتْهُ عِنْدَ السُّؤَالِ، وَيَمِّنْ كِتَابَهُ، وَيَسِّرْ حِسَابَهُ، وَارْفَعْ فِي أَعْلَى عِلِّيِّينَ دَرَجَتَهُ فِي الفِرْدَوْسِ الأَعْلَى مَعَ النَّبِيِّينَ وَالصِّدِّيقِينَ وَالشُّهَدَاءِ وَالصَّالِحِينَ.»',
        '«اللَّهُمَّ احْفَظْ وَالِدَيْهِ بِحِفْظِكَ التَّامِّ، وَبَارِكْ فِي عُمُرِهِمَا عَلَى طَاعَتِكَ، وَأَلْبِسْهُمَا لِبَاسَ الصِّحَّةِ وَالعَافِيَةِ، وَارْبِطْ عَلَى قُلُوبِهِمَا بِالصَّبْرِ وَالسَّكِينَةِ وَالاحْتِسَابِ، وَاجْزِهِمَا عَنْهُ خَيْرَ مَا جَزَيْتَ وَالِداً عَنْ وَلَدِهِ، وَاجْعَلْهُ لَهُمَا فَرَطاً وَذُخْراً وَشَفِيعاً مُجَاباً عِنْدَكَ..»',
        '«اللَّهُمَّ اجْعَلْ كُلَّ آيَةٍ تُتْلَى، وَكُلَّ صَلَاةٍ وَذِكْرٍ وَتَسْبِيحَةٍ فِي هَذَا التَّطْبِيقِ نُوراً يَسْعَى بَيْنَ يَدَيْ عَبْدِكَ "مُؤْمِن"، وَبَرَكَةً وَأَجْراً وَذُخْراً لِوَالِدَيْهِ فِي دِينِهِمَا وَدُنْيَاهُمَا، وَشَفِيعاً لَهُمْ يَوْمَ العَرْضِ عَلَيْكَ.. آمِينَ يَا رَبَّ العَالَمِينَ»',
        'قال ﷺ: «إِذَا مَاتَ الإِنْسَانُ انْقَطَعَ عَنْهُ عَمَلُهُ إِلَّا مِنْ ثَلَاثٍ: صَدَقَةٍ جَارِيَةٍ، أَوْ عِلْمٍ يُنْتَفَعُ بِهِ، أَوْ وَلَدٍ صَالِحٍ يَدْعُو لَهُ» (رواه مسلم)',
        'آمين',
      ];

      for (final scale in [1.0, 2.0]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: MediaQuery(
                data: MediaQueryData(
                  size: const Size(360, 800),
                  textScaler: TextScaler.linear(scale),
                ),
                child: const MomenDuaaScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final traversal = tester.semantics.simulatedAccessibilityTraversal();
        final actualLabels = traversal
            .map((n) => n.getSemanticsData().label)
            .where((l) => l.isNotEmpty)
            .toList();

        // 1. Verify exact count and unique ordered sequence
        expect(actualLabels.length, equals(expectedLabels.length),
            reason: 'Should have exactly 10 accessible stops at scale $scale');
        for (int i = 0; i < expectedLabels.length; i++) {
          expect(actualLabels[i], equals(expectedLabels[i]),
              reason: 'Stop $i at scale $scale does not match expected label');
        }

        // 2. Verify all labels are distinct (unique)
        expect(actualLabels.toSet().length, equals(actualLabels.length),
            reason: 'All accessible stops must be unique at scale $scale');

        // 3. Verify no decorative, emoji, or duplicate stops exist in semantics or widgets
        expect(actualLabels.any((l) => l.contains('۞')), isFalse,
            reason: 'Decorative bracket ۞ must be excluded from semantics');
        expect(actualLabels.any((l) => l.contains('🤲')), isFalse,
            reason: 'Fallback emoji 🤲 must not exist in semantics');
        expect(find.textContaining('🤲'), findsNothing,
            reason: 'Fallback emoji 🤲 must be replaced with bundled icon/font decoration');
        expect(actualLabels.any((l) => l == 'اضغط على زر آمين للدخول إلى التطبيق'), isFalse,
            reason: 'Subtitle must be excluded to prevent duplicate button announcement');
      }

      semantics.dispose();
    });

    testWidgets('Semantic showOnScreen traversal brings each offscreen prayer paragraph from isHidden true to false at BOTH scales 1.0 and 2.0', (WidgetTester tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final paragraphFinders = [
        find.textContaining('اللَّهُمَّ يَا حَنَّانُ يَا مَنَّانُ'),
        find.textContaining('اللَّهُمَّ جَازِهِ بِالإِحْسَانِ إِحْسَاناً'),
        find.textContaining('اللَّهُمَّ احْفَظْ وَالِدَيْهِ بِحِفْظِكَ التَّامِّ'),
        find.textContaining('اللَّهُمَّ اجْعَلْ كُلَّ آيَةٍ تُتْلَى'),
        find.textContaining('إِذَا مَاتَ الإِنْسَانُ انْقَطَعَ عَنْهُ عَمَلُهُ إِلَّا مِنْ ثَلَاثٍ'),
      ];

      for (final scale in [1.0, 2.0]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: MediaQuery(
                data: MediaQueryData(
                  size: const Size(360, 800),
                  textScaler: TextScaler.linear(scale),
                ),
                child: const MomenDuaaScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Paragraph 0 is near the top of the card and initially visible
        final node0 = tester.semantics.find(paragraphFinders[0]);
        expect(node0.getSemanticsData().hasFlag(SemanticsFlag.isHidden), isFalse,
            reason: 'Paragraph 0 must be initially visible at scale $scale');

        // Paragraphs 1-4 are positioned below the 800px viewport fold and are initially hidden
        for (int i = 1; i < paragraphFinders.length; i++) {
          final finder = paragraphFinders[i];
          final SemanticsNode nodeBefore = tester.semantics.find(finder);

          // Assert isHidden flag is true before semantic showOnScreen action
          expect(nodeBefore.getSemanticsData().hasFlag(SemanticsFlag.isHidden), isTrue,
              reason: 'Paragraph $i must be hidden before semantic showOnScreen at scale $scale');

          // Dispatch real semantic action showOnScreen
          nodeBefore.owner!.performAction(nodeBefore.id, SemanticsAction.showOnScreen);
          await tester.pumpAndSettle();

          // Assert isHidden flag is now false after semantic showOnScreen action
          final SemanticsNode nodeAfter = tester.semantics.find(finder);
          expect(nodeAfter.getSemanticsData().hasFlag(SemanticsFlag.isHidden), isFalse,
              reason: 'Paragraph $i must not be hidden after semantic showOnScreen at scale $scale');
        }
      }

      semantics.dispose();
    });

    testWidgets('Renders without layout overflow on 360x800 at textScaler 1.0 and 2.0', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final scale in [1.0, 2.0]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: MediaQuery(
                data: MediaQueryData(
                  size: const Size(360, 800),
                  textScaler: TextScaler.linear(scale),
                ),
                child: const MomenDuaaScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: 'MomenDuaaScreen must have zero overflow or layout exceptions at text scale $scale');
      }
    });

    testWidgets('Exact Arabic religious text preservation verification', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MomenDuaaScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      const expectedExactTexts = [
        'صَدَقَةٌ جَارِيَةٌ',
        'عَنْ رُوحِ المَرْحُومِ بِإِذْنِ اللَّهِ تَعَالَى',
        'مُؤْمِن إِبْرَاهِيم رحمهُ الله',
        '«الله يرحمه ويغفر له ويسكنه فسيح جناته»',
        'دُعَاءٌ وَرَجَاءٌ لِرَفِيعِ الدَّرَجَاتِ',
        '«اللَّهُمَّ يَا حَنَّانُ يَا مَنَّانُ، يَا بَدِيعَ السَّمَاوَاتِ وَالأَرْضِ، يَا ذَا الجَلَالِ وَالإِكْرَامِ.. أَنْزِلْ عَلَى عَبْدِكَ "مُؤْمِن إِبْرَاهِيم" الضِّيَاءَ وَالنُّورَ، وَالفُسْحَةَ وَالسُّرُورَ، وَالبَهْجَةَ وَالحُبُورَ، وَاجْعَلْ قَبْرَهُ رَوْضَةً نَدِيَّةً مِنْ رِيَاضِ الجَنَّةِ، تَهَبُّ عَلَيْهِ مِنْ نَسَائِمِهَا وَرَيْحَانِهَا إِلَى يَوْمِ الدِّينِ.»',
        '«اللَّهُمَّ جَازِهِ بِالإِحْسَانِ إِحْسَاناً، وَعَنِ السَّيِّئَاتِ عَفْواً وَغُفْرَاناً، وَأَبْدِلْهُ دَاراً خَيْراً مِنْ دَارِهِ، وَأَهْلاً خَيْراً مِنْ أَهْلِهِ، وَثَبِّتْهُ عِنْدَ السُّؤَالِ، وَيَمِّنْ كِتَابَهُ، وَيَسِّرْ حِسَابَهُ، وَارْفَعْ فِي أَعْلَى عِلِّيِّينَ دَرَجَتَهُ فِي الفِرْدَوْسِ الأَعْلَى مَعَ النَّبِيِّينَ وَالصِّدِّيقِينَ وَالشُّهَدَاءِ وَالصَّالِحِينَ.»',
        '«اللَّهُمَّ احْفَظْ وَالِدَيْهِ بِحِفْظِكَ التَّامِّ، وَبَارِكْ فِي عُمُرِهِمَا عَلَى طَاعَتِكَ، وَأَلْبِسْهُمَا لِبَاسَ الصِّحَّةِ وَالعَافِيَةِ، وَارْبِطْ عَلَى قُلُوبِهِمَا بِالصَّبْرِ وَالسَّكِينَةِ وَالاحْتِسَابِ، وَاجْزِهِمَا عَنْهُ خَيْرَ مَا جَزَيْتَ وَالِداً عَنْ وَلَدِهِ، وَاجْعَلْهُ لَهُمَا فَرَطاً وَذُخْراً وَشَفِيعاً مُجَاباً عِنْدَكَ..»',
        '«اللَّهُمَّ اجْعَلْ كُلَّ آيَةٍ تُتْلَى، وَكُلَّ صَلَاةٍ وَذِكْرٍ وَتَسْبِيحَةٍ فِي هَذَا التَّطْبِيقِ نُوراً يَسْعَى بَيْنَ يَدَيْ عَبْدِكَ "مُؤْمِن"، وَبَرَكَةً وَأَجْراً وَذُخْراً لِوَالِدَيْهِ فِي دِينِهِمَا وَدُنْيَاهُمَا، وَشَفِيعاً لَهُمْ يَوْمَ العَرْضِ عَلَيْكَ.. آمِينَ يَا رَبَّ العَالَمِينَ»',
        'قال ﷺ: «إِذَا مَاتَ الإِنْسَانُ انْقَطَعَ عَنْهُ عَمَلُهُ إِلَّا مِنْ ثَلَاثٍ: صَدَقَةٍ جَارِيَةٍ، أَوْ عِلْمٍ يُنْتَفَعُ بِهِ، أَوْ وَلَدٍ صَالِحٍ يَدْعُو لَهُ» (رواه مسلم)',
        'آمين',
        'اضغط على زر آمين للدخول إلى التطبيق',
      ];

      for (final text in expectedExactTexts) {
        expect(find.text(text), findsOneWidget, reason: 'Text "$text" must be exactly preserved byte-for-byte.');
      }
    });

    testWidgets('SettingsScreen has no retired tour controls and preserves its saved preference', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 8000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: SettingsScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify internal cleanliness per user spec
      expect(find.textContaining('دعاء لمؤمن إبراهيم رحمهُ الله'), findsNothing);
      expect(find.text('إظهار شاشات شرح البرنامج عند الفتح'), findsNothing);
      expect(find.text('عرض شاشات شرح استخدام البرنامج'), findsNothing);
      expect(SettingsService.instance.showTutorialScreens, isTrue);

    });
  });
}
