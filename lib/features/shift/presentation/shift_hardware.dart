import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../station/domain/dispenser_models.dart';
import '../../station/presentation/station_providers.dart';
import '../domain/shift_lifecycle.dart';

int? dispensingUnitIdOf(WidgetRef ref) {
  final StationState station = ref.read(stationControllerProvider);
  return ShiftLifecycleGuard.firstDispensingUnit(
    station.units.values
        .where((DispenserUnit unit) => unit.isDispensing)
        .map((DispenserUnit unit) => unit.unitId),
  );
}

Map<int, double> currentUnitMetersOf(WidgetRef ref) {
  return ref.read(stationControllerProvider.notifier).unitMeterSnapshot();
}
