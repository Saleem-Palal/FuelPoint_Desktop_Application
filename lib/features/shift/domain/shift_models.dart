import 'package:flutter/material.dart';

import '../../station/domain/dispenser_models.dart';

enum ShiftWorkspaceTab { operators, helpers }

enum OperatorTallyPane { todaySales, historical }

enum OperatorRole { operator, owner }

enum OperatorProfileStatus { active, inactive }

enum HelperDutyStatus { onDuty, offDuty, inactive }

enum OperatorShiftStatus { open, pendingReconciliation, closed, forceClosed }

enum HelperRangePreset { today, thisMonth, custom }

enum StartShiftOutcome { started, alreadyOnDuty, blocked, invalidPin }

enum HandoverOutcome {
  handedOff,
  invalidPin,
  noActiveShift,
  unknownOperator,
  sameOperator,
  alreadyPending,
  unitsDispensing,
  pendingAccount,
}

/// Default attendant reward until a station setting is persisted.
const double kDefaultHelperRewardPerTx = 5;

/// Mock PIN used for newly added operators until SQLite credentials exist.
const String kDefaultOperatorPin = '0000';

class OperatorProfile {
  const OperatorProfile({
    required this.id,
    required this.name,
    required this.role,
    required this.status,
    this.pin = kDefaultOperatorPin,
  });

  final String id;
  final String name;
  final OperatorRole role;
  final OperatorProfileStatus status;
  final String pin;

  String get initials => initialsFromName(name);

  OperatorProfile copyWith({
    String? name,
    OperatorRole? role,
    OperatorProfileStatus? status,
    String? pin,
  }) {
    return OperatorProfile(
      id: id,
      name: name ?? this.name,
      role: role ?? this.role,
      status: status ?? this.status,
      pin: pin ?? this.pin,
    );
  }
}

/// Master helper row (`helpers` table). Duty is derived from unit assignment.
class HelperProfile {
  HelperProfile({
    required this.id,
    required this.name,
    this.isActive = true,
    List<int>? assignedUnitIds,
    int? assignedUnitId,
  }) : assignedUnitIds = _normalizedIds(assignedUnitIds, assignedUnitId);

  final String id;
  final String name;
  final bool isActive;
  final List<int> assignedUnitIds;

  static List<int> _normalizedIds(List<int>? ids, int? single) {
    final List<int> next = <int>[
      if (ids != null) ...ids,
      if (single != null) single,
    ];
    final Set<int> unique = <int>{};
    final List<int> ordered = <int>[];
    for (final int id in next) {
      if (unique.add(id)) {
        ordered.add(id);
      }
    }
    ordered.sort();
    return List<int>.unmodifiable(ordered);
  }

  String get initials => initialsFromName(name);

  int? get assignedUnitId =>
      assignedUnitIds.isEmpty ? null : assignedUnitIds.first;

  int? get unitId => assignedUnitId;

  bool isAssignedTo(int unitId) => assignedUnitIds.contains(unitId);

  HelperDutyStatus get status {
    if (!isActive) {
      return HelperDutyStatus.inactive;
    }
    if (assignedUnitIds.isNotEmpty) {
      return HelperDutyStatus.onDuty;
    }
    return HelperDutyStatus.offDuty;
  }

  HelperProfile copyWith({
    String? name,
    bool? isActive,
    List<int>? assignedUnitIds,
    bool clearAssignment = false,
  }) {
    return HelperProfile(
      id: id,
      name: name ?? this.name,
      isActive: isActive ?? this.isActive,
      assignedUnitIds: clearAssignment
          ? const <int>[]
          : (assignedUnitIds ?? this.assignedUnitIds),
    );
  }

  HelperProfile withUnitAdded(int unitId) {
    if (assignedUnitIds.contains(unitId)) {
      return this;
    }
    return copyWith(assignedUnitIds: <int>[...assignedUnitIds, unitId]);
  }

  HelperProfile withUnitRemoved(int unitId) {
    if (!assignedUnitIds.contains(unitId)) {
      return this;
    }
    return copyWith(
      assignedUnitIds: assignedUnitIds.where((int id) => id != unitId).toList(),
    );
  }
}

class HelperDutySession {
  const HelperDutySession({
    required this.id,
    required this.helperId,
    required this.helperName,
    required this.unitId,
    required this.startTime,
    this.endTime,
  });

  final String id;
  final String helperId;
  final String helperName;
  final int unitId;
  final DateTime startTime;
  final DateTime? endTime;

  bool get isOpen => endTime == null;

  HelperDutySession copyWith({DateTime? endTime}) {
    return HelperDutySession(
      id: id,
      helperId: helperId,
      helperName: helperName,
      unitId: unitId,
      startTime: startTime,
      endTime: endTime ?? this.endTime,
    );
  }
}

class OperatorShiftRecord {
  const OperatorShiftRecord({
    required this.shiftId,
    required this.operatorId,
    required this.operatorName,
    required this.role,
    required this.startTime,
    required this.expectedCash,
    required this.status,
    this.endTime,
    this.actualCash,
    this.notes = '',
    this.udhaarRecoveryTotal = 0,
    this.openingMeters = const <int, double>{},
    this.closingMeters = const <int, double>{},
  });

  final String shiftId;
  final String operatorId;
  final String operatorName;
  final OperatorRole role;
  final DateTime startTime;
  final DateTime? endTime;
  final double expectedCash;
  final double? actualCash;
  final String notes;
  final OperatorShiftStatus status;
  final double udhaarRecoveryTotal;
  final Map<int, double> openingMeters;
  final Map<int, double> closingMeters;

  double get discrepancy {
    final double? actual = actualCash;
    if (actual == null) {
      return 0;
    }
    return actual - expectedCash;
  }

  bool get isOpen => status == OperatorShiftStatus.open;

  bool get isPendingReconciliation =>
      status == OperatorShiftStatus.pendingReconciliation;

  OperatorShiftRecord copyWith({
    DateTime? endTime,
    double? expectedCash,
    double? actualCash,
    String? notes,
    OperatorShiftStatus? status,
    double? udhaarRecoveryTotal,
    Map<int, double>? openingMeters,
    Map<int, double>? closingMeters,
  }) {
    return OperatorShiftRecord(
      shiftId: shiftId,
      operatorId: operatorId,
      operatorName: operatorName,
      role: role,
      startTime: startTime,
      endTime: endTime ?? this.endTime,
      expectedCash: expectedCash ?? this.expectedCash,
      actualCash: actualCash ?? this.actualCash,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      udhaarRecoveryTotal: udhaarRecoveryTotal ?? this.udhaarRecoveryTotal,
      openingMeters: openingMeters ?? this.openingMeters,
      closingMeters: closingMeters ?? this.closingMeters,
    );
  }
}

class HelperSaleRecord {
  const HelperSaleRecord({
    required this.tokenNo,
    required this.timestamp,
    required this.helperId,
    required this.helperName,
    required this.unitId,
    required this.fuelType,
    required this.volumeLiters,
    required this.rate,
    required this.amountPkr,
    this.payment = PaymentMethod.cash,
    this.shiftId = '',
    this.cashierName = '',
    this.operatorId = '',
    this.cashAmount = 0,
    this.accountAmount = 0,
    this.pendingAccountAmount = 0,
    this.openingMeter = 0,
    this.closingMeter = 0,
    this.customerName = '',
    this.vehicleNo = '',
    this.operatorStaffId = '',
    this.helperStaffId = '',
    this.actions = '',
    this.espTxId = '',
    this.edited = false,
    this.isTest = false,
    this.drumQty = 0,
  });

  final int tokenNo;
  final DateTime timestamp;
  final String helperId;
  final String helperName;
  final int unitId;
  final String fuelType;
  final double volumeLiters;
  final double rate;
  final double amountPkr;
  final PaymentMethod payment;
  final String shiftId;
  final String cashierName;
  final String operatorId;
  final double cashAmount;
  final double accountAmount;
  final double pendingAccountAmount;
  final double openingMeter;
  final double closingMeter;
  final String customerName;
  final String vehicleNo;
  final String operatorStaffId;
  final String helperStaffId;
  final String actions;
  final String espTxId;
  final bool edited;
  final bool isTest;
  final int drumQty;

  /// Cash column only. Never [amountPkr] (that would double-count the ticket).
  double get cashTender {
    switch (payment) {
      case PaymentMethod.udhaar:
        return 0;
      case PaymentMethod.cash:
        return cashAmount > 0 ? cashAmount : amountPkr;
      case PaymentMethod.bankAccount:
      case PaymentMethod.easyPaisa:
        return cashAmount;
    }
  }

  /// Account column only. Legacy Account rows with empty split use [amountPkr].
  double get accountTender {
    switch (payment) {
      case PaymentMethod.bankAccount:
      case PaymentMethod.easyPaisa:
        if (pendingAccountAmount > 0) {
          return accountAmount;
        }
        if (cashAmount > 0 || accountAmount > 0) {
          return accountAmount;
        }
        return amountPkr;
      case PaymentMethod.cash:
      case PaymentMethod.udhaar:
        return 0;
    }
  }

  HelperSaleRecord copyWith({
    int? tokenNo,
    DateTime? timestamp,
    String? helperId,
    String? helperName,
    int? unitId,
    String? fuelType,
    double? volumeLiters,
    double? rate,
    double? amountPkr,
    PaymentMethod? payment,
    String? shiftId,
    String? cashierName,
    String? operatorId,
    double? cashAmount,
    double? accountAmount,
    double? pendingAccountAmount,
    double? openingMeter,
    double? closingMeter,
    String? customerName,
    String? vehicleNo,
    String? operatorStaffId,
    String? helperStaffId,
    String? actions,
    String? espTxId,
    bool? edited,
    bool? isTest,
    int? drumQty,
  }) {
    return HelperSaleRecord(
      tokenNo: tokenNo ?? this.tokenNo,
      timestamp: timestamp ?? this.timestamp,
      helperId: helperId ?? this.helperId,
      helperName: helperName ?? this.helperName,
      unitId: unitId ?? this.unitId,
      fuelType: fuelType ?? this.fuelType,
      volumeLiters: volumeLiters ?? this.volumeLiters,
      rate: rate ?? this.rate,
      amountPkr: amountPkr ?? this.amountPkr,
      payment: payment ?? this.payment,
      shiftId: shiftId ?? this.shiftId,
      cashierName: cashierName ?? this.cashierName,
      operatorId: operatorId ?? this.operatorId,
      cashAmount: cashAmount ?? this.cashAmount,
      accountAmount: accountAmount ?? this.accountAmount,
      pendingAccountAmount: pendingAccountAmount ?? this.pendingAccountAmount,
      openingMeter: openingMeter ?? this.openingMeter,
      closingMeter: closingMeter ?? this.closingMeter,
      customerName: customerName ?? this.customerName,
      vehicleNo: vehicleNo ?? this.vehicleNo,
      operatorStaffId: operatorStaffId ?? this.operatorStaffId,
      helperStaffId: helperStaffId ?? this.helperStaffId,
      actions: actions ?? this.actions,
      espTxId: espTxId ?? this.espTxId,
      edited: edited ?? this.edited,
      isTest: isTest ?? this.isTest,
      drumQty: drumQty ?? this.drumQty,
    );
  }
}

@immutable
class HelperPerformanceSnapshot {
  const HelperPerformanceSnapshot({
    required this.transactionCount,
    required this.totalLiters,
    required this.rewardPayout,
    required this.rewardRate,
    required this.firstSaleAt,
    required this.lastSaleAt,
    required this.sales,
  });

  final int transactionCount;
  final double totalLiters;
  final double rewardPayout;
  final double rewardRate;
  final DateTime? firstSaleAt;
  final DateTime? lastSaleAt;
  final List<HelperSaleRecord> sales;

  static const HelperPerformanceSnapshot empty = HelperPerformanceSnapshot(
    transactionCount: 0,
    totalLiters: 0,
    rewardPayout: 0,
    rewardRate: kDefaultHelperRewardPerTx,
    firstSaleAt: null,
    lastSaleAt: null,
    sales: <HelperSaleRecord>[],
  );
}

HelperPerformanceSnapshot helperPerformanceSnapshot(
  List<HelperSaleRecord> rows, {
  required double rewardRate,
}) {
  final List<HelperSaleRecord> sorted = List<HelperSaleRecord>.from(rows)
    ..sort(
      (HelperSaleRecord a, HelperSaleRecord b) =>
          b.timestamp.compareTo(a.timestamp),
    );
  final double liters = sorted.fold<double>(0, (
    double sum,
    HelperSaleRecord row,
  ) {
    return isDirectSaleUnit(row.unitId) ? sum : sum + row.volumeLiters;
  });
  DateTime? firstSale;
  DateTime? lastSale;
  int commercialCount = 0;
  for (final HelperSaleRecord row in sorted) {
    if (row.isTest || isDirectSaleUnit(row.unitId)) {
      continue;
    }
    commercialCount += 1;
    if (firstSale == null || row.timestamp.isBefore(firstSale)) {
      firstSale = row.timestamp;
    }
    if (lastSale == null || row.timestamp.isAfter(lastSale)) {
      lastSale = row.timestamp;
    }
  }
  final double rate = rewardRate < 0 ? 0 : rewardRate;
  return HelperPerformanceSnapshot(
    transactionCount: commercialCount,
    totalLiters: liters,
    rewardPayout: commercialCount * rate,
    rewardRate: rate,
    firstSaleAt: firstSale,
    lastSaleAt: lastSale,
    sales: sorted
        .where((HelperSaleRecord row) => !isDirectSaleUnit(row.unitId))
        .toList(),
  );
}

@immutable
class ShiftWindowMetrics {
  const ShiftWindowMetrics({
    required this.sales,
    required this.fuelCashSales,
    required this.udhaarSales,
    required this.accountSales,
    required this.udhaarRecoveryTotal,
    required this.totalLiters,
    this.udhaarRecoveryAccountTotal = 0,
    this.udhaarRecoveryPartialTotal = 0,
    this.directSales = const <HelperSaleRecord>[],
    this.firstToken,
    this.lastToken,
  });

  /// Visible tickets including tagged test fills. Money KPIs exclude tests.
  /// [totalLiters] includes test fills.
  final List<HelperSaleRecord> sales;

  /// Direct-sale stock tickets. Never rolled into shift cash KPIs.
  final List<HelperSaleRecord> directSales;
  final double fuelCashSales;
  final double udhaarSales;
  final double accountSales;
  final double udhaarRecoveryTotal;
  final double udhaarRecoveryAccountTotal;
  final double udhaarRecoveryPartialTotal;
  final double totalLiters;
  final int? firstToken;
  final int? lastToken;

  int get commercialSaleCount {
    int count = 0;
    for (final HelperSaleRecord row in sales) {
      if (!row.isTest) {
        count += 1;
      }
    }
    return count;
  }

  /// Cash (incl. Cash Now) + Account remainder + Udhaar issued.
  double get totalSale => fuelCashSales + accountSales + udhaarSales;

  /// Cash recoveries + Bank/EasyPaisa recoveries.
  double get udhaarRecoveryCombined =>
      udhaarRecoveryTotal + udhaarRecoveryAccountTotal;

  /// Cash sales + Cash Now on Account + cash udhaar recovery. Purchases are not shift cash.
  double get expectedCashInHand => fuelCashSales + udhaarRecoveryTotal;

  static const ShiftWindowMetrics empty = ShiftWindowMetrics(
    sales: <HelperSaleRecord>[],
    fuelCashSales: 0,
    udhaarSales: 0,
    accountSales: 0,
    udhaarRecoveryTotal: 0,
    totalLiters: 0,
  );

  static const String totalSaleFormula =
      'Cash Sales + Cash Now + Account remainder + Udhaar Issued';
  static const String expectedCashFormula =
      'Cash Sales + Cash Now + Udhaar Recovery (Cash)';
  static const String udhaarIssuedHint = 'Credit sales this shift';
  static const String udhaarRecoveryHint =
      'Cash + Account recoveries this shift';
  static const String accountPaymentsHint =
      'Bank / EasyPaisa remainder (not Cash Now)';
}

@immutable
class ShiftSummary {
  const ShiftSummary({required this.shift, required this.metrics});

  final OperatorShiftRecord shift;
  final ShiftWindowMetrics metrics;

  Duration get duration {
    final DateTime end = shift.endTime ?? DateTime.now();
    return end.difference(shift.startTime);
  }
}

@immutable
class ShiftHandoverResult {
  const ShiftHandoverResult({
    required this.outcome,
    this.pending,
    this.opened,
    this.closed,
    this.blockedUnitId,
  });

  final HandoverOutcome outcome;
  final ReconciliationSnapshot? pending;
  final OperatorShiftRecord? opened;
  final OperatorShiftRecord? closed;
  final int? blockedUnitId;

  bool get isSuccess => outcome == HandoverOutcome.handedOff;
}

@immutable
class ReconciliationSnapshot {
  const ReconciliationSnapshot({required this.shift, required this.metrics});

  final OperatorShiftRecord shift;
  final ShiftWindowMetrics metrics;

  Duration get duration {
    final DateTime end = shift.endTime ?? DateTime.now();
    return end.difference(shift.startTime);
  }

  ShiftSummary get summary => ShiftSummary(shift: shift, metrics: metrics);
}

String initialsFromName(String name) {
  final List<String> parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((String part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) {
    return '?';
  }
  if (parts.length == 1) {
    return parts[0].substring(0, 1).toUpperCase();
  }
  return '${parts[0].substring(0, 1)}${parts[1].substring(0, 1)}'.toUpperCase();
}

String operatorRoleLabel(OperatorRole role) {
  switch (role) {
    case OperatorRole.operator:
      return 'Operator';
    case OperatorRole.owner:
      return 'Owner';
  }
}

String operatorStatusLabel(OperatorProfileStatus status) {
  switch (status) {
    case OperatorProfileStatus.active:
      return 'Active';
    case OperatorProfileStatus.inactive:
      return 'Inactive';
  }
}

String helperDutyLabel(HelperProfile helper) {
  switch (helper.status) {
    case HelperDutyStatus.onDuty:
      if (helper.assignedUnitIds.isEmpty) {
        return 'On Duty';
      }
      return 'On Duty — ${helper.assignedUnitIds.map((int id) => 'Unit $id').join(', ')}';
    case HelperDutyStatus.offDuty:
      return 'Off Duty';
    case HelperDutyStatus.inactive:
      return 'Inactive';
  }
}

String shiftStatusLabel(OperatorShiftStatus status) {
  switch (status) {
    case OperatorShiftStatus.open:
      return 'Live';
    case OperatorShiftStatus.pendingReconciliation:
      return 'Pending tally';
    case OperatorShiftStatus.closed:
      return 'Closed';
    case OperatorShiftStatus.forceClosed:
      return 'Force closed';
  }
}

String formatShiftDuration(Duration duration) {
  final Duration safe = duration.isNegative ? Duration.zero : duration;
  final int hours = safe.inHours;
  final int minutes = safe.inMinutes.remainder(60);
  final int seconds = safe.inSeconds.remainder(60);
  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

DateTime dateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

String formatShiftId(int shiftPk) => 'SHF-$shiftPk';

int? parseShiftPk(String shiftId) {
  final Match? match = RegExp(r'(\d+)$').firstMatch(shiftId.trim());
  if (match == null) {
    return null;
  }
  return int.tryParse(match.group(1) ?? '');
}

DateTimeRange rangeForPreset(HelperRangePreset preset, {DateTime? now}) {
  final DateTime clock = now ?? DateTime.now();
  switch (preset) {
    case HelperRangePreset.today:
      return DateTimeRange(start: dateOnly(clock), end: dateOnly(clock));
    case HelperRangePreset.thisMonth:
      return DateTimeRange(
        start: DateTime(clock.year, clock.month),
        end: dateOnly(clock),
      );
    case HelperRangePreset.custom:
      return DateTimeRange(start: dateOnly(clock), end: dateOnly(clock));
  }
}

bool isInInclusiveRange(DateTime value, DateTimeRange range) {
  final DateTime day = dateOnly(value);
  return !day.isBefore(dateOnly(range.start)) &&
      !day.isAfter(dateOnly(range.end));
}

bool isInShiftWindow(DateTime value, DateTime start, {DateTime? end}) {
  if (value.isBefore(start)) {
    return false;
  }
  if (end != null && value.isAfter(end)) {
    return false;
  }
  return true;
}

ShiftWindowMetrics metricsForSales(
  List<HelperSaleRecord> rows, {
  double udhaarRecoveryTotal = 0,
  double udhaarRecoveryAccountTotal = 0,
  double udhaarRecoveryPartialTotal = 0,
}) {
  final List<HelperSaleRecord> sorted = List<HelperSaleRecord>.from(rows)
    ..sort(
      (HelperSaleRecord a, HelperSaleRecord b) =>
          a.timestamp.compareTo(b.timestamp),
    );
  double cash = 0;
  double udhaar = 0;
  double account = 0;
  double liters = 0;
  int? firstToken;
  int? lastToken;
  for (final HelperSaleRecord row in sorted) {
    if (isDirectSaleUnit(row.unitId)) {
      continue;
    }
    liters += row.volumeLiters;
    if (row.isTest) {
      continue;
    }
    switch (row.payment) {
      case PaymentMethod.cash:
        cash += row.cashTender;
      case PaymentMethod.udhaar:
        udhaar += row.amountPkr;
      case PaymentMethod.bankAccount:
      case PaymentMethod.easyPaisa:
        cash += row.cashTender;
        account += row.accountTender;
    }
    if (firstToken == null || row.tokenNo < firstToken) {
      firstToken = row.tokenNo;
    }
    if (lastToken == null || row.tokenNo > lastToken) {
      lastToken = row.tokenNo;
    }
  }
  return ShiftWindowMetrics(
    sales: sorted.reversed
        .where((HelperSaleRecord row) => !isDirectSaleUnit(row.unitId))
        .toList(),
    directSales: sorted
        .where((HelperSaleRecord row) => isDirectSaleUnit(row.unitId))
        .toList(),
    fuelCashSales: cash,
    udhaarSales: udhaar,
    accountSales: account,
    udhaarRecoveryTotal: udhaarRecoveryTotal,
    udhaarRecoveryAccountTotal: udhaarRecoveryAccountTotal,
    udhaarRecoveryPartialTotal: udhaarRecoveryPartialTotal,
    totalLiters: liters,
    firstToken: firstToken,
    lastToken: lastToken,
  );
}

List<HelperSaleRecord> salesInShiftWindow(
  List<HelperSaleRecord> sales,
  OperatorShiftRecord shift,
) {
  return sales.where((HelperSaleRecord row) {
    return isInShiftWindow(row.timestamp, shift.startTime, end: shift.endTime);
  }).toList();
}

/// Itemized rows for an outgoing operator: tagged `shiftId`, else operator + window.
List<HelperSaleRecord> salesForOutgoingOperator(
  List<HelperSaleRecord> sales,
  OperatorShiftRecord shift,
) {
  return sales.where((HelperSaleRecord row) {
    if (row.shiftId.isNotEmpty) {
      return row.shiftId == shift.shiftId;
    }
    if (row.operatorId.isNotEmpty) {
      return row.operatorId == shift.operatorId &&
          isInShiftWindow(row.timestamp, shift.startTime, end: shift.endTime);
    }
    final bool matchesCashier = row.cashierName.isEmpty
        ? true
        : row.cashierName == shift.operatorName;
    return matchesCashier &&
        isInShiftWindow(row.timestamp, shift.startTime, end: shift.endTime);
  }).toList();
}

HelperProfile? helperById(List<HelperProfile> helpers, String? id) {
  if (id == null) {
    return null;
  }
  for (final HelperProfile helper in helpers) {
    if (helper.id == id) {
      return helper;
    }
  }
  return null;
}

HelperProfile? helperOnUnit(List<HelperProfile> helpers, int unitId) {
  for (final HelperProfile helper in helpers) {
    if (helper.isActive && helper.isAssignedTo(unitId)) {
      return helper;
    }
  }
  return null;
}

/// Current helper id per dispenser unit. Null means the unit is unassigned.
Map<int, String?> unitHelperAssignmentsOf(List<HelperProfile> helpers) {
  return <int, String?>{
    for (final int unitId in dispenserUnitIds)
      unitId: helperOnUnit(helpers, unitId)?.id,
  };
}
