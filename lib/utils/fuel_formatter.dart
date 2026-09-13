import 'package:intl/intl.dart';

import '../core/decimal_display.dart';

/// Presentation-only number formatting for fuel UI.
///
/// Never use these helpers inside models, repositories, or calculation
/// functions.
///
/// Rupees are whole numbers. Liters and average rate are truncated to 2
/// decimal places for display (never rounded). Storage keeps 13 places.
class FuelFormatter {
  FuelFormatter._();

  static final NumberFormat _whole = NumberFormat('#,##0', 'en_US');
  static final NumberFormat _lcdWhole = NumberFormat('0', 'en_US');
  static final NumberFormat _fieldFuel = NumberFormat(
    '0.#############',
    'en_US',
  );

  static String formatCurrency(double amount) {
    return 'Rs. ${_whole.format(amount.round())}';
  }

  static String formatVolume(double liters) {
    return '${groupTruncatedDecimal(liters)} Ltr';
  }

  static String formatRate(double rate) {
    return formatAverageRate(rate);
  }

  /// WAC / average rate for UI: two decimal digits, truncated, not rounded.
  static String formatAverageRateValue(double rate) {
    return 'Rs. ${groupTruncatedDecimal(rate)}';
  }

  static String formatAverageRate(double rate) {
    return '${formatAverageRateValue(rate)} / L';
  }

  static String lcdAmount(double value) {
    return _lcdWhole.format(value.round());
  }

  /// Live dispenser rupees: two decimals, truncated toward zero, never rounded.
  static String lcdDispenserAmount(double value) {
    return truncateToDecimalPlaces(value, 2);
  }

  static String lcdVolume(double value) {
    return truncateToDecimalPlaces(value, 2);
  }

  static String lcdRate(double value) {
    return lcdAverageRate(value);
  }

  /// LCD WAC / average rate: two decimal digits, truncated, not rounded.
  static String lcdAverageRate(double value) {
    return truncateToDecimalPlaces(value, 2);
  }

  /// Compact rate string for an editable text field (no grouping).
  static String fieldRate(double value) {
    if (value == 0) {
      return '';
    }
    return _fieldFuel.format(value);
  }

  /// Liters string for a text field (no grouping, up to 13 places).
  static String fieldWhole(double value) {
    if (value == 0) {
      return '';
    }
    return _fieldFuel.format(value);
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
