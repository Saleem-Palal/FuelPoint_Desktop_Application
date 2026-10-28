import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_dispenser/features/station/data/station_unit_scan.dart';
import 'package:fuel_dispenser/features/station/data/station_wifi_store.dart';

void main() {
  test('Ufone_006 keeps gateway 192.168.1.1 until a new one is saved', () {
    expect(StationWifiStore.gatewayFor('Ufone_006', ''), '192.168.1.1');
    expect(
      StationWifiStore.gatewayFor('Ufone_006', '192.168.1.1'),
      '192.168.1.1',
    );
    expect(
      StationWifiStore.gatewayFor('Ufone_006', '192.168.0.1'),
      '192.168.1.1',
    );
    expect(StationWifiStore.gatewayFor('System', ''), '192.168.0.1');
    expect(StationWifiStore.gatewayFor('Other', ''), '');
  });

  test('gateway subnet skips the router and stays on 192.168.1.x', () {
    final List<String> hosts = hostsOnGatewaySubnet('192.168.1.1');
    expect(hosts, isNot(contains('192.168.1.1')));
    expect(hosts.first, '192.168.1.2');
    expect(hosts.last, '192.168.1.254');
    expect(hosts, hasLength(253));
  });

  test('hello text identifies the unit', () {
    expect(
      unitIdFromStationHello(
        '{"cmd":"WIFI_STATUS","unit":5,"ssid":"Ufone_006","ip":"192.168.1.40","dhcp":true}',
      ),
      5,
    );
    expect(unitIdFromStationHello('{"unit":5,"cmd":"TELEMETRY"}'), 5);
    expect(unitIdFromStationHello('{"cmd":"PING"}'), isNull);
  });
}
