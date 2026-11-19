import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/audio/fast_audio_service.dart';
import 'package:almomin/core/audio/ayah_audio_player.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/ui/portal_category_card.dart';
import 'package:almomin/core/ui/adaptive_screen_layouts.dart';
import 'package:almomin/features/home/widgets/home_quick_sections_grid.dart';
import 'package:almomin/features/settings/widgets/adhan_voice_option.dart';

Widget frame(Widget child, {double scale = 1}) => MaterialApp(
      theme: ThemeData(fontFamily: 'Cairo', useMaterial3: true),
      home: MediaQuery(
          data: MediaQueryData(
              size: const Size(420, 900), textScaler: TextScaler.linear(scale)),
          child: Directionality(
              textDirection: TextDirection.rtl, child: Scaffold(body: child))),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init(forceReload: true);
  });

  test('Retired standalone screens have no incoming references from the app',
      () {
    const retired = [
      'hadith_library_screen.dart',
      'hadith_detail_screen.dart',
      'islamic_mutoon_screen.dart',
      'riyad_alsalihin_screen.dart'
    ];
    const classes = [
      'HadithLibraryScreen',
      'HadithDetailScreen',
      'IslamicMutoonScreen',
      'RiyadAlSalihinScreen'
    ];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      if (retired.any((name) => f.path.endsWith(name))) continue;
      final text = f.readAsStringSync();
      for (final name in [...retired, ...classes]) {
        expect(text.contains(name), isFalse,
            reason: '${f.path} must not reach $name');
      }
    }
    final router = File('lib/app/router.dart').readAsStringSync();
    for (final path in [
      '/hadith',
      '/hadith-detail',
      '/riyad-alsalihin',
      '/islamic-mutoon'
    ]) {
      expect(RegExp("path: ['\"]" + path + "['\"]").hasMatch(router), isFalse);
    }
    expect(
        File('lib/features/library/islamic_library_screen.dart')
            .readAsStringSync(),
        contains('ShamelaLibraryScreen'));
  });

  testWidgets('Navigation cards expose the name, not filler, to every user',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(frame(PortalCategoryCard(
      numberText: '١',
      title: 'المكتبة',
      subtitle: 'FILLER',
      icon: Icons.book,
      color: Colors.green,
      onTap: () {},
    )));
    expect(find.text('المكتبة'), findsOneWidget);
    expect(find.text('FILLER'), findsNothing);
    expect(find.bySemanticsLabel('المكتبة'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('FILLER')), findsNothing);
    semantics.dispose();
  });

  testWidgets('Home keeps the five names without old Riyad description',
      (tester) async {
    await tester.pumpWidget(frame(
        const SingleChildScrollView(child: HomeQuickSectionsGrid()),
        scale: 2));
    expect(find.text('رياض الصالحين والقصص والفقه'), findsNothing);
    expect(find.text('المصحف الشريف'), findsOneWidget);
    expect(find.text('ختمة القرآن'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final mode in ScreenStructureMode.values) {
    testWidgets(
        'Navigation hides prose in ${mode.name}, content previews survive',
        (tester) async {
      final item = StructuredScreenItem(
          id: 'a',
          title: 'اسم الزر',
          subtitle: 'CONTENT_PREVIEW',
          icon: Icons.book,
          accentColor: Colors.green,
          onTap: () {});
      await tester.pumpWidget(frame(SingleChildScrollView(
          child: AdaptiveStructuredCollectionView(
              mode: mode, items: [item], showDescriptions: false))));
      expect(find.text('اسم الزر'), findsOneWidget);
      expect(find.text('CONTENT_PREVIEW'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(frame(SingleChildScrollView(
          child: AdaptiveStructuredCollectionView(mode: mode, items: [item]))));
      expect(find.text('CONTENT_PREVIEW'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final downloaded in [false, true]) {
    testWidgets('Voice actions stay independent, downloaded=$downloaded',
        (tester) async {
      int listen = 0, assign = 0, download = 0;
      await tester.pumpWidget(frame(
          AdhanVoiceOption(
              name: 'اسم المؤذن',
              selected: false,
              playing: false,
              downloaded: downloaded,
              downloading: false,
              onListen: () => listen++,
              onAssign: () => assign++,
              onDownload: () => download++),
          scale: 2));
      expect(find.text('استماع'), findsOneWidget);
      expect(find.text('تعيين'), findsOneWidget);
      expect(find.text('تحميل'), downloaded ? findsNothing : findsOneWidget);
      await tester.tap(find.text('استماع'));
      await tester.tap(find.text('تعيين'));
      if (!downloaded) await tester.tap(find.text('تحميل'));
      expect(listen, 1);
      expect(assign, 1);
      expect(download, downloaded ? 0 : 1);
      expect(tester.takeException(), isNull);
    });
  }

  test('Network-only adhan preview never falls back to its bundled asset',
      () async {
    final fast = FastAudioService.instance;
    fast.resetForTesting();
    final seenNetworkOnly = <bool>[];
    fast.getFastAudioSourceOverride = (url,
        {required cacheKey, localDownloadedPath, isLiveStream = false}) async {
      seenNetworkOnly.add(isLiveStream);
      expect(localDownloadedPath, isNull);
      throw const SocketException('offline fixture');
    };
    final bundled = IslamicAudioService.allTracks
        .firstWhere((t) => t.isBundled && t.remoteUrl != null);
    expect(
        await IslamicAudioService.instance.playOnlinePreview(bundled), isFalse);
    expect(seenNetworkOnly, isNotEmpty);
    expect(seenNetworkOnly.every((value) => value), isTrue);
    expect(IslamicAudioService.instance.isPlaying, isFalse);
    fast.resetForTesting();
  });

  testWidgets(
      'Failed verse listening shows an internet message and clears playing state',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(frame(Builder(builder: (c) {
      context = c;
      return const SizedBox();
    })));
    final player = AyahAudioPlayer.instance;
    player.resetForTesting();
    player.stopPlayerRunner = () async {};
    player.playResilientRunner = (url,
            {player,
            primaryUrl,
            fallbackUrls = const [],
            cacheKey,
            localDownloadedPath,
            onStopCallback}) async =>
        false;
    await player.playAyah(context, 1, 1);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.textContaining('التحقق من الاتصال بالإنترنت'), findsOneWidget);
    expect(player.isPlaying.value, isFalse);
    player.resetForTesting();
  });
}
