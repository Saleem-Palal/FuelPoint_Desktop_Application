import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_dispenser/features/station/domain/dispenser_models.dart';
import 'package:fuel_dispenser/features/station/domain/rate_change_summary.dart';

SaleTransaction _sale({
  required int unitId,
  required double opening,
  required double closing,
  required double rate,
  required DateTime timestamp,
  double liters = 0,
  bool isTest = false,
  int tokenNo = 1,
}) {
  return SaleTransaction(
    tokenNo: tokenNo,
    unitId: unitId,
    fuelType: kDieselFuelType,
    amountPkr: 0,
    volumeLiters: liters,
    rate: rate,
    meterCount: 0,
    timestamp: timestamp,
    openingMeter: opening,
    closingMeter: closing,
    isTest: isTest,
  );
}

void main() {
  test('sheet figures use closing minus opening times one rate', () {
    final RateChangeSummary summary = rateChangeSummary(<SaleTransaction>[
      _sale(
        unitId: 1,
        opening: 257370.58,
        closing: 258808.27,
        rate: 318,
        timestamp: DateTime(2026, 10, 1),
        tokenNo: 1,
      ),
      _sale(
        unitId: 2,
        opening: 235808.20,
        closing: 239024.65,
        rate: 318,
        timestamp: DateTime(2026, 10, 1),
        tokenNo: 2,
      ),
      _sale(
        unitId: 3,
        opening: 242871.86,
        closing: 244479.95,
        rate: 318,
        timestamp: DateTime(2026, 10, 1),
        tokenNo: 3,
      ),
      _sale(
        unitId: 4,
        opening: 214490.59,
        closing: 216049.13,
        rate: 318,
        timestamp: DateTime(2026, 10, 1),
        tokenNo: 4,
      ),
    ]);

    expect(summary.stretches, hasLength(4));
    expect(summary.stretches[0].dispensedLiters, closeTo(1437.69, 0.001));
    expect(summary.stretches[0].amountPkr, 457185);
    expect(summary.stretches[1].amountPkr, 1022831);
    expect(summary.stretches[2].amountPkr, 511373);
    expect(summary.stretches[3].amountPkr, 495616);
    expect(summary.dispensedLiters, closeTo(7820.77, 0.001));
    expect(summary.amountPkr, 2487005);
  });

  test('a rate change splits the unit and a test stays in its stretch', () {
    final RateChangeSummary summary = rateChangeSummary(<SaleTransaction>[
      _sale(
        unitId: 1,
        opening: 100,
        closing: 110,
        rate: 300,
        liters: 10,
        timestamp: DateTime(2026, 10, 1, 9),
        tokenNo: 1,
      ),
      _sale(
        unitId: 1,
        opening: 110,
        closing: 113,
        rate: 300,
        liters: 3,
        isTest: true,
        timestamp: DateTime(2026, 10, 1, 10),
        tokenNo: 2,
      ),
      _sale(
        unitId: 1,
        opening: 113,
        closing: 130,
        rate: 310,
        liters: 17,
        timestamp: DateTime(2026, 10, 1, 11),
        tokenNo: 3,
      ),
    ]);

    expect(summary.stretches, hasLength(2));
    expect(summary.stretches[0].openingMeter, 100);
    expect(summary.stretches[0].closingMeter, 113);
    expect(summary.stretches[0].testLiters, 3);
    expect(summary.stretches[0].netLiters, closeTo(10, 0.001));
    expect(summary.stretches[0].amountPkr, 3000);
    expect(summary.stretches[1].openingMeter, 113);
    expect(summary.stretches[1].closingMeter, 130);
    expect(summary.stretches[1].rate, 310);
    expect(summary.stretches[1].amountPkr, 5270);
    expect(summary.amountPkr, 8270);
  });

  test('shared rate changes stay together, oldest period first', () {
    final RateChangeSummary summary = rateChangeSummary(<SaleTransaction>[
      _sale(
        unitId: 1,
        opening: 100,
        closing: 110,
        rate: 305,
        timestamp: DateTime(2026, 10, 1, 9),
        tokenNo: 1,
      ),
      _sale(
        unitId: 2,
        opening: 200,
        closing: 220,
        rate: 305,
        timestamp: DateTime(2026, 10, 1, 9, 5),
        tokenNo: 2,
      ),
      _sale(
        unitId: 1,
        opening: 110,
        closing: 140,
        rate: 312,
        timestamp: DateTime(2026, 10, 2, 9),
        tokenNo: 3,
      ),
      _sale(
        unitId: 2,
        opening: 220,
        closing: 250,
        rate: 312,
        timestamp: DateTime(2026, 10, 2, 9, 5),
        tokenNo: 4,
      ),
      _sale(
        unitId: 2,
        opening: 250,
        closing: 260,
        rate: 336,
        timestamp: DateTime(2026, 10, 3, 9, 5),
        tokenNo: 5,
      ),
      _sale(
        unitId: 1,
        opening: 140,
        closing: 150,
        rate: 336,
        timestamp: DateTime(2026, 10, 3, 9),
        tokenNo: 6,
      ),
    ]);

    expect(
      summary.stretches.map((RateChangeStretch row) => row.unitId).toList(),
      <int>[1, 2, 1, 2, 1, 2],
    );
    expect(
      summary.stretches.map((RateChangeStretch row) => row.rate).toList(),
      <double>[305, 305, 312, 312, 336, 336],
    );
  });

  test('direct sales are left out of the meter spans', () {
    final RateChangeSummary summary = rateChangeSummary(<SaleTransaction>[
      _sale(
        unitId: kDirectSaleUnitId,
        opening: 0,
        closing: 50,
        rate: 300,
        timestamp: DateTime(2026, 10, 1),
      ),
    ]);

    expect(summary.stretches, isEmpty);
    expect(summary.amountPkr, 0);
    expect(summary.dispensedLiters, 0);
  });
}
