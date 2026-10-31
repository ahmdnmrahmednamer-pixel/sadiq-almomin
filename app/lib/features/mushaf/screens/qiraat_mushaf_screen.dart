import 'package:flutter/material.dart';
import '../../../app/widgets/app_navigation_drawer.dart';
import '../../../core/services/qiraat_service.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/theme/app_theme.dart';

/// شاشة «مصحف الصحابة في القراءات العشر المتواترة من طريق الشاطبية والدرة»
/// مستخرجة من المرجع المعتمد: «مصحف القراءات.pdf»
class QiraatMushafScreen extends StatefulWidget {
  const QiraatMushafScreen({super.key});

  @override
  State<QiraatMushafScreen> createState() => _QiraatMushafScreenState();
}

class _QiraatMushafScreenState extends State<QiraatMushafScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Directionality(
      textDirection: SettingsService.instance.textDirection,
      child: Scaffold(
        drawer: const AppNavigationDrawer(),
        appBar: AppBar(
          title: const Text('مصحف القراءات العشر المتواترة'),
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            indicatorColor: AppColors.accentGold,
            indicatorWeight: 3,
            labelColor: AppColors.accentGold,
            unselectedLabelColor: Colors.white70,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
            tabs: const [
              Tab(icon: Icon(Icons.people_alt_rounded, size: 20), text: 'القراء العشرة ورواتهم'),
              Tab(icon: Icon(Icons.font_download_rounded, size: 20), text: 'رموز الشاطبية والدرة'),
              Tab(icon: Icon(Icons.menu_book_rounded, size: 20), text: 'أصول القراءات'),
              Tab(icon: Icon(Icons.auto_stories_rounded, size: 20), text: 'فرش الحروف والتوجيه'),
            ],
          ),
        ),
        body: Column(
          children: [
            // Top Reference Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: isDark ? const Color(0xFF14221A) : const Color(0xFFE8F2EC),
              child: Row(
                children: [
                  const Icon(Icons.verified_rounded, color: AppColors.accentGold, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          QiraatService.bookTitle,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Amiri',
                          ),
                        ),
                        Text(
                          'تحقيق وإعداد: ${QiraatService.authorName}',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white60 : AppColors.mutedText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildRecitersTab(context, isDark),
                  _buildSymbolsTab(context, isDark),
                  _buildUsulTab(context, isDark),
                  _buildDifferencesTab(context, isDark),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 1. Reciters & Narrators Tab
  Widget _buildRecitersTab(BuildContext context, bool isDark) {
    final reciters = QiraatService.reciters;

    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: reciters.length,
      itemBuilder: (context, index) {
        final r = reciters[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 1.5,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ExpansionTile(
            shape: const Border(),
            leading: CircleAvatar(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              child: Text(
                '${r.orderNumber}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(
              r.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            subtitle: Text(
              '${r.city} • توفي سنة ${r.deathYearHijri} هـ • رمزه: «${r.individualCode}»',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white60 : AppColors.mutedText,
              ),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              const Divider(height: 1),
              const SizedBox(height: 10),
              Text(
                r.fullBiography,
                style: const TextStyle(fontSize: 12.5, height: 1.5),
              ),
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'الراويان المعتمدان عن الإمام:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppColors.accentGold,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ...r.narrators.map((n) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'الراوي: ${n.name} (رمزه: «${n.code}»)',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            const Spacer(),
                            Text(
                              'ت: ${n.deathYearHijri} هـ',
                              style: const TextStyle(fontSize: 11, color: AppColors.accentGold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'أبرز خصائص قراءته: ${n.characteristics}',
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.45,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
          ),
        );
      },
    );
  }

  // 2. Symbols Tab
  Widget _buildSymbolsTab(BuildContext context, bool isDark) {
    final symbols = QiraatService.symbols;

    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: symbols.length,
      itemBuilder: (context, index) {
        final s = symbols[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 1.5,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primaryGreen,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        s.symbol,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'رمز ${s.type} (${s.poemSource})',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : AppColors.mutedText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  s.representation,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1B2D22) : const Color(0xFFF1F8F4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.format_quote_rounded, size: 16, color: AppColors.accentGold),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          s.examplePoemLine,
                          style: const TextStyle(
                            fontFamily: 'Amiri',
                            fontSize: 13.5,
                            color: AppColors.accentGold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 3. Usul Rules Tab
  Widget _buildUsulTab(BuildContext context, bool isDark) {
    final rules = QiraatService.usulRules;

    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: rules.length,
      itemBuilder: (context, index) {
        final rule = rules[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 1.5,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.rule_rounded, color: AppColors.primaryGreen, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        rule.title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  rule.explanation,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.accentGold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.accentGold.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    'مثال قرآني: ${rule.exampleQuranic}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.accentGold,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'القراء المعنيون: ${rule.applicableReciters}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white60 : AppColors.mutedText,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 4. Differences Tab
  Widget _buildDifferencesTab(BuildContext context, bool isDark) {
    final diffs = QiraatService.famousDifferences;

    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: diffs.length,
      itemBuilder: (context, index) {
        final d = diffs[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 1.5,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primaryGreen,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'سورة ${d.surahName} (آية ${d.ayahNumber})',
                        style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      d.ayahFragment,
                      style: const TextStyle(
                        fontFamily: 'Amiri',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.accentGold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'قراءة حفص عن عاصم:\n${d.readingHafs}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  'القراءات الأخرى:\n${d.otherReadings}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? const Color(0xFFFFD180) : const Color(0xFFB26A00),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E3326) : const Color(0xFFF1F8F4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'التوجيه البلاغي والمعنى:\n${d.explanationAndTawjih}',
                    style: const TextStyle(fontSize: 12, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
