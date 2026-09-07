import 'package:flutter/foundation.dart';

import '../../../services/database_helper.dart';
import '../../shift/domain/shift_models.dart';
import '../domain/dispenser_models.dart';
import 'transaction_store.dart';

/// Maps POS [SaleTransaction] rows onto `sales_transactions`.
class SalesTransactionRepository {
  SalesTransactionRepository({DatabaseHelper? db})
    : _db = db ?? DatabaseHelper.instance;

  static const String fallbackManagerId = 'mgr-walkin';

  final DatabaseHelper _db;

  Future<void> insertCommittedSale({
    required SaleTransaction txn,
    required String managerId,
    required String managerName,
    required String managerPin,
    String? helperId,
    String? helperName,
    String? creditCustomerId,
    String? creditShiftId,
  }) async {
    final String resolvedHelperId = helperId?.trim() ?? '';
    try {
      await _db.commitSaleTransaction(
        sale: <String, Object?>{
          'TOKEN': formatLedgerToken(txn.tokenNo),
          'DATE_TIME': txn.timestamp.toIso8601String(),
          'UNIT_NO': txn.unitId,
          'AMOUNT': txn.amountPkr,
          'LITERS': txn.volumeLiters,
          'RATE': txn.rate,
          'OPENING_READING': txn.openingMeter,
          'CLOSING_READING': txn.closingMeter,
          'PAYMENT_METHOD': txn.payment.label,
          'CUSTOMER_NAME': txn.customerName.trim().isEmpty
              ? null
              : txn.customerName.trim(),
          'VEHICLE_NO': txn.vehicleNo.trim().isEmpty
              ? null
              : txn.vehicleNo.trim(),
          'HELPER': resolvedHelperId.isEmpty ? null : resolvedHelperId,
          'Manager': managerId,
          'ACTIONS': null,
        },
        managerId: managerId,
        managerName: managerName,
        managerPin: managerPin,
        helperId: resolvedHelperId.isEmpty ? null : resolvedHelperId,
        helperName: helperName,
        volumeLiters: txn.volumeLiters,
        creditCustomerId: creditCustomerId,
        creditCustomerName: txn.customerName,
        creditShiftId: creditShiftId,
        creditDescription: txn.fuelType,
        creditVehicle: txn.vehicleNo,
      );
    } catch (error, stack) {
      debugPrint('SalesTransactionRepository.insert failed: $error\n$stack');
      rethrow;
    }
  }

  Future<List<SaleTransaction>> recent({int limit = 20}) async {
    final List<Map<String, Object?>> rows = await _db.queryRecentSales(
      limit: limit,
    );
    return rows.map(_fromRow).toList();
  }

  Future<List<SaleTransaction>> all() async {
    final List<Map<String, Object?>> rows = await _db.queryAllSales();
    return rows.map(_fromRow).toList();
  }

  Future<SaleTransaction?> byToken(int tokenNo) async {
    final Map<String, Object?>? row = await _db.querySaleByToken(
      formatLedgerToken(tokenNo),
    );
    if (row == null) {
      return null;
    }
    return _fromRow(row);
  }

  Future<SaleTransaction?> settleUdhaar({
    required int tokenNo,
    required double settledAmount,
    required String description,
  }) async {
    final SaleTransaction? current = await byToken(tokenNo);
    if (current == null) {
      return null;
    }
    if (current.payment != PaymentMethod.udhaar || current.udhaarSettled) {
      return null;
    }
    final DateTime settledAt = DateTime.now();
    await _db.markSaleSettled(
      token: formatLedgerToken(tokenNo),
      actions: encodeSettledActions(
        amount: settledAmount,
        at: settledAt,
        notes: description,
      ),
    );
    return current.copyWith(
      notes: _mergeNotes(current.notes, description),
      udhaarSettled: true,
      settledAmount: settledAmount,
      settledAt: settledAt,
    );
  }

  static SalesLedgerSnapshot querySnapshot(
    List<SaleTransaction> source, {
    int? unitId,
    String search = '',
    DateTime? from,
    DateTime? to,
  }) {
    final List<SaleTransaction> matched = source.where((SaleTransaction row) {
      if (unitId != null && row.unitId != unitId) {
        return false;
      }
      if (!_inRange(row.timestamp, from, to)) {
        return false;
      }
      return _saleMatchesSearch(row, search);
    }).toList();

    double totalAmount = 0;
    double totalVolume = 0;
    double udhaarAmount = 0;
    int udhaarCount = 0;
    for (final SaleTransaction row in matched) {
      totalAmount += row.amountPkr;
      totalVolume += row.volumeLiters;
      if (row.payment == PaymentMethod.udhaar) {
        udhaarAmount += row.amountPkr;
        udhaarCount += 1;
      }
    }

    return SalesLedgerSnapshot(
      rows: matched,
      totalCount: matched.length,
      totalAmountPkr: totalAmount,
      totalVolumeLiters: totalVolume,
      udhaarAmountPkr: udhaarAmount,
      udhaarCount: udhaarCount,
    );
  }

  Future<Map<int, int>> sequencesFromHistory() async {
    final Map<int, int> nextSequence = <int, int>{
      for (final int unitId in dispenserUnitIds) unitId: 1,
    };
    final List<SaleTransaction> rows = await all();
    for (final SaleTransaction txn in rows) {
      final int issued = sequenceFromToken(txn.tokenNo, txn.unitId);
      final int current = nextSequence[txn.unitId] ?? 1;
      if (issued + 1 > current) {
        nextSequence[txn.unitId] = issued + 1;
      }
    }
    return nextSequence;
  }

  Future<void> updateMetadata({
    required int tokenNo,
    required String customerName,
    required String vehicleNo,
    required PaymentMethod payment,
  }) async {
    final String resolvedCustomer = customerName.trim();
    final String resolvedVehicle = vehicleNo.trim();
    await _db.updateSalesTransaction(
      token: formatLedgerToken(tokenNo),
      customerName: resolvedCustomer.isEmpty ? null : resolvedCustomer,
      vehicleNo: resolvedVehicle.isEmpty ? null : resolvedVehicle,
      paymentMethod: payment.label,
    );
  }

  static String managerIdFor(ManagerShiftRecord? shift) {
    final String? id = shift?.managerId.trim();
    if (id == null || id.isEmpty) {
      return fallbackManagerId;
    }
    return id;
  }

  static String managerNameFor({
    required ManagerShiftRecord? shift,
    required String fallbackName,
  }) {
    final String fromShift = shift?.managerName.trim() ?? '';
    if (fromShift.isNotEmpty) {
      return fromShift;
    }
    final String trimmed = fallbackName.trim();
    return trimmed.isEmpty ? 'Cashier' : trimmed;
  }

  static String managerPinFor({
    required List<ManagerProfile> managers,
    required String managerId,
  }) {
    for (final ManagerProfile profile in managers) {
      if (profile.id == managerId) {
        return profile.pin;
      }
    }
    return kDefaultManagerPin;
  }

  static SaleTransaction _fromRow(Map<String, Object?> row) {
    final double closing = _asDouble(row['CLOSING_READING']);
    final String helperName = (row['helper_name'] as String?)?.trim() ?? '';
    final String managerName = (row['manager_name'] as String?)?.trim() ?? '';
    final _SettledActions settled = _SettledActions.parse(
      row['ACTIONS'] as String?,
    );
    return SaleTransaction(
      tokenNo: parseLedgerToken('${row['TOKEN'] ?? ''}'),
      unitId: _asInt(row['UNIT_NO']),
      fuelType: kDieselFuelType,
      amountPkr: _asDouble(row['AMOUNT']),
      volumeLiters: _asDouble(row['LITERS']),
      rate: _asDouble(row['RATE']),
      meterCount: closing.round(),
      timestamp:
          DateTime.tryParse('${row['DATE_TIME'] ?? ''}') ?? DateTime.now(),
      openingMeter: _asDouble(row['OPENING_READING']),
      closingMeter: closing,
      customerName: (row['CUSTOMER_NAME'] as String?)?.trim() ?? 'Walk-in',
      vehicleNo: (row['VEHICLE_NO'] as String?)?.trim() ?? '',
      payment: paymentMethodFromStorage(row['PAYMENT_METHOD'] as String?),
      cashierName: managerName.isEmpty ? 'Cashier' : managerName,
      helperName: helperName,
      notes: settled.notes,
      udhaarSettled: settled.settled,
      settledAmount: settled.amount,
      settledAt: settled.at,
    );
  }

  static String encodeSettledActions({
    required double amount,
    required DateTime at,
    required String notes,
  }) {
    return 'SETTLED|$amount|${at.toIso8601String()}|${notes.trim()}';
  }

  static String _mergeNotes(String existing, String incoming) {
    final String left = existing.trim();
    final String right = incoming.trim();
    if (left.isEmpty) {
      return right;
    }
    if (right.isEmpty) {
      return left;
    }
    return '$left · $right';
  }

  static bool _inRange(DateTime timestamp, DateTime? from, DateTime? to) {
    if (from != null) {
      final DateTime start = DateTime(from.year, from.month, from.day);
      if (timestamp.isBefore(start)) {
        return false;
      }
    }
    if (to != null) {
      final DateTime end = DateTime(to.year, to.month, to.day, 23, 59, 59, 999);
      if (timestamp.isAfter(end)) {
        return false;
      }
    }
    return true;
  }

  static bool _saleMatchesSearch(SaleTransaction row, String raw) {
    final String query = raw.trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }
    final String tokenLabel = formatLedgerToken(row.tokenNo).toLowerCase();
    final String tokenDigits = formatTokenNo(row.tokenNo);
    if (tokenLabel.contains(query) ||
        tokenDigits.contains(query) ||
        row.tokenNo.toString().contains(query)) {
      return true;
    }
    if (row.customerName.toLowerCase().contains(query)) {
      return true;
    }
    if (row.vehicleNo.toLowerCase().contains(query)) {
      return true;
    }
    return false;
  }

  static double _asDouble(Object? value) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    return 0.0;
  }

  static int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    return 0;
  }
}

class _SettledActions {
  const _SettledActions({
    required this.settled,
    required this.amount,
    required this.notes,
    this.at,
  });

  final bool settled;
  final double amount;
  final String notes;
  final DateTime? at;

  static _SettledActions parse(String? raw) {
    final String value = raw?.trim() ?? '';
    if (!value.startsWith('SETTLED|')) {
      return const _SettledActions(settled: false, amount: 0, notes: '');
    }
    final List<String> parts = value.split('|');
    final double amount = parts.length > 1
        ? (double.tryParse(parts[1]) ?? 0)
        : 0;
    final DateTime? at = parts.length > 2 ? DateTime.tryParse(parts[2]) : null;
    final String notes = parts.length > 3 ? parts.sublist(3).join('|') : '';
    return _SettledActions(
      settled: true,
      amount: amount,
      notes: notes,
      at: at,
    );
  }
}
