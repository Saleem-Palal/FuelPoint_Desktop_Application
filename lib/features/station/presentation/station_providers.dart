import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/dispenser_socket_manager.dart';
import '../data/mock_telemetry_simulator.dart';
import '../data/payment_buzzer.dart';
import '../data/printer_queue.dart';
import '../data/transaction_store.dart';
import '../domain/dispenser_models.dart';
import '../domain/money_format.dart';

final transactionStoreProvider = Provider<TransactionStore>((Ref ref) {
  return TransactionStore();
});

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
  final int current = ref.read(selectedDispenserIndexProvider);
  int next = current + delta;
  if (next < 1) {
    next = kDispenserUnitCount;
  }
  if (next > kDispenserUnitCount) {
    next = 1;
  }
  ref.read(selectedDispenserIndexProvider.notifier).state = next;
}

final stationControllerProvider =
    NotifierProvider<StationController, StationState>(StationController.new);

class StationController extends Notifier<StationState> {
  late final TransactionStore _store;
  late final DispenserSocketManager _sockets;
  late final MockTelemetrySimulator _simulator;
  late final PrinterQueue _printer;
  late final PaymentBuzzer _buzzer;

  final Map<int, Timer> _abortTimers = <int, Timer>{};
  final Set<int> _confirmInFlight = <int>{};

  PrinterQueue get printerQueue => _printer;

  @override
  StationState build() {
    _store = ref.read(transactionStoreProvider);
    _printer = PrinterQueue();
    _buzzer = PaymentBuzzer();
    _simulator = MockTelemetrySimulator(emit: _onTelemetry);
    _sockets = DispenserSocketManager(
      onTelemetry: (DispenserTelemetry packet) {
        _simulator.cancel(packet.unitId);
        _onTelemetry(packet);
      },
      onOffline: _onOffline,
    );
    ref.onDispose(() {
      for (final Timer timer in _abortTimers.values) {
        timer.cancel();
      }
      _abortTimers.clear();
      _buzzer.dispose();
      _simulator.dispose();
      unawaited(_sockets.dispose());
    });
    Future<void>.microtask(_bootstrap);
    return StationState.seed().copyWith(recentTransactions: _store.snapshot);
  }

  Future<void> _bootstrap() async {
    await _store.init();
    final Map<int, int> sequences = await _store.sequencesFromHistory();
    final List<SaleTransaction> rows = await _store.recent();
    state = state.copyWith(sequences: sequences, recentTransactions: rows);
  }

  void _patchBay(int unitId, DispenserBay next) {
    final Map<int, DispenserBay> bays = Map<int, DispenserBay>.from(state.bays);
    bays[unitId] = next;
    state = state.copyWith(bays: bays);
    _syncBuzzer();
  }

  void _syncBuzzer() {
    final bool awaitingPayment = state.bays.values.any(
      (DispenserBay bay) => bay.canConfirmPayment,
    );
    if (awaitingPayment) {
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

  void _onTelemetry(DispenserTelemetry packet) {
    final DispenserBay previous = state.bay(packet.unitId);
    DispenserRunState nextStatus = packet.status;
    if (packet.status == DispenserRunState.idle && previous.isDispensing) {
      if (packet.volumeLiters.abs() < DispenserBay.zeroVolumeEpsilon) {
        unawaited(_handleZeroVolumeAbort(packet));
        return;
      }
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
        keypadLocked: packet.keypadLocked,
        lastPacketAt: DateTime.now(),
      ),
    );
  }

  Future<void> _handleZeroVolumeAbort(DispenserTelemetry packet) async {
    final DispenserBay previous = state.bay(packet.unitId);
    _patchBay(
      packet.unitId,
      previous.copyWith(
        status: DispenserRunState.idle,
        amountPkr: 0,
        volumeLiters: 0,
        rate: packet.rate,
        meterCount: packet.meterCount,
        lastPacketAt: DateTime.now(),
      ),
    );
    await _store.insertSystemLog(
      eventType: 'ZERO_VOLUME_ABORT',
      unitId: packet.unitId,
      details: 'Hang-up at 0.00 L — no sale, no lock, no receipt',
    );
    _flashAbortNotice(packet.unitId);
  }

  void _onOffline(int _) {}

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
  }) async {
    if (_confirmInFlight.contains(unitId)) {
      return null;
    }
    final DispenserBay bay = state.bay(unitId);
    if (!bay.canConfirmPayment) {
      return null;
    }
    _confirmInFlight.add(unitId);
    try {
      unawaited(_sendKeypadRelay(unitId: unitId, lock: true));
      final int sequence = state.sequences[unitId] ?? 1;
      final String resolvedCustomer = customerName.trim().isEmpty
          ? 'Walk-in'
          : customerName.trim();
      final double openingMeter = bay.meterCount.toDouble();
      final double closingMeter = openingMeter + bay.volumeLiters;
      final SaleTransaction txn = SaleTransaction(
        tokenNo: tokenIdFor(unitId: unitId, sequence: sequence),
        unitId: unitId,
        fuelType: bay.fuelType,
        amountPkr: bay.amountPkr,
        volumeLiters: bay.volumeLiters,
        rate: bay.rate,
        meterCount: closingMeter.round(),
        timestamp: DateTime.now(),
        openingMeter: openingMeter,
        closingMeter: closingMeter,
        customerName: resolvedCustomer,
        vehicleNo: vehicleNo.trim(),
        payment: payment,
        cashierName: cashierName,
        shiftName: 'Morning',
      );
      await _store.insertSalesHistory(txn);
      bumpHistoryRevision(ref.read(historyRevisionProvider.notifier));
      _printer.enqueue(txn);

      final Map<int, int> sequences = Map<int, int>.from(state.sequences);
      sequences[unitId] = sequence + 1;
      final List<SaleTransaction> recent = await _store.recent();
      final Map<int, DispenserBay> bays = Map<int, DispenserBay>.from(
        state.bays,
      );
      final DispenserBay latest = state.bay(unitId);
      bays[unitId] = latest.copyWith(
        status: DispenserRunState.idle,
        amountPkr: 0,
        volumeLiters: 0,
        keypadLocked: true,
        lastRupees: formatPkr(txn.amountPkr),
        lastLiters: formatLiters(txn.volumeLiters),
        lastTime: formatClock(txn.timestamp),
        lastCashier: cashierName,
        lastCustomer: resolvedCustomer,
        lastVehicleNo: txn.vehicleNo,
        lastPayment: payment,
        meterCount: closingMeter.round(),
      );
      state = state.copyWith(
        sequences: sequences,
        recentTransactions: recent,
        bays: bays,
      );
      _syncBuzzer();
      return txn;
    } finally {
      _confirmInFlight.remove(unitId);
    }
  }

  void simulateDispense(int unitId) {
    final DispenserBay bay = state.bay(unitId);
    _simulator.simulateDispense(
      unitId: unitId,
      rate: bay.rate,
      meterCount: bay.meterCount,
      keypadLocked: false,
    );
  }

  void simulateZeroVolumeAbort(int unitId) {
    final DispenserBay bay = state.bay(unitId);
    _simulator.simulateZeroVolumeAbort(
      unitId: unitId,
      rate: bay.rate,
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
  }

  void connectUnit(int unitId) {
    final Map<int, UnitEndpoint> endpoints = Map<int, UnitEndpoint>.from(
      state.endpoints,
    );
    endpoints[unitId] = state.endpoint(unitId).copyWith(connected: true);
    state = state.copyWith(endpoints: endpoints);
  }

  void reprintReceipt(SaleTransaction txn) {
    _printer.enqueue(txn);
  }

  Future<SaleTransaction?> updateSaleMetadata({
    required int tokenNo,
    required String customerName,
    required String vehicleNo,
    required PaymentMethod payment,
  }) async {
    final SaleTransaction? updated = await _store.updateSalesHistory(
      tokenNo: tokenNo,
      customerName: customerName,
      vehicleNo: vehicleNo,
      payment: payment,
    );
    if (updated == null) {
      return null;
    }
    final List<SaleTransaction> recent = await _store.recent();
    state = state.copyWith(recentTransactions: recent);
    bumpHistoryRevision(ref.read(historyRevisionProvider.notifier));
    return updated;
  }

  Future<SaleTransaction?> settleUdhaar({
    required int tokenNo,
    required double settledAmount,
    required String description,
  }) async {
    final SaleTransaction? updated = await _store.settleUdhaar(
      tokenNo: tokenNo,
      settledAmount: settledAmount,
      description: description,
    );
    if (updated == null) {
      return null;
    }
    final List<SaleTransaction> recent = await _store.recent();
    state = state.copyWith(recentTransactions: recent);
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
  }
}
