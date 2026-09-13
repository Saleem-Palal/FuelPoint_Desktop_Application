import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shift/domain/shift_models.dart';
import '../../shift/presentation/shift_providers.dart';
import '../data/purchase_repository.dart';
import '../data/sales_ledger_repository.dart';
import '../data/sales_transaction_repository.dart';
import '../data/transaction_store.dart';
import '../domain/dispenser_models.dart';
import '../domain/shift_ledger_models.dart';
import 'purchase_providers.dart';
import 'station_providers.dart';

enum LedgerTab { sales, purchases }

enum SalesLedgerMode { allTransactions, shiftWise }

@immutable
class LedgerQuery {
  const LedgerQuery({
    this.tab = LedgerTab.sales,
    this.salesMode = SalesLedgerMode.allTransactions,
    this.unitId,
    this.search = '',
    this.salesFrom,
    this.salesTo,
    this.purchaseFrom,
    this.purchaseTo,
    this.selectedShiftId,
  });

  final LedgerTab tab;
  final SalesLedgerMode salesMode;
  final int? unitId;
  final String search;
  final DateTime? salesFrom;
  final DateTime? salesTo;
  final DateTime? purchaseFrom;
  final DateTime? purchaseTo;
  final String? selectedShiftId;

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
    SalesLedgerMode? salesMode,
    int? unitId,
    bool clearUnit = false,
    String? search,
    DateTime? salesFrom,
    DateTime? salesTo,
    bool clearSalesRange = false,
    DateTime? purchaseFrom,
    DateTime? purchaseTo,
    bool clearPurchaseRange = false,
    String? selectedShiftId,
    bool clearSelectedShift = false,
  }) {
    return LedgerQuery(
      tab: tab ?? this.tab,
      salesMode: salesMode ?? this.salesMode,
      unitId: clearUnit ? null : (unitId ?? this.unitId),
      search: search ?? this.search,
      salesFrom: clearSalesRange ? null : (salesFrom ?? this.salesFrom),
      salesTo: clearSalesRange ? null : (salesTo ?? this.salesTo),
      purchaseFrom: clearPurchaseRange
          ? null
          : (purchaseFrom ?? this.purchaseFrom),
      purchaseTo: clearPurchaseRange ? null : (purchaseTo ?? this.purchaseTo),
      selectedShiftId: clearSelectedShift
          ? null
          : (selectedShiftId ?? this.selectedShiftId),
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

  void setSalesMode(SalesLedgerMode salesMode) {
    if (state.salesMode == salesMode) {
      return;
    }
    state = state.copyWith(salesMode: salesMode);
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

  void setSelectedShift(String? shiftId) {
    if (state.selectedShiftId == shiftId) {
      return;
    }
    state = state.copyWith(
      selectedShiftId: shiftId,
      clearSelectedShift: shiftId == null,
    );
  }

  void stepShift(int delta, List<ShiftLedgerSummary> shifts) {
    if (shifts.isEmpty || delta == 0) {
      return;
    }
    final String nextId = steppedShiftId(shifts, state.selectedShiftId, delta);
    if (nextId.isEmpty || nextId == state.selectedShiftId) {
      return;
    }
    state = state.copyWith(selectedShiftId: nextId);
  }
}

final ledgerQueryProvider = NotifierProvider<LedgerQueryNotifier, LedgerQuery>(
  LedgerQueryNotifier.new,
);

final salesLedgerSliceProvider = Provider<SalesLedgerSnapshot>((Ref ref) {
  ref.watch(historyRevisionProvider);
  final LedgerQuery query = ref.watch(ledgerQueryProvider);
  final List<SaleTransaction> committed = ref.watch(committedSalesProvider);
  List<SaleTransaction> source = committed;

  if (query.salesMode == SalesLedgerMode.shiftWise) {
    final ShiftLedgerSummary? shift = ref.watch(selectedShiftSummaryProvider);
    if (shift == null) {
      return SalesLedgerSnapshot.empty;
    }
    final List<HelperSaleRecord> workspaceSales = ref.watch(
      shiftWorkspaceProvider.select((ShiftWorkspaceState state) => state.sales),
    );
    source = liveSalesForShift(
      summary: shift,
      committed: committed,
      workspaceSales: workspaceSales,
    );
    if (source.isEmpty && shift.totalTransactions > 0) {
      final List<SaleTransaction>? remote = ref
          .watch(shiftTransactionsByIdProvider(shift.shiftId))
          .valueOrNull;
      if (remote != null && remote.isNotEmpty) {
        source = remote;
      }
    }
  }

  return SalesTransactionRepository.querySnapshot(
    source,
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

final salesLedgerRepositoryProvider = Provider<SalesLedgerRepository>((
  Ref ref,
) {
  return SalesLedgerRepository();
});

final shiftLedgerSummariesProvider = FutureProvider<List<ShiftLedgerSummary>>((
  Ref ref,
) async {
  ref.watch(historyRevisionProvider);
  return ref.read(salesLedgerRepositoryProvider).getShiftLedgerSummaries();
});

/// SQLite shift aggregates with live OPEN-shift totals from committed sales
/// and in-memory workspace sales (updated as soon as a sale is confirmed).
final shiftWiseLedgerProvider = Provider<AsyncValue<List<ShiftLedgerSummary>>>((
  Ref ref,
) {
  final AsyncValue<List<ShiftLedgerSummary>> remote = ref.watch(
    shiftLedgerSummariesProvider,
  );
  final List<SaleTransaction> sales = ref.watch(committedSalesProvider);
  final ShiftWorkspaceState workspace = ref.watch(shiftWorkspaceProvider);
  return remote.whenData((List<ShiftLedgerSummary> rows) {
    return overlayLiveShiftLedger(
      attachManagerRoles(rows, workspace.managers),
      sales,
      workspaceSales: workspace.sales,
    );
  });
});

final shiftWisePagerProvider = Provider<AsyncValue<List<ShiftLedgerSummary>>>((
  Ref ref,
) {
  final LedgerQuery query = ref.watch(ledgerQueryProvider);
  return ref.watch(shiftWiseLedgerProvider).whenData((
    List<ShiftLedgerSummary> rows,
  ) {
    return filterShiftsByRange(rows, from: query.salesFrom, to: query.salesTo);
  });
});

final selectedShiftSummaryProvider = Provider<ShiftLedgerSummary?>((Ref ref) {
  final LedgerQuery query = ref.watch(ledgerQueryProvider);
  final List<ShiftLedgerSummary>? rows = ref
      .watch(shiftWisePagerProvider)
      .valueOrNull;
  if (rows == null || rows.isEmpty) {
    return null;
  }
  return resolveSelectedShift(rows, query.selectedShiftId);
});

final shiftTransactionsByIdProvider = FutureProvider.autoDispose
    .family<List<SaleTransaction>, String>((Ref ref, String shiftId) async {
      ref.watch(historyRevisionProvider);
      return ref
          .read(salesLedgerRepositoryProvider)
          .getTransactionsByShiftId(shiftId);
    });
