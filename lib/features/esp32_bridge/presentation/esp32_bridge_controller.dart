import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/constants.dart';
import '../../connection/data/socket_client.dart';
import '../../connection/domain/models.dart';
import '../data/esp32_bridge_parser.dart';
import '../domain/esp32_bridge_models.dart';

class Esp32BridgeController extends ChangeNotifier {
  Esp32BridgeController({DispenserSocketClient? socket})
    : _socket = socket ?? DispenserSocketClient();

  final DispenserSocketClient _socket;
  bool _disposed = false;
  String _lineBuf = '';

  String targetIp = Esp32BridgeDefaults.defaultIp;
  int targetPort = Esp32BridgeDefaults.defaultPort;

  LinkState linkState = LinkState.disconnected;
  Esp32BridgeSnapshot snapshot = Esp32BridgeSnapshot.empty;
  final List<LogLine> lines = <LogLine>[];
  String? lastError;
  String statusMessage =
      'Join FDX-MUXTRONICS, then connect to ESP32-2 (default 192.168.100.253:9877).';

  String get logText => lines.map((LogLine line) => line.formatted).join('\n');
  bool get isConnected => linkState == LinkState.connected;
  bool get isBusy => linkState == LinkState.connecting;

  Future<void> connect({String? ip, int? port}) async {
    if (linkState == LinkState.connecting) {
      return;
    }
    final String host = (ip ?? targetIp).trim();
    final int resolvedPort = port ?? targetPort;
    if (InternetAddress.tryParse(host)?.type != InternetAddressType.IPv4) {
      lastError = 'That IP address is not valid.';
      statusMessage = lastError ?? '';
      _safeNotify();
      return;
    }
    if (resolvedPort < 1 || resolvedPort > 65535) {
      lastError = 'Port must be between 1 and 65535.';
      statusMessage = lastError ?? '';
      _safeNotify();
      return;
    }

    targetIp = host;
    targetPort = resolvedPort;
    linkState = LinkState.connecting;
    lastError = null;
    snapshot = Esp32BridgeSnapshot.empty;
    _lineBuf = '';
    statusMessage = 'Connecting to ESP32-2 $host:$resolvedPort…';
    _append('SYS CONNECT $host:$resolvedPort');
    _safeNotify();

    try {
      await _socket.connect(
        host: host,
        port: resolvedPort,
        onData: _onBytes,
        onError: _onSocketError,
        onDone: _onSocketDone,
      );
      if (_disposed) {
        await _socket.disconnect();
        return;
      }
      linkState = LinkState.connected;
      statusMessage = 'Connected to ESP32-2 $host:$resolvedPort.';
      _append('SYS CONNECTED');
    } catch (e) {
      lastError = _describeError(e);
      linkState = LinkState.disconnected;
      statusMessage = 'Could not connect to ESP32-2: $lastError';
      _append('SYS CONNECT fail $lastError');
    }
    _safeNotify();
  }

  Future<void> disconnect() async {
    await _dropLink('Disconnected from ESP32-2.');
  }

  void clearLogs() {
    lines.clear();
    statusMessage = 'Logs cleared.';
    _safeNotify();
  }

  bool sendRelayOn() {
    return _sendCommand('RELAY ON\n');
  }

  bool sendRelayOff() {
    return _sendCommand('RELAY OFF\n');
  }

  bool _sendCommand(String command) {
    if (!isConnected) {
      lastError = 'Connect to ESP32-2 first.';
      statusMessage = lastError ?? '';
      _safeNotify();
      return false;
    }
    try {
      _socket.send(utf8.encode(command));
      _append('SYS TX ${command.trim()}');
      statusMessage = 'Sent ${command.trim()}';
      _safeNotify();
      return true;
    } catch (e) {
      lastError = _describeError(e);
      statusMessage = 'Relay command failed: $lastError';
      _append('SYS TX error $lastError');
      _safeNotify();
      return false;
    }
  }

  void _onBytes(Uint8List data) {
    if (_disposed) {
      return;
    }
    _lineBuf += utf8.decode(data, allowMalformed: true);
    while (true) {
      final int nl = _lineBuf.indexOf('\n');
      if (nl < 0) {
        break;
      }
      final String raw = _lineBuf.substring(0, nl).replaceAll('\r', '');
      _lineBuf = _lineBuf.substring(nl + 1);
      if (raw.isEmpty) {
        continue;
      }
      _append(raw);
      snapshot = applyEsp32BridgeLine(snapshot, raw);
    }
    if (_lineBuf.length > 4096) {
      _lineBuf = '';
    }
    _safeNotify();
  }

  void _onSocketError(Object error) {
    lastError = _describeError(error);
    unawaited(
      _dropLink('ESP32-2 connection lost: $lastError', alreadyClosed: true),
    );
  }

  void _onSocketDone() {
    if (linkState == LinkState.connected) {
      unawaited(
        _dropLink('ESP32-2 closed the connection.', alreadyClosed: true),
      );
    }
  }

  Future<void> _dropLink(String message, {bool alreadyClosed = false}) async {
    if (!alreadyClosed) {
      try {
        await _socket.disconnect();
      } catch (_) {}
    }
    if (linkState == LinkState.disconnected && statusMessage == message) {
      return;
    }
    linkState = LinkState.disconnected;
    statusMessage = message;
    _append('SYS $message');
    _safeNotify();
  }

  void _append(String text) {
    lines.add(LogLine(timestamp: DateTime.now(), text: text));
    if (lines.length > FdxDefaults.maxLogLines) {
      lines.removeRange(0, lines.length - FdxDefaults.maxLogLines);
    }
  }

  String _describeError(Object error) {
    if (error is SocketException) {
      final String os = error.osError?.message ?? '';
      if (os.isNotEmpty) {
        return '${error.message} ($os)';
      }
      return error.message;
    }
    if (error is TimeoutException) {
      return 'Timed out after ${FdxDefaults.connectTimeout.inSeconds} seconds.';
    }
    return error.toString();
  }

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_socket.disconnect());
    super.dispose();
  }
}
