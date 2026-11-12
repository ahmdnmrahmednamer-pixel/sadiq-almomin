import 'dart:async';
import 'package:flutter/gestures.dart';

/// A gesture recognizer for Quranic Ayahs extending [TapGestureRecognizer] so that
/// it is fully supported by Flutter's [RenderParagraph] and semantics system:
/// - Normal single tap (ضغطة عادية): triggers [onTap] to play the Ayah with default audio.
/// - Long press (ضغط مطول): triggers [onLongPress] to open the full Ayah action sheet.
class AyahGestureRecognizer extends TapGestureRecognizer {
  AyahGestureRecognizer({
    super.debugOwner,
    this.onAyahTap,
    this.onAyahLongPress,
  }) {
    onTapDown = _handleTapDown;
    onTapUp = _handleTapUp;
    onTapCancel = _handleTapCancel;
  }

  GestureTapCallback? onAyahTap;
  GestureLongPressCallback? onAyahLongPress;

  Timer? _longPressTimer;
  bool _longPressTriggered = false;

  void _handleTapDown(TapDownDetails details) {
    _longPressTriggered = false;
    _longPressTimer?.cancel();
    _longPressTimer = Timer(kLongPressTimeout, () {
      _longPressTriggered = true;
      onAyahLongPress?.call();
    });
  }

  void _handleTapUp(TapUpDetails details) {
    final triggered = _longPressTriggered;
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _longPressTriggered = false;

    if (!triggered) {
      onAyahTap?.call();
    }
  }

  void _handleTapCancel() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _longPressTriggered = false;
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    super.dispose();
  }
}
