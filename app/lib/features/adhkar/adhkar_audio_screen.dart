import 'package:flutter/material.dart';
import '../../core/services/islamic_audio_service.dart';
import '../../core/services/settings_service.dart';

/// Presentation-only, asset-only queue. Separate IDs cannot reuse catalog downloads.
class AdhkarAudioScreen extends StatefulWidget {
  const AdhkarAudioScreen({super.key});

  static const tracks = <IslamicAudioTrack>[
    IslamicAudioTrack(
        id: 'adhkar_asset_reviewed_morning',
        title: 'أذكار الصباح',
        subtitle: 'تسجيل مرفق بالتطبيق',
        type: IslamicAudioType.adhkar,
        assetPath: 'assets/audio/adhkar_morning_full.mp3',
        durationFormatted: '02:56',
        quality: ''),
    IslamicAudioTrack(
        id: 'adhkar_asset_reviewed_evening',
        title: 'أذكار المساء',
        subtitle: 'تسجيل مرفق بالتطبيق',
        type: IslamicAudioType.adhkar,
        assetPath: 'assets/audio/adhkar_evening_full.mp3',
        durationFormatted: '03:20',
        quality: ''),
    IslamicAudioTrack(
        id: 'adhkar_asset_reviewed_sleep',
        title: 'أذكار النوم',
        subtitle: 'تسجيل مرفق بالتطبيق',
        type: IslamicAudioType.adhkar,
        assetPath: 'assets/audio/adhkar_sleep_full.mp3',
        durationFormatted: '01:59',
        quality: ''),
    IslamicAudioTrack(
        id: 'adhkar_asset_reviewed_post_adhan',
        title: 'دعاء بعد الأذان',
        subtitle: 'تسجيل مرفق بالتطبيق',
        type: IslamicAudioType.adhkar,
        assetPath: 'assets/audio/duaa_sharawi_post_prayer.mp3',
        durationFormatted: '01:08',
        quality: ''),
  ];

  static const bundledCatalogIds = {
    'adhkar_morning',
    'adhkar_evening',
    'adhkar_sleep',
    'duaa_sharawi_post_prayer'
  };
  static List<IslamicAudioTrack> get pendingTracks =>
      IslamicAudioService.allTracks
          .where((t) =>
              t.type == IslamicAudioType.adhkar &&
              !bundledCatalogIds.contains(t.id))
          .toList(growable: false);

  @override
  State<AdhkarAudioScreen> createState() => _AdhkarAudioScreenState();
}

class _AdhkarAudioScreenState extends State<AdhkarAudioScreen> {
  final service = IslamicAudioService.instance;

  @override
  void initState() {
    super.initState();
    service.init();
    service.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    service.removeListener(_changed);
    super.dispose();
  }

  Future<void> _activate(int index) async {
    final track = AdhkarAudioScreen.tracks[index];
    if (service.currentTrack?.id == track.id) {
      if (service.isPlaying) {
        await service.pause();
      } else {
        await service.resume();
      }
    } else {
      await service.playQueue(AdhkarAudioScreen.tracks, startIndex: index);
    }
  }

  String _clock(Duration duration) =>
      '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final current = service.currentTrack;
    final safeCurrent =
        AdhkarAudioScreen.tracks.any((track) => track.id == current?.id);
    final large = MediaQuery.textScalerOf(context).scale(16) >= 22;
    return Directionality(
      textDirection: SettingsService.instance.textDirection,
      child: Scaffold(
        appBar: AppBar(
            title: const Text('الأذكار المسموعة', maxLines: 2),
            toolbarHeight: large ? 110 : 64),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('تسجيلات مرفقة',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
              'أسماء مختصرة بحسب المحتوى المراجع. لا تعني أن التسجيل يشمل كل أذكار الباب.'),
          if (current != null)
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(safeCurrent
                              ? 'التسجيل الحالي: ${current.title}'
                              : 'يوجد تشغيل من قسم آخر. لم تُراجع هويته هنا.'),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                              onPressed: service.stop,
                              icon: const Icon(Icons.stop),
                              label: const Text('إيقاف التشغيل الحالي')),
                          if (safeCurrent &&
                              service.duration > Duration.zero) ...[
                            Text(
                                '${_clock(service.position)} / ${_clock(service.duration)}'),
                            Slider(
                                semanticFormatterCallback: (value) =>
                                    '${value.round()} ثانية',
                                value: service.position.inSeconds
                                    .toDouble()
                                    .clamp(0,
                                        service.duration.inSeconds.toDouble()),
                                max: service.duration.inSeconds.toDouble(),
                                onChanged: (value) => service
                                    .seek(Duration(seconds: value.round()))),
                          ],
                        ]))),
          ...AdhkarAudioScreen.tracks.asMap().entries.map((entry) {
            final track = entry.value;
            final active = current?.id == track.id;
            final playing = active && service.isPlaying;
            return Card(
                child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(track.title,
                              style: const TextStyle(
                                  fontSize: 19, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Text('مرفق بالتطبيق، ${track.durationFormatted}'),
                          const SizedBox(height: 8),
                          FilledButton(
                              style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 16)),
                              onPressed: () => _activate(entry.key),
                              child: Text(
                                  '${playing ? 'إيقاف مؤقت' : 'استمع'}: ${track.title}')),
                          if (active && service.isBuffering)
                            const LinearProgressIndicator(
                                semanticsLabel: 'جار تحميل التسجيل المرفق'),
                        ])));
          }),
          const SizedBox(height: 24),
          const Text('تسجيلات تحتاج مراجعة',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
              'حُفظت سجلاتها الأصلية. الاستماع والتحميل غير متاحين هنا حتى مطابقة الأسماء بالتسجيلات ومراجعة مصادرها.'),
          ...AdhkarAudioScreen.pendingTracks.map((track) => Card(
              child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                            'الاسم السابق في الفهرس، غير موثّق: ${track.title}',
                            style: const TextStyle(fontSize: 16)),
                        const SizedBox(height: 8),
                        Text(track.id == 'dua_khatm_abdulbasit'
                            ? 'المصدر الذي فُحص تلاوة لسورة الناس، وليس دعاء ختم القرآن.'
                            : 'المحتوى أو نسبته أو مصدره يحتاج مراجعة.'),
                        const SizedBox(height: 8),
                        const OutlinedButton(
                            onPressed: null,
                            child: Text('الاستماع والتحميل غير متاحين')),
                      ])))),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}
