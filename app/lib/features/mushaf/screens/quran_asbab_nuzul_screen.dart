import 'package:flutter/material.dart';
import '../../../core/models/surah.dart';
import '../../../core/services/quran_linguistics_service.dart';
import '../../../core/services/quran_repository.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/theme/app_theme.dart';

/// شاشة «أسباب نزول الآيات وسياق التنزيل»
class QuranAsbabNuzulScreen extends StatefulWidget {
  final int initialSurahId;
  final int initialAyah;

  const QuranAsbabNuzulScreen({
    super.key,
    this.initialSurahId = 1,
    this.initialAyah = 1,
  });

  @override
  State<QuranAsbabNuzulScreen> createState() => _QuranAsbabNuzulScreenState();
}

class _QuranAsbabNuzulScreenState extends State<QuranAsbabNuzulScreen> {
  List<Surah> _surahs = [];
  late int _selectedSurahId;
  late int _selectedAyah;
  bool _isLoading = true;
  Surah? _currentSurah;
  AsbabNuzul? _asbabNuzul;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedSurahId = widget.initialSurahId;
    _selectedAyah = widget.initialAyah;
    _loadSurahs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
    _loadData();
  }

  Future<void> _loadData() async {
    final result = await QuranLinguisticsService.getDetails(
      surahId: _selectedSurahId,
      ayahNumber: _selectedAyah,
    );
    if (!mounted) return;
    setState(() {
      _asbabNuzul = result.asbabNuzul;
    });
  }

  void _onSurahChanged(int? newSurahId) {
    if (newSurahId == null) return;
    setState(() {
      _selectedSurahId = newSurahId;
      _currentSurah = _surahs.firstWhere((s) => s.id == newSurahId);
      _selectedAyah = 1;
    });
    _loadData();
  }

  void _onAyahChanged(int newAyah) {
    setState(() {
      _selectedAyah = newAyah;
    });
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: SettingsService.instance.textDirection,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('أسباب نزول الآيات'),
          actions: [
            IconButton(
              icon: const Icon(Icons.info_outline_rounded),
              tooltip: 'عن أسباب النزول',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('عن أسباب نزول الآيات'),
                    content: const Text(
                      'يُعنى هذا القسم ببيان الوقائع والأحداث التي نزلت بشأنها الآيات الكريمة '
                      'استناداً إلى كتب الحديث الصحاح وأمهات كتب أسباب النزول كالإمام الواحدي '
                      'ولباب النقول للإمام السيوطي، مما يعين على تدبر المعاني وفهم مقاصد الشريعة.',
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

                    // 2. Surah & Ayah Banner
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
                                  'الآية $_selectedAyah',
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
                            _asbabNuzul?.title ?? 'سياق نزول الآية الكريمة',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFFFE680),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 3. Reason for Revelation Detail Card
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF14241C) : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppColors.primaryGreen.withOpacity(0.25),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(isDark ? 0.25 : 0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryGreen.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.history_edu_rounded,
                                  color: AppColors.primaryGreen,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'الرواية وسياق النزول المأثور:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                    color: AppColors.primaryGreen,
                                  ),
                                ),
                              ),
                              if (_asbabNuzul?.hasSpecificIncident ?? false)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.amber.withOpacity(0.4)),
                                  ),
                                  child: const Text(
                                    'واقعة خاصة',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.amber,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const Divider(height: 22),
                          Text(
                            _asbabNuzul?.narration ?? 'جاري استدعاء سبب النزول...',
                            style: const TextStyle(
                              fontSize: 14.5,
                              height: 1.85,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF0F241A) : const Color(0xFFF4F7F4),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.withOpacity(0.2)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.menu_book_rounded, size: 16, color: AppColors.accentGold),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'المصدر: ${_asbabNuzul?.source ?? "أسباب النزول المعتمدة"}',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 4. Quick Rule & Lesson Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF14241C) : const Color(0xFFF9FBF9),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.accentGold.withOpacity(0.3)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.lightbulb_outline_rounded, color: AppColors.accentGold, size: 22),
                          SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'فائدة أصولية:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13.5,
                                    color: AppColors.accentGold,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  '«العبرة بعموم اللفظ لا بخصوص السبب»؛ فالحكم القرآني عام وشامل لكل أفراد الأمة إلى قيام الساعة.',
                                  style: TextStyle(fontSize: 12, height: 1.6),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
      ),
    );
  }
}
