import 'package:decimal/decimal.dart';

/// Fractional digits kept for liters and rate in SQLite / domain math.
const int fuelScale = 13;

/// TEXT form of zero liters or rate (`0` plus [fuelScale] fractional zeros).
final String zeroFuelText = fuelToText(Decimal.zero);

/// Truncate toward zero to [fuelScale] places. Never rounds.
Decimal truncateFuel(Decimal value) {
  return value.truncate(scale: fuelScale);
}

/// Parse any SQLite / form value, then truncate liters/rate to [fuelScale].
Decimal parseFuel(Object? value) {
  return truncateFuel(parseDecimal(value));
}

/// Parse a number without truncating (used for rupee rounding).
Decimal parseDecimal(Object? value) {
  if (value == null) {
    return Decimal.zero;
  }
  if (value is Decimal) {
    return value;
  }
  if (value is int) {
    return Decimal.fromInt(value);
  }
  final String text = '$value'.trim().replaceAll(',', '');
  if (text.isEmpty || text == 'null') {
    return Decimal.zero;
  }
  return Decimal.tryParse(text) ?? Decimal.zero;
}

/// Persist liters or rate as TEXT with exactly [fuelScale] fractional digits.
String fuelToText(Object? value) {
  return truncateFuel(parseDecimal(value)).toStringAsFixed(fuelScale);
}

/// Nearest whole PKR (`.5` away from zero), matching Dart `num.round()`.
int roundRupees(Object? value) {
  return parseDecimal(value).round().toBigInt().toInt();
}

Decimal rupeesDecimal(Object? value) {
  return Decimal.fromInt(roundRupees(value));
}

/// UI / controller edge: TEXT or REAL from SQLite as `double`.
double storedNumberToDouble(Object? value) {
  return parseDecimal(value).toDouble();
}

/// Meter delta from two Total Meter snapshots, truncated like stored liters.
Decimal meterDeltaLiters(Object? openingMeter, Object? closingMeter) {
  return truncateFuel(parseDecimal(closingMeter) - parseDecimal(openingMeter));
}

/// Fractional digits used for same-unit meter continuity (2-place display).
/// Finer noise, including [fuelScale] / 13th-place, is not a mismatch.
const int meterMismatchScale = 2;

Decimal truncateMeterCheck(Object? value) {
  return parseDecimal(value).truncate(scale: meterMismatchScale);
}

bool metersMatchAtAuditScale(Object? left, Object? right) {
  return truncateMeterCheck(left) == truncateMeterCheck(right);
}

/// True when ESP liters and Closing − Opening agree at [meterMismatchScale].
bool saleLitersMatchMeter({
  required Object? liters,
  required Object? openingMeter,
  required Object? closingMeter,
}) {
  final Decimal delta = parseDecimal(closingMeter) - parseDecimal(openingMeter);
  return metersMatchAtAuditScale(liters, delta);
}

/// Convert a Decimal division result to [fuelScale] places, truncated.
Decimal divideFuel(Decimal numerator, Decimal denominator) {
  return truncateFuel(
    (numerator / denominator).toDecimal(
      scaleOnInfinitePrecision: fuelScale + 16,
    ),
  );
}
