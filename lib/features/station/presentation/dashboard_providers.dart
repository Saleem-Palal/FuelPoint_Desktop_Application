import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../customer/presentation/customer_providers.dart';
import '../../shift/domain/shift_models.dart';
import '../../shift/presentation/shift_providers.dart';
import '../../../providers/operators_provider.dart';
import '../domain/dashboard_models.dart';
import 'station_providers.dart';

final dashboardUnitRangeProvider = StateProvider<DashboardRangePreset>(
  (Ref ref) => DashboardRangePreset.today,
);

final dashboardOperatorRangeProvider = StateProvider<DashboardRangePreset>(
  (Ref ref) => DashboardRangePreset.today,
);

final dashboardHelperRangeProvider = StateProvider<DashboardRangePreset>(
  (Ref ref) => DashboardRangePreset.today,
);

List<DashboardStaffMember> _operatorRoster(Ref ref) {
  final List<OperatorProfile> shiftOperators = ref.watch(
    shiftWorkspaceProvider.select(
      (ShiftWorkspaceState state) => state.operators,
    ),
  );
  if (shiftOperators.isNotEmpty) {
    return <DashboardStaffMember>[
      for (final OperatorProfile operator in shiftOperators)
        DashboardStaffMember(id: operator.id, name: operator.name),
    ];
  }
  return <DashboardStaffMember>[
    for (final StationOperator operator in ref.watch(operatorsProvider).operators)
      DashboardStaffMember(id: operator.id, name: operator.name),
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
    unitRange: ref.watch(dashboardUnitRangeProvider),
    operatorRange: ref.watch(dashboardOperatorRangeProvider),
    helperRange: ref.watch(dashboardHelperRangeProvider),
    operators: _operatorRoster(ref),
    helpers: _helperRoster(ref),
  );
});
