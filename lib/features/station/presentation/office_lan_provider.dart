import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../connection/data/network_monitor.dart';
import '../../connection/domain/models.dart';
import '../data/dispenser_socket_manager.dart';
import '../data/station_wifi_store.dart';

/// Station network the PC and the banners should match.
///
/// Release builds stay on System. A debug network change updates this.
final stationOfficeSsidProvider =
    NotifierProvider<StationOfficeSsidNotifier, String>(
      StationOfficeSsidNotifier.new,
    );

class StationOfficeSsidNotifier extends Notifier<String> {
  bool _alive = true;

  @override
  String build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    if (kDebugMode) {
      Future<void>.microtask(_load);
    }
    return StationNetDefaults.officeSsid;
  }

  Future<void> _load() async {
    final String saved = await StationWifiStore.read();
    if (!_alive || saved == state) {
      return;
    }
    state = saved;
  }

  Future<void> remember(String ssid, {String gateway = ''}) async {
    final String trimmed = ssid.trim();
    if (!kDebugMode || trimmed.isEmpty) {
      return;
    }
    await StationWifiStore.write(trimmed, gateway: gateway);
    if (!_alive) {
      return;
    }
    state = trimmed;
  }
}

/// True when this PC is on the station network.
///
/// System accepts that SSID or any 192.168.0.x address on this PC. A debug
/// network matches by name. Windows release builds often hide the SSID, so the
/// adapter addresses are what keep the Sale banner honest.
final officeLanProvider = StreamProvider<bool>((Ref ref) async* {
  final String officeSsid = ref.watch(stationOfficeSsidProvider);
  final NetworkMonitor monitor = NetworkMonitor();
  await for (final NetworkSnapshot snapshot in monitor.watch()) {
    yield isOnOfficeLan(
      wifiName: snapshot.wifiName,
      wifiIp: snapshot.wifiIp,
      localIps: snapshot.localIps,
      officeSsid: officeSsid,
    );
  }
});
