import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/zakat_calculation.dart';

/// Service managing Islamic Zakat calculations, persistence and Hawl reminders (FR-ZKT)
class ZakatService extends ChangeNotifier {
  static final ZakatService instance = ZakatService._internal();
  ZakatService._internal();

  static const String _storageKey = 'zakat_calculation_draft_v1';

  static const List<String> supportedCurrencies = [
    'ج.م', // Egyptian Pound
    'ر.س', // Saudi Riyal
    'د.إ', // UAE Dirham
    'د.ك', // Kuwaiti Dinar
    'ر.ق', // Qatari Riyal
    'د.ب', // Bahraini Dinar
    'ر.ع', // Omani Rial
    'د.أ', // Jordanian Dinar
    'د.ت', // Tunisian Dinar
    'د.ج', // Algerian Dinar
    'درهم', // Moroccan Dirham
    '\$', // US Dollar
    '€', // Euro
  ];

  ZakatCalculation _calculation = const ZakatCalculation();
  bool _isInitialized = false;
  Future<void> _operations = Future<void>.value();

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _operations.then((_) => action());
    _operations =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  bool get isInitialized => _isInitialized;
  ZakatCalculation get calculation => _calculation;

  /// Initializes the service from persistent storage
  Future<void> init({bool forceReload = false}) => _serialize(() async {
        if (_isInitialized && !forceReload) return;
        try {
          final prefs = await SharedPreferences.getInstance();
          if (forceReload) await prefs.reload();
          final jsonStr = prefs.getString(_storageKey);
          final next = jsonStr != null && jsonStr.isNotEmpty
              ? ZakatCalculation.fromJson(
                  json.decode(jsonStr) as Map<String, dynamic>)
              : const ZakatCalculation();
          _calculation = next;
          _isInitialized = true;
          notifyListeners();
        } catch (e) {
          debugPrint('ZakatService init error: $e');
          _isInitialized = true;
        }
      });

  /// Publishes the draft only after storage confirms the write.
  Future<bool> updateCalculation(ZakatCalculation calculation) =>
      _serialize(() => _persist(calculation));

  /// Derive date/reset changes when their turn in the write queue starts.
  Future<bool> setHawlDate(DateTime? date) => _serialize(() => _persist(
      _calculation.copyWith(hawlDate: date, clearHawlDate: date == null)));

  Future<bool> reset() => _serialize(() => _persist(ZakatCalculation(
        currency: _calculation.currency,
        goldPricePerGram24: _calculation.goldPricePerGram24,
        silverPricePerGram: _calculation.silverPricePerGram,
        nisabBasis: _calculation.nisabBasis,
      )));

  Map<String, dynamic> exportData() => _calculation.toJson();

  /// Backup must not report success after a rejected delegated write.
  Future<void> importData(Map<String, dynamic> data) async {
    await init();
    final next = ZakatCalculation.fromJson(data);
    if (!await updateCalculation(next)) {
      throw StateError('Zakat calculation could not be saved');
    }
  }

  Future<bool> _persist(ZakatCalculation next) async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(_storageKey, json.encode(next.toJson()))) {
        throw StateError('Zakat calculation write rejected');
      }
      _calculation = next;
      notifyListeners();
      return true;
    } catch (e) {
      // SharedPreferences updates its cache before the platform confirms.
      try {
        await prefs?.reload();
      } catch (reloadError) {
        debugPrint('ZakatService cache reload error: $reloadError');
      }
      debugPrint('ZakatService persist error: $e');
      return false;
    }
  }
}
