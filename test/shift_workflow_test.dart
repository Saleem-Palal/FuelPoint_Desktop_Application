import 'package:flutter_test/flutter_test.dart';

import 'package:fuel_dispenser/features/shift/domain/shift_lifecycle.dart';
import 'package:fuel_dispenser/features/shift/domain/shift_models.dart';
import 'package:fuel_dispenser/features/station/domain/dispenser_models.dart';

void main() {
  group('ShiftStatusStorage', () {
    test('persists LIVE for an open cashier window', () {
      expect(
        ShiftStatusStorage.toStorage(OperatorShiftStatus.open),
        ShiftStatusStorage.live,
      );
    });

    test('reads LIVE and legacy OPEN as the same live status', () {
      expect(ShiftStatusStorage.fromStorage('LIVE'), OperatorShiftStatus.open);
      expect(ShiftStatusStorage.fromStorage('OPEN'), OperatorShiftStatus.open);
      expect(ShiftStatusStorage.isLiveStatus('LIVE'), isTrue);
      expect(ShiftStatusStorage.isLiveStatus('OPEN'), isTrue);
    });

    test('maps pending and closed statuses', () {
      expect(
        ShiftStatusStorage.fromStorage('PENDING_RECONCILIATION'),
        OperatorShiftStatus.pendingReconciliation,
      );
      expect(
        ShiftStatusStorage.fromStorage('CLOSED'),
        OperatorShiftStatus.closed,
      );
    });
  });

  group('ShiftLifecycleGuard', () {
    test('blocks handover on the first dispensing unit', () {
      expect(ShiftLifecycleGuard.firstDispensingUnit(<int>[3, 1]), 1);
      expect(
        ShiftLifecycleGuard.handoverBlockedMessage(3),
        contains('Unit #3 is actively dispensing'),
      );
    });

    test('allows handover when no unit is pumping', () {
      expect(ShiftLifecycleGuard.firstDispensingUnit(const <int>[]), isNull);
    });
  });

  group('ShiftMeterSnapshot', () {
    test('round-trips unit totalizers', () {
      const Map<int, double> meters = <int, double>{1: 1200.5, 2: 88};
      final String encoded = ShiftMeterSnapshot.encode(meters);
      final Map<int, double> decoded = ShiftMeterSnapshot.decode(encoded);
      expect(decoded[1], 1200.5);
      expect(decoded[2], 88);
    });
  });

  group('HelperUnitAssignmentSnapshot', () {
    test('round-trips assigned units so duty survives app resume', () {
      const List<int> units = <int>[3, 1, 1, 2];
      final String encoded = HelperUnitAssignmentSnapshot.encode(units);
      expect(encoded, '[1,2,3]');
      expect(HelperUnitAssignmentSnapshot.decode(encoded), <int>[1, 2, 3]);
    });

    test('empty or invalid storage is unassigned, not a crash', () {
      expect(HelperUnitAssignmentSnapshot.encode(const <int>[]), '[]');
      expect(HelperUnitAssignmentSnapshot.decode(null), isEmpty);
      expect(HelperUnitAssignmentSnapshot.decode('[]'), isEmpty);
      expect(HelperUnitAssignmentSnapshot.decode('{bad'), isEmpty);
    });
  });

  group('atomic handover result', () {
    test('keeps outgoing pending tally and incoming LIVE', () {
      expect(
        ShiftStatusStorage.toStorage(OperatorShiftStatus.pendingReconciliation),
        'PENDING_RECONCILIATION',
      );
      expect(ShiftStatusStorage.toStorage(OperatorShiftStatus.open), 'LIVE');
      final DateTime start = DateTime(2026, 9, 9, 8);
      final DateTime handoff = DateTime(2026, 9, 9, 16);
      final ShiftHandoverResult result = ShiftHandoverResult(
        outcome: HandoverOutcome.handedOff,
        pending: ReconciliationSnapshot(
          shift: OperatorShiftRecord(
            shiftId: 'SHF-1',
            operatorId: 'mgr-out',
            operatorName: 'Outgoing',
            role: OperatorRole.operator,
            startTime: start,
            endTime: handoff,
            expectedCash: 5000,
            status: OperatorShiftStatus.pendingReconciliation,
          ),
          metrics: ShiftWindowMetrics.empty,
        ),
        opened: OperatorShiftRecord(
          shiftId: 'SHF-2',
          operatorId: 'mgr-in',
          operatorName: 'Incoming',
          role: OperatorRole.operator,
          startTime: handoff,
          expectedCash: 0,
          status: OperatorShiftStatus.open,
        ),
      );
      expect(result.isSuccess, isTrue);
      expect(result.pending, isNotNull);
      expect(
        result.pending!.shift.status,
        OperatorShiftStatus.pendingReconciliation,
      );
      expect(result.opened?.status, OperatorShiftStatus.open);
      expect(result.closed, isNull);
    });

    test('unitsDispensing is not a successful handoff', () {
      const ShiftHandoverResult result = ShiftHandoverResult(
        outcome: HandoverOutcome.unitsDispensing,
        blockedUnitId: 3,
      );
      expect(result.isSuccess, isFalse);
      expect(result.blockedUnitId, 3);
    });
  });

  group('expected cash in hand', () {
    test('is cash sales plus in-cash udhaar recovery', () {
      const ShiftWindowMetrics metrics = ShiftWindowMetrics(
        sales: <HelperSaleRecord>[],
        fuelCashSales: 1000,
        udhaarSales: 4000,
        accountSales: 250,
        udhaarRecoveryTotal: 200,
        totalLiters: 10,
      );
      expect(metrics.expectedCashInHand, 1200);
      expect(metrics.totalSale, 5250);
    });
  });

  group('partial account sale metrics', () {
    HelperSaleRecord sale({
      required PaymentMethod payment,
      required double amountPkr,
      double cashAmount = 0,
      double accountAmount = 0,
    }) {
      return HelperSaleRecord(
        tokenNo: 200004,
        timestamp: DateTime(2026, 9, 14, 10),
        helperId: 'h-1',
        helperName: 'Ali',
        unitId: 2,
        fuelType: kDieselFuelType,
        volumeLiters: 10,
        rate: 256.32,
        amountPkr: amountPkr,
        payment: payment,
        cashAmount: cashAmount,
        accountAmount: accountAmount,
      );
    }

    test('splits Cash Now into cash and remainder into account', () {
      final ShiftWindowMetrics metrics = metricsForSales(<HelperSaleRecord>[
        sale(
          payment: PaymentMethod.bankAccount,
          amountPkr: 2989,
          cashAmount: 2000,
          accountAmount: 989,
        ),
      ]);
      expect(metrics.fuelCashSales, 2000);
      expect(metrics.accountSales, 989);
      expect(metrics.totalSale, 2989);
      expect(metrics.expectedCashInHand, 2000);
    });

    test('cash-only with cashAmount set uses Cash column not AMOUNT twice', () {
      final ShiftWindowMetrics metrics = metricsForSales(<HelperSaleRecord>[
        sale(payment: PaymentMethod.cash, amountPkr: 2989, cashAmount: 2989),
      ]);
      expect(metrics.fuelCashSales, 2989);
      expect(metrics.accountSales, 0);
      expect(metrics.totalSale, 2989);
    });

    test('legacy account rows with empty split columns stay all account', () {
      final ShiftWindowMetrics metrics = metricsForSales(<HelperSaleRecord>[
        sale(payment: PaymentMethod.easyPaisa, amountPkr: 5000),
      ]);
      expect(metrics.fuelCashSales, 0);
      expect(metrics.accountSales, 5000);
      expect(metrics.expectedCashInHand, 0);
    });

    test('test fills stay listed, add liters, and skip cash and count', () {
      final ShiftWindowMetrics metrics = metricsForSales(<HelperSaleRecord>[
        sale(payment: PaymentMethod.cash, amountPkr: 1000, cashAmount: 1000),
        sale(
          payment: PaymentMethod.cash,
          amountPkr: 500,
        ).copyWith(isTest: true, tokenNo: 200005, volumeLiters: 5),
      ]);
      expect(metrics.sales.length, 2);
      expect(metrics.commercialSaleCount, 1);
      expect(metrics.fuelCashSales, 1000);
      expect(metrics.totalLiters, 15);
      expect(metrics.expectedCashInHand, 1000);
    });
  });

  group('owner-elevation audit flag', () {
    test('stores 1 when the owner is elevated', () {
      expect(elevatedByOwnerFlag(true), 1);
      expect(elevatedByOwnerFlag(false), 0);
    });
  });
}
