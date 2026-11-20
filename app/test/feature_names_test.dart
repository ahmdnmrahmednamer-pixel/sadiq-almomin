import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/features/home/widgets/home_adhkar_tasbih_row.dart';

void main() {
  testWidgets('Tasbih feature exposes a concise visible and semantic name', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HomeAdhkarTasbihRow())));
    expect(find.text('السبحة'), findsOneWidget);
    expect(find.text('السبحة الذكية'), findsNothing);
    expect(find.bySemanticsLabel('السبحة، عداد الورد والتسبيح'), findsOneWidget);
    semantics.dispose();
  });
  test('Chrome names change without editing content catalogs or the held player title', () {
    final player = File('lib/features/audio/widgets/full_screen_studio_player.dart').readAsStringSync();
    expect(player, contains("'مؤقت النوم (إيقاف تلقائي)'"));
    expect(player, contains("'المشغل الصوتي الاستوديو'"));
    expect(File('lib/features/mushaf/memorization_screen.dart').readAsStringSync(), contains("'المحفظ القرآني والتكرار'"));
    expect(File('lib/features/zakat/zakat_screen.dart').readAsStringSync(), contains("'حاسبة الزكاة'"));
    expect(File('lib/core/services/settings_service.dart').readAsStringSync(), contains("style: 'تلاوة خاشعة'"));
    expect(File('lib/core/services/scholars_lectures_service.dart').readAsStringSync(), contains('أسرار الصلاة الخاشعة'));
  });
}
