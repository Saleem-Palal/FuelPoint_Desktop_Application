import 'dart:convert';

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

class DispenserBay {
  const DispenserBay({
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

  /// Manager on the latest `sales_transactions` row for this unit.
  final String lastCashier;
  final String lastCustomer;
  final String lastVehicleNo;
  final PaymentMethod lastPayment;
  final DateTime? lastPacketAt;
  final String lastEspTxId;

  static const double zeroVolumeEpsilon = 0.005;

  bool get isDispensing => status == DispenserRunState.dispensing;
  bool get isOffline => status == DispenserRunState.offline;
  bool get isOnline => !isOffline;
  bool get isCycleComplete => status == DispenserRunState.cycleComplete;
  bool get isZeroVolume => volumeLiters.abs() < zeroVolumeEpsilon;
  bool get canConfirmPayment => isCycleComplete && !isZeroVolume;

  String get productLabel => fuelType.toUpperCase();

  DispenserBay copyWith({
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
    bool clearLastPacket = false,
  }) {
    return DispenserBay(
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
      DispenserBay.zeroVolumeEpsilon;
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
        rate: _espHundredths(
          tel['rate'] ?? tel['rate_pkr'],
          tel['rate_cents'],
        ),
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
    this.cashierName = 'Cashier',
    this.helperName = '',
    this.shiftId = '',
    this.shiftName = 'Morning',
    this.notes = '',
    this.udhaarSettled = false,
    this.settledAmount = 0,
    this.settledAt,
    this.espTxId = '',
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

  bool get isUnsettledUdhaar {
    return payment == PaymentMethod.udhaar && !udhaarSettled;
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

/// Active dispenser bays on the sale workspace (Unit 1 … Unit N).
const int kDispenserUnitCount = 5;

/// Hardware bays on Tenda System (Unit 5 stays hidden unless Settings enables it).
const int kHardwareDispenserUnitCount = 4;

/// Optional extra bay. Hidden on the Sale screen unless enabled in Settings.
const int kOptionalDispenserUnitId = 5;

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
    return UnitEndpoint(
      host: '192.168.0.${100 + (10 * unitId)}',
      port: 81,
    );
  }
}

/// Sole station product. Purchase, sale, and LCD RATE all share this type.
const String kDieselFuelType = 'Diesel';

class StationState {
  const StationState({
    required this.bays,
    required this.sequences,
    required this.recentTransactions,
    required this.endpoints,
    this.dieselAverageRate = 0,
    this.abortNotices = const <int, String>{},
  });

  final Map<int, DispenserBay> bays;
  final Map<int, int> sequences;
  final List<SaleTransaction> recentTransactions;
  final Map<int, UnitEndpoint> endpoints;

  /// Weighted-average diesel cost from Purchase. Independent of per-bay RATE.
  final double dieselAverageRate;
  final Map<int, String> abortNotices;

  String? abortNoticeFor(int unitId) => abortNotices[unitId];

  /// WebSocket is open and the last JSON frame is younger than 3 s.
  bool isUnitLinkOnline(int unitId, {DateTime? now}) {
    final UnitEndpoint ep = endpoint(unitId);
    if (!ep.connected) {
      return false;
    }
    final DateTime? at = bay(unitId).lastPacketAt;
    if (at == null) {
      return true;
    }
    return (now ?? DateTime.now()).difference(at) <
        const Duration(seconds: 3);
  }

  UnitEndpoint endpoint(int unitId) {
    final UnitEndpoint? found = endpoints[unitId];
    if (found != null) {
      return found;
    }
    return UnitEndpoint.seedFor(unitId);
  }

  DispenserBay bay(int unitId) {
    final DispenserBay? found = bays[unitId];
    if (found != null) {
      return found;
    }
    return StationState.seedBay(unitId);
  }

  static DispenserBay seedBay(int unitId) {
    switch (unitId) {
      case 2:
        return const DispenserBay(
          unitId: 2,
          name: 'Unit 2',
          fuelType: kDieselFuelType,
          status: DispenserRunState.idle,
          amountPkr: 0,
          volumeLiters: 0,
          rate: 150,
          meterCount: 13454719.863,
          keypadLocked: false,
          lastRupees: '',
          lastLiters: '',
          lastTime: '',
          lastCashier: '',
        );
      case 3:
        return const DispenserBay(
          unitId: 3,
          name: 'Unit 3',
          fuelType: kDieselFuelType,
          status: DispenserRunState.idle,
          amountPkr: 0,
          volumeLiters: 0,
          rate: 200,
          meterCount: 13450108.004,
          keypadLocked: false,
          lastRupees: '',
          lastLiters: '',
          lastTime: '',
          lastCashier: '',
        );
      case 4:
        return const DispenserBay(
          unitId: 4,
          name: 'Unit 4',
          fuelType: kDieselFuelType,
          status: DispenserRunState.idle,
          amountPkr: 0,
          volumeLiters: 0,
          rate: 150,
          meterCount: 13449880.55,
          keypadLocked: false,
          lastRupees: '',
          lastLiters: '',
          lastTime: '',
          lastCashier: '',
        );
      case 5:
        return const DispenserBay(
          unitId: 5,
          name: 'Unit 5',
          fuelType: kDieselFuelType,
          status: DispenserRunState.idle,
          amountPkr: 0,
          volumeLiters: 0,
          rate: 200,
          meterCount: 13451200.21,
          keypadLocked: false,
          lastRupees: '',
          lastLiters: '',
          lastTime: '',
          lastCashier: '',
        );
      case 1:
      default:
        return const DispenserBay(
          unitId: 1,
          name: 'Unit 1',
          fuelType: kDieselFuelType,
          status: DispenserRunState.idle,
          amountPkr: 0,
          volumeLiters: 0,
          rate: 200,
          meterCount: 13452342.143,
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
      bays: <int, DispenserBay>{
        for (final int unitId in dispenserUnitIds) unitId: seedBay(unitId),
      },
      sequences: <int, int>{1: 25, 2: 14, 3: 8, 4: 2, 5: 1},
      recentTransactions: const <SaleTransaction>[],
      endpoints: <int, UnitEndpoint>{
        for (final int unitId in dispenserUnitIds)
          unitId: UnitEndpoint.seedFor(unitId),
      },
      dieselAverageRate: 0,
    );
  }

  StationState copyWith({
    Map<int, DispenserBay>? bays,
    Map<int, int>? sequences,
    List<SaleTransaction>? recentTransactions,
    Map<int, UnitEndpoint>? endpoints,
    double? dieselAverageRate,
    Map<int, String>? abortNotices,
  }) {
    return StationState(
      bays: bays ?? this.bays,
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
  return 'Unit ${unitId.toString().padLeft(2, '0')}';
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
