import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../../core/audio/fast_audio_service.dart';
import '../../core/models/islamic_radio.dart';
import '../../core/services/islamic_radio_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/app_theme.dart';

/// شاشة الإذاعات الإسلامية والبث المباشر (راديو القرآن الكريم والعالم الإسلامي)
class IslamicRadioScreen extends StatefulWidget {
  final IslamicRadioCategoryType initialCategory;
  final Stream<PlayerState>? playerStateStreamOverride;

  const IslamicRadioScreen({
    super.key,
    this.initialCategory = IslamicRadioCategoryType.all,
    this.playerStateStreamOverride,
  });

  @override
  State<IslamicRadioScreen> createState() => _IslamicRadioScreenState();
}

class _IslamicRadioScreenState extends State<IslamicRadioScreen>
    with SingleTickerProviderStateMixin {
  final IslamicRadioService _radioService = IslamicRadioService.instance;
  final FastAudioService _audioService = FastAudioService.instance;

  late IslamicRadioCategoryType _selectedCategory;
  String _searchQuery = '';
  bool _favoritesOnly = false;
  IslamicRadioStation? _currentStation;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _isRadioActive = false;
  StreamSubscription? _playerStateSubscription;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory;
    _radioService.init();

    // الاستماع لحالة مشغل الصوت المركزي مع التأكد من ملكية الجلسة للإذاعة
    final stream = widget.playerStateStreamOverride ?? _audioService.playerStateStream;
    _playerStateSubscription = stream.listen((state) {
      if (!mounted) return;
      // لا يتم وسم الإذاعة بالتشغيل إذا كان المشغل يعزف مقطعاً من خدمة أو شاشة أخرى
      if (_currentStation == null || !_isRadioActive) {
        if (_isPlaying || _isBuffering) {
          setState(() {
            _isPlaying = false;
            _isBuffering = false;
          });
        }
        return;
      }
      setState(() {
        if (state.processingState == ProcessingState.idle) {
          // B injectidle duringBconnecting thenbuffering->ready; assertBcard+miniplayer survive, realidleafterplayingclears.
          if (!_isBuffering && !state.playing) {
            _isPlaying = false;
            _isBuffering = false;
            _isRadioActive = false;
            _currentStation = null;
          }
        } else if (state.processingState == ProcessingState.completed) {
          if (!state.playing) {
            _isPlaying = false;
            _isBuffering = false;
            _isRadioActive = false;
            _currentStation = null;
          }
        } else if (state.processingState == ProcessingState.buffering ||
            state.processingState == ProcessingState.loading) {
          _isBuffering = true;
          _isPlaying = state.playing;
        } else if (state.processingState == ProcessingState.ready) {
          _isBuffering = false;
          _isPlaying = state.playing;
        }
      });
    });
  }

  @override
  void dispose() {
    _activeSessionToken++;
    _playerStateSubscription?.cancel();
    _searchController.dispose();
    if (_isPlaying || _isBuffering) {
      _isRadioActive = false;
      _audioService.stop();
    }
    super.dispose();
  }

  int _activeSessionToken = 0;

  /// تشغيل أو إيقاف المحطة الإذاعية مع حراسة التزامن برمز الجلسة التصاعدي
  Future<void> _toggleStation(IslamicRadioStation station) async {
    final currentSession = ++_activeSessionToken;
    final isSameStation = _currentStation?.id == station.id;

    // النقر المتكرر أثناء التشغيل أو جاري الاتصال (Buffering) يلغي الاتصال ويوقف البث فوراً
    if (isSameStation && (_isPlaying || _isBuffering)) {
      _isRadioActive = false;
      await _audioService.stop();
      if (mounted && currentSession == _activeSessionToken) {
        setState(() {
          _isPlaying = false;
          _isBuffering = false;
          _currentStation = null;
        });
      }
      return;
    }

    setState(() {
      _currentStation = station;
      _isBuffering = true;
      _isRadioActive = true;
    });

    final ok = await _audioService.playLiveRadio(
      primaryUrl: station.streamUrl,
      fallbackUrls: station.fallbackUrls,
      cacheKey: 'live_radio_${station.id}',
      onStopCallback: () async {
        if (mounted && currentSession == _activeSessionToken) {
          setState(() {
            _isRadioActive = false;
            _isPlaying = false;
            _isBuffering = false;
            _currentStation = null;
          });
        }
      },
    );

    if (!mounted || currentSession != _activeSessionToken) return;

    setState(() {
      _isBuffering = false;
      _isPlaying = ok;
      _isRadioActive = ok;
      _currentStation = ok ? station : null;
    });

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              ok ? Icons.radio_rounded : Icons.error_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                ok
                    ? 'جاري الاستماع: ${station.name}'
                    : 'تعذر تشغيل إذاعة ${station.name} حالياً',
                style: const TextStyle(fontFamily: 'Amiri', fontSize: 14),
              ),
            ),
          ],
        ),
        backgroundColor: ok ? AppColors.primaryGreen : Colors.redAccent,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  /// إظهار شريط التحكم بمستوى الصوت
  void _showVolumeDialog() {
    double currentVolume = _audioService.player.volume;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCard : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      Icon(Icons.volume_up_rounded, color: AppColors.primaryGreen),
                      SizedBox(width: 8),
                      Text(
                        'مستوى صوت الإذاعة',
                        style: TextStyle(
                          fontFamily: 'Amiri',
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          currentVolume == 0
                              ? Icons.volume_off_rounded
                              : Icons.volume_down_rounded,
                          color: AppColors.primaryGreen,
                        ),
                        onPressed: () {
                          setModalState(() => currentVolume = 0.0);
                          _audioService.player.setVolume(0.0);
                        },
                      ),
                      Expanded(
                        child: Slider(
                          value: currentVolume,
                          min: 0.0,
                          max: 1.0,
                          activeColor: AppColors.primaryGreen,
                          inactiveColor: AppColors.primaryGreen.withValues(alpha: 0.2),
                          onChanged: (val) {
                            setModalState(() => currentVolume = val);
                            _audioService.player.setVolume(val);
                          },
                        ),
                      ),
                      Text(
                        '${(currentVolume * 100).round()}%',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stations = _radioService.getStations(
      category: _selectedCategory,
      query: _searchQuery,
      favoritesOnly: _favoritesOnly,
    );

    final cairoStation = IslamicRadioService.defaultStations.firstWhere(
      (s) => s.id == 'radio_cairo_live',
    );

    return Directionality(
      textDirection: SettingsService.instance.textDirection,
      child: Scaffold(
        backgroundColor: isDark ? AppTheme.darkBg : const Color(0xFFF9F7F2),
        appBar: AppBar(
          backgroundColor: AppColors.primaryGreen,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Row(
            children: [
              ExcludeSemantics(child: Icon(Icons.radio_rounded, size: 20, color: Colors.white)),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'إذاعات القرآن الكريم',
                  style: TextStyle(
                    fontFamily: 'Amiri',
                    fontWeight: FontWeight.bold,
                    fontSize: 19,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(
                _favoritesOnly ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: _favoritesOnly ? Colors.amberAccent : Colors.white,
              ),
              tooltip: _favoritesOnly ? 'عرض الكل' : 'المفضلة فقط',
              onPressed: () {
                setState(() {
                  _favoritesOnly = !_favoritesOnly;
                });
              },
            ),
          ],
        ),
        body: Column(
          children: [
            // شريط البحث والفلترة السريعة
            _buildSearchAndFilterBar(isDark),

            // تصنيفات الإذاعات (Chips أفقية)
            _buildCategoriesBar(isDark),

            // قائمة الإذاعات
            Expanded(
              child: stations.isEmpty
                  ? _buildEmptyState(isDark)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 90),
                      children: [
                        // بطاقة إذاعة القرآن الكريم من القاهرة المميزة (إذا لم يكن هناك فلتر بحث مخصص)
                        if (_searchQuery.isEmpty &&
                            !_favoritesOnly &&
                            (_selectedCategory == IslamicRadioCategoryType.all ||
                                _selectedCategory == IslamicRadioCategoryType.generalLive)) ...[
                          _buildCairoFeaturedCard(cairoStation, isDark),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Container(
                                width: 4,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: AppColors.primaryGreen,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'باقة الإذاعات المختارة (${stations.length})',
                                  style: TextStyle(
                                    fontFamily: 'Amiri',
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white70 : Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                        ],

                        // بطاقات الإذاعات
                        ...stations.map((station) {
                          // تجنب تكرار إذاعة القاهرة في الصفحة الأولى العامة
                          if (_searchQuery.isEmpty &&
                              !_favoritesOnly &&
                              _selectedCategory == IslamicRadioCategoryType.all &&
                              station.id == 'radio_cairo_live') {
                            return const SizedBox.shrink();
                          }
                          return _buildStationCard(station, isDark);
                        }),
                      ],
                    ),
            ),
          ],
        ),

        // شريط التشغيل المباشر العائم بالأسفل
        bottomSheet: _currentStation != null
            ? _buildBottomMiniPlayer(_currentStation!, isDark)
            : null,
      ),
    );
  }

  /// شريط البحث وزر المفضلة
  Widget _buildSearchAndFilterBar(bool isDark) {
    return Container(
      color: AppColors.primaryGreen,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: TextField(
          key: const Key('quran_radio_search'),
          controller: _searchController,
          onChanged: (val) {
            setState(() {
              _searchQuery = val;
            });
          },
          decoration: InputDecoration(
            labelText: 'ابحث عن إذاعة أو قارئ أو سورة...',
            floatingLabelBehavior: FloatingLabelBehavior.never,
            labelStyle: TextStyle(
              fontFamily: 'Amiri',
              fontSize: 13.5,
              color: isDark ? Colors.white38 : Colors.grey.shade500,
            ),
            prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primaryGreen, size: 22),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _searchQuery = '';
                      });
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          ),
        ),
      ),
    );
  }

  /// شريط تصنيفات الإذاعات
  Widget _buildCategoriesBar(bool isDark) {
    return Container(
      height: 48,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: IslamicRadioService.categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final cat = IslamicRadioService.categories[index];
          final isSelected = _selectedCategory == cat.type;

          return ChoiceChip(
            tooltip: cat.title,
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  cat.icon,
                  size: 16,
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Colors.white70 : AppColors.primaryGreen),
                ),
                const SizedBox(width: 6),
                Text(
                  cat.title,
                  style: TextStyle(
                    fontFamily: 'Amiri',
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected
                        ? Colors.white
                        : (isDark ? Colors.white70 : Colors.black87),
                  ),
                ),
              ],
            ),
            selected: isSelected,
            selectedColor: AppColors.primaryGreen,
            backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
            elevation: isSelected ? 1 : 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: isSelected
                    ? AppColors.primaryGreen
                    : (isDark ? Colors.white12 : Colors.grey.shade300),
              ),
            ),
            onSelected: (val) {
              if (val) {
                setState(() {
                  _selectedCategory = cat.type;
                });
              }
            },
          );
        },
      ),
    );
  }

  /// البطاقة المميزة لإذاعة القرآن الكريم من القاهرة
  Widget _buildCairoFeaturedCard(IslamicRadioStation station, bool isDark) {
    final isThisPlaying = _currentStation?.id == station.id && _isPlaying;
    final isThisBuffering = _currentStation?.id == station.id && _isBuffering;
    final isAndroid = station.streamUrl.contains('8s5u5tpdtwzuv') &&
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF0F382A), const Color(0xFF142B22)]
              : [const Color(0xFF0F5B45), const Color(0xFF167257)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F5B45).withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // خلفية زخرفية ناعمة
          Positioned(
            left: -15,
            bottom: -20,
            child: Icon(
              Icons.radio_rounded,
              size: 130,
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // شارة ترحيل الإنترنت وتنبيه أندرويد
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isAndroid ? Colors.grey.shade700 : AppColors.primaryGreen,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isAndroid ? 'غير مدعوم على أندرويد' : 'بث إذاعي',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'الموقع الرسمي',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ),
                    AnimatedBuilder(
                      animation: _radioService,
                      builder: (context, _) {
                        final isFav = _radioService.isFavorite(station.id);
                        return Semantics(
                          label: isFav
                              ? 'إزالة ${station.name} من المفضلة'
                              : 'إضافة ${station.name} إلى المفضلة',
                          button: true,
                          child: IconButton(
                            icon: Icon(
                              isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                              color: isFav ? Colors.amberAccent : Colors.white70,
                            ),
                            tooltip: isFav
                                ? 'إزالة ${station.name} من المفضلة'
                                : 'إضافة ${station.name} إلى المفضلة',
                            onPressed: () => _radioService.toggleFavorite(station.id),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // عنوان الإذاعة
                const Text(
                  'إذاعة القرآن الكريم من القاهرة',
                  style: TextStyle(
                    fontFamily: 'Amiri',
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),

                // الوصف
                Text(
                  station.subtitle,
                  style: TextStyle(
                    fontFamily: 'Amiri',
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.85),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),

                // زر التشغيل والتحكم
                Row(
                  children: [
                    Semantics(
                      label: isAndroid
                          ? 'إذاعة القرآن الكريم من القاهرة غير مدعومة على أندرويد لعدم التشفير'
                          : (isThisBuffering
                              ? 'جاري الاتصال بإذاعة ${station.name}'
                              : (isThisPlaying ? 'إيقاف ${station.name}' : 'تشغيل ${station.name}')),
                      button: !isAndroid,
                      liveRegion: isThisBuffering || isThisPlaying,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isAndroid
                              ? Colors.grey.shade400
                              : (isThisPlaying ? Colors.amberAccent : Colors.white),
                          foregroundColor: isAndroid
                              ? Colors.grey.shade800
                              : (isThisPlaying ? Colors.black87 : AppColors.primaryGreen),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        onPressed: isAndroid ? null : () => _toggleStation(station),
                        icon: isAndroid
                            ? const Icon(Icons.block_rounded, size: 20)
                            : (isThisBuffering
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryGreen),
                                    ),
                                  )
                                : Icon(
                                    isThisPlaying
                                        ? Icons.pause_circle_filled_rounded
                                        : Icons.play_arrow_rounded,
                                    size: 22,
                                  )),
                        label: Text(
                          isAndroid
                              ? 'غير مدعوم على أندرويد (غير مشفر)'
                              : (isThisBuffering
                                  ? 'جاري الاتصال بالبث...'
                                  : (isThisPlaying ? 'إيقاف مؤقت' : 'استماع للبث')),
                          style: const TextStyle(
                            fontFamily: 'Amiri',
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (isThisPlaying)
                      IconButton(
                        icon: const Icon(Icons.volume_up_rounded, color: Colors.white),
                        tooltip: 'مستوى الصوت',
                        onPressed: _showVolumeDialog,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _originLabel(IslamicRadioStation station) => station.countryOrOrigin
      .replaceAll(RegExp(r'[\u{1F1E6}-\u{1F1FF}\u{1F300}-\u{1FAFF}\u{FE0F}]', unicode: true), '')
      .trim();

  /// بطاقة محطة إذاعية عادية
  Widget _buildStationCard(IslamicRadioStation station, bool isDark) {
    final isThisPlaying = _currentStation?.id == station.id && _isPlaying;
    final isThisBuffering = _currentStation?.id == station.id && _isBuffering;
    final isCairoUnsupported = station.streamUrl.contains('8s5u5tpdtwzuv') &&
        (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isThisPlaying
              ? AppColors.primaryGreen
              : (isDark ? Colors.white12 : Colors.grey.shade200),
          width: isThisPlaying ? 1.5 : 1,
        ),
      ),
      color: isDark ? AppTheme.darkCard : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // أيقونة الإذاعة مع التدرج اللوني
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    station.accentColor,
                    station.accentColor.withValues(alpha: 0.75),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isThisPlaying ? Icons.graphic_eq_rounded : station.icon,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),

            // التفاصيل (منطقة نقر مستقلة دلالياً)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: isCairoUnsupported ? null : () => _toggleStation(station),
                child: Semantics(
                  label: isCairoUnsupported
                      ? '${station.name}، غير متاح على أجهزة أندرويد لعدم التشفير'
                      : '${station.name}، ${station.categoryName}، ${_originLabel(station)}',
                  hint: isCairoUnsupported
                      ? 'غير مدعوم على أندرويد'
                      : (isThisPlaying ? 'انقر لإيقاف البث' : 'انقر لبدء الاستماع'),
                  button: !isCairoUnsupported,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            station.name,
                            style: TextStyle(
                              fontFamily: 'Amiri',
                              fontSize: 15.5,
                              fontWeight: FontWeight.bold,
                              color: isThisPlaying
                                  ? AppColors.primaryGreen
                                  : (isDark ? Colors.white : Colors.black87),
                            ),
                            softWrap: true,
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
              _originLabel(station),
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        station.subtitle,
                        style: TextStyle(
                          fontFamily: 'Amiri',
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.grey.shade600,
                          height: 1.3,
                        ),
                        softWrap: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // أزرار المفضلة والتشغيل (مستقلة بدون تداخل أزرار في شجرة الدلالات)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _radioService,
                  builder: (context, _) {
                    final isFav = _radioService.isFavorite(station.id);
                    return Semantics(
                      label: isFav
                          ? 'إزالة ${station.name} من المفضلة'
                          : 'إضافة ${station.name} إلى المفضلة',
                      button: true,
                      child: IconButton(
                        iconSize: 20,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        tooltip: isFav
                            ? 'إزالة ${station.name} من المفضلة'
                            : 'إضافة ${station.name} إلى المفضلة',
                        icon: Icon(
                          isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: isFav ? Colors.redAccent : Colors.grey.shade400,
                        ),
                        onPressed: () => _radioService.toggleFavorite(station.id),
                      ),
                    );
                  },
                ),
                Semantics(
                  label: isCairoUnsupported
                      ? '${station.name} غير متاح على أجهزة أندرويد لعدم التشفير'
                      : (isThisBuffering
                          ? 'جاري الاتصال بإذاعة ${station.name}'
                          : (isThisPlaying
                              ? 'إيقاف بث ${station.name}'
                              : 'تشغيل بث ${station.name}')),
                  button: !isCairoUnsupported,
                  liveRegion: isThisBuffering || isThisPlaying,
                  child: IconButton(
                    iconSize: 32,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    tooltip: isCairoUnsupported
                        ? 'غير مدعوم على أندرويد لعدم التشفير'
                        : (isThisPlaying
                            ? 'إيقاف بث ${station.name}'
                            : 'تشغيل بث ${station.name}'),
                    icon: isCairoUnsupported
                        ? const Icon(
                            Icons.block_rounded,
                            size: 24,
                            color: Colors.grey,
                          )
                        : (isThisBuffering
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryGreen),
                                ),
                              )
                            : Icon(
                                isThisPlaying
                                    ? Icons.pause_circle_filled_rounded
                                    : Icons.play_circle_fill_rounded,
                                color: isThisPlaying
                                    ? AppColors.accentGold
                                    : AppColors.primaryGreen,
                              )),
                    onPressed: isCairoUnsupported ? null : () => _toggleStation(station),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// شريط المشغل المباشر العائم بالأسفل
  Widget _buildBottomMiniPlayer(IslamicRadioStation station, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
        border: Border(
          top: BorderSide(
            color: AppColors.primaryGreen.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // مؤشر النبض المباشر
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: station.accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _isPlaying ? Icons.graphic_eq_rounded : Icons.radio_rounded,
                color: station.accentColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),

            // اسم الإذاعة
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _isPlaying ? Colors.redAccent : Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _isPlaying ? 'استماع متواصل' : 'متوقف مؤقتاً',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: _isPlaying ? AppColors.primaryGreen : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '• ${_originLabel(station)}',
                        style: const TextStyle(fontSize: 10.5, color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    station.name,
                    style: const TextStyle(
                      fontFamily: 'Amiri',
                      fontWeight: FontWeight.bold,
                      fontSize: 14.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // زر التحكم بمستوى الصوت
            IconButton(
              icon: const Icon(Icons.volume_up_rounded, size: 22),
              color: isDark ? Colors.white70 : Colors.black87,
              tooltip: 'مستوى الصوت',
              onPressed: _showVolumeDialog,
            ),

            // زر التشغيل والإيقاف
            IconButton(
              iconSize: 36,
              icon: _isBuffering
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryGreen),
                      ),
                    )
                  : Icon(
                      _isPlaying
                          ? Icons.pause_circle_filled_rounded
                          : Icons.play_circle_fill_rounded,
                      color: AppColors.primaryGreen,
                    ),
              onPressed: () => _toggleStation(station),
            ),

            // زر إغلاق الشريط
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              color: Colors.grey,
              tooltip: 'إيقاف وخروج',
              onPressed: () async {
                await _audioService.stop();
                if (mounted) {
                  setState(() {
                    _currentStation = null;
                    _isPlaying = false;
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /// واجهة عند عدم وجود نتائج
  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.radio_rounded,
              size: 64,
              color: isDark ? Colors.white24 : Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              _favoritesOnly
                  ? 'لم تقم بإضافة أي إذاعات للمفضلة بعد'
                  : 'لم يتم العثور على إذاعات مطابقة لبحثك',
              style: TextStyle(
                fontFamily: 'Amiri',
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _favoritesOnly
                  ? 'اضغط على رمز القلب بجوار أي إذاعة لإضافتها هنا'
                  : 'جرب البحث بكلمة أخرى مثل (القاهرة، المنشاوي، الحصري، البقرة...)',
              style: TextStyle(
                fontFamily: 'Amiri',
                fontSize: 13,
                color: isDark ? Colors.white38 : Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
