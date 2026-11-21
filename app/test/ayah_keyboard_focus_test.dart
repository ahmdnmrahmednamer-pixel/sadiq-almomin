import 'package:almomin/features/mushaf/widgets/ayah_keyboard_focus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const lengths = [10, 12, 9];
  final opened = <int>[];
  final played = <int>[];
  int? lastActive;

  Future<void> pumpIt(WidgetTester t) async {
    opened.clear();
    played.clear();
    lastActive = null;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          const TextButton(onPressed: null, child: Text('before')),
          Focus(debugLabel: 'before', child: const SizedBox(width: 10, height: 10)),
          AyahKeyboardFocus(
            segmentLengths: lengths,
            onOpen: opened.add,
            onPlay: played.add,
            builder: (c, active, key) {
              lastActive = active;
              return RichText(key: key, text: const TextSpan(text: 'aaaaaaaaaabbbbbbbbbbbbccccccccc', style: TextStyle(color: Colors.black)));
            },
          ),
          ElevatedButton(onPressed: () {}, child: const Text('after')),
        ]),
      ),
    ));
  }

  Future<void> focusVerses(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      if (FocusManager.instance.primaryFocus?.debugLabel == 'reader-verses') return;
    }
    fail('Tab never reached reader-verses');
  }

  testWidgets('inactive until focused, then tints verse 0', (t) async {
    await pumpIt(t);
    expect(lastActive, isNull);
    await focusVerses(t);
    expect(lastActive, 0);
  });

  testWidgets('arrows move one verse, key repeat keeps moving, ends are released', (t) async {
    await pumpIt(t);
    await focusVerses(t);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    expect(lastActive, 1);
    await t.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    expect(lastActive, 2, reason: 'second press moved to the last verse');
    await t.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown); // held at the end: stays on the last verse
    await t.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, isNot('reader-verses'));
    expect(lastActive, isNull, reason: 'the fresh press at the end handed focus on, the repeats did not move it back');
    await focusVerses(t);
    expect(lastActive, 2, reason: 'active verse is kept when focus returns');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.pump();
    expect(lastActive, 1);
  });

  testWidgets('Enter and Menu open the active verse, Space plays it, nothing fires on other keys', (t) async {
    await pumpIt(t);
    await focusVerses(t);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.sendKeyEvent(LogicalKeyboardKey.keyA);
    expect(opened, [1, 1]);
    expect(played, [1]);
  });

  testWidgets('Shift+Tab leaves the verses backwards, Tab leaves forwards', (t) async {
    await pumpIt(t);
    await focusVerses(t);
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, isNot('reader-verses'));
    expect(lastActive, isNull);
    await focusVerses(t);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, isNot('reader-verses'));
  });
}
