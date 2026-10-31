import 'package:flutter/material.dart';
import '../../../core/models/surah.dart';
import '../../../core/services/quran_linguistics_service.dart';
import '../../../core/services/quran_repository.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/theme/app_theme.dart';

/// شاشة «إعراب القرآن الكريم وبيانه النحوي»
class QuranIrabScreen extends StatefulWidget {
  final int initialSurahId;
  final int initialAyah;

  const QuranIrabScreen({
    super.key,
    this.initialSurahId = 1,
    this.initialAyah = 1,
  });

  @override
  State<QuranIrabScreen> createState() => _QuranIrabScreenState();
}

class _QuranIrabScreenState extends State<QuranIrabScreen> {
  List<Surah> _surahs = [];
  late int _selectedSurahId;
  late int _selectedAyah;
  bool _isLoading = true;
  Surah? _currentSurah;
  QuranLinguisticsResult? _linguistics;

  @override
  void initState() {
    super.initState();
    _selectedSurahId = widget.initialSurahId;
    _selectedAyah = widget.initialAyah;
    _loadSurahs();
  }

  Future<void> _loadSurahs() async {
    final list = await QuranRepository.loadSurahs();
    if (!mounted) return;
    setState(() {
      _surahs = list;
      _currentSurah = list.firstWhere(
        (s) => s.id == _selectedSurahId,
        orElse: () => list.first,
      );
      _isLoading = false;
    });
    _loadAyahData();
  }

  Future<void> _loadAyahData() async {
    final result = await QuranLinguisticsService.getDetails(
      surahId: _selectedSurahId,
      ayahNumber: _selectedAyah,
    );
    if (!mounted) return;
    setState(() {
      _linguistics = result;
    });
  }

  void _onSurahChanged(int? newSurahId) {
    if (newSurahId == null) return;
    setState(() {
      _selectedSurahId = newSurahId;
      _currentSurah = _surahs.firstWhere((s) => s.id == newSurahId);
      _selectedAyah = 1;
    });
    _loadAyahData();
  }

  void _onAyahChanged(int newAyah) {
    setState(() {
      _selectedAyah = newAyah;
    });
    _loadAyahData();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: SettingsService.instance.textDirection,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إعراب القرآن وبيانه'),
          actions: [
            IconButton(
              icon: const Icon(Icons.info_outline_rounded),
              tooltip: 'عن الإعراب',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('عن إعراب القرآن وبيانه'),
                    content: const Text(
                      'يقدم هذا القسم الإعراب النحوي التفصيلي لكل كلمة وآية في كتاب الله الكريم، '
                      'مع بيان المعاني البلاغية والوجوه الإعرابية المعتمدة عند أئمة النحو والتفسير.',
                      style: TextStyle(height: 1.6),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('إغلاق'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primaryGreen),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. Selector Bar: Surah and Ayah
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF14241C) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.primaryGreen.withOpacity(0.2)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          // Surah Dropdown
                          Expanded(
                            flex: 3,
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<int>(
                                value: _selectedSurahId,
                                isExpanded: true,
                                icon: const Icon(Icons.arrow_drop_down_rounded,
                                    color: AppColors.primaryGreen),
                                items: _surahs.map((surah) {
                                  return DropdownMenuItem<int>(
                                    value: surah.id,
                                    child: Text(
                                      '${surah.id}. سورة ${surah.nameAr}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  );
                                }).toList(),
                                onChanged: _onSurahChanged,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Ayah Number Selector
                          Expanded(
                            flex: 2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                color: AppColors.primaryGreen.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<int>(
                                  value: _selectedAyah,
                                  isExpanded: true,
                                  icon: const Icon(Icons.unfold_more_rounded,
                                      size: 18, color: AppColors.primaryGreen),
                                  items: List.generate(
                                    _currentSurah?.ayahCount ?? 7,
                                    (index) => DropdownMenuItem<int>(
                                      value: index + 1,
                                      child: Text(
                                        'الآية ${index + 1}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: AppColors.primaryGreen,
                                        ),
                                      ),
                                    ),
                                  ),
                                  onChanged: (val) {
                                    if (val != null) _onAyahChanged(val);
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 2. Surah & Ayah Heading Banner
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isDark
                              ? [const Color(0xFF0F3628), const Color(0xFF071E16)]
                              : [const Color(0xFF0F5B45), const Color(0xFF1B6B4E)],
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.accentGold.withOpacity(0.4)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'سورة ${_currentSurah?.nameAr ?? ""}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  fontFamily: 'Amiri',
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.accentGold.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.accentGold.withOpacity(0.4)),
                                ),
                                child: Text(
                                  'الآية رقم $_selectedAyah',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.softGold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '﴿${_currentSurah?.nameAr ?? ""} : $_selectedAyah﴾',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Amiri',
                              color: Color(0xFFFFE680),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 3. Overall Grammatical Summary Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF14241C) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.primaryGreen.withOpacity(0.25)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.account_tree_rounded, color: AppColors.primaryGreen, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'المعنى والإعراب الإجمالي:',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  color: AppColors.primaryGreen,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 20),
                          Text(
                            _linguistics?.grammar.summary ??
                                'إعراب مفصل ومطرد لآيات الذكر الحكيم وفق قواعد النحو العربي المعتمدة.',
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.7,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 4. Rhetoric & Eloquence Card
                    if ((_linguistics?.grammar.rhetoricSummary ?? '').isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF14241C) : const Color(0xFFF9FBF9),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.accentGold.withOpacity(0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.auto_awesome, color: AppColors.accentGold, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'البلاغة والبيان القرآني:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                    color: AppColors.accentGold,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 20),
                            Text(
                              _linguistics!.grammar.rhetoricSummary,
                              style: const TextStyle(
                                fontSize: 13.5,
                                height: 1.7,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // 5. Word-by-Word Grammatical Parsing Table
                    if ((_linguistics?.grammar.words ?? []).isNotEmpty) ...[
                      const Text(
                        'إعراب مفردات الآية الكريمة كلمةً كلمة:',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          color: AppColors.primaryGreen,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...(_linguistics!.grammar.words.map((wordGrammar) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF162A20) : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.withOpacity(0.2)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryGreen.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  wordGrammar.word,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14.5,
                                    color: AppColors.primaryGreen,
                                    fontFamily: 'Amiri',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      wordGrammar.role,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      wordGrammar.caseEnding,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      })),
                    ],

                    const SizedBox(height: 20),
                  ],
                ),
              ),
      ),
    );
  }
}
