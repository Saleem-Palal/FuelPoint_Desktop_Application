import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../customer/presentation/customer_providers.dart';
import '../../shift/domain/shift_models.dart';
import '../../shift/presentation/shift_providers.dart';
import '../../../providers/managers_provider.dart';
import '../domain/dashboard_models.dart';
import 'station_providers.dart';

final dashboardBayRangeProvider = StateProvider<DashboardRangePreset>(
  (Ref ref) => DashboardRangePreset.today,
);

final dashboardManagerRangeProvider = StateProvider<DashboardRangePreset>(
  (Ref ref) => DashboardRangePreset.today,
);

final dashboardHelperRangeProvider = StateProvider<DashboardRangePreset>(
  (Ref ref) => DashboardRangePreset.today,
);

List<DashboardStaffMember> _managerRoster(Ref ref) {
  final List<ManagerProfile> shiftManagers = ref.watch(
    shiftWorkspaceProvider.select(
      (ShiftWorkspaceState state) => state.managers,
    ),
  );
  if (shiftManagers.isNotEmpty) {
    return <DashboardStaffMember>[
      for (final ManagerProfile manager in shiftManagers)
        DashboardStaffMember(id: manager.id, name: manager.name),
    ];
  }
  return <DashboardStaffMember>[
    for (final StationManager manager in ref.watch(managersProvider).managers)
      DashboardStaffMember(id: manager.id, name: manager.name),
  ];
}

List<DashboardStaffMember> _helperRoster(Ref ref) {
  return <DashboardStaffMember>[
    for (final HelperProfile helper in ref.watch(helperRosterProvider))
      DashboardStaffMember(id: helper.id, name: helper.name),
  ];
}

/// SQLite-backed financial snapshot. Rebuilds after sales, settlements, or a
/// dashboard refresh reloads data from the database.
final dashboardSnapshotProvider = Provider<DashboardSnapshot>((Ref ref) {
  ref.watch(historyRevisionProvider);
  ref.watch(customerRevisionProvider);
  return assembleDashboardSnapshot(
    sales: ref.watch(committedSalesProvider),
    accounts: ref.watch(customerAccountsProvider),
    now: DateTime.now(),
    bayRange: ref.watch(dashboardBayRangeProvider),
    managerRange: ref.watch(dashboardManagerRangeProvider),
    helperRange: ref.watch(dashboardHelperRangeProvider),
    managers: _managerRoster(ref),
    helpers: _helperRoster(ref),
  );
});
