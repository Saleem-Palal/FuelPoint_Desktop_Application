import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../connection/data/network_monitor.dart';
import '../../connection/domain/models.dart';

/// True when this PC is on Tenda `System` Wi-Fi or 192.168.0.x Ethernet.
final officeLanProvider = StreamProvider<bool>((Ref ref) async* {
  final NetworkMonitor monitor = NetworkMonitor();
  yield (await monitor.snapshot()).onOfficeLan;
  await for (final _ in Stream<void>.periodic(const Duration(seconds: 2))) {
    yield (await monitor.snapshot()).onOfficeLan;
  }
});
