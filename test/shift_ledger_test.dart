import 'package:flutter_test/flutter_test.dart';

import 'package:fuel_dispenser/features/shift/domain/shift_models.dart';
import 'package:fuel_dispenser/features/station/data/sales_transaction_repository.dart';
import 'package:fuel_dispenser/features/station/data/transaction_store.dart';
import 'package:fuel_dispenser/features/station/domain/dispenser_models.dart';
import 'package:fuel_dispenser/features/station/domain/shift_ledger_models.dart';

SaleTransaction _sale({
  required String shiftId,
  required double liters,
  required double pkr,
  int tokenNo = 100001,
  int unitId = 1,
  DateTime? timestamp,
  PaymentMethod payment = PaymentMethod.cash,
}) {
  return SaleTransaction(
    tokenNo: tokenNo,
    unitId: unitId,
    fuelType: kDieselFuelType,
    amountPkr: pkr,
    volumeLiters: liters,
    rate: 280,
    meterCount: 1,
    timestamp: timestamp ?? DateTime(2026, 9, 8, 10),
    shiftId: shiftId,
    payment: payment,
  );
}

ShiftLedgerSummary _summary({
  required String shiftId,
  required ManagerShiftStatus status,
  int totalTransactions = 1,
  double totalShiftPkr = 100,
  double totalShiftLiters = 1,
  DateTime? startTime,
  DateTime? endTime,
}) {
  return ShiftLedgerSummary(
    shiftId: shiftId,
    managerId: 'mgr-1',
    managerName: 'Saleem',
    role: ManagerRole.manager,
    startTime: startTime ?? DateTime(2026, 9, 8, 8),
    endTime: endTime,
    status: status,
    totalTransactions: totalTransactions,
    totalShiftPkr: totalShiftPkr,
    totalShiftLiters: totalShiftLiters,
  );
}

void main() {
  group('ShiftLedgerSummary.overlayWithSales', () {
    test('replaces LIVE shift totals from committed sales', () {
      final ShiftLedgerSummary live = _summary(
        shiftId: 'SHF-12',
        status: ManagerShiftStatus.open,
        totalTransactions: 1,
        totalShiftPkr: 100,
        totalShiftLiters: 1,
      );
      final ShiftLedgerSummary next = live.overlayWithSales(<SaleTransaction>[
        _sale(shiftId: 'SHF-12', liters: 10, pkr: 2800, tokenNo: 100001),
        _sale(shiftId: 'SHF-12', liters: 5, pkr: 1400, tokenNo: 100002),
        _sale(shiftId: 'SHF-99', liters: 50, pkr: 9999, tokenNo: 100003),
      ]);

      expect(next.totalTransactions, 2);
      expect(next.totalShiftPkr, 4200);
      expect(next.totalShiftLiters, 15);
    });

    test('keeps SQLite totals when memory cache has not caught up', () {
      final ShiftLedgerSummary live = _summary(
        shiftId: 'SHF-12',
        status: ManagerShiftStatus.open,
        totalTransactions: 4,
        totalShiftPkr: 800,
        totalShiftLiters: 8,
      );
      final ShiftLedgerSummary next = live.overlayWithSales(
        const <SaleTransaction>[],
      );

      expect(next.totalTransactions, 4);
      expect(next.totalShiftPkr, 800);
      expect(next.totalShiftLiters, 8);
    });

    test('does not rewrite closed shift aggregates', () {
      final ShiftLedgerSummary closed = _summary(
        shiftId: 'SHF-12',
        status: ManagerShiftStatus.closed,
        totalTransactions: 3,
        totalShiftPkr: 500,
        totalShiftLiters: 2,
      );
      final ShiftLedgerSummary next = closed.overlayWithSales(<SaleTransaction>[
        _sale(shiftId: 'SHF-12', liters: 99, pkr: 9900),
      ]);

      expect(next.totalTransactions, 3);
      expect(next.totalShiftPkr, 500);
      expect(next.totalShiftLiters, 2);
    });

    test('includes untagged committed sales inside the live shift window', () {
      final ShiftLedgerSummary live = _summary(
        shiftId: 'SHF-12',
        status: ManagerShiftStatus.open,
        totalTransactions: 0,
        totalShiftPkr: 0,
        totalShiftLiters: 0,
      );
      final ShiftLedgerSummary next = live.overlayWithSales(<SaleTransaction>[
        _sale(shiftId: '', liters: 12, pkr: 3360),
      ]);

      expect(next.totalTransactions, 1);
      expect(next.totalShiftPkr, 3360);
      expect(next.totalShiftLiters, 12);
    });

    test('merges in-memory workspace sales before SQLite refresh', () {
      final ShiftLedgerSummary live = _summary(
        shiftId: 'SHF-12',
        status: ManagerShiftStatus.open,
        totalTransactions: 0,
        totalShiftPkr: 0,
        totalShiftLiters: 0,
      );
      final ShiftLedgerSummary next = live.overlayWithSales(
        const <SaleTransaction>[],
        workspaceSales: <HelperSaleRecord>[
          HelperSaleRecord(
            tokenNo: 100002,
            timestamp: DateTime(2026, 9, 8, 11),
            helperId: 'h-1',
            helperName: 'Ali',
            unitId: 1,
            fuelType: kDieselFuelType,
            volumeLiters: 8,
            rate: 280,
            amountPkr: 2240,
            shiftId: 'SHF-12',
          ),
        ],
      );

      expect(next.totalTransactions, 1);
      expect(next.totalShiftPkr, 2240);
      expect(next.totalShiftLiters, 8);
    });
  });

  test('parseShiftPk reads SHF-prefixed ids', () {
    expect(parseShiftPk('SHF-12'), 12);
    expect(parseShiftPk('12'), 12);
    expect(parseShiftPk(''), isNull);
  });

  test('manager badge uses name and role', () {
    final ShiftLedgerSummary row = _summary(
      shiftId: 'SHF-1',
      status: ManagerShiftStatus.open,
    );
    expect(row.managerBadgeLabel, 'Saleem (MANAGER)');
  });

  group('shift pager', () {
    final List<ShiftLedgerSummary> shifts = <ShiftLedgerSummary>[
      _summary(
        shiftId: 'SHF-3',
        status: ManagerShiftStatus.open,
        startTime: DateTime(2026, 9, 10, 8),
      ),
      _summary(
        shiftId: 'SHF-2',
        status: ManagerShiftStatus.closed,
        startTime: DateTime(2026, 9, 8, 8),
        endTime: DateTime(2026, 9, 8, 20),
      ),
      _summary(
        shiftId: 'SHF-1',
        status: ManagerShiftStatus.closed,
        startTime: DateTime(2026, 9, 1, 8),
        endTime: DateTime(2026, 9, 1, 20),
      ),
    ];

    test('drops shifts outside the date range', () {
      final List<ShiftLedgerSummary> filtered = filterShiftsByRange(
        shifts,
        from: DateTime(2026, 9, 8),
        to: DateTime(2026, 9, 8),
      );
      expect(filtered.map((ShiftLedgerSummary row) => row.shiftId), <String>[
        'SHF-2',
      ]);
    });

    test('snaps a missing selected id to the first remaining shift', () {
      expect(resolveShiftIndex(shifts, 'SHF-99'), 0);
      expect(resolveSelectedShift(shifts, 'SHF-99')?.shiftId, 'SHF-3');
    });

    test('arrow steps clamp at the ends', () {
      expect(steppedShiftId(shifts, 'SHF-3', 1), 'SHF-2');
      expect(steppedShiftId(shifts, 'SHF-2', 1), 'SHF-1');
      expect(steppedShiftId(shifts, 'SHF-1', 1), 'SHF-1');
      expect(steppedShiftId(shifts, 'SHF-3', -1), 'SHF-3');
      expect(steppedShiftId(shifts, null, 1), 'SHF-2');
    });
  });

  group('focused sales slice', () {
    test('shift plus unit filter drives KPIs and rows', () {
      final ShiftLedgerSummary shift = _summary(
        shiftId: 'SHF-1',
        status: ManagerShiftStatus.closed,
        endTime: DateTime(2026, 9, 8, 20),
      );
      final List<SaleTransaction> source = liveSalesForShift(
        summary: shift,
        committed: <SaleTransaction>[
          _sale(
            shiftId: 'SHF-1',
            liters: 10,
            pkr: 2800,
            tokenNo: 100001,
            unitId: 1,
            timestamp: DateTime(2026, 9, 8, 10),
          ),
          _sale(
            shiftId: 'SHF-1',
            liters: 5,
            pkr: 1400,
            tokenNo: 100002,
            unitId: 2,
            timestamp: DateTime(2026, 9, 8, 11),
          ),
          _sale(
            shiftId: 'SHF-1',
            liters: 8,
            pkr: 2240,
            tokenNo: 100003,
            unitId: 1,
            timestamp: DateTime(2026, 9, 8, 12),
            payment: PaymentMethod.udhaar,
          ),
          _sale(
            shiftId: 'SHF-2',
            liters: 50,
            pkr: 9999,
            tokenNo: 100004,
            unitId: 1,
            timestamp: DateTime(2026, 9, 8, 13),
          ),
        ],
      );
      final SalesLedgerSnapshot slice =
          SalesTransactionRepository.querySnapshot(source, unitId: 1);

      expect(slice.totalCount, 2);
      expect(slice.totalAmountPkr, 5040);
      expect(slice.totalVolumeLiters, 18);
      expect(slice.udhaarAmountPkr, 2240);
      expect(slice.udhaarCount, 1);
      expect(
        slice.rows.map((SaleTransaction row) => row.tokenNo).toList(),
        <int>[100003, 100001],
      );
    });
  });
}
