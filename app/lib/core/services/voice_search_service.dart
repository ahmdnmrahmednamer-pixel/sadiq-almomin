import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_recognition_error.dart';

enum VoiceSearchStatus {
  idle,
  initializing,
  listening,
  done,
  error,
  permissionDenied
}

/// Device speech recognition for Quran search. Native operations are ordered;
/// consumers belong to one session and are retired by cancellation or retry.
class VoiceSearchService extends ChangeNotifier {
  VoiceSearchService._();
  static final VoiceSearchService instance = VoiceSearchService._();
  final SpeechToText _speech = SpeechToText();
  bool _isInitialized = false;
  VoiceSearchStatus _status = VoiceSearchStatus.idle;
  String _lastRecognizedWords = '';
  String _errorMessage = '';
  double _soundLevel = 0;
  String? _preferredArabicLocale;
  int _generation = 0;
  int? _activeGeneration;
  void Function(String error)? _activeError;
  Future<bool>? _initializing;
  int? _initializingGeneration;
  Future<void> _nativeTail = Future.value();

  static bool isTestMode = false;
  static String? testMockRecognizedWords;
  VoiceSearchStatus get status => _status;
  bool get isListening =>
      _activeGeneration == _generation &&
      (_speech.isListening ||
          (isTestMode && _status == VoiceSearchStatus.listening));
  bool get isAvailable => _isInitialized && _speech.isAvailable;
  String get lastRecognizedWords => _lastRecognizedWords;
  String get errorMessage => _errorMessage;
  double get soundLevel => _soundLevel;

  Future<void> _ordered(Future<void> Function() operation) {
    final result = _nativeTail.then((_) => operation());
    _nativeTail = result.catchError((_) {});
    return result;
  }

  bool _current(int generation) => generation == _generation;
  bool _active(int generation) =>
      _current(generation) && _activeGeneration == generation;

  Future<bool> initialize() {
    if (isTestMode) {
      _isInitialized = true;
      _status = VoiceSearchStatus.idle;
      notifyListeners();
      return Future.value(true);
    }
    if (_isInitialized && _speech.isAvailable) return Future.value(true);
    if (_initializing != null) return _initializing!;
    _initializingGeneration = _generation;
    return _initializing = _initialize(_generation).whenComplete(() {
      _initializing = null;
      _initializingGeneration = null;
    });
  }

  Future<bool> _initialize(int generation) async {
    _status = VoiceSearchStatus.initializing;
    notifyListeners();
    try {
      final permission = await Permission.microphone.status;
      if (!permission.isGranted) {
        if (!_current(generation)) return false;
        final requested = await Permission.microphone.request();
        if (!requested.isGranted) {
          if (_current(generation)) {
            _status = VoiceSearchStatus.permissionDenied;
            _errorMessage =
                'يرجى منح صلاحية الميكروفون لاستخدام البحث الصوتي القرآني';
            notifyListeners();
          }
          return false;
        }
      }
      if (!_current(generation)) return false;
      final available = await _speech.initialize(
        onStatus: _handleStatus,
        onError: _handleError,
        debugLogging: kDebugMode,
      );
      _isInitialized = available;
      if (available) {
        try {
          final locales = await _speech.locales();
          for (final locale in locales) {
            final id = locale.localeId.toLowerCase();
            if (id.startsWith('ar_eg') || id.startsWith('ar-eg')) {
              _preferredArabicLocale = locale.localeId;
              break;
            }
            if (id.startsWith('ar')) _preferredArabicLocale ??= locale.localeId;
          }
        } catch (_) {}
        _preferredArabicLocale ??= 'ar-EG';
      }
      if (_current(generation)) {
        _status = available ? VoiceSearchStatus.idle : VoiceSearchStatus.error;
        if (!available)
          _errorMessage = 'خدمة التعرف الصوتي غير متاحة حالياً على هذا الجهاز';
        notifyListeners();
      }
      return available;
    } catch (e) {
      _isInitialized = false;
      if (_current(generation)) {
        _status = VoiceSearchStatus.error;
        _errorMessage = 'تعذّر تشغيل الميكروفون أو التعرف الصوتي: $e';
        notifyListeners();
      }
      return false;
    }
  }

  Future<void> startListening({
    required void Function(String words, bool isFinal) onResult,
    void Function(double level)? onSoundLevel,
    void Function(String error)? onError,
  }) async {
    final generation = ++_generation;
    _activeGeneration = null;
    _activeError = null;
    _lastRecognizedWords = '';
    _errorMessage = '';
    _soundLevel = 0;
    if (isTestMode) {
      _activeGeneration = generation;
      _status = VoiceSearchStatus.listening;
      notifyListeners();
      if (!_active(generation)) return;
      final words = testMockRecognizedWords ?? 'قل هو الله احد';
      _lastRecognizedWords = words;
      onResult(words, true);
      if (_active(generation)) {
        _status = VoiceSearchStatus.done;
        _activeGeneration = null;
        notifyListeners();
      }
      return;
    }
    if (!_isInitialized || !_speech.isAvailable) {
      final initializingGeneration = _initializingGeneration ?? generation;
      var ok = await initialize();
      if (!_current(generation)) return;
      // A shared check can end early after its old consumer was canceled.
      // Retry once for the latest owner, without reviving the old request.
      if (!ok && initializingGeneration != generation) {
        ok = await initialize();
        if (!_current(generation)) return;
      }
      if (!ok) {
        onError?.call(_errorMessage);
        return;
      }
    }
    if (!_current(generation)) return;
    try {
      await _ordered(() async {
        if (!_current(generation)) return;
        // Retry must finish ending the old native listen before starting a new
        // one. A late completion of an older Stop/Cancel cannot cut it off.
        await _speech.cancel();
        if (!_current(generation)) return;
        _activeGeneration = generation;
        _activeError = onError;
        _status = VoiceSearchStatus.listening;
        notifyListeners();
        if (!_active(generation)) return;
        await _speech.listen(
          onResult: (SpeechRecognitionResult result) {
            if (!_active(generation)) return;
            final words = result.recognizedWords.trim();
            _lastRecognizedWords = words;
            if (result.finalResult) _status = VoiceSearchStatus.done;
            notifyListeners();
            if (!_active(generation)) return;
            onResult(words, result.finalResult);
          },
          listenOptions: SpeechListenOptions(
            localeId: _preferredArabicLocale ?? 'ar-EG',
            listenFor: const Duration(seconds: 25),
            pauseFor: const Duration(seconds: 3),
            cancelOnError: true,
            partialResults: true,
          ),
          onSoundLevelChange: (level) {
            if (!_active(generation)) return;
            _soundLevel = level;
            onSoundLevel?.call(level);
            if (_active(generation)) notifyListeners();
          },
        );
      });
    } catch (e) {
      if (!_current(generation)) return;
      _status = VoiceSearchStatus.error;
      _errorMessage = 'حدث خطأ أثناء الاستماع: $e';
      _activeGeneration = null;
      _activeError = null;
      onError?.call(_errorMessage);
      if (_current(generation)) notifyListeners();
    }
  }

  Future<String> stopListening() async {
    final generation =
        _activeGeneration == _generation ? _generation : ++_generation;
    if (!isTestMode) {
      try {
        await _ordered(() => _speech.stop());
      } catch (e) {
        if (_current(generation)) _handleStopFailure(e);
        return _lastRecognizedWords;
      }
    }
    if (_current(generation)) {
      _activeGeneration = null;
      _activeError = null;
      _status = VoiceSearchStatus.done;
      notifyListeners();
    }
    return _lastRecognizedWords;
  }

  Future<void> cancelListening() async {
    final generation = ++_generation;
    _activeGeneration = null;
    _activeError = null;
    _lastRecognizedWords = '';
    _soundLevel = 0;
    _status = VoiceSearchStatus.idle;
    notifyListeners();
    if (!isTestMode) {
      try {
        await _ordered(() => _speech.cancel());
      } catch (e) {
        if (_current(generation)) _handleStopFailure(e);
      }
    }
  }

  void _handleStopFailure(Object error) {
    _status = VoiceSearchStatus.error;
    _errorMessage = 'تعذر تأكيد إيقاف الميكروفون، يرجى المحاولة ثانية: $error';
    notifyListeners();
  }

  void _handleStatus(String status) {
    if (_activeGeneration != _generation) return;
    if (status == 'listening') {
      _status = VoiceSearchStatus.listening;
    } else if ((status == 'notListening' || status == 'done') &&
        _status == VoiceSearchStatus.listening) {
      _status = VoiceSearchStatus.done;
    }
    notifyListeners();
  }

  void _handleError(SpeechRecognitionError error) {
    if (_activeGeneration != _generation) return;
    final generation = _generation;
    final callback = _activeError;
    _activeGeneration = null;
    _activeError = null;
    _status = VoiceSearchStatus.error;
    _errorMessage = _translateError(error.errorMsg);
    callback?.call(_errorMessage);
    if (_current(generation)) notifyListeners();
  }

  String _translateError(String original) {
    final lower = original.toLowerCase();
    if (lower.contains('no match') ||
        lower.contains('no_match') ||
        lower.contains('speech_timeout')) {
      return 'لم يتم تمييز أي صوت، يرجى الاقتراب من الميكروفون والمحاولة ثانية';
    }
    if (lower.contains('network') || lower.contains('timeout')) {
      return 'تعذر الاتصال بخدمة التعرف الصوتي، يرجى التحقق من الشبكة';
    }
    if (lower.contains('permission') || lower.contains('denied')) {
      return 'صلاحية الميكروفون مرفوضة، يرجى تفعيلها من إعدادات الهاتف';
    }
    return 'تعذر التعرف على الصوت ($original)';
  }

  static void resetTestMode() {
    isTestMode = false;
    testMockRecognizedWords = null;
  }
}
