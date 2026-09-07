import 'package:flutter/material.dart';

import '../../station/domain/dispenser_models.dart';

enum ShiftWorkspaceTab { managers, helpers }

enum ManagerTallyPane { todaySales, historical }

enum ManagerRole { manager, owner }

enum ManagerProfileStatus { active, inactive }

enum HelperDutyStatus { onDuty, offDuty, inactive }

enum ManagerShiftStatus { open, pendingReconciliation, closed, forceClosed }

enum HelperRangePreset { today, thisMonth, custom }

enum StartShiftOutcome { started, alreadyOnDuty, blocked, invalidPin }

enum HandoverOutcome {
  handedOff,
  invalidPin,
  noActiveShift,
  unknownManager,
  sameManager,
  alreadyPending,
}

/// Default attendant reward until a station setting is persisted.
const double kDefaultHelperRewardPerTx = 5;

/// Mock PIN used for newly added managers until SQLite credentials exist.
const String kDefaultManagerPin = '0000';

class ManagerProfile {
  const ManagerProfile({
    required this.id,
    required this.name,
    required this.role,
    required this.status,
    this.pin = kDefaultManagerPin,
  });

  final String id;
  final String name;
  final ManagerRole role;
  final ManagerProfileStatus status;
  final String pin;

  String get initials => initialsFromName(name);

  ManagerProfile copyWith({
    String? name,
    ManagerRole? role,
    ManagerProfileStatus? status,
    String? pin,
  }) {
    return ManagerProfile(
      id: id,
      name: name ?? this.name,
      role: role ?? this.role,
      status: status ?? this.status,
      pin: pin ?? this.pin,
    );
  }
}

/// Master helper row (`helpers` table). Duty is derived from bay assignment.
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

class ManagerShiftRecord {
  const ManagerShiftRecord({
    required this.shiftId,
    required this.managerId,
    required this.managerName,
    required this.role,
    required this.startTime,
    required this.expectedCash,
    required this.status,
    this.endTime,
    this.actualCash,
    this.notes = '',
    this.udhaarRecoveryTotal = 0,
  });

  final String shiftId;
  final String managerId;
  final String managerName;
  final ManagerRole role;
  final DateTime startTime;
  final DateTime? endTime;
  final double expectedCash;
  final double? actualCash;
  final String notes;
  final ManagerShiftStatus status;
  final double udhaarRecoveryTotal;

  double get discrepancy {
    final double? actual = actualCash;
    if (actual == null) {
      return 0;
    }
    return actual - expectedCash;
  }

  bool get isOpen => status == ManagerShiftStatus.open;

  bool get isPendingReconciliation =>
      status == ManagerShiftStatus.pendingReconciliation;

  ManagerShiftRecord copyWith({
    DateTime? endTime,
    double? expectedCash,
    double? actualCash,
    String? notes,
    ManagerShiftStatus? status,
    double? udhaarRecoveryTotal,
  }) {
    return ManagerShiftRecord(
      shiftId: shiftId,
      managerId: managerId,
      managerName: managerName,
      role: role,
      startTime: startTime,
      endTime: endTime ?? this.endTime,
      expectedCash: expectedCash ?? this.expectedCash,
      actualCash: actualCash ?? this.actualCash,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      udhaarRecoveryTotal: udhaarRecoveryTotal ?? this.udhaarRecoveryTotal,
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
    this.managerId = '',
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
  final String managerId;
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
  final double liters = sorted.fold<double>(
    0,
    (double sum, HelperSaleRecord row) => sum + row.volumeLiters,
  );
  DateTime? firstSale;
  DateTime? lastSale;
  for (final HelperSaleRecord row in sorted) {
    if (firstSale == null || row.timestamp.isBefore(firstSale)) {
      firstSale = row.timestamp;
    }
    if (lastSale == null || row.timestamp.isAfter(lastSale)) {
      lastSale = row.timestamp;
    }
  }
  final double rate = rewardRate < 0 ? 0 : rewardRate;
  return HelperPerformanceSnapshot(
    transactionCount: sorted.length,
    totalLiters: liters,
    rewardPayout: sorted.length * rate,
    rewardRate: rate,
    firstSaleAt: firstSale,
    lastSaleAt: lastSale,
    sales: sorted,
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
    this.purchaseTotal = 0,
    this.firstToken,
    this.lastToken,
  });

  final List<HelperSaleRecord> sales;
  final double fuelCashSales;
  final double udhaarSales;
  final double accountSales;
  final double udhaarRecoveryTotal;
  final double totalLiters;
  final double purchaseTotal;
  final int? firstToken;
  final int? lastToken;

  /// Cash sales + udhaar settlements − purchases / expenses.
  double get expectedCashInHand =>
      fuelCashSales + udhaarRecoveryTotal - purchaseTotal;

  static const ShiftWindowMetrics empty = ShiftWindowMetrics(
    sales: <HelperSaleRecord>[],
    fuelCashSales: 0,
    udhaarSales: 0,
    accountSales: 0,
    udhaarRecoveryTotal: 0,
    totalLiters: 0,
  );
}

@immutable
class ShiftSummary {
  const ShiftSummary({required this.shift, required this.metrics});

  final ManagerShiftRecord shift;
  final ShiftWindowMetrics metrics;

  Duration get duration {
    final DateTime end = shift.endTime ?? DateTime.now();
    return end.difference(shift.startTime);
  }
}

@immutable
class ShiftHandoverResult {
  const ShiftHandoverResult({required this.outcome, this.pending, this.opened});

  final HandoverOutcome outcome;
  final ReconciliationSnapshot? pending;
  final ManagerShiftRecord? opened;

  bool get isSuccess => outcome == HandoverOutcome.handedOff;
}

@immutable
class ReconciliationSnapshot {
  const ReconciliationSnapshot({required this.shift, required this.metrics});

  final ManagerShiftRecord shift;
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

String managerRoleLabel(ManagerRole role) {
  switch (role) {
    case ManagerRole.manager:
      return 'Manager';
    case ManagerRole.owner:
      return 'Owner';
  }
}

String managerStatusLabel(ManagerProfileStatus status) {
  switch (status) {
    case ManagerProfileStatus.active:
      return 'Active';
    case ManagerProfileStatus.inactive:
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

String shiftStatusLabel(ManagerShiftStatus status) {
  switch (status) {
    case ManagerShiftStatus.open:
      return 'Open';
    case ManagerShiftStatus.pendingReconciliation:
      return 'Pending tally';
    case ManagerShiftStatus.closed:
      return 'Closed';
    case ManagerShiftStatus.forceClosed:
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
  double purchaseTotal = 0,
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
    switch (row.payment) {
      case PaymentMethod.cash:
        cash += row.amountPkr;
      case PaymentMethod.udhaar:
        udhaar += row.amountPkr;
      case PaymentMethod.bankAccount:
      case PaymentMethod.easyPaisa:
        account += row.amountPkr;
    }
    liters += row.volumeLiters;
    if (firstToken == null || row.tokenNo < firstToken) {
      firstToken = row.tokenNo;
    }
    if (lastToken == null || row.tokenNo > lastToken) {
      lastToken = row.tokenNo;
    }
  }
  return ShiftWindowMetrics(
    sales: sorted.reversed.toList(),
    fuelCashSales: cash,
    udhaarSales: udhaar,
    accountSales: account,
    udhaarRecoveryTotal: udhaarRecoveryTotal,
    totalLiters: liters,
    purchaseTotal: purchaseTotal,
    firstToken: firstToken,
    lastToken: lastToken,
  );
}

List<HelperSaleRecord> salesInShiftWindow(
  List<HelperSaleRecord> sales,
  ManagerShiftRecord shift,
) {
  return sales.where((HelperSaleRecord row) {
    return isInShiftWindow(row.timestamp, shift.startTime, end: shift.endTime);
  }).toList();
}

/// Itemized rows for an outgoing manager: tagged `shiftId`, else manager + window.
List<HelperSaleRecord> salesForOutgoingManager(
  List<HelperSaleRecord> sales,
  ManagerShiftRecord shift,
) {
  return sales.where((HelperSaleRecord row) {
    if (row.shiftId.isNotEmpty) {
      return row.shiftId == shift.shiftId;
    }
    if (row.managerId.isNotEmpty) {
      return row.managerId == shift.managerId &&
          isInShiftWindow(row.timestamp, shift.startTime, end: shift.endTime);
    }
    final bool matchesCashier = row.cashierName.isEmpty
        ? true
        : row.cashierName == shift.managerName;
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

/// Current helper id per dispenser bay. Null means the bay is unassigned.
Map<int, String?> unitHelperAssignmentsOf(List<HelperProfile> helpers) {
  return <int, String?>{
    for (final int unitId in dispenserUnitIds)
      unitId: helperOnUnit(helpers, unitId)?.id,
  };
}
