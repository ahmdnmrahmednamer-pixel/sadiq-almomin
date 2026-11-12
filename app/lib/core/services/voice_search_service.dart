import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_recognition_error.dart';

/// State of Voice Search
enum VoiceSearchStatus {
  idle,
  initializing,
  listening,
  done,
  error,
  permissionDenied,
}

/// Service managing Speech-to-Text for Quranic voice search using the device microphone.
class VoiceSearchService extends ChangeNotifier {
  VoiceSearchService._();
  static final VoiceSearchService instance = VoiceSearchService._();

  final SpeechToText _speech = SpeechToText();
  bool _isInitialized = false;
  VoiceSearchStatus _status = VoiceSearchStatus.idle;
  String _lastRecognizedWords = '';
  String _errorMessage = '';
  double _soundLevel = 0.0;
  String? _preferredArabicLocale;

  // Mock hook for headless testing environments
  static bool isTestMode = false;
  static String? testMockRecognizedWords;

  VoiceSearchStatus get status => _status;
  bool get isListening => _speech.isListening || (isTestMode && _status == VoiceSearchStatus.listening);
  bool get isAvailable => _isInitialized && _speech.isAvailable;
  String get lastRecognizedWords => _lastRecognizedWords;
  String get errorMessage => _errorMessage;
  double get soundLevel => _soundLevel;

  /// Initializes the speech recognition engine and validates microphone permissions.
  Future<bool> initialize() async {
    if (isTestMode) {
      _isInitialized = true;
      _status = VoiceSearchStatus.idle;
      notifyListeners();
      return true;
    }

    if (_isInitialized && _speech.isAvailable) {
      return true;
    }

    _status = VoiceSearchStatus.initializing;
    notifyListeners();

    try {
      // 1. Check & request microphone permission
      final permStatus = await Permission.microphone.status;
      if (!permStatus.isGranted) {
        final requestResult = await Permission.microphone.request();
        if (!requestResult.isGranted) {
          _status = VoiceSearchStatus.permissionDenied;
          _errorMessage = 'يرجى منح صلاحية الميكروفون لاستخدام البحث الصوتي القرآني';
          notifyListeners();
          return false;
        }
      }

      // 2. Initialize SpeechToText
      final available = await _speech.initialize(
        onStatus: _handleStatus,
        onError: _handleError,
        debugLogging: kDebugMode,
      );

      _isInitialized = available;

      if (available) {
        // Detect best Arabic locale
        try {
          final locales = await _speech.locales();
          for (final loc in locales) {
            final id = loc.localeId.toLowerCase();
            if (id.startsWith('ar_eg') || id.startsWith('ar-eg')) {
              _preferredArabicLocale = loc.localeId;
              break;
            } else if (id.startsWith('ar')) {
              _preferredArabicLocale ??= loc.localeId;
            }
          }
        } catch (_) {}
        _preferredArabicLocale ??= 'ar-EG';
        _status = VoiceSearchStatus.idle;
      } else {
        _status = VoiceSearchStatus.error;
        _errorMessage = 'خدمة التعرف الصوتي غير متاحة حالياً على هذا الجهاز';
      }

      notifyListeners();
      return available;
    } catch (e) {
      _isInitialized = false;
      _status = VoiceSearchStatus.error;
      _errorMessage = 'تعذّر تشغيل الميكروفون أو التعرف الصوتي: $e';
      notifyListeners();
      return false;
    }
  }

  /// Starts listening to voice input in Arabic.
  Future<void> startListening({
    required void Function(String words, bool isFinal) onResult,
    void Function(double level)? onSoundLevel,
    void Function(String error)? onError,
  }) async {
    _lastRecognizedWords = '';
    _errorMessage = '';
    _soundLevel = 0.0;

    if (isTestMode) {
      _status = VoiceSearchStatus.listening;
      notifyListeners();
      final words = testMockRecognizedWords ?? 'قل هو الله احد';
      _lastRecognizedWords = words;
      onResult(words, true);
      _status = VoiceSearchStatus.done;
      notifyListeners();
      return;
    }

    if (!_isInitialized || !_speech.isAvailable) {
      final ok = await initialize();
      if (!ok) {
        onError?.call(_errorMessage);
        return;
      }
    }

    _status = VoiceSearchStatus.listening;
    notifyListeners();

    try {
      await _speech.listen(
        onResult: (SpeechRecognitionResult result) {
          final words = result.recognizedWords.trim();
          _lastRecognizedWords = words;
          notifyListeners();
          onResult(words, result.finalResult);
          if (result.finalResult) {
            _status = VoiceSearchStatus.done;
            notifyListeners();
          }
        },
        localeId: _preferredArabicLocale ?? 'ar-EG',
        listenFor: const Duration(seconds: 25),
        pauseFor: const Duration(seconds: 3),
        onSoundLevelChange: (level) {
          _soundLevel = level;
          onSoundLevel?.call(level);
          notifyListeners();
        },
        cancelOnError: true,
        partialResults: true,
      );
    } catch (e) {
      _status = VoiceSearchStatus.error;
      _errorMessage = 'حدث خطأ أثناء الاستماع: $e';
      onError?.call(_errorMessage);
      notifyListeners();
    }
  }

  /// Stops listening and returns captured words.
  Future<String> stopListening() async {
    if (isTestMode) {
      _status = VoiceSearchStatus.done;
      notifyListeners();
      return _lastRecognizedWords;
    }

    try {
      await _speech.stop();
    } catch (_) {}
    _status = VoiceSearchStatus.done;
    notifyListeners();
    return _lastRecognizedWords;
  }

  /// Cancels current voice listening session.
  Future<void> cancelListening() async {
    if (isTestMode) {
      _status = VoiceSearchStatus.idle;
      _lastRecognizedWords = '';
      notifyListeners();
      return;
    }

    try {
      await _speech.cancel();
    } catch (_) {}
    _status = VoiceSearchStatus.idle;
    _lastRecognizedWords = '';
    notifyListeners();
  }

  void _handleStatus(String status) {
    if (status == 'listening') {
      _status = VoiceSearchStatus.listening;
    } else if (status == 'notListening' || status == 'done') {
      if (_status == VoiceSearchStatus.listening) {
        _status = VoiceSearchStatus.done;
      }
    }
    notifyListeners();
  }

  void _handleError(SpeechRecognitionError error) {
    _status = VoiceSearchStatus.error;
    _errorMessage = _translateError(error.errorMsg);
    notifyListeners();
  }

  String _translateError(String original) {
    final lower = original.toLowerCase();
    if (lower.contains('network') || lower.contains('timeout')) {
      return 'تعذر الاتصال بخدمة التعرف الصوتي، يرجى التحقق من الشبكة';
    } else if (lower.contains('permission') || lower.contains('denied')) {
      return 'صلاحية الميكروفون مرفوضة، يرجى تفعيلها من إعدادات الهاتف';
    } else if (lower.contains('no match') || lower.contains('speech_timeout')) {
      return 'لم يتم تمييز أي صوت، يرجى الاقتراب من الميكروفون والمحاولة ثانية';
    }
    return 'تعذر التعرف على الصوت ($original)';
  }

  /// Resets test mode
  static void resetTestMode() {
    isTestMode = false;
    testMockRecognizedWords = null;
  }
}
