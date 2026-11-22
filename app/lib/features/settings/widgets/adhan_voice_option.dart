import 'package:flutter/material.dart';

/// One voice with independent listening, assignment and download actions.
class AdhanVoiceOption extends StatelessWidget {
  final String name;
  final String? semanticName;
  final String? sourceDetails;
  final String? assignmentUnavailableMessage;
  final String? unavailableReason;
  final String? assignmentUnavailableReason;
  final bool selected;
  final bool playing;
  final bool downloaded;
  final bool downloading;
  final VoidCallback onListen;
  final VoidCallback onAssign;
  final VoidCallback onDownload;

  const AdhanVoiceOption({
    super.key,
    required this.name,
    this.semanticName,
    this.sourceDetails,
    this.assignmentUnavailableMessage,
    this.unavailableReason,
    this.assignmentUnavailableReason,
    required this.selected,
    required this.playing,
    required this.downloaded,
    required this.downloading,
    required this.onListen,
    required this.onAssign,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                  child: Semantics(
                      label: semanticName,
                    container: semanticName != null,
                      excludeSemantics: semanticName != null,
                      child: Text(name,
                          style:
                              const TextStyle(fontWeight: FontWeight.bold)))),
              if (sourceDetails != null)
                IconButton(
                  tooltip: 'معلومات المصدر',
                  icon: const Icon(Icons.info_outline),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('معلومات التسجيل'),
                      content: SingleChildScrollView(
                          child: SelectableText(sourceDetails!)),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('إغلاق'))
                      ],
                    ),
                  ),
                ),
              if (selected)
                const Icon(Icons.check_circle_outline,
                    semanticLabel: 'المؤذن المعين'),
            ]),
            if (unavailableReason != null)
              Semantics(liveRegion: true, child: Text(unavailableReason!)),
            if (unavailableReason == null &&
                assignmentUnavailableReason != null)
              Text(
                  assignmentUnavailableMessage ?? assignmentUnavailableReason!),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  onPressed: unavailableReason == null ? onListen : null,
                  icon: Icon(playing ? Icons.stop : Icons.play_arrow),
                  label: Text(playing ? 'إيقاف' : 'استماع'),
                ),
                FilledButton.icon(
                  onPressed: unavailableReason == null &&
                          assignmentUnavailableReason == null
                      ? onAssign
                      : null,
                  icon: const Icon(Icons.check),
                  label: const Text('تعيين'),
                ),
                if (!downloaded)
                  TextButton.icon(
                    onPressed: downloading || unavailableReason != null
                        ? null
                        : onDownload,
                    icon:
                        Icon(downloading ? Icons.downloading : Icons.download),
                    label: Text(downloading ? 'جار التحميل' : 'تحميل'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
