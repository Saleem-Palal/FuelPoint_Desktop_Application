import 'package:flutter/foundation.dart';

import '../../../services/database_helper.dart';
import '../../shift/domain/shift_models.dart';
import '../domain/dispenser_models.dart';
import '../domain/fuel_precision.dart';
import '../domain/shift_ledger_models.dart';
import 'sales_transaction_repository.dart';

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
    final String managerName = (row['manager_name'] as String?)?.trim() ?? '';
    return ShiftLedgerSummary(
      shiftId: formatShiftId(pk),
      managerId: '${row['manager_id'] ?? ''}'.trim(),
      managerName: managerName.isEmpty ? 'Manager' : managerName,
      role: ManagerRole.manager,
      startTime:
          DateTime.tryParse('${row['start_timestamp'] ?? ''}') ??
          DateTime.now(),
      endTime: DateTime.tryParse('${row['end_timestamp'] ?? ''}'),
      status: shiftStatusFromStorage('${row['shift_status'] ?? ''}'),
      totalTransactions: _asInt(row['total_transactions']),
      totalShiftPkr: _asDouble(row['total_shift_pkr']),
      totalShiftLiters: _asDouble(row['total_shift_liters']),
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
}
