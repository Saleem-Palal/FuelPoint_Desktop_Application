import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../customer/presentation/customer_store.dart';
import '../../shift/domain/shift_models.dart';
import '../../shift/presentation/shift_providers.dart';
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
  final Random _demoLitersRandom = Random();

  PrinterQueue get printerQueue => _printer;

  @override
  StationState build() {
    _store = ref.read(transactionStoreProvider);
    _salesDb = ref.read(salesTransactionRepositoryProvider);
    _printer = PrinterQueue();
    _buzzer = PaymentBuzzer();
    _simulator = MockTelemetrySimulator(
      emit: (DispenserTelemetry packet) {
        _logSyntheticTelemetry(packet);
        _onTelemetry(packet);
      },
    );
    _sockets = DispenserSocketManager(
      onTelemetry: (DispenserTelemetry packet) {
        _simulator.cancel(packet.unitId);
        _onTelemetry(packet);
      },
      onOffline: _onOffline,
      onWire: (DispenserWireFrame frame) {
        ref.read(dispenserMonitorProvider.notifier).ingestWire(frame);
      },
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
    Future<void>(_bootstrap);
    return StationState.seed();
  }

  Future<void> _bootstrap() async {
    await _store.init();
    unawaited(_sockets.start());
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

  /// Recalculated WAC from Purchase. Does not overwrite per-bay programmed rates.
  void setDieselAverageRate(double rate) {
    if (state.dieselAverageRate == rate) {
      return;
    }
    state = state.copyWith(dieselAverageRate: rate);
  }

  void _onTelemetry(DispenserTelemetry packet) {
    final DispenserBay previous = state.bay(packet.unitId);
    DispenserRunState nextStatus = packet.status;
    if (packet.status == DispenserRunState.idle && previous.isDispensing) {
      if (packet.volumeLiters.abs() < DispenserBay.zeroVolumeEpsilon) {
        unawaited(_handleZeroVolumeAbort(packet));
        ref
            .read(dispenserMonitorProvider.notifier)
            .ingestTelemetryExtras(packet);
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
    ref.read(dispenserMonitorProvider.notifier).ingestTelemetryExtras(packet);
  }

  void _logSyntheticTelemetry(DispenserTelemetry packet) {
    final Map<String, Object> body = <String, Object>{
      'unit_id': packet.unitId,
      'timestamp': DateTime.now().toIso8601String(),
      'status': packet.status.name.toUpperCase(),
      'liters': packet.volumeLiters,
      'amount_pkr': packet.amountPkr,
      'rate_pkr': packet.rate,
      'total_meter': packet.meterCount,
      'keypad_locked': packet.keypadLocked,
    };
    final int? rssi = packet.rssiDbm;
    if (rssi != null) {
      body['rssi'] = rssi;
    }
    ref
        .read(dispenserMonitorProvider.notifier)
        .ingestWire(
          DispenserWireFrame(
            at: DateTime.now(),
            outbound: false,
            kind: DispenserWireKind.telemetry,
            payload: jsonEncode(body),
            unitId: packet.unitId,
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

  SaleTransaction _draftSale({
    required int unitId,
    required DispenserBay bay,
    required String customerName,
    required String vehicleNo,
    required PaymentMethod payment,
    String cashierName = 'Cashier',
  }) {
    final int sequence = state.sequences[unitId] ?? 1;
    final HelperProfile? assigned = helperOnUnit(
      ref.read(shiftWorkspaceProvider).helpers,
      unitId,
    );
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
      meterCount: closingMeter.round(),
      timestamp: DateTime.now(),
      openingMeter: openingMeter,
      closingMeter: closingMeter,
      customerName: resolvedCustomer,
      vehicleNo: vehicleNo.trim(),
      payment: payment,
      cashierName: assigned?.name ?? cashierName,
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
    try {
      unawaited(_sendKeypadRelay(unitId: unitId, lock: true));
      final int sequence = state.sequences[unitId] ?? 1;
      final SaleTransaction txn = _draftSale(
        unitId: unitId,
        bay: bay,
        customerName: customerName,
        vehicleNo: vehicleNo,
        payment: payment,
        cashierName: cashierName,
      );
      final ShiftWorkspaceState workspace = ref.read(shiftWorkspaceProvider);
      final HelperProfile? assigned = helperOnUnit(workspace.helpers, unitId);
      final ManagerShiftRecord? activeShift = workspace.activeShift;
      final String resolvedCashier = txn.cashierName;
      final String resolvedCustomer = txn.customerName;
      final double closingMeter = txn.closingMeter;
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
        lastCashier: resolvedCashier,
        lastCustomer: resolvedCustomer,
        lastVehicleNo: txn.vehicleNo,
        lastPayment: payment,
        meterCount: closingMeter.round(),
      );
      state = state.copyWith(sequences: sequences, bays: bays);
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
    for (final int unitId in dispenserUnitIds) {
      unawaited(setKeypadLock(unitId: unitId, lock: true));
    }
  }

  void testBayBuzzer(int unitId) {
    unawaited(_sockets.testBuzzer(unitId: unitId));
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
    if (endpoints[unitId]!.connected) {
      unawaited(
        _sockets.connectBay(unitId: unitId, host: host.trim(), port: port),
      );
    }
  }

  void connectUnit(int unitId) {
    final UnitEndpoint endpoint = state.endpoint(unitId);
    final Map<int, UnitEndpoint> endpoints = Map<int, UnitEndpoint>.from(
      state.endpoints,
    );
    endpoints[unitId] = endpoint.copyWith(connected: true);
    state = state.copyWith(endpoints: endpoints);
    ref.read(dispenserMonitorProvider.notifier).markSocketOpened(unitId);
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
