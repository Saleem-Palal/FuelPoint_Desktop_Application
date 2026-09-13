import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fuel_dispenser/features/station/data/telemetry_parser.dart';
import 'package:fuel_dispenser/features/station/domain/dispenser_models.dart';

void main() {
  final TelemetryParser parser = TelemetryParser();

  test('nested Type-33 heartbeat flattens LCD fields and flags', () {
    final String raw = jsonEncode(<String, Object>{
      'unit': 2,
      'cmd': 'HEARTBEAT',
      'system': <String, Object>{
        'uptime_sec': 12,
        'wifi_rssi': -61,
        'pending_tx_count': 1,
      },
      'status_flags': <String, Object>{
        'esp_to_board_link': true,
        'keypad_locked': false,
      },
      'telemetry': <String, Object>{
        'amount': 6619,
        'liters': 20,
        'rate': 330.95,
        'meter': 78.74,
        'status': 'Active / Pumping',
        'product': 'Diesel',
      },
    });

    final DispenserTelemetry? packet = parser.tryParse(raw);
    expect(packet, isNotNull);
    expect(packet!.unitId, 2);
    expect(packet.status, DispenserRunState.dispensing);
    expect(packet.amountPkr, 6619);
    expect(packet.volumeLiters, 20);
    expect(packet.rate, closeTo(330.95, 0.001));
    expect(packet.meterCount, closeTo(78.74, 0.001));
    expect(packet.keypadLocked, isFalse);
    expect(packet.rssiDbm, -61);
    expect(packet.espToBoardLink, isTrue);
    expect(packet.pendingTxCount, 1);
  });

  test('queue replay is a pending sale and is not auto-acked by the parser', () {
    final String raw = jsonEncode(<String, Object>{
      'cmd': 'QUEUE_REPLAY',
      'tx_id': 'ECC9FFFD1370-4',
      'unit': 1,
      'kind': 'Incomplete/PowerLost',
      'telemetry': <String, Object>{
        'amount': 500,
        'liters': 1.87,
        'rate': 267,
        'meter': 560695.06,
      },
    });

    final PendingEspSale? sale = PendingEspSale.tryParse(raw);
    expect(sale, isNotNull);
    expect(sale!.txId, 'ECC9FFFD1370-4');
    expect(sale.unitId, 1);
    expect(sale.isIncomplete, isTrue);
    expect(sale.volumeLiters, closeTo(1.87, 0.001));
    expect(sale.meterCount, closeTo(560695.06, 0.001));
  });

  test('live SALE_COMPLETE is telemetry, not a recovery queue row', () {
    final String raw = jsonEncode(<String, Object>{
      'cmd': 'SALE_COMPLETE',
      'tx_id': 'ECC9FFFD1370-5',
      'unit': 1,
      'telemetry': <String, Object>{
        'amount': 500,
        'liters': 1.87,
        'rate': 267,
        'meter': 12.4,
        'status': 'Idle',
      },
    });
    expect(PendingEspSale.tryParse(raw), isNull);
    final DispenserTelemetry? packet = parser.tryParse(raw);
    expect(packet, isNotNull);
    expect(packet!.txId, 'ECC9FFFD1370-5');
    expect(packet.status, DispenserRunState.idle);
  });

  test('NO_SALE cmd is a null hang-up even when idle LCD has last-sale liters', () {
    final String raw = jsonEncode(<String, Object>{
      'cmd': 'NO_SALE',
      'unit': 2,
      'status_flags': <String, Object>{'keypad_locked': false},
      'telemetry': <String, Object>{
        'amount': 100,
        'liters': 0.30,
        'rate': 330.95,
        'meter': 111.18,
        'status': 'Idle',
      },
    });
    final DispenserTelemetry? packet = parser.tryParse(raw);
    expect(packet, isNotNull);
    expect(packet!.isNoSaleCmd, isTrue);
    expect(packet.volumeLiters, closeTo(0.30, 0.001));
    expect(packet.keypadLocked, isFalse);
  });

  test('null hang-up uses pumping liters, not idle last-sale LCD', () {
    expect(
      isNullHangupCycle(lastPumpingLiters: 0, packetLiters: 0.30),
      isTrue,
    );
    expect(
      isNullHangupCycle(lastPumpingLiters: 1.87, packetLiters: 1.87),
      isFalse,
    );
    expect(
      isNullHangupCycle(lastPumpingLiters: null, packetLiters: 0),
      isTrue,
    );
  });

  test('seed hosts land on Tenda reserved IPs and port 81', () {
    expect(UnitEndpoint.seedFor(1).host, '192.168.0.110');
    expect(UnitEndpoint.seedFor(2).host, '192.168.0.120');
    expect(UnitEndpoint.seedFor(3).host, '192.168.0.130');
    expect(UnitEndpoint.seedFor(4).host, '192.168.0.140');
    expect(UnitEndpoint.seedFor(1).port, 81);
  });
}
