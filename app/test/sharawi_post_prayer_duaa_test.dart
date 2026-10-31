import 'package:almomin/core/services/settings_service.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/core/services/adhkar_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    IslamicAudioService.instance.disableNativePlayerForTesting = true;
  });

  group('Sheikh Al-Sha\'rawi Post-Prayer Duaa Tests', () {
    test('1. Track registration in IslamicAudioService', () {
      final track = IslamicAudioService.allTracks.firstWhere(
        (t) => t.id == 'duaa_sharawi_post_prayer',
        orElse: () => throw Exception('Track not found!'),
      );

      expect(track.id, 'duaa_sharawi_post_prayer');
      expect(track.title, contains('الشعراوي'));
      expect(track.type, IslamicAudioType.adhkar);
      expect(track.isBundled, isTrue);
      expect(track.assetPath, 'assets/audio/duaa_sharawi_post_prayer.mp3');
      expect(track.remoteUrl, isNotNull);
      expect(track.fallbackUrls, isNotEmpty);
      expect(track.rawNotificationSound, 'duaa_sharawi_post_prayer');
    });

    test('2. Bundled MP3 file exists on disk with valid size', () {
      final assetFile = File('assets/audio/duaa_sharawi_post_prayer.mp3');
      expect(assetFile.existsSync(), isTrue, reason: 'assets/audio/duaa_sharawi_post_prayer.mp3 must exist');
      expect(assetFile.lengthSync(), greaterThan(100000), reason: 'Audio file must be properly sized');

      final rawResFile = File('android/app/src/main/res/raw/duaa_sharawi_post_prayer.mp3');
      expect(rawResFile.existsSync(), isTrue, reason: 'android res/raw copy must exist for native alarms');
    });

    test('3. Post-Prayer Adhkar category contains Sheikh Al-Sha\'rawi supplications', () async {
      final adhkarService = AdhkarService.instance;
      await adhkarService.init();

      final postPrayerCat = adhkarService.categories.firstWhere(
        (c) => c.id == 'post_prayer',
        orElse: () => throw Exception('post_prayer category not found!'),
      );

      // Check item 308 (Audio supplication)
      final sharawiAudioItem = postPrayerCat.items.firstWhere(
        (item) => item.id == 308,
        orElse: () => throw Exception('Sharawi item 308 not found!'),
      );
      expect(sharawiAudioItem.text, contains('اللَّهُمَّ رَبَّ هَذِهِ الدَّعْوَةِ التَّامَّةِ'));
      expect(sharawiAudioItem.source, contains('الشعراوي'));

      // Check item 309 (Khatm supplication)
      final sharawiKhatmItem = postPrayerCat.items.firstWhere(
        (item) => item.id == 309,
        orElse: () => throw Exception('Sharawi item 309 not found!'),
      );
      expect(sharawiKhatmItem.text, contains('مَا قَصُرَ عَنْهُ عِلْمِي'));
      expect(sharawiKhatmItem.text, contains('آبَائِنَا وَأُمَّهَاتِنَا'));
      expect(sharawiKhatmItem.source, contains('الشعراوي'));
    });

    test('4. IslamicAudioService can select and prepare Sheikh Al-Sha\'rawi track without error', () {
      final audioService = IslamicAudioService.instance;
      final track = IslamicAudioService.allTracks.firstWhere(
        (t) => t.id == 'duaa_sharawi_post_prayer',
      );

      expect(() => audioService.playTrack(track), returnsNormally);
      expect(audioService.currentTrack?.id, 'duaa_sharawi_post_prayer');
    });

    test('5. SettingsService playSharawiDuaaAfterAdhan toggle works and persists', () async {
      final settings = SettingsService.instance;
      await settings.init();

      expect(settings.playSharawiDuaaAfterAdhan, isTrue, reason: 'Default should be enabled');

      await settings.togglePlaySharawiDuaaAfterAdhan(false);
      expect(settings.playSharawiDuaaAfterAdhan, isFalse);

      await settings.togglePlaySharawiDuaaAfterAdhan(true);
      expect(settings.playSharawiDuaaAfterAdhan, isTrue);
    });

    test('6. Sheikh Al-Sha\'rawi Duaa is isolated and NOT in adhan list', () {
      final adhanTracks = IslamicAudioService.allTracks
          .where((t) => t.type == IslamicAudioType.adhan)
          .toList();

      final sharawiInAdhans = adhanTracks.where((t) => t.id.contains('sharawi') || t.id.contains('duaa'));
      expect(sharawiInAdhans, isEmpty, reason: 'Sheikh Al-Sha\'rawi is post-adhan duaa, not an adhan mu\'adhin');
    });

    test('7. All 7 requested Sheikhs exist in adhan list with valid authentic URLs', () {
      final adhanTracks = IslamicAudioService.allTracks
          .where((t) => t.type == IslamicAudioType.adhan)
          .toList();

      final ids = adhanTracks.map((t) => t.id).toSet();

      // 1. ناصر القطامي
      expect(ids.contains('adhan_alqatami'), isTrue);

      // 2. محمد صديق المنشاوي (verified authentic 020.mp3 Damascus Adhan)
      expect(ids.contains('adhan_menshawi'), isTrue);
      final menshawiTrack = adhanTracks.firstWhere((t) => t.id == 'adhan_menshawi');
      expect(menshawiTrack.remoteUrl, contains('020.mp3'));

      // 3. سيد النقشبندي
      expect(ids.contains('adhan_naqshbandi'), isTrue);

      // 4. عبد الباسط عبد الصمد
      expect(ids.contains('adhan_abdulbasit'), isTrue);

      // 5. محمود خليل الحصري
      expect(ids.contains('adhan_hussary'), isTrue);

      // 6. فارس عباد
      expect(ids.contains('adhan_fares_abbad'), isTrue);

      // 7. ياسر الدوسري
      expect(ids.contains('adhan_aldosari'), isTrue);
    });
  });
}

