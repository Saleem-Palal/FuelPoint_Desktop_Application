enum LinkState { disconnected, offline, connecting, connected }

class PortScanResult {
  const PortScanResult({
    required this.port,
    required this.open,
    this.latencyMs,
    this.error,
  });

  final int port;
  final bool open;
  final int? latencyMs;
  final String? error;

  String get label {
    if (open) {
      final int? ms = latencyMs;
      return ms == null ? '$port open' : '$port open (${ms}ms)';
    }
    final String? reason = error;
    if (reason == null || reason.isEmpty) {
      return '$port closed';
    }
    return '$port closed ($reason)';
  }
}

class NetworkSnapshot {
  const NetworkSnapshot({
    required this.offline,
    required this.onWifi,
    this.wifiName,
    this.wifiIp,
    this.summary = 'Unknown',
    this.onDispenserAp = false,
  });

  final bool offline;
  final bool onWifi;
  final String? wifiName;
  final String? wifiIp;
  final String summary;
  final bool onDispenserAp;

  static const NetworkSnapshot unknown = NetworkSnapshot(
    offline: false,
    onWifi: false,
    summary: 'Checking Wi-Fi…',
  );
}

class LogLine {
  const LogLine({required this.timestamp, required this.text});

  final DateTime timestamp;
  final String text;

  String get formatted {
    final String h = timestamp.hour.toString().padLeft(2, '0');
    final String m = timestamp.minute.toString().padLeft(2, '0');
    final String s = timestamp.second.toString().padLeft(2, '0');
    final String ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '[$h:$m:$s.$ms] $text';
  }
}
