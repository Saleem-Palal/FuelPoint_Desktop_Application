import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fuel_dispenser/core/decimal_display.dart';
import 'package:fuel_dispenser/features/station/domain/average_rate.dart';
import 'package:fuel_dispenser/features/station/domain/fuel_precision.dart';
import 'package:fuel_dispenser/utils/fuel_formatter.dart';

void main() {
  group('FuelPrecision', () {
    test('truncates liters and rate to 13 places without rounding', () {
      expect(fuelToText(Decimal.parse('1.23456789012356')), '1.2345678901235');
      expect(fuelToText(Decimal.parse('1.23999999999999')), '1.2399999999999');
    });

    test('pads shorter values to 13 fractional digits', () {
      expect(fuelToText(Decimal.parse('12.5')), '12.5000000000000');
      expect(zeroFuelText, '0.0000000000000');
    });

    test('roundRupees uses half-up away from zero', () {
      expect(roundRupees(Decimal.parse('10.4')), 10);
      expect(roundRupees(Decimal.parse('10.5')), 11);
      expect(roundRupees(Decimal.parse('-10.5')), -11);
    });
  });

  group('nextAverageRate', () {
    test('uses stored rounded Stock_amount, not liters × rate', () {
      final Decimal next = nextAverageRate(
        currentLiters: Decimal.parse('100'),
        currentStockAmount: Decimal.fromInt(28050),
        purchaseLiters: Decimal.parse('50'),
        purchaseAmount: Decimal.fromInt(14100),
      );
      expect(next, Decimal.parse('281'));
    });

    test('truncates WAC to 13 places instead of rounding the 13th digit', () {
      final Decimal next = nextAverageRate(
        currentLiters: Decimal.zero,
        currentStockAmount: Decimal.zero,
        purchaseLiters: Decimal.parse('3'),
        purchaseAmount: Decimal.fromInt(1),
      );
      expect(fuelToText(next), '0.3333333333333');
    });
  });

  group('UI display', () {
    test('rate and liters show 2 truncated digits, not rounded', () {
      expect(truncateToDecimalPlaces(1.239, 2), '1.23');
      expect(FuelFormatter.lcdAverageRate(1.239), '1.23');
      expect(FuelFormatter.lcdVolume(10.999), '10.99');
      expect(FuelFormatter.formatVolume(10.999), '10.99 Ltr');
    });

    test('rupees round to a whole number', () {
      expect(FuelFormatter.lcdAmount(10.4), '10');
      expect(FuelFormatter.lcdAmount(10.5), '11');
      expect(FuelFormatter.formatCurrency(1234.6), 'Rs. 1,235');
    });

    test('live dispenser amount truncates two decimals and does not round up', () {
      expect(FuelFormatter.lcdDispenserAmount(6618.50), '6618.50');
      expect(FuelFormatter.lcdDispenserAmount(10.5), '10.50');
      expect(FuelFormatter.lcdDispenserAmount(10.999), '10.99');
    });
  });
}
