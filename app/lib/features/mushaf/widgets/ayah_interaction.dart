import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// One focus target for a complete verse, including its visual verse number.
/// Gesture callbacks also expose the same actions to assistive technology.
class AyahInteraction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool isPlaying;
  final double? order;
  final Widget child;

  const AyahInteraction({
    super.key,
    required this.label,
    required this.onTap,
    required this.onLongPress,
    required this.child,
    this.isPlaying = false,
    this.order,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      selected: isPlaying,
      sortKey: order == null ? null : OrdinalSortKey(order!),
      label: label,
      hint: isPlaying
          ? 'اضغط مرتين لإيقاف التلاوة، واضغط مطولاً لخيارات الآية'
          : 'اضغط مرتين للاستماع بصوت القارئ المختار، واضغط مطولاً لخيارات الآية',
      onTap: onTap,
      onLongPress: onLongPress,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: onTap,
          onLongPress: onLongPress,
          child: child,
        ),
      ),
    );
  }
}
