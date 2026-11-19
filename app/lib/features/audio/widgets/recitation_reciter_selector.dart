import 'package:flutter/material.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/theme/app_theme.dart';

/// Two dependent selectors. Browsing a style never silently changes the saved
/// reciter or starts playback: the user still chooses a reciter explicitly.
class RecitationReciterSelector extends StatefulWidget {
  const RecitationReciterSelector({
    super.key,
    required this.reciter,
    required this.onChanged,
    required this.onPreview,
    this.isPreviewing = false,
  });

  final ReciterInfo reciter;
  final ValueChanged<ReciterInfo> onChanged;
  final VoidCallback onPreview;
  final bool isPreviewing;

  @override
  State<RecitationReciterSelector> createState() =>
      _RecitationReciterSelectorState();
}

class _RecitationReciterSelectorState extends State<RecitationReciterSelector> {
  late String _style = widget.reciter.style;

  @override
  void didUpdateWidget(covariant RecitationReciterSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reciter.id != widget.reciter.id) {
      _style = widget.reciter.style;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Derive categories from the real catalog, including less common styles.
    final styles =
        SettingsService.availableReciters.map((r) => r.style).toSet();
    final reciters = SettingsService.availableReciters
        .where((r) => r.style == _style)
        .toList();
    final selectedId = reciters.any((r) => r.id == widget.reciter.id)
        ? widget.reciter.id
        : null;

    String label(ReciterInfo reciter) =>
        reciter.nameAr.endsWith(' (${reciter.style})')
            ? reciter.nameAr
                .substring(0, reciter.nameAr.length - reciter.style.length - 3)
            : reciter.nameAr;
    final textStyle = TextStyle(
      fontFamily: 'Amiri',
      fontSize: 14.5,
      fontWeight: FontWeight.w700,
      color: Theme.of(context).colorScheme.onSurface,
    );
    Widget selectedText(String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(text),
        );

    InputDecoration decoration(String label, IconData icon) => InputDecoration(
          labelText: label,
          prefixIcon: ExcludeSemantics(child: Icon(icon)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('recitation_style_$_style'),
          initialValue: _style,
          isExpanded: true,
          isDense: false,
          itemHeight: null,
          style: textStyle,
          decoration: decoration('نوع التلاوة', Icons.library_music_outlined),
          selectedItemBuilder: (_) =>
              styles.map((_) => selectedText(_style)).toList(),
          items: styles
              .map((style) => DropdownMenuItem(
                    value: style,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(style),
                    ),
                  ))
              .toList(),
          onChanged: (style) {
            if (style != null) setState(() => _style = style);
          },
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          // FormField.initialValue is only read on creation. Recreate when
          // either dependency changes, never show a stale reciter as selected.
          key: ValueKey('recitation_reciter_${_style}_${widget.reciter.id}'),
          initialValue: selectedId,
          isExpanded: true,
          isDense: false,
          itemHeight: null,
          style: textStyle,
          decoration: decoration('القارئ', Icons.record_voice_over_rounded),
          hint: const Text('اختر القارئ'),
          selectedItemBuilder: (_) =>
              reciters.map((_) => selectedText(label(widget.reciter))).toList(),
          items: reciters
              .map((reciter) => DropdownMenuItem(
                    value: reciter.id,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(label(reciter)),
                    ),
                  ))
              .toList(),
          onChanged: (id) {
            if (id != null) {
              widget.onChanged(reciters.firstWhere((r) => r.id == id));
            }
          },
        ),
        const SizedBox(height: 10),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.icon(
            key: const ValueKey('recitation_preview_button'),
            style: FilledButton.styleFrom(
              backgroundColor: widget.isPreviewing
                  ? Colors.red.shade700
                  : AppColors.primaryGreen,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            onPressed: selectedId != null || widget.isPreviewing
                ? widget.onPreview
                : null,
            icon: Icon(widget.isPreviewing
                ? Icons.stop_circle_outlined
                : Icons.play_circle_outline),
            label: Text(widget.isPreviewing ? 'إيقاف العينة' : 'استماع عينة'),
          ),
        ),
      ],
    );
  }
}
