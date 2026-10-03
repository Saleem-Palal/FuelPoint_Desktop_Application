import 'package:flutter_test/flutter_test.dart';

import 'package:fuel_dispenser/features/shift/domain/shift_models.dart';
import 'package:fuel_dispenser/features/shift/domain/shift_report_layout.dart';
import 'package:fuel_dispenser/features/station/domain/dispenser_models.dart';
import 'package:fuel_dispenser/features/station/domain/money_format.dart';

HelperSaleRecord _sale({
  required int tokenNo,
  required int unitId,
  required DateTime timestamp,
  required double opening,
  required double closing,
  double liters = 10,
  double rate = 256.32,
  bool isTest = false,
}) {
  return HelperSaleRecord(
    tokenNo: tokenNo,
    timestamp: timestamp,
    helperId: 'h-1',
    helperName: 'Ali',
    unitId: unitId,
    fuelType: kDieselFuelType,
    volumeLiters: liters,
    rate: rate,
    amountPkr: 2563,
    openingMeter: opening,
    closingMeter: closing,
    isTest: isTest,
  );
}

OperatorShiftRecord _shift({
  OperatorShiftStatus status = OperatorShiftStatus.closed,
  Map<int, double> openingMeters = const <int, double>{1: 100},
  Map<int, double> closingMeters = const <int, double>{1: 140},
}) {
  return OperatorShiftRecord(
    shiftId: 'SHF-1',
    operatorId: 'op-1',
    operatorName: 'Saleem',
    role: OperatorRole.operator,
    startTime: DateTime(2026, 9, 28, 8),
    endTime: DateTime(2026, 9, 28, 20),
    expectedCash: 0,
    status: status,
    openingMeters: openingMeters,
    closingMeters: closingMeters,
  );
}

void main() {
  group('shift report grouping', () {
    test('orders sales by unit then time, not mixed chronology', () {
      final List<ShiftUnitSaleGroup> groups =
          groupShiftReportSalesByUnit(<HelperSaleRecord>[
            _sale(
              tokenNo: 4,
              unitId: 2,
              timestamp: DateTime(2026, 9, 28, 10),
              opening: 50,
              closing: 60,
            ),
            _sale(
              tokenNo: 3,
              unitId: 1,
              timestamp: DateTime(2026, 9, 28, 11),
              opening: 110,
              closing: 120,
            ),
            _sale(
              tokenNo: 2,
              unitId: 1,
              timestamp: DateTime(2026, 9, 28, 9),
              opening: 100,
              closing: 110,
            ),
            _sale(
              tokenNo: 1,
              unitId: 2,
              timestamp: DateTime(2026, 9, 28, 8),
              opening: 40,
              closing: 50,
            ),
            _sale(
              tokenNo: 600001,
              unitId: kDirectSaleUnitId,
              timestamp: DateTime(2026, 9, 28, 7),
              opening: 0,
              closing: 0,
            ),
          ]);

      expect(groups.map((ShiftUnitSaleGroup g) => g.unitId), <int>[1, 2]);
      expect(groups[0].sales.map((HelperSaleRecord row) => row.tokenNo), <int>[
        2,
        3,
      ]);
      expect(groups[1].sales.map((HelperSaleRecord row) => row.tokenNo), <int>[
        1,
        4,
      ]);
    });

    test('omits Unit 5 unless settings enable it', () {
      final List<HelperSaleRecord> sales = <HelperSaleRecord>[
        _sale(
          tokenNo: 1,
          unitId: 1,
          timestamp: DateTime(2026, 9, 28, 9),
          opening: 100,
          closing: 110,
        ),
        _sale(
          tokenNo: 2,
          unitId: 5,
          timestamp: DateTime(2026, 9, 28, 10),
          opening: 200,
          closing: 210,
        ),
      ];
      final OperatorShiftRecord shift = _shift(
        openingMeters: const <int, double>{1: 100, 5: 200},
        closingMeters: const <int, double>{1: 110, 5: 210},
      );

      final List<ShiftUnitSaleGroup> hidden = groupShiftReportSalesByUnit(
        sales,
      );
      expect(hidden.map((ShiftUnitSaleGroup g) => g.unitId), <int>[1]);

      final List<ShiftUnitSaleGroup> shown = groupShiftReportSalesByUnit(
        sales,
        showUnit5: true,
      );
      expect(shown.map((ShiftUnitSaleGroup g) => g.unitId), <int>[1, 5]);

      expect(
        buildShiftReportReadings(
          shift: shift,
          sales: sales,
        ).map((ShiftUnitReading row) => row.unitId),
        <int>[1],
      );
      expect(
        buildShiftReportReadings(
          shift: shift,
          sales: sales,
          showUnit5: true,
        ).map((ShiftUnitReading row) => row.unitId),
        <int>[1, 5],
      );
    });
  });

  group('shift report readings', () {
    test('single rate uses shift opening and closing for one row', () {
      final List<ShiftUnitReading> readings = buildShiftReportReadings(
        shift: _shift(),
        sales: <HelperSaleRecord>[
          _sale(
            tokenNo: 1,
            unitId: 1,
            timestamp: DateTime(2026, 9, 28, 9),
            opening: 100,
            closing: 120,
            liters: 20,
          ),
          _sale(
            tokenNo: 2,
            unitId: 1,
            timestamp: DateTime(2026, 9, 28, 11),
            opening: 120,
            closing: 140,
            liters: 20,
          ),
        ],
      );

      expect(readings, hasLength(1));
      expect(readings.first.rows, hasLength(1));
      final ShiftRateReadingRow row = readings.first.rows.single;
      expect(row.opening, 100);
      expect(row.closing, 140);
      expect(row.dispensed, 40);
      expect(row.rate, 256.32);
      expect(row.amountPkr, 10253);
    });

    test('rate change splits meter sub-rows', () {
      final List<ShiftUnitReading> readings = buildShiftReportReadings(
        shift: _shift(),
        sales: <HelperSaleRecord>[
          _sale(
            tokenNo: 1,
            unitId: 1,
            timestamp: DateTime(2026, 9, 28, 9),
            opening: 100,
            closing: 110,
            rate: 256.32,
          ),
          _sale(
            tokenNo: 2,
            unitId: 1,
            timestamp: DateTime(2026, 9, 28, 10),
            opening: 110,
            closing: 120,
            rate: 256.32,
          ),
          _sale(
            tokenNo: 3,
            unitId: 1,
            timestamp: DateTime(2026, 9, 28, 12),
            opening: 120,
            closing: 130,
            rate: 260,
          ),
          _sale(
            tokenNo: 4,
            unitId: 1,
            timestamp: DateTime(2026, 9, 28, 13),
            opening: 130,
            closing: 140,
            rate: 260,
          ),
        ],
      );

      expect(readings.single.rows, hasLength(2));
      final ShiftRateReadingRow first = readings.single.rows[0];
      final ShiftRateReadingRow second = readings.single.rows[1];
      expect(first.rate, 256.32);
      expect(first.opening, 100);
      expect(first.closing, 120);
      expect(first.dispensed, 20);
      expect(first.amountPkr, 5126);
      expect(second.rate, 260);
      expect(second.opening, 120);
      expect(second.closing, 140);
      expect(second.dispensed, 20);
      expect(second.amountPkr, 5200);
    });

    test('test liters stay in dispensed and leave net volume and amount', () {
      final List<ShiftUnitReading> readings = buildShiftReportReadings(
        shift: _shift(),
        sales: <HelperSaleRecord>[
          _sale(
            tokenNo: 1,
            unitId: 1,
            timestamp: DateTime(2026, 9, 28, 9),
            opening: 100,
            closing: 130,
            liters: 30,
            rate: 250,
          ),
          _sale(
            tokenNo: 2,
            unitId: 1,
            timestamp: DateTime(2026, 9, 28, 11),
            opening: 130,
            closing: 140,
            liters: 10,
            rate: 250,
            isTest: true,
          ),
        ],
      );

      final ShiftRateReadingRow row = readings.single.rows.single;
      expect(row.dispensed, 40);
      expect(row.testLiters, 10);
      expect(row.netVolume, 30);
      expect(row.amountPkr, 7500);
    });
  });

  group('shift report audit lines', () {
    test('PASS when metered volume matches logged sales', () {
      final List<String> lines = shiftReportAuditLines(
        shift: _shift(
          openingMeters: const <int, double>{1: 80},
          closingMeters: const <int, double>{1: 120},
        ),
        sales: <HelperSaleRecord>[
          _sale(
            tokenNo: 1,
            unitId: 1,
            timestamp: DateTime(2026, 9, 28, 9),
            opening: 80,
            closing: 90,
          ),
          _sale(
            tokenNo: 2,
            unitId: 1,
            timestamp: DateTime(2026, 9, 28, 11),
            opening: 90,
            closing: 100,
          ),
          _sale(
            tokenNo: 3,
            unitId: 1,
            timestamp: DateTime(2026, 9, 28, 13),
            opening: 100,
            closing: 110,
          ),
          _sale(
            tokenNo: 4,
            unitId: 1,
            timestamp: DateTime(2026, 9, 28, 15),
            opening: 110,
            closing: 120,
          ),
        ],
      );

      expect(lines, <String>['UNIT 1: PASS']);
    });

    test('MISMATCH copy includes liter delta when meter exceeds sales', () {
      final List<String> lines = shiftReportAuditLines(
        shift: _shift(
          openingMeters: const <int, double>{1: 80},
          closingMeters: const <int, double>{1: 92.5},
        ),
        sales: const <HelperSaleRecord>[],
      );

      expect(lines, hasLength(1));
      expect(
        lines.single,
        'UNIT 1: MISMATCH - Meter volume exceeds ledger transactions by 12.50 L',
      );
    });
  });

  group('shift report table labels', () {
    test('DateTime is day and 12-hour clock', () {
      expect(formatShiftTableTime(DateTime(2026, 9, 29, 2, 6)), '29 2:06 AM');
    });

    test('PM abbreviations are Cash, ACC, and Udhr', () {
      expect(shiftReportPaymentLabel(PaymentMethod.cash), 'Cash');
      expect(shiftReportPaymentLabel(PaymentMethod.bankAccount), 'ACC');
      expect(shiftReportPaymentLabel(PaymentMethod.easyPaisa), 'ACC');
      expect(shiftReportPaymentLabel(PaymentMethod.udhaar), 'Udhr');
    });

    test('direct sales are listed separately from dispenser units', () {
      final List<HelperSaleRecord> sales = <HelperSaleRecord>[
        _sale(
          tokenNo: 1,
          unitId: 1,
          timestamp: DateTime(2026, 9, 28, 9),
          opening: 100,
          closing: 110,
        ),
        _sale(
          tokenNo: 600002,
          unitId: kDirectSaleUnitId,
          timestamp: DateTime(2026, 9, 28, 11),
          opening: 0,
          closing: 0,
          liters: 20,
        ),
        _sale(
          tokenNo: 600001,
          unitId: kDirectSaleUnitId,
          timestamp: DateTime(2026, 9, 28, 10),
          opening: 0,
          closing: 0,
          liters: 15,
        ),
      ];
      expect(
        groupShiftReportSalesByUnit(
          sales,
        ).map((ShiftUnitSaleGroup g) => g.unitId),
        <int>[1],
      );
      expect(
        shiftReportDirectSales(
          sales,
        ).map((HelperSaleRecord row) => row.tokenNo),
        <int>[600001, 600002],
      );
    });
  });

  test(
    'waiting account shows on the row and stays out of the account total',
    () {
      final HelperSaleRecord row =
          _sale(
            tokenNo: 1,
            unitId: 1,
            timestamp: DateTime(2026, 9, 1),
            opening: 10,
            closing: 20,
          ).copyWith(
            payment: PaymentMethod.bankAccount,
            amountPkr: 2989,
            cashAmount: 2000,
            accountAmount: 0,
            pendingAccountAmount: 989,
          );
      expect(row.accountTender, 0);
      expect(shiftSaleAccountColumn(row), 989);
      expect(shiftSalePaymentLabel(row), 'Bank Account · Pending');
      expect(shiftSalePaymentLabel(row, short: true), 'ACC · Pending');
    },
  );
}
