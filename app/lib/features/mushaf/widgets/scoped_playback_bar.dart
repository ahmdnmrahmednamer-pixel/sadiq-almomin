import 'package:flutter/material.dart';
import '../../../core/audio/ayah_audio_player.dart';
import '../../../core/services/settings_service.dart';
import '../../settings/widgets/settings_reciter_modal.dart';

/// Playback for the opened surah, page or juz with the selected reciter.
/// Independent of single-ayah play: tapping one ayah leaves this scope.
class ScopedPlaybackBar extends StatefulWidget {
  /// Ayah keys ("surah:ayah") of the opened surah, page or juz, in order.
  final List<String> keys;
  /// Short scope name used in labels, e.g. "السورة", "الصفحة", "الجزء".
  final String scopeName;
  /// Other scopes the listener can switch to (name -> keys), e.g. the juz.
  final Map<String, List<String>> alternates;
  const ScopedPlaybackBar({super.key, required this.keys, this.scopeName = 'السورة', this.alternates = const {}});

  @override
  State<ScopedPlaybackBar> createState() => _ScopedPlaybackBarState();
}

class _ScopedPlaybackBarState extends State<ScopedPlaybackBar> {
  int _scopeIndex = 0;
  List<MapEntry<String, List<String>>> get _scopes => [
        MapEntry(widget.scopeName, widget.keys),
        ...widget.alternates.entries.where((e) => e.value.isNotEmpty),
      ];
  String get _name => _scopes[_scopeIndex.clamp(0, _scopes.length - 1)].key;
  List<String> get _keys => _scopes[_scopeIndex.clamp(0, _scopes.length - 1)].value;
  bool _repeat = false;
  int _count = 3;
  static const int _maxCount = 20;

  AyahAudioPlayer get _p => AyahAudioPlayer.instance;
  int get _passes => _repeat ? _count : 1;

  bool get _ownsScope {
    final s = _p.activeScope;
    return s != null && s.length == _keys.length && s.first == _keys.first && s.last == _keys.last;
  }

  Future<void> _playPause() async {
    if (_p.scopedActive.value && _ownsScope) {
      await _p.togglePause();
    } else {
      await _p.playScope(context, _keys, passes: _passes);
    }
    if (mounted) setState(() {});
  }

  void _applyPasses() {
    if (_p.scopedActive.value && _ownsScope) _p.setScopePasses(_passes);
  }

  @override
  Widget build(BuildContext context) {
    final reciter = SettingsService.instance.currentReciter;
    return SafeArea(
      top: false,
      child: Material(
        elevation: 8,
        color: Theme.of(context).colorScheme.surface,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: AnimatedBuilder(
            animation: Listenable.merge([_p.scopedActive, _p.isPlaying, _p.currentPlayingKey]),
            builder: (context, _) {
              final active = _p.scopedActive.value && _ownsScope;
              final playing = active && _p.isPlaying.value;
              final playLabel = playing
                  ? 'إيقاف مؤقت'
                  : (active ? 'استئناف' : 'تشغيل $_name');
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  children: [
                    IconButton(
                      key: const ValueKey('scoped-play-pause'),
                      tooltip: playLabel,
                      icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_fill, size: 36),
                      onPressed: _playPause,
                    ),
                    if (_scopes.length > 1)
                      PopupMenuButton<int>(
                        key: const ValueKey('scoped-scope'),
                        tooltip: 'نطاق التشغيل: $_name',
                        icon: const Icon(Icons.tune_rounded),
                        enabled: !active,
                        onSelected: (i) => setState(() => _scopeIndex = i),
                        itemBuilder: (_) => [
                          for (var i = 0; i < _scopes.length; i++)
                            CheckedPopupMenuItem<int>(
                              value: i,
                              checked: i == _scopeIndex,
                              child: Text(_scopes[i].key),
                            ),
                        ],
                      ),
                    IconButton(
                      key: const ValueKey('scoped-stop'),
                      tooltip: 'إيقاف',
                      icon: const Icon(Icons.stop_circle_outlined, size: 32),
                      onPressed: active ? () => _p.stop() : null,
                    ),
                    Semantics(
                      toggled: _repeat,
                      child: IconButton(
                        key: const ValueKey('scoped-repeat'),
                        tooltip: 'تكرار',
                        isSelected: _repeat,
                        icon: const Icon(Icons.repeat_rounded),
                        selectedIcon: const Icon(Icons.repeat_on_rounded),
                        onPressed: () {
                          setState(() => _repeat = !_repeat);
                          _applyPasses();
                        },
                      ),
                    ),
                    if (_repeat) ...[
                      IconButton(
                        key: const ValueKey('scoped-count-down'),
                        tooltip: 'إنقاص عدد التكرار',
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: _count > 2
                            ? () {
                                setState(() => _count--);
                                _applyPasses();
                              }
                            : null,
                      ),
                      Semantics(
                        label: 'عدد التكرار $_count',
                        excludeSemantics: true,
                        child: Text('$_count', key: const ValueKey('scoped-count'), style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      IconButton(
                        key: const ValueKey('scoped-count-up'),
                        tooltip: 'زيادة عدد التكرار',
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: _count < _maxCount
                            ? () {
                                setState(() => _count++);
                                _applyPasses();
                              }
                            : null,
                      ),
                    ],
                    IconButton(
                      key: const ValueKey('scoped-reciter'),
                      tooltip: 'القارئ: ${reciter.nameAr}',
                      icon: const Icon(Icons.record_voice_over_rounded),
                      onPressed: () => showSettingsReciterModal(context),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
