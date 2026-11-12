import 'package:flutter/material.dart';
import '../../../core/services/voice_search_service.dart';
import '../../../core/theme/app_theme.dart';

/// Modal Bottom Sheet for Quranic Voice Search through the device microphone.
class QuranVoiceSearchSheet extends StatefulWidget {
  const QuranVoiceSearchSheet({super.key});

  /// Displays the Voice Search Sheet and returns the recognized query string if confirmed.
  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const QuranVoiceSearchSheet(),
    );
  }

  @override
  State<QuranVoiceSearchSheet> createState() => _QuranVoiceSearchSheetState();
}

class _QuranVoiceSearchSheetState extends State<QuranVoiceSearchSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final VoiceSearchService _service = VoiceSearchService.instance;
  String _recognizedWords = '';
  double _soundLevel = 0.0;
  bool _isListening = false;
  String _statusMessage = 'جاري تجهيز الميكروفون...';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Auto-start listening on sheet open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startVoiceListening();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _service.cancelListening();
    super.dispose();
  }

  Future<void> _startVoiceListening() async {
    setState(() {
      _recognizedWords = '';
      _errorMessage = null;
      _isListening = true;
      _statusMessage = 'تحدث الآن، نستمع إليك...';
    });

    final initialized = await _service.initialize();
    if (!initialized && mounted) {
      setState(() {
        _isListening = false;
        _errorMessage = _service.errorMessage.isNotEmpty
            ? _service.errorMessage
            : 'تعذّر تشغيل خدمة التعرف الصوتي';
      });
      return;
    }

    if (!mounted) return;

    await _service.startListening(
      onResult: (words, isFinal) {
        if (!mounted) return;
        setState(() {
          _recognizedWords = words;
          if (isFinal) {
            _isListening = false;
            _statusMessage = 'تم التقاط الصوت بنجاح';
          } else {
            _statusMessage = 'جاري التقاط الكلمات...';
          }
        });
      },
      onSoundLevel: (level) {
        if (!mounted) return;
        setState(() {
          _soundLevel = level;
        });
      },
      onError: (err) {
        if (!mounted) return;
        setState(() {
          _isListening = false;
          _errorMessage = err;
        });
      },
    );
  }

  void _confirmAndSearch() {
    final query = _recognizedWords.trim();
    if (query.isNotEmpty) {
      _service.stopListening();
      Navigator.pop(context, query);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1B2420) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 28,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle Bar
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header Title
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.mic_rounded, color: AppColors.primaryGreen, size: 24),
                const SizedBox(width: 8),
                Text(
                  'البحث الصوتي في القرآن الكريم',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                    fontFamily: 'Cairo',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Subtitle / Status
            Text(
              _errorMessage ?? _statusMessage,
              style: TextStyle(
                fontSize: 13,
                color: _errorMessage != null
                    ? Colors.red.shade400
                    : (_isListening ? AppColors.accentGold : AppColors.secondaryGreen),
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Central Pulsating Mic Button
            GestureDetector(
              onTap: () {
                if (_isListening) {
                  _service.stopListening();
                  setState(() => _isListening = false);
                } else {
                  _startVoiceListening();
                }
              },
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  final soundBoost = (_soundLevel.clamp(0.0, 10.0) / 50.0);
                  final scale = _isListening ? (_pulseAnimation.value + soundBoost) : 1.0;
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: _isListening
                              ? [AppColors.accentGold, AppColors.primaryGreen]
                              : [AppColors.primaryGreen, AppColors.secondaryGreen],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (_isListening ? AppColors.accentGold : AppColors.primaryGreen)
                                .withValues(alpha: 0.4),
                            blurRadius: _isListening ? 24 : 12,
                            spreadRadius: _isListening ? 6 : 2,
                          ),
                        ],
                      ),
                      child: Icon(
                        _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                        color: Colors.white,
                        size: 42,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),

            // Spoken Text Display Box
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _recognizedWords.isNotEmpty
                      ? AppColors.accentGold.withValues(alpha: 0.6)
                      : (isDark ? Colors.white12 : Colors.grey.shade200),
                  width: _recognizedWords.isNotEmpty ? 1.5 : 1.0,
                ),
              ),
              child: Column(
                children: [
                  if (_recognizedWords.isNotEmpty) ...[
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.format_quote_rounded, size: 18, color: AppColors.accentGold),
                        SizedBox(width: 4),
                        Text(
                          'الكلمات التي تم التقاطها:',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.accentGold,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '«$_recognizedWords»',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                        fontFamily: 'Amiri',
                        height: 1.6,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ] else ...[
                    Text(
                      'تحدّث باسم السورة، أو آية كريمة، أو كلمة قرانية تبحث عنها:',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isDark ? Colors.white60 : Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      alignment: WrapAlignment.center,
                      children: [
                        _buildExampleChip('آية الكرسي'),
                        _buildExampleChip('قل هو الله أحد'),
                        _buildExampleChip('سورة الملك'),
                        _buildExampleChip('إن مع العسر يسرا'),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 2,
                    ),
                    icon: const Icon(Icons.search_rounded, size: 20),
                    label: const Text(
                      'بحث بالآية',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _recognizedWords.trim().isNotEmpty ? _confirmAndSearch : null,
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: textColor,
                    side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('إعادة'),
                  onPressed: () {
                    _startVoiceListening();
                  },
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'إغلاق',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExampleChip(String label) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      backgroundColor: AppColors.primaryGreen.withValues(alpha: 0.08),
      side: BorderSide(color: AppColors.primaryGreen.withValues(alpha: 0.2)),
      onPressed: () {
        setState(() {
          _recognizedWords = label;
          _isListening = false;
        });
      },
    );
  }
}
