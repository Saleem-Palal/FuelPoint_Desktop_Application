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
    this.onOfficeLan = false,
  });

  final bool offline;
  final bool onWifi;
  final String? wifiName;
  final String? wifiIp;
  final String summary;
  final bool onDispenserAp;
  final bool onOfficeLan;

  static const NetworkSnapshot unknown = NetworkSnapshot(
    offline: false,
    onWifi: false,
    summary: 'Checking Wi-Fi…',
  );
}

/// Tenda office LAN: SSID `System` or any 192.168.0.x address (Ethernet counts).
bool isOnOfficeLan({String? wifiName, String? wifiIp}) {
  final String ssid = (wifiName ?? '').replaceAll('"', '').trim().toLowerCase();
  if (ssid == 'system') {
    return true;
  }
  final String ip = (wifiIp ?? '').trim();
  return ip.startsWith('192.168.0.');
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
