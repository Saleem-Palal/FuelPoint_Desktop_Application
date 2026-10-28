import 'dart:convert';
import 'dart:io';

import 'wifi_status.dart';

class StationUnitHit {
  const StationUnitHit({required this.unitId, required this.host});

  final int unitId;
  final String host;
}

/// Addresses on the gateway's /24, skipping the gateway itself.
List<String> hostsOnGatewaySubnet(String gateway) {
  final List<String> parts = gateway.trim().split('.');
  if (parts.length != 4) {
    return const <String>[];
  }
  final int? tail = int.tryParse(parts[3]);
  if (tail == null) {
    return const <String>[];
  }
  final String prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
  return <String>[
    for (int host = 1; host <= 254; host++)
      if (host != tail) '$prefix.$host',
  ];
}

int? unitIdFromStationHello(String text) {
  final DispenserWifiStatus? wifi = tryParseWifiStatus(text);
  if (wifi != null && wifi.unitId >= 1 && wifi.unitId <= 5) {
    return wifi.unitId;
  }
  try {
    final Object? decoded = jsonDecode(text.trim());
    if (decoded is! Map) {
      return null;
    }
    final int? unitId = int.tryParse('${decoded['unit'] ?? ''}');
    if (unitId == null || unitId < 1 || unitId > 5) {
      return null;
    }
    return unitId;
  } catch (_) {
    return null;
  }
}

/// Opens port 81 on [gateway]'s network and reads each unit's hello.
Future<List<StationUnitHit>> findUnitsOnGateway(String gateway) async {
  final List<String> hosts = hostsOnGatewaySubnet(gateway);
  final List<StationUnitHit> found = <StationUnitHit>[];
  const int batch = 32;
  for (int index = 0; index < hosts.length; index += batch) {
    final int end = index + batch > hosts.length ? hosts.length : index + batch;
    final List<StationUnitHit?> hits = await Future.wait(
      <Future<StationUnitHit?>>[
        for (int cursor = index; cursor < end; cursor++) _probe(hosts[cursor]),
      ],
    );
    for (final StationUnitHit? hit in hits) {
      if (hit != null) {
        found.add(hit);
      }
    }
  }
  return found;
}

Future<StationUnitHit?> _probe(String host) async {
  try {
    final Socket socket = await Socket.connect(
      host,
      81,
      timeout: const Duration(milliseconds: 350),
    );
    socket.destroy();
  } catch (_) {
    return null;
  }
  WebSocket? webSocket;
  try {
    webSocket = await WebSocket.connect(
      'ws://$host:81/',
      compression: CompressionOptions.compressionOff,
    ).timeout(const Duration(milliseconds: 800));
    final dynamic first = await webSocket.first.timeout(
      const Duration(seconds: 2),
    );
    final String text = first is String
        ? first
        : utf8.decode(
            first is List<int> ? first : const <int>[],
            allowMalformed: true,
          );
    final int? unitId = unitIdFromStationHello(text);
    if (unitId == null) {
      return null;
    }
    return StationUnitHit(unitId: unitId, host: host);
  } catch (_) {
    return null;
  } finally {
    try {
      await webSocket?.close();
    } catch (_) {}
  }
}
