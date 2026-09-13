import 'package:flutter_test/flutter_test.dart';

import 'package:fuel_dispenser/features/shift/domain/shift_lifecycle.dart';
import 'package:fuel_dispenser/features/shift/domain/shift_models.dart';

void main() {
  group('ShiftStatusStorage', () {
    test('persists LIVE for an open cashier window', () {
      expect(
        ShiftStatusStorage.toStorage(ManagerShiftStatus.open),
        ShiftStatusStorage.live,
      );
    });

    test('reads LIVE and legacy OPEN as the same live status', () {
      expect(ShiftStatusStorage.fromStorage('LIVE'), ManagerShiftStatus.open);
      expect(ShiftStatusStorage.fromStorage('OPEN'), ManagerShiftStatus.open);
      expect(ShiftStatusStorage.isLiveStatus('LIVE'), isTrue);
      expect(ShiftStatusStorage.isLiveStatus('OPEN'), isTrue);
    });

    test('maps pending and closed statuses', () {
      expect(
        ShiftStatusStorage.fromStorage('PENDING_RECONCILIATION'),
        ManagerShiftStatus.pendingReconciliation,
      );
      expect(
        ShiftStatusStorage.fromStorage('CLOSED'),
        ManagerShiftStatus.closed,
      );
    });
  });

  group('ShiftLifecycleGuard', () {
    test('blocks handover on the first dispensing bay', () {
      expect(ShiftLifecycleGuard.firstDispensingBay(<int>[3, 1]), 1);
      expect(
        ShiftLifecycleGuard.handoverBlockedMessage(3),
        contains('Bay #3 is actively dispensing'),
      );
    });

    test('allows handover when no bay is pumping', () {
      expect(ShiftLifecycleGuard.firstDispensingBay(const <int>[]), isNull);
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

  group('atomic handover result', () {
    test('keeps outgoing pending tally and incoming LIVE', () {
      expect(
        ShiftStatusStorage.toStorage(ManagerShiftStatus.pendingReconciliation),
        'PENDING_RECONCILIATION',
      );
      expect(ShiftStatusStorage.toStorage(ManagerShiftStatus.open), 'LIVE');
      final DateTime start = DateTime(2026, 9, 9, 8);
      final DateTime handoff = DateTime(2026, 9, 9, 16);
      final ShiftHandoverResult result = ShiftHandoverResult(
        outcome: HandoverOutcome.handedOff,
        pending: ReconciliationSnapshot(
          shift: ManagerShiftRecord(
            shiftId: 'SHF-1',
            managerId: 'mgr-out',
            managerName: 'Outgoing',
            role: ManagerRole.manager,
            startTime: start,
            endTime: handoff,
            expectedCash: 5000,
            status: ManagerShiftStatus.pendingReconciliation,
          ),
          metrics: ShiftWindowMetrics.empty,
        ),
        opened: ManagerShiftRecord(
          shiftId: 'SHF-2',
          managerId: 'mgr-in',
          managerName: 'Incoming',
          role: ManagerRole.manager,
          startTime: handoff,
          expectedCash: 0,
          status: ManagerShiftStatus.open,
        ),
      );
      expect(result.isSuccess, isTrue);
      expect(result.pending, isNotNull);
      expect(
        result.pending!.shift.status,
        ManagerShiftStatus.pendingReconciliation,
      );
      expect(result.opened?.status, ManagerShiftStatus.open);
      expect(result.closed, isNull);
    });

    test('baysDispensing is not a successful handoff', () {
      const ShiftHandoverResult result = ShiftHandoverResult(
        outcome: HandoverOutcome.baysDispensing,
        blockedBayId: 3,
      );
      expect(result.isSuccess, isFalse);
      expect(result.blockedBayId, 3);
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

  group('owner-elevation audit flag', () {
    test('stores 1 when the owner is elevated', () {
      expect(elevatedByOwnerFlag(true), 1);
      expect(elevatedByOwnerFlag(false), 0);
    });
  });
}
