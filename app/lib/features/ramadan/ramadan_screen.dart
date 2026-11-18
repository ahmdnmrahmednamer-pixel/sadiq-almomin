import '../../core/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/models/ramadan_day.dart';
import '../../core/services/ramadan_service.dart';
import '../../core/services/prayer_service.dart';
import '../../core/theme/app_theme.dart';
import '../prayer/widgets/prayer_location_banner.dart';

class RamadanScreen extends StatefulWidget {
  const RamadanScreen({super.key});

  @override
  State<RamadanScreen> createState() => _RamadanScreenState();
}

class _RamadanScreenState extends State<RamadanScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<RamadanDay> _imsakiyyahList = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    RamadanService.instance.init();
    _imsakiyyahList = RamadanService.instance.generateImsakiyyah();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showDayDetails(RamadanDay day) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Directionality(
          textDirection: SettingsService.instance.textDirection,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'اليوم ${day.dayNumber} من شهر رمضان المبارك',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primaryGreen),
                    ),
                    Text(
                      '${day.dayName} · ${day.gregorianDate.day}/${day.gregorianDate.month}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.secondaryGreen, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.accentGold.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildTimeStat('الإمساك', day.imsakTime, Icons.alarm_rounded, AppColors.accentGold),
                          _buildTimeStat('الفجر', day.fajrTime, Icons.wb_twilight_rounded, AppColors.primaryGreen),
                          _buildTimeStat('الشروق', day.sunriseTime, Icons.wb_sunny_rounded, Colors.orange),
                        ],
                      ),
                      const Divider(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildTimeStat('الظهر', day.dhuhrTime, Icons.sunny, AppColors.primaryGreen),
                          _buildTimeStat('العصر', day.asrTime, Icons.wb_cloudy_rounded, AppColors.primaryGreen),
                          _buildTimeStat('المغرب (الإفطار)', day.maghribTime, Icons.nightlight_round, AppColors.accentGold, isHighlight: true),
                          _buildTimeStat('العشاء', day.ishaTime, Icons.bedtime_rounded, AppColors.primaryGreen),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkCard : const Color(0xFFFBFBFB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome, color: AppColors.accentGold, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          day.dailyDuaa,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTimeStat(String title, String time, IconData icon, Color color, {bool isHighlight = false}) {
    return Column(
      children: [
        Icon(icon, color: color, size: isHighlight ? 22 : 18),
        const SizedBox(height: 4),
        Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isHighlight ? AppColors.accentGold : AppColors.mutedText)),
        const SizedBox(height: 2),
        Text(
          time,
          style: TextStyle(
            fontSize: isHighlight ? 13.5 : 12,
            fontWeight: FontWeight.w900,
            color: isHighlight ? AppColors.primaryGreen : null,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: Listenable.merge([
        PrayerService.instance,
        SettingsService.instance,
      ]),
      builder: (context, _) {
        final service = PrayerService.instance;
        final prayerData = service.currentData;
        final freshness = service.locationFreshness;
        final ageLabel = service.cachedFixAgeLabel;
        final countdown = RamadanService.instance.getCountdown();
        _imsakiyyahList = RamadanService.instance.generateImsakiyyah();
        final locationName = PrayerService.formatDisplayLocationName(
          prayerData,
          freshness,
          unknownFallback: 'الموقع غير محدد عبر GPS',
        );

        return Directionality(
          textDirection: SettingsService.instance.textDirection,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('إمساكية ومحراب رمضان المبارك', style: TextStyle(fontWeight: FontWeight.w900)),
              bottom: TabBar(
                controller: _tabController,
                labelColor: AppColors.accentGold,
                unselectedLabelColor: isDark ? Colors.white70 : Colors.white60,
                indicatorColor: AppColors.accentGold,
                indicatorWeight: 3,
                tabs: const [
                  Tab(icon: Icon(Icons.table_chart_rounded, size: 20), text: 'الإمساكية (٣٠ يوماً)'),
                  Tab(icon: Icon(Icons.task_alt_rounded, size: 20), text: 'متابع الصيام والعبادات'),
                  Tab(icon: Icon(Icons.volunteer_activism_rounded, size: 20), text: 'أدعية وسنن الصائم'),
                ],
              ),
            ),
            body: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverToBoxAdapter(
                  // Top Ramadan Hero Banner with Countdown (scrolls away cleanly
                  // on tall 2.0x viewports so lower tab content is never masked)
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0F4E37), Color(0xFF1B5E20), Color(0xFF072D1E)],
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryGreen.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.location_on_rounded, color: AppColors.softGold, size: 16),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      locationName,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  GpsFreshnessChip(freshness: freshness, onDarkSurface: true),
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      backgroundColor: Colors.white.withValues(alpha: 0.12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    icon: const Icon(Icons.my_location_rounded, size: 14, color: AppColors.softGold),
                                    label: const Text('تحديث الموقع الفعلي', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold)),
                                    onPressed: () async {
                                      final ok = await PrayerService.instance.requestGpsLocation();
                                      if (!mounted) return;
                                      setState(() {
                                        _imsakiyyahList = RamadanService.instance.generateImsakiyyah();
                                      });
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(ok
                                                ? 'تم تحديث الموقع الفعلي عبر GPS بنجاح'
                                                : GpsLocationActionControls.describeUnavailableReason(
                                                    PrayerService.instance,
                                                    promptContext: GpsPromptContext.ramadan,
                                                  )),
                                            backgroundColor: ok ? AppColors.primaryGreen : Colors.redAccent,
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (ageLabel != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              ageLabel,
                              style: const TextStyle(color: Color(0xFFFEF3C7), fontSize: 11),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.accentGold.withValues(alpha: 0.5)),
                          ),
                          child: countdown == null
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'مواقيت الإمساك والإفطار تتطلب تحديد موقعك عبر GPS',
                                      style: TextStyle(color: Color(0xFFFFE680), fontSize: 12.5, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      GpsLocationActionControls.describeUnavailableReason(
                                        service,
                                        promptContext: GpsPromptContext.ramadan,
                                      ),
                                      style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                                    ),
                                    const SizedBox(height: 8),
                                    const GpsLocationActionControls(
                                      onDarkSurface: true,
                                      promptContext: GpsPromptContext.ramadan,
                                    ),
                                  ],
                                )
                              : Wrap(
                                  alignment: WrapAlignment.spaceBetween,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          countdown.title,
                                          style: const TextStyle(color: Color(0xFFFFE680), fontSize: 12.5, fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'موعد الأذان: ${countdown.targetTimeFormatted}',
                                          style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                                        ),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.accentGold,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        PrayerService.instance.formatCountdown(countdown.remaining),
                                        style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF072D1E), fontSize: 14.5),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              body: TabBarView(
                controller: _tabController,
                children: [
                  _buildImsakiyyahTab(),
                  _buildTrackerTab(),
                  _buildDuaaTab(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // 1. Imsakiyyah Table Tab
  Widget _buildImsakiyyahTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_imsakiyyahList.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            key: const ValueKey('ramadan_imsakiyyah_unavailable_card'),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'لا يمكن حساب إمساكية رمضان قبل تحديد موقعك عبر GPS',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    GpsLocationActionControls.describeUnavailableReason(
                      PrayerService.instance,
                      promptContext: GpsPromptContext.ramadan,
                    ),
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white70 : AppColors.mutedText,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const GpsLocationActionControls(
                    promptContext: GpsPromptContext.ramadan,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      children: [
        // Table Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.primaryGreen,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            children: [
              SizedBox(width: 48, child: Text('رمضان', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12))),
              Expanded(flex: 2, child: Text('التاريخ واليوم', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12))),
              Expanded(child: Text('الإمساك', textAlign: TextAlign.center, style: TextStyle(color: AppColors.softGold, fontWeight: FontWeight.w900, fontSize: 12))),
              Expanded(child: Text('الفجر', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12))),
              Expanded(child: Text('الإفطار', textAlign: TextAlign.center, style: TextStyle(color: AppColors.softGold, fontWeight: FontWeight.w900, fontSize: 12))),
              Expanded(child: Text('العشاء', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12))),
            ],
          ),
        ),
        const SizedBox(height: 6),

        // 30 Days rows
        ..._imsakiyyahList.map((day) {
          final isEven = day.dayNumber % 2 == 0;
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _showDayDetails(day),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: isEven
                    ? (isDark ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFF7FBF8))
                    : (isDark ? Colors.transparent : Colors.white),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primaryGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${day.dayNumber}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryGreen, fontSize: 12),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(day.dayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                        Text('${day.gregorianDate.day}/${day.gregorianDate.month}', style: const TextStyle(fontSize: 10, color: AppColors.mutedText)),
                      ],
                    ),
                  ),
                  Expanded(child: Text(day.imsakTime, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11))),
                  Expanded(child: Text(day.fajrTime, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11))),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.accentGold.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        day.maghribTime,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF8B6508), fontSize: 11),
                      ),
                    ),
                  ),
                  Expanded(child: Text(day.ishaTime, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11))),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 16),
      ],
    );
  }

  // 2. Fasting & Worship Tracker Tab
  Widget _buildTrackerTab() {
    return AnimatedBuilder(
      animation: RamadanService.instance,
      builder: (context, _) {
        final fastedCount = RamadanService.instance.totalFastedCount;
        final taraweehCount = RamadanService.instance.totalTaraweehCount;
        final quranCount = RamadanService.instance.totalQuranCount;
        final progress = RamadanService.instance.fastingProgress;

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          children: [
            // Stats Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primaryGreen.withValues(alpha: 0.12),
                    AppColors.accentGold.withValues(alpha: 0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.accentGold.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('سجل إنجاز العبادات الرمضانية', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.primaryGreen)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.accentGold.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('${(progress * 100).toInt()}% مكتمل', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryGreen, fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: Colors.grey.withValues(alpha: 0.2),
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accentGold),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildTrackerStat('الصيام', '$fastedCount / 30', Icons.check_circle_rounded, AppColors.primaryGreen),
                      _buildTrackerStat('التراويح', '$taraweehCount ليلة', Icons.nightlight_round, AppColors.accentGold),
                      _buildTrackerStat('الورد القرآني', '$quranCount جزء', Icons.menu_book_rounded, AppColors.secondaryGreen),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Daily Check-in list (30 days)
            ..._imsakiyyahList.map((day) {
              final isFasted = RamadanService.instance.isDayFasted(day.dayNumber);
              final isTaraweeh = RamadanService.instance.isTaraweehCompleted(day.dayNumber);
              final isQuran = RamadanService.instance.isQuranCompleted(day.dayNumber);

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isFasted ? AppColors.primaryGreen : AppColors.primaryGreen.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${day.dayNumber}',
                          style: TextStyle(
                            color: isFasted ? Colors.white : AppColors.primaryGreen,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${day.dayName} (${day.gregorianDate.day}/${day.gregorianDate.month})',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                            ),
                            Text(
                              'إفطار: ${day.maghribTime} · إمساك: ${day.imsakTime}',
                              style: const TextStyle(fontSize: 11, color: AppColors.mutedText),
                            ),
                          ],
                        ),
                      ),
                      // 3 Action Icons
                      IconButton(
                        icon: Icon(
                          isFasted ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                          color: isFasted ? AppColors.primaryGreen : Colors.grey.shade400,
                          size: 24,
                        ),
                        tooltip: 'صمت هذا اليوم',
                        onPressed: () => RamadanService.instance.toggleFasted(day.dayNumber),
                      ),
                      IconButton(
                        icon: Icon(
                          isTaraweeh ? Icons.mosque_rounded : Icons.mosque_outlined,
                          color: isTaraweeh ? AppColors.accentGold : Colors.grey.shade400,
                          size: 24,
                        ),
                        tooltip: 'صليت التراويح / القيام',
                        onPressed: () => RamadanService.instance.toggleTaraweeh(day.dayNumber),
                      ),
                      IconButton(
                        icon: Icon(
                          isQuran ? Icons.auto_stories_rounded : Icons.auto_stories_outlined,
                          color: isQuran ? AppColors.secondaryGreen : Colors.grey.shade400,
                          size: 24,
                        ),
                        tooltip: 'قرأت الورد القرآني',
                        onPressed: () => RamadanService.instance.toggleQuran(day.dayNumber),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _buildTrackerStat(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.mutedText)),
      ],
    );
  }

  // 3. Ramadan Supplications Tab
  Widget _buildDuaaTab() {
    const supplications = RamadanService.supplications;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      children: [
        ...supplications.map((duaa) {
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.accentGold.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          duaa.category,
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF8B6508)),
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.primaryGreen),
                            tooltip: 'نسخ الدعاء',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: '${duaa.title}\n«${duaa.arabicText}»\n${duaa.source}')).catchError((_) {});
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('تم نسخ الدعاء المبارك')),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.share_rounded, size: 18, color: AppColors.primaryGreen),
                            tooltip: 'مشاركة الدعاء',
                            onPressed: () {
                              try {
                                Share.share('🤲 ${duaa.title}\n\n«${duaa.arabicText}»\n\n📌 المرجع: ${duaa.source}\n---\nتطبيق صديق المؤمن للقرآن الكريم والعبادات');
                              } catch (_) {}
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(duaa.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primaryGreen.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.15)),
                    ),
                    child: Text(
                      '«${duaa.arabicText}»',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Amiri',
                        fontSize: 16.5,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primaryGreen,
                        height: 1.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'المرجع: ${duaa.source}',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.mutedText, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          );
        }),

        // Momen Ibrahim dedication card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primaryGreen.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.accentGold.withValues(alpha: 0.4)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.nights_stay_rounded, color: AppColors.accentGold, size: 18),
              SizedBox(width: 8),
              Text(
                'رمضان مبارك — تقبل الله منا ومنكم صالح الأعمال',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: AppColors.primaryGreen),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
