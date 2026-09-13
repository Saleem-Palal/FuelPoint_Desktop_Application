import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/dispenser_models.dart';
import '../domain/dispenser_monitor_models.dart';
import 'telemetry_parser.dart';

typedef TelemetryHandler = void Function(DispenserTelemetry packet);
typedef OfflineHandler = void Function(int unitId);
typedef ConnectedHandler = void Function(int unitId);
typedef WireFrameHandler = void Function(DispenserWireFrame frame);
typedef PendingSaleHandler = void Function(PendingEspSale sale);

class StationNetDefaults {
  static const int port = 81;
  static const Duration heartbeat = Duration(milliseconds: 3000);
  static const Duration serialStall = Duration(milliseconds: 1500);
  static const Duration connectTimeout = Duration(seconds: 4);
  static const String officeSsid = 'System';
  static const String gatewayHost = '192.168.0.110';

  static String hostFor(int unitId) => '192.168.0.${100 + (10 * unitId)}';

  static String gatewayUrl({String? host, int? port}) {
    return 'ws://${host ?? gatewayHost}:${port ?? StationNetDefaults.port}/';
  }
}

class DispenserSocketManager {
  DispenserSocketManager({
    required this.onTelemetry,
    required this.onOffline,
    this.onConnected,
    this.onWire,
    this.onPendingSale,
  });

  final TelemetryHandler onTelemetry;
  final OfflineHandler onOffline;
  final ConnectedHandler? onConnected;
  final WireFrameHandler? onWire;
  final PendingSaleHandler? onPendingSale;

  final TelemetryParser _parser = TelemetryParser();
  final Map<int, _UnitLink> _links = <int, _UnitLink>{};
  final Map<int, DateTime> _lastPacketAt = <int, DateTime>{};

  Timer? _heartbeat;
  Timer? _appHeartbeat;
  bool _appHeartbeatEnabled = false;
  bool _shiftLive = false;
  bool _disposed = false;

  Future<void> start() async {
    if (_disposed) {
      return;
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    for (final int unitId in dispenserUnitIds) {
      final String host =
          prefs.getString('esp_host_$unitId') ??
          StationNetDefaults.hostFor(unitId);
      final int port =
          prefs.getInt('esp_port_$unitId') ?? StationNetDefaults.port;
      _links[unitId] = _UnitLink(
        unitId: unitId,
        host: host,
        port: port,
        onText: (String text) => _accept(text, fallbackUnit: unitId),
        onOffline: () => onOffline(unitId),
        onConnected: () => onConnected?.call(unitId),
      );
    }
    _heartbeat = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _checkHeartbeats();
    });
  }

  static Future<void> persistEndpoint({
    required int unitId,
    required String host,
    required int port,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('esp_host_$unitId', host);
    await prefs.setInt('esp_port_$unitId', port);
  }

  static Future<Map<int, UnitEndpoint>> loadEndpoints() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return <int, UnitEndpoint>{
      for (final int unitId in dispenserUnitIds)
        unitId: UnitEndpoint(
          host:
              prefs.getString('esp_host_$unitId') ??
              StationNetDefaults.hostFor(unitId),
          port: prefs.getInt('esp_port_$unitId') ?? StationNetDefaults.port,
        ),
    };
  }

  void _accept(String piece, {int fallbackUnit = 0}) {
    if (_disposed) {
      return;
    }
    final String trimmed = piece.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final PendingEspSale? pending = PendingEspSale.tryParse(trimmed);
    if (pending != null) {
      _lastPacketAt[pending.unitId] = DateTime.now();
      _emitWire(
        DispenserWireFrame(
          at: DateTime.now(),
          outbound: false,
          kind: DispenserWireKind.command,
          payload: trimmed,
          unitId: pending.unitId,
        ),
      );
      onPendingSale?.call(pending);
      final DispenserTelemetry? live = _parser.tryParse(trimmed);
      if (live != null) {
        onTelemetry(live);
      }
      return;
    }
    final DispenserTelemetry? packet = _parser.tryParse(
      trimmed,
      fallbackUnit: fallbackUnit,
    );
    if (packet == null) {
      _emitWire(
        DispenserWireFrame(
          at: DateTime.now(),
          outbound: false,
          kind: DispenserWireKind.error,
          payload: trimmed,
          unitId: fallbackUnit > 0 ? fallbackUnit : null,
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

  /// Keep a 1 s APP_HEARTBEAT while unit sockets are wanted so the ESP can
  /// tell app-crash from "shift not live". [live] is the shift flag.
  void setAppHeartbeatEnabled(bool enabled, {bool shiftLive = false}) {
    _shiftLive = shiftLive;
    _appHeartbeatEnabled = enabled;
    if (!enabled || _disposed) {
      _appHeartbeat?.cancel();
      _appHeartbeat = null;
      return;
    }
    _appHeartbeat ??= Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_broadcastAppHeartbeat());
    });
    unawaited(_broadcastAppHeartbeat());
  }

  Future<void> _broadcastAppHeartbeat() async {
    if (!_appHeartbeatEnabled || _disposed) {
      return;
    }
    final String at = DateTime.now().toIso8601String();
    for (final int unitId in dispenserUnitIds) {
      final _UnitLink? link = _links[unitId];
      if (link == null || !link.wanted) {
        continue;
      }
      await sendCommand(
        unitId: unitId,
        payload: <String, Object>{
          'cmd': 'APP_HEARTBEAT',
          'unit': unitId,
          'live': _shiftLive,
          'at': at,
        },
      );
    }
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
        'gpio': 4,
      },
    );
  }

  Future<void> confirmBay(int unitId) async {
    await sendCommand(
      unitId: unitId,
      payload: <String, Object>{'cmd': 'CONFIRM', 'unit': unitId},
    );
    await setKeypadRelay(unitId: unitId, lock: false);
  }

  Future<void> ackTransaction({
    required int unitId,
    required String txId,
  }) async {
    final _UnitLink? link = _links[unitId];
    final String frame = '<ACK,TX_ID_$txId>';
    _emitWire(
      DispenserWireFrame(
        at: DateTime.now(),
        outbound: true,
        kind: DispenserWireKind.command,
        payload: frame,
        unitId: unitId,
      ),
    );
    try {
      await link?.sendLine(frame);
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
    unawaited(
      persistEndpoint(unitId: unitId, host: host, port: port),
    );
    final _UnitLink link = _links.putIfAbsent(
      unitId,
      () => _UnitLink(
        unitId: unitId,
        host: host,
        port: port,
        onText: (String text) => _accept(text, fallbackUnit: unitId),
        onOffline: () => onOffline(unitId),
        onConnected: () => onConnected?.call(unitId),
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
    await pingUnit(unitId: unitId);
  }

  Future<void> flushUartBuffer(int unitId) async {
    await pingUnit(unitId: unitId);
  }

  Future<void> reconnectUnit(int unitId) async {
    final _UnitLink? link = _links[unitId];
    if (link == null) {
      return;
    }
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
    _appHeartbeat?.cancel();
    _appHeartbeat = null;
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
    required this.onText,
    required this.onOffline,
    required this.onConnected,
  });

  final int unitId;
  final void Function(String text) onText;
  final void Function() onOffline;
  final void Function() onConnected;

  String host;
  int port;
  bool wanted = false;

  WebSocket? _socket;
  StreamSubscription<dynamic>? _sub;
  int _attempts = 0;
  bool _disposed = false;
  bool _connecting = false;

  Future<void> connect() async {
    if (_disposed || _connecting || !wanted) {
      return;
    }
    _connecting = true;
    try {
      final WebSocket socket = await WebSocket.connect(
        StationNetDefaults.gatewayUrl(host: host, port: port),
      ).timeout(StationNetDefaults.connectTimeout);
      _socket = socket;
      _attempts = 0;
      onConnected();
      _sub = socket.listen(
        (dynamic data) {
          if (data is String) {
            onText(data);
          } else if (data is List<int>) {
            onText(utf8.decode(data, allowMalformed: true));
          }
        },
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
    final WebSocket? socket = _socket;
    if (socket == null) {
      throw const SocketException('Unit WebSocket unavailable');
    }
    socket.add(line);
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
    final WebSocket? socket = _socket;
    _socket = null;
    if (socket != null) {
      try {
        await socket.close();
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
