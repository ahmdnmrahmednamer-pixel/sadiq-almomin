import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/prayer_service.dart';
import 'package:almomin/core/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init();
    await PrayerService.instance.init(forceReload: true);
  });

  group('Arab Countries & Cities Dataset Completeness Tests', () {
    test('Contains all 22 sovereign Arab League nations', () {
      const countries = ArabCountriesData.countries;
      expect(countries.length, 22);

      final countryNames = countries.map((c) => c.name).toList();
      expect(countryNames.any((n) => n.contains('مصر')), isTrue);
      expect(countryNames.any((n) => n.contains('السعودية')), isTrue);
      expect(countryNames.any((n) => n.contains('الإمارات')), isTrue);
      expect(countryNames.any((n) => n.contains('الكويت')), isTrue);
      expect(countryNames.any((n) => n.contains('قطر')), isTrue);
      expect(countryNames.any((n) => n.contains('البحرين')), isTrue);
      expect(countryNames.any((n) => n.contains('عُمان')), isTrue);
      expect(countryNames.any((n) => n.contains('الأردن')), isTrue);
      expect(countryNames.any((n) => n.contains('فلسطين')), isTrue);
      expect(countryNames.any((n) => n.contains('لبنان')), isTrue);
      expect(countryNames.any((n) => n.contains('سوريا')), isTrue);
      expect(countryNames.any((n) => n.contains('العراق')), isTrue);
      expect(countryNames.any((n) => n.contains('اليمن')), isTrue);
      expect(countryNames.any((n) => n.contains('السودان')), isTrue);
      expect(countryNames.any((n) => n.contains('ليبيا')), isTrue);
      expect(countryNames.any((n) => n.contains('تونس')), isTrue);
      expect(countryNames.any((n) => n.contains('الجزائر')), isTrue);
      expect(countryNames.any((n) => n.contains('المغرب')), isTrue);
      expect(countryNames.any((n) => n.contains('موريتانيا')), isTrue);
      expect(countryNames.any((n) => n.contains('الصومال')), isTrue);
      expect(countryNames.any((n) => n.contains('جيبوتي')), isTrue);
      expect(countryNames.any((n) => n.contains('جزر القمر')), isTrue);
    });

    test('Every Arab country has valid cities with non-null coordinates and valid bounds', () {
      for (final country in ArabCountriesData.countries) {
        expect(country.flag.isNotEmpty, isTrue);
        expect(country.cities.isNotEmpty, isTrue, reason: 'Country ${country.name} must have cities');

        for (final city in country.cities) {
          expect(city.name.isNotEmpty, isTrue);
          expect(city.latitude, inInclusiveRange(-90.0, 90.0));
          expect(city.longitude, inInclusiveRange(-180.0, 180.0));
          expect(city.method.isNotEmpty, isTrue);
        }
      }
    });

    test('allCities flattens over 150 Arab cities across all countries', () {
      final allCities = ArabCountriesData.allCities;
      expect(allCities.length, greaterThan(150));
      expect(PrayerService.famousCities.length, equals(allCities.length));
    });

    test('findCountryByCityName accurately locates country', () {
      final egypt = ArabCountriesData.findCountryByCityName('القاهرة، مصر');
      expect(egypt.id, 'eg');

      final saudi = ArabCountriesData.findCountryByCityName('مكة المكرمة');
      expect(saudi.id, 'sa');

      final uae = ArabCountriesData.findCountryByCityName('دبي');
      expect(uae.id, 'ae');

      final palestine = ArabCountriesData.findCountryByCityName('القدس الشريف');
      expect(palestine.id, 'ps');
    });
  });

  group('PrayerService GPS-Only Identification & Live Continuous Updates', () {
    test('identifyCity labels verified GPS coordinates inside and outside Arab catalog cleanly', () {
      expect(
        PrayerService.instance.identifyCity(24.7136, 46.6753),
        contains('الرياض'),
      );
      expect(
        PrayerService.instance.identifyCity(35.6762, 139.6503),
        equals('موقعك الفعلي (35.68°, 139.65°)'),
      );
    });

    test('formatCountdown outputs HH:MM:SS format for live countdown', () {
      const d1 = Duration(hours: 2, minutes: 15, seconds: 40);
      expect(PrayerService.instance.formatCountdown(d1), '02:15:40');

      const d2 = Duration(minutes: 5, seconds: 9);
      expect(PrayerService.instance.formatCountdown(d2), '00:05:09');

      const d3 = Duration(seconds: -5);
      expect(PrayerService.instance.formatCountdown(d3), 'حان الآن');
    });
  });
}
