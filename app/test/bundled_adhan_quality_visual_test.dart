import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/features/audio/widgets/full_screen_studio_player.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('bundled quality badge readable at $scale', (t) async {
      await t.runAsync(() async {
        await (FontLoader('Cairo')
              ..addFont(Future.value(ByteData.sublistView(
                  File('assets/fonts/Cairo-Regular.ttf').readAsBytesSync()))))
            .load();
      });
      t.view.physicalSize = const Size(360, 1200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final service = IslamicAudioService.instance;
      service.disableNativePlayerForTesting = true;
      final track = IslamicAudioService.allTracks
          .singleWhere((x) => x.id == 'adhan_hussary');
      service.seedPlaybackSnapshotForTesting(
          queue: [track], currentIndex: 0, playing: false);
      final key = GlobalKey();
      await t.pumpWidget(RepaintBoundary(
          key: key,
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(fontFamily: 'Cairo'),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: const Scaffold(body: FullScreenStudioPlayer()))));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(find.text(track.quality), findsOneWidget);
      expect(t.takeException(), isNull);
      final dir = Platform.environment['QUALITY_SCREENSHOT_DIR'];
      if (dir != null)
        await t.runAsync(() async {
          final image = await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$dir/quality-$scale.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
        });
      await t.pumpWidget(const SizedBox());
      await service.stop();
      service.disableNativePlayerForTesting = false;
    });
  }
}
