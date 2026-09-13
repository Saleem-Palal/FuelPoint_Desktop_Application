import 'package:flutter/foundation.dart';

import '../../shift/domain/shift_lifecycle.dart';
import '../../shift/domain/shift_models.dart';
import 'dispenser_models.dart';

/// Aggregated `shifts` ⨯ `sales_transactions` row for the Shift-Wise Ledger.
@immutable
class ShiftLedgerSummary {
  const ShiftLedgerSummary({
    required this.shiftId,
    required this.managerId,
    required this.managerName,
    required this.role,
    required this.startTime,
    required this.status,
    required this.totalTransactions,
    required this.totalShiftPkr,
    required this.totalShiftLiters,
    this.endTime,
  });

  final String shiftId;
  final String managerId;
  final String managerName;
  final ManagerRole role;
  final DateTime startTime;
  final DateTime? endTime;
  final ManagerShiftStatus status;
  final int totalTransactions;
  final double totalShiftPkr;
  final double totalShiftLiters;

  bool get isLive => status == ManagerShiftStatus.open;

  String get managerBadgeLabel {
    final String name = managerName.trim().isEmpty
        ? 'Manager'
        : managerName.trim();
    return '$name (${managerRoleLabel(role).toUpperCase()})';
  }

  ShiftLedgerSummary copyWith({
    String? managerName,
    ManagerRole? role,
    DateTime? endTime,
    ManagerShiftStatus? status,
    int? totalTransactions,
    double? totalShiftPkr,
    double? totalShiftLiters,
  }) {
    return ShiftLedgerSummary(
      shiftId: shiftId,
      managerId: managerId,
      managerName: managerName ?? this.managerName,
      role: role ?? this.role,
      startTime: startTime,
      endTime: endTime ?? this.endTime,
      status: status ?? this.status,
      totalTransactions: totalTransactions ?? this.totalTransactions,
      totalShiftPkr: totalShiftPkr ?? this.totalShiftPkr,
      totalShiftLiters: totalShiftLiters ?? this.totalShiftLiters,
    );
  }

  /// Replaces SQLite aggregates with live committed / workspace sales.
  ShiftLedgerSummary overlayWithSales(
    List<SaleTransaction> sales, {
    List<HelperSaleRecord> workspaceSales = const <HelperSaleRecord>[],
  }) {
    if (!isLive) {
      return this;
    }
    final List<SaleTransaction> rows = liveSalesForShift(
      summary: this,
      committed: sales,
      workspaceSales: workspaceSales,
    );
    if (rows.isEmpty && totalTransactions > 0) {
      return this;
    }
    double pkr = 0;
    double liters = 0;
    for (final SaleTransaction row in rows) {
      pkr += row.amountPkr;
      liters += row.volumeLiters;
    }
    return copyWith(
      totalTransactions: rows.length,
      totalShiftPkr: pkr,
      totalShiftLiters: liters,
    );
  }
}

bool saleBelongsToShift(SaleTransaction row, ShiftLedgerSummary summary) {
  if (row.shiftId == summary.shiftId) {
    return true;
  }
  if (row.shiftId.isNotEmpty) {
    return false;
  }
  return isInShiftWindow(
    row.timestamp,
    summary.startTime,
    end: summary.endTime,
  );
}

bool helperSaleBelongsToShift(
  HelperSaleRecord row,
  ShiftLedgerSummary summary,
) {
  if (row.shiftId == summary.shiftId) {
    return true;
  }
  if (row.shiftId.isNotEmpty) {
    return false;
  }
  if (row.managerId.isNotEmpty && row.managerId != summary.managerId) {
    return false;
  }
  return isInShiftWindow(
    row.timestamp,
    summary.startTime,
    end: summary.endTime,
  );
}

SaleTransaction saleFromHelperSale(HelperSaleRecord row) {
  return SaleTransaction(
    tokenNo: row.tokenNo,
    unitId: row.unitId,
    fuelType: row.fuelType,
    amountPkr: row.amountPkr,
    volumeLiters: row.volumeLiters,
    rate: row.rate,
    meterCount: 0,
    timestamp: row.timestamp,
    payment: row.payment,
    cashierName: row.cashierName,
    helperName: row.helperName,
    shiftId: row.shiftId,
  );
}

/// Merges SQLite-backed sales with in-memory workspace sales for one shift.
List<SaleTransaction> liveSalesForShift({
  required ShiftLedgerSummary summary,
  required List<SaleTransaction> committed,
  List<HelperSaleRecord> workspaceSales = const <HelperSaleRecord>[],
}) {
  final Map<int, SaleTransaction> byToken = <int, SaleTransaction>{};
  for (final SaleTransaction row in committed) {
    if (saleBelongsToShift(row, summary)) {
      byToken[row.tokenNo] = row;
    }
  }
  for (final HelperSaleRecord row in workspaceSales) {
    if (!helperSaleBelongsToShift(row, summary)) {
      continue;
    }
    byToken.putIfAbsent(row.tokenNo, () => saleFromHelperSale(row));
  }
  final List<SaleTransaction> rows = byToken.values.toList();
  rows.sort(
    (SaleTransaction a, SaleTransaction b) =>
        b.timestamp.compareTo(a.timestamp),
  );
  return rows;
}

List<SaleTransaction> salesForShift(
  List<SaleTransaction> sales,
  ShiftLedgerSummary summary,
) {
  return liveSalesForShift(summary: summary, committed: sales);
}

List<ShiftLedgerSummary> overlayLiveShiftLedger(
  List<ShiftLedgerSummary> summaries,
  List<SaleTransaction> sales, {
  List<HelperSaleRecord> workspaceSales = const <HelperSaleRecord>[],
}) {
  return summaries
      .map(
        (ShiftLedgerSummary row) =>
            row.overlayWithSales(sales, workspaceSales: workspaceSales),
      )
      .toList();
}

bool shiftOverlapsRange(
  ShiftLedgerSummary shift, {
  DateTime? from,
  DateTime? to,
}) {
  if (from == null && to == null) {
    return true;
  }
  final DateTime? rangeStart = from == null
      ? null
      : DateTime(from.year, from.month, from.day);
  final DateTime? rangeEnd = to == null
      ? null
      : DateTime(to.year, to.month, to.day, 23, 59, 59, 999);
  final DateTime shiftEnd = shift.endTime ?? DateTime.now();
  if (rangeStart != null && shiftEnd.isBefore(rangeStart)) {
    return false;
  }
  if (rangeEnd != null && shift.startTime.isAfter(rangeEnd)) {
    return false;
  }
  return true;
}

List<ShiftLedgerSummary> filterShiftsByRange(
  List<ShiftLedgerSummary> rows, {
  DateTime? from,
  DateTime? to,
}) {
  if (from == null && to == null) {
    return rows;
  }
  return rows
      .where(
        (ShiftLedgerSummary row) => shiftOverlapsRange(row, from: from, to: to),
      )
      .toList();
}

int resolveShiftIndex(List<ShiftLedgerSummary> shifts, String? selectedId) {
  if (shifts.isEmpty) {
    return -1;
  }
  if (selectedId == null || selectedId.isEmpty) {
    return 0;
  }
  final int index = shifts.indexWhere(
    (ShiftLedgerSummary row) => row.shiftId == selectedId,
  );
  return index >= 0 ? index : 0;
}

ShiftLedgerSummary? resolveSelectedShift(
  List<ShiftLedgerSummary> shifts,
  String? selectedId,
) {
  final int index = resolveShiftIndex(shifts, selectedId);
  if (index < 0) {
    return null;
  }
  return shifts[index];
}

String steppedShiftId(
  List<ShiftLedgerSummary> shifts,
  String? selectedId,
  int delta,
) {
  if (shifts.isEmpty) {
    return selectedId ?? '';
  }
  final int current = resolveShiftIndex(shifts, selectedId);
  final int next = (current + delta).clamp(0, shifts.length - 1);
  return shifts[next].shiftId;
}

List<ShiftLedgerSummary> attachManagerRoles(
  List<ShiftLedgerSummary> summaries,
  List<ManagerProfile> managers,
) {
  return summaries.map((ShiftLedgerSummary row) {
    for (final ManagerProfile manager in managers) {
      if (manager.id == row.managerId) {
        return row.copyWith(role: manager.role, managerName: manager.name);
      }
    }
    return row;
  }).toList();
}

ManagerShiftStatus shiftStatusFromStorage(String raw) {
  return ShiftStatusStorage.fromStorage(raw);
}
