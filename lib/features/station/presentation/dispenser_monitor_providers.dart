import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/dispenser_models.dart';
import '../domain/dispenser_monitor_models.dart';

final dispenserMonitorProvider =
    NotifierProvider<DispenserMonitorController, DispenserMonitorState>(
      DispenserMonitorController.new,
    );

class DispenserMonitorController extends Notifier<DispenserMonitorState> {
  Timer? _clock;
  bool _screenOpen = false;

  @override
  DispenserMonitorState build() {
    ref.onDispose(() {
      _clock?.cancel();
      _clock = null;
    });
    return DispenserMonitorState.empty();
  }

  /// TX/RX lamps and the wire log run only while Dispenser Monitor is open.
  void setScreenOpen(bool open) {
    if (open == _screenOpen) {
      return;
    }
    _screenOpen = open;
    _clock?.cancel();
    _clock = null;
    if (!open) {
      return;
    }
    _clock = Timer.periodic(const Duration(milliseconds: 400), (_) {
      state = state.copyWith(clock: DateTime.now());
    });
  }

  /// Socket-operator callback. The frame list is copied only while Dispenser
  /// Monitor is open, so Sale does not pay for the wire log.
  void ingestWire(DispenserWireFrame frame) {
    if (!_screenOpen) {
      return;
    }
    _patchLinkActivity(frame);
    if (state.paused) {
      return;
    }
    final List<DispenserWireFrame> next = <DispenserWireFrame>[
      ...state.frames,
      frame,
    ];
    final int cap = wireLogCap();
    if (next.length > cap) {
      next.removeRange(0, next.length - cap);
    }
    state = state.copyWith(frames: next);
  }

  void ingestTelemetryExtras(DispenserTelemetry packet) {
    final DateTime now = DateTime.now();
    final UnitDiagnosticSnapshot previous = state.diagnosticFor(packet.unitId);
    final DateTime? pingAt = previous.lastPingAt;
    int? latency = previous.latencyMs;
    if (pingAt != null && now.difference(pingAt) < const Duration(seconds: 5)) {
      latency = now.difference(pingAt).inMilliseconds;
    }
    final UnitDiagnosticSnapshot next = previous.copyWith(
      rssiDbm: packet.rssiDbm ?? previous.rssiDbm,
      latencyMs: latency,
      lastRxAt: _screenOpen ? now : previous.lastRxAt,
      espToBoardLink: packet.espToBoardLink ?? previous.espToBoardLink,
      pendingTxCount: packet.pendingTxCount ?? previous.pendingTxCount,
    );
    int? gatewayMs = state.gatewayLatencyMs;
    if (latency != null) {
      gatewayMs = latency;
    }
    if (_sameDiagnostic(previous, next) &&
        gatewayMs == state.gatewayLatencyMs) {
      return;
    }
    final Map<int, UnitDiagnosticSnapshot> diagnostics =
        Map<int, UnitDiagnosticSnapshot>.from(state.diagnostics);
    diagnostics[packet.unitId] = next;
    state = state.copyWith(
      diagnostics: diagnostics,
      gatewayLatencyMs: gatewayMs,
    );
  }

  void markPingSent(int unitId) {
    _patchUnit(
      unitId,
      state.diagnosticFor(unitId).copyWith(lastPingAt: DateTime.now()),
    );
  }

  void markSocketOpened(int unitId) {
    _patchUnit(
      unitId,
      state.diagnosticFor(unitId).copyWith(socketOpenedAt: DateTime.now()),
    );
  }

  void markSocketClosed(int unitId) {
    _patchUnit(
      unitId,
      state.diagnosticFor(unitId).copyWith(clearSocketOpened: true),
    );
  }

  void setPaused(bool paused) {
    state = state.copyWith(paused: paused);
  }

  void clearLog() {
    state = state.copyWith(frames: const <DispenserWireFrame>[]);
  }

  void setUnitFilter(int? unitId) {
    state = state.copyWith(unitFilter: unitId, clearUnitFilter: unitId == null);
  }

  void setKindFilter(DispenserWireKind? kind) {
    state = state.copyWith(kindFilter: kind, clearKindFilter: kind == null);
  }

  void _patchLinkActivity(DispenserWireFrame frame) {
    final int? unitId = frame.unitId;
    if (unitId == null) {
      return;
    }
    final DateTime now = DateTime.now();
    final UnitDiagnosticSnapshot previous = state.diagnosticFor(unitId);
    _patchUnit(
      unitId,
      frame.outbound
          ? previous.copyWith(lastTxAt: now)
          : previous.copyWith(lastRxAt: now),
    );
  }

  void _patchUnit(int unitId, UnitDiagnosticSnapshot next) {
    final UnitDiagnosticSnapshot previous = state.diagnosticFor(unitId);
    if (_sameDiagnostic(previous, next)) {
      return;
    }
    final Map<int, UnitDiagnosticSnapshot> diagnostics =
        Map<int, UnitDiagnosticSnapshot>.from(state.diagnostics);
    diagnostics[unitId] = next;
    state = state.copyWith(diagnostics: diagnostics);
  }

  bool _sameDiagnostic(UnitDiagnosticSnapshot a, UnitDiagnosticSnapshot b) {
    return a.rssiDbm == b.rssiDbm &&
        a.latencyMs == b.latencyMs &&
        a.lastPingAt == b.lastPingAt &&
        a.lastRxAt == b.lastRxAt &&
        a.lastTxAt == b.lastTxAt &&
        a.socketOpenedAt == b.socketOpenedAt &&
        a.espToBoardLink == b.espToBoardLink &&
        a.pendingTxCount == b.pendingTxCount;
  }
}
