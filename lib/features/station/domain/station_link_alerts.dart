import 'dispenser_models.dart';
import 'dispenser_monitor_models.dart';

enum StationLinkAlertKind { softwareWifi, espWifi, fdxBoard }

class StationLinkAlert {
  const StationLinkAlert({required this.kind, required this.message});

  final StationLinkAlertKind kind;
  final String message;
}

/// Banner name for the station network. System keeps the original wording.
String stationWifiAlertName(String ssid) {
  final String name = ssid.trim();
  if (name.isEmpty || name.toLowerCase() == 'system') {
    return 'Tenda WiFi System';
  }
  return name;
}

List<StationLinkAlert> buildStationLinkAlerts({
  required bool onOfficeLan,
  required List<int> unitIds,
  required StationState station,
  required DispenserMonitorState monitor,
  String networkName = 'Tenda WiFi System',
}) {
  return buildLinkAlerts(
    onOfficeLan: onOfficeLan,
    unitIds: unitIds,
    networkName: networkName,
    connected: (int unitId) => station.endpoint(unitId).connected,
    espToBoardLink: (int unitId) =>
        monitor.diagnosticFor(unitId).espToBoardLink,
  );
}

List<StationLinkAlert> buildLinkAlerts({
  required bool onOfficeLan,
  required List<int> unitIds,
  required bool Function(int unitId) connected,
  required bool? Function(int unitId) espToBoardLink,
  String networkName = 'Tenda WiFi System',
}) {
  final String network = networkName.trim().isEmpty
      ? 'Tenda WiFi System'
      : networkName.trim();
  final List<StationLinkAlert> alerts = <StationLinkAlert>[];
  // [onOfficeLan] should come from [stationLanOkProvider]: network match or a
  // live unit socket. Do not show the software banner when either is true.
  if (!onOfficeLan) {
    alerts.add(
      StationLinkAlert(
        kind: StationLinkAlertKind.softwareWifi,
        message: 'Software is not connected to $network',
      ),
    );
    return alerts;
  }
  for (final int unitId in unitIds) {
    if (!connected(unitId)) {
      alerts.add(
        StationLinkAlert(
          kind: StationLinkAlertKind.espWifi,
          message: 'Unit $unitId — ESP is Not connected to $network',
        ),
      );
      continue;
    }
    if (espToBoardLink(unitId) == false) {
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
