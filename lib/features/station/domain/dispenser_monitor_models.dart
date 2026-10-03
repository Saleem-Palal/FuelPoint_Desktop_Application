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

class UnitDiagnosticSnapshot {
  const UnitDiagnosticSnapshot({
    this.rssiDbm,
    this.latencyMs,
    this.lastPingAt,
    this.lastRxAt,
    this.lastTxAt,
    this.socketOpenedAt,
    this.espToBoardLink,
    this.pendingTxCount,
  });

  final int? rssiDbm;
  final int? latencyMs;
  final DateTime? lastPingAt;
  final DateTime? lastRxAt;
  final DateTime? lastTxAt;
  final DateTime? socketOpenedAt;
  final bool? espToBoardLink;
  final int? pendingTxCount;

  UnitDiagnosticSnapshot copyWith({
    int? rssiDbm,
    int? latencyMs,
    DateTime? lastPingAt,
    DateTime? lastRxAt,
    DateTime? lastTxAt,
    DateTime? socketOpenedAt,
    bool? espToBoardLink,
    int? pendingTxCount,
    bool clearSocketOpened = false,
  }) {
    return UnitDiagnosticSnapshot(
      rssiDbm: rssiDbm ?? this.rssiDbm,
      latencyMs: latencyMs ?? this.latencyMs,
      lastPingAt: lastPingAt ?? this.lastPingAt,
      lastRxAt: lastRxAt ?? this.lastRxAt,
      lastTxAt: lastTxAt ?? this.lastTxAt,
      socketOpenedAt: clearSocketOpened
          ? null
          : (socketOpenedAt ?? this.socketOpenedAt),
      espToBoardLink: espToBoardLink ?? this.espToBoardLink,
      pendingTxCount: pendingTxCount ?? this.pendingTxCount,
    );
  }
}

class UnitLinkHealth {
  const UnitLinkHealth({
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

  static UnitLinkHealth evaluate({
    required UnitEndpoint endpoint,
    required UnitDiagnosticSnapshot snapshot,
    required DateTime now,
  }) {
    final int rssi = snapshot.rssiDbm ?? -95;
    final bool muxSocketUp = endpoint.connected;
    const bool muxHeartbeatLost = false;

    final bool serialStall = muxSocketUp && snapshot.espToBoardLink == false;
    final bool serialLive = muxSocketUp && snapshot.espToBoardLink == true;

    final bool fdxWifiDrop = muxSocketUp && rssi <= -88;
    final bool fdxWifiUp = muxSocketUp && rssi > -88;

    final bool txHot =
        snapshot.lastTxAt != null && now.difference(snapshot.lastTxAt!) < _lamp;
    final bool rxHot =
        snapshot.lastRxAt != null && now.difference(snapshot.lastRxAt!) < _lamp;

    return UnitLinkHealth(
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
  final Map<int, UnitDiagnosticSnapshot> diagnostics;
  final DateTime clock;
  final int? unitFilter;
  final DispenserWireKind? kindFilter;
  final int? gatewayLatencyMs;

  static DispenserMonitorState empty() {
    return DispenserMonitorState(
      frames: const <DispenserWireFrame>[],
      paused: false,
      diagnostics: const <int, UnitDiagnosticSnapshot>{},
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

  UnitDiagnosticSnapshot diagnosticFor(int unitId) {
    return diagnostics[unitId] ?? const UnitDiagnosticSnapshot();
  }

  DispenserMonitorState copyWith({
    List<DispenserWireFrame>? frames,
    bool? paused,
    Map<int, UnitDiagnosticSnapshot>? diagnostics,
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

enum MonitorUnitStatus { online, dispensing, keypadLocked, offline }

MonitorUnitStatus monitorStatusFor(DispenserUnit unit, {bool linkOnline = true}) {
  if (!linkOnline || unit.isOffline) {
    return MonitorUnitStatus.offline;
  }
  if (unit.isDispensing) {
    return MonitorUnitStatus.dispensing;
  }
  if (unit.keypadLocked) {
    return MonitorUnitStatus.keypadLocked;
  }
  return MonitorUnitStatus.online;
}

extension MonitorUnitStatusX on MonitorUnitStatus {
  String get label {
    switch (this) {
      case MonitorUnitStatus.online:
        return 'ONLINE';
      case MonitorUnitStatus.dispensing:
        return 'DISPENSING';
      case MonitorUnitStatus.keypadLocked:
        return 'KEYPAD_LOCKED';
      case MonitorUnitStatus.offline:
        return 'OFFLINE';
    }
  }
}

int wireLogCap() => FdxDefaults.maxLogLines;
