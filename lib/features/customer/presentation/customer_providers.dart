import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shift/presentation/shift_providers.dart';
import '../../station/domain/dispenser_models.dart';
import '../../station/presentation/station_providers.dart';
import '../domain/customer_models.dart';
import '../domain/customer_repository.dart';
import 'customer_store.dart';

export 'customer_store.dart';

@immutable
class CustomerWorkspaceQuery {
  const CustomerWorkspaceQuery({this.search = '', this.selectedId});

  final String search;
  final String? selectedId;

  CustomerWorkspaceQuery copyWith({
    String? search,
    String? selectedId,
    bool clearSelected = false,
  }) {
    return CustomerWorkspaceQuery(
      search: search ?? this.search,
      selectedId: clearSelected ? null : (selectedId ?? this.selectedId),
    );
  }
}

class CustomerWorkspaceNotifier extends Notifier<CustomerWorkspaceQuery> {
  @override
  CustomerWorkspaceQuery build() => const CustomerWorkspaceQuery();

  void setSearch(String value) {
    state = state.copyWith(search: value);
  }

  void select(String id) {
    state = state.copyWith(selectedId: id);
  }

  /// Reloads customer directory + unified udhaar ledger from SQLite.
  Future<void> reload() async {
    await reloadCustomerPersistence(ref);
  }

  Future<CustomerProfile> addCustomer({
    required String name,
    String phone = '',
  }) async {
    final CustomerProfile created = await ref
        .read(customerDirectoryRepositoryProvider)
        .add(name: name, phone: phone);
    await reloadCustomerPersistence(ref);
    state = state.copyWith(selectedId: created.id);
    return created;
  }

  Future<CustomerSettlement> settleBill({
    required CustomerProfile customer,
    required double amountPkr,
    required SettlementPaymentMode paymentMode,
    String notes = '',
    String cashierName = 'Cashier',
    String cashierId = '',
  }) async {
    final UnifiedUdhaarRepository ledger = ref.read(
      unifiedUdhaarRepositoryProvider,
    );
    final String shiftId =
        ref.read(shiftWorkspaceProvider).activeShift?.shiftId ??
        kUnknownShiftId;
    final UnifiedUdhaarRow row = await ledger.insertSettlement(
      customerId: customer.id,
      customerName: customer.name,
      amountPkr: amountPkr,
      paymentMode: paymentMode,
      shiftId: shiftId,
      notes: notes,
    );
    if (paymentMode == SettlementPaymentMode.cash) {
      ref.read(shiftWorkspaceProvider.notifier).addUdhaarRecovery(amountPkr);
    }
    await reloadCustomerPersistence(ref);
    return settlementFromLedgerRow(
      row,
      cashierName: cashierName,
      cashierId: cashierId,
    );
  }
}

final customerWorkspaceProvider =
    NotifierProvider<CustomerWorkspaceNotifier, CustomerWorkspaceQuery>(
      CustomerWorkspaceNotifier.new,
    );

final customerIdCacheProvider = Provider<Map<String, CustomerProfile>>((
  Ref ref,
) {
  ref.watch(customerRevisionProvider);
  final List<CustomerProfile> rows = ref.watch(customerDirectoryCacheProvider);
  return <String, CustomerProfile>{
    for (final CustomerProfile row in rows) row.id: row,
  };
});

CustomerAccount _accountFor({
  required CustomerProfile profile,
  required List<UnifiedUdhaarRow> rows,
}) {
  double salesTotal = 0;
  double paidTotal = 0;
  final List<CustomerLedgerLine> ledger = <CustomerLedgerLine>[];
  int settlementIndex = 0;
  for (final UnifiedUdhaarRow row in rows) {
    if (row.isSale) {
      salesTotal += row.amountPkr;
      final int tokenNo = row.tokenLabel == null || row.tokenLabel!.isEmpty
          ? 0
          : parseLedgerToken(row.tokenLabel!);
      ledger.add(
        CustomerLedgerLine(
          ledgerId: row.primaryKey,
          at: row.at,
          kind: CustomerLedgerKind.sale,
          description: row.description,
          amountPkr: row.amountPkr,
          debitPkr: row.amountPkr,
          creditPkr: 0,
          runningBalance: row.remainingPkr,
          tokenNo: tokenNo == 0 ? null : tokenNo,
          vehicleNo: row.vehicle,
          volumeLiters: row.liters,
          rate: row.rate,
        ),
      );
    } else {
      paidTotal += row.amountPkr;
      settlementIndex += 1;
      final CustomerSettlement settlement = settlementFromLedgerRow(
        row,
        id: settlementIndex,
      );
      final String note = settlement.notes.trim();
      final String desc = note.isEmpty
          ? '${settlement.paymentMode.label} recovery'
          : note;
      ledger.add(
        CustomerLedgerLine(
          ledgerId: row.primaryKey,
          at: row.at,
          kind: CustomerLedgerKind.settlement,
          description: desc,
          amountPkr: row.amountPkr,
          debitPkr: 0,
          creditPkr: row.amountPkr,
          runningBalance: row.remainingPkr,
          settlement: settlement,
        ),
      );
    }
  }

  final double outstanding = rows.isEmpty ? 0 : rows.last.remainingPkr;
  return CustomerAccount(
    profile: profile,
    udhaarSalesTotal: salesTotal,
    settlementsTotal: paidTotal,
    outstanding: outstanding,
    ledger: ledger.reversed.toList(),
  );
}

final customerAccountsProvider = Provider<List<CustomerAccount>>((Ref ref) {
  ref.watch(customerRevisionProvider);
  final List<CustomerProfile> directory = ref.watch(
    customerDirectoryCacheProvider,
  );
  final List<UnifiedUdhaarRow> ledger = ref.watch(unifiedLedgerCacheProvider);
  return directory.map((CustomerProfile profile) {
    final List<UnifiedUdhaarRow> rows = ledger
        .where((UnifiedUdhaarRow row) => row.customerId == profile.id)
        .toList();
    return _accountFor(profile: profile, rows: rows);
  }).toList();
});

final filteredCustomerAccountsProvider = Provider<List<CustomerAccount>>((
  Ref ref,
) {
  final String query = ref.watch(customerWorkspaceProvider).search.trim();
  final List<CustomerAccount> all = ref.watch(customerAccountsProvider);
  if (query.isEmpty) {
    return all;
  }
  final String needle = query.toLowerCase();
  final String idNeedle = normalizeCustomerIdQuery(query);
  return all.where((CustomerAccount account) {
    if (idNeedle.isNotEmpty && account.profile.id == idNeedle) {
      return true;
    }
    if (account.profile.id.toLowerCase().contains(needle)) {
      return true;
    }
    return account.profile.name.toLowerCase().contains(needle);
  }).toList();
});

final selectedCustomerAccountProvider = Provider<CustomerAccount?>((Ref ref) {
  final String? selectedId = ref.watch(customerWorkspaceProvider).selectedId;
  final List<CustomerAccount> accounts = ref.watch(customerAccountsProvider);
  if (accounts.isEmpty) {
    return null;
  }
  if (selectedId != null) {
    for (final CustomerAccount account in accounts) {
      if (account.profile.id == selectedId) {
        return account;
      }
    }
  }
  return accounts.first;
});

final customerKpisProvider = Provider<CustomerKpis>((Ref ref) {
  final List<CustomerAccount> accounts = ref.watch(customerAccountsProvider);
  final List<UnifiedUdhaarRow> ledger = ref.watch(unifiedLedgerCacheProvider);
  final DateTime now = DateTime.now();
  double totalOutstanding = 0;
  int active = 0;
  CustomerAccount? highest;
  for (final CustomerAccount account in accounts) {
    totalOutstanding += account.outstanding;
    if (account.hasDebt) {
      active += 1;
    }
    if (highest == null || account.outstanding > highest.outstanding) {
      highest = account;
    }
  }
  double settledThisMonth = 0;
  for (final UnifiedUdhaarRow row in ledger) {
    if (row.type != UnifiedUdhaarType.settlement) {
      continue;
    }
    if (row.at.year == now.year && row.at.month == now.month) {
      settledThisMonth += row.amountPkr;
    }
  }
  return CustomerKpis(
    totalOutstanding: totalOutstanding,
    activeCreditAccounts: active,
    settledThisMonth: settledThisMonth,
    highestDebt: highest != null && highest.outstanding > 0 ? highest : null,
  );
});

final stationCashInHandProvider = Provider<double>((Ref ref) {
  ref.watch(historyRevisionProvider);
  ref.watch(customerRevisionProvider);
  final List<SaleTransaction> sales = ref.watch(committedSalesProvider);
  final List<UnifiedUdhaarRow> ledger = ref.watch(unifiedLedgerCacheProvider);
  final List<CustomerSettlement> settlements = <CustomerSettlement>[
    for (final UnifiedUdhaarRow row in ledger)
      if (row.type == UnifiedUdhaarType.settlement)
        settlementFromLedgerRow(row),
  ];
  return cashInHandFromLedgers(sales: sales, settlements: settlements);
});
