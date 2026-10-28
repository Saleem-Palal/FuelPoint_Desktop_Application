import 'dart:convert';

/// Reply from a unit after its Wi-Fi name is saved.
class DispenserWifiStatus {
  const DispenserWifiStatus({
    required this.unitId,
    required this.ssid,
    required this.ip,
    required this.dhcp,
  });

  final int unitId;
  final String ssid;
  final String ip;
  final bool dhcp;

  bool get hasAddress {
    return ip.isNotEmpty && ip != '0.0.0.0';
  }
}

DispenserWifiStatus? tryParseWifiStatus(String text) {
  try {
    final Object? decoded = jsonDecode(text.trim());
    if (decoded is! Map || decoded['cmd'] != 'WIFI_STATUS') {
      return null;
    }
    final int unitId = int.tryParse('${decoded['unit'] ?? ''}') ?? 0;
    return DispenserWifiStatus(
      unitId: unitId,
      ssid: '${decoded['ssid'] ?? ''}',
      ip: '${decoded['ip'] ?? ''}',
      dhcp: decoded['dhcp'] == true,
    );
  } catch (_) {
    return null;
  }
}
