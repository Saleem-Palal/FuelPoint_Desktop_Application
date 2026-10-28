import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dispenser_socket_manager.dart';

/// The station network chosen in a debug build. Release always uses System.
class StationWifiStore {
  static const String prefsKey = 'debug_station_ssid';
  static const String gatewayKey = 'debug_station_gateway';

  static bool isSystemNetwork(String ssid) {
    return ssid.trim().toLowerCase() ==
        StationNetDefaults.officeSsid.toLowerCase();
  }

  /// Gateway saved with the network. Ufone_006 stays on 192.168.1.1 until changed.
  static String gatewayFor(String ssid, String savedGateway) {
    final String gateway = savedGateway.trim();
    final String name = ssid.trim().toLowerCase();
    if (name == 'ufone_006' &&
        (gateway.isEmpty || gateway == '192.168.0.1')) {
      return '192.168.1.1';
    }
    if (isIpv4(gateway)) {
      return gateway;
    }
    if (isSystemNetwork(ssid)) {
      return '192.168.0.1';
    }
    return '';
  }

  static bool isIpv4(String value) {
    final List<String> parts = value.trim().split('.');
    if (parts.length != 4) {
      return false;
    }
    for (final String part in parts) {
      final int? octet = int.tryParse(part);
      if (octet == null || octet < 0 || octet > 255 || part != '$octet') {
        return false;
      }
    }
    return true;
  }

  static Future<String> read() async {
    if (!kDebugMode) {
      return StationNetDefaults.officeSsid;
    }
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String saved = (prefs.getString(prefsKey) ?? '').trim();
      if (!_acceptable(saved)) {
        return StationNetDefaults.officeSsid;
      }
      return saved;
    } catch (_) {
      return StationNetDefaults.officeSsid;
    }
  }

  static Future<String> readGateway() async {
    final String ssid = await read();
    if (!kDebugMode) {
      return gatewayFor(ssid, '');
    }
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return gatewayFor(ssid, prefs.getString(gatewayKey) ?? '');
    } catch (_) {
      return gatewayFor(ssid, '');
    }
  }

  static Future<void> write(String ssid, {String gateway = ''}) async {
    if (!kDebugMode) {
      return;
    }
    final String trimmed = ssid.trim();
    if (!_acceptable(trimmed)) {
      return;
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, trimmed);
    final String resolved = gatewayFor(trimmed, gateway);
    if (resolved.isNotEmpty) {
      await prefs.setString(gatewayKey, resolved);
    }
  }

  static Future<String?> readUnitHost({
    required String ssid,
    required int unitId,
  }) async {
    if (!kDebugMode) {
      return null;
    }
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String host = (prefs.getString(_hostKey(ssid, unitId)) ?? '')
          .trim();
      if (!isIpv4(host)) {
        return null;
      }
      return host;
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeUnitHost({
    required String ssid,
    required int unitId,
    required String host,
  }) async {
    if (!kDebugMode || !isIpv4(host)) {
      return;
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hostKey(ssid, unitId), host.trim());
  }

  static String _hostKey(String ssid, int unitId) {
    return 'debug_unit_host_${ssid.trim().toLowerCase()}_$unitId';
  }

  static bool _acceptable(String ssid) {
    return ssid.isNotEmpty &&
        ssid.length <= 32 &&
        !ssid.contains('"') &&
        !ssid.contains('\\');
  }
}
