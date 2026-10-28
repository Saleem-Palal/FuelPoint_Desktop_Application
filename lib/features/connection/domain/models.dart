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
    this.localIps = const <String>[],
    this.summary = 'Unknown',
    this.onDispenserAp = false,
    this.onOfficeLan = false,
  });

  final bool offline;
  final bool onWifi;
  final String? wifiName;
  final String? wifiIp;

  /// IPv4 addresses on this PC. Used when Windows will not report the Wi-Fi name.
  final List<String> localIps;
  final String summary;
  final bool onDispenserAp;
  final bool onOfficeLan;

  static const NetworkSnapshot unknown = NetworkSnapshot(
    offline: false,
    onWifi: false,
    summary: 'Checking Wi-Fi…',
  );
}

/// True when this PC is on [officeSsid].
///
/// `System` also accepts any 192.168.0.x address on Wi-Fi or Ethernet, so the
/// Sale banner stays clear when Windows hides the SSID but the Tenda LAN is up.
/// Any other station network matches the Wi-Fi name only.
bool isOnOfficeLan({
  String? wifiName,
  String? wifiIp,
  String officeSsid = 'System',
  Iterable<String>? localIps,
}) {
  final String expected = officeSsid.replaceAll('"', '').trim().toLowerCase();
  final String ssid = (wifiName ?? '')
      .replaceAll('"', '')
      .trim()
      .toLowerCase();
  if (expected.isNotEmpty && ssid == expected) {
    return true;
  }
  if (expected == 'system' && ssid.contains('system')) {
    return true;
  }
  if (expected != 'system') {
    return false;
  }
  if (_isSystemLanIp(wifiIp)) {
    return true;
  }
  if (localIps == null) {
    return false;
  }
  for (final String ip in localIps) {
    if (_isSystemLanIp(ip)) {
      return true;
    }
  }
  return false;
}

bool _isSystemLanIp(String? ip) {
  return (ip ?? '').trim().startsWith('192.168.0.');
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
