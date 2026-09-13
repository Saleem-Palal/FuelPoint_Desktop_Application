import 'package:flutter/foundation.dart';

import '../../../services/database_helper.dart';
import '../../shift/domain/shift_models.dart';
import '../domain/dispenser_models.dart';
import '../domain/average_rate.dart';
import '../domain/fuel_precision.dart';
import '../domain/money_format.dart';
import 'sales_transaction_repository.dart';
import 'transaction_store.dart';

/// One row from SQLite `purchases`. Liters/rate keep 13-place storage.
class PurchaseRecord {
  const PurchaseRecord({
    required this.invNo,
    required this.dateTime,
    required this.quantity,
    required this.rate,
    required this.amount,
    this.tafseel = '',
    this.managerName = '',
  });

  final String invNo;
  final DateTime dateTime;
  final double quantity;
  final double rate;
  final double amount;
  final String tafseel;
  final String managerName;

  bool get isInitialDip => isInitialDipTafseel(tafseel);
}

/// Maps Purchase Screen / ledger onto `purchases` + `diesel_stock`.
class PurchaseRepository {
  PurchaseRepository({DatabaseHelper? db})
    : _db = db ?? DatabaseHelper.instance;

  final DatabaseHelper _db;

  Future<List<PurchaseRecord>> list() async {
    final List<Map<String, Object?>> rows = await _db.queryPurchases();
    return rows.map(_fromRow).toList();
  }

  Future<int> nextInvoiceNo() async {
    return _db.nextPurchaseInvoiceNo();
  }

  Future<({double quantity, double averageRate, double amount})> stock() async {
    return _db.getDieselStock();
  }

  Future<void> commitPurchase({
    required String invNo,
    required DateTime timestamp,
    required double quantity,
    required double rate,
    required double amount,
    required String tafseel,
    required String managerId,
    required String managerName,
    required String managerPin,
  }) async {
    try {
      await _db.commitPurchase(
        invNo: invNo,
        datetimeIso: timestamp.toIso8601String(),
        quantity: quantity,
        rate: rate,
        amount: amount,
        tafseel: tafseel,
        managerId: managerId,
        managerName: managerName,
        managerPin: managerPin,
      );
    } catch (error, stack) {
      debugPrint('PurchaseRepository.commitPurchase failed: $error\n$stack');
      rethrow;
    }
  }

  Future<void> updatePurchase({
    required String invNo,
    required double quantity,
    required double rate,
    required double amount,
    String tafseel = '',
  }) async {
    try {
      await _db.updatePurchase(
        invNo: invNo,
        quantity: quantity,
        rate: rate,
        amount: amount,
        tafseel: tafseel,
      );
    } catch (error, stack) {
      debugPrint('PurchaseRepository.updatePurchase failed: $error\n$stack');
      rethrow;
    }
  }

  static PurchaseLedgerSnapshot snapshot(
    List<PurchaseRecord> source, {
    DateTime? from,
    DateTime? to,
  }) {
    final List<PurchaseTransaction> matched = <PurchaseTransaction>[];
    double totalAmount = 0;
    double totalVolume = 0;
    double largestDelivery = 0;
    for (final PurchaseRecord row in source) {
      if (!_inRange(row.dateTime, from, to)) {
        continue;
      }
      matched.add(toLedgerRow(row));
      totalAmount += row.amount;
      totalVolume += row.quantity;
      if (row.quantity > largestDelivery) {
        largestDelivery = row.quantity;
      }
    }
    return PurchaseLedgerSnapshot(
      rows: matched,
      totalCount: matched.length,
      totalAmountPkr: totalAmount,
      totalVolumeLiters: totalVolume,
      largestDeliveryLiters: largestDelivery,
    );
  }

  static PurchaseTransaction toLedgerRow(PurchaseRecord row) {
    return PurchaseTransaction(
      refNo: parseInvoiceNo(row.invNo),
      timestamp: row.dateTime,
      supplierName: '',
      fuelType: kDieselFuelType,
      weightKg: 0,
      sharahRatio: 0,
      netLiters: row.quantity,
      ratePerLiter: row.rate,
      totalAmount: row.amount,
      tafseel: row.tafseel,
      user: row.managerName,
    );
  }

  static ({String id, String name, String pin}) managerCreds({
    required ManagerShiftRecord? activeShift,
    required List<ManagerProfile> managers,
  }) {
    final String id = SalesTransactionRepository.managerIdFor(activeShift);
    return (
      id: id,
      name: SalesTransactionRepository.managerNameFor(
        shift: activeShift,
        fallbackName: 'Cashier',
      ),
      pin: SalesTransactionRepository.managerPinFor(
        managers: managers,
        managerId: id,
      ),
    );
  }

  static PurchaseRecord _fromRow(Map<String, Object?> row) {
    return PurchaseRecord(
      invNo: '${row['INV_NO'] ?? ''}',
      dateTime: DateTime.tryParse('${row['DATETIME'] ?? ''}') ?? DateTime.now(),
      quantity: _asDouble(row['QUANTITY']),
      rate: _asDouble(row['RATE']),
      amount: _asDouble(row['AMOUNT']),
      tafseel: (row['TAFSEEL'] as String?)?.trim() ?? '',
      managerName: (row['manager_name'] as String?)?.trim() ?? '',
    );
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

  static double _asDouble(Object? value) {
    return storedNumberToDouble(value);
  }
}
