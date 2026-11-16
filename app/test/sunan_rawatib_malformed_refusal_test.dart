// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/sunan_rawatib_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('malformed host refusal with host bytes pinned UNCHANGED', (tester) async {
    const malformedRaw = 'not a valid json {[';
    SharedPreferences.setMockInitialValues({
      'sunan_rawatib_logs_v1': malformedRaw,
    });

    final service = SunanRawatibService.instance;
    await service.init(forceReload: true);

    expect(service.isCompleted('fajr_pre_2'), isFalse);

    final result = await service.toggleSunnah('fajr_pre_2');

    expect(result.status, equals(SunanRawatibOperationStatus.writeRefusedUnreadable));
    expect(result.livePublished, isFalse);

    // Assert live map untouched
    expect(service.isCompleted('fajr_pre_2'), isFalse);

    // Assert host bytes pinned UNCHANGED
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('sunan_rawatib_logs_v1'), equals(malformedRaw));
  });
}
