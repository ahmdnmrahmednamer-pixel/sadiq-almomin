import 'package:flutter/foundation.dart';

class AppLogger {
  static void warn(String scope, Object error, [StackTrace? stack]) {
    if (kDebugMode) {
      debugPrint('[$scope] $error');
      if (stack != null) debugPrint('$stack');
    }
  }
}
