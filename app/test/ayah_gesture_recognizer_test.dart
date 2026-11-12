import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/core/gestures/ayah_gesture_recognizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AyahGestureRecognizer: Single Tap triggers onAyahTap and not onAyahLongPress', (tester) async {
    bool tapped = false;
    bool longPressed = false;

    final recognizer = AyahGestureRecognizer(
      onAyahTap: () => tapped = true,
      onAyahLongPress: () => longPressed = true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RichText(
              text: TextSpan(
                text: 'بسم الله الرحمن الرحيم',
                style: const TextStyle(fontSize: 24, color: Colors.black),
                recognizer: recognizer,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(RichText));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
    expect(longPressed, isFalse);

    recognizer.dispose();
  });

  testWidgets('AyahGestureRecognizer: Long Press triggers onAyahLongPress and not onAyahTap', (tester) async {
    bool tapped = false;
    bool longPressed = false;

    final recognizer = AyahGestureRecognizer(
      onAyahTap: () => tapped = true,
      onAyahLongPress: () => longPressed = true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RichText(
              text: TextSpan(
                text: 'الحمد لله رب العالمين',
                style: const TextStyle(fontSize: 24, color: Colors.black),
                recognizer: recognizer,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.longPress(find.byType(RichText));
    await tester.pumpAndSettle();

    expect(longPressed, isTrue);
    expect(tapped, isFalse);

    recognizer.dispose();
  });
}
