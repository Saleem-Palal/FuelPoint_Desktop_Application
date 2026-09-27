import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fuel_dispenser/features/shift/domain/shift_models.dart';
import 'package:fuel_dispenser/features/station/domain/dispenser_models.dart';
import 'package:fuel_dispenser/features/station/domain/fuel_precision.dart';

void main() {
  group('Direct sale tokens and labels', () {
    test('first Direct token is TKN-DR-600000', () {
      expect(kDirectSaleUnitId, 6);
      expect(tokenIdFor(unitId: kDirectSaleUnitId, sequence: 0), 600000);
      expect(formatLedgerToken(600000), 'TKN-DR-600000');
      expect(parseLedgerToken('TKN-DR-600000'), 600000);
      expect(formatLedgerToken(parseLedgerToken('TKN-DR-600000')), 'TKN-DR-600000');
    });

    test('pump tokens stay TKN- without DR', () {
      expect(formatLedgerToken(100001), 'TKN-100001');
      expect(isDirectSaleToken(100001), isFalse);
    });

    test('unit column is Direct not 06', () {
      expect(formatUnitLabel(kDirectSaleUnitId), 'Direct');
      expect(formatSaleUnitColumn(kDirectSaleUnitId), 'Direct');
      expect(formatSaleUnitColumn(1), '01');
    });
  });

  group('Direct sale amount', () {
    test('amount is whole PKR from truncated liters times rate', () {
      final Decimal liters = parseFuel('10.456789');
      final Decimal rate = parseFuel('256.329');
      expect(roundRupees(liters * rate), 2680);
    });
  });

  group('metricsForSales', () {
    HelperSaleRecord pumpCash() {
      return HelperSaleRecord(
        tokenNo: 100001,
        timestamp: DateTime(2026, 9, 24, 10),
        helperId: '',
        helperName: '',
        unitId: 1,
        fuelType: kDieselFuelType,
        volumeLiters: 10,
        rate: 256.32,
        amountPkr: 2563,
        payment: PaymentMethod.cash,
        cashAmount: 2563,
      );
    }

    HelperSaleRecord directCash() {
      return HelperSaleRecord(
        tokenNo: 600000,
        timestamp: DateTime(2026, 9, 24, 11),
        helperId: '',
        helperName: '',
        unitId: kDirectSaleUnitId,
        fuelType: kDieselFuelType,
        volumeLiters: 50,
        rate: 256.32,
        amountPkr: 12816,
        payment: PaymentMethod.cash,
        cashAmount: 12816,
      );
    }

    test('ignores Direct rows in volume and shift cash', () {
      final ShiftWindowMetrics pumpOnly = metricsForSales(<HelperSaleRecord>[
        pumpCash(),
      ]);
      final ShiftWindowMetrics mixed = metricsForSales(<HelperSaleRecord>[
        pumpCash(),
        directCash(),
      ]);
      expect(mixed.totalLiters, pumpOnly.totalLiters);
      expect(mixed.fuelCashSales, pumpOnly.fuelCashSales);
      expect(mixed.totalSale, pumpOnly.totalSale);
    });
  });
}
