import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/operators_provider.dart';
import '../../customer/presentation/customer_providers.dart';
import '../../shift/presentation/shift_providers.dart';
import 'purchase_providers.dart';
import 'station_providers.dart';

Future<void> _runRefresh(String label, Future<void> Function() job) async {
  try {
    await job();
  } catch (error, stack) {
    debugPrint('$label refresh failed: $error\n$stack');
  }
}

/// Reloads every SQLite-backed workspace cache (sales, customers, purchases,
/// shifts, operators) so KPI cards and tables match the database.
Future<void> refreshWorkspaceFromDatabase(WidgetRef ref) async {
  Object? firstError;
  Future<void> run(String label, Future<void> Function() job) async {
    try {
      await job();
    } catch (error, stack) {
      debugPrint('$label refresh failed: $error\n$stack');
      firstError ??= error;
    }
  }

  await run(
    'Sales',
    () => ref.read(stationControllerProvider.notifier).reloadPersistedData(),
  );
  await run('Purchases', () => ref.read(purchaseControllerProvider).reload());
  await run('Shifts', () => ref.read(shiftWorkspaceProvider.notifier).reload());
  await run('Operators', () => ref.read(operatorsProvider.notifier).reload());
  bumpHistoryRevision(ref.read(historyRevisionProvider.notifier));
  final Object? error = firstError;
  if (error != null) {
    throw error;
  }
}

Future<void> refreshSalesFromDatabase(WidgetRef ref) {
  return _runRefresh(
    'Sales',
    () => ref.read(stationControllerProvider.notifier).reloadPersistedData(),
  );
}

Future<void> refreshPurchasesFromDatabase(WidgetRef ref) {
  return _runRefresh(
    'Purchases',
    () => ref.read(purchaseControllerProvider).reload(),
  );
}

Future<void> refreshCustomersFromDatabase(WidgetRef ref) {
  return _runRefresh(
    'Customers',
    () => ref.read(customerWorkspaceProvider.notifier).reload(),
  );
}

Future<void> refreshLedgerFromDatabase(WidgetRef ref) async {
  await refreshSalesFromDatabase(ref);
  await refreshPurchasesFromDatabase(ref);
  await refreshShiftsFromDatabase(ref);
}

Future<void> refreshOperatorsFromDatabase(WidgetRef ref) {
  return _runRefresh(
    'Operators',
    () => ref.read(operatorsProvider.notifier).reload(),
  );
}

Future<void> refreshShiftsFromDatabase(WidgetRef ref) {
  return _runRefresh(
    'Shifts',
    () => ref.read(shiftWorkspaceProvider.notifier).reload(),
  );
}
