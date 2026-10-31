import 'package:flutter/foundation.dart';

/// منصات الاستماع المتاحة للمختصر الصوتي في تفسير القرآن
enum AudioTafsirPlatform {
  youtube('يوتيوب (YouTube)', 'قائمة التشغيل المرئية والصوتية الكاملة', 'https://www.youtube.com'),
  applePodcasts('أبل بودكاست (Apple Podcasts)', 'استماع عالي الجودة لجميع السور', 'https://podcasts.apple.com'),
  soundCloud('ساوند كلاود (SoundCloud)', 'مجموعة المقاطع الصوتية الكاملة', 'https://soundcloud.com'),
  podbean('بودبين (Podbean)', 'البث الصوتي والتحميل المباشر', 'https://podbean.com'),
  telegram('تيليجرام (Telegram)', 'قناة الصوتيات والتفريغ', 'https://t.me');

  final String title;
  final String subtitle;
  final String baseUrl;

  const AudioTafsirPlatform(this.title, this.subtitle, this.baseUrl);
}

/// بيانات الشيخ المفسر في مشروع المختصر الصوتي
class AudioTafsirScholar {
  final String id;
  final String name;
  final String titleHonorific;
  final String description;
  final String youtubePlaylistUrl;
  final String applePodcastsUrl;
  final String soundCloudUrl;
  final String podbeanUrl;
  final String? telegramUrl;
  final String avatarAssetOrIcon;

  const AudioTafsirScholar({
    required this.id,
    required this.name,
    required this.titleHonorific,
    required this.description,
    required this.youtubePlaylistUrl,
    required this.applePodcastsUrl,
    required this.soundCloudUrl,
    required this.podbeanUrl,
    this.telegramUrl,
    required this.avatarAssetOrIcon,
  });

  Map<AudioTafsirPlatform, String> get platformLinks {
    final map = <AudioTafsirPlatform, String>{
      AudioTafsirPlatform.youtube: youtubePlaylistUrl,
      AudioTafsirPlatform.applePodcasts: applePodcastsUrl,
      AudioTafsirPlatform.soundCloud: soundCloudUrl,
      AudioTafsirPlatform.podbean: podbeanUrl,
    };
    if (telegramUrl != null) {
      map[AudioTafsirPlatform.telegram] = telegramUrl!;
    }
    return map;
  }
}

/// خدمة المختصر في تفسير القرآن الكريم صوتياً
/// مستخرجة من: «ملف_تفسير_القران_الكريم_صوتيا_pdf.pdf» الصادر عن مركز تفسير للدراسات القرآنية
class AudioTafsirService extends ChangeNotifier {
  static final AudioTafsirService instance = AudioTafsirService._internal();
  AudioTafsirService._internal();

  static const String projectTitle = 'المختصر في تفسير القرآن الكريم (صوتياً)';
  static const String issuingBody = 'مركز تفسير للدراسات القرآنية';
  static const String generalTelegramUrl = 'https://t.me/MokhSound';
  static const String projectDescription =
      'مشروع صوتي مبارك وشامل يهدف إلى تقريب معاني كتاب الله الكريم لكافة المسلمين '
      'بأسلوب سهل وموجز وموثق، بصوت نخبة من كبار المشايخ المتقنين، متاح كاملاً عبر يوتيوب، '
      'أبل بودكاست، ساوندكلاود، بودبين، وتيليجرام.';

  /// قائمة المشايخ الثلاثة المعتمدين في الملف
  static const List<AudioTafsirScholar> scholars = [
    AudioTafsirScholar(
      id: 'asmari',
      name: 'الشيخ عبد الله الأسمري',
      titleHonorific: 'فضيلة الشيخ',
      description:
          'قراءة صوتية متقنة ومؤثرة لكتاب المختصر في تفسير القرآن الكريم، تغطي سور القرآن الـ ١١٤ بيسر وسكينة.',
      youtubePlaylistUrl:
          'https://www.youtube.com/playlist?list=PLoslTfCHb8N-fI69sNcTAVTh9JDrspjo2',
      applePodcastsUrl:
          'https://podcasts.apple.com/sa/podcast/%D8%A7%D9%84%D9%85%D8%AE%D8%AA%D8%B5%D8%B1-%D9%81%D9%8A-%D8%AA%D9%81%D8%B3%D9%8A%D8%B1-%D8%A7%D9%84%D9%82%D8%B1%D8%A2%D9%86-%D8%A7%D9%84%D9%83%D8%B1%D9%8A%D9%85-%D8%B9%D8%A8%D8%AF%D8%A7%D9%84%D9%84%D9%87-%D8%A7%D9%84%D8%A3%D8%B3%D9%85%D8%B1%D9%8A/id1555920673',
      soundCloudUrl: 'https://soundcloud.com/tafsircenter/sets/mokhasmari',
      podbeanUrl: 'https://mokhasmari.podbean.com/',
      telegramUrl: 'https://t.me/MokhSound',
      avatarAssetOrIcon: 'asmari',
    ),
    AudioTafsirScholar(
      id: 'ghamdi',
      name: 'الشيخ ساعد الغامدي',
      titleHonorific: 'فضيلة الشيخ',
      description:
          'تسجيل صوتي كامل للتفسير الميسر والمختصر من مركز تفسير، بصوت خاشع ومخارج ألفاظ نقية وواضحة.',
      youtubePlaylistUrl:
          'https://www.youtube.com/playlist?list=PLoslTfCHb8N8Yt4hoCyXN_DK6Ko8A98cF',
      applePodcastsUrl:
          'https://podcasts.apple.com/sa/podcast/%D8%A7%D9%84%D9%85%D8%AE%D8%AA%D8%B5%D8%B1-%D9%81%D9%8A-%D8%AA%D9%81%D8%B3%D9%8A%D8%B1-%D8%A7%D9%84%D9%82%D8%B1%D8%A2%D9%86-%D8%A7%D9%84%D9%83%D8%B1%D9%8A%D9%85-%D8%B3%D8%A7%D8%B9%D8%AF-%D8%A7%D9%84%D8%BA%D8%A7%D9%85%D8%AF%D9%8A/id1556376818',
      soundCloudUrl: 'https://soundcloud.com/tafsircenter/sets/mokhghamdi',
      podbeanUrl: 'https://mokhghamdi.podbean.com/',
      telegramUrl: 'https://t.me/MokhSound',
      avatarAssetOrIcon: 'ghamdi',
    ),
    AudioTafsirScholar(
      id: 'shaya',
      name: 'الشيخ عبد الرحمن الشايع',
      titleHonorific: 'فضيلة الشيخ',
      description:
          'قراءة بيانية علمية هادئة تسلط الضوء على هدايات الآيات ومعاني القرآن الكريم بأسلوب تدبري رقراق.',
      youtubePlaylistUrl:
          'https://www.youtube.com/playlist?list=PLoslTfCHb8N_aeCuUbCSRSgIGb2ZgAkA1',
      applePodcastsUrl:
          'https://podcasts.apple.com/sa/podcast/%D8%A7%D9%84%D9%85%D8%AE%D8%AA%D8%B5%D8%B1-%D9%81%D9%8A-%D8%AA%D9%81%D8%B3%D9%8A%D8%B1-%D8%A7%D9%84%D9%82%D8%B1%D8%A2%D9%86-%D8%A7%D9%84%D9%83%D8%B1%D9%8A%D9%85-%D8%B9%D8%A8%D8%AF%D8%A7%D9%84%D8%B1%D8%AD%D9%85%D9%86-%D8%A7%D9%84%D8%B4%D8%A7%D9%8a%D8%B9/id1556376528',
      soundCloudUrl: 'https://soundcloud.com/tafsircenter/sets/mokhalshaya',
      podbeanUrl: 'https://mokhalshaya.podbean.com/',
      telegramUrl: 'https://t.me/MokhSound',
      avatarAssetOrIcon: 'shaya',
    ),
  ];

  AudioTafsirScholar? getScholarById(String id) {
    try {
      return scholars.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }
}
