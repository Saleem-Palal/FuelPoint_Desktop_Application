import 'dart:convert';

import '../../../core/constants.dart';
import 'dispenser_models.dart';

enum DispenserWireKind {
  telemetry,
  command,
  error;

  String get label {
    switch (this) {
      case DispenserWireKind.telemetry:
        return 'Telemetry';
      case DispenserWireKind.command:
        return 'Commands';
      case DispenserWireKind.error:
        return 'Errors';
    }
  }

  static DispenserWireKind classifyInbound(String payload) {
    try {
      final Object? decoded = jsonDecode(payload);
      if (decoded is! Map) {
        return DispenserWireKind.error;
      }
      if (decoded['error'] != null) {
        return DispenserWireKind.error;
      }
      if (decoded['cmd'] != null) {
        return DispenserWireKind.command;
      }
      return DispenserWireKind.telemetry;
    } catch (_) {
      return DispenserWireKind.error;
    }
  }
}

class DispenserWireFrame {
  const DispenserWireFrame({
    required this.at,
    required this.outbound,
    required this.kind,
    required this.payload,
    this.unitId,
  });

  final DateTime at;
  final bool outbound;
  final DispenserWireKind kind;
  final String payload;
  final int? unitId;

  String get directionTag => outbound ? 'TX' : 'RX';

  String get unitTag {
    final int? id = unitId;
    if (id == null || id < 1) {
      return 'GW';
    }
    return 'U$id';
  }
}

class BayDiagnosticSnapshot {
  const BayDiagnosticSnapshot({
    this.rssiDbm,
    this.latencyMs,
    this.lastPingAt,
    this.lastRxAt,
    this.lastTxAt,
    this.socketOpenedAt,
  });

  final int? rssiDbm;
  final int? latencyMs;
  final DateTime? lastPingAt;
  final DateTime? lastRxAt;
  final DateTime? lastTxAt;
  final DateTime? socketOpenedAt;

  BayDiagnosticSnapshot copyWith({
    int? rssiDbm,
    int? latencyMs,
    DateTime? lastPingAt,
    DateTime? lastRxAt,
    DateTime? lastTxAt,
    DateTime? socketOpenedAt,
    bool clearSocketOpened = false,
  }) {
    return BayDiagnosticSnapshot(
      rssiDbm: rssiDbm ?? this.rssiDbm,
      latencyMs: latencyMs ?? this.latencyMs,
      lastPingAt: lastPingAt ?? this.lastPingAt,
      lastRxAt: lastRxAt ?? this.lastRxAt,
      lastTxAt: lastTxAt ?? this.lastTxAt,
      socketOpenedAt: clearSocketOpened
          ? null
          : (socketOpenedAt ?? this.socketOpenedAt),
    );
  }
}

class BayLinkHealth {
  const BayLinkHealth({
    required this.rssiDbm,
    required this.fdxWifiUp,
    required this.fdxWifiDrop,
    required this.serialLive,
    required this.serialStall,
    required this.txHot,
    required this.rxHot,
    required this.muxSocketUp,
    required this.muxHeartbeatLost,
  });

  final int rssiDbm;
  final bool fdxWifiUp;
  final bool fdxWifiDrop;
  final bool serialLive;
  final bool serialStall;
  final bool txHot;
  final bool rxHot;
  final bool muxSocketUp;
  final bool muxHeartbeatLost;

  bool get muxAlert => !muxSocketUp || muxHeartbeatLost;

  static const Duration _lamp = Duration(milliseconds: 450);
  static const Duration _heartbeat = Duration(milliseconds: 3000);
  static const Duration _serialStall = Duration(milliseconds: 1500);

  static const List<int> demoRssi = <int>[-52, -61, -68, -74, -81];

  static BayLinkHealth evaluate({
    required DispenserBay bay,
    required UnitEndpoint endpoint,
    required BayDiagnosticSnapshot snapshot,
    required DateTime now,
  }) {
    final int rssi =
        snapshot.rssiDbm ??
        (bay.isOffline || !endpoint.connected
            ? -95
            : demoRssi[(bay.unitId - 1).clamp(0, demoRssi.length - 1)]);
    final DateTime? lastActivity = snapshot.lastRxAt ?? bay.lastPacketAt;
    final Duration? silence = lastActivity == null
        ? null
        : now.difference(lastActivity);
    final DateTime? opened = snapshot.socketOpenedAt;
    final Duration sinceOpen = opened == null
        ? Duration.zero
        : now.difference(opened);

    final bool muxSocketUp = endpoint.connected;
    final bool muxHeartbeatLost =
        muxSocketUp &&
        (silence == null ? sinceOpen >= _heartbeat : silence >= _heartbeat);

    final bool serialStall =
        muxSocketUp &&
        !muxHeartbeatLost &&
        (silence == null ? sinceOpen >= _serialStall : silence >= _serialStall);

    final bool fdxWifiDrop =
        muxSocketUp && (rssi <= -88 || (bay.isOffline && !muxHeartbeatLost));
    final bool fdxWifiUp = muxSocketUp && !fdxWifiDrop && rssi > -88;

    final bool txHot =
        snapshot.lastTxAt != null && now.difference(snapshot.lastTxAt!) < _lamp;
    final bool rxHot =
        snapshot.lastRxAt != null && now.difference(snapshot.lastRxAt!) < _lamp;
    final bool serialLive =
        muxSocketUp &&
        !serialStall &&
        (rxHot || txHot || (silence != null && silence < _serialStall));

    return BayLinkHealth(
      rssiDbm: rssi,
      fdxWifiUp: fdxWifiUp,
      fdxWifiDrop: fdxWifiDrop,
      serialLive: serialLive,
      serialStall: serialStall,
      txHot: txHot,
      rxHot: rxHot,
      muxSocketUp: muxSocketUp,
      muxHeartbeatLost: muxHeartbeatLost,
    );
  }
}

class DispenserMonitorState {
  const DispenserMonitorState({
    required this.frames,
    required this.paused,
    required this.diagnostics,
    required this.clock,
    this.unitFilter,
    this.kindFilter,
    this.gatewayLatencyMs,
  });

  final List<DispenserWireFrame> frames;
  final bool paused;
  final Map<int, BayDiagnosticSnapshot> diagnostics;
  final DateTime clock;
  final int? unitFilter;
  final DispenserWireKind? kindFilter;
  final int? gatewayLatencyMs;

  static DispenserMonitorState empty() {
    return DispenserMonitorState(
      frames: const <DispenserWireFrame>[],
      paused: false,
      diagnostics: const <int, BayDiagnosticSnapshot>{},
      clock: DateTime.now(),
    );
  }

  List<DispenserWireFrame> get visibleFrames {
    return frames.where((DispenserWireFrame frame) {
      final int? unit = unitFilter;
      if (unit != null && frame.unitId != unit) {
        return false;
      }
      final DispenserWireKind? kind = kindFilter;
      if (kind != null && frame.kind != kind) {
        return false;
      }
      return true;
    }).toList();
  }

  BayDiagnosticSnapshot diagnosticFor(int unitId) {
    return diagnostics[unitId] ?? const BayDiagnosticSnapshot();
  }

  DispenserMonitorState copyWith({
    List<DispenserWireFrame>? frames,
    bool? paused,
    Map<int, BayDiagnosticSnapshot>? diagnostics,
    DateTime? clock,
    int? unitFilter,
    DispenserWireKind? kindFilter,
    int? gatewayLatencyMs,
    bool clearUnitFilter = false,
    bool clearKindFilter = false,
  }) {
    return DispenserMonitorState(
      frames: frames ?? this.frames,
      paused: paused ?? this.paused,
      diagnostics: diagnostics ?? this.diagnostics,
      clock: clock ?? this.clock,
      unitFilter: clearUnitFilter ? null : (unitFilter ?? this.unitFilter),
      kindFilter: clearKindFilter ? null : (kindFilter ?? this.kindFilter),
      gatewayLatencyMs: gatewayLatencyMs ?? this.gatewayLatencyMs,
    );
  }
}

enum MonitorBayStatus { online, dispensing, keypadLocked, offline }

MonitorBayStatus monitorStatusFor(DispenserBay bay) {
  if (bay.isOffline) {
    return MonitorBayStatus.offline;
  }
  if (bay.isDispensing) {
    return MonitorBayStatus.dispensing;
  }
  if (bay.keypadLocked) {
    return MonitorBayStatus.keypadLocked;
  }
  return MonitorBayStatus.online;
}

extension MonitorBayStatusX on MonitorBayStatus {
  String get label {
    switch (this) {
      case MonitorBayStatus.online:
        return 'ONLINE';
      case MonitorBayStatus.dispensing:
        return 'DISPENSING';
      case MonitorBayStatus.keypadLocked:
        return 'KEYPAD_LOCKED';
      case MonitorBayStatus.offline:
        return 'OFFLINE';
    }
  }
}

int wireLogCap() => FdxDefaults.maxLogLines;
