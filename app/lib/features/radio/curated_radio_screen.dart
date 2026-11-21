import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/audio/fast_audio_service.dart';

/// One station from the owner's supplied radio tool. Titles and links are used as received.
class CuratedStation {
  final String id;
  final String name;
  final String url;
  const CuratedStation(this.id, this.name, this.url);
}

class CuratedCategory {
  final String id;
  final String title;
  final List<CuratedStation> stations;
  const CuratedCategory(this.id, this.title, this.stations);
}

/// Loads and validates the bundled station list. Throws FormatException on a bad file.
Future<List<CuratedCategory>> loadCuratedCategories({AssetBundle? bundle}) async {
  final raw = await (bundle ?? rootBundle).loadString('assets/data/radio_stations.json');
  final data = jsonDecode(raw) as Map<String, dynamic>;
  final seen = <String>{};
  final out = <CuratedCategory>[];
  for (final c in (data['categories'] as List)) {
    final stations = <CuratedStation>[];
    for (final s in (c['stations'] as List)) {
      final id = s['id'] as String;
      final url = s['url'] as String;
      final uri = Uri.tryParse(url);
      if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) {
        throw FormatException('Bad station url for $id');
      }
      if (!seen.add(id)) throw FormatException('Duplicate station id $id');
      stations.add(CuratedStation(id, (s['title'] as String).trim(), url));
    }
    out.add(CuratedCategory(c['id'] as String, c['title'] as String, stations));
  }
  return out;
}

/// Minimal player seam so the screens can be tested without audio hardware.
abstract class CuratedRadioPlayer {
  Future<void> play(String url);
  Future<void> stop();

  /// Emits when a station that started playing later fails.
  Stream<Object> get errors;
  void dispose();
}

class JustAudioRadioPlayer implements CuratedRadioPlayer {
  final AudioPlayer _p = AudioPlayer();
  final StreamController<Object> _errors = StreamController<Object>.broadcast();
  StreamSubscription<PlaybackEvent>? _sub;

  JustAudioRadioPlayer() {
    _sub = _p.playbackEventStream.listen((_) {}, onError: (Object e, StackTrace _) => _errors.add(e));
  }

  @override
  Future<void> play(String url) async {
    await _p.setUrl(url);
    // play() completes only when playback ends, so it is not awaited for a live stream.
    unawaited(_p.play().catchError((Object e) => _errors.add(e)));
  }

  @override
  Future<void> stop() => _p.stop();

  @override
  Stream<Object> get errors => _errors.stream;

  @override
  void dispose() {
    _sub?.cancel();
    _errors.close();
    _p.dispose();
  }
}

/// Marker pushed on the player's error stream when the central audio service
/// stopped this station because another owner claimed the focus. It is not a
/// failure, so the screen clears the playing state without an error message.
class RadioStoppedExternally {
  const RadioStoppedExternally();
}

/// Production player backed by the central FastAudioService (PR132 contract).
/// A rejected focus claim surfaces as a thrown failure; there is never a
/// direct fallback play after a `false` from the service.
class FastAudioRadioPlayer implements CuratedRadioPlayer {
  FastAudioRadioPlayer({
    AudioPlayer? nativeTarget,
    Future<bool> Function(String url, Future<void> Function()? onStopCallback)?
        playFn,
    Future<void> Function()? stopFn,
  }) {
    // A dedicated target makes every stop owner-scoped. The central service
    // still admits focus and checks its token before playback starts.
    if (playFn == null) {
      _nativePlayer = nativeTarget ?? AudioPlayer();
      _nativeSub = _nativePlayer!.playbackEventStream.listen((_) {},
          onError: (Object e, StackTrace _) {
        if (!_errors.isClosed) _errors.add(e);
      });
    }
    _playFn = playFn ?? ((url, callback) =>
        FastAudioService.instance.playResilient(url,
          player: _nativePlayer!, isLiveStream: true,
          onStopCallback: callback));
    _stopFn = stopFn ?? (() async {
      final target = _nativePlayer;
      if (target == null) return;
      FastAudioService.instance.releaseAudioFocusFor(target);
      await target.stop();
      if (target.playing) throw StateError('Radio stop was not confirmed');
    });
  }
  late final Future<bool> Function(String url,
      Future<void> Function()? onStopCallback) _playFn;
  late final Future<void> Function() _stopFn;
  AudioPlayer? _nativePlayer;
  StreamSubscription<PlaybackEvent>? _nativeSub;
  final StreamController<Object> _errors = StreamController<Object>.broadcast();
  bool _ownsPlayback = false;
  bool _disposed = false;
  int _pendingStarts = 0;
  int _generation = 0;
  Future<void> _stopTail = Future.value();

  Future<void> _stopOwned() {
    final run = _stopTail.then((_) => _stopFn());
    _stopTail = run.catchError((_) {});
    return run;
  }

  @override
  Future<void> play(String url) async {
    if (_disposed) return;
    final gen = ++_generation;
    _pendingStarts++;
    try {
      // A native stop already in flight must settle before a newer start can
      // load or play on this same target. Failure stays retryable.
      await _stopTail;
      if (_disposed || gen != _generation) return;
      final ok = await _playFn(url, () async {
        if (gen != _generation) return;
        _ownsPlayback = false;
        if (!_errors.isClosed) _errors.add(const RadioStoppedExternally());
      });
      if (_disposed) {
        // This stop can touch only our own target, never the new focus owner.
        return;
      }
      if (gen != _generation) return;
      if (!ok) throw StateError('audio focus claim or play rejected');
      _ownsPlayback = true;
    } finally {
      _pendingStarts--;
      if (_disposed && _pendingStarts == 0) await _cleanup();
    }
  }

  @override
  Future<void> stop() async {
    ++_generation;
    await _stopOwned();
    _ownsPlayback = false;
  }

  Future<void> _cleanup() async {
    try {
      await _stopOwned();
      _ownsPlayback = false;
      if (_pendingStarts == 0) {
        await _nativeSub?.cancel();
        _nativeSub = null;
        await _nativePlayer?.dispose();
        _nativePlayer = null;
      }
    } catch (_) {
      // Keep the sounding target registered with the central service. A
      // later focus claim must still stop and confirm it before playing.
      // Disposal cannot throw into an already removed widget.
    }
  }

  @override
  Stream<Object> get errors => _errors.stream;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    if (_ownsPlayback || _pendingStarts > 0 || _nativePlayer != null) {
      unawaited(_cleanup());
    }
    _errors.close();
  }
}

const String kFavoritesCategoryId = 'favorites';
const String _favKey = 'curated_radio_favorites';
const String _legacyFavKey = 'islamic_radio_favorites';

/// Migration from the previous radio screen's slug ids. A slug maps only when
/// its old stream URL is byte-identical to a curated station's URL; slugs with
/// no exact URL match stay in the legacy key, untouched and unlost.
const Map<String, String> _legacyFavoriteIds = {
  'radio_general_recitations': '9587fbe3dc',
  'radio_minshawi': '54811ff480',
  'radio_abdulbasit': 'a4fc2a350a',
  'radio_tablaway': '627547eb2f',
  'radio_banna': '17275d77b6',
  'radio_alafasi': '881759d51e',
  'radio_almuaiqly': '488270ce0c',
  'radio_fares_abbad': '92af772b75',
  'radio_salah_albudair': '30f39aa7e0',
  'radio_nasser_alqatami': '5bc099db03',
  'radio_dosari': '8e1a9a197a',
  'radio_khalifa_altunaiji': 'aa99a281d6',
  'radio_hani_arrifai': 'd4deb34582',
  'radio_tafseer_general': 'fabaec3a55',
  'radio_mukhtasar_tafsir': '39a499d92a',
  'radio_fatwa_general': '84c14455d4',
  'radio_athkar_sabah': '854049c024',
  'radio_athkar_masa': '81e19127e3',
  'radio_eid_takbeerat': '245965b8c7',
  'radio_khushoo_salma': 'a1ccc56644',
  'radio_tarateel_fajr': '56a21ee5c2',
  // Same operator (qurango.net, incl. its backup. mirror host) and an
  // identical stream path: established identity, still never a guessed name.
  'radio_mustafa_ismail': '30caa9c075',
  'radio_sudais': '9b6f1ee823',
  'radio_shuraim': 'b4f8eac737',
  'radio_ajmy': '8735faa1ff',
  'radio_shatri': '34786c33c2',
  'radio_abkr': 'e557b81aa6',
  'radio_albaqarah_continuous': 'f014ae468f',
};

/// Previous-screen stations with no grounded replacement in the curated
/// catalog. A legacy favorite for one of these slugs stays visible and
/// playable from the favorites category instead of vanishing.
const Map<String, (String, String)> _legacyStationInfo = {
  'radio_cairo_live': ('إذاعة القرآن الكريم من القاهرة', 'https://service.webvideocore.net/CL1olYogIrDWvwqiIKK7eCxOS4PStqG9DuEjAr2ZjZQtvS3d4y9r0cvRhvS17SGN/a_7a4vuubc6mo8.m3u8'),
  'radio_husary': ('إذاعة الشيخ محمود خليل الحصري', 'https://qurango.net/radio/mahmoud_khalil_alhussary_mojawwad'),
  'radio_ali_jaber': ('إذاعة الشيخ علي جابر', 'https://backup.qurango.net/radio/ali_jaber'),
  'radio_abdullah_aljohany': ('إذاعة الشيخ عبد الله عواد الجهني', 'https://backup.qurango.net/radio/abdullah_aljohany'),
  'radio_hazza_albalushi': ('إذاعة الشيخ هزاع البلوشي', 'https://backup.qurango.net/radio/hazza'),
  'radio_abdulmohsen_alqasim': ('إذاعة الشيخ عبد المحسن القاسم', 'https://backup.qurango.net/radio/abdulmohsen_alqasim'),
  'radio_saheh_bokharee': ('إذاعة صحيح البخاري الشريف', 'https://backup.qurango.net/radio/saheh-bokharee'),
  'radio_saheh_muslim': ('إذاعة صحيح مسلم', 'https://backup.qurango.net/radio/saheh-muslim'),
  'radio_riyad_salihin': ('إذاعة رياض الصالحين', 'https://backup.qurango.net/radio/riyad'),
  'radio_alanbiya': ('إذاعة قصص الأنبياء والمرسلين', 'https://backup.qurango.net/radio/alanbiya'),
  'radio_shmaeel': ('إذاعة الشمائل المحمدية', 'https://backup.qurango.net/radio/shmaeel'),
  'radio_tabari_tafsir': ('إذاعة تفسير الإمام الطبري', 'https://backup.qurango.net/radio/tabri'),
  'radio_gareeb_quran': ('إذاعة غريب القرآن ومفرداته', 'https://backup.qurango.net/radio/gareeb-quran'),
  'radio_roqiah_sharaiyah': ('إذاعة الرقية الشرعية الشاملة', 'https://backup.qurango.net/radio/roqiah'),
  'radio_almulk_continuous': ('إذاعة سورة الملك المانعة', 'https://qurango.net/radio/Surah_Al-Mulk'),
};

class _RadioController extends ChangeNotifier {
  _RadioController(this.player) {
    _errSub = player.errors.listen((Object e) {
      if (_disposed) return;
      if (playingId != null) {
        playingId = null;
        loading = false;
        failed = e is! RadioStoppedExternally;
        _safeNotify();
      }
    });
  }
  final CuratedRadioPlayer player;
  late final StreamSubscription<Object> _errSub;
  String? playingId;
  bool failed = false;
  bool loading = false;
  bool favSaveFailed = false;
  final Set<String> favorites = {};
  final List<CuratedStation> legacyStations = [];
  List<String> _legacySlugs = const [];
  bool _disposed = false;
  int _playGen = 0;
  Future<void> _favQueue = Future.value();
  List<String> _legacyPending = const [];
  bool _legacyImported = false;

  // Every state publication goes through this guard: a widget that left the
  // tree during a pending play must never be notified after dispose.
  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    favorites
      ..clear()
      ..addAll(prefs.getStringList(_favKey) ?? const []);
    _legacyPending = prefs.getStringList(_legacyFavKey) ?? const [];
    _legacySlugs = _legacyPending;
    legacyStations
      ..clear()
      ..addAll(_legacySlugs
          .where((slug) => !_legacyFavoriteIds.containsKey(slug))
          .where(_legacyStationInfo.containsKey)
          .map((slug) => CuratedStation(
              'legacy:$slug', _legacyStationInfo[slug]!.$1, _legacyStationInfo[slug]!.$2)));
    _safeNotify();
  }

  /// One-time import of ids saved by the previous radio screen, through the
  /// exact-URL slug mapping. Unmapped slugs stay only in the legacy key,
  /// which is never deleted.
  Future<void> importLegacyFavorites() async {
    if (_legacyImported) return;
    _legacyImported = true;
    final toAdd = _legacyPending
        .map((slug) => _legacyFavoriteIds[slug])
        .whereType<String>()
        .where((id) => !favorites.contains(id))
        .toList();
    _legacyPending = const [];
    if (toAdd.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final ok = await prefs.setStringList(_favKey, [...favorites, ...toAdd]);
    if (_disposed) return;
    if (ok) favorites.addAll(toAdd);
    _safeNotify();
  }

  /// Serializes presses so rapid taps cannot interleave preference writes,
  /// and publishes the new favorite only after the store accepted it.
  Future<void> toggleFavorite(String id) {
    final run = _favQueue.then((_) => _saveFavoriteSafely(() => _toggleFavoriteNow(id)));
    _favQueue = run.catchError((_) {});
    return run;
  }

  Future<void> _saveFavoriteSafely(Future<void> Function() write) async {
    try {
      await write();
    } catch (_) {
      if (_disposed) return;
      favSaveFailed = true;
      _safeNotify();
    }
  }

  /// Removes a legacy favorite at the user's explicit tap (write-first).
  Future<void> toggleLegacyFavorite(CuratedStation s) {
    final run = _favQueue.then((_) => _saveFavoriteSafely(() => _toggleLegacyNow(s)));
    _favQueue = run.catchError((_) {});
    return run;
  }

  Future<void> _toggleLegacyNow(CuratedStation s) async {
    if (_disposed) return;
    final slug = s.id.substring('legacy:'.length);
    final prefs = await SharedPreferences.getInstance();
    final next = (prefs.getStringList(_legacyFavKey) ?? const <String>[])
        .where((e) => e != slug)
        .toList();
    final ok = await prefs.setStringList(_legacyFavKey, next);
    if (_disposed) return;
    if (ok) {
      legacyStations.removeWhere((e) => e.id == s.id);
      favSaveFailed = false;
    } else {
      favSaveFailed = true;
    }
    _safeNotify();
  }

  Future<void> _toggleFavoriteNow(String id) async {
    if (_disposed) return;
    final next = {...favorites};
    final removed = next.remove(id);
    if (!removed) next.add(id);
    final prefs = await SharedPreferences.getInstance();
    if (removed) {
      // This explicit removal applies to the user's old selection too.
      // Remove its source slugs before the new favorite write. If that later
      // write fails, the still-saved curated favorite remains visible/retryable.
      final slugs = _legacyFavoriteIds.entries
          .where((entry) => entry.value == id).map((entry) => entry.key).toSet();
      final old = prefs.getStringList(_legacyFavKey) ?? const <String>[];
      if (old.any(slugs.contains)) {
        final accepted = await prefs.setStringList(_legacyFavKey,
            old.where((slug) => !slugs.contains(slug)).toList());
        if (!accepted) {
          if (!_disposed) { favSaveFailed = true; _safeNotify(); }
          return;
        }
      }
    }
    final ok = await prefs.setStringList(_favKey, next.toList());
    if (_disposed) return;
    if (ok) {
      favorites
        ..clear()
        ..addAll(next);
      favSaveFailed = false;
    } else {
      favSaveFailed = true;
    }
    _safeNotify();
  }

  Future<void> toggle(CuratedStation s) async {
    // Rapid presses settle on the last press; stale completions do nothing.
    final gen = ++_playGen;
    if (playingId == s.id) {
      loading = true;
      failed = false;
      _safeNotify();
      try {
        await player.stop();
        if (_disposed || gen != _playGen) return;
        playingId = null;
      } catch (_) {
        if (_disposed || gen != _playGen) return;
        // A failed physical stop is not silence. Keep the station and its
        // stop control so the user can retry without starting another play.
        failed = true;
      }
      loading = false;
      _safeNotify();
      return;
    }
    playingId = s.id;
    failed = false;
    loading = true;
    _safeNotify();
    try {
      await player.play(s.url);
      if (_disposed || gen != _playGen) return;
      if (playingId == s.id) {
        loading = false;
        _safeNotify();
      }
    } catch (_) {
      if (_disposed || gen != _playGen) return;
      if (playingId == s.id) {
        playingId = null;
        failed = true;
        loading = false;
      }
      _safeNotify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _errSub.cancel();
    player.dispose();
    super.dispose();
  }
}

class CuratedRadioScreen extends StatefulWidget {
  final CuratedRadioPlayer Function()? playerFactory;
  final AssetBundle? bundle;
  const CuratedRadioScreen({super.key, this.playerFactory, this.bundle});

  @override
  State<CuratedRadioScreen> createState() => _CuratedRadioScreenState();
}

class _CuratedRadioScreenState extends State<CuratedRadioScreen> {
  late final _RadioController _c =
      _RadioController((widget.playerFactory ?? FastAudioRadioPlayer.new)());
  late Future<List<CuratedCategory>> _future = loadCuratedCategories(bundle: widget.bundle);

  @override
  void initState() {
    super.initState();
    _c.loadFavorites();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الإذاعة')),
        body: FutureBuilder<List<CuratedCategory>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator(semanticsLabel: 'تحميل الإذاعات'));
            }
            if (snap.hasError || snap.data == null) {
              return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('تعذر تحميل قائمة الإذاعات.'),
                  TextButton(
                    onPressed: () => setState(() => _future = loadCuratedCategories(bundle: widget.bundle)),
                    child: const Text('إعادة المحاولة'),
                  ),
                ]),
              );
            }
            final cats = snap.data!;
            _c.importLegacyFavorites();
            return AnimatedBuilder(
              animation: _c,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: ListTile(
                      key: const Key('curated_radio_cat_favorites'),
                      title: const Text('المفضلة'),
                      trailing: Text('${_c.favorites.length}'),
                      onTap: () => _open(context, cats, null),
                    ),
                  ),
                  for (final cat in cats)
                    Card(
                      child: ListTile(
                        key: Key('curated_radio_cat_${cat.id}'),
                        title: Text(cat.title),
                        trailing: Text('${cat.stations.length}'),
                        onTap: () => _open(context, cats, cat),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _open(BuildContext context, List<CuratedCategory> cats, CuratedCategory? cat) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _StationsScreen(controller: _c, all: cats, category: cat),
    ));
  }
}

class _StationsScreen extends StatelessWidget {
  final _RadioController controller;
  final List<CuratedCategory> all;
  final CuratedCategory? category; // null = favorites
  const _StationsScreen({required this.controller, required this.all, required this.category});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(category?.title ?? 'المفضلة')),
        body: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final stations = category != null
                ? category!.stations
                : [
                    for (final c in all)
                      for (final s in c.stations)
                        if (controller.favorites.contains(s.id)) s,
                    ...controller.legacyStations,
                  ];
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (controller.failed)
                  const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('تعذر التشغيل')),
                if (controller.favSaveFailed)
                  const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('تعذر حفظ المفضلة')),
                if (stations.isEmpty) const Text('لا توجد إذاعات مفضلة.'),
                for (final s in stations) _row(s),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _row(CuratedStation s) {
    final playing = controller.playingId == s.id;
    final isLegacy = s.id.startsWith('legacy:');
    final fav = isLegacy || controller.favorites.contains(s.id);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(child: Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold))),
          IconButton(
            key: Key('curated_radio_fav_${s.id}'),
            tooltip: fav ? 'إزالة ${s.name} من المفضلة' : 'إضافة ${s.name} إلى المفضلة',
            onPressed: () => isLegacy
                ? controller.toggleLegacyFavorite(s)
                : controller.toggleFavorite(s.id),
            icon: Icon(fav ? Icons.star : Icons.star_border),
          ),
          Semantics(
            key: Key('curated_radio_${s.id}'),
            button: true,
            label: playing ? 'إيقاف ${s.name}' : 'تشغيل ${s.name}',
            excludeSemantics: true,
            onTap: () => controller.toggle(s),
            child: FilledButton(
              onPressed: () => controller.toggle(s),
              child: Text(playing ? (controller.loading ? 'جار التحميل' : 'إيقاف') : 'تشغيل'),
            ),
          ),
        ]),
      ),
    );
  }
}
