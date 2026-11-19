import 'package:flutter/material.dart';

/// One voice with independent listening, assignment and download actions.
class AdhanVoiceOption extends StatelessWidget {
  final String name;
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
                  child: Text(name,
                      style: const TextStyle(fontWeight: FontWeight.bold))),
              if (selected)
                const Icon(Icons.check_circle_outline,
                    semanticLabel: 'المؤذن المعين'),
            ]),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  onPressed: onListen,
                  icon: Icon(playing ? Icons.stop : Icons.play_arrow),
                  label: Text(playing ? 'إيقاف' : 'استماع'),
                ),
                FilledButton.icon(
                  onPressed: onAssign,
                  icon: const Icon(Icons.check),
                  label: const Text('تعيين'),
                ),
                if (!downloaded)
                  TextButton.icon(
                    onPressed: downloading ? null : onDownload,
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
