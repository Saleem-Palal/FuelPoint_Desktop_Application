import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/transaction_store.dart';
import '../domain/money_format.dart';
import 'station_providers.dart';

enum LedgerTab { sales, purchases }

@immutable
class LedgerQuery {
  const LedgerQuery({
    this.tab = LedgerTab.sales,
    this.unitId,
    this.search = '',
    required this.month,
  });

  final LedgerTab tab;
  final int? unitId;
  final String search;
  final DateTime month;

  LedgerQuery copyWith({
    LedgerTab? tab,
    int? unitId,
    bool clearUnit = false,
    String? search,
    DateTime? month,
  }) {
    return LedgerQuery(
      tab: tab ?? this.tab,
      unitId: clearUnit ? null : (unitId ?? this.unitId),
      search: search ?? this.search,
      month: month ?? this.month,
    );
  }
}

@immutable
class LedgerMonthNav {
  const LedgerMonthNav({
    required this.month,
    required this.canGoPrevious,
    required this.canGoNext,
  });

  final DateTime month;
  final bool canGoPrevious;
  final bool canGoNext;
}

class LedgerQueryNotifier extends Notifier<LedgerQuery> {
  @override
  LedgerQuery build() {
    final DateTime initial = _pickMonth(
      startOfMonth(DateTime.now()),
      ref.read(transactionStoreProvider).availableSalesMonths(),
    );
    return LedgerQuery(month: initial);
  }

  List<DateTime> _monthsFor(LedgerTab tab) {
    final TransactionStore store = ref.read(transactionStoreProvider);
    if (tab == LedgerTab.sales) {
      return store.availableSalesMonths();
    }
    return store.availablePurchaseMonths();
  }

  void setTab(LedgerTab tab) {
    if (state.tab == tab) {
      return;
    }
    state = state.copyWith(
      tab: tab,
      month: _pickMonth(state.month, _monthsFor(tab)),
    );
  }

  void setUnit(int? unitId) {
    state = state.copyWith(unitId: unitId, clearUnit: unitId == null);
  }

  void setSearch(String search) {
    state = state.copyWith(search: search);
  }

  void stepMonth(int delta) {
    final List<DateTime> months = _monthsFor(state.tab);
    if (months.isEmpty) {
      return;
    }
    final int index = _indexOfMonth(months, state.month);
    if (index < 0) {
      state = state.copyWith(month: _pickMonth(state.month, months));
      return;
    }
    final int next = index + delta;
    if (next < 0 || next >= months.length) {
      return;
    }
    state = state.copyWith(month: months[next]);
  }

  static int _indexOfMonth(List<DateTime> months, DateTime month) {
    return months.indexWhere((DateTime item) {
      return item.year == month.year && item.month == month.month;
    });
  }

  static DateTime _pickMonth(DateTime preferred, List<DateTime> months) {
    if (months.isEmpty) {
      return startOfMonth(preferred);
    }
    for (final DateTime month in months) {
      if (month.year == preferred.year && month.month == preferred.month) {
        return month;
      }
    }
    return months.last;
  }
}

final ledgerQueryProvider = NotifierProvider<LedgerQueryNotifier, LedgerQuery>(
  LedgerQueryNotifier.new,
);

final ledgerAvailableMonthsProvider = Provider<List<DateTime>>((Ref ref) {
  ref.watch(historyRevisionProvider);
  final LedgerTab tab = ref.watch(
    ledgerQueryProvider.select((LedgerQuery q) {
      return q.tab;
    }),
  );
  final TransactionStore store = ref.read(transactionStoreProvider);
  if (tab == LedgerTab.sales) {
    return store.availableSalesMonths();
  }
  return store.availablePurchaseMonths();
});

final ledgerMonthNavProvider = Provider<LedgerMonthNav>((Ref ref) {
  final DateTime month = ref.watch(
    ledgerQueryProvider.select((LedgerQuery q) => q.month),
  );
  final List<DateTime> months = ref.watch(ledgerAvailableMonthsProvider);
  final int index = months.indexWhere((DateTime item) {
    return item.year == month.year && item.month == month.month;
  });
  return LedgerMonthNav(
    month: month,
    canGoPrevious: index > 0,
    canGoNext: index >= 0 && index < months.length - 1,
  );
});

final salesLedgerSliceProvider = Provider<SalesLedgerSnapshot>((Ref ref) {
  ref.watch(historyRevisionProvider);
  final LedgerQuery query = ref.watch(ledgerQueryProvider);
  return ref
      .read(transactionStoreProvider)
      .querySales(
        unitId: query.unitId,
        search: query.search,
        month: query.month,
      );
});

final purchaseLedgerSliceProvider = Provider<PurchaseLedgerSnapshot>((Ref ref) {
  ref.watch(historyRevisionProvider);
  final LedgerQuery query = ref.watch(ledgerQueryProvider);
  return ref.read(transactionStoreProvider).queryPurchases(month: query.month);
});
