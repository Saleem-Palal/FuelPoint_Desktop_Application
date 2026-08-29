import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/constants.dart';
import '../connection/data/network_monitor.dart';
import '../connection/data/port_scanner.dart';
import '../connection/data/socket_client.dart';
import '../connection/domain/models.dart';
import '../telemetry/data/alpha_log_store.dart';
import '../telemetry/data/telemetry_ingestor.dart';
import '../telemetry/domain/telemetry_models.dart';

class DashboardController extends ChangeNotifier {
  DashboardController({
    PortScanner? scanner,
    DispenserSocketClient? socket,
    NetworkMonitor? networkMonitor,
    TelemetryIngestor? ingestor,
    AlphaLogStore? alphaLog,
  }) : _scanner = scanner ?? PortScanner(),
       _socket = socket ?? DispenserSocketClient(),
       _networkMonitor = networkMonitor ?? NetworkMonitor(),
       _ingestor = ingestor ?? TelemetryIngestor(),
       _alphaLog = alphaLog ?? AlphaLogStore();

  final PortScanner _scanner;
  final DispenserSocketClient _socket;
  final NetworkMonitor _networkMonitor;
  final TelemetryIngestor _ingestor;
  final AlphaLogStore _alphaLog;

  StreamSubscription<NetworkSnapshot>? _networkSub;
  bool _scanCancelled = false;
  bool _disposed = false;

  String targetIp = FdxDefaults.defaultIp;
  int targetPort = FdxDefaults.defaultPort;

  LinkState linkState = LinkState.disconnected;
  NetworkSnapshot network = NetworkSnapshot.unknown;
  TelemetrySnapshot telemetry = TelemetrySnapshot.empty;

  final List<LogLine> hexLines = <LogLine>[];
  final List<LogLine> asciiLines = <LogLine>[];
  final List<PortScanResult> scanResults = <PortScanResult>[];

  bool scanning = false;
  String? lastError;
  String statusMessage =
      'Not connected. Join FDX-ALPHA Wi-Fi, then tap Scan Ports.';

  String get hexLogText =>
      hexLines.map((LogLine line) => line.formatted).join('\n');
  String get asciiLogText =>
      asciiLines.map((LogLine line) => line.formatted).join('\n');
  bool get isConnected => linkState == LinkState.connected;
  bool get isBusy => scanning || linkState == LinkState.connecting;

  Future<void> start() async {
    _networkSub = _networkMonitor.watch().listen(_onNetwork);
    try {
      _onNetwork(await _networkMonitor.snapshot());
    } catch (e) {
      lastError = e.toString();
      _safeNotify();
    }
  }

  void _onNetwork(NetworkSnapshot snapshot) {
    network = snapshot;
    if (snapshot.offline && linkState == LinkState.connected) {
      unawaited(
        _dropLink(
          LinkState.offline,
          'Wi-Fi dropped. Join FDX-ALPHA Wi-Fi and tap Connect again.',
        ),
      );
    } else if (snapshot.offline &&
        linkState != LinkState.connected &&
        linkState != LinkState.connecting) {
      linkState = LinkState.offline;
      statusMessage =
          'Offline. Join the FDX-ALPHA Wi-Fi (board address 192.168.5.1).';
    } else if (!snapshot.offline && linkState == LinkState.offline) {
      linkState = LinkState.disconnected;
      statusMessage = snapshot.onDispenserAp
          ? 'On dispenser Wi-Fi. Tap Scan Ports or Connect (port 9876).'
          : 'Wi-Fi is on. Join FDX-ALPHA, then connect to 192.168.5.1 port 9876.';
    }
    _safeNotify();
  }

  Future<void> scanPorts({String? ip}) async {
    if (scanning) {
      return;
    }
    final String host = (ip ?? targetIp).trim();
    if (!_validIp(host)) {
      lastError = 'That IP address is not valid.';
      statusMessage = lastError ?? '';
      _safeNotify();
      return;
    }
    targetIp = host;
    scanning = true;
    _scanCancelled = false;
    scanResults
      ..clear()
      ..addAll(
        FdxDefaults.scanPorts.map(
          (int port) =>
              PortScanResult(port: port, open: false, error: 'pending'),
        ),
      );
    lastError = null;
    statusMessage = 'Looking for open ports on $host…';
    _appendSys('SCAN start $host ports ${FdxDefaults.scanPorts.join(', ')}');
    _safeNotify();

    try {
      await _scanner.scan(
        host,
        onResult: (PortScanResult result) {
          final int index = scanResults.indexWhere(
            (PortScanResult item) => item.port == result.port,
          );
          if (index >= 0) {
            scanResults[index] = result;
          } else {
            scanResults.add(result);
          }
          _appendSys('SCAN ${result.label}');
          _safeNotify();
        },
        isCancelled: () => _scanCancelled || _disposed,
      );
      final int openCount = scanResults
          .where((PortScanResult r) => r.open)
          .length;
      final bool unreachable = scanResults.every(
        (PortScanResult r) =>
            (r.error ?? '').contains('unreachable') ||
            (r.error ?? '').contains('offline') ||
            (r.error ?? '').contains('timeout'),
      );
      if (openCount == 0 && unreachable && !network.onDispenserAp) {
        linkState = LinkState.offline;
        statusMessage =
            'Cannot reach the board. Join FDX-ALPHA Wi-Fi and try again.';
      } else {
        statusMessage = openCount == 0
            ? 'Scan finished. No open ports on $host.'
            : 'Scan finished. Tap an open port, then Connect.';
        if (linkState == LinkState.offline && !network.offline) {
          linkState = LinkState.disconnected;
        }
      }
    } catch (e) {
      lastError = _describeError(e);
      statusMessage = 'Scan failed: $lastError';
      _appendSys('SCAN error $lastError');
      if (_looksUnreachable(e)) {
        linkState = LinkState.offline;
      }
    } finally {
      scanning = false;
      _safeNotify();
    }
  }

  Future<void> connect({String? ip, int? port}) async {
    if (linkState == LinkState.connecting) {
      return;
    }
    final String host = (ip ?? targetIp).trim();
    final int resolvedPort = port ?? targetPort;
    if (!_validIp(host)) {
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
    statusMessage = 'Connecting to $host port $resolvedPort…';
    _ingestor.reset();
    telemetry = TelemetrySnapshot.empty;
    _appendSys('CONNECT $host:$resolvedPort');
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
      statusMessage = 'Connected to $host port $resolvedPort.';
      _appendSys('CONNECTED');
    } catch (e) {
      lastError = _describeError(e);
      if (_looksUnreachable(e) || network.offline) {
        linkState = LinkState.offline;
        statusMessage =
            'Cannot reach the board: $lastError Join FDX-ALPHA Wi-Fi and retry.';
      } else {
        linkState = LinkState.disconnected;
        statusMessage = 'Could not connect: $lastError';
      }
      _appendSys('CONNECT fail $lastError');
    }
    _safeNotify();
  }

  Future<void> disconnect() async {
    await _dropLink(LinkState.disconnected, 'Disconnected.');
  }

  Future<void> sendAscii(String text, {bool appendCrlf = true}) async {
    if (!isConnected) {
      lastError = 'Connect first, then send.';
      statusMessage = lastError ?? '';
      _safeNotify();
      return;
    }
    try {
      final String payload = appendCrlf && !text.endsWith('\n')
          ? '$text\r\n'
          : text;
      final List<int> bytes = utf8.encode(payload);
      _socket.send(bytes);
      _appendTx(Uint8List.fromList(bytes));
      statusMessage = 'Sent ${bytes.length} character(s).';
    } catch (e) {
      lastError = _describeError(e);
      statusMessage = 'Send failed: $lastError';
      _appendSys('TX error $lastError');
    }
    _safeNotify();
  }

  Future<void> sendHex(String hex) async {
    if (!isConnected) {
      lastError = 'Connect first, then send.';
      statusMessage = lastError ?? '';
      _safeNotify();
      return;
    }
    final Uint8List? bytes = parseHexBytes(hex);
    if (bytes == null) {
      lastError = 'Hex must be pairs like 01 0A FF.';
      statusMessage = lastError ?? '';
      _safeNotify();
      return;
    }
    try {
      _socket.send(bytes);
      _appendTx(bytes);
      statusMessage = 'Sent ${bytes.length} byte(s).';
    } catch (e) {
      lastError = _describeError(e);
      statusMessage = 'Send failed: $lastError';
      _appendSys('TX error $lastError');
    }
    _safeNotify();
  }

  /// Writes a raw ASCII protocol frame on the open socket. Does not touch
  /// the receive / decode path.
  bool sendSocketCommand(String command) {
    if (!isConnected) {
      lastError = 'Connect first, then send.';
      statusMessage = lastError ?? '';
      _safeNotify();
      return false;
    }
    try {
      final List<int> bytes = utf8.encode(command);
      _socket.send(bytes);
      _appendTx(Uint8List.fromList(bytes));
      statusMessage = 'Sent: $command';
      _safeNotify();
      return true;
    } catch (e) {
      lastError = _describeError(e);
      statusMessage = 'Send failed: $lastError';
      _appendSys('TX error $lastError');
      _safeNotify();
      return false;
    }
  }

  bool startFlow() {
    return sendSocketCommand('<PL 999>\n');
  }

  bool stopFlow() {
    return sendSocketCommand('<PL 0>\n');
  }

  void selectPort(int port) {
    targetPort = port;
    statusMessage = 'Port set to $port. Tap Connect.';
    _safeNotify();
  }

  void clearLogs() {
    hexLines.clear();
    asciiLines.clear();
    statusMessage = 'Logs cleared.';
    _safeNotify();
  }

  void _onBytes(Uint8List data) {
    if (_disposed) {
      return;
    }
    _appendRx(data);
    try {
      final IngestOutcome outcome = _ingestor.ingest(data, telemetry);
      telemetry = outcome.snapshot;
      for (final String line in outcome.logLines) {
        _appendSys(line);
        unawaited(_alphaLog.append(line));
      }
    } catch (_) {}
    _safeNotify();
  }

  void _onSocketError(Object error) {
    lastError = _describeError(error);
    final LinkState next = _looksUnreachable(error) || network.offline
        ? LinkState.offline
        : LinkState.disconnected;
    unawaited(
      _dropLink(next, 'Connection lost: $lastError', alreadyClosed: true),
    );
  }

  void _onSocketDone() {
    if (linkState == LinkState.connected) {
      unawaited(
        _dropLink(
          network.offline ? LinkState.offline : LinkState.disconnected,
          'The board closed the connection.',
          alreadyClosed: true,
        ),
      );
    }
  }

  Future<void> _dropLink(
    LinkState next,
    String message, {
    bool alreadyClosed = false,
  }) async {
    if (!alreadyClosed) {
      try {
        await _socket.disconnect();
      } catch (_) {}
    }
    if (linkState == next && statusMessage == message && !isConnected) {
      return;
    }
    linkState = next;
    statusMessage = message;
    _appendSys(message);
    _safeNotify();
  }

  void _appendRx(Uint8List data) {
    _appendPair(_hex(data), _ascii(data));
  }

  void _appendTx(Uint8List data) {
    _appendPair('TX ${_hex(data)}', 'TX ${_ascii(data)}');
  }

  void _appendSys(String text) {
    _appendPair('SYS $text', 'SYS $text');
  }

  void _appendPair(String hex, String ascii) {
    final DateTime now = DateTime.now();
    hexLines.add(LogLine(timestamp: now, text: hex));
    asciiLines.add(LogLine(timestamp: now, text: ascii));
    _trim(hexLines);
    _trim(asciiLines);
  }

  void _trim(List<LogLine> lines) {
    if (lines.length > FdxDefaults.maxLogLines) {
      lines.removeRange(0, lines.length - FdxDefaults.maxLogLines);
    }
  }

  String _hex(Uint8List data) {
    return data.map((int b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  }

  String _ascii(Uint8List data) {
    return utf8.decode(data, allowMalformed: true);
  }

  bool _validIp(String value) {
    final InternetAddress? parsed = InternetAddress.tryParse(value);
    return parsed != null && parsed.type == InternetAddressType.IPv4;
  }

  bool _looksUnreachable(Object error) {
    final String text = error.toString().toLowerCase();
    return text.contains('unreachable') ||
        text.contains('no route') ||
        text.contains('network is down') ||
        text.contains('timed out') ||
        text.contains('timeout') ||
        text.contains('host is down') ||
        text.contains('os error: 1231') ||
        text.contains('os error: 10051') ||
        text.contains('os error: 10060') ||
        text.contains('os error: 10065');
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
    _scanCancelled = true;
    unawaited(_networkSub?.cancel());
    unawaited(_socket.disconnect());
    super.dispose();
  }
}

Uint8List? parseHexBytes(String input) {
  final String cleaned = input.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
  if (cleaned.isEmpty || cleaned.length.isOdd) {
    return null;
  }
  final List<int> bytes = <int>[];
  for (int i = 0; i < cleaned.length; i += 2) {
    bytes.add(int.parse(cleaned.substring(i, i + 2), radix: 16));
  }
  return Uint8List.fromList(bytes);
}
