import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/purchase_repository.dart';
import '../data/sales_transaction_repository.dart';
import '../data/transaction_store.dart';
import 'purchase_providers.dart';
import 'station_providers.dart';

enum LedgerTab { sales, purchases }

@immutable
class LedgerQuery {
  const LedgerQuery({
    this.tab = LedgerTab.sales,
    this.unitId,
    this.search = '',
    this.salesFrom,
    this.salesTo,
    this.purchaseFrom,
    this.purchaseTo,
  });

  final LedgerTab tab;
  final int? unitId;
  final String search;
  final DateTime? salesFrom;
  final DateTime? salesTo;
  final DateTime? purchaseFrom;
  final DateTime? purchaseTo;

  DateTimeRange? get salesRange => _range(salesFrom, salesTo);

  DateTimeRange? get purchaseRange => _range(purchaseFrom, purchaseTo);

  static DateTimeRange? _range(DateTime? from, DateTime? to) {
    if (from == null || to == null) {
      return null;
    }
    return DateTimeRange(start: from, end: to);
  }

  LedgerQuery copyWith({
    LedgerTab? tab,
    int? unitId,
    bool clearUnit = false,
    String? search,
    DateTime? salesFrom,
    DateTime? salesTo,
    bool clearSalesRange = false,
    DateTime? purchaseFrom,
    DateTime? purchaseTo,
    bool clearPurchaseRange = false,
  }) {
    return LedgerQuery(
      tab: tab ?? this.tab,
      unitId: clearUnit ? null : (unitId ?? this.unitId),
      search: search ?? this.search,
      salesFrom: clearSalesRange ? null : (salesFrom ?? this.salesFrom),
      salesTo: clearSalesRange ? null : (salesTo ?? this.salesTo),
      purchaseFrom: clearPurchaseRange
          ? null
          : (purchaseFrom ?? this.purchaseFrom),
      purchaseTo: clearPurchaseRange ? null : (purchaseTo ?? this.purchaseTo),
    );
  }
}

class LedgerQueryNotifier extends Notifier<LedgerQuery> {
  @override
  LedgerQuery build() => const LedgerQuery();

  void setTab(LedgerTab tab) {
    if (state.tab == tab) {
      return;
    }
    state = state.copyWith(tab: tab);
  }

  void setSalesRange(DateTimeRange? range) {
    state = state.copyWith(
      salesFrom: range?.start,
      salesTo: range?.end,
      clearSalesRange: range == null,
    );
  }

  void setPurchaseRange(DateTimeRange? range) {
    state = state.copyWith(
      purchaseFrom: range?.start,
      purchaseTo: range?.end,
      clearPurchaseRange: range == null,
    );
  }

  void setUnit(int? unitId) {
    state = state.copyWith(unitId: unitId, clearUnit: unitId == null);
  }

  void setSearch(String search) {
    state = state.copyWith(search: search);
  }
}

final ledgerQueryProvider = NotifierProvider<LedgerQueryNotifier, LedgerQuery>(
  LedgerQueryNotifier.new,
);

final salesLedgerSliceProvider = Provider<SalesLedgerSnapshot>((Ref ref) {
  ref.watch(historyRevisionProvider);
  final LedgerQuery query = ref.watch(ledgerQueryProvider);
  return SalesTransactionRepository.querySnapshot(
    ref.watch(committedSalesProvider),
    unitId: query.unitId,
    search: query.search,
    from: query.salesFrom,
    to: query.salesTo,
  );
});

final purchaseLedgerSliceProvider = Provider<PurchaseLedgerSnapshot>((Ref ref) {
  ref.watch(historyRevisionProvider);
  final LedgerQuery query = ref.watch(ledgerQueryProvider);
  final List<PurchaseRecord> rows = ref
      .watch(purchaseControllerProvider)
      .purchases;
  return PurchaseRepository.snapshot(
    rows,
    from: query.purchaseFrom,
    to: query.purchaseTo,
  );
});
