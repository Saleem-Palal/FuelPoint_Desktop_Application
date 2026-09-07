import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/dispenser_models.dart';
import '../domain/dispenser_monitor_models.dart';

final dispenserMonitorProvider =
    NotifierProvider<DispenserMonitorController, DispenserMonitorState>(
      DispenserMonitorController.new,
    );

class DispenserMonitorController extends Notifier<DispenserMonitorState> {
  @override
  DispenserMonitorState build() {
    final Timer ticker = Timer.periodic(const Duration(milliseconds: 400), (_) {
      state = state.copyWith(clock: DateTime.now());
    });
    ref.onDispose(ticker.cancel);
    return DispenserMonitorState.empty();
  }

  /// Socket-manager callback. Never writes [StationState], so Sale UI is idle.
  void ingestWire(DispenserWireFrame frame) {
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
    final BayDiagnosticSnapshot previous = state.diagnosticFor(packet.unitId);
    final DateTime? pingAt = previous.lastPingAt;
    int? latency = previous.latencyMs;
    if (pingAt != null && now.difference(pingAt) < const Duration(seconds: 5)) {
      latency = now.difference(pingAt).inMilliseconds;
    }
    final Map<int, BayDiagnosticSnapshot> diagnostics =
        Map<int, BayDiagnosticSnapshot>.from(state.diagnostics);
    diagnostics[packet.unitId] = previous.copyWith(
      rssiDbm: packet.rssiDbm ?? previous.rssiDbm,
      latencyMs: latency,
      lastRxAt: now,
    );
    int? gatewayMs = state.gatewayLatencyMs;
    if (latency != null) {
      gatewayMs = latency;
    }
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
    final BayDiagnosticSnapshot previous = state.diagnosticFor(unitId);
    _patchUnit(
      unitId,
      frame.outbound
          ? previous.copyWith(lastTxAt: now)
          : previous.copyWith(lastRxAt: now),
    );
  }

  void _patchUnit(int unitId, BayDiagnosticSnapshot next) {
    final Map<int, BayDiagnosticSnapshot> diagnostics =
        Map<int, BayDiagnosticSnapshot>.from(state.diagnostics);
    diagnostics[unitId] = next;
    state = state.copyWith(diagnostics: diagnostics);
  }
}
