import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../domain/dispenser_models.dart';
import 'telemetry_parser.dart';

typedef TelemetryHandler = void Function(DispenserTelemetry packet);
typedef OfflineHandler = void Function(int unitId);

class StationNetDefaults {
  static const int port = 8080;
  static const Duration heartbeat = Duration(seconds: 3);
  static const Duration connectTimeout = Duration(seconds: 4);

  static String hostFor(int unitId) => '192.168.1.${100 + unitId}';
}

class DispenserSocketManager {
  DispenserSocketManager({required this.onTelemetry, required this.onOffline});

  final TelemetryHandler onTelemetry;
  final OfflineHandler onOffline;

  final TelemetryParser _parser = TelemetryParser();
  final Map<int, _UnitLink> _links = <int, _UnitLink>{};
  final Map<int, DateTime> _lastPacketAt = <int, DateTime>{};

  RawDatagramSocket? _udp;
  Timer? _heartbeat;
  bool _disposed = false;

  Future<void> start() async {
    if (_disposed) {
      return;
    }
    for (final int unitId in dispenserUnitIds) {
      _links[unitId] = _UnitLink(
        unitId: unitId,
        onBytes: (Uint8List data) => _ingest(unitId, data),
        onOffline: () => onOffline(unitId),
      );
      unawaited(_links[unitId]!.connect());
    }
    await _bindUdp();
    _heartbeat = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _checkHeartbeats();
    });
  }

  Future<void> _bindUdp() async {
    try {
      _udp = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        StationNetDefaults.port,
      );
      _udp?.listen((RawSocketEvent event) {
        if (event != RawSocketEvent.read) {
          return;
        }
        final Datagram? datagram = _udp?.receive();
        if (datagram == null) {
          return;
        }
        _ingest(0, datagram.data);
      });
    } catch (_) {}
  }

  void _ingest(int fallbackUnit, Uint8List data) {
    if (_disposed) {
      return;
    }
    String chunk;
    try {
      chunk = utf8.decode(data, allowMalformed: true);
    } catch (_) {
      return;
    }
    final int unitHint = fallbackUnit;
    if (_links.containsKey(unitHint)) {
      _links[unitHint]!.buffer.write(chunk);
      _drain(_links[unitHint]!);
      return;
    }
    _drainRaw(chunk);
  }

  void _drain(_UnitLink link) {
    final String raw = link.buffer.toString();
    final int lastNl = raw.lastIndexOf('\n');
    if (lastNl < 0) {
      final String trimmed = raw.trim();
      if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
        _accept(trimmed);
        link.buffer.clear();
      }
      return;
    }
    final String complete = raw.substring(0, lastNl);
    link.buffer
      ..clear()
      ..write(raw.substring(lastNl + 1));
    for (final String piece in complete.split('\n')) {
      _accept(piece);
    }
  }

  void _drainRaw(String chunk) {
    for (final String piece in chunk.split('\n')) {
      _accept(piece);
    }
  }

  void _accept(String piece) {
    final DispenserTelemetry? packet = _parser.tryParse(piece);
    if (packet == null) {
      return;
    }
    _lastPacketAt[packet.unitId] = DateTime.now();
    onTelemetry(packet);
  }

  void _checkHeartbeats() {
    final DateTime now = DateTime.now();
    for (final int unitId in dispenserUnitIds) {
      final DateTime? last = _lastPacketAt[unitId];
      if (last == null) {
        continue;
      }
      if (now.difference(last) >= StationNetDefaults.heartbeat) {
        onOffline(unitId);
      }
    }
  }

  Future<void> setKeypadRelay({required int unitId, required bool lock}) async {
    final _UnitLink? link = _links[unitId];
    if (link == null) {
      return;
    }
    final String payload = jsonEncode(<String, Object>{
      'cmd': lock ? 'LOCK_KEYPAD' : 'UNLOCK_KEYPAD',
      'unit': unitId,
      'lock': lock,
    });
    try {
      await link.sendLine(payload);
    } catch (_) {}
  }

  Future<void> dispose() async {
    _disposed = true;
    _heartbeat?.cancel();
    _heartbeat = null;
    try {
      _udp?.close();
    } catch (_) {}
    _udp = null;
    for (final _UnitLink link in _links.values) {
      await link.dispose();
    }
    _links.clear();
  }
}

class _UnitLink {
  _UnitLink({
    required this.unitId,
    required this.onBytes,
    required this.onOffline,
  });

  final int unitId;
  final void Function(Uint8List data) onBytes;
  final void Function() onOffline;

  final StringBuffer buffer = StringBuffer();
  Socket? _socket;
  StreamSubscription<Uint8List>? _sub;
  int _attempts = 0;
  bool _disposed = false;
  bool _connecting = false;

  Future<void> connect() async {
    if (_disposed || _connecting) {
      return;
    }
    _connecting = true;
    try {
      final Socket socket = await Socket.connect(
        StationNetDefaults.hostFor(unitId),
        StationNetDefaults.port,
        timeout: StationNetDefaults.connectTimeout,
      );
      try {
        socket.setOption(SocketOption.tcpNoDelay, true);
      } catch (_) {}
      _socket = socket;
      _attempts = 0;
      _sub = socket.listen(
        onBytes,
        onError: (Object error, StackTrace _) {
          unawaited(_handleDrop());
        },
        onDone: () {
          unawaited(_handleDrop());
        },
        cancelOnError: true,
      );
    } catch (_) {
      await _handleDrop();
    } finally {
      _connecting = false;
    }
  }

  Future<void> sendLine(String line) async {
    if (_socket == null) {
      await connect();
    }
    final Socket? socket = _socket;
    if (socket == null) {
      throw const SocketException('Unit socket unavailable');
    }
    socket.writeln(line);
    await socket.flush();
  }

  Future<void> _handleDrop() async {
    await _closeSocket();
    if (_disposed) {
      return;
    }
    onOffline();
    _attempts += 1;
    final int shift = _attempts.clamp(1, 5);
    final int ms = (1000 * (1 << (shift - 1))).clamp(1000, 30000);
    await Future<void>.delayed(Duration(milliseconds: ms));
    if (!_disposed) {
      unawaited(connect());
    }
  }

  Future<void> _closeSocket() async {
    try {
      await _sub?.cancel();
    } catch (_) {}
    _sub = null;
    final Socket? socket = _socket;
    _socket = null;
    if (socket != null) {
      try {
        await socket.close();
      } catch (_) {}
      try {
        socket.destroy();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _closeSocket();
  }
}
