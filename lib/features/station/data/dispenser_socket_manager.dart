import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../domain/dispenser_models.dart';
import '../domain/dispenser_monitor_models.dart';
import 'telemetry_parser.dart';

typedef TelemetryHandler = void Function(DispenserTelemetry packet);
typedef OfflineHandler = void Function(int unitId);
typedef WireFrameHandler = void Function(DispenserWireFrame frame);

class StationNetDefaults {
  static const int port = 8080;
  static const Duration heartbeat = Duration(milliseconds: 3000);
  static const Duration serialStall = Duration(milliseconds: 1500);
  static const Duration connectTimeout = Duration(seconds: 4);

  /// Central ESP32 on the office SSID that Flutter talks to.
  static const String gatewayHost = '192.168.1.100';
  static const String officeSsid = 'FDX-MUXTRONICS';

  static String hostFor(int unitId) => '192.168.1.${100 + unitId}';

  static String gatewayUrl({String? host, int? port}) {
    return 'ws://${host ?? gatewayHost}:${port ?? StationNetDefaults.port}';
  }
}

class DispenserSocketManager {
  DispenserSocketManager({
    required this.onTelemetry,
    required this.onOffline,
    this.onWire,
  });

  final TelemetryHandler onTelemetry;
  final OfflineHandler onOffline;
  final WireFrameHandler? onWire;

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
        host: StationNetDefaults.hostFor(unitId),
        port: StationNetDefaults.port,
        onBytes: (Uint8List data) => _ingest(unitId, data),
        onOffline: () => onOffline(unitId),
      );
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
    final String trimmed = piece.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final DispenserTelemetry? packet = _parser.tryParse(trimmed);
    if (packet == null) {
      _emitWire(
        DispenserWireFrame(
          at: DateTime.now(),
          outbound: false,
          kind: DispenserWireKind.error,
          payload: trimmed,
          unitId: _unitHintFromJson(trimmed),
        ),
      );
      return;
    }
    _lastPacketAt[packet.unitId] = DateTime.now();
    _emitWire(
      DispenserWireFrame(
        at: DateTime.now(),
        outbound: false,
        kind: DispenserWireKind.classifyInbound(trimmed),
        payload: trimmed,
        unitId: packet.unitId,
      ),
    );
    onTelemetry(packet);
  }

  int? _unitHintFromJson(String trimmed) {
    try {
      final Object? decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        final Object? unit = decoded['unit'] ?? decoded['unit_id'];
        if (unit != null) {
          return int.tryParse(unit.toString());
        }
      }
    } catch (_) {}
    return null;
  }

  void _emitWire(DispenserWireFrame frame) {
    onWire?.call(frame);
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
    await sendCommand(
      unitId: unitId,
      payload: <String, Object>{
        'cmd': 'SET_KEYPAD_LOCK',
        'unit': unitId,
        'lock': lock,
        'gpio': 23,
      },
    );
  }

  Future<void> testBuzzer({required int unitId}) async {
    await sendCommand(
      unitId: unitId,
      payload: <String, Object>{
        'cmd': 'BUZZER_TEST',
        'unit': unitId,
        'gpio': 19,
      },
    );
  }

  Future<void> pingUnit({required int unitId}) async {
    await sendCommand(
      unitId: unitId,
      payload: <String, Object>{'cmd': 'PING', 'unit': unitId},
    );
  }

  Future<void> connectBay({
    required int unitId,
    required String host,
    required int port,
  }) async {
    final _UnitLink link = _links.putIfAbsent(
      unitId,
      () => _UnitLink(
        unitId: unitId,
        host: host,
        port: port,
        onBytes: (Uint8List data) => _ingest(unitId, data),
        onOffline: () => onOffline(unitId),
      ),
    );
    link.host = host;
    link.port = port;
    link.wanted = true;
    await link.reset();
  }

  Future<void> disconnectBay(int unitId) async {
    final _UnitLink? link = _links[unitId];
    if (link == null) {
      return;
    }
    link.wanted = false;
    await link.hangUp();
  }

  Future<void> rescanBayWifi(int unitId) async {
    await sendCommand(
      unitId: unitId,
      payload: <String, Object>{'cmd': 'RESCAN_BAY_WIFI', 'unit': unitId},
    );
  }

  Future<void> flushUartBuffer(int unitId) async {
    await sendCommand(
      unitId: unitId,
      payload: <String, Object>{'cmd': 'FLUSH_UART', 'unit': unitId},
    );
  }

  Future<void> reconnectUnit(int unitId) async {
    final _UnitLink? link = _links[unitId];
    if (link == null) {
      return;
    }
    _emitWire(
      DispenserWireFrame(
        at: DateTime.now(),
        outbound: true,
        kind: DispenserWireKind.command,
        payload: jsonEncode(<String, Object>{
          'cmd': 'RESET_BAY_SOCKET',
          'unit': unitId,
        }),
        unitId: unitId,
      ),
    );
    link.wanted = true;
    await link.reset();
  }

  Future<void> sendCommand({
    required int unitId,
    required Map<String, Object> payload,
  }) async {
    final _UnitLink? link = _links[unitId];
    final String encoded = jsonEncode(payload);
    _emitWire(
      DispenserWireFrame(
        at: DateTime.now(),
        outbound: true,
        kind: DispenserWireKind.command,
        payload: encoded,
        unitId: unitId,
      ),
    );
    if (link == null) {
      return;
    }
    try {
      await link.sendLine(encoded);
    } catch (error) {
      _emitWire(
        DispenserWireFrame(
          at: DateTime.now(),
          outbound: false,
          kind: DispenserWireKind.error,
          payload: jsonEncode(<String, Object>{
            'error': error.toString(),
            'unit': unitId,
          }),
          unitId: unitId,
        ),
      );
    }
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
    required this.host,
    required this.port,
    required this.onBytes,
    required this.onOffline,
  });

  final int unitId;
  final void Function(Uint8List data) onBytes;
  final void Function() onOffline;

  String host;
  int port;
  bool wanted = false;

  final StringBuffer buffer = StringBuffer();
  Socket? _socket;
  StreamSubscription<Uint8List>? _sub;
  int _attempts = 0;
  bool _disposed = false;
  bool _connecting = false;

  Future<void> connect() async {
    if (_disposed || _connecting || !wanted) {
      return;
    }
    _connecting = true;
    try {
      final Socket socket = await Socket.connect(
        host,
        port,
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
    if (_disposed || !wanted) {
      return;
    }
    onOffline();
    _attempts += 1;
    final int shift = _attempts.clamp(1, 5);
    final int ms = (1000 * (1 << (shift - 1))).clamp(1000, 30000);
    await Future<void>.delayed(Duration(milliseconds: ms));
    if (!_disposed && wanted) {
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

  Future<void> hangUp() async {
    wanted = false;
    await _closeSocket();
  }

  Future<void> reset() async {
    _attempts = 0;
    await _closeSocket();
    if (!_disposed && wanted) {
      unawaited(connect());
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    wanted = false;
    await _closeSocket();
  }
}
