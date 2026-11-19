import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/models/surah.dart';
import '../../../core/models/ayah.dart';
import '../../../core/services/tafsir_service.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/audio/ayah_audio_player.dart';
import '../../../core/ui/app_dropdown_field.dart';

class TafsirViewerSheet extends StatefulWidget {
  final Surah surah;
  final Ayah initialAyah;

  const TafsirViewerSheet({
    super.key,
    required this.surah,
    required this.initialAyah,
  });

  static void show(BuildContext context, {required Surah surah, required Ayah ayah}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (_) => TafsirViewerSheet(surah: surah, initialAyah: ayah),
    );
  }

  @override
  State<TafsirViewerSheet> createState() => _TafsirViewerSheetState();
}

class _TafsirViewerSheetState extends State<TafsirViewerSheet> {
  late int _currentAyahNumber;
  late String _selectedEditionId;
  int _requestVersion = 0;
  String? _loadError;
  double _fontSize = 16.0;
  bool _isLoading = true;
  TafsirResult? _tafsirResult;

  @override
  void initState() {
    super.initState();
    _currentAyahNumber = widget.initialAyah.ayahNumber;
    _selectedEditionId = TafsirService.getEdition(SettingsService.instance.defaultTafsirEdition).id;
    _fontSize = (SettingsService.instance.mushafFontSize * 0.7).clamp(14.0, 26.0);
    _loadTafsir();
  }

  void _loadTafsir() async {
    final version = ++_requestVersion;
    final ayah = _currentAyahNumber;
    final edition = _selectedEditionId;
    setState(() { _isLoading = true; _loadError = null; _tafsirResult = null; });
    try {
      final res = await TafsirService.getTafsir(surahId:widget.surah.id,
        ayahNumber:ayah, editionId:edition);
      if (!mounted || version != _requestVersion) return;
      setState(() { _tafsirResult = res; _isLoading = false; });
    } catch (_) {
      if (!mounted || version != _requestVersion) return;
      setState(() { _loadError = 'تعذر تحميل التفسير. حاول مرة أخرى.'; _isLoading = false; });
    }
  }

  void _goToPreviousAyah() {
    if (_currentAyahNumber > 1) {
      setState(() => _currentAyahNumber--);
      _loadTafsir();
    }
  }

  void _goToNextAyah() {
    if (_currentAyahNumber < widget.surah.ayahCount) {
      setState(() => _currentAyahNumber++);
      _loadTafsir();
    }
  }

  void _copyTafsir() {
    if (_tafsirResult == null || !_tafsirResult!.hasSourceText) return;
    final text = _tafsirResult!.formatForShare(widget.surah.nameAr);
    Clipboard.setData(ClipboardData(text: text)).catchError((_) {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم نسخ النص'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _shareTafsir() {
    if (_tafsirResult == null || !_tafsirResult!.hasSourceText) return;
    final text = _tafsirResult!.formatForShare(widget.surah.nameAr);
    try {
      Share.share(text);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mediaQuery = MediaQuery.of(context);
    final keyboardBottom = mediaQuery.viewInsets.bottom;
    final availableHeight =
        (mediaQuery.size.height - keyboardBottom).clamp(0.0, mediaQuery.size.height);
    final isCompactHeight = availableHeight < 620;
    final sheetHeight = keyboardBottom > 0
        ? (availableHeight - 8.0).clamp(0.0, availableHeight)
        : mediaQuery.size.height * 0.88;

    return Directionality(
      textDirection: SettingsService.instance.textDirection,
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboardBottom),
        child: Container(
          height: sheetHeight,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1B201E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: isCompactHeight
                    ? const EdgeInsets.only(top: 6, bottom: 4)
                    : const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Sheet Top Header
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: isCompactHeight ? 0 : 4,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final textScale = MediaQuery.textScalerOf(context).scale(1.0);
                  final isCompact = constraints.maxWidth < 520 || textScale >= 1.35;
                  final titleRow = Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primaryGreen.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.menu_book_rounded, color: AppColors.primaryGreen, size: 20),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            'سورة ${widget.surah.nameAr} — الآية $_currentAyahNumber',
                            softWrap: true,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                      ),
                    ],
                  );
                  final secondaryActions = _buildHeaderSecondaryActions();
                  final closeButton = IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'إغلاق',
                    onPressed: () => Navigator.pop(context),
                  );
                  if (!isCompact) {
                    return Row(
                      children: [
                        Expanded(child: titleRow),
                        const SizedBox(width: 8),
                        ...secondaryActions,
                        closeButton,
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [Expanded(child: titleRow), closeButton],
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Wrap(spacing: 4, runSpacing: 4, children: secondaryActions),
                      ),
                    ],
                  );
                },
              ),
            ),

            if (!isCompactHeight) ...[
              _buildDropdownSelectors(),
              const Divider(height: 1),
            ],

            // Content Area
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
                  : ListView(
                      padding: EdgeInsets.only(
                        top: isCompactHeight ? 0 : 16,
                        bottom: 16,
                      ),
                      children: [
                        if (isCompactHeight) ...[
                          _buildDropdownSelectors(),
                          const Divider(height: 1),
                          const SizedBox(height: 16),
                        ],
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Ayah Text Container
                              Semantics(
                                container: true,
                                label: 'نص الآية رقم $_currentAyahNumber: ${_tafsirResult?.ayahText ?? ""}',
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF232A26) : const Color(0xFFF9F7F1),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: AppColors.accentGold.withValues(alpha: 0.6), width: 1.2),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        _tafsirResult?.ayahText ?? '',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 19,
                                          height: 2.0,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.accentGold,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          TextButton.icon(
                                            style: TextButton.styleFrom(
                                              foregroundColor: AppColors.primaryGreen,
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            ),
                                            icon: const Icon(Icons.play_circle_outline, size: 18),
                                            label: const Text('استمع للآية', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                            onPressed: () {
                                              AyahAudioPlayer.instance.playAyah(
                                                context,
                                                widget.surah.id,
                                                _currentAyahNumber,
                                                surahName: widget.surah.nameAr,
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),

                              // Edition details card
                              Row(
                                children: [
                                  const Icon(Icons.auto_stories, color: AppColors.secondaryGreen, size: 18),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _tafsirResult?.editionName ?? '',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.secondaryGreen),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'تأليف: ${_tafsirResult?.author ?? ""}',
                                style: const TextStyle(fontSize: 11, color: AppColors.mutedText),
                              ),
                              const SizedBox(height: 12),

                              // Exegesis Content Text
                              Semantics(
                                container: true,
                                label: 'شرح التفسير: ${_tafsirResult?.tafsirText ?? ""}',
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Text(
                                    _loadError ?? _tafsirResult?.tafsirText ?? '',
                                    textAlign: TextAlign.justify,
                                    style: TextStyle(
                                      fontSize: _fontSize,
                                      height: 1.9,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),

            // Bottom Navigation: Previous Ayah / Next Ayah
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isCompactHeight || mediaQuery.textScaler.scale(1.0) >= 1.25
                    ? 4
                    : 16,
                vertical: isCompactHeight ? 2 : 8,
              ),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E2522) : Colors.grey.shade50,
                border: Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
              ),
              child: SafeArea(
                top: false,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
                    final useCompactFooter = constraints.maxWidth < 320 || textScale >= 1.25;
                    final footerButtonStyle = TextButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        horizontal: useCompactFooter ? 2 : 6,
                        vertical: useCompactFooter ? 2 : 4,
                      ),
                      minimumSize: const Size(48, 48),
                      tapTargetSize: MaterialTapTargetSize.padded,
                    );
                    final prevButton = _buildFooterNavButton(
                      label: 'الآية السابقة',
                      icon: Icons.arrow_back_ios,
                      iconAtStart: true,
                      constrainLabel: useCompactFooter,
                      style: footerButtonStyle,
                      onPressed: _currentAyahNumber > 1 ? _goToPreviousAyah : null,
                    );
                    final counterText = Text(
                      'الآية $_currentAyahNumber من ${widget.surah.ayahCount}',
                      textAlign: TextAlign.center,
                      softWrap: true,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    );
                    final nextButton = _buildFooterNavButton(
                      label: 'الآية التالية',
                      icon: Icons.arrow_back_ios,
                      iconAtStart: false,
                      constrainLabel: useCompactFooter,
                      style: footerButtonStyle,
                      onPressed: _currentAyahNumber < widget.surah.ayahCount ? _goToNextAyah : null,
                    );
                    if (!useCompactFooter) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          prevButton,
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: counterText,
                            ),
                          ),
                          nextButton,
                        ],
                      );
                    }
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        counterText,
                        SizedBox(height: isCompactHeight ? 2 : 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(child: prevButton),
                            const SizedBox(width: 4),
                            Expanded(child: nextButton),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildDropdownSelectors() {
    // Dropdown Selector for Tafsir Edition + Ayah Selector (Phase 4 Dropdown Rule)
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: AppDropdownField<String>(
              label: 'التفسير',
              value: _selectedEditionId,
              dense: true,
              prefixIcon: Icons.auto_stories_rounded,
              options: TafsirService.availableEditions
                  .map((ed) => AppDropdownOption<String>(
                        value: ed.id,
                        label: ed.nameAr,
                      ))
                  .toList(),
              onChanged: (val) {
                setState(() => _selectedEditionId = val);
                _loadTafsir();
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: AppDropdownField<int>(
              label: 'رقم الآية',
              value: _currentAyahNumber,
              dense: true,
              options: List.generate(
                widget.surah.ayahCount,
                (idx) => AppDropdownOption<int>(
                  value: idx + 1,
                  label: 'آية ${idx + 1}',
                ),
              ),
              onChanged: (val) {
                setState(() => _currentAyahNumber = val);
                _loadTafsir();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterNavButton({
    required String label,
    required IconData icon,
    required bool iconAtStart,
    required bool constrainLabel,
    required ButtonStyle style,
    required VoidCallback? onPressed,
  }) {
    final textWidget = Text(
      label,
      softWrap: true,
      textAlign: TextAlign.center,
    );
    final labelChild = constrainLabel ? Flexible(child: textWidget) : textWidget;
    final iconWidget = Icon(icon, size: 14);
    final gap = SizedBox(width: constrainLabel ? 2 : 4);
    final children = iconAtStart
        ? <Widget>[iconWidget, gap, labelChild]
        : <Widget>[
            labelChild,
            gap,
            Directionality(
              textDirection: TextDirection.ltr,
              child: iconWidget,
            ),
          ];
    return TextButton(
      style: style,
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: children,
      ),
    );
  }

  List<Widget> _buildHeaderSecondaryActions() {
    return [
      IconButton(
        icon: const Icon(Icons.format_size, size: 20),
        tooltip: 'تغيير حجم خط التفسير',
        onPressed: () {
          setState(() {
            _fontSize = _fontSize >= 24.0 ? 14.0 : _fontSize + 2.0;
          });
        },
      ),
      IconButton(
        icon: const Icon(Icons.copy_rounded, size: 20),
        tooltip: 'نسخ التفسير',
        onPressed: _copyTafsir,
      ),
      IconButton(
        icon: const Icon(Icons.share_rounded, size: 20),
        tooltip: 'مشاركة التفسير',
        onPressed: _shareTafsir,
      ),
    ];
  }
}
