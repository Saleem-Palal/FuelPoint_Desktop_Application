import 'package:flutter_test/flutter_test.dart';

import 'package:fuel_dispenser/Screens/Sale Screen/Widgets/Services/dispenser_units_widget.dart';
import 'package:fuel_dispenser/features/connection/domain/models.dart';
import 'package:fuel_dispenser/features/station/domain/dispenser_models.dart';
import 'package:fuel_dispenser/features/station/domain/dispenser_monitor_models.dart';
import 'package:fuel_dispenser/features/station/domain/station_link_alerts.dart';

void main() {
  group('isOnOfficeLan', () {
    test('matches Tenda SSID System, ignoring quotes and case', () {
      expect(isOnOfficeLan(wifiName: 'System'), isTrue);
      expect(isOnOfficeLan(wifiName: '"SYSTEM"'), isTrue);
      expect(isOnOfficeLan(wifiName: ' system '), isTrue);
    });

    test('matches 192.168.0.x even without SSID', () {
      expect(isOnOfficeLan(wifiIp: '192.168.0.42'), isTrue);
      expect(
        isOnOfficeLan(wifiName: 'Ethernet', wifiIp: '192.168.0.110'),
        isTrue,
      );
    });

    test('rejects dispenser AP and other subnets', () {
      expect(isOnOfficeLan(wifiName: 'FDX-ALPHA'), isFalse);
      expect(isOnOfficeLan(wifiIp: '192.168.1.10'), isFalse);
      expect(isOnOfficeLan(), isFalse);
    });
  });

  group('isUnitLinkOnline', () {
    test('follows the WebSocket flag, not packet age', () {
      final DateTime stale = DateTime.now().subtract(
        const Duration(seconds: 30),
      );
      final StationState online = _station(
        connected: true,
        lastPacketAt: stale,
      );
      expect(online.isUnitLinkOnline(1, now: DateTime.now()), isTrue);

      final StationState dropped = _station(
        connected: false,
        lastPacketAt: DateTime.now(),
      );
      expect(dropped.isUnitLinkOnline(1), isFalse);
    });
  });

  group('BayLinkHealth', () {
    test('does not treat packet silence as ESP Wi-Fi loss', () {
      final BayLinkHealth health = BayLinkHealth.evaluate(
        endpoint: const UnitEndpoint(
          host: '192.168.0.110',
          port: 81,
          connected: true,
        ),
        snapshot: const BayDiagnosticSnapshot(espToBoardLink: false),
        now: DateTime.now(),
      );
      expect(health.muxSocketUp, isTrue);
      expect(health.muxHeartbeatLost, isFalse);
      expect(health.muxAlert, isFalse);
      expect(health.serialStall, isTrue);
      expect(health.serialLive, isFalse);
    });

    test('muxAlert is only a closed WebSocket', () {
      final BayLinkHealth health = BayLinkHealth.evaluate(
        endpoint: UnitEndpoint.seedFor(1),
        snapshot: const BayDiagnosticSnapshot(espToBoardLink: true),
        now: DateTime.now(),
      );
      expect(health.muxSocketUp, isFalse);
      expect(health.muxAlert, isTrue);
      expect(health.serialStall, isFalse);
    });
  });

  group('buildStationLinkAlerts', () {
    test('PC off Tenda shows only the software banner, not per-unit ESP', () {
      final StationState station = StationState.seed().copyWith(
        endpoints: <int, UnitEndpoint>{
          1: UnitEndpoint.seedFor(1).copyWith(connected: false),
          2: UnitEndpoint.seedFor(2).copyWith(connected: true),
          3: UnitEndpoint.seedFor(3).copyWith(connected: true),
          4: UnitEndpoint.seedFor(4).copyWith(connected: true),
        },
      );
      final DispenserMonitorState monitor = DispenserMonitorState.empty()
          .copyWith(
            diagnostics: <int, BayDiagnosticSnapshot>{
              2: const BayDiagnosticSnapshot(espToBoardLink: false),
              3: const BayDiagnosticSnapshot(espToBoardLink: true),
            },
          );

      final List<StationLinkAlert> alerts = buildStationLinkAlerts(
        onOfficeLan: false,
        unitIds: const <int>[1, 2, 3],
        station: station,
        monitor: monitor,
      );

      expect(alerts, hasLength(1));
      expect(alerts.single.kind, StationLinkAlertKind.softwareWifi);
      expect(
        alerts.single.message,
        'Software is not connected to Tenda WiFi System',
      );
    });

    test('PC on Tenda reports ESP down and FDX UART down per unit', () {
      final StationState station = StationState.seed().copyWith(
        endpoints: <int, UnitEndpoint>{
          1: UnitEndpoint.seedFor(1).copyWith(connected: false),
          2: UnitEndpoint.seedFor(2).copyWith(connected: true),
          3: UnitEndpoint.seedFor(3).copyWith(connected: true),
          4: UnitEndpoint.seedFor(4).copyWith(connected: true),
        },
      );
      final DispenserMonitorState monitor = DispenserMonitorState.empty()
          .copyWith(
            diagnostics: <int, BayDiagnosticSnapshot>{
              2: const BayDiagnosticSnapshot(espToBoardLink: false),
              3: const BayDiagnosticSnapshot(espToBoardLink: true),
            },
          );

      final List<StationLinkAlert> alerts = buildStationLinkAlerts(
        onOfficeLan: true,
        unitIds: const <int>[1, 2, 3],
        station: station,
        monitor: monitor,
      );

      expect(
        alerts.map((StationLinkAlert a) => a.kind).toList(),
        <StationLinkAlertKind>[
          StationLinkAlertKind.espWifi,
          StationLinkAlertKind.fdxBoard,
        ],
      );
      expect(
        alerts[0].message,
        'Unit 1 — ESP is Not connected to Tenda WiFi System',
      );
      expect(
        alerts[1].message,
        'Unit 2 — ESP is not Connected to FDX Unit Board',
      );
    });

    test('skips FDX banner when the unit WebSocket is already down', () {
      final StationState station = StationState.seed().copyWith(
        endpoints: <int, UnitEndpoint>{
          1: UnitEndpoint.seedFor(1).copyWith(connected: false),
        },
      );
      final DispenserMonitorState monitor = DispenserMonitorState.empty()
          .copyWith(
            diagnostics: <int, BayDiagnosticSnapshot>{
              1: const BayDiagnosticSnapshot(espToBoardLink: false),
            },
          );

      final List<StationLinkAlert> alerts = buildStationLinkAlerts(
        onOfficeLan: true,
        unitIds: const <int>[1],
        station: station,
        monitor: monitor,
      );

      expect(alerts, hasLength(1));
      expect(alerts.single.kind, StationLinkAlertKind.espWifi);
    });
  });

  group('DispenserUnitData link flags', () {
    test('FDX UART down looks Offline but Confirm stays enabled', () {
      final DispenserUnitData data = DispenserUnitData.fromBay(
        StationState.seedBay(
          1,
        ).copyWith(status: DispenserRunState.cycleComplete, volumeLiters: 12.5),
        espConnected: true,
        fdxBoardLinked: false,
      );
      expect(data.isOffline, isTrue);
      expect(data.isEspDisconnected, isFalse);
      expect(data.isFdxDisconnected, isTrue);
      expect(data.canConfirmPayment, isTrue);
    });

    test('ESP socket down disables Confirm', () {
      final DispenserUnitData data = DispenserUnitData.fromBay(
        StationState.seedBay(
          1,
        ).copyWith(status: DispenserRunState.cycleComplete, volumeLiters: 12.5),
        espConnected: false,
        fdxBoardLinked: true,
      );
      expect(data.isOffline, isTrue);
      expect(data.isEspDisconnected, isTrue);
      expect(data.canConfirmPayment, isTrue);
    });
  });
}

StationState _station({required bool connected, DateTime? lastPacketAt}) {
  final StationState seed = StationState.seed();
  return seed.copyWith(
    bays: <int, DispenserBay>{
      ...seed.bays,
      1: seed.bay(1).copyWith(lastPacketAt: lastPacketAt),
    },
    endpoints: <int, UnitEndpoint>{
      ...seed.endpoints,
      1: seed.endpoint(1).copyWith(connected: connected),
    },
  );
}
