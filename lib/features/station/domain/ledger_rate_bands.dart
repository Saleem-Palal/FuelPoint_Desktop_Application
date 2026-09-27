import '../../../core/decimal_display.dart';
import 'dispenser_models.dart';

/// Displayed-rate key used to band ledger rows. Matches [formatRate] digits.
String displayedRateKey(double rate) {
  return truncateToDecimalPlaces(rate, 2);
}

/// First-seen rate → palette index. Empty when the slice has a single rate.
Map<String, int> rateBandIndexes(List<SaleTransaction> rows) {
  final Set<String> distinct = <String>{};
  for (final SaleTransaction row in rows) {
    if (row.isTest) {
      continue;
    }
    distinct.add(displayedRateKey(row.rate));
  }
  if (distinct.length < 2) {
    return const <String, int>{};
  }
  final Map<String, int> indexes = <String, int>{};
  int next = 0;
  for (final SaleTransaction row in rows) {
    if (row.isTest) {
      continue;
    }
    final String key = displayedRateKey(row.rate);
    indexes.putIfAbsent(key, () => next++);
  }
  return indexes;
}
