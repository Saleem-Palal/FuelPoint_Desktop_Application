import 'dart:async';
import 'dart:io';

import '../../../core/constants.dart';
import '../domain/models.dart';

class PortScanner {
  Future<List<PortScanResult>> scan(
    String host, {
    List<int> ports = FdxDefaults.scanPorts,
    Duration timeout = FdxDefaults.scanTimeout,
    void Function(PortScanResult result)? onResult,
    bool Function()? isCancelled,
  }) async {
    final List<PortScanResult> results = <PortScanResult>[];
    for (final int port in ports) {
      if (isCancelled?.call() == true) {
        break;
      }
      final PortScanResult result = await probe(host, port, timeout: timeout);
      results.add(result);
      onResult?.call(result);
    }
    return results;
  }

  Future<PortScanResult> probe(
    String host,
    int port, {
    Duration timeout = FdxDefaults.scanTimeout,
  }) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      final int latencyMs = stopwatch.elapsedMilliseconds;
      return PortScanResult(port: port, open: true, latencyMs: latencyMs);
    } on SocketException catch (e) {
      return PortScanResult(port: port, open: false, error: _shortError(e));
    } on TimeoutException {
      return PortScanResult(port: port, open: false, error: 'timeout');
    } catch (e) {
      return PortScanResult(port: port, open: false, error: e.toString());
    } finally {
      try {
        socket?.destroy();
      } catch (_) {}
    }
  }

  String _shortError(SocketException e) {
    final String message = e.message.toLowerCase();
    final String os = e.osError?.message.toLowerCase() ?? '';
    if (message.contains('timed out') || os.contains('timed out')) {
      return 'timeout';
    }
    if (message.contains('refused') || os.contains('refused')) {
      return 'refused';
    }
    if (message.contains('unreachable') ||
        os.contains('unreachable') ||
        message.contains('no route') ||
        os.contains('no route')) {
      return 'unreachable';
    }
    if (message.contains('network is down') || os.contains('network is down')) {
      return 'offline';
    }
    if (e.message.isNotEmpty) {
      return e.message;
    }
    return 'closed';
  }
}
