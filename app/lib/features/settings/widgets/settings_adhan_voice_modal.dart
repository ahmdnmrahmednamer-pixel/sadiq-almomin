import 'adhan_voice_option.dart';
import '../../../core/text/arabic_normalizer.dart';
import '../../../core/services/settings_service.dart';
import 'package:flutter/material.dart';
import '../../../core/notifications/prayer_notification_service.dart';
import '../../../core/services/islamic_audio_service.dart';

String getAdhanVoiceName(String key) {
  final track = IslamicAudioService.allTracks.firstWhere(
    (t) => t.id == key || t.rawNotificationSound == key,
    orElse: () => IslamicAudioService.allTracks.first,
  );
  return adhanVoiceLabel(track);
}

String adhanVoiceLabel(IslamicAudioTrack track) {
  final name = track.muezzinName?.trim();
  if (name == null || name.isEmpty) return track.title;
  return track.id.contains('fajr') ? '$name (الفجر)' : name;
}

String getIqamahVoiceName(String key) {
  switch (key) {
    case 'iqamah_madinah':
      return 'إقامة المسجد النبوي الشريف (المدينة المنورة)';
    case 'iqamah_afasy':
      return 'إقامة الشيخ مشاري بن راشد العفاسي';
    case 'iqamah_abdulbasit':
      return 'إقامة الشيخ عبد الباسط عبد الصمد';
    case 'iqamah_cairo':
      return 'إقامة مساجد القاهرة والأزهر الشريف';
    case 'iqamah_short':
      return 'إقامة سريعة وخفيفة للتنبيه';
    case 'iqamah_makkah':
    case 'iqamah_full':
    default:
      return 'إقامة المسجد الحرام (مكة المكرمة)';
  }
}

void showSettingsAdhanVoiceModal(BuildContext context,
    {int initialTab = 0, String? initialPrayer}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _PrayerMuezzinManagerSheet(
      initialTab: initialTab,
      initialPrayer: initialPrayer,
    ),
  );
}

/// Sheet showing the 5 daily prayers, each with its dedicated Muezzin dropdown and audio preview
class _PrayerMuezzinManagerSheet extends StatefulWidget {
  final int initialTab;
  final String? initialPrayer;
  const _PrayerMuezzinManagerSheet({this.initialTab = 0, this.initialPrayer});
  @override
  State<_PrayerMuezzinManagerSheet> createState() =>
      _PrayerMuezzinManagerSheetState();
}

class _PrayerMuezzinManagerSheetState
    extends State<_PrayerMuezzinManagerSheet> {
  @override
  void initState() {
    super.initState();
    if (widget.initialPrayer != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted)
          showPrayerMuezzinDropdownPicker(context, widget.initialPrayer!);
      });
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: SettingsService.instance.textDirection,
        child: SafeArea(
            child: Material(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.88,
            child: Column(children: [
              ListTile(
                  title: const Text('مؤذنو الصلوات الخمس'),
                  trailing: IconButton(
                      tooltip: 'إغلاق',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context))),
              const Expanded(
                  child: SingleChildScrollView(child: PrayerVoiceList())),
            ]),
          ),
        )),
      );
}

/// All entry points open the same per-prayer voice picker.
class PrayerVoiceList extends StatelessWidget {
  const PrayerVoiceList({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: PrayerNotificationService.instance,
        builder: (context, _) {
          final notifications = PrayerNotificationService.instance;
          return Column(children: [
            for (final name in ['الفجر', 'الظهر', 'العصر', 'المغرب', 'العشاء'])
              ListTile(
                key: ValueKey('prayer_voice_$name'),
                title: Text('صلاة $name'),
                subtitle:
                    Text(getAdhanVoiceName(notifications.getPrayerVoice(name))),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => showPrayerMuezzinDropdownPicker(context, name),
              ),
            ListTile(
                title: const Text('مؤذن لجميع الصلوات'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => showPrayerMuezzinDropdownPicker(context, 'الكل')),
            ListTile(
                title: const Text('صوت الإقامة'),
                subtitle:
                    Text(getIqamahVoiceName(notifications.selectedIqamahVoice)),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => showPrayerMuezzinDropdownPicker(
                    context, 'إقامة الصلاة',
                    isIqamah: true)),
          ]);
        },
      );
}

/// Interactive Dropdown/Picker Sheet for choosing a Sheikh for a specific prayer
/// Allows listening to any Sheikh's voice before selecting him
void showPrayerMuezzinDropdownPicker(BuildContext context, String prayerName,
    {bool isIqamah = false}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _PrayerMuezzinPickerSheet(
      prayerName: prayerName,
      isIqamah: isIqamah,
    ),
  );
}

class _PrayerMuezzinPickerSheet extends StatefulWidget {
  final String prayerName;
  final bool isIqamah;

  const _PrayerMuezzinPickerSheet({
    required this.prayerName,
    this.isIqamah = false,
  });

  @override
  State<_PrayerMuezzinPickerSheet> createState() =>
      _PrayerMuezzinPickerSheetState();
}

class _PrayerMuezzinPickerSheetState extends State<_PrayerMuezzinPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _currentlyPlayingTrackId;

  @override
  void initState() {
    super.initState();
    IslamicAudioService.instance.init();
  }

  @override
  void dispose() {
    IslamicAudioService.instance.stop();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _playPreview(IslamicAudioTrack track) async {
    final audio = IslamicAudioService.instance;
    if (_currentlyPlayingTrackId == track.id && audio.isPlaying) {
      await audio.stop();
      if (mounted) setState(() => _currentlyPlayingTrackId = null);
    } else {
      if (mounted) setState(() => _currentlyPlayingTrackId = track.id);
      final ok = await audio.playOnlinePreview(track);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'تعذر تشغيل الصوت عبر الإنترنت. تحقق من اتصالك ثم حاول مرة أخرى.')));
      }
    }
  }

  List<IslamicAudioTrack> _getFilteredTracks() {
    final all = IslamicAudioService.allTracks.where((t) {
      if (widget.isIqamah) {
        return t.type == IslamicAudioType.iqamah;
      } else {
        return t.type == IslamicAudioType.adhan &&
            !t.id.contains('duaa') &&
            !t.id.contains('sharawi');
      }
    }).toList();

    if (_searchQuery.trim().isEmpty) return all;

    final q = _searchQuery.trim().toLowerCase();
    final normQ = ArabicNormalizer.normalize(_searchQuery, loose: true);
    return all.where((t) {
      final matchTitle = t.title.toLowerCase().contains(q) ||
          ArabicNormalizer.normalize(t.title, loose: true).contains(normQ);
      final matchSub = t.subtitle.toLowerCase().contains(q) ||
          ArabicNormalizer.normalize(t.subtitle, loose: true).contains(normQ);
      final matchMuezzin =
          (t.muezzinName?.toLowerCase().contains(q) ?? false) ||
              (t.muezzinName != null &&
                  ArabicNormalizer.normalize(t.muezzinName!, loose: true)
                      .contains(normQ));
      final matchCat = (t.categoryAr?.toLowerCase().contains(q) ?? false) ||
          (t.categoryAr != null &&
              ArabicNormalizer.normalize(t.categoryAr!, loose: true)
                  .contains(normQ));
      return matchTitle || matchSub || matchMuezzin || matchCat;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final audio = IslamicAudioService.instance;
    final notifications = PrayerNotificationService.instance;
    return Directionality(
      textDirection: SettingsService.instance.textDirection,
      child: SafeArea(
        child: Container(
          height: MediaQuery.sizeOf(context).height * 0.88,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(children: [
                Expanded(
                    child: Text(
                        widget.isIqamah
                            ? 'صوت الإقامة'
                            : widget.prayerName == 'الكل'
                                ? 'مؤذن لجميع الصلوات'
                                : 'مؤذن ${widget.prayerName}',
                        style: Theme.of(context).textTheme.titleLarge)),
                IconButton(
                    tooltip: 'إغلاق',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _searchQuery = value),
                  decoration: const InputDecoration(
                      labelText: 'بحث باسم المؤذن',
                      prefixIcon: Icon(Icons.search))),
            ),
            Expanded(
                child: AnimatedBuilder(
              animation: Listenable.merge([audio, notifications]),
              builder: (context, _) {
                final tracks = _getFilteredTracks();
                final selected = widget.isIqamah
                    ? notifications.selectedIqamahVoice
                    : widget.prayerName == 'الكل'
                        ? notifications.selectedAdhanVoice
                        : notifications.getPrayerVoice(widget.prayerName);
                if (tracks.isEmpty)
                  return const Center(child: Text('لا توجد أصوات مطابقة'));
                return ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  itemCount: tracks.length,
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    return AdhanVoiceOption(
                      key: ValueKey('voice_${track.id}'),
                      name: adhanVoiceLabel(track),
                      selected: selected == track.id ||
                          selected == track.rawNotificationSound,
                      playing:
                          audio.currentTrack?.id == track.id && audio.isPlaying,
                      downloaded:
                          track.isBundled || audio.isDownloaded(track.id),
                      downloading: audio.isDownloading(track.id),
                      onListen: () => _playPreview(track),
                      onAssign: () async {
                        await audio.stop();
                        if (widget.isIqamah) {
                          await notifications.setSelectedIqamahVoice(track.id);
                        } else if (widget.prayerName == 'الكل') {
                          await notifications.setAllPrayersVoice(track.id);
                        } else {
                          await notifications.setPrayerVoice(
                              widget.prayerName, track.id);
                        }
                        if (!context.mounted) return;
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(
                                'تم تعيين ${adhanVoiceLabel(track)}: ${widget.prayerName}')));
                      },
                      onDownload: () async {
                        final ok = await audio.downloadTrack(track.id);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(ok
                                ? 'تم التحميل'
                                : 'تعذر التحميل. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.')));
                      },
                    );
                  },
                );
              },
            )),
          ]),
        ),
      ),
    );
  }
}
