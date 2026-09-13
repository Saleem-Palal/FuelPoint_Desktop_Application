import 'package:decimal/decimal.dart';

import 'fuel_precision.dart';

/// Running weighted-average cost (WAC).
///
/// next WAC = (current Stock_amount + this purchase AMOUNT)
///            ÷ (current liters + this purchase liters)
///
/// [currentStockAmount] and [purchaseAmount] are whole rupees already stored
/// or about to be stored. Liters and the result are truncated to [fuelScale].
Decimal nextAverageRate({
  required Decimal currentLiters,
  required Decimal currentStockAmount,
  required Decimal purchaseLiters,
  required Decimal purchaseAmount,
}) {
  final Decimal nextLiters = truncateFuel(currentLiters + purchaseLiters);
  if (nextLiters == Decimal.zero) {
    return Decimal.zero;
  }
  return divideFuel(currentStockAmount + purchaseAmount, nextLiters);
}

/// Double convenience for Purchase Screen previews. Storage still uses
/// [nextAverageRate] on [Decimal].
double nextAverageRateFromDoubles({
  required double currentLiters,
  required double currentStockAmount,
  required double purchaseLiters,
  required double purchaseAmount,
}) {
  return nextAverageRate(
    currentLiters: parseFuel(currentLiters),
    currentStockAmount: rupeesDecimal(currentStockAmount),
    purchaseLiters: parseFuel(purchaseLiters),
    purchaseAmount: rupeesDecimal(purchaseAmount),
  ).toDouble();
}

bool isInitialDipTafseel(String tafseel) {
  return tafseel.trim().toUpperCase().startsWith('DIP');
}
