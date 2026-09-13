import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../station/domain/dispenser_models.dart';
import '../../station/presentation/station_providers.dart';
import '../domain/shift_lifecycle.dart';

int? dispensingBayIdOf(WidgetRef ref) {
  final StationState station = ref.read(stationControllerProvider);
  return ShiftLifecycleGuard.firstDispensingBay(
    station.bays.values
        .where((DispenserBay bay) => bay.isDispensing)
        .map((DispenserBay bay) => bay.unitId),
  );
}

Map<int, double> currentBayMetersOf(WidgetRef ref) {
  return ref.read(stationControllerProvider.notifier).bayMeterSnapshot();
}
