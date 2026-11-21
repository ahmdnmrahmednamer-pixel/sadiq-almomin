/// Pure immutable audio types, shared without initializing playback services.
enum IslamicAudioType {
  adhan,
  iqamah,
  adhkar,
  tasbih,
  quran,
  story,
  lesson,
}

enum PlaybackLoopMode {
  off,
  all,
  single,
}

enum AudioClarityPreset {
  studioHd('studio_hd', 'استوديو فائق النقاء (HD Master)', 1.0),
  mosqueEcho('mosque_echo', 'رحاب الحرم والمسجد (خاشع)', 1.0),
  warmVoice('warm_voice', 'صوت دافئ رخيم (للقراء والابتهالات)', 1.0),
  clearSpeech('clear_speech', 'تعزيز وضوح الصوت (للدروس والأدعية)', 1.0);

  final String id;
  final String labelAr;
  final double volumeGain;
  const AudioClarityPreset(this.id, this.labelAr, this.volumeGain);

  static AudioClarityPreset fromId(String id) {
    return AudioClarityPreset.values.firstWhere(
      (e) => e.id == id,
      orElse: () => AudioClarityPreset.studioHd,
    );
  }
}

class IslamicAudioTrack {
  final String id;
  final String title;
  final String subtitle;
  final IslamicAudioType type;
  final String? assetPath;
  final String? remoteUrl;
  final List<String> fallbackUrls;
  final String durationFormatted;
  final String? rawNotificationSound;
  final String quality;
  final int? fileSizeBytes;
  final String? categoryAr;
  final String? muezzinName;
  final String? imageUrl;
  final int? surahNumber;
  final String? reciterId;

  const IslamicAudioTrack({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.type,
    this.assetPath,
    this.remoteUrl,
    this.fallbackUrls = const [],
    required this.durationFormatted,
    this.rawNotificationSound,
    this.quality = 'عالي النقاء HD',
    this.fileSizeBytes,
    this.categoryAr,
    this.muezzinName,
    this.imageUrl,
    this.surahNumber,
    this.reciterId,
  });

  bool get isBundled => assetPath != null;
}
