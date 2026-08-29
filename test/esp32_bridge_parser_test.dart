import 'package:flutter_test/flutter_test.dart';

import 'package:fuel_dispenser/features/esp32_bridge/data/esp32_bridge_parser.dart';
import 'package:fuel_dispenser/features/esp32_bridge/domain/esp32_bridge_models.dart';

void main() {
  test('parses compact FDX line from ESP32-2 UART prefix', () {
    const String line =
        'ESP32-2 UART FDX,AMT:500.00,VOL:1.87,RATE:267.00,MTR:560695.06,STS:Idle,PRD:Petrol,TIME:06:04:42';
    final Esp32BridgeSnapshot got = applyEsp32BridgeLine(
      Esp32BridgeSnapshot.empty,
      line,
    );
    expect(got.haveFdx, isTrue);
    expect(got.amount, closeTo(500.00, 0.001));
    expect(got.volume, closeTo(1.87, 0.001));
    expect(got.rate, closeTo(267.00, 0.001));
    expect(got.meter, closeTo(560695.06, 0.001));
    expect(got.status, 'Idle');
    expect(got.product, 'Petrol');
    expect(got.time, '06:04:42');
  });

  test('parses status with spaces from compact FDX line', () {
    const String line =
        'FDX,AMT:10.00,VOL:0.04,RATE:267.00,MTR:1.00,STS:Active / Pumping,PRD:Diesel,TIME:01:02:03';
    final Esp32BridgeSnapshot got = applyEsp32BridgeLine(
      Esp32BridgeSnapshot.empty,
      line,
    );
    expect(got.status, 'Active / Pumping');
    expect(got.product, 'Diesel');
  });

  test('UART-prefixed wifi offline is ESP32-1 dispenser, not office bridge', () {
    Esp32BridgeSnapshot snap = applyEsp32BridgeLine(
      Esp32BridgeSnapshot.empty,
      'wifi        192.168.100.253  TCP/UDP port 9877',
    );
    snap = applyEsp32BridgeLine(
      snap,
      'ESP32-2 UART wifi        offline',
    );
    snap = applyEsp32BridgeLine(snap, 'ESP32-2 UART socket      down');
    snap = applyEsp32BridgeLine(
      snap,
      'ESP32-2 UART live        waiting for Type-33 frame...',
    );
    expect(snap.bridgeIp, '192.168.100.253');
    expect(snap.dispenserWifi, 'offline');
    expect(snap.dispenserSocket, 'down');
    expect(snap.dispenserLive, 'waiting for Type-33 frame...');
    expect(snap.haveFdx, isFalse);
    expect(snap.waitingType33, isTrue);
  });

  test('marks UART live vs waiting from snapshot lines', () {
    final Esp32BridgeSnapshot live = applyEsp32BridgeLine(
      Esp32BridgeSnapshot.empty,
      'uart gpio   RX 16  lines 12  LIVE',
    );
    expect(live.uartLive, isTrue);
    expect(live.uartWaiting, isFalse);
    expect(live.uartLineCount, 12);

    final Esp32BridgeSnapshot wait = applyEsp32BridgeLine(
      live,
      'uart gpio   RX 16  lines 12  waiting for ESP32-1',
    );
    expect(wait.uartLive, isFalse);
    expect(wait.uartWaiting, isTrue);
  });

  test('parses relay state from compact and snapshot lines', () {
    final Esp32BridgeSnapshot fromCmd = applyEsp32BridgeLine(
      Esp32BridgeSnapshot.empty,
      'RELAY,STATE:ON,SRC:GPIO13',
    );
    expect(fromCmd.relayState, 'ON');
    expect(fromCmd.relaySource, 'GPIO13');

    final Esp32BridgeSnapshot fromSnap = applyEsp32BridgeLine(
      Esp32BridgeSnapshot.empty,
      'relay       OFF  src APP  IN GPIO 27',
    );
    expect(fromSnap.relayState, 'OFF');
    expect(fromSnap.relaySource, 'APP');
  });
}
