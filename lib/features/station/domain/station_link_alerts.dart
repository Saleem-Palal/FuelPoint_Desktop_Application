import 'dispenser_models.dart';
import 'dispenser_monitor_models.dart';

enum StationLinkAlertKind { softwareWifi, espWifi, fdxBoard }

class StationLinkAlert {
  const StationLinkAlert({required this.kind, required this.message});

  final StationLinkAlertKind kind;
  final String message;
}

List<StationLinkAlert> buildStationLinkAlerts({
  required bool onOfficeLan,
  required List<int> unitIds,
  required StationState station,
  required DispenserMonitorState monitor,
}) {
  final List<StationLinkAlert> alerts = <StationLinkAlert>[];
  if (!onOfficeLan) {
    alerts.add(
      const StationLinkAlert(
        kind: StationLinkAlertKind.softwareWifi,
        message: 'Software is not connected to Tenda WiFi System',
      ),
    );
    return alerts;
  }
  for (final int unitId in unitIds) {
    if (!station.endpoint(unitId).connected) {
      alerts.add(
        StationLinkAlert(
          kind: StationLinkAlertKind.espWifi,
          message: 'Unit $unitId — ESP is Not connected to Tenda WiFi System',
        ),
      );
      continue;
    }
    if (monitor.diagnosticFor(unitId).espToBoardLink == false) {
      alerts.add(
        StationLinkAlert(
          kind: StationLinkAlertKind.fdxBoard,
          message: 'Unit $unitId — ESP is not Connected to FDX Unit Board',
        ),
      );
    }
  }
  return alerts;
}
