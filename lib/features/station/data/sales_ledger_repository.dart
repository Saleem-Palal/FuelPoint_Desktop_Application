import 'package:flutter/foundation.dart';

import '../../../services/database_helper.dart';
import '../../shift/domain/shift_lifecycle.dart';
import '../../shift/domain/shift_models.dart';
import '../domain/dispenser_models.dart';
import '../domain/fuel_precision.dart';
import '../domain/rate_change_summary.dart';
import '../domain/sales_ledger_window.dart';
import '../domain/shift_ledger_models.dart';
import 'sales_transaction_repository.dart';
import 'transaction_store.dart';

/// Shift-grouped sales ledger: SQLite aggregates plus on-demand child rows.
class SalesLedgerRepository {
  SalesLedgerRepository({DatabaseHelper? db})
    : _db = db ?? DatabaseHelper.instance;

  final DatabaseHelper _db;

  Future<List<ShiftLedgerSummary>> getShiftLedgerSummaries() async {
    try {
      final List<Map<String, Object?>> rows = await _db
          .queryShiftLedgerSummaries();
      return rows.map(_summaryFromRow).toList();
    } catch (error, stack) {
      debugPrint(
        'SalesLedgerRepository.getShiftLedgerSummaries failed: $error\n$stack',
      );
      rethrow;
    }
  }

  Future<List<SaleTransaction>> getTransactionsByShiftId(String shiftId) async {
    final int? pk = parseShiftPk(shiftId);
    if (pk == null || pk <= 0) {
      return const <SaleTransaction>[];
    }
    try {
      final List<Map<String, Object?>> rows = await _db.querySalesByShiftId(pk);
      return rows.map(SalesTransactionRepository.fromRow).toList();
    } catch (error, stack) {
      debugPrint(
        'SalesLedgerRepository.getTransactionsByShiftId failed: $error\n$stack',
      );
      rethrow;
    }
  }

  static ShiftLedgerSummary _summaryFromRow(Map<String, Object?> row) {
    final int pk = _asInt(row['shift_id']);
    final String operatorName = (row['manager_name'] as String?)?.trim() ?? '';
    return ShiftLedgerSummary(
      shiftId: formatShiftId(pk),
      operatorId: '${row['manager_id'] ?? ''}'.trim(),
      operatorName: operatorName.isEmpty ? 'Operator' : operatorName,
      role: OperatorRole.operator,
      startTime:
          DateTime.tryParse('${row['start_timestamp'] ?? ''}') ??
          DateTime.now(),
      endTime: DateTime.tryParse('${row['end_timestamp'] ?? ''}'),
      status: shiftStatusFromStorage('${row['shift_status'] ?? ''}'),
      totalTransactions: _asInt(row['total_transactions']),
      totalShiftPkr: _asDouble(row['total_shift_pkr']),
      totalShiftLiters: _asDouble(row['total_shift_liters']),
      openingMeters: ShiftMeterSnapshot.decode(
        row['opening_meters'] as String?,
      ),
      closingMeters: ShiftMeterSnapshot.decode(
        row['closing_meters'] as String?,
      ),
    );
  }

  static double _asDouble(Object? value) {
    return storedNumberToDouble(value);
  }

  static int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    return int.tryParse('$value') ?? 0;
  }

  /// One 30-day block, or the picked range. Meter cards use every pump row
  /// in that block. [search] filters the visible ticket list only.
  Future<AllTransactionsPage> loadAllTransactionsPage({
    int? unitId,
    String search = '',
    DateTime? salesFrom,
    DateTime? salesTo,
    required int pageIndex,
    DateTime? now,
  }) async {
    try {
      final bool custom = salesFrom != null && salesTo != null;
      final DateTime? oldest = custom
          ? null
          : await _db.queryOldestSaleTimestamp(unitId: unitId, search: search);
      final int pageCount = custom
          ? 1
          : salesLedgerBlockCount(oldest, now: now);
      final int requested = pageIndex < 0 ? 0 : pageIndex;
      final int safePage = requested >= pageCount ? pageCount - 1 : requested;
      final SalesLedgerWindow window = salesLedgerWindowForPage(
        pageIndex: custom ? 0 : safePage,
        from: salesFrom,
        to: salesTo,
        now: now,
      );
      final ({Map<String, Object?> totals, List<Map<String, Object?>> rows})
      loaded = await _db.querySalesLedgerWindow(
        fromInclusive: window.from,
        toInclusive: window.to,
        unitId: unitId,
      );
      final List<SaleTransaction> all = loaded.rows
          .map(SalesTransactionRepository.fromRow)
          .toList();
      final SalesLedgerSnapshot tickets =
          SalesTransactionRepository.querySnapshot(all, search: search);
      final RateChangeSummary rates = rateChangeSummary(all);
      return AllTransactionsPage(
        snapshot: SalesLedgerSnapshot(
          rows: tickets.rows,
          meterRows: tickets.meterRows,
          totalCount: tickets.totalCount,
          totalAmountPkr: rates.amountPkr.toDouble(),
          totalVolumeLiters: rates.netLiters,
          udhaarAmountPkr: tickets.udhaarAmountPkr,
          udhaarCount: tickets.udhaarCount,
          totalAccountAmountPkr: tickets.totalAccountAmountPkr,
          windowPhysicalVolumeLiters: rates.dispensedLiters,
        ),
        pageIndex: custom ? 0 : safePage,
        pageCount: pageCount,
        windowRowCount: tickets.rows.length,
        window: window,
        rateChanges: rates,
      );
    } catch (error, stack) {
      debugPrint(
        'SalesLedgerRepository.loadAllTransactionsPage failed: $error\n$stack',
      );
      rethrow;
    }
  }
}

/// One All Transactions page plus the window the cards were summed over.
class AllTransactionsPage {
  const AllTransactionsPage({
    required this.snapshot,
    required this.pageIndex,
    required this.pageCount,
    required this.windowRowCount,
    required this.window,
    this.rateChanges = RateChangeSummary.empty,
  });

  final SalesLedgerSnapshot snapshot;
  final int pageIndex;
  final int pageCount;
  final int windowRowCount;
  final SalesLedgerWindow window;
  final RateChangeSummary rateChanges;
}

/// Shift-wise ticket list, with Total Sales Amount taken from the meter.
///
/// Amount is net volume times the rate on each constant-rate stretch.
/// Net volume is closing minus opening, minus test liters. Search does not
/// remove rows from that span.
SalesLedgerSnapshot shiftWiseLedgerSnapshot({
  required List<SaleTransaction> source,
  int? unitId,
  String search = '',
  DateTime? from,
  DateTime? to,
}) {
  final SalesLedgerSnapshot tickets = SalesTransactionRepository.querySnapshot(
    source,
    unitId: unitId,
    search: search,
    from: from,
    to: to,
  );
  final List<SaleTransaction> meterSource = <SaleTransaction>[
    for (final SaleTransaction row in source)
      if (unitId == null || row.unitId == unitId) row,
  ];
  final RateChangeSummary rates = rateChangeSummary(meterSource);
  return SalesLedgerSnapshot(
    rows: tickets.rows,
    meterRows: tickets.meterRows,
    totalCount: tickets.totalCount,
    totalAmountPkr: rates.amountPkr.toDouble(),
    totalVolumeLiters: tickets.totalVolumeLiters,
    udhaarAmountPkr: tickets.udhaarAmountPkr,
    udhaarCount: tickets.udhaarCount,
    totalAccountAmountPkr: tickets.totalAccountAmountPkr,
  );
}
