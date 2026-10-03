import 'dart:convert';

import 'fuel_precision.dart';

enum DispenserRunState {
  idle,
  dispensing,
  cycleComplete,
  offline,
  rupeesPreset,
  litersPreset,
}

enum PaymentMethod { cash, udhaar, bankAccount, easyPaisa }

extension PaymentMethodX on PaymentMethod {
  String get label {
    switch (this) {
      case PaymentMethod.cash:
        return 'Cash';
      case PaymentMethod.udhaar:
        return 'Udhaar';
      case PaymentMethod.bankAccount:
        return 'Bank Account';
      case PaymentMethod.easyPaisa:
        return 'EasyPaisa';
    }
  }

  /// Compact ledger pill: CASH, UDHAAR, or BANK / DIGITAL.
  String get ledgerPill {
    switch (this) {
      case PaymentMethod.cash:
        return 'CASH';
      case PaymentMethod.udhaar:
        return 'UDHAAR';
      case PaymentMethod.bankAccount:
      case PaymentMethod.easyPaisa:
        return 'BANK / DIGITAL';
    }
  }

  /// Udhaar and Account (bank / EasyPaisa) print customer + station copies.
  bool get printsTwoCopies {
    switch (this) {
      case PaymentMethod.udhaar:
      case PaymentMethod.bankAccount:
      case PaymentMethod.easyPaisa:
        return true;
      case PaymentMethod.cash:
        return false;
    }
  }
}

/// Tender columns on `sales_transactions`. [amountPkr] stays the ticket total
/// and is never added to Cash or Account KPIs.
({PaymentMethod payment, double cashAmount, double accountAmount})
resolveAccountSplit({
  required PaymentMethod payment,
  required double saleAmount,
  required double cashNow,
}) {
  final int sale = roundRupees(saleAmount);
  switch (payment) {
    case PaymentMethod.cash:
      return (
        payment: PaymentMethod.cash,
        cashAmount: sale.toDouble(),
        accountAmount: 0,
      );
    case PaymentMethod.udhaar:
      return (payment: PaymentMethod.udhaar, cashAmount: 0, accountAmount: 0);
    case PaymentMethod.bankAccount:
    case PaymentMethod.easyPaisa:
      final int cash = roundRupees(cashNow).clamp(0, sale);
      if (cash >= sale) {
        return (
          payment: PaymentMethod.cash,
          cashAmount: sale.toDouble(),
          accountAmount: 0,
        );
      }
      return (
        payment: payment,
        cashAmount: cash.toDouble(),
        accountAmount: (sale - cash).toDouble(),
      );
  }
}

/// Confirm / Update on a waiting account sale. Cash above the ticket is cut
/// down to the sale. A zero account remainder becomes a cash ticket.
({PaymentMethod payment, double cashAmount, double accountAmount})
resolvePendingAccountConfirm({
  required PaymentMethod payment,
  required double saleAmount,
  required double cashAmount,
}) {
  final int sale = roundRupees(saleAmount);
  final int cash = roundRupees(cashAmount).clamp(0, sale);
  final int account = sale - cash;
  if (account <= 0) {
    return (
      payment: PaymentMethod.cash,
      cashAmount: sale.toDouble(),
      accountAmount: 0,
    );
  }
  return (
    payment: payment,
    cashAmount: cash.toDouble(),
    accountAmount: account.toDouble(),
  );
}

/// Account remainder stays uncredited until bank Confirm / Update.
({double cashAmount, double accountAmount, double pendingAccountAmount})
accountPersistSplit({
  required PaymentMethod payment,
  required double cashAmount,
  required double accountAmount,
}) {
  switch (payment) {
    case PaymentMethod.bankAccount:
    case PaymentMethod.easyPaisa:
      return (
        cashAmount: cashAmount,
        accountAmount: 0,
        pendingAccountAmount: accountAmount,
      );
    case PaymentMethod.cash:
    case PaymentMethod.udhaar:
      return (
        cashAmount: cashAmount,
        accountAmount: accountAmount,
        pendingAccountAmount: 0,
      );
  }
}

String _tenderCustomerName(String raw) {
  final String trimmed = raw.trim();
  return trimmed.isEmpty ? 'Walk-in' : trimmed;
}

/// True when Confirm should rewrite the hang-up cash row (payment, split,
/// customer, or vehicle changed).
bool saleTenderNeedsUpdate({
  required SaleTransaction saved,
  required PaymentMethod payment,
  required String customerName,
  required String vehicleNo,
  required double cashAmount,
  required double accountAmount,
  double pendingAccountAmount = 0,
  int drumQty = 0,
}) {
  if (saved.payment != payment) {
    return true;
  }
  if (roundRupees(saved.cashAmount) != roundRupees(cashAmount)) {
    return true;
  }
  if (roundRupees(saved.accountAmount) != roundRupees(accountAmount)) {
    return true;
  }
  if (roundRupees(saved.pendingAccountAmount) !=
      roundRupees(pendingAccountAmount)) {
    return true;
  }
  if (saved.vehicleNo.trim() != vehicleNo.trim()) {
    return true;
  }
  if (saved.drumQty != drumQty) {
    return true;
  }
  return _tenderCustomerName(saved.customerName) !=
      _tenderCustomerName(customerName);
}

DispenserRunState dispenserStatusFromWire(String? raw) {
  final String key = (raw ?? '').trim().toUpperCase();
  if (key.contains('PUMP') || key == 'DISPENSING' || key == 'ACTIVE') {
    return DispenserRunState.dispensing;
  }
  if (key.contains('LITER') && key.contains('PRESET')) {
    return DispenserRunState.litersPreset;
  }
  if ((key.contains('RUPEE') || key.contains('AMOUNT')) &&
      key.contains('PRESET')) {
    return DispenserRunState.rupeesPreset;
  }
  if (key == 'P') {
    return DispenserRunState.rupeesPreset;
  }
  if (key == 'L') {
    return DispenserRunState.litersPreset;
  }
  switch (key) {
    case 'OFFLINE':
      return DispenserRunState.offline;
    case 'CYCLE_COMPLETE':
    case 'AWAITING_PAYMENT':
      return DispenserRunState.cycleComplete;
    case 'IDLE':
    case 'ONLINE':
      return DispenserRunState.idle;
    default:
      return DispenserRunState.idle;
  }
}

class DispenserUnit {
  const DispenserUnit({
    required this.unitId,
    required this.name,
    required this.fuelType,
    required this.status,
    required this.amountPkr,
    required this.volumeLiters,
    required this.rate,
    required this.meterCount,
    required this.keypadLocked,
    required this.lastRupees,
    required this.lastLiters,
    required this.lastTime,
    required this.lastCashier,
    this.lastCustomer = 'Walk-in',
    this.lastVehicleNo = '',
    this.lastPayment = PaymentMethod.cash,
    this.lastPacketAt,
    this.lastEspTxId = '',
    this.pendingSavedToken = 0,
    this.cycleOpeningMeter,
    this.testMode = false,
    this.testCycle = false,
  });

  final int unitId;
  final String name;
  final String fuelType;
  final DispenserRunState status;
  final double amountPkr;
  final double volumeLiters;
  final double rate;
  final double meterCount;
  final bool keypadLocked;
  final String lastRupees;
  final String lastLiters;
  final String lastTime;

  /// Operator on the latest `sales_transactions` row for this unit.
  final String lastCashier;
  final String lastCustomer;
  final String lastVehicleNo;
  final PaymentMethod lastPayment;
  final DateTime? lastPacketAt;
  final String lastEspTxId;
  final int pendingSavedToken;

  /// ESP Total Meter when this fill started. Not computed from liters.
  final double? cycleOpeningMeter;

  /// Operator armed a test fill. Volume returns to tank; not a sale.
  final bool testMode;

  /// This hang-up is a test fill (latched from [testMode] while pumping).
  final bool testCycle;

  static const double zeroVolumeEpsilon = 0.005;

  bool get isDispensing => status == DispenserRunState.dispensing;
  bool get isOffline => status == DispenserRunState.offline;
  bool get isOnline => !isOffline;
  bool get isCycleComplete => status == DispenserRunState.cycleComplete;
  bool get isZeroVolume => volumeLiters.abs() < zeroVolumeEpsilon;
  bool get canConfirmPayment => isCycleComplete && !isZeroVolume;
  bool get isTestRun => testMode || testCycle;

  String get productLabel => fuelType.toUpperCase();

  DispenserUnit copyWith({
    DispenserRunState? status,
    double? amountPkr,
    double? volumeLiters,
    double? rate,
    double? meterCount,
    bool? keypadLocked,
    String? lastRupees,
    String? lastLiters,
    String? lastTime,
    String? lastCashier,
    String? lastCustomer,
    String? lastVehicleNo,
    PaymentMethod? lastPayment,
    DateTime? lastPacketAt,
    String? lastEspTxId,
    int? pendingSavedToken,
    double? cycleOpeningMeter,
    bool? testMode,
    bool? testCycle,
    bool clearLastPacket = false,
    bool clearCycleOpeningMeter = false,
  }) {
    return DispenserUnit(
      unitId: unitId,
      name: name,
      fuelType: fuelType,
      status: status ?? this.status,
      amountPkr: amountPkr ?? this.amountPkr,
      volumeLiters: volumeLiters ?? this.volumeLiters,
      rate: rate ?? this.rate,
      meterCount: meterCount ?? this.meterCount,
      keypadLocked: keypadLocked ?? this.keypadLocked,
      lastRupees: lastRupees ?? this.lastRupees,
      lastLiters: lastLiters ?? this.lastLiters,
      lastTime: lastTime ?? this.lastTime,
      lastCashier: lastCashier ?? this.lastCashier,
      lastCustomer: lastCustomer ?? this.lastCustomer,
      lastVehicleNo: lastVehicleNo ?? this.lastVehicleNo,
      lastPayment: lastPayment ?? this.lastPayment,
      lastPacketAt: clearLastPacket
          ? null
          : (lastPacketAt ?? this.lastPacketAt),
      lastEspTxId: lastEspTxId ?? this.lastEspTxId,
      pendingSavedToken: pendingSavedToken ?? this.pendingSavedToken,
      cycleOpeningMeter: clearCycleOpeningMeter
          ? null
          : (cycleOpeningMeter ?? this.cycleOpeningMeter),
      testMode: testMode ?? this.testMode,
      testCycle: testCycle ?? this.testCycle,
    );
  }
}

class DispenserTelemetry {
  const DispenserTelemetry({
    required this.unitId,
    required this.amountPkr,
    required this.volumeLiters,
    required this.rate,
    required this.meterCount,
    required this.status,
    required this.keypadLocked,
    this.rssiDbm,
    this.pulseCount,
    this.txId = '',
    this.cmd = '',
    this.espToBoardLink,
    this.pendingTxCount,
    this.product = '',
  });

  final int unitId;
  final double amountPkr;
  final double volumeLiters;
  final double rate;
  final double meterCount;
  final DispenserRunState status;
  final bool keypadLocked;

  /// ESP32 Wi-Fi RSSI in dBm when the heartbeat includes it.
  final int? rssiDbm;

  /// Raw GPIO 14 pulse encoder ticks. Falls back to [meterCount] in the UI.
  final int? pulseCount;
  final String txId;
  final String cmd;
  final bool? espToBoardLink;
  final int? pendingTxCount;
  final String product;

  int get encoderPulses => pulseCount ?? meterCount.round();

  bool get isNoSaleCmd {
    final String upper = cmd.toUpperCase();
    return upper == 'NO_SALE' || upper == 'ZERO_HANGUP';
  }
}

/// FDX idle Type-33 redisplays the last sale. Confirm / relay / buzzer must
/// use liters from the pumping window, not the idle LCD.
double dispenserCycleLiters({
  required double? lastPumpingLiters,
  required double packetLiters,
}) {
  return lastPumpingLiters ?? packetLiters;
}

bool isNullHangupCycle({
  required double? lastPumpingLiters,
  required double packetLiters,
}) {
  return dispenserCycleLiters(
        lastPumpingLiters: lastPumpingLiters,
        packetLiters: packetLiters,
      ).abs() <
      DispenserUnit.zeroVolumeEpsilon;
}

class PendingEspSale {
  const PendingEspSale({
    required this.txId,
    required this.unitId,
    required this.kind,
    required this.amountPkr,
    required this.volumeLiters,
    required this.rate,
    required this.meterCount,
    this.product = '',
  });

  final String txId;
  final int unitId;
  final String kind;
  final double amountPkr;
  final double volumeLiters;
  final double rate;
  final double meterCount;
  final String product;

  bool get isIncomplete => kind.toLowerCase().contains('incomplete');

  static PendingEspSale? tryParse(String raw) {
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      final Map<String, dynamic> map = Map<String, dynamic>.from(decoded);
      final String cmd = '${map['cmd'] ?? ''}'.toUpperCase();
      if (cmd != 'QUEUE_REPLAY' &&
          cmd != 'INTERRUPTED_TX' &&
          cmd != 'INTERRUPTED_TRANSACTION') {
        return null;
      }
      final String txId = '${map['tx_id'] ?? map['ack_tx_id'] ?? ''}'.trim();
      if (txId.isEmpty) {
        return null;
      }
      final Map<String, dynamic> tel = map['telemetry'] is Map
          ? Map<String, dynamic>.from(map['telemetry'] as Map)
          : map;
      return PendingEspSale(
        txId: txId,
        unitId: int.tryParse('${map['unit'] ?? map['unit_id'] ?? '0'}') ?? 0,
        kind: '${map['kind'] ?? map['status'] ?? 'UNSYNCED'}',
        amountPkr: _espHundredths(
          tel['amount'] ?? tel['amount_pkr'],
          tel['amount_cents'],
        ),
        volumeLiters: _espHundredths(tel['liters'], tel['liter_cents']),
        rate: _espHundredths(tel['rate'] ?? tel['rate_pkr'], tel['rate_cents']),
        meterCount: _espHundredths(
          tel['meter'] ?? tel['total_meter'],
          tel['meter_cents'],
        ),
        product: '${tel['product'] ?? ''}',
      );
    } catch (_) {
      return null;
    }
  }
}

double _espHundredths(Object? value, Object? cents) {
  if (cents is int) {
    return cents / 100.0;
  }
  if (cents is num) {
    return cents.toInt() / 100.0;
  }
  final int? parsed = int.tryParse('${cents ?? ''}'.trim());
  if (parsed != null) {
    return parsed / 100.0;
  }
  return double.tryParse('${value ?? 0}') ?? 0;
}

class SystemLog {
  const SystemLog({
    required this.eventType,
    required this.unitId,
    required this.timestamp,
    this.details = '',
  });

  final String eventType;
  final int unitId;
  final DateTime timestamp;
  final String details;
}

class PrintJob {
  const PrintJob({required this.transaction, required this.queuedAt});

  final SaleTransaction transaction;
  final DateTime queuedAt;
}

class SaleTransaction {
  const SaleTransaction({
    this.id,
    required this.tokenNo,
    required this.unitId,
    required this.fuelType,
    required this.amountPkr,
    required this.volumeLiters,
    required this.rate,
    required this.meterCount,
    required this.timestamp,
    this.openingMeter = 0,
    this.closingMeter = 0,
    this.customerName = 'Walk-in',
    this.vehicleNo = '',
    this.payment = PaymentMethod.cash,
    this.cashierName = 'Operator',
    this.helperName = '',
    this.shiftId = '',
    this.shiftName = 'Morning',
    this.notes = '',
    this.udhaarSettled = false,
    this.settledAmount = 0,
    this.settledAt,
    this.espTxId = '',
    this.cashAmount = 0,
    this.accountAmount = 0,
    this.pendingAccountAmount = 0,
    this.edited = false,
    this.isTest = false,
    this.drumQty = 0,
    this.saleType = '',
  });

  final int? id;
  final int tokenNo;
  final int unitId;
  final String fuelType;
  final double amountPkr;
  final double volumeLiters;
  final double rate;
  final int meterCount;
  final DateTime timestamp;
  final double openingMeter;
  final double closingMeter;
  final String customerName;
  final String vehicleNo;
  final PaymentMethod payment;
  final String cashierName;
  final String helperName;
  final String shiftId;
  final String shiftName;
  final String notes;
  final bool udhaarSettled;
  final double settledAmount;
  final DateTime? settledAt;
  final String espTxId;
  final double cashAmount;
  final double accountAmount;
  final double pendingAccountAmount;
  final bool edited;
  final bool isTest;
  final int drumQty;
  final String saleType;

  bool get isRecoveredSale {
    return saleType.toUpperCase() == 'RECOVERED' ||
        notes.toUpperCase().contains('RECOVERED');
  }

  bool get isAccountPending {
    return !isTest && pendingAccountAmount > 0;
  }

  double get receiptAccountAmount {
    return pendingAccountAmount > 0 ? pendingAccountAmount : accountAmount;
  }

  bool get isUnsettledUdhaar {
    return payment == PaymentMethod.udhaar && !udhaarSettled;
  }

  /// ESP liters vs Closing − Opening. 13th-place noise is not a mismatch.
  bool get litersMatchMeterDelta {
    return saleLitersMatchMeter(
      liters: volumeLiters,
      openingMeter: openingMeter,
      closingMeter: closingMeter,
    );
  }

  SaleTransaction copyWith({
    int? id,
    int? tokenNo,
    int? unitId,
    String? fuelType,
    double? amountPkr,
    double? volumeLiters,
    double? rate,
    int? meterCount,
    DateTime? timestamp,
    double? openingMeter,
    double? closingMeter,
    String? customerName,
    String? vehicleNo,
    PaymentMethod? payment,
    String? cashierName,
    String? helperName,
    String? shiftId,
    String? shiftName,
    String? notes,
    bool? udhaarSettled,
    double? settledAmount,
    DateTime? settledAt,
    String? espTxId,
    double? cashAmount,
    double? accountAmount,
    double? pendingAccountAmount,
    bool? edited,
    bool? isTest,
    int? drumQty,
    String? saleType,
  }) {
    return SaleTransaction(
      id: id ?? this.id,
      tokenNo: tokenNo ?? this.tokenNo,
      unitId: unitId ?? this.unitId,
      fuelType: fuelType ?? this.fuelType,
      amountPkr: amountPkr ?? this.amountPkr,
      volumeLiters: volumeLiters ?? this.volumeLiters,
      rate: rate ?? this.rate,
      meterCount: meterCount ?? this.meterCount,
      timestamp: timestamp ?? this.timestamp,
      openingMeter: openingMeter ?? this.openingMeter,
      closingMeter: closingMeter ?? this.closingMeter,
      customerName: customerName ?? this.customerName,
      vehicleNo: vehicleNo ?? this.vehicleNo,
      payment: payment ?? this.payment,
      cashierName: cashierName ?? this.cashierName,
      helperName: helperName ?? this.helperName,
      shiftId: shiftId ?? this.shiftId,
      shiftName: shiftName ?? this.shiftName,
      notes: notes ?? this.notes,
      udhaarSettled: udhaarSettled ?? this.udhaarSettled,
      settledAmount: settledAmount ?? this.settledAmount,
      settledAt: settledAt ?? this.settledAt,
      espTxId: espTxId ?? this.espTxId,
      cashAmount: cashAmount ?? this.cashAmount,
      accountAmount: accountAmount ?? this.accountAmount,
      pendingAccountAmount: pendingAccountAmount ?? this.pendingAccountAmount,
      edited: edited ?? this.edited,
      isTest: isTest ?? this.isTest,
      drumQty: drumQty ?? this.drumQty,
      saleType: saleType ?? this.saleType,
    );
  }
}

/// Stock replenishment row persisted in `purchase_history`.
class PurchaseTransaction {
  const PurchaseTransaction({
    this.id,
    required this.refNo,
    required this.timestamp,
    required this.supplierName,
    required this.fuelType,
    required this.weightKg,
    required this.sharahRatio,
    required this.netLiters,
    required this.ratePerLiter,
    required this.totalAmount,
    this.deductions = 0,
    this.paidAmount = 0,
    this.remainingBalance = 0,
    this.tafseel = '',
    this.user = 'Ali',
  });

  final int? id;
  final int refNo;
  final DateTime timestamp;
  final String supplierName;
  final String fuelType;
  final double weightKg;
  final double sharahRatio;
  final double netLiters;
  final double ratePerLiter;
  final double totalAmount;
  final double deductions;
  final double paidAmount;
  final double remainingBalance;
  final String tafseel;
  final String user;

  String get tafseelDisplay {
    final String note = tafseel.trim();
    if (note.isNotEmpty) {
      return note;
    }
    final String supplier = supplierName.trim();
    if (supplier.isEmpty) {
      return '—';
    }
    return supplier;
  }
}

/// Active dispenser units on the sale workspace (Unit 1 … Unit N).
const int kDispenserUnitCount = 5;

/// Hardware units on Tenda System (Unit 5 stays hidden unless Settings enables it).
const int kHardwareDispenserUnitCount = 4;

/// Optional extra unit. Hidden on the Sale screen unless enabled in Settings.
const int kOptionalDispenserUnitId = 5;

/// Manual Direct Sale Card. Not a dispenser unit; `UNIT_NO` stays INTEGER.
const int kDirectSaleUnitId = 6;

/// First Direct token (`TKN-DR-600000`). Same band as `tokenIdFor(6, 0)`.
const int kDirectSaleTokenBase = 600000;

bool isDirectSaleUnit(int unitId) => unitId == kDirectSaleUnitId;

bool isDirectSaleToken(int tokenNo) {
  return tokenNo >= kDirectSaleTokenBase &&
      tokenNo < kDirectSaleTokenBase + 100000;
}

List<int> get dispenserUnitIds =>
    List<int>.generate(kDispenserUnitCount, (int i) => i + 1);

List<int> visibleDispenserUnitIds({required bool showUnit5}) {
  if (showUnit5) {
    return dispenserUnitIds;
  }
  return dispenserUnitIds
      .where((int id) => id != kOptionalDispenserUnitId)
      .toList();
}

class UnitEndpoint {
  const UnitEndpoint({
    required this.host,
    required this.port,
    this.connected = false,
  });

  final String host;
  final int port;
  final bool connected;

  UnitEndpoint copyWith({String? host, int? port, bool? connected}) {
    return UnitEndpoint(
      host: host ?? this.host,
      port: port ?? this.port,
      connected: connected ?? this.connected,
    );
  }

  static UnitEndpoint seedFor(int unitId) {
    return UnitEndpoint(host: '192.168.0.${100 + (10 * unitId)}', port: 81);
  }
}

/// Sole station product. Purchase, sale, and LCD RATE all share this type.
const String kDieselFuelType = 'Diesel';

class StationState {
  const StationState({
    required this.units,
    required this.sequences,
    required this.recentTransactions,
    required this.endpoints,
    this.dieselAverageRate = 0,
    this.abortNotices = const <int, String>{},
  });

  final Map<int, DispenserUnit> units;
  final Map<int, int> sequences;
  final List<SaleTransaction> recentTransactions;
  final Map<int, UnitEndpoint> endpoints;

  /// Weighted-average diesel cost from Purchase. Independent of per-unit RATE.
  final double dieselAverageRate;
  final Map<int, String> abortNotices;

  String? abortNoticeFor(int unitId) => abortNotices[unitId];

  /// WebSocket to this unit's ESP is open. Packet silence is not a drop.
  bool isUnitLinkOnline(int unitId, {DateTime? now}) {
    return endpoint(unitId).connected;
  }

  UnitEndpoint endpoint(int unitId) {
    final UnitEndpoint? found = endpoints[unitId];
    if (found != null) {
      return found;
    }
    return UnitEndpoint.seedFor(unitId);
  }

  DispenserUnit unit(int unitId) {
    final DispenserUnit? found = units[unitId];
    if (found != null) {
      return found;
    }
    return StationState.seedUnit(unitId);
  }

  static DispenserUnit seedUnit(int unitId) {
    switch (unitId) {
      case 2:
        return const DispenserUnit(
          unitId: 2,
          name: 'Unit 2',
          fuelType: kDieselFuelType,
          status: DispenserRunState.idle,
          amountPkr: 0,
          volumeLiters: 0,
          rate: 150,
          meterCount: 0,
          keypadLocked: false,
          lastRupees: '',
          lastLiters: '',
          lastTime: '',
          lastCashier: '',
        );
      case 3:
        return const DispenserUnit(
          unitId: 3,
          name: 'Unit 3',
          fuelType: kDieselFuelType,
          status: DispenserRunState.idle,
          amountPkr: 0,
          volumeLiters: 0,
          rate: 200,
          meterCount: 0,
          keypadLocked: false,
          lastRupees: '',
          lastLiters: '',
          lastTime: '',
          lastCashier: '',
        );
      case 4:
        return const DispenserUnit(
          unitId: 4,
          name: 'Unit 4',
          fuelType: kDieselFuelType,
          status: DispenserRunState.idle,
          amountPkr: 0,
          volumeLiters: 0,
          rate: 150,
          meterCount: 0,
          keypadLocked: false,
          lastRupees: '',
          lastLiters: '',
          lastTime: '',
          lastCashier: '',
        );
      case 5:
        return const DispenserUnit(
          unitId: 5,
          name: 'Unit 5',
          fuelType: kDieselFuelType,
          status: DispenserRunState.idle,
          amountPkr: 0,
          volumeLiters: 0,
          rate: 200,
          meterCount: 0,
          keypadLocked: false,
          lastRupees: '',
          lastLiters: '',
          lastTime: '',
          lastCashier: '',
        );
      case 1:
      default:
        return const DispenserUnit(
          unitId: 1,
          name: 'Unit 1',
          fuelType: kDieselFuelType,
          status: DispenserRunState.idle,
          amountPkr: 0,
          volumeLiters: 0,
          rate: 200,
          meterCount: 0,
          keypadLocked: false,
          lastRupees: '',
          lastLiters: '',
          lastTime: '',
          lastCashier: '',
        );
    }
  }

  static StationState seed() {
    return StationState(
      units: <int, DispenserUnit>{
        for (final int unitId in dispenserUnitIds) unitId: seedUnit(unitId),
      },
      sequences: <int, int>{
        1: 25,
        2: 14,
        3: 8,
        4: 2,
        5: 1,
        kDirectSaleUnitId: 0,
      },
      recentTransactions: const <SaleTransaction>[],
      endpoints: <int, UnitEndpoint>{
        for (final int unitId in dispenserUnitIds)
          unitId: UnitEndpoint.seedFor(unitId),
      },
      dieselAverageRate: 0,
    );
  }

  StationState copyWith({
    Map<int, DispenserUnit>? units,
    Map<int, int>? sequences,
    List<SaleTransaction>? recentTransactions,
    Map<int, UnitEndpoint>? endpoints,
    double? dieselAverageRate,
    Map<int, String>? abortNotices,
  }) {
    return StationState(
      units: units ?? this.units,
      sequences: sequences ?? this.sequences,
      recentTransactions: recentTransactions ?? this.recentTransactions,
      endpoints: endpoints ?? this.endpoints,
      dieselAverageRate: dieselAverageRate ?? this.dieselAverageRate,
      abortNotices: abortNotices ?? this.abortNotices,
    );
  }
}

int tokenIdFor({required int unitId, required int sequence}) {
  return (unitId * 100000) + sequence;
}

int sequenceFromToken(int tokenNo, int unitId) {
  return tokenNo - (unitId * 100000);
}

String formatTokenNo(int tokenNo) {
  return tokenNo.abs().toString().padLeft(6, '0');
}

String formatLedgerToken(int tokenNo) {
  if (isDirectSaleToken(tokenNo)) {
    return 'TKN-DR-${formatTokenNo(tokenNo)}';
  }
  return 'TKN-${formatTokenNo(tokenNo)}';
}

int parseLedgerToken(String raw) {
  final String digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  return int.tryParse(digits) ?? 0;
}

PaymentMethod paymentMethodFromStorage(String? raw) {
  switch ((raw ?? '').trim().toLowerCase()) {
    case 'udhaar':
      return PaymentMethod.udhaar;
    case 'bank account':
    case 'bankaccount':
    case 'bank / digital':
    case 'bank':
      return PaymentMethod.bankAccount;
    case 'easypaisa':
      return PaymentMethod.easyPaisa;
    default:
      return PaymentMethod.cash;
  }
}

String formatUnitLabel(int unitId) {
  if (isDirectSaleUnit(unitId)) {
    return 'Direct';
  }
  return 'Unit ${unitId.toString().padLeft(2, '0')}';
}

/// Sale-table UNIT cell: pumps stay `01`…`05`; Direct is `Direct`.
String formatSaleUnitColumn(int unitId) {
  if (isDirectSaleUnit(unitId)) {
    return 'Direct';
  }
  return unitId.toString().padLeft(2, '0');
}

String displayCustomerName(String name) {
  final String trimmed = name.trim();
  if (trimmed.isEmpty || trimmed.toLowerCase() == 'walk-in') {
    return '—';
  }
  return trimmed;
}

String displayVehicleNo(String vehicleNo) {
  final String trimmed = vehicleNo.trim();
  if (trimmed.isEmpty) {
    return '—';
  }
  return trimmed;
}

String displaySaleFulfillment({
  required String vehicleNo,
  required int drumQty,
}) {
  final String plate = displayVehicleNo(vehicleNo);
  if (drumQty > 0) {
    final String drums = '$drumQty ${drumQty == 1 ? 'drum' : 'drums'}';
    if (plate == '—') {
      return drums;
    }
    return '$plate · $drums';
  }
  return plate;
}
