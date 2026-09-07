import 'package:intl/intl.dart';

/// Presentation-only number formatting for fuel UI.
///
/// Never use these helpers inside models, repositories, or calculation
/// functions. They round for display only.
///
/// Amounts and liters are whole numbers. Rate keeps decimals.
class FuelFormatter {
  FuelFormatter._();

  static final NumberFormat _whole = NumberFormat('#,##0', 'en_US');
  static final NumberFormat _rate = NumberFormat('#,##0.00', 'en_US');
  static final NumberFormat _lcdWhole = NumberFormat('0', 'en_US');
  static final NumberFormat _lcdRate = NumberFormat('0.00', 'en_US');
  static final NumberFormat _fieldRate = NumberFormat('0.########', 'en_US');

  static String formatCurrency(double amount) {
    return 'Rs. ${_whole.format(amount.round())}';
  }

  static String formatVolume(double liters) {
    return '${_whole.format(liters.round())} Ltr';
  }

  static String formatRate(double rate) {
    return 'Rs. ${_rate.format(rate)} / L';
  }

  static String lcdAmount(double value) {
    return _lcdWhole.format(value.round());
  }

  static String lcdVolume(double value) {
    return _lcdWhole.format(value.round());
  }

  static String lcdRate(double value) {
    return _lcdRate.format(value);
  }

  /// Compact rate string for an editable text field (no grouping).
  static String fieldRate(double value) {
    if (value == 0) {
      return '';
    }
    return _fieldRate.format(value);
  }

  /// Whole-number string for liters text fields (no grouping).
  static String fieldWhole(double value) {
    if (value == 0) {
      return '';
    }
    return value.round().toString();
  }

  /// Whole-number amount for the Amount text field, with grouping commas.
  static String fieldAmount(double value) {
    if (value == 0) {
      return '';
    }
    return _whole.format(value.round());
  }

  static double parseGrouped(String text) {
    return double.tryParse(text.trim().replaceAll(',', '')) ?? 0;
  }
}
