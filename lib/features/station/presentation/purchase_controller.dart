import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../providers/settings_provider.dart';
import '../../../services/database_helper.dart';
import '../data/purchase_repository.dart';
import '../domain/money_format.dart';

/// Reactive purchase session backed by SQLite `purchases` + `diesel_stock`.
class PurchaseController extends ChangeNotifier {
  PurchaseController(this._repository, {this.onCommitted}) {
    unawaited(reload());
  }

  final PurchaseRepository _repository;
  final VoidCallback? onCommitted;

  List<PurchaseRecord> _purchases = const <PurchaseRecord>[];
  double _stockQuantity = 0;
  double _averageRate = 0;
  double _stockAmount = 0;
  int _nextInvoice = 1000;
  bool _loading = true;

  List<PurchaseRecord> get purchases => _purchases;

  List<PurchaseRecord> get lastTenPurchases {
    if (_purchases.length <= 10) {
      return _purchases;
    }
    return _purchases.take(10).toList();
  }

  int get nextInvoiceNo => _nextInvoice;

  bool get loading => _loading;

  /// Current tank liters from `diesel_stock.stock_quantity` (13-place storage).
  double get globalStockQuantity => _stockQuantity;

  double get currentDipLiters => _stockQuantity;

  /// Running WAC stored on `diesel_stock.Average_rate` (13-place storage).
  double get weightedAverageRate => _averageRate;

  /// PKR value stored on `diesel_stock.Stock_amount` (rounded quantity × WAC).
  double get overallStockPkr => _stockAmount;

  double get previousTotalCost => overallStockPkr;

  double get previousTotalLiters => currentDipLiters;

  Future<void> reload() async {
    try {
      final List<PurchaseRecord> rows = await _repository.list();
      final ({double quantity, double averageRate, double amount}) stock =
          await _repository.stock();
      final int nextInv = await _repository.nextInvoiceNo();
      _purchases = rows;
      _stockQuantity = stock.quantity;
      _averageRate = stock.averageRate;
      _stockAmount = stock.amount;
      _nextInvoice = nextInv;
    } catch (error, stack) {
      debugPrint('PurchaseController.reload failed: $error\n$stack');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> recordPurchase({
    required double purchasedLiters,
    required double purchaseRate,
    required double totalAmountPkr,
    required String managerId,
    required String managerName,
    required String managerPin,
    String tafseel = '',
  }) async {
    await _repository.commitPurchase(
      invNo: formatInvoiceNo(_nextInvoice),
      timestamp: DateTime.now(),
      quantity: purchasedLiters,
      rate: purchaseRate,
      amount: totalAmountPkr,
      tafseel: tafseel,
      managerId: managerId,
      managerName: managerName,
      managerPin: managerPin,
    );
    await reload();
    unawaited(
      DatabaseHelper.instance.insertAuditLog(
        actionType: AuditActionType.stockAdjust,
        details:
            'Purchase $tafseel qty=$purchasedLiters rate=$purchaseRate '
            'amount=$totalAmountPkr',
        managerId: managerId,
        elevatedByOwner: true,
      ),
    );
    onCommitted?.call();
  }

  Future<void> updatePurchase({
    required String invNo,
    required double purchasedLiters,
    required double purchaseRate,
    required double totalAmountPkr,
    String tafseel = '',
    String managerId = '',
  }) async {
    await _repository.updatePurchase(
      invNo: invNo,
      quantity: purchasedLiters,
      rate: purchaseRate,
      amount: totalAmountPkr,
      tafseel: tafseel,
    );
    await reload();
    unawaited(
      DatabaseHelper.instance.insertAuditLog(
        actionType: AuditActionType.stockAdjust,
        details:
            'Edit $invNo qty=$purchasedLiters rate=$purchaseRate '
            'amount=$totalAmountPkr',
        managerId: managerId,
        elevatedByOwner: true,
      ),
    );
    onCommitted?.call();
  }
}
