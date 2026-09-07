enum DispenserRunState { idle, dispensing, cycleComplete, offline }

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
}

DispenserRunState dispenserStatusFromWire(String? raw) {
  switch ((raw ?? '').trim().toUpperCase()) {
    case 'DISPENSING':
      return DispenserRunState.dispensing;
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
  });

  final int unitId;
  final String name;
  final String fuelType;
  final DispenserRunState status;
  final double amountPkr;
  final double volumeLiters;
  final double rate;
  final int meterCount;
  final bool keypadLocked;
  final String lastRupees;
  final String lastLiters;
  final String lastTime;
  final String lastCashier;
  final String lastCustomer;
  final String lastVehicleNo;
  final PaymentMethod lastPayment;
  final DateTime? lastPacketAt;

  static const double zeroVolumeEpsilon = 0.005;

  bool get isDispensing => status == DispenserRunState.dispensing;
  bool get isOffline => status == DispenserRunState.offline;
  bool get isOnline => !isOffline;
  bool get isCycleComplete => status == DispenserRunState.cycleComplete;
  bool get isZeroVolume => volumeLiters.abs() < zeroVolumeEpsilon;
  bool get canConfirmPayment => isOnline && isCycleComplete && !isZeroVolume;

  String get productLabel => fuelType.toUpperCase();

  DispenserBay copyWith({
    DispenserRunState? status,
    double? amountPkr,
    double? volumeLiters,
    double? rate,
    int? meterCount,
    bool? keypadLocked,
    String? lastRupees,
    String? lastLiters,
    String? lastTime,
    String? lastCashier,
    String? lastCustomer,
    String? lastVehicleNo,
    PaymentMethod? lastPayment,
    DateTime? lastPacketAt,
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
  });

  final int unitId;
  final double amountPkr;
  final double volumeLiters;
  final double rate;
  final int meterCount;
  final DispenserRunState status;
  final bool keypadLocked;

  /// ESP-01 Wi-Fi RSSI in dBm when the gateway includes it.
  final int? rssiDbm;

  /// Raw GPIO 14 pulse encoder ticks. Falls back to [meterCount] in the UI.
  final int? pulseCount;

  int get encoderPulses => pulseCount ?? meterCount;
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
    this.shiftName = 'Morning',
    this.notes = '',
    this.udhaarSettled = false,
    this.settledAmount = 0,
    this.settledAt,
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
  final String shiftName;
  final String notes;
  final bool udhaarSettled;
  final double settledAmount;
  final DateTime? settledAt;

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
    String? shiftName,
    String? notes,
    bool? udhaarSettled,
    double? settledAmount,
    DateTime? settledAt,
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
      shiftName: shiftName ?? this.shiftName,
      notes: notes ?? this.notes,
      udhaarSettled: udhaarSettled ?? this.udhaarSettled,
      settledAmount: settledAmount ?? this.settledAmount,
      settledAt: settledAt ?? this.settledAt,
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

List<int> get dispenserUnitIds =>
    List<int>.generate(kDispenserUnitCount, (int i) => i + 1);

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
    return UnitEndpoint(host: '192.168.1.${100 + unitId}', port: 8080);
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
          meterCount: 13454719,
          keypadLocked: false,
          lastRupees: 'Rs. 1,200.00',
          lastLiters: '8.00 Ltr',
          lastTime: '12:40 PM',
          lastCashier: 'Ali',
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
          meterCount: 13450108,
          keypadLocked: false,
          lastRupees: 'Rs. 800.00',
          lastLiters: '4.00 Ltr',
          lastTime: '11:55 AM',
          lastCashier: 'Cashier',
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
          meterCount: 13449880,
          keypadLocked: false,
          lastRupees: 'Rs. 600.00',
          lastLiters: '4.00 Ltr',
          lastTime: '11:30 AM',
          lastCashier: 'Usman',
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
          meterCount: 13451200,
          keypadLocked: false,
          lastRupees: 'Rs. 900.00',
          lastLiters: '4.50 Ltr',
          lastTime: '11:10 AM',
          lastCashier: 'Cashier',
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
          meterCount: 13452342,
          keypadLocked: false,
          lastRupees: 'Rs. 1,500.00',
          lastLiters: '7.50 Ltr',
          lastTime: '12:30 PM',
          lastCashier: 'Cashier',
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
