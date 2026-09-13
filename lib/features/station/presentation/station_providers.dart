import 'dart:async';
import 'dart:math';

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
import '../domain/money_format.dart';
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

final selectedBayProvider = Provider<DispenserBay>((Ref ref) {
  final int unitId = ref.watch(selectedDispenserIndexProvider);
  return ref.watch(stationControllerProvider).bay(unitId);
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

final pendingEspSalesProvider = StateProvider<List<PendingEspSale>>(
  (Ref ref) => const <PendingEspSale>[],
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

/// Weighted-average diesel cost from Purchase. Not painted onto bay RATE LCDs.
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
  final Set<int> _confirmInFlight = <int>{};
  final Set<int> _pendingConfirmUnits = <int>{};
  final Set<int> _suppressConfirmUntilReset = <int>{};
  final Map<int, double> _confirmedLiters = <int, double>{};
  final Map<int, double> _lastPumpingLiters = <int, double>{};
  final Set<String> _ackedEspTx = <String>{};
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
        _simulator.cancel(packet.unitId);
        _onTelemetry(packet);
      },
      onOffline: _onOffline,
      onConnected: _onSocketConnected,
      onPendingSale: _onPendingSale,
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
      final List<SaleTransaction> rows = await _salesDb.all();
      ref.read(committedSalesProvider.notifier).state = rows;
      state = state.copyWith(
        recentTransactions: rows.length <= 10 ? rows : rows.take(10).toList(),
      );
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
      return <int, int>{for (final int unitId in dispenserUnitIds) unitId: 1};
    }
  }

  void _patchBay(int unitId, DispenserBay next) {
    final Map<int, DispenserBay> bays = Map<int, DispenserBay>.from(state.bays);
    bays[unitId] = next;
    state = state.copyWith(bays: bays);
    _syncBuzzer();
  }

  DispenserBay _withSavedLastSale(DispenserBay bay, SaleTransaction? row) {
    if (row == null) {
      return bay.copyWith(
        lastRupees: '',
        lastLiters: '',
        lastTime: '',
        lastCashier: '',
      );
    }
    return bay.copyWith(
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
      latest.putIfAbsent(row.unitId, () => row);
    }
    final Map<int, DispenserBay> bays = Map<int, DispenserBay>.from(state.bays);
    bool changed = false;
    for (final int unitId in dispenserUnitIds) {
      final DispenserBay bay = state.bay(unitId);
      final DispenserBay next = _withSavedLastSale(bay, latest[unitId]);
      if (next.lastRupees == bay.lastRupees &&
          next.lastLiters == bay.lastLiters &&
          next.lastTime == bay.lastTime &&
          next.lastCashier == bay.lastCashier) {
        continue;
      }
      bays[unitId] = next;
      changed = true;
    }
    if (changed) {
      state = state.copyWith(bays: bays);
    }
  }

  void _syncBuzzer() {
    // PC speaker only while Confirm is actually enabled on a bay.
    final bool waitingForConfirm = state.bays.values.any(
      (DispenserBay bay) => bay.canConfirmPayment,
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

  /// Recalculated WAC from Purchase. Does not overwrite per-bay programmed rates.
  void setDieselAverageRate(double rate) {
    if (state.dieselAverageRate == rate) {
      return;
    }
    state = state.copyWith(dieselAverageRate: rate);
  }

  void _onTelemetry(DispenserTelemetry packet) {
    final DispenserBay previous = state.bay(packet.unitId);
    final String cmd = packet.cmd.toUpperCase();
    DispenserRunState nextStatus = packet.status;
    final bool alreadyAcked =
        packet.txId.isNotEmpty && _ackedEspTx.contains(packet.txId);
    final bool dispensingToIdle =
        packet.status == DispenserRunState.idle && previous.isDispensing;
    final bool saleCompleteCmd = cmd == 'SALE_COMPLETE' && !alreadyAcked;
    final bool suppressConfirm =
        _suppressConfirmUntilReset.contains(packet.unitId);

    if (packet.status == DispenserRunState.dispensing) {
      _lastPumpingLiters[packet.unitId] = packet.volumeLiters;
      _pendingConfirmUnits.remove(packet.unitId);
      final double? confirmedLiters = _confirmedLiters[packet.unitId];
      if (confirmedLiters == null ||
          packet.volumeLiters.abs() < DispenserBay.zeroVolumeEpsilon ||
          packet.volumeLiters + 0.001 < confirmedLiters) {
        _suppressConfirmUntilReset.remove(packet.unitId);
        _confirmedLiters.remove(packet.unitId);
      }
    }

    final bool nullHangup =
        packet.isNoSaleCmd ||
        ((dispensingToIdle || saleCompleteCmd) &&
            isNullHangupCycle(
              lastPumpingLiters: _lastPumpingLiters[packet.unitId],
              packetLiters: packet.volumeLiters,
            ));
    if (nullHangup) {
      _pendingConfirmUnits.remove(packet.unitId);
      _lastPumpingLiters.remove(packet.unitId);
      if (saleCompleteCmd && packet.txId.isNotEmpty) {
        _ackedEspTx.add(packet.txId);
        unawaited(
          _sockets.ackTransaction(unitId: packet.unitId, txId: packet.txId),
        );
        unawaited(_sockets.confirmBay(packet.unitId));
      }
      unawaited(
        _handleZeroVolumeAbort(
          packet,
          showNotice: previous.isDispensing || previous.isCycleComplete,
        ),
      );
      ref
          .read(dispenserMonitorProvider.notifier)
          .ingestTelemetryExtras(packet);
      return;
    }

    if (!suppressConfirm && (dispensingToIdle || saleCompleteCmd)) {
      _pendingConfirmUnits.add(packet.unitId);
      nextStatus = DispenserRunState.cycleComplete;
    } else if (_pendingConfirmUnits.contains(packet.unitId) &&
        packet.status != DispenserRunState.dispensing) {
      nextStatus = DispenserRunState.cycleComplete;
    }

    if (nextStatus == DispenserRunState.dispensing) {
      _clearAbortNotice(packet.unitId);
      _dismissReceiptOverlay(packet.unitId);
    }

    _patchBay(
      packet.unitId,
      previous.copyWith(
        status: nextStatus,
        amountPkr: packet.amountPkr,
        volumeLiters: packet.volumeLiters,
        rate: packet.rate,
        meterCount: packet.meterCount,
        keypadLocked: _pendingConfirmUnits.contains(packet.unitId)
            ? true
            : packet.keypadLocked,
        lastPacketAt: DateTime.now(),
        lastEspTxId: packet.txId.isNotEmpty ? packet.txId : previous.lastEspTxId,
      ),
    );
    if (!state.endpoint(packet.unitId).connected) {
      _onSocketConnected(packet.unitId);
    }
    ref.read(dispenserMonitorProvider.notifier).ingestTelemetryExtras(packet);
  }

  Future<void> _handleZeroVolumeAbort(
    DispenserTelemetry packet, {
    required bool showNotice,
  }) async {
    final DispenserBay previous = state.bay(packet.unitId);
    _patchBay(
      packet.unitId,
      previous.copyWith(
        status: DispenserRunState.idle,
        amountPkr: packet.amountPkr,
        volumeLiters: packet.volumeLiters,
        rate: packet.rate,
        meterCount: packet.meterCount,
        keypadLocked: false,
        lastPacketAt: DateTime.now(),
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
  }

  void _onOffline(int unitId) {
    final UnitEndpoint current = state.endpoint(unitId);
    final DispenserBay bay = state.bay(unitId);
    if (!current.connected && (bay.isOffline || bay.isCycleComplete)) {
      return;
    }
    final Map<int, UnitEndpoint> endpoints = Map<int, UnitEndpoint>.from(
      state.endpoints,
    );
    endpoints[unitId] = current.copyWith(connected: false);
    _patchBay(
      unitId,
      bay.copyWith(
        status: bay.isCycleComplete
            ? DispenserRunState.cycleComplete
            : DispenserRunState.offline,
      ),
    );
    state = state.copyWith(endpoints: endpoints);
    ref.read(dispenserMonitorProvider.notifier).markSocketClosed(unitId);
  }

  void _onPendingSale(PendingEspSale sale) {
    if (_ackedEspTx.contains(sale.txId)) {
      unawaited(_sockets.ackTransaction(unitId: sale.unitId, txId: sale.txId));
      return;
    }
    if (sale.volumeLiters.abs() < DispenserBay.zeroVolumeEpsilon) {
      unawaited(_sockets.ackTransaction(unitId: sale.unitId, txId: sale.txId));
      return;
    }
    final List<PendingEspSale> next = List<PendingEspSale>.from(
      ref.read(pendingEspSalesProvider),
    );
    if (next.any((PendingEspSale row) => row.txId == sale.txId)) {
      return;
    }
    next.add(sale);
    ref.read(pendingEspSalesProvider.notifier).state = next;
  }

  Future<void> savePendingEspSale(PendingEspSale sale) async {
    final bool saved = await _commitPendingEspSale(sale);
    if (!saved) {
      return;
    }
    _ackedEspTx.add(sale.txId);
    unawaited(_sockets.ackTransaction(unitId: sale.unitId, txId: sale.txId));
    unawaited(_sockets.confirmBay(sale.unitId));
    _removePending(sale.txId);
  }

  void dismissPendingEspSale(PendingEspSale sale) {
    _removePending(sale.txId);
  }

  void _removePending(String txId) {
    final List<PendingEspSale> next = ref
        .read(pendingEspSalesProvider)
        .where((PendingEspSale row) => row.txId != txId)
        .toList();
    ref.read(pendingEspSalesProvider.notifier).state = next;
  }

  Future<bool> _commitPendingEspSale(PendingEspSale sale) async {
    final ShiftWorkspaceState workspace = ref.read(shiftWorkspaceProvider);
    final ManagerShiftRecord? activeShift = workspace.activeShift;
    if (activeShift == null || !activeShift.isOpen) {
      return false;
    }
    final int unitId = sale.unitId;
    if (unitId < 1) {
      return false;
    }
    try {
      final DispenserBay bay = state.bay(unitId);
      final double liters = sale.volumeLiters;
      final double amount = sale.amountPkr;
      final double rate = sale.rate > 0 ? sale.rate : bay.rate;
      final int meter = sale.meterCount.truncate();
      final HelperProfile? assigned = helperOnUnit(workspace.helpers, unitId);
      final int sequence = state.sequences[unitId] ?? 1;
      final SaleTransaction txn = SaleTransaction(
        tokenNo: tokenIdFor(unitId: unitId, sequence: sequence),
        unitId: unitId,
        fuelType: bay.fuelType,
        amountPkr: amount,
        volumeLiters: liters,
        rate: rate,
        meterCount: meter,
        timestamp: DateTime.now(),
        payment: PaymentMethod.cash,
        cashierName: activeShift.managerName,
        helperName: assigned?.name ?? '',
        shiftId: activeShift.shiftId,
        openingMeter: (meter - liters).clamp(0, double.infinity).toDouble(),
        closingMeter: meter.toDouble(),
        espTxId: sale.txId,
      );
      await _salesDb.insertCommittedSale(
        txn: txn,
        managerId: activeShift.managerId,
        managerName: activeShift.managerName,
        managerPin: SalesTransactionRepository.managerPinFor(
          managers: workspace.managers,
          managerId: activeShift.managerId,
        ),
        helperId: assigned?.id,
        helperName: assigned?.name,
        creditShiftId: activeShift.shiftId,
      );
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
              managerId: activeShift.managerId,
              shiftId: activeShift.shiftId,
              cashierName: activeShift.managerName,
            ),
          );
      final Map<int, int> sequences = Map<int, int>.from(state.sequences);
      sequences[unitId] = sequence + 1;
      state = state.copyWith(sequences: sequences);
      await _refreshCommittedSales();
      bumpHistoryRevision(ref.read(historyRevisionProvider.notifier));
      unawaited(ref.read(lowStockAlertProvider.notifier).sync());
      return true;
    } catch (error, stack) {
      debugPrint('Pending ESP sale ingest failed: $error\n$stack');
      return false;
    }
  }

  SaleTransaction _draftSale({
    required int unitId,
    required DispenserBay bay,
    required String customerName,
    required String vehicleNo,
    required PaymentMethod payment,
    String cashierName = 'Cashier',
  }) {
    final int sequence = state.sequences[unitId] ?? 1;
    final ShiftWorkspaceState workspace = ref.read(shiftWorkspaceProvider);
    final HelperProfile? assigned = helperOnUnit(workspace.helpers, unitId);
    final String resolvedCustomer = customerName.trim().isEmpty
        ? 'Walk-in'
        : customerName.trim();
    final double openingMeter = bay.meterCount.toDouble();
    final double closingMeter = openingMeter + bay.volumeLiters;
    return SaleTransaction(
      tokenNo: tokenIdFor(unitId: unitId, sequence: sequence),
      unitId: unitId,
      fuelType: bay.fuelType,
      amountPkr: bay.amountPkr,
      volumeLiters: bay.volumeLiters,
      rate: bay.rate,
      meterCount: closingMeter.truncate(),
      timestamp: DateTime.now(),
      openingMeter: openingMeter,
      closingMeter: closingMeter,
      customerName: resolvedCustomer,
      vehicleNo: vehicleNo.trim(),
      payment: payment,
      cashierName: SalesTransactionRepository.managerNameFor(
        shift: workspace.activeShift,
        fallbackName: cashierName,
      ),
      helperName: assigned?.name ?? '',
      shiftName: 'Morning',
    );
  }

  /// Live preview from the unit card. Does not commit the sale.
  bool previewReceiptForBay({
    required int unitId,
    required String customerName,
    required String vehicleNo,
    required PaymentMethod payment,
  }) {
    final DispenserBay bay = state.bay(unitId);
    if (!bay.canConfirmPayment) {
      return false;
    }
    final SaleTransaction draft = _draftSale(
      unitId: unitId,
      bay: bay,
      customerName: customerName,
      vehicleNo: vehicleNo,
      payment: payment,
    );
    final Map<int, SaleTransaction> next = Map<int, SaleTransaction>.from(
      ref.read(receiptOverlayTxnsProvider),
    );
    next[unitId] = draft;
    ref.read(receiptOverlayTxnsProvider.notifier).state = next;
    return true;
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

  Future<SaleTransaction?> confirmAndClearBay({
    required int unitId,
    required String customerName,
    required String vehicleNo,
    required PaymentMethod payment,
    String cashierName = 'Cashier',
    String customerId = '',
  }) async {
    if (_confirmInFlight.contains(unitId)) {
      return null;
    }
    final DispenserBay bay = state.bay(unitId);
    if (!bay.canConfirmPayment) {
      return null;
    }
    _confirmInFlight.add(unitId);
    _pendingConfirmUnits.remove(unitId);
    _suppressConfirmUntilReset.add(unitId);
    _confirmedLiters[unitId] = bay.volumeLiters;
    _buzzer.stop();
    try {
      final ShiftWorkspaceState workspace = ref.read(shiftWorkspaceProvider);
      final ManagerShiftRecord? activeShift = workspace.activeShift;
      if (shouldEnforceStationGuards &&
          (activeShift == null || !activeShift.isOpen)) {
        debugPrint('Sale blocked: no LIVE shift');
        _pendingConfirmUnits.add(unitId);
        _suppressConfirmUntilReset.remove(unitId);
        _confirmedLiters.remove(unitId);
        _syncBuzzer();
        return null;
      }
      final String espTxId = bay.lastEspTxId;
      if (espTxId.isNotEmpty) {
        _ackedEspTx.add(espTxId);
        unawaited(_sockets.ackTransaction(unitId: unitId, txId: espTxId));
      }
      unawaited(_sockets.confirmBay(unitId));
      final int sequence = state.sequences[unitId] ?? 1;
      final HelperProfile? assigned = helperOnUnit(workspace.helpers, unitId);
      final SaleTransaction txn = _draftSale(
        unitId: unitId,
        bay: bay,
        customerName: customerName,
        vehicleNo: vehicleNo,
        payment: payment,
        cashierName: cashierName,
      ).copyWith(shiftId: activeShift?.shiftId ?? '', espTxId: espTxId);
      final String resolvedCashier = txn.cashierName;
      final String resolvedCustomer = txn.customerName;
      final double closingMeter = txn.closingMeter;
      final Map<int, DispenserBay> waitingBays = Map<int, DispenserBay>.from(
        state.bays,
      );
      waitingBays[unitId] = bay.copyWith(
        status: DispenserRunState.idle,
        amountPkr: 0,
        volumeLiters: 0,
        keypadLocked: false,
        lastEspTxId: '',
        lastRupees: formatDispenserPkr(txn.amountPkr),
        lastLiters: formatLiters(txn.volumeLiters),
        lastTime: formatClock(txn.timestamp),
        lastCashier: resolvedCashier,
        lastCustomer: resolvedCustomer,
        lastVehicleNo: txn.vehicleNo,
        lastPayment: payment,
        meterCount: closingMeter,
      );
      state = state.copyWith(bays: waitingBays);
      _syncBuzzer();
      await _salesDb.insertCommittedSale(
        txn: txn,
        managerId: SalesTransactionRepository.managerIdFor(activeShift),
        managerName: SalesTransactionRepository.managerNameFor(
          shift: activeShift,
          fallbackName: activeShift?.managerName ?? resolvedCashier,
        ),
        managerPin: SalesTransactionRepository.managerPinFor(
          managers: workspace.managers,
          managerId: SalesTransactionRepository.managerIdFor(activeShift),
        ),
        helperId: assigned?.id,
        helperName: assigned?.name,
        creditCustomerId: payment == PaymentMethod.udhaar
            ? customerId.trim()
            : null,
        creditShiftId: activeShift?.shiftId,
      );
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
                managerId: activeShift?.managerId ?? '',
                shiftId: activeShift?.shiftId ?? '',
                cashierName: activeShift?.managerName ?? resolvedCashier,
              ),
            );
      }
      if (payment == PaymentMethod.udhaar) {
        _printer.enqueue(txn);
      }

      final Map<int, int> sequences = Map<int, int>.from(state.sequences);
      sequences[unitId] = sequence + 1;
      state = state.copyWith(sequences: sequences);
      await _refreshCommittedSales();
      if (payment == PaymentMethod.udhaar) {
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
    } finally {
      _confirmInFlight.remove(unitId);
    }
  }

  void simulateDispense(int unitId) {
    final DispenserBay bay = state.bay(unitId);
    final double liters = 5.0 + _demoLitersRandom.nextDouble() * 40.0;
    _simulator.simulateDispense(
      unitId: unitId,
      rate: MockTelemetrySimulator.demoSaleRate,
      targetLiters: liters,
      meterCount: bay.meterCount,
      keypadLocked: false,
    );
  }

  void simulateZeroVolumeAbort(int unitId) {
    final DispenserBay bay = state.bay(unitId);
    _simulator.simulateZeroVolumeAbort(
      unitId: unitId,
      rate: MockTelemetrySimulator.demoSaleRate,
      meterCount: bay.meterCount,
      keypadLocked: bay.keypadLocked,
    );
  }

  void issueNewToken() {
    final int unitId = ref.read(selectedDispenserIndexProvider);
    final Map<int, int> sequences = Map<int, int>.from(state.sequences);
    sequences[unitId] = (sequences[unitId] ?? 1) + 1;
    state = state.copyWith(sequences: sequences);
  }

  Future<void> setKeypadLock({required int unitId, required bool lock}) async {
    _patchBay(unitId, state.bay(unitId).copyWith(keypadLocked: lock));
    unawaited(_sendKeypadRelay(unitId: unitId, lock: lock));
  }

  /// Emergency lockout across all bays. Fire-and-forget so POS stays live.
  void lockAllKeypads() {
    for (final int unitId in _liveBayIds()) {
      unawaited(setKeypadLock(unitId: unitId, lock: true));
    }
  }

  void unlockAllKeypads() {
    for (final int unitId in _liveBayIds()) {
      if (_pendingConfirmUnits.contains(unitId)) {
        continue;
      }
      unawaited(setKeypadLock(unitId: unitId, lock: false));
    }
  }

  List<int> _liveBayIds() {
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

  Map<int, double> bayMeterSnapshot() {
    return <int, double>{
      for (final DispenserBay bay in state.bays.values)
        bay.unitId: bay.meterCount.toDouble(),
    };
  }

  void testBayBuzzer(int unitId) {
    unawaited(_sockets.pingUnit(unitId: unitId));
  }

  void pingResetBay(int unitId) {
    ref.read(dispenserMonitorProvider.notifier).markPingSent(unitId);
    unawaited(_sockets.pingUnit(unitId: unitId));
    unawaited(_sockets.reconnectUnit(unitId));
  }

  void rescanBayWifi(int unitId) {
    unawaited(_sockets.rescanBayWifi(unitId));
  }

  void flushUartBuffer(int unitId) {
    unawaited(_sockets.flushUartBuffer(unitId));
  }

  void resetBaySocket(int unitId) {
    pingResetBay(unitId);
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
        _sockets.connectBay(unitId: unitId, host: host.trim(), port: port),
      );
    }
  }

  void connectUnit(int unitId) {
    final UnitEndpoint endpoint = state.endpoint(unitId);
    unawaited(
      _sockets.connectBay(
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
  }) async {
    await _salesDb.updateMetadata(
      tokenNo: tokenNo,
      customerName: customerName,
      vehicleNo: vehicleNo,
      payment: payment,
    );
    await _refreshCommittedSales();
    bumpHistoryRevision(ref.read(historyRevisionProvider.notifier));
    return _salesDb.byToken(tokenNo);
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
    unawaited(_sockets.disconnectBay(unitId));
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
    (int id) => station.bay(id).lastPacketAt != null,
  );
  if (!anyPacket) {
    return false;
  }
  return ids.every((int id) => !station.endpoint(id).connected);
});
