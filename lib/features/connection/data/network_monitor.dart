import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';

import '../../../core/constants.dart';
import '../domain/models.dart';

class NetworkMonitor {
  NetworkMonitor({Connectivity? connectivity, NetworkInfo? networkInfo})
    : _connectivity = connectivity ?? Connectivity(),
      _networkInfo = networkInfo ?? NetworkInfo();

  final Connectivity _connectivity;
  final NetworkInfo _networkInfo;

  Stream<NetworkSnapshot> watch() async* {
    yield await snapshot();
    await for (final List<ConnectivityResult> results
        in _connectivity.onConnectivityChanged) {
      yield await snapshot(results);
    }
  }

  Future<NetworkSnapshot> snapshot([List<ConnectivityResult>? results]) async {
    try {
      results ??= await _connectivity.checkConnectivity();
    } catch (_) {
      results = const <ConnectivityResult>[ConnectivityResult.none];
    }

    final bool offline =
        results.isEmpty ||
        results.every((ConnectivityResult r) => r == ConnectivityResult.none);
    final bool onWifi = results.contains(ConnectivityResult.wifi);
    final bool onEthernet = results.contains(ConnectivityResult.ethernet);

    String? wifiName;
    String? wifiIp;
    try {
      wifiName = _clean(await _networkInfo.getWifiName());
    } catch (_) {}
    try {
      wifiIp = _clean(await _networkInfo.getWifiIP());
    } catch (_) {}

    final bool onDispenserAp =
        wifiName != null &&
        wifiName.toUpperCase().startsWith(FdxDefaults.boardSsidPrefix);

    final String summary;
    if (offline) {
      summary = 'Offline';
    } else if (wifiName != null && wifiName.isNotEmpty) {
      summary = wifiIp == null || wifiIp.isEmpty
          ? wifiName
          : '$wifiName  $wifiIp';
    } else if (onWifi) {
      summary = wifiIp == null || wifiIp.isEmpty ? 'Wi-Fi' : 'Wi-Fi  $wifiIp';
    } else if (onEthernet) {
      summary = 'Ethernet';
    } else {
      summary = results.map((ConnectivityResult r) => r.name).join(', ');
    }

    return NetworkSnapshot(
      offline: offline,
      onWifi: onWifi,
      wifiName: wifiName,
      wifiIp: wifiIp,
      summary: summary,
      onDispenserAp: onDispenserAp,
    );
  }

  String? _clean(String? value) {
    if (value == null) {
      return null;
    }
    final String trimmed = value.replaceAll('"', '').trim();
    if (trimmed.isEmpty || trimmed.toLowerCase() == 'null') {
      return null;
    }
    return trimmed;
  }
}
