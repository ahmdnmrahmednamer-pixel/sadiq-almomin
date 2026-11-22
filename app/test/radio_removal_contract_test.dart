import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('removed radio implementation, station asset and switches are absent',
      () {
    for (final path in [
      'lib/features/radio',
      'lib/core/services/islamic_radio_service.dart',
      'lib/core/models/islamic_radio.dart',
      'lib/core/feature_flags.dart',
      'assets/data/radio_stations.json',
    ]) {
      expect(FileSystemEntity.typeSync(path), FileSystemEntityType.notFound,
          reason: '$path must not ship as a hidden feature');
    }
  });

  test('production code has no radio entrypoints, models or backup hooks', () {
    const retired = [
      'CuratedRadio',
      'IslamicRadio',
      'EgyptianRadioStation',
      'radioStations',
      'playLiveRadio',
      '/islamic-radio',
      '/curated-radio',
      'radio_stations.json',
      'curated_radio_favorites',
      'radio_favorites',
      'eg_hub_radio',
      'home_islamic_radio_banner',
    ];
    for (final file
        in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      for (final token in retired) {
        expect(source.contains(token), isFalse,
            reason: '${file.path} still references $token');
      }
    }
  });
}
