import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/sqlite_customer_directory_repository.dart';
import '../data/sqlite_unified_udhaar_repository.dart';
import '../domain/customer_models.dart';
import '../domain/customer_repository.dart';

final customerDirectoryRepositoryProvider =
    Provider<CustomerDirectoryRepository>((Ref ref) {
      return SqliteCustomerDirectoryRepository();
    });

final unifiedUdhaarRepositoryProvider = Provider<UnifiedUdhaarRepository>((
  Ref ref,
) {
  return SqliteUnifiedUdhaarRepository();
});

/// Bumped after customer or unified-ledger writes.
final customerRevisionProvider = StateProvider<int>((Ref ref) => 0);

final customerDirectoryCacheProvider = StateProvider<List<CustomerProfile>>(
  (Ref ref) => const <CustomerProfile>[],
);

final unifiedLedgerCacheProvider = StateProvider<List<UnifiedUdhaarRow>>(
  (Ref ref) => const <UnifiedUdhaarRow>[],
);

void bumpCustomerRevision(StateController<int> revision) {
  revision.state = revision.state + 1;
}

Future<void> reloadCustomerPersistence(Ref ref) async {
  try {
    final List<CustomerProfile> customers = await ref
        .read(customerDirectoryRepositoryProvider)
        .list();
    final List<UnifiedUdhaarRow> ledger = await ref
        .read(unifiedUdhaarRepositoryProvider)
        .list();
    ref.read(customerDirectoryCacheProvider.notifier).state = customers;
    ref.read(unifiedLedgerCacheProvider.notifier).state = ledger;
    bumpCustomerRevision(ref.read(customerRevisionProvider.notifier));
  } catch (_) {
    ref.read(customerDirectoryCacheProvider.notifier).state =
        const <CustomerProfile>[];
    ref.read(unifiedLedgerCacheProvider.notifier).state =
        const <UnifiedUdhaarRow>[];
    bumpCustomerRevision(ref.read(customerRevisionProvider.notifier));
    rethrow;
  }
}
