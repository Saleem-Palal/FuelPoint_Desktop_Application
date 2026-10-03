import 'dart:async';
import 'dart:math';

import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../access/domain/access_policy.dart';
import '../../customer/presentation/customer_store.dart';
import '../../shift/domain/shift_models.dart';
import '../../shift/presentation/shift_providers.dart';
import '../../../providers/settings_provider.dart';
import '../../../services/database_helper.dart';
import '../data/dispenser_socket_manager.dart';
import '../data/mock_telemetry_simulator.dart';
import '../data/payment_buzzer.dart';
import '../data/printer_queue.dart';
import '../data/sales_transaction_repository.dart';
import '../data/transaction_store.dart';
import '../domain/dispenser_models.dart';
import '../domain/dispenser_monitor_models.dart';
import '../domain/esp_token_log.dart';
import '../domain/fuel_precision.dart';
import '../domain/money_format.dart';
import '../domain/sale_fulfillment.dart';
import 'dispenser_monitor_providers.dart';

final transactionStoreProvider = Provider<TransactionStore>((Ref ref) {
  return TransactionStore();
});

final salesTransactionRepositoryProvider = Provider<SalesTransactionRepository>(
  (Ref ref) {
    return SalesTransactionRepository();
  },
);

/// SQLite `sales_transactions` cache. Refreshed after confirm / edit / settle.
final committedSalesProvider = StateProvider<List<SaleTransaction>>(
  (Ref ref) => const <SaleTransaction>[],
);

final pendingAccountSalesProvider = FutureProvider<List<SaleTransaction>>((
  Ref ref,
) async {
  ref.watch(historyRevisionProvider);
  return ref.read(salesTransactionRepositoryProvider).pendingAccount();
});

class MeterMismatchNotice {
  const MeterMismatchNotice({
    required this.unitId,
    required this.previousTokenNo,
    required this.currentTokenNo,
    required this.previousClosing,
    required this.currentOpening,
  });

  final int unitId;
  final int previousTokenNo;
  final int currentTokenNo;
  final double previousClosing;
  final double currentOpening;

  String get previousClosingLabel => formatMeterReading(previousClosing);
  String get currentOpeningLabel => formatMeterReading(currentOpening);
  String get differenceLabel => formatMeterReading(
    storedNumberToDouble(
      truncateMeterCheck(currentOpening) - truncateMeterCheck(previousClosing),
    ),
  );
}

/// Non-null after a saved sale whose opening meter ≠ previous closing on the same unit.
final meterMismatchNoticeProvider = StateProvider<MeterMismatchNotice?>(
  (Ref ref) => null,
);

/// Bumped after `sales_history` / `purchase_history` writes so ledger slices rebuild.
final historyRevisionProvider = StateProvider<int>((Ref ref) => 0);

void bumpHistoryRevision(StateController<int> revision) {
  revision.state = revision.state + 1;
}

final selectedDispenserIndexProvider = StateProvider<int>((Ref ref) => 1);

final currentTokenIdProvider = Provider<int>((Ref ref) {
  final int unitId = ref.watch(selectedDispenserIndexProvider);
  final int sequence =
      ref.watch(stationControllerProvider).sequences[unitId] ?? 1;
  return tokenIdFor(unitId: unitId, sequence: sequence);
});

final selectedUnitProvider = Provider<DispenserUnit>((Ref ref) {
  final int unitId = ref.watch(selectedDispenserIndexProvider);
  return ref.watch(stationControllerProvider).unit(unitId);
});

/// Live LCD numbers for one unit. Ignores last-sale / sequence so the 30-row
/// table does not rebuild at telemetry rate.
class LiveUnitLcd {
  const LiveUnitLcd({
    required this.amountPkr,
    required this.volumeLiters,
    required this.rate,
    required this.meterCount,
    required this.status,
    required this.offline,
  });

  final double amountPkr;
  final double volumeLiters;
  final double rate;
  final double meterCount;
  final DispenserRunState status;
  final bool offline;

  @override
  bool operator ==(Object other) {
    return other is LiveUnitLcd &&
        other.amountPkr == amountPkr &&
        other.volumeLiters == volumeLiters &&
        other.rate == rate &&
        other.meterCount == meterCount &&
        other.status == status &&
        other.offline == offline;
  }

  @override
  int get hashCode =>
      Object.hash(amountPkr, volumeLiters, rate, meterCount, status, offline);
}

final liveUnitLcdProvider = Provider.family<LiveUnitLcd, int>((
  Ref ref,
  int unitId,
) {
  return ref.watch(
    stationControllerProvider.select((StationState station) {
      final DispenserUnit unit = station.unit(unitId);
      return LiveUnitLcd(
        amountPkr: unit.amountPkr,
        volumeLiters: unit.volumeLiters,
        rate: unit.rate,
        meterCount: unit.meterCount,
        status: unit.status,
        offline:
            shouldEnforceStationGuards &&
            !station.endpoint(unitId).connected &&
            !unit.isCycleComplete,
      );
    }),
  );
});

final paymentSheetUnitsProvider = StateProvider<Set<int>>((Ref ref) => <int>{});

final paymentSubmitNonceProvider = StateProvider<int>((Ref ref) => 0);

class PaymentCycleSignal {
  const PaymentCycleSignal({
    required this.delta,
    required this.seq,
    required this.axis,
  });

  final int delta;
  final int seq;
  final PaymentCycleAxis axis;
}

enum PaymentCycleAxis { method, rail }

final paymentCycleSignalProvider = StateProvider<PaymentCycleSignal?>(
  (Ref ref) => null,
);

void openPaymentSheet(WidgetRef ref, int unitId) {
  ref.read(selectedDispenserIndexProvider.notifier).state = unitId;
  ref.read(paymentSubmitNonceProvider.notifier).state =
      ref.read(paymentSubmitNonceProvider) + 1;
}

void closePaymentSheet(WidgetRef ref, int unitId) {
  final Set<int> next = <int>{...ref.read(paymentSheetUnitsProvider)};
  next.remove(unitId);
  ref.read(paymentSheetUnitsProvider.notifier).state = next;
}

void cycleSelectedPaymentMethod(WidgetRef ref, int delta) {
  _emitPaymentCycle(ref, delta: delta, axis: PaymentCycleAxis.method);
}

void cycleSelectedAccountRail(WidgetRef ref, int delta) {
  _emitPaymentCycle(ref, delta: delta, axis: PaymentCycleAxis.rail);
}

void _emitPaymentCycle(
  WidgetRef ref, {
  required int delta,
  required PaymentCycleAxis axis,
}) {
  final int seq = (ref.read(paymentCycleSignalProvider)?.seq ?? 0) + 1;
  ref.read(paymentCycleSignalProvider.notifier).state = PaymentCycleSignal(
    delta: delta,
    seq: seq,
    axis: axis,
  );
}

final receiptOverlayTxnsProvider = StateProvider<Map<int, SaleTransaction>>(
  (Ref ref) => <int, SaleTransaction>{},
);

final espRecoverOffersProvider = StateProvider<List<EspTokenLogRow>>(
  (Ref ref) => const <EspTokenLogRow>[],
);

final espLastTenByUnitProvider = StateProvider<Map<int, List<EspTokenLogRow>>>(
  (Ref ref) => const <int, List<EspTokenLogRow>>{},
);

@immutable
class LowStockAlert {
  const LowStockAlert({
    required this.remainingLiters,
    required this.thresholdLiters,
  });

  final double remainingLiters;
  final double thresholdLiters;
}

class LowStockAlertNotifier extends Notifier<LowStockAlert?> {
  @override
  LowStockAlert? build() => null;

  /// Show once while below threshold; clear when restocked or the alert is off.
  Future<void> sync() async {
    final double threshold = ref.read(settingsProvider).lowStockThresholdLiters;
    if (threshold <= 0) {
      _clear();
      return;
    }
    try {
      final ({double quantity, double averageRate, double amount}) stock =
          await DatabaseHelper.instance.getDieselStock();
      if (stock.quantity >= threshold) {
        _clear();
        return;
      }
      final LowStockAlert? current = state;
      if (current != null &&
          current.remainingLiters == stock.quantity &&
          current.thresholdLiters == threshold) {
        return;
      }
      state = LowStockAlert(
        remainingLiters: stock.quantity,
        thresholdLiters: threshold,
      );
    } catch (error, stack) {
      debugPrint('Low stock check failed: $error\n$stack');
    }
  }

  void _clear() {
    if (state != null) {
      state = null;
    }
  }
}

/// Sticky until tank liters are at or above the threshold (or the alert is off).
final lowStockAlertProvider =
    NotifierProvider<LowStockAlertNotifier, LowStockAlert?>(
      LowStockAlertNotifier.new,
    );

void showUnitReceiptOverlay(WidgetRef ref, SaleTransaction txn) {
  final Map<int, SaleTransaction> next = Map<int, SaleTransaction>.from(
    ref.read(receiptOverlayTxnsProvider),
  );
  next[txn.unitId] = txn;
  ref.read(receiptOverlayTxnsProvider.notifier).state = next;
}

void dismissUnitReceiptOverlay(WidgetRef ref, int unitId) {
  final Map<int, SaleTransaction> next = Map<int, SaleTransaction>.from(
    ref.read(receiptOverlayTxnsProvider),
  );
  if (!next.containsKey(unitId)) {
    return;
  }
  next.remove(unitId);
  ref.read(receiptOverlayTxnsProvider.notifier).state = next;
}

void nudgeSelectedUnit(WidgetRef ref, int delta) {
  final List<int> ids = visibleDispenserUnitIds(
    showUnit5: ref.read(settingsProvider).showUnit5,
  );
  if (ids.isEmpty) {
    return;
  }
  final int current = ref.read(selectedDispenserIndexProvider);
  int index = ids.indexOf(current);
  if (index < 0) {
    index = 0;
  }
  index = (index + delta) % ids.length;
  if (index < 0) {
    index += ids.length;
  }
  ref.read(selectedDispenserIndexProvider.notifier).state = ids[index];
}

final stationControllerProvider =
    NotifierProvider<StationController, StationState>(StationController.new);

/// Weighted-average diesel cost from Purchase. Not painted onto unit RATE LCDs.
final dieselAverageRateProvider = Provider<double>((Ref ref) {
  return ref.watch(
    stationControllerProvider.select(
      (StationState station) => station.dieselAverageRate,
    ),
  );
});

class StationController extends Notifier<StationState> {
  late final TransactionStore _store;
  late final SalesTransactionRepository _salesDb;
  late final DispenserSocketManager _sockets;
  late final MockTelemetrySimulator _simulator;
  late final PrinterQueue _printer;
  late final PaymentBuzzer _buzzer;

  final Map<int, Timer> _abortTimers = <int, Timer>{};
  final Map<int, Timer> _monitorUnlockTimers = <int, Timer>{};
  final Set<int> _confirmInFlight = <int>{};
  final Set<int> _pendingConfirmUnits = <int>{};
  final Set<int> _suppressConfirmUntilReset = <int>{};
  final Map<int, double> _confirmedLiters = <int, double>{};
  final Map<int, double> _lastPumpingLiters = <int, double>{};
  final Set<int> _autoSaving = <int>{};
  final Random _demoLitersRandom = Random();

  PrinterQueue get printerQueue => _printer;

  @override
  StationState build() {
    _store = ref.read(transactionStoreProvider);
    _salesDb = ref.read(salesTransactionRepositoryProvider);
    _printer = PrinterQueue();
    _buzzer = PaymentBuzzer();
    _simulator = MockTelemetrySimulator(emit: _onTelemetry);
    _sockets = DispenserSocketManager(
      onTelemetry: (DispenserTelemetry packet) {
        // Live ESP must not cancel or overwrite an in-progress debug demo.
        if (kDebugMode && _simulator.isRunning(packet.unitId)) {
          return;
        }
        _simulator.cancel(packet.unitId);
        _onTelemetry(packet);
      },
      onOffline: _onOffline,
      onConnected: _onSocketConnected,
      onPendingSale: _onPendingSale,
      onSyncLog: _onSyncLog,
      nextSequenceFor: (int unitId) => state.sequences[unitId] ?? 1,
      onWire: (DispenserWireFrame frame) {
        ref.read(dispenserMonitorProvider.notifier).ingestWire(frame);
      },
    );
    ref.listen<ShiftWorkspaceState>(shiftWorkspaceProvider, (
      ShiftWorkspaceState? previous,
      ShiftWorkspaceState next,
    ) {
      _syncHardwareToShift(next);
    });
    ref.onDispose(() {
      for (final Timer timer in _abortTimers.values) {
        timer.cancel();
      }
      _abortTimers.clear();
      for (final Timer timer in _monitorUnlockTimers.values) {
        timer.cancel();
      }
      _monitorUnlockTimers.clear();
      _buzzer.dispose();
      _simulator.dispose();
      unawaited(_sockets.dispose());
    });
    Future<void>(_bootstrap);
    return StationState.seed();
  }

  Future<void> _bootstrap() async {
    await _store.init();
    final Map<int, UnitEndpoint> stored =
        await DispenserSocketManager.loadEndpoints();
    state = state.copyWith(endpoints: stored);
    await _sockets.start();
    _syncHardwareToShift(ref.read(shiftWorkspaceProvider));
    for (final int unitId in dispenserUnitIds) {
      if (unitId == kOptionalDispenserUnitId) {
        continue;
      }
      connectUnit(unitId);
    }
    final Map<int, int> dbSequences = await _salesSequences();
    await _refreshCommittedSales();
    try {
      await reloadCustomerPersistence(ref);
    } catch (error, stack) {
      debugPrint('Could not load customers / udhaar ledger: $error\n$stack');
    }
    state = state.copyWith(sequences: dbSequences);
  }

  Future<void> _refreshCommittedSales() async {
    try {
      final List<SaleTransaction> rows = await _salesDb.all(includeTest: true);
      final List<SaleTransaction> recent = await _salesDb.recent(
        limit: 20,
        includeTest: true,
      );
      ref.read(committedSalesProvider.notifier).state = rows;
      state = state.copyWith(recentTransactions: recent);
      _applyLastSales(rows);
    } catch (error, stack) {
      debugPrint('Could not load sales_transactions: $error\n$stack');
      ref.read(committedSalesProvider.notifier).state =
          const <SaleTransaction>[];
      state = state.copyWith(recentTransactions: const <SaleTransaction>[]);
    }
  }

  /// Reloads SQLite-backed sales, sequences, and customers from disk.
  Future<void> reloadPersistedData() async {
    final Map<int, int> dbSequences = await _salesSequences();
    await _refreshCommittedSales();
    try {
      await reloadCustomerPersistence(ref);
    } catch (error, stack) {
      debugPrint('Could not reload customers after DB change: $error\n$stack');
    }
    state = state.copyWith(sequences: dbSequences);
    bumpHistoryRevision(ref.read(historyRevisionProvider.notifier));
  }

  Future<Map<int, int>> _salesSequences() async {
    try {
      return await _salesDb.sequencesFromHistory();
    } catch (error, stack) {
      debugPrint('Could not load sale sequences: $error\n$stack');
      return <int, int>{
        for (final int unitId in dispenserUnitIds) unitId: 1,
        kDirectSaleUnitId: 0,
      };
    }
  }

  bool _liveTelemetryUnchanged(DispenserUnit previous, DispenserUnit next) {
    return previous.status == next.status &&
        previous.amountPkr == next.amountPkr &&
        previous.volumeLiters == next.volumeLiters &&
        previous.rate == next.rate &&
        previous.meterCount == next.meterCount &&
        previous.keypadLocked == next.keypadLocked &&
        previous.lastEspTxId == next.lastEspTxId &&
        previous.pendingSavedToken == next.pendingSavedToken &&
        previous.cycleOpeningMeter == next.cycleOpeningMeter &&
        previous.testMode == next.testMode &&
        previous.testCycle == next.testCycle;
  }

  void _patchUnit(int unitId, DispenserUnit next) {
    final DispenserUnit previous = state.unit(unitId);
    if (_liveTelemetryUnchanged(previous, next)) {
      return;
    }
    final Map<int, DispenserUnit> units = Map<int, DispenserUnit>.from(
      state.units,
    );
    units[unitId] = next;
    state = state.copyWith(units: units);
    _syncBuzzer();
  }

  DispenserUnit _withSavedLastSale(DispenserUnit unit, SaleTransaction? row) {
    if (row == null) {
      return unit.copyWith(
        lastRupees: '',
        lastLiters: '',
        lastTime: '',
        lastCashier: '',
      );
    }
    return unit.copyWith(
      lastRupees: formatDispenserPkr(row.amountPkr),
      lastLiters: formatLiters(row.volumeLiters),
      lastTime: formatClock(row.timestamp),
      lastCashier: row.cashierName.trim(),
      lastCustomer: row.customerName,
      lastVehicleNo: row.vehicleNo,
      lastPayment: row.payment,
    );
  }

  void _applyLastSales(List<SaleTransaction> rows) {
    final Map<int, SaleTransaction> latest = <int, SaleTransaction>{};
    for (final SaleTransaction row in rows) {
      if (row.isTest) {
        continue;
      }
      latest.putIfAbsent(row.unitId, () => row);
    }
    final Map<int, DispenserUnit> units = Map<int, DispenserUnit>.from(
      state.units,
    );
    bool changed = false;
    for (final int unitId in dispenserUnitIds) {
      final DispenserUnit unit = state.unit(unitId);
      final DispenserUnit next = _withSavedLastSale(unit, latest[unitId]);
      if (next.lastRupees == unit.lastRupees &&
          next.lastLiters == unit.lastLiters &&
          next.lastTime == unit.lastTime &&
          next.lastCashier == unit.lastCashier) {
        continue;
      }
      units[unitId] = next;
      changed = true;
    }
    if (changed) {
      state = state.copyWith(units: units);
    }
  }

  void _syncBuzzer() {
    // PC speaker only while Confirm is actually enabled on a unit.
    final bool waitingForConfirm = state.units.values.any(
      (DispenserUnit unit) => unit.canConfirmPayment,
    );
    if (waitingForConfirm) {
      unawaited(_buzzer.start());
      return;
    }
    _buzzer.stop();
  }

  void _clearAbortNotice(int unitId) {
    _abortTimers.remove(unitId)?.cancel();
    if (!state.abortNotices.containsKey(unitId)) {
      return;
    }
    final Map<int, String> notices = Map<int, String>.from(state.abortNotices);
    notices.remove(unitId);
    state = state.copyWith(abortNotices: notices);
  }

  void _flashAbortNotice(int unitId) {
    _abortTimers.remove(unitId)?.cancel();
    final Map<int, String> notices = Map<int, String>.from(state.abortNotices);
    notices[unitId] = 'Cycle Cancelled (0.00 L)';
    state = state.copyWith(abortNotices: notices);
    _abortTimers[unitId] = Timer(const Duration(seconds: 2), () {
      _abortTimers.remove(unitId);
      final Map<int, String> next = Map<int, String>.from(state.abortNotices);
      next.remove(unitId);
      state = state.copyWith(abortNotices: next);
    });
  }

  /// Recalculated WAC from Purchase. Does not overwrite per-unit programmed rates.
  void setDieselAverageRate(double rate) {
    if (state.dieselAverageRate == rate) {
      return;
    }
    state = state.copyWith(dieselAverageRate: rate);
  }

  void _onTelemetry(DispenserTelemetry packet) {
    final DispenserUnit previous = state.unit(packet.unitId);
    final String cmd = packet.cmd.toUpperCase();
    DispenserRunState nextStatus = packet.status;
    if (packet.status == DispenserRunState.dispensing) {
      _lastPumpingLiters[packet.unitId] = packet.volumeLiters;
      _pendingConfirmUnits.remove(packet.unitId);
      _suppressConfirmUntilReset.remove(packet.unitId);
      _confirmedLiters.remove(packet.unitId);
    }

    final double? pumped = _lastPumpingLiters[packet.unitId];
    final bool hadPump =
        previous.isDispensing ||
        (pumped != null && pumped.abs() >= DispenserUnit.zeroVolumeEpsilon);
    final bool dispensingToIdle =
        packet.status == DispenserRunState.idle &&
        hadPump &&
        !previous.isCycleComplete;
    final bool saleCompleteCmd = cmd == 'SALE_COMPLETE';
    final bool suppressConfirm = _suppressConfirmUntilReset.contains(
      packet.unitId,
    );

    final bool nullHangup =
        packet.isNoSaleCmd ||
        ((dispensingToIdle || saleCompleteCmd) &&
            isNullHangupCycle(
              lastPumpingLiters: _lastPumpingLiters[packet.unitId],
              packetLiters: packet.volumeLiters,
            ));
    if (nullHangup &&
        !previous.isCycleComplete &&
        !_pendingConfirmUnits.contains(packet.unitId)) {
      _pendingConfirmUnits.remove(packet.unitId);
      _lastPumpingLiters.remove(packet.unitId);
      unawaited(
        _handleZeroVolumeAbort(packet, showNotice: previous.isDispensing),
      );
      ref.read(dispenserMonitorProvider.notifier).ingestTelemetryExtras(packet);
      return;
    }

    if (!suppressConfirm && (dispensingToIdle || saleCompleteCmd)) {
      _pendingConfirmUnits.add(packet.unitId);
      nextStatus = DispenserRunState.cycleComplete;
    } else if (_pendingConfirmUnits.contains(packet.unitId) &&
        packet.status != DispenserRunState.dispensing) {
      nextStatus = DispenserRunState.cycleComplete;
    } else if (!suppressConfirm &&
        previous.isCycleComplete &&
        packet.status != DispenserRunState.dispensing) {
      nextStatus = DispenserRunState.cycleComplete;
    }

    final bool holdComplete =
        nextStatus == DispenserRunState.cycleComplete && !suppressConfirm;
    double amountPkr = packet.amountPkr;
    double volumeLiters = packet.volumeLiters;
    if (holdComplete && volumeLiters.abs() < DispenserUnit.zeroVolumeEpsilon) {
      volumeLiters = previous.volumeLiters;
      amountPkr = previous.amountPkr;
    }

    if (nextStatus == DispenserRunState.dispensing) {
      _clearAbortNotice(packet.unitId);
      _dismissReceiptOverlay(packet.unitId);
    }

    double? cycleOpening = previous.cycleOpeningMeter;
    if (packet.status == DispenserRunState.dispensing && cycleOpening == null) {
      if (!previous.isDispensing ||
          previous.volumeLiters.abs() < DispenserUnit.zeroVolumeEpsilon) {
        cycleOpening = previous.meterCount;
      }
    } else if (!suppressConfirm &&
        (dispensingToIdle || saleCompleteCmd) &&
        cycleOpening == null &&
        !previous.isDispensing) {
      cycleOpening = previous.meterCount;
    }

    final bool latchTest = previous.testMode || previous.testCycle;

    _patchUnit(
      packet.unitId,
      previous.copyWith(
        status: nextStatus,
        amountPkr: packet.amountPkr,
        volumeLiters: packet.volumeLiters,
        rate: packet.rate,
        meterCount: packet.meterCount,
        keypadLocked: _pendingConfirmUnits.contains(packet.unitId)
            ? true
            : (_monitorUnlockTimers.containsKey(packet.unitId)
                  ? false
                  : packet.keypadLocked),
        lastPacketAt: DateTime.now(),
        lastEspTxId: packet.txId.trim().isNotEmpty
            ? packet.txId.trim()
            : previous.lastEspTxId,
        cycleOpeningMeter: cycleOpening,
        testCycle: latchTest,
      ),
    );
    if (nextStatus == DispenserRunState.cycleComplete && !latchTest) {
      unawaited(_autoInsertCashOnComplete(packet.unitId));
    }
    if (!state.endpoint(packet.unitId).connected) {
      _onSocketConnected(packet.unitId);
    }
    ref.read(dispenserMonitorProvider.notifier).ingestTelemetryExtras(packet);
  }

  Future<void> _handleZeroVolumeAbort(
    DispenserTelemetry packet, {
    required bool showNotice,
  }) async {
    final DispenserUnit previous = state.unit(packet.unitId);
    _patchUnit(
      packet.unitId,
      previous.copyWith(
        status: DispenserRunState.idle,
        amountPkr: packet.amountPkr,
        volumeLiters: packet.volumeLiters,
        rate: packet.rate,
        meterCount: packet.meterCount,
        keypadLocked: false,
        lastPacketAt: DateTime.now(),
        clearCycleOpeningMeter: true,
      ),
    );
    if (!showNotice) {
      return;
    }
    await _store.insertSystemLog(
      eventType: 'ZERO_VOLUME_ABORT',
      unitId: packet.unitId,
      details:
          'Hang-up at 0.00 L (idle LCD may replay last sale) — no lock, buzzer, or receipt',
    );
    _flashAbortNotice(packet.unitId);
  }

  void _onSocketConnected(int unitId) {
    final Map<int, UnitEndpoint> endpoints = Map<int, UnitEndpoint>.from(
      state.endpoints,
    );
    endpoints[unitId] = state.endpoint(unitId).copyWith(connected: true);
    state = state.copyWith(endpoints: endpoints);
    ref.read(dispenserMonitorProvider.notifier).markSocketOpened(unitId);
    _syncBuzzer();
    unawaited(_sockets.requestSyncLog(unitId));
    if (_suppressConfirmUntilReset.contains(unitId)) {
      unawaited(_sockets.confirmUnit(unitId));
    }
  }

  void _onOffline(int unitId) {
    final UnitEndpoint current = state.endpoint(unitId);
    final DispenserUnit unit = state.unit(unitId);
    if (!current.connected && (unit.isOffline || unit.isCycleComplete)) {
      return;
    }
    final Map<int, UnitEndpoint> endpoints = Map<int, UnitEndpoint>.from(
      state.endpoints,
    );
    endpoints[unitId] = current.copyWith(connected: false);
    if (shouldEnforceStationGuards &&
        !unit.isDispensing &&
        !unit.isCycleComplete) {
      _patchUnit(unitId, unit.copyWith(status: DispenserRunState.offline));
    }
    state = state.copyWith(endpoints: endpoints);
    ref.read(dispenserMonitorProvider.notifier).markSocketClosed(unitId);
  }

  void _onPendingSale(PendingEspSale sale) {
    // Old firmware QUEUE_REPLAY is not a ledger source. ACK only to silence it.
    if (sale.txId.isEmpty) {
      return;
    }
    unawaited(_sockets.ackTransaction(unitId: sale.unitId, txId: sale.txId));
  }

  Future<void> _onSyncLog(int unitId, List<EspTokenLogRow> rows) async {
    final List<EspTokenLogRow> unitRows = rows
        .where((EspTokenLogRow row) => row.unitId == unitId)
        .toList();
    try {
      final List<SaleTransaction> appRows = (await _salesDb.all(
        includeTest: true,
      )).where((SaleTransaction row) => row.unitId == unitId).toList();
      final List<EspTokenLogRow> sorted = List<EspTokenLogRow>.from(unitRows)
        ..sort((EspTokenLogRow a, EspTokenLogRow b) {
          final DateTime aAt = a.at ?? DateTime.fromMillisecondsSinceEpoch(0);
          final DateTime bAt = b.at ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bAt.compareTo(aAt);
        });
      final Map<int, List<EspTokenLogRow>> logs = Map<int, List<EspTokenLogRow>>.from(
        ref.read(espLastTenByUnitProvider),
      );
      logs[unitId] = sorted;
      ref.read(espLastTenByUnitProvider.notifier).state = logs;
      final List<EspTokenLogRow> missing = missingEspTokenRows(
        espRows: unitRows,
        appRows: appRows,
      );
      final Set<int> missingTokens = <int>{
        for (final EspTokenLogRow row in missing) row.token,
      };
      for (final EspTokenLogRow row in unitRows) {
        if (!missingTokens.contains(row.token)) {
          unawaited(_sockets.ackToken(unitId: unitId, token: row.token));
        }
      }
      final List<EspTokenLogRow> kept = ref
          .read(espRecoverOffersProvider)
          .where((EspTokenLogRow row) => row.unitId != unitId)
          .toList();
      ref.read(espRecoverOffersProvider.notifier).state = <EspTokenLogRow>[
        ...kept,
        ...missing,
      ];
    } catch (error, stack) {
      debugPrint('SYNC_LOG reconcile failed: $error\n$stack');
    }
  }

  Future<void> recoverAllEspOffers() async {
    final List<EspTokenLogRow> rows = List<EspTokenLogRow>.from(
      ref.read(espRecoverOffersProvider),
    );
    for (final EspTokenLogRow row in rows) {
      await recoverEspLogRow(row);
    }
  }

  void dismissEspRecoverOffer(EspTokenLogRow row) {
    final List<EspTokenLogRow> next = ref
        .read(espRecoverOffersProvider)
        .where(
          (EspTokenLogRow item) =>
              !(item.token == row.token && item.unitId == row.unitId),
        )
        .toList();
    ref.read(espRecoverOffersProvider.notifier).state = next;
  }

  void _bindPendingSavedSale(int unitId, SaleTransaction saved) {
    final DispenserUnit latest = state.unit(unitId);
    if (!latest.isCycleComplete || latest.pendingSavedToken != 0) {
      return;
    }
    _patchUnit(
      unitId,
      latest.copyWith(
        pendingSavedToken: saved.tokenNo,
        lastRupees: formatDispenserPkr(saved.amountPkr),
        lastLiters: formatLiters(saved.volumeLiters),
        lastTime: formatClock(saved.timestamp),
        lastCashier: saved.cashierName,
        lastCustomer: saved.customerName,
        lastVehicleNo: saved.vehicleNo,
        lastPayment: saved.payment,
      ),
    );
  }

  void dismissAllEspRecoverOffers() {
    ref.read(espRecoverOffersProvider.notifier).state =
        const <EspTokenLogRow>[];
  }

  void requestEspSyncLog(int unitId) {
    unawaited(_sockets.requestSyncLog(unitId));
  }

  Future<SaleTransaction?> recoverEspLogRow(
    EspTokenLogRow row, {
    PaymentMethod payment = PaymentMethod.cash,
    String customerName = '',
    String vehicleNo = '',
    String customerId = '',
    double cashNow = 0,
  }) async {
    if (state.unit(row.unitId).isTestRun) {
      return null;
    }
    final ShiftWorkspaceState workspace = ref.read(shiftWorkspaceProvider);
    final OperatorShiftRecord? activeShift = workspace.activeShift;
    if (shouldEnforceStationGuards &&
        (activeShift == null || !activeShift.isOpen)) {
      return null;
    }
    final int unitId = row.unitId;
    final int tokenNo = await _allocateUnusedToken(unitId);
    final DispenserUnit unit = state.unit(unitId);
    final HelperProfile? assigned = helperOnUnit(workspace.helpers, unitId);
    final double volumeLiters = parseFuel(row.volumeLiters).toDouble();
    final double rate = parseFuel(row.rate).toDouble();
    final double amountPkr = roundRupees(row.amountPkr).toDouble();
    final ({PaymentMethod payment, double cashAmount, double accountAmount})
    split = resolveAccountSplit(
      payment: payment,
      saleAmount: amountPkr,
      cashNow: cashNow,
    );
    final double opening = row.meterCount - volumeLiters;
    final SaleTransaction txn = SaleTransaction(
      tokenNo: tokenNo,
      unitId: unitId,
      fuelType: unit.fuelType,
      amountPkr: amountPkr,
      volumeLiters: volumeLiters,
      rate: rate,
      meterCount: row.meterCount.truncate(),
      timestamp: row.at ?? DateTime.now(),
      openingMeter: opening < 0 ? 0 : opening,
      closingMeter: row.meterCount,
      customerName: customerName.trim().isEmpty ? 'Walk-in' : customerName.trim(),
      vehicleNo: persistVehicleNo(vehicleNo),
      payment: split.payment,
      cashierName: SalesTransactionRepository.operatorNameFor(
        shift: activeShift,
        fallbackName: activeShift?.operatorName ?? 'Operator',
      ),
      helperName: assigned?.name ?? '',
      shiftId: activeShift?.shiftId ?? '',
      cashAmount: split.cashAmount,
      accountAmount: split.accountAmount,
      pendingAccountAmount: split.payment == PaymentMethod.bankAccount ||
              split.payment == PaymentMethod.easyPaisa
          ? split.accountAmount
          : 0,
      notes: 'RECOVERED',
      saleType: 'RECOVERED',
      espTxId: row.token > 0 ? '${row.token}' : '',
    );
    try {
      await _salesDb.insertCommittedSale(
        txn: txn,
        operatorId: SalesTransactionRepository.operatorIdFor(activeShift),
        operatorName: SalesTransactionRepository.operatorNameFor(
          shift: activeShift,
          fallbackName: txn.cashierName,
        ),
        operatorPin: SalesTransactionRepository.operatorPinFor(
          operators: workspace.operators,
          operatorId: SalesTransactionRepository.operatorIdFor(activeShift),
        ),
        helperId: assigned?.id,
        helperName: assigned?.name,
        creditCustomerId: split.payment == PaymentMethod.udhaar
            ? customerId.trim()
            : null,
        creditShiftId: activeShift?.shiftId,
      );
    } catch (error, stack) {
      debugPrint('ESP recover insert failed: $error\n$stack');
      return null;
    }
    final SaleTransaction? saved = await _salesDb.byToken(tokenNo);
    if (saved == null) {
      return null;
    }
    _advanceSequencePast(unitId, saved.tokenNo);
    await _refreshCommittedSales();
    bumpHistoryRevision(ref.read(historyRevisionProvider.notifier));
    unawaited(_sockets.ackToken(unitId: unitId, token: row.token));
    if (saved.tokenNo != row.token) {
      unawaited(_sockets.ackToken(unitId: unitId, token: saved.tokenNo));
    }
    dismissEspRecoverOffer(row);
    unawaited(ref.read(lowStockAlertProvider.notifier).sync());
    return saved;
  }

  SaleTransaction _draftSale({
    required int unitId,
    required DispenserUnit unit,
    required String customerName,
    required String vehicleNo,
    required PaymentMethod payment,
    String cashierName = 'Operator',
    double cashAmount = 0,
    int? tokenNo,
    String saleType = '',
  }) {
    final int resolvedToken =
        tokenNo ??
        (unit.pendingSavedToken != 0
            ? unit.pendingSavedToken
            : tokenIdFor(
                unitId: unitId,
                sequence: state.sequences[unitId] ?? 1,
              ));
    final ShiftWorkspaceState workspace = ref.read(shiftWorkspaceProvider);
    final HelperProfile? assigned = helperOnUnit(workspace.helpers, unitId);
    final String resolvedCustomer = customerName.trim().isEmpty
        ? 'Walk-in'
        : customerName.trim();
    final double openingMeter = unit.cycleOpeningMeter ?? 0;
    final double closingMeter = unit.meterCount;
    final ({PaymentMethod payment, double cashAmount, double accountAmount})
    split = resolveAccountSplit(
      payment: payment,
      saleAmount: unit.amountPkr,
      cashNow: cashAmount,
    );
    return SaleTransaction(
      tokenNo: resolvedToken,
      unitId: unitId,
      fuelType: unit.fuelType,
      amountPkr: unit.amountPkr,
      volumeLiters: unit.volumeLiters,
      rate: unit.rate,
      meterCount: closingMeter.truncate(),
      timestamp: DateTime.now(),
      openingMeter: openingMeter,
      closingMeter: closingMeter,
      customerName: resolvedCustomer,
      vehicleNo: persistVehicleNo(vehicleNo),
      payment: split.payment,
      cashierName: SalesTransactionRepository.operatorNameFor(
        shift: workspace.activeShift,
        fallbackName: cashierName,
      ),
      helperName: assigned?.name ?? '',
      shiftName: 'Morning',
      cashAmount: split.cashAmount,
      accountAmount: split.accountAmount,
      drumQty: 0,
      saleType: saleType.isEmpty
          ? (isVehicleRegistrationValid(vehicleNo) ? 'VEHICLE' : '')
          : saleType,
    );
  }

  Future<int> _allocateUnusedToken(int unitId) async {
    final bool direct = isDirectSaleUnit(unitId);
    int sequence = state.sequences[unitId] ?? (direct ? 0 : 1);
    if (!direct && sequence < 1) {
      sequence = 1;
    }
    if (direct && sequence < 0) {
      sequence = 0;
    }
    for (int attempt = 0; attempt < 64; attempt++) {
      final int tokenNo = tokenIdFor(unitId: unitId, sequence: sequence);
      if (await _salesDb.byToken(tokenNo) == null) {
        final int current = state.sequences[unitId] ?? (direct ? 0 : 1);
        if (current != sequence) {
          final Map<int, int> sequences = Map<int, int>.from(state.sequences);
          sequences[unitId] = sequence;
          state = state.copyWith(sequences: sequences);
        }
        return tokenNo;
      }
      sequence += 1;
    }
    throw StateError('Could not allocate a free token for unit $unitId');
  }

  void _advanceSequencePast(int unitId, int usedToken) {
    final int next = sequenceFromToken(usedToken, unitId) + 1;
    if (isDirectSaleUnit(unitId)) {
      if (next < 0) {
        return;
      }
    } else if (next < 1) {
      return;
    }
    final int current =
        state.sequences[unitId] ?? (isDirectSaleUnit(unitId) ? 0 : 1);
    if (next <= current) {
      return;
    }
    final Map<int, int> sequences = Map<int, int>.from(state.sequences);
    sequences[unitId] = next;
    state = state.copyWith(sequences: sequences);
  }

  Future<SaleTransaction?> _insertCashCompletedSale(int unitId) async {
    DispenserUnit unit = state.unit(unitId);
    if (unit.isTestRun) {
      return null;
    }
    if (unit.pendingSavedToken != 0) {
      return _salesDb.byToken(unit.pendingSavedToken);
    }
    final ShiftWorkspaceState workspace = ref.read(shiftWorkspaceProvider);
    final OperatorShiftRecord? activeShift = workspace.activeShift;
    if (shouldEnforceStationGuards &&
        (activeShift == null || !activeShift.isOpen)) {
      debugPrint('Cash auto-save blocked: no LIVE shift');
      return null;
    }
    unit = state.unit(unitId);
    final HelperProfile? assigned = helperOnUnit(workspace.helpers, unitId);
    final int tokenNo = await _allocateUnusedToken(unitId);
    if (state.unit(unitId).isTestRun) {
      return null;
    }
    final SaleTransaction txn = _draftSale(
      unitId: unitId,
      unit: unit,
      customerName: '',
      vehicleNo: '',
      payment: PaymentMethod.cash,
      cashierName: activeShift?.operatorName ?? 'Operator',
      tokenNo: tokenNo,
    ).copyWith(shiftId: activeShift?.shiftId ?? '', espTxId: '');
    await _salesDb.insertCommittedSale(
      txn: txn,
      operatorId: SalesTransactionRepository.operatorIdFor(activeShift),
      operatorName: SalesTransactionRepository.operatorNameFor(
        shift: activeShift,
        fallbackName: activeShift?.operatorName ?? txn.cashierName,
      ),
      operatorPin: SalesTransactionRepository.operatorPinFor(
        operators: workspace.operators,
        operatorId: SalesTransactionRepository.operatorIdFor(activeShift),
      ),
      helperId: assigned?.id,
      helperName: assigned?.name,
      creditShiftId: activeShift?.shiftId,
    );
    SaleTransaction? saved = await _salesDb.byToken(txn.tokenNo);
    if (saved == null) {
      return null;
    }
    _advanceSequencePast(unitId, saved.tokenNo);
    final DispenserUnit latest = state.unit(unitId);
    _patchUnit(
      unitId,
      latest.copyWith(
        pendingSavedToken: saved.tokenNo,
        lastRupees: formatDispenserPkr(saved.amountPkr),
        lastLiters: formatLiters(saved.volumeLiters),
        lastTime: formatClock(saved.timestamp),
        lastCashier: saved.cashierName,
        lastCustomer: saved.customerName,
        lastVehicleNo: saved.vehicleNo,
        lastPayment: saved.payment,
      ),
    );
    await _refreshCommittedSales();
    bumpHistoryRevision(ref.read(historyRevisionProvider.notifier));
    unawaited(ref.read(lowStockAlertProvider.notifier).sync());
    unawaited(_sockets.ackToken(unitId: unitId, token: saved.tokenNo));
    final int espToken = int.tryParse(latest.lastEspTxId.trim()) ?? 0;
    if (espToken > 0 && espToken != saved.tokenNo) {
      unawaited(_sockets.ackToken(unitId: unitId, token: espToken));
    }
    _publishMeterMismatch(saved);
    return saved;
  }

  int peekDirectTokenNo() {
    int sequence = state.sequences[kDirectSaleUnitId] ?? 0;
    if (sequence < 0) {
      sequence = 0;
    }
    return tokenIdFor(unitId: kDirectSaleUnitId, sequence: sequence);
  }

  Future<SaleTransaction?> insertDirectCashSale({
    required double rate,
    required double liters,
    String customerName = '',
  }) async {
    final Decimal volume = parseFuel(liters);
    final Decimal unitRate = parseFuel(rate);
    if (volume <= Decimal.zero || unitRate <= Decimal.zero) {
      return null;
    }
    final ShiftWorkspaceState workspace = ref.read(shiftWorkspaceProvider);
    final OperatorShiftRecord? activeShift = workspace.activeShift;
    if (shouldEnforceStationGuards &&
        (activeShift == null || !activeShift.isOpen)) {
      debugPrint('Direct sale blocked: no LIVE shift');
      return null;
    }
    final int amountPkr = roundRupees(volume * unitRate);
    if (amountPkr <= 0) {
      return null;
    }
    final String name = customerName.trim();
    final int tokenNo = await _allocateUnusedToken(kDirectSaleUnitId);
    final SaleTransaction txn = SaleTransaction(
      tokenNo: tokenNo,
      unitId: kDirectSaleUnitId,
      fuelType: kDieselFuelType,
      amountPkr: amountPkr.toDouble(),
      volumeLiters: volume.toDouble(),
      rate: unitRate.toDouble(),
      meterCount: 0,
      timestamp: DateTime.now(),
      openingMeter: 0,
      closingMeter: 0,
      customerName: name.isEmpty ? 'Walk-in' : name,
      vehicleNo: '',
      payment: PaymentMethod.cash,
      cashierName: SalesTransactionRepository.operatorNameFor(
        shift: activeShift,
        fallbackName: activeShift?.operatorName ?? 'Operator',
      ),
      shiftId: '',
      cashAmount: amountPkr.toDouble(),
      accountAmount: 0,
      espTxId: '',
    );
    await _salesDb.insertCommittedSale(
      txn: txn,
      operatorId: SalesTransactionRepository.operatorIdFor(activeShift),
      operatorName: SalesTransactionRepository.operatorNameFor(
        shift: activeShift,
        fallbackName: txn.cashierName,
      ),
      operatorPin: SalesTransactionRepository.operatorPinFor(
        operators: workspace.operators,
        operatorId: SalesTransactionRepository.operatorIdFor(activeShift),
      ),
      creditShiftId: null,
    );
    SaleTransaction? saved = await _salesDb.byToken(txn.tokenNo);
    if (saved == null) {
      return null;
    }
    _advanceSequencePast(kDirectSaleUnitId, saved.tokenNo);
    await _refreshCommittedSales();
    bumpHistoryRevision(ref.read(historyRevisionProvider.notifier));
    unawaited(ref.read(lowStockAlertProvider.notifier).sync());
    return saved;
  }

  void _publishMeterMismatch(SaleTransaction txn) {
    if (isDirectSaleUnit(txn.unitId) || txn.isTest) {
      return;
    }
    SaleTransaction? previousOnUnit;
    for (final SaleTransaction row in ref.read(committedSalesProvider)) {
      if (row.unitId != txn.unitId || row.tokenNo == txn.tokenNo) {
        continue;
      }
      previousOnUnit = row;
      break;
    }
    if (previousOnUnit == null) {
      return;
    }
    if (metersMatchAtAuditScale(
      txn.openingMeter,
      previousOnUnit.closingMeter,
    )) {
      return;
    }
    ref.read(meterMismatchNoticeProvider.notifier).state = MeterMismatchNotice(
      unitId: txn.unitId,
      previousTokenNo: previousOnUnit.tokenNo,
      currentTokenNo: txn.tokenNo,
      previousClosing: previousOnUnit.closingMeter,
      currentOpening: txn.openingMeter,
    );
  }

  Future<void> _autoInsertCashOnComplete(int unitId) async {
    if (!_autoSaving.add(unitId)) {
      return;
    }
    try {
      final DispenserUnit unit = state.unit(unitId);
      if (unit.isTestRun ||
          !unit.isCycleComplete ||
          unit.pendingSavedToken != 0) {
        return;
      }
      await _insertCashCompletedSale(unitId);
    } catch (error, stack) {
      debugPrint('Cash auto-save failed: $error\n$stack');
    } finally {
      _autoSaving.remove(unitId);
    }
  }

  /// Live preview from the unit card. Does not change payment in SQLite.
  bool previewReceiptForUnit({
    required int unitId,
    required String customerName,
    required String vehicleNo,
    required PaymentMethod payment,
    double cashNow = 0,
  }) {
    final DispenserUnit unit = state.unit(unitId);
    if (!unit.canConfirmPayment) {
      return false;
    }
    if (!unit.isTestRun && !isVehicleRegistrationValid(vehicleNo)) {
      return false;
    }
    final ({PaymentMethod payment, double cashAmount, double accountAmount})
    split = resolveAccountSplit(
      payment: payment,
      saleAmount: unit.amountPkr,
      cashNow: cashNow,
    );
    SaleTransaction draft = _draftSale(
      unitId: unitId,
      unit: unit,
      customerName: customerName,
      vehicleNo: vehicleNo,
      payment: split.payment,
      cashAmount: split.cashAmount,
    );
    if (unit.isTestRun) {
      draft = draft.copyWith(
        isTest: true,
        notes: 'TEST_METER',
        cashAmount: 0,
        accountAmount: 0,
        pendingAccountAmount: 0,
      );
    }
    final Map<int, SaleTransaction> next = Map<int, SaleTransaction>.from(
      ref.read(receiptOverlayTxnsProvider),
    );
    next[unitId] = draft;
    ref.read(receiptOverlayTxnsProvider.notifier).state = next;
    return true;
  }

  SaleTransaction? receiptDraftForUnit({
    required int unitId,
    required String customerName,
    required String vehicleNo,
    required PaymentMethod payment,
    double cashNow = 0,
  }) {
    final DispenserUnit unit = state.unit(unitId);
    if (!unit.canConfirmPayment) {
      return null;
    }
    if (!unit.isTestRun && !isVehicleRegistrationValid(vehicleNo)) {
      return null;
    }
    final ({PaymentMethod payment, double cashAmount, double accountAmount})
    split = resolveAccountSplit(
      payment: payment,
      saleAmount: unit.amountPkr,
      cashNow: cashNow,
    );
    SaleTransaction draft = _draftSale(
      unitId: unitId,
      unit: unit,
      customerName: customerName,
      vehicleNo: vehicleNo,
      payment: split.payment,
      cashAmount: split.cashAmount,
    );
    if (unit.isTestRun) {
      draft = draft.copyWith(
        isTest: true,
        notes: 'TEST_METER',
        cashAmount: 0,
        accountAmount: 0,
        pendingAccountAmount: 0,
      );
    }
    return draft;
  }

  void _dismissReceiptOverlay(int unitId) {
    final Map<int, SaleTransaction> next = Map<int, SaleTransaction>.from(
      ref.read(receiptOverlayTxnsProvider),
    );
    if (!next.containsKey(unitId)) {
      return;
    }
    next.remove(unitId);
    ref.read(receiptOverlayTxnsProvider.notifier).state = next;
  }

  void setUnitTestMode(int unitId, {required bool enabled}) {
    final DispenserUnit unit = state.unit(unitId);
    if (!enabled && unit.isDispensing) {
      return;
    }
    _patchUnit(
      unitId,
      unit.copyWith(
        testMode: enabled,
        testCycle: enabled ? unit.testCycle : false,
      ),
    );
  }

  Future<SaleTransaction?> _confirmTestMeterCycle(
    int unitId, {
    String vehicleNo = '',
    int drumQty = 0,
    String saleType = '',
  }) async {
    if (_confirmInFlight.contains(unitId)) {
      return null;
    }
    DispenserUnit unit = state.unit(unitId);
    if (!unit.canConfirmPayment) {
      return null;
    }
    _confirmInFlight.add(unitId);
    _pendingConfirmUnits.remove(unitId);
    _suppressConfirmUntilReset.add(unitId);
    _confirmedLiters[unitId] = unit.volumeLiters;
    _buzzer.stop();
    try {
      final ShiftWorkspaceState workspace = ref.read(shiftWorkspaceProvider);
      final OperatorShiftRecord? activeShift = workspace.activeShift;
      if (shouldEnforceStationGuards &&
          (activeShift == null || !activeShift.isOpen)) {
        debugPrint('Test meter save blocked: no LIVE shift');
        _pendingConfirmUnits.add(unitId);
        _suppressConfirmUntilReset.remove(unitId);
        _confirmedLiters.remove(unitId);
        _syncBuzzer();
        return null;
      }
      while (_autoSaving.contains(unitId)) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      unit = state.unit(unitId);
      final double closing = unit.meterCount;
      final HelperProfile? assigned = helperOnUnit(workspace.helpers, unitId);
      final SaleTransaction txn;
      if (unit.pendingSavedToken != 0) {
        final SaleTransaction? converted = await _salesDb
            .convertCommittedSaleToTest(
              tokenNo: unit.pendingSavedToken,
              volumeLiters: unit.volumeLiters,
            );
        if (converted == null) {
          _pendingConfirmUnits.add(unitId);
          _suppressConfirmUntilReset.remove(unitId);
          _confirmedLiters.remove(unitId);
          _syncBuzzer();
          return null;
        }
        txn = converted.copyWith(
          notes: 'TEST_METER',
          isTest: true,
          cashAmount: 0,
          accountAmount: 0,
          pendingAccountAmount: 0,
          customerName: 'TEST',
          vehicleNo: vehicleNo,
          drumQty: drumQty,
          saleType: saleType,
        );
        await _salesDb.updateMetadata(
          tokenNo: txn.tokenNo,
          customerName: 'TEST',
          vehicleNo: vehicleNo,
          payment: PaymentMethod.cash,
          cashAmount: 0,
          accountAmount: 0,
          pendingAccountAmount: 0,
          edited: false,
          drumQty: drumQty,
          saleType: saleType,
        );
      } else {
        final int tokenNo = await _allocateUnusedToken(unitId);
        txn =
            _draftSale(
              unitId: unitId,
              unit: unit,
              customerName: 'TEST',
              vehicleNo: vehicleNo,
              payment: PaymentMethod.cash,
              cashierName: activeShift?.operatorName ?? 'Operator',
              tokenNo: tokenNo,
              saleType: saleType,
            ).copyWith(
              timestamp: DateTime.now(),
              shiftId: activeShift?.shiftId ?? '',
              espTxId: '',
              isTest: true,
              cashAmount: 0,
              accountAmount: 0,
              notes: 'TEST_METER',
              customerName: 'TEST',
            );
        await _salesDb.insertCommittedSale(
          txn: txn,
          operatorId: SalesTransactionRepository.operatorIdFor(activeShift),
          operatorName: SalesTransactionRepository.operatorNameFor(
            shift: activeShift,
            fallbackName: activeShift?.operatorName ?? txn.cashierName,
          ),
          operatorPin: SalesTransactionRepository.operatorPinFor(
            operators: workspace.operators,
            operatorId: SalesTransactionRepository.operatorIdFor(activeShift),
          ),
          helperId: assigned?.id,
          helperName: assigned?.name,
          creditShiftId: activeShift?.shiftId,
        );
        _advanceSequencePast(unitId, txn.tokenNo);
      }
      unawaited(_sockets.confirmUnit(unitId));
      if (assigned != null || activeShift != null) {
        ref
            .read(shiftWorkspaceProvider.notifier)
            .recordSale(
              HelperSaleRecord(
                tokenNo: txn.tokenNo,
                timestamp: txn.timestamp,
                helperId: assigned?.id ?? '',
                helperName: assigned?.name ?? '',
                unitId: txn.unitId,
                fuelType: txn.fuelType,
                volumeLiters: txn.volumeLiters,
                rate: txn.rate,
                amountPkr: txn.amountPkr,
                payment: txn.payment,
                operatorId: activeShift?.operatorId ?? '',
                shiftId: activeShift?.shiftId ?? '',
                cashierName: activeShift?.operatorName ?? txn.cashierName,
                cashAmount: 0,
                accountAmount: 0,
                pendingAccountAmount: 0,
                openingMeter: txn.openingMeter,
                closingMeter: txn.closingMeter,
                customerName: txn.customerName,
                vehicleNo: txn.vehicleNo,
                operatorStaffId: activeShift?.operatorId ?? '',
                helperStaffId: assigned?.id ?? '',
                actions: txn.notes,
                isTest: true,
                drumQty: txn.drumQty,
              ),
            );
      }
      _patchUnit(
        unitId,
        unit.copyWith(
          status: DispenserRunState.idle,
          amountPkr: 0,
          volumeLiters: 0,
          keypadLocked: false,
          lastEspTxId: '',
          pendingSavedToken: 0,
          meterCount: closing,
          testMode: false,
          testCycle: false,
          clearCycleOpeningMeter: true,
        ),
      );
      _dismissReceiptOverlay(unitId);
      _syncBuzzer();
      await _refreshCommittedSales();
      bumpHistoryRevision(ref.read(historyRevisionProvider.notifier));
      return txn.copyWith(notes: 'TEST_METER', isTest: true);
    } catch (error, stack) {
      debugPrint('Test meter save failed: $error\n$stack');
      _pendingConfirmUnits.add(unitId);
      _suppressConfirmUntilReset.remove(unitId);
      _confirmedLiters.remove(unitId);
      _syncBuzzer();
      rethrow;
    } finally {
      _confirmInFlight.remove(unitId);
    }
  }

  Future<SaleTransaction?> confirmAndClearUnit({
    required int unitId,
    required String customerName,
    required String vehicleNo,
    required PaymentMethod payment,
    String cashierName = 'Operator',
    String customerId = '',
    double cashNow = 0,
  }) async {
    if (_confirmInFlight.contains(unitId)) {
      return null;
    }
    DispenserUnit unit = state.unit(unitId);
    if (!unit.canConfirmPayment) {
      return null;
    }
    final String persistVehicle = persistVehicleNo(vehicleNo);
    if (!unit.isTestRun && persistVehicle.isEmpty) {
      return null;
    }
    const int persistDrums = 0;
    final String fulfillment = persistVehicle.isEmpty ? '' : 'VEHICLE';
    if (unit.isTestRun) {
      return _confirmTestMeterCycle(
        unitId,
        vehicleNo: persistVehicle,
        drumQty: persistDrums,
        saleType: fulfillment,
      );
    }
    if (payment == PaymentMethod.udhaar && customerId.trim().isEmpty) {
      return null;
    }
    final ({PaymentMethod payment, double cashAmount, double accountAmount})
    split = resolveAccountSplit(
      payment: payment,
      saleAmount: unit.amountPkr,
      cashNow: cashNow,
    );
    final PaymentMethod tender = split.payment;
    final ({
      double cashAmount,
      double accountAmount,
      double pendingAccountAmount,
    })
    held = accountPersistSplit(
      payment: tender,
      cashAmount: split.cashAmount,
      accountAmount: split.accountAmount,
    );
    _confirmInFlight.add(unitId);
    _buzzer.stop();
    try {
      final ShiftWorkspaceState workspace = ref.read(shiftWorkspaceProvider);
      final OperatorShiftRecord? activeShift = workspace.activeShift;
      if (shouldEnforceStationGuards &&
          (activeShift == null || !activeShift.isOpen)) {
        debugPrint('Sale blocked: no LIVE shift');
        _syncBuzzer();
        return null;
      }
      _pendingConfirmUnits.remove(unitId);
      _suppressConfirmUntilReset.add(unitId);
      _confirmedLiters[unitId] = unit.volumeLiters;
      SaleTransaction? txn;
      if (unit.pendingSavedToken != 0) {
        txn = await _salesDb.byToken(unit.pendingSavedToken);
      }
      txn ??= await _insertCashCompletedSale(unitId);
      unit = state.unit(unitId);
      if (txn == null) {
        _pendingConfirmUnits.add(unitId);
        _suppressConfirmUntilReset.remove(unitId);
        _confirmedLiters.remove(unitId);
        _syncBuzzer();
        return null;
      }
      if (saleTenderNeedsUpdate(
        saved: txn,
        payment: tender,
        customerName: customerName,
        vehicleNo: persistVehicle,
        cashAmount: held.cashAmount,
        accountAmount: held.accountAmount,
        pendingAccountAmount: held.pendingAccountAmount,
        drumQty: persistDrums,
      )) {
        await _salesDb.applyConfirmTender(
          txn: txn,
          payment: tender,
          customerName: customerName,
          vehicleNo: persistVehicle,
          cashAmount: held.cashAmount,
          accountAmount: held.accountAmount,
          pendingAccountAmount: held.pendingAccountAmount,
          drumQty: persistDrums,
          saleType: fulfillment,
          creditCustomerId: tender == PaymentMethod.udhaar
              ? customerId.trim()
              : null,
          creditShiftId: activeShift?.shiftId,
        );
        txn =
            (await _salesDb.byToken(txn.tokenNo)) ??
            txn.copyWith(
              payment: tender,
              customerName: customerName.trim().isEmpty
                  ? 'Walk-in'
                  : customerName.trim(),
              vehicleNo: persistVehicle,
              cashAmount: held.cashAmount,
              accountAmount: held.accountAmount,
              pendingAccountAmount: held.pendingAccountAmount,
              drumQty: persistDrums,
              saleType: fulfillment,
            );
      }
      final HelperProfile? assigned = helperOnUnit(workspace.helpers, unitId);
      if (assigned != null || activeShift != null) {
        ref
            .read(shiftWorkspaceProvider.notifier)
            .recordSale(
              HelperSaleRecord(
                tokenNo: txn.tokenNo,
                timestamp: txn.timestamp,
                helperId: assigned?.id ?? '',
                helperName: assigned?.name ?? '',
                unitId: txn.unitId,
                fuelType: txn.fuelType,
                volumeLiters: txn.volumeLiters,
                rate: txn.rate,
                amountPkr: txn.amountPkr,
                payment: txn.payment,
                operatorId: activeShift?.operatorId ?? '',
                shiftId: activeShift?.shiftId ?? '',
                cashierName: activeShift?.operatorName ?? txn.cashierName,
                cashAmount: txn.cashAmount,
                accountAmount: txn.accountAmount,
                pendingAccountAmount: txn.pendingAccountAmount,
                openingMeter: txn.openingMeter,
                closingMeter: txn.closingMeter,
                customerName: txn.customerName,
                vehicleNo: txn.vehicleNo,
                operatorStaffId: activeShift?.operatorId ?? '',
                helperStaffId: assigned?.id ?? '',
                actions: txn.notes,
                espTxId: txn.espTxId,
                edited: txn.edited,
                isTest: txn.isTest,
                drumQty: txn.drumQty,
              ),
            );
      }
      if (tender == PaymentMethod.udhaar) {
        _printer.enqueue(txn);
      }
      unawaited(_sockets.confirmUnit(unitId, token: txn.tokenNo));
      unawaited(_sockets.ackToken(unitId: unitId, token: txn.tokenNo));
      _lastPumpingLiters.remove(unitId);
      final double closingMeter = txn.closingMeter;
      _patchUnit(
        unitId,
        unit.copyWith(
          status: DispenserRunState.idle,
          amountPkr: 0,
          volumeLiters: 0,
          keypadLocked: false,
          lastEspTxId: '',
          pendingSavedToken: 0,
          lastRupees: formatDispenserPkr(txn.amountPkr),
          lastLiters: formatLiters(txn.volumeLiters),
          lastTime: formatClock(txn.timestamp),
          lastCashier: txn.cashierName,
          lastCustomer: txn.customerName,
          lastVehicleNo: txn.vehicleNo,
          lastPayment: txn.payment,
          meterCount: closingMeter,
          clearCycleOpeningMeter: true,
        ),
      );
      await _refreshCommittedSales();
      if (tender == PaymentMethod.udhaar) {
        try {
          await reloadCustomerPersistence(ref);
        } catch (error, stack) {
          debugPrint('Could not refresh udhaar ledger: $error\n$stack');
        }
      }
      bumpHistoryRevision(ref.read(historyRevisionProvider.notifier));
      _dismissReceiptOverlay(unitId);
      _syncBuzzer();
      unawaited(ref.read(lowStockAlertProvider.notifier).sync());
      return txn;
    } catch (error, stack) {
      debugPrint('Confirm failed: $error\n$stack');
      _pendingConfirmUnits.add(unitId);
      _suppressConfirmUntilReset.remove(unitId);
      _confirmedLiters.remove(unitId);
      _syncBuzzer();
      return null;
    } finally {
      _confirmInFlight.remove(unitId);
    }
  }

  void simulateDispense(int unitId) {
    if (!kDebugMode) {
      return;
    }
    final DispenserUnit unit = state.unit(unitId);
    final double liters = 5.0 + _demoLitersRandom.nextDouble() * 40.0;
    _simulator.simulateDispense(
      unitId: unitId,
      rate: MockTelemetrySimulator.demoSaleRate,
      targetLiters: liters,
      meterCount: unit.meterCount,
      keypadLocked: false,
    );
  }

  void simulateZeroVolumeAbort(int unitId) {
    if (!kDebugMode) {
      return;
    }
    final DispenserUnit unit = state.unit(unitId);
    _simulator.simulateZeroVolumeAbort(
      unitId: unitId,
      rate: MockTelemetrySimulator.demoSaleRate,
      meterCount: unit.meterCount,
      keypadLocked: unit.keypadLocked,
    );
  }

  void issueNewToken() {
    final int unitId = ref.read(selectedDispenserIndexProvider);
    final Map<int, int> sequences = Map<int, int>.from(state.sequences);
    sequences[unitId] = (sequences[unitId] ?? 1) + 1;
    state = state.copyWith(sequences: sequences);
  }

  Future<void> setKeypadLock({required int unitId, required bool lock}) async {
    if (lock) {
      _monitorUnlockTimers.remove(unitId)?.cancel();
    }
    _patchUnit(unitId, state.unit(unitId).copyWith(keypadLocked: lock));
    unawaited(_sendKeypadRelay(unitId: unitId, lock: lock));
  }

  /// Monitor override: unlock for 5s, then lock again.
  void unlockKeypadTimed({
    required int unitId,
    Duration hold = const Duration(seconds: 5),
  }) {
    _monitorUnlockTimers.remove(unitId)?.cancel();
    unawaited(setKeypadLock(unitId: unitId, lock: false));
    _monitorUnlockTimers[unitId] = Timer(hold, () {
      _monitorUnlockTimers.remove(unitId);
      unawaited(setKeypadLock(unitId: unitId, lock: true));
    });
  }

  void toggleMonitorKeypad(int unitId) {
    if (state.unit(unitId).keypadLocked) {
      unlockKeypadTimed(unitId: unitId);
      return;
    }
    unawaited(setKeypadLock(unitId: unitId, lock: true));
  }

  /// Emergency lockout across all units. Fire-and-forget so POS stays live.
  void lockAllKeypads() {
    for (final int unitId in _liveUnitIds()) {
      unawaited(setKeypadLock(unitId: unitId, lock: true));
    }
  }

  void toggleAllMonitorKeypads() {
    final List<int> ids = _liveUnitIds();
    final bool anyLocked = ids.any(
      (int unitId) => state.unit(unitId).keypadLocked,
    );
    if (anyLocked) {
      for (final int unitId in ids) {
        if (state.unit(unitId).keypadLocked) {
          unlockKeypadTimed(unitId: unitId);
        }
      }
      return;
    }
    lockAllKeypads();
  }

  void unlockAllKeypads() {
    for (final int unitId in _liveUnitIds()) {
      if (_pendingConfirmUnits.contains(unitId)) {
        continue;
      }
      unawaited(setKeypadLock(unitId: unitId, lock: false));
    }
  }

  List<int> _liveUnitIds() {
    return visibleDispenserUnitIds(
      showUnit5: ref.read(settingsProvider).showUnit5,
    );
  }

  void _syncHardwareToShift(ShiftWorkspaceState workspace) {
    // Pump keypad follows an open shift, not the POS PIN overlay.
    // Confirm must be able to drop GPIO 4 even if sessionVerified is false.
    if (!shouldEnforceStationGuards) {
      _sockets.setAppHeartbeatEnabled(true, shiftLive: true);
      unlockAllKeypads();
      return;
    }
    final bool shiftOpen =
        workspace.activeShift != null && workspace.activeShift!.isOpen;
    _sockets.setAppHeartbeatEnabled(true, shiftLive: shiftOpen);
    if (shiftOpen) {
      unlockAllKeypads();
      return;
    }
    lockAllKeypads();
  }

  Map<int, double> unitMeterSnapshot() {
    return <int, double>{
      for (final DispenserUnit unit in state.units.values)
        unit.unitId: unit.meterCount.toDouble(),
    };
  }

  void testUnitBuzzer(int unitId) {
    unawaited(_sockets.pingUnit(unitId: unitId));
  }

  void pingResetUnit(int unitId) {
    ref.read(dispenserMonitorProvider.notifier).markPingSent(unitId);
    unawaited(_sockets.pingUnit(unitId: unitId));
    unawaited(_sockets.reconnectUnit(unitId));
  }

  void rescanUnitWifi(int unitId) {
    unawaited(_sockets.rescanUnitWifi(unitId));
  }

  void flushUartBuffer(int unitId) {
    unawaited(_sockets.flushUartBuffer(unitId));
  }

  void resetUnitSocket(int unitId) {
    pingResetUnit(unitId);
  }

  Future<void> _sendKeypadRelay({
    required int unitId,
    required bool lock,
  }) async {
    try {
      await _sockets.setKeypadRelay(unitId: unitId, lock: lock);
    } catch (_) {}
  }

  void saveEndpoint({
    required int unitId,
    required String host,
    required int port,
  }) {
    final Map<int, UnitEndpoint> endpoints = Map<int, UnitEndpoint>.from(
      state.endpoints,
    );
    final UnitEndpoint current = state.endpoint(unitId);
    endpoints[unitId] = current.copyWith(host: host.trim(), port: port);
    state = state.copyWith(endpoints: endpoints);
    unawaited(
      DispenserSocketManager.persistEndpoint(
        unitId: unitId,
        host: host.trim(),
        port: port,
      ),
    );
    if (endpoints[unitId]!.connected) {
      unawaited(
        _sockets.connectUnit(unitId: unitId, host: host.trim(), port: port),
      );
    }
  }

  void resetFdxBoard(int unitId) {
    if (state.unit(unitId).isDispensing) {
      return;
    }
    unawaited(_sockets.resetFdx(unitId));
  }

  void connectUnit(int unitId) {
    final UnitEndpoint endpoint = state.endpoint(unitId);
    unawaited(
      _sockets.connectUnit(
        unitId: unitId,
        host: endpoint.host,
        port: endpoint.port,
      ),
    );
  }

  void reprintReceipt(SaleTransaction txn) {
    _printer.enqueue(txn);
    if (txn.payment == PaymentMethod.udhaar) {
      _printer.enqueue(txn);
    }
  }

  Future<SaleTransaction?> updateSaleMetadata({
    required int tokenNo,
    required String customerName,
    required String vehicleNo,
    required PaymentMethod payment,
    double cashNow = 0,
    double saleAmount = 0,
  }) async {
    final SaleTransaction? current = await _salesDb.byToken(tokenNo);
    if (current == null || current.isAccountPending) {
      return null;
    }
    final ({PaymentMethod payment, double cashAmount, double accountAmount})
    split = resolveAccountSplit(
      payment: payment,
      saleAmount: saleAmount,
      cashNow: cashNow,
    );
    await _salesDb.updateMetadata(
      tokenNo: tokenNo,
      customerName: customerName,
      vehicleNo: vehicleNo,
      payment: split.payment,
      cashAmount: split.cashAmount,
      accountAmount: split.accountAmount,
      pendingAccountAmount: 0,
      edited: true,
    );
    await _refreshCommittedSales();
    bumpHistoryRevision(ref.read(historyRevisionProvider.notifier));
    return _salesDb.byToken(tokenNo);
  }

  Future<SaleTransaction?> confirmPendingAccountTransfer({
    required int tokenNo,
    required double cashAmount,
  }) async {
    final SaleTransaction? current = await _salesDb.byToken(tokenNo);
    if (current == null || !current.isAccountPending) {
      return null;
    }
    final ({PaymentMethod payment, double cashAmount, double accountAmount})
    confirmed = resolvePendingAccountConfirm(
      payment: current.payment,
      saleAmount: current.amountPkr,
      cashAmount: cashAmount,
    );
    final SaleTransaction? updated = await _salesDb.confirmPendingAccount(
      tokenNo: tokenNo,
      receivedAmount: confirmed.accountAmount,
      cashAmount: confirmed.cashAmount,
      payment: confirmed.payment,
    );
    await _refreshCommittedSales();
    bumpHistoryRevision(ref.read(historyRevisionProvider.notifier));
    if (updated != null) {
      ref
          .read(shiftWorkspaceProvider.notifier)
          .patchSaleTender(
            tokenNo: updated.tokenNo,
            payment: updated.payment,
            cashAmount: updated.cashAmount,
            accountAmount: updated.accountAmount,
            pendingAccountAmount: updated.pendingAccountAmount,
          );
    }
    return updated;
  }

  Future<SaleTransaction?> settleUdhaar({
    required int tokenNo,
    required double settledAmount,
    required String description,
  }) async {
    final SaleTransaction? updated = await _salesDb.settleUdhaar(
      tokenNo: tokenNo,
      settledAmount: settledAmount,
      description: description,
    );
    if (updated == null) {
      return null;
    }
    await _refreshCommittedSales();
    bumpHistoryRevision(ref.read(historyRevisionProvider.notifier));
    _printer.enqueue(updated);
    return updated;
  }

  void disconnectUnit(int unitId) {
    final Map<int, UnitEndpoint> endpoints = Map<int, UnitEndpoint>.from(
      state.endpoints,
    );
    endpoints[unitId] = state.endpoint(unitId).copyWith(connected: false);
    state = state.copyWith(endpoints: endpoints);
    ref.read(dispenserMonitorProvider.notifier).markSocketClosed(unitId);
    unawaited(_sockets.disconnectUnit(unitId));
  }
}

/// True when a LIVE shift has lost ESP32 telemetry / Wi-Fi.
final hardwareOfflineProvider = Provider<bool>((Ref ref) {
  if (!shouldEnforceStationGuards) {
    return false;
  }
  final bool live = ref.watch(
    shiftWorkspaceProvider.select(
      (ShiftWorkspaceState state) => state.activeShift?.isOpen == true,
    ),
  );
  if (!live) {
    return false;
  }
  final StationState station = ref.watch(stationControllerProvider);
  final List<int> ids = visibleDispenserUnitIds(
    showUnit5: ref.watch(settingsProvider).showUnit5,
  );
  if (ids.isEmpty) {
    return false;
  }
  final bool anyPacket = ids.any(
    (int id) => station.unit(id).lastPacketAt != null,
  );
  if (!anyPacket) {
    return false;
  }
  return ids.every((int id) => !station.endpoint(id).connected);
});
