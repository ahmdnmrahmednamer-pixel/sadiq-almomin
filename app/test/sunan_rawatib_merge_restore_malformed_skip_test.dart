// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/sunan_rawatib_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('malformed import in merge => local bytes untouched intentionalSkip', (tester) async {
    const localDate = '2025-01-01';
    final localJson = json.encode({
      localDate: ['fajr_pre_2'],
    });

    SharedPreferences.setMockInitialValues({
      'sunan_rawatib_logs_v1': localJson,
    });

    final service = SunanRawatibService.instance;
    await service.init(forceReload: true);

    const malformedImport = '{corrupt-json-payload:[';

    final result = await service.restoreSunanRawatib(
      rawImport: malformedImport,
      replaceMode: false,
    );

    expect(result.status, equals(SunanRawatibRestoreStatus.intentionalSkip));
    expect(result.livePublished, isTrue);

    // Assert local host bytes untouched
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('sunan_rawatib_logs_v1'), equals(localJson));
  });
}
