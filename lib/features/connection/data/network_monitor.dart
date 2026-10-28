import 'dart:async';
import 'dart:io';

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

  /// Emits on start, on connectivity changes, and every few seconds.
  ///
  /// The poll matters on Windows: the SSID is often blank in release builds,
  /// and the Wi-Fi IP can arrive after the first connectivity event.
  Stream<NetworkSnapshot> watch({
    Duration poll = const Duration(seconds: 3),
  }) {
    late final StreamController<NetworkSnapshot> controller;
    Timer? timer;
    StreamSubscription<List<ConnectivityResult>>? connectivity;
    var emitting = false;

    Future<void> push() async {
      if (emitting || controller.isClosed) {
        return;
      }
      emitting = true;
      try {
        final NetworkSnapshot next = await snapshot();
        if (!controller.isClosed) {
          controller.add(next);
        }
      } finally {
        emitting = false;
      }
    }

    controller = StreamController<NetworkSnapshot>(
      onListen: () {
        unawaited(push());
        timer = Timer.periodic(poll, (_) => unawaited(push()));
        connectivity = _connectivity.onConnectivityChanged.listen((_) {
          unawaited(push());
        });
      },
      onCancel: () async {
        timer?.cancel();
        timer = null;
        await connectivity?.cancel();
        connectivity = null;
      },
    );
    return controller.stream;
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
    List<String> localIps = await _localIpv4();
    if (wifiIp != null && wifiIp.isNotEmpty && !localIps.contains(wifiIp)) {
      localIps = <String>[wifiIp, ...localIps];
    }

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
      String? lan;
      for (final String ip in localIps) {
        if (ip.startsWith('192.168.0.')) {
          lan = ip;
          break;
        }
      }
      lan ??= localIps.isEmpty ? null : localIps.first;
      summary = lan == null || lan.isEmpty ? 'Ethernet' : 'Ethernet  $lan';
    } else {
      summary = results.map((ConnectivityResult r) => r.name).join(', ');
    }

    return NetworkSnapshot(
      offline: offline,
      onWifi: onWifi,
      wifiName: wifiName,
      wifiIp: wifiIp,
      localIps: localIps,
      summary: summary,
      onDispenserAp: onDispenserAp,
      onOfficeLan: isOnOfficeLan(
        wifiName: wifiName,
        wifiIp: wifiIp,
        localIps: localIps,
      ),
    );
  }

  Future<List<String>> _localIpv4() async {
    try {
      final List<NetworkInterface> ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      final List<String> ips = <String>[];
      for (final NetworkInterface iface in ifaces) {
        for (final InternetAddress address in iface.addresses) {
          final String ip = address.address.trim();
          if (ip.isNotEmpty && !ips.contains(ip)) {
            ips.add(ip);
          }
        }
      }
      return ips;
    } catch (_) {
      return const <String>[];
    }
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
