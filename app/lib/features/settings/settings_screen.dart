import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/router.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/audio/ayah_audio_player.dart';
import '../../core/notifications/prayer_notification_service.dart';
import '../../core/services/islamic_audio_service.dart';
import '../../core/services/prayer_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/tafsir_service.dart';
import '../../core/ui/adaptive_screen_layouts.dart';
import '../prayer/adhan_control_screen.dart';
import '../prayer/widgets/prayer_location_banner.dart';
import 'models/settings_draft.dart';
import 'models/settings_session.dart';
import 'widgets/settings_adhan_voice_modal.dart';
import 'widgets/settings_reciter_modal.dart';
import 'widgets/sections/settings_adhkar_reminders_section.dart';
import 'widgets/sections/settings_tools_and_about_section.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  late final SettingsSession session = SettingsSession();
  int? category;
  String? status;
  bool closing = false;
  String? ownedReciterPreview;
  bool reciterPreviewPending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(stopReciterPreview());
    }
  }
  bool get ar => SettingsService.instance.isArabic;
  String tr(String arabic, String english) {
    if (ar) return arabic;
    final code = SettingsService.instance.languageCode;
    if (code == 'en') return english;
    const keys = {
      'Language and appearance': 'section_language_appearance',
      'Quran and audio': 'section_quran_audio',
      'Prayer': 'section_prayer_fiqh',
      'Adhan and controls': 'section_adhan_sensors',
      'Tools and information': 'section_tools_about',
      'Settings': 'settings_title',
      'Language': 'app_language',
      'Quran translation': 'quran_translation_lang',
      'Bilingual display': 'bilingual_mode',
      'Theme': 'theme',
      'Screen layout': 'screen_layout',
      'System': 'theme_system',
      'Light': 'theme_light',
      'Dark': 'theme_dark',
      'Reciter': 'default_reciter',
      'Tafsir': 'default_tafsir',
      'Audio quality': 'audio_dsp_preset',
      'Playback speed': 'playback_speed',
      'Verse repeat': 'ayah_repeat',
      'Font size': 'font_size',
      'Mushaf view': 'mushaf_mode',
      'Play next verse': 'auto_play_next',
      'Keep screen on': 'keep_screen_on',
      'Download over Wi-Fi only': 'wifi_only',
      'Calculation method': 'calc_method',
      'Fiqh': 'fiqh_madhhab',
      'Hijri adjustment': 'hijri_adjust',
      'Notifications': 'notifications',
      'Pre-adhan reminder': 'pre_adhan_alert',
      'Iqamah minutes': 'iqamah_offset',
      'Cancel': 'cancel',
      'Home': 'nav_home',
    };
    final key = keys[english];
    if (key != null) return context.tr(key);
    const actions = {
      'fr': {'Apply': 'Appliquer', 'Discard': 'Ignorer', 'Stay': 'Rester'},
      'tr': {'Apply': 'Uygula', 'Discard': 'Vazgeç', 'Stay': 'Kal'},
      'ur': {
        'Apply': 'لاگو کریں',
        'Discard': 'تبدیلیاں رد کریں',
        'Stay': 'یہیں رہیں'
      },
      'id': {'Apply': 'Terapkan', 'Discard': 'Abaikan', 'Stay': 'Tetap'},
    };
    return actions[code]?[english] ?? english;
  }

  List<String> get names => [
        tr('اللغة والمظهر', 'Language and appearance'),
        tr('القرآن والصوت', 'Quran and audio'),
        tr('الصلاة', 'Prayer'),
        tr('الأذكار', 'Adhkar'),
        tr('الأذان والتحكم', 'Adhan and controls'),
        tr('الأدوات والمعلومات', 'Tools and information')
      ];

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(stopReciterPreview());
    session.draft.dispose();
    super.dispose();
  }

  Future<void> stopReciterPreview() async {
    final id = ownedReciterPreview;
    if (id == null) return;
    ownedReciterPreview = null;
    if (reciterPreviewPending ||
        AyahAudioPlayer.instance.currentPlayingKey.value == 'preview_$id') {
      await AyahAudioPlayer.instance.stop();
    }
  }

  Future<void> previewReciter() async {
    if (reciterPreviewPending) {
      await stopReciterPreview();
      return;
    }
    final player = AyahAudioPlayer.instance;
    final reciter = SettingsService.availableReciters.firstWhere(
        (r) => r.id == session.reciter.value,
        orElse: () => SettingsService.availableReciters.first);
    ownedReciterPreview = reciter.id;
    reciterPreviewPending = true;
    final ok = await player.playReciterPreview(reciter);
    reciterPreviewPending = false;
    if (!mounted || ownedReciterPreview != reciter.id) return;
    if (!ok && player.currentPlayingKey.value != 'preview_${reciter.id}') {
      setState(() => status = tr(
          'توقفت المعاينة أو تعذر تشغيلها', 'Preview stopped or unavailable'));
    }
  }

  Future<void> leave({bool home = false}) async {
    if (session.draft.applying || closing) return;
    if (category != null && !home) {
      await stopReciterPreview();
      if (!mounted) return;
      setState(() => category = null);
      return;
    }
    closing = true;
    try {
      if (session.draft.dirty) {
        final discard = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
                    title: Text(tr('تغييرات غير مطبقة', 'Unapplied changes')),
                    content: Text(tr(
                        'هل تريد تجاهل التغييرات؟', 'Discard these changes?')),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(tr('البقاء', 'Stay'))),
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(tr('تجاهل', 'Discard')))
                    ]));
        if (discard != true || !mounted) return;
        session.draft.discard();
      }
      if (!mounted) return;
      if (home || !Navigator.canPop(context)) {
        GoRouter.maybeOf(context)?.go('/home');
      } else {
        Navigator.pop(context);
      }
    } finally {
      closing = false;
    }
  }

  Future<void> apply() async {
    final result = await session.draft.apply();
    if (!mounted) return;
    setState(() => status = result.success
        ? tr('تم حفظ التغييرات', 'Changes saved')
        : result.conflict
            ? tr('تغير إعداد من شاشة أخرى. أعد فتح الإعدادات قبل المحاولة.',
                'A setting changed elsewhere. Reopen settings before retrying.')
            : tr(
                'لم تكتمل كل التغييرات. قد تكون بعض التغييرات محفوظة. راجع الحالة وأعد المحاولة.',
                'Not all changes were applied. Some may be saved. Check the status and retry.'));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: Listenable.merge([
        session.draft,
        PrayerNotificationService.instance,
        PrayerService.instance
      ]),
      builder: (context, _) {
        final draft = session.draft;
        return PopScope(
          canPop: !draft.dirty && !draft.applying && category == null,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) leave();
          },
          child: Directionality(
              textDirection: SettingsService.instance.textDirection,
              child: Scaffold(
                appBar: AppBar(
                    toolbarHeight:
                        MediaQuery.textScalerOf(context).scale(18) * 2.4 + 20,
                    title: Text(
                        category == null
                            ? tr('الإعدادات', 'Settings')
                            : names[category!],
                        maxLines: 2,
                        softWrap: true,
                        style: const TextStyle(fontSize: 18)),
                    leading: IsolatedBackButton(onPressed: leave),
                    actions: [
                      IconButton(
                          tooltip: tr('الرئيسية', 'Home'),
                          onPressed:
                              draft.applying ? null : () => leave(home: true),
                          icon: const Icon(Icons.home_outlined))
                    ]),
                body: AbsorbPointer(
                    absorbing: draft.applying,
                    child: category == null
                        ? ListView(children: [
                            for (var i = 0; i < names.length; i++)
                              ListTile(
                                  key: ValueKey('settings_category_$i'),
                                  title: Text(names[i]),
                                  trailing: const Icon(Icons.chevron_left),
                                  onTap: () => setState(() => category = i))
                          ])
                        : Semantics(
                            namesRoute: true,
                            label: names[category!],
                            child: ListView(
                                key: ValueKey('settings_page_$category'),
                                padding: const EdgeInsets.only(bottom: 24),
                                children: page(category!)))),
                bottomNavigationBar: SafeArea(
                    child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (status != null)
                                Semantics(
                                    liveRegion: true, child: Text(status!)),
                              if (draft.applying)
                                Semantics(
                                    liveRegion: true,
                                    child: Text(
                                        tr('جار التطبيق...', 'Applying...'))),
                              Wrap(
                                  alignment: WrapAlignment.end,
                                  spacing: 12,
                                  runSpacing: 8,
                                  children: [
                                    OutlinedButton(
                                        key: const ValueKey('settings_discard'),
                                        onPressed: draft.dirty &&
                                                !draft.applying
                                            ? () {
                                                draft.discard();
                                                setState(() => status = null);
                                              }
                                            : null,
                                        child: Text(tr('تجاهل', 'Discard'))),
                                    FilledButton(
                                        key: const ValueKey('settings_apply'),
                                        onPressed:
                                            draft.dirty && !draft.applying
                                                ? apply
                                                : null,
                                        child: Text(tr('تطبيق', 'Apply')))
                                  ])
                            ]))),
              )),
        );
      });

  Widget toggle(String label, DraftSetting<bool> setting) => SwitchListTile(
      key: ValueKey('setting_$label'),
      title: Text(label),
      value: setting.value,
      onChanged: (value) {
        setting.stage(value);
        setState(() => status = null);
      });

  Widget choice<T>(
          String label, DraftSetting<T> setting, Map<T, String> options) =>
      select<T>(label, setting.value, options, setting.stage);

  Widget select<T>(
      String label, T value, Map<T, String> options, ValueChanged<T> stage) {
    // Include a supported custom/current value instead of silently choosing the first.
    final all = <T, String>{...options};
    all.putIfAbsent(value, () => '$value');
    return ListTile(
        key: ValueKey('setting_$label'),
        title: Text(label),
        subtitle: Text(all[value]!),
        trailing: const Icon(Icons.expand_more),
        onTap: () async {
          final picked = await showModalBottomSheet<T>(
              context: context,
              isScrollControlled: true,
              builder: (ctx) => SafeArea(
                  child: SizedBox(
                      height: MediaQuery.sizeOf(ctx).height * .75,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                                padding: const EdgeInsets.all(16),
                                child: Semantics(
                                    header: true,
                                    child: Text(label,
                                        style: Theme.of(ctx)
                                            .textTheme
                                            .titleLarge))),
                            Expanded(
                                child: ListView(children: [
                              for (final option in all.entries)
                                ListTile(
                                    title: Text(option.value),
                                    selected: option.key == value,
                                    trailing: option.key == value
                                        ? const Icon(Icons.check)
                                        : null,
                                    onTap: () => Navigator.pop(ctx, option.key))
                            ])),
                            TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: Text(tr('إلغاء', 'Cancel')))
                          ]))));
          if (picked != null && mounted) {
            stage(picked);
            setState(() => status = null);
          }
        });
  }

  Widget time(String label, DraftSetting<({int hour, int minute})> setting) =>
      ListTile(
          title: Text(label),
          subtitle: Text(
              TimeOfDay(hour: setting.value.hour, minute: setting.value.minute)
                  .format(context)),
          onTap: () async {
            final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(
                    hour: setting.value.hour, minute: setting.value.minute));
            if (picked != null && mounted) {
              setting.stage((hour: picked.hour, minute: picked.minute));
            }
          });

  List<Widget> page(int index) => switch (index) {
        0 => languagePage(),
        1 => quranPage(),
        2 => prayerPage(),
        3 => adhkarPage(),
        4 => adhanPage(),
        _ => [const SettingsToolsAndAboutSection(showHeader: false)],
      };

  List<Widget> languagePage() {
    final selected = session.language.value;
    return [
      select(
          tr('اللغة', 'Language'),
          selected.language,
          {for (final lang in AppLanguage.values) lang.code: lang.nativeName},
          session.stageLanguage),
      select(
          tr('ترجمة القرآن', 'Quran translation'),
          selected.translation,
          {
            for (final value in QuranTranslationEdition.availableTranslations)
              value.id: ar ? value.nameAr : value.nameNative
          },
          (value) => session.language.stage((
                language: selected.language,
                translation: value,
                bilingual: selected.bilingual
              ))),
      SwitchListTile(
          title: Text(tr('العرض بلغتين', 'Bilingual display')),
          value: selected.bilingual,
          onChanged: (value) => session.language.stage((
                language: selected.language,
                translation: selected.translation,
                bilingual: value
              ))),
      choice(tr('المظهر', 'Theme'), session.theme, {
        'system': tr('النظام', 'System'),
        'light': tr('فاتح', 'Light'),
        'dark': tr('داكن', 'Dark'),
        'oled': 'OLED'
      }),
      choice(tr('تخطيط الشاشة', 'Screen layout'), session.layout, {
        for (final mode in ScreenStructureMode.values) mode.id: mode.labelAr
      }),
    ];
  }

  List<Widget> quranPage() => [
        ListTile(
            title: Text(tr('القارئ', 'Reciter')),
            subtitle: Text(SettingsService.availableReciters
                .firstWhere((r) => r.id == session.reciter.value,
                    orElse: () => SettingsService.availableReciters.first)
                .nameAr),
            trailing: const Icon(Icons.expand_more),
            onTap: () async {
              await stopReciterPreview();
              if (!mounted) return;
              showSettingsReciterModal(context,
                  selectedReciter: session.reciter.value,
                  onStage: session.reciter.stage);
            }),
        TextButton.icon(
            onPressed: previewReciter,
            icon: const Icon(Icons.headphones),
            label: Text(tr('استماع أو إيقاف العينة', 'Listen or stop sample'))),
        choice(tr('التفسير', 'Tafsir'), session.tafsir, {
          for (final value in TafsirService.availableEditions)
            value.id: value.nameAr
        }),
        choice(tr('جودة الصوت', 'Audio quality'), session.quality, {
          AudioClarityPreset.studioHd.id: tr('نقاء', 'Clear'),
          AudioClarityPreset.mosqueEcho.id: tr('صدى', 'Echo'),
          AudioClarityPreset.warmVoice.id: tr('دافئ', 'Warm'),
          AudioClarityPreset.clearSpeech.id: tr('وضوح الكلام', 'Speech clarity')
        }),
        choice(tr('سرعة التشغيل', 'Playback speed'), session.speed, {
          for (final value in [.5, .75, 1.0, 1.25, 1.5, 1.75, 2.0])
            value: '${value}x'
        }),
        choice(tr('تكرار الآية', 'Verse repeat'), session.repeat,
            {for (var i = 1; i <= 10; i++) i: '$i'}),
        choice(tr('حجم الخط', 'Font size'), session.font,
            {for (var i = 18; i <= 38; i += 2) i.toDouble(): '$i'}),
        choice(tr('عرض المصحف', 'Mushaf view'), session.mode,
            {'page': tr('صفحات', 'Pages'), 'text': tr('نص', 'Text')}),
        choice(tr('أرقام الآيات', 'Verse numbers'), session.numbering,
            {'arabic': '1, 2, 3', 'indic': '١، ٢، ٣'}),
        toggle(tr('تشغيل الآية التالية', 'Play next verse'), session.autoplay),
        toggle(tr('إبقاء الشاشة مضاءة', 'Keep screen on'), session.screen),
        toggle(tr('التحميل عبر واي فاي فقط', 'Download over Wi-Fi only'),
            session.wifi),
      ];

  List<Widget> prayerPage() => [
        choice(tr('طريقة الحساب', 'Calculation method'), session.method, {
          for (final value in SettingsService.calculationMethods)
            value['id']!: value['name']!
        }),
        choice(tr('المذهب', 'Fiqh'), session.fiqh, {
          'shafii_egypt': 'الشافعي / دار الإفتاء المصرية',
          'hanafi': 'الحنفي',
          'maliki': 'المالكي',
          'hanbali': 'الحنبلي',
          'comparative': 'الفقه المقارن'
        }),
        choice(tr('تعديل الهجري', 'Hijri adjustment'), session.hijri,
            {for (var i = -2; i <= 2; i++) i: '$i'}),
        PrayerLocationBanner(data: PrayerService.instance.currentData),
      ];

  List<Widget> adhkarPage() {
    final n = PrayerNotificationService.instance;
    return [
      toggle(tr('أذكار الصباح', 'Morning adhkar'), session.morning),
      time(tr('موعد الصباح', 'Morning time'), session.morningTime),
      toggle(tr('أذكار المساء', 'Evening adhkar'), session.evening),
      time(tr('موعد المساء', 'Evening time'), session.eveningTime),
      toggle(tr('أذكار النوم', 'Sleep adhkar'), session.sleep),
      time(tr('موعد النوم', 'Sleep time'), session.sleepTime),
      if (!n.masterEnabled)
        Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
                tr('التنبيهات العامة مغلقة', 'Master notifications are off'))),
      for (final key in ['salawat', 'istighfar']) ...[
        choice(
            key == 'salawat'
                ? tr('الصلاة على النبي', 'Salawat')
                : tr('الاستغفار والحوقلة', 'Istighfar and hawqala'),
            session.shortFrequencies[key]!,
            {
              ShortReminderFrequency.off: tr('إيقاف', 'Off'),
              ShortReminderFrequency.halfHourly:
                  tr('كل ٣٠ دقيقة', 'Every 30 minutes'),
              ShortReminderFrequency.hourly: tr('كل ساعة', 'Hourly'),
              ShortReminderFrequency.twoHourly:
                  tr('كل ساعتين', 'Every two hours'),
              ShortReminderFrequency.daily: tr('كل ٢٤ ساعة', 'Daily')
            }),
        if (n.shortReminderError(key) != null) ...[
          Semantics(
              liveRegion: true,
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(n.shortReminderError(key)!))),
          TextButton(
              onPressed: n.shortReminderBusy ? null : n.scheduleShortReminders,
              child: Text(tr('إعادة محاولة التحديث', 'Retry scheduling')))
        ],
        TextButton.icon(
            onPressed: () => showShortReminderPreview(context, key),
            icon: const Icon(Icons.headphones),
            label: Text(tr('استماع إلى الصوت', 'Listen to sound'))),
      ],
      Padding(
          padding: const EdgeInsets.all(16),
          child: Text(tr(
              'قد تتأخر الإشعارات أو تصمت حسب أذونات الجهاز والصامت وعدم الإزعاج.',
              'Notifications may be delayed or silent depending on device permissions and sound settings.'))),
    ];
  }

  List<Widget> adhanPage() => [
        AnimatedBuilder(
          animation: PrayerNotificationService.instance,
          builder: (context, _) {
            final error = PrayerNotificationService.instance.prayerSchedulingError;
            if (error == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Semantics(liveRegion: true, child: Text(error)),
                TextButton(
                  onPressed: PrayerNotificationService.instance.retryPrayerScheduling,
                  child: Text(tr('إعادة محاولة جدولة الصلاة', 'Retry prayer scheduling')),
                ),
              ]),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(tr(
              'تُحسب تنبيهات الصلاة لكل يوم على حدة لليوم وستة أيام تالية. افتح التطبيق لتحديث الموقع والجدولة قبل انتهاء هذه المدة. إغلاقه مدة أطول قد يوقف تنبيهات الصلاة؛ هذه ليست جدولة دائمة في الخلفية.',
              'Prayer alerts are calculated separately for today and the next six days. Open the app to refresh location and scheduling before this window ends. Keeping it closed longer may stop prayer alerts; this is not permanent background renewal.')),
        ),
        SwitchListTile(
            title: Text(tr('التنبيهات', 'Notifications')),
            value: session.master.value.notifications,
            onChanged: (value) =>
                session.master.stage((settings: value, notifications: value))),
        choice(tr('نمط الصوت', 'Sound mode'), session.sound, {
          AdhanSoundMode.fullAdhan: tr('أذان كامل', 'Full adhan'),
          AdhanSoundMode.takbeerat: tr('تكبيرات', 'Takbeerat'),
          AdhanSoundMode.softBeep: tr('نغمة', 'Beep'),
          AdhanSoundMode.vibrateOnly: tr('اهتزاز', 'Vibrate'),
          AdhanSoundMode.silent: tr('صامت', 'Silent')
        }),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(tr(
              'إعدادات كل صلاة مستقلة. يظل مفتاح التنبيهات العام مطلوباً، ويعمل التنبيه المسبق عند تفعيله عموماً ولهذه الصلاة وبالدقائق المحددة أدناه. إيقاف أذان الصلاة يوقف تنبيهها المسبق أيضاً. لا تُحفظ التغييرات إلا عند الضغط على تطبيق.',
              'Each prayer has separate settings. The main notification switch still applies. Pre-reminders also require this prayer and the global pre-reminder switch, and use the minutes below. Disabling a prayer also disables its pre-reminder. Changes are saved only with Apply.')),
        ),
        for (final prayer in SettingsSession.prayers)
          ExpansionTile(
              key: ValueKey('prayer_settings_$prayer'),
              title: Text(tr('إعدادات صلاة $prayer', '$prayer settings')),
              subtitle: Text(session.prayerEnabled[prayer]!.value
                  ? tr('الأذان مفعّل لهذه الصلاة',
                      'Adhan enabled for this prayer')
                  : tr('الأذان متوقف لهذه الصلاة',
                      'Adhan disabled for this prayer')),
              children: [
                toggle(tr('أذان صلاة $prayer', '$prayer adhan'),
                    session.prayerEnabled[prayer]!),
                ListTile(
                    key: ValueKey('prayer_voice_$prayer'),
                    title: Text(tr('مؤذن صلاة $prayer', '$prayer muezzin')),
                    subtitle:
                        Text(getAdhanVoiceName(session.voices[prayer]!.value)),
                    onTap: () => showPrayerMuezzinDropdownPicker(
                        context, prayer,
                        selectedVoice: session.voices[prayer]!.value,
                        onStage: session.voices[prayer]!.stage)),
                toggle(
                    tr('التنبيه قبل صلاة $prayer', 'Reminder before $prayer'),
                    session.prePrayerEnabled[prayer]!),
              ]),
        ListTile(
            title: Text(tr('مؤذن لجميع الصلوات', 'Voice for all prayers')),
            onTap: () => showPrayerMuezzinDropdownPicker(context, 'الكل',
                    onStage: (value) {
                  for (final voice in session.voices.values) {
                    voice.stage(value);
                  }
                })),
        ListTile(
            title: Text(tr('صوت الإقامة', 'Iqamah voice')),
            subtitle: Text(getIqamahVoiceName(session.iqamahVoice.value)),
            onTap: () => showPrayerMuezzinDropdownPicker(
                context, 'إقامة الصلاة',
                isIqamah: true,
                selectedVoice: session.iqamahVoice.value,
                onStage: session.iqamahVoice.stage)),
        toggle(tr('التنبيه المسبق', 'Pre-adhan reminder'), session.pre),
        choice(tr('دقائق قبل الأذان', 'Minutes before adhan'),
            session.preMinutes, {
          for (final i in [5, 10, 15, 20, 30]) i: '$i'
        }),
        choice(tr('دقائق الإقامة', 'Iqamah minutes'), session.iqamahMinutes, {
          for (final i in [5, 10, 15, 20, 25, 30]) i: '$i'
        }),
        toggle(tr('قيام الليل', 'Qiyam reminder'), session.qiyam),
        choice(tr('دقائق قبل الفجر', 'Minutes before Fajr'),
            session.qiyamMinutes, {60: '60', 90: '90'}),
        toggle(tr('تذكير الجمعة', 'Friday reminder'), session.friday),
        toggle(tr('صوت الفجر', 'Distinct Fajr voice'), session.fajr),
        toggle(tr('دعاء الشعراوي', 'Sharawi dua'), session.sharawi),
        toggle(tr('تذكير كتم الرنين', 'Mute reminder'), session.silent),
        toggle(tr('تذكير السنن الرواتب', 'Sunan reminder'), session.sunan),
        toggle(tr('الظهور فوق التطبيقات', 'Overlay window'), session.overlay),
        toggle(tr('الهز للإيقاف', 'Shake to stop'), session.shake),
        toggle(tr('القلب للكتم', 'Flip to mute'), session.flip),
        toggle(tr('التسبيح بزر الصوت', 'Tasbih with volume button'),
            session.volume),
        toggle(tr('شريط المسبحة', 'Tasbih slider'), session.slider),
        ListTile(
            title: Text(tr('تجربة شاشة الأذان', 'Preview adhan screen')),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AdhanControlScreen(
                        prayerName: 'الظهر', autoPlay: false)))),
      ];
}
