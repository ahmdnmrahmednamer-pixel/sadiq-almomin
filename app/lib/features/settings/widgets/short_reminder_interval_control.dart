import 'package:flutter/material.dart';
import '../../../core/notifications/prayer_notification_service.dart';

/// Stages a minute interval. No persistence or audio side effect before Apply.
class ShortReminderIntervalControl extends StatelessWidget {
  const ShortReminderIntervalControl(
      {super.key,
      required this.reminderKey,
      required this.label,
      required this.value,
      required this.onChanged,
      required this.translate,
      this.busy = false});
  final String reminderKey;
  final String label;
  final ShortReminderInterval value;
  final ValueChanged<ShortReminderInterval> onChanged;
  final String Function(String, String) translate;
  final bool busy;

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SwitchListTile(
          key: ValueKey('short_interval_enabled_$reminderKey'),
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          value: value.enabled,
          onChanged: busy
              ? null
              : (enabled) =>
                  onChanged((enabled: enabled, minutes: value.minutes)),
        ),
        Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            children: [
              Text(translate('كل ${value.minutes} دقيقة',
                  'Every ${value.minutes} minutes')),
              TextButton(
                  key: ValueKey('short_interval_edit_$reminderKey'),
                  onPressed: busy
                      ? null
                      : () async {
                          final minutes = await showDialog<int>(
                              context: context,
                              builder: (_) => _MinuteDialog(
                                  label: label,
                                  initial: value.minutes,
                                  translate: translate));
                          if (minutes != null && context.mounted)
                            onChanged(
                                (enabled: value.enabled, minutes: minutes));
                        },
                  child: Text(translate('إدخال المدة', 'Enter interval'))),
            ]),
        Semantics(
            container: true,
            excludeSemantics: true,
            slider: true,
            enabled: !busy,
            value:
                translate('${value.minutes} دقيقة', '${value.minutes} minutes'),
            increasedValue: value.minutes < 1440
                ? translate('${value.minutes + 1} دقيقة',
                    '${value.minutes + 1} minutes')
                : null,
            decreasedValue: value.minutes > 1
                ? translate('${value.minutes - 1} دقيقة',
                    '${value.minutes - 1} minutes')
                : null,
            onIncrease: busy || value.minutes == 1440
                ? null
                : () => onChanged(
                    (enabled: value.enabled, minutes: value.minutes + 1)),
            onDecrease: busy || value.minutes == 1
                ? null
                : () => onChanged(
                    (enabled: value.enabled, minutes: value.minutes - 1)),
            label: translate(
                '$label، المدة بالدقائق', '$label, interval in minutes'),
            child: Slider(
              key: ValueKey('short_interval_slider_$reminderKey'),
              value: value.minutes.toDouble(),
              min: 1,
              max: 1440,
              divisions: 1439,
              label: translate(
                  '${value.minutes} دقيقة', '${value.minutes} minutes'),
              semanticFormatterCallback: (minutes) => translate(
                  '${minutes.round()} دقيقة', '${minutes.round()} minutes'),
              onChanged: busy
                  ? null
                  : (minutes) => onChanged(
                      (enabled: value.enabled, minutes: minutes.round())),
            )),
      ]));
}

class _MinuteDialog extends StatefulWidget {
  const _MinuteDialog(
      {required this.label, required this.initial, required this.translate});
  final String label;
  final int initial;
  final String Function(String, String) translate;
  @override
  State<_MinuteDialog> createState() => _MinuteDialogState();
}

class _MinuteDialogState extends State<_MinuteDialog> {
  late final controller = TextEditingController(text: '${widget.initial}');
  String? error;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() {
    final normalized = String.fromCharCodes(
        controller.text.trim().runes.map((r) => r >= 0x660 && r <= 0x669
            ? r - 0x660 + 48
            : r >= 0x6f0 && r <= 0x6f9
                ? r - 0x6f0 + 48
                : r));
    final minutes = int.tryParse(normalized);
    if (minutes == null || minutes < 1 || minutes > 1440) {
      setState(() => error = widget.translate(
          'أدخل عدداً صحيحاً من 1 إلى 1440 دقيقة',
          'Enter a whole number from 1 to 1440 minutes'));
      return;
    }
    Navigator.pop(context, minutes);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: Text(widget.label),
        content: TextField(
          key: const ValueKey('short_interval_minutes_input'),
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
              errorMaxLines: 4,
              helperMaxLines: 2,
              labelText:
                  widget.translate('المدة بالدقائق', 'Interval in minutes'),
              helperText: widget.translate(
                  'من 1 إلى 1440 دقيقة', 'From 1 to 1440 minutes'),
              errorText: error),
          onSubmitted: (_) => submit(),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(widget.translate('إلغاء', 'Cancel'))),
          FilledButton(
              key: const ValueKey('short_interval_confirm'),
              onPressed: submit,
              child: Text(widget.translate('اختيار', 'Choose'))),
        ],
      );
}
