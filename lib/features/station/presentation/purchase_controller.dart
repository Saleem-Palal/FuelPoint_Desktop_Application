import 'dart:async';

import 'package:flutter/foundation.dart';

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
  double _stockLiters = 0;
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

  /// Current tank volume from `diesel_stock` (full precision).
  double get currentDipLiters => _stockLiters;

  /// Weighted average cost across all purchase lots (full precision).
  double get weightedAverageRate {
    double cost = 0;
    double liters = 0;
    for (final PurchaseRecord row in _purchases) {
      cost += row.amount;
      liters += row.quantity;
    }
    if (liters == 0) {
      return 0;
    }
    return cost / liters;
  }

  /// Stock value = dip × WAC (full precision).
  double get overallStockPkr => currentDipLiters * weightedAverageRate;

  double get previousTotalCost => overallStockPkr;

  double get previousTotalLiters => currentDipLiters;

  Future<void> reload() async {
    try {
      final List<PurchaseRecord> rows = await _repository.list();
      final double stock = await _repository.stockAmount();
      final int nextInv = await _repository.nextInvoiceNo();
      _purchases = rows;
      _stockLiters = stock;
      _nextInvoice = nextInv;
    } catch (error, stack) {
      debugPrint('PurchaseController.reload failed: $error\n$stack');
      rethrow;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> recordInitialDip({
    required double liters,
    required double ratePerLiter,
    required String managerId,
    required String managerName,
    required String managerPin,
    String tafseel = '',
  }) async {
    final double totalAmountPkr = liters * ratePerLiter;
    final String note = tafseel.trim();
    await _repository.commitPurchase(
      invNo: formatInvoiceNo(_nextInvoice),
      timestamp: DateTime.now(),
      quantity: liters,
      rate: ratePerLiter,
      amount: totalAmountPkr,
      tafseel: note.isEmpty || note.toUpperCase().startsWith('DIP')
          ? (note.isEmpty ? 'DIP' : note)
          : 'DIP · $note',
      managerId: managerId,
      managerName: managerName,
      managerPin: managerPin,
      replaceStock: true,
    );
    await reload();
    onCommitted?.call();
  }

  Future<void> recordPurchase({
    required double purchasedLiters,
    required double totalAmountPkr,
    required String managerId,
    required String managerName,
    required String managerPin,
    String tafseel = '',
  }) async {
    final double ratePerLiter = purchasedLiters == 0
        ? 0
        : totalAmountPkr / purchasedLiters;
    await _repository.commitPurchase(
      invNo: formatInvoiceNo(_nextInvoice),
      timestamp: DateTime.now(),
      quantity: purchasedLiters,
      rate: ratePerLiter,
      amount: totalAmountPkr,
      tafseel: tafseel,
      managerId: managerId,
      managerName: managerName,
      managerPin: managerPin,
    );
    await reload();
    onCommitted?.call();
  }
}
