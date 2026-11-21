import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// One keyboard focus stop for a continuous run of verses.
/// ArrowDown/ArrowUp move the active verse, Enter or the Menu key opens its
/// options, Space plays or stops it. Tab and Shift+Tab keep their normal meaning,
/// and a fresh arrow press at either end is released to the normal focus traversal.
class AyahKeyboardFocus extends StatefulWidget {
  const AyahKeyboardFocus({
    super.key,
    required this.segmentLengths,
    required this.onOpen,
    required this.onPlay,
    required this.builder,
    this.debugLabel = 'reader-verses',
    this.initialIndex,
  });

  /// Verse to focus and scroll into view when first shown (for example a saved bookmark).
  final int? initialIndex;

  /// UTF-16 length of each verse (text plus number marker) inside the paragraph.
  final List<int> segmentLengths;
  final void Function(int index) onOpen;
  final void Function(int index) onPlay;
  final String debugLabel;

  /// Builds the paragraph. [activeIndex] is the verse to tint while focused, or null.
  final Widget Function(BuildContext context, int? activeIndex, Key paragraphKey) builder;

  @override
  State<AyahKeyboardFocus> createState() => _AyahKeyboardFocusState();
}

class _AyahKeyboardFocusState extends State<AyahKeyboardFocus> {
  late final FocusNode _focus = FocusNode(debugLabel: widget.debugLabel);
  final GlobalKey _paragraphKey = GlobalKey();
  int _active = 0;

  @override
  void initState() {
    super.initState();
    final start = widget.initialIndex;
    if (start != null && start >= 0 && start < widget.segmentLengths.length) {
      _active = start;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
    _focus.addListener(() {
      if (!mounted) return;
      setState(() {});
      if (_focus.hasFocus) WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  int get _last => widget.segmentLengths.length - 1;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (widget.segmentLengths.isEmpty || event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowUp) {
      final next = _active + (key == LogicalKeyboardKey.arrowDown ? 1 : -1);
      // A fresh press at either end hands focus to the next control; a held key stops at the end.
      if (next < 0 || next > _last) return event is KeyRepeatEvent ? KeyEventResult.handled : KeyEventResult.ignored;
      setState(() => _active = next);
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final index = _active.clamp(0, _last);
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter || key == LogicalKeyboardKey.contextMenu) {
      widget.onOpen(index);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space) {
      widget.onPlay(index);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _reveal() {
    final render = _paragraphKey.currentContext?.findRenderObject();
    if (render is! RenderParagraph || widget.segmentLengths.isEmpty) return;
    final index = _active.clamp(0, _last);
    var start = 0;
    for (var i = 0; i < index; i++) {
      start += widget.segmentLengths[i];
    }
    final boxes = render.getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: start + widget.segmentLengths[index]));
    if (boxes.isEmpty) return;
    // Reveal the whole verse, not just its first line, when it fits in the viewport.
    var rect = boxes.first.toRect();
    for (final b in boxes.skip(1)) {
      rect = rect.expandToInclude(b.toRect());
    }
    render.showOnScreen(rect: rect.inflate(24), duration: const Duration(milliseconds: 120));
  }

  @override
  Widget build(BuildContext context) {
    if (_active > _last && _last >= 0) _active = 0;
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: widget.builder(context, _focus.hasFocus ? _active : null, _paragraphKey),
    );
  }
}
