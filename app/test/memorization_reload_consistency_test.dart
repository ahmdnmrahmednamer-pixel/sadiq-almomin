import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/memorization_service.dart';
import 'package:almomin/core/models/memorization_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = MemorizationService.instance;
  String saved(int ayah) => jsonEncode([
        MemorizationItem.createInitial(
          surahId: 1,
          ayahNumber: ayah,
          surahName: 'Test surah',
        ).toJson(),
      ]);
  setUp(() async {
    SharedPreferences.setMockInitialValues({'memorization_items_v1': saved(1)});
    await service.init(forceReload: true);
    expect(service.hasItem(1, 1), isTrue);
  });
  test('forced reload with absent key clears old items', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('memorization_items_v1');
    await service.init(forceReload: true);
    expect(service.totalTrackedAyahs, 0);
    expect(service.exportData(), isEmpty);
  });
  test('forced reload with empty saved value clears old items', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('memorization_items_v1', '');
    await service.init(forceReload: true);
    expect(service.totalTrackedAyahs, 0);
  });
  test('ordinary init preserves initialized cache guard', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('memorization_items_v1');
    await service.init();
    expect(service.hasItem(1, 1), isTrue);
  });
  test('malformed JSON preserves existing cached items', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('memorization_items_v1', '{invalid');
    await service.init(forceReload: true);
    expect(service.hasItem(1, 1), isTrue);
    expect(service.totalTrackedAyahs, 1);
  });
  test('missing value reload notifies listeners of cleared items', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('memorization_items_v1');
    final observed = <int>[];
    void listener() => observed.add(service.totalTrackedAyahs);
    service.addListener(listener);
    addTearDown(() => service.removeListener(listener));
    await service.init(forceReload: true);
    expect(observed, [0]);
    expect(service.isInitialized, isTrue);
  });
  test('new review after clearing does not resurrect an old item', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('memorization_items_v1');
    await service.init(forceReload: true);
    await service.recordReview(
        surahId: 1,
        ayahNumber: 2,
        surahName: 'Test surah',
        rating: MemorizationRating.easy);
    expect(service.hasItem(1, 1), isFalse);
    expect(service.hasItem(1, 2), isTrue);
    final persisted =
        jsonDecode(prefs.getString('memorization_items_v1')!) as List;
    expect(persisted, hasLength(1));
    expect((persisted.single as Map)['id'], '1:2');
  });
  test('valid empty list clears old items', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('memorization_items_v1', '[]');
    await service.init(forceReload: true);
    expect(service.totalTrackedAyahs, 0);
  });
  test('valid replacement loads only replacement items', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('memorization_items_v1', saved(2));
    await service.init(forceReload: true);
    expect(service.hasItem(1, 1), isFalse);
    expect(service.hasItem(1, 2), isTrue);
    expect(service.totalTrackedAyahs, 1);
  });
}
