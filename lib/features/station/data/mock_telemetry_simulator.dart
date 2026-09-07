import 'dart:async';

import '../domain/dispenser_models.dart';

/// Hardware-less telemetry source for live client demos.
///
/// Emits the same [DispenserTelemetry] packets the ESP32/ESP-01 bridge will
/// send, so [StationController] has a single ingest path for mock and live wire.
class MockTelemetrySimulator {
  MockTelemetrySimulator({required this.emit});

  final void Function(DispenserTelemetry packet) emit;

  static const double demoSaleRate = 256.32;
  static const double demoSaleLiters = 10;
  static const int _saleTicks = 16;
  static const Duration _tick = Duration(milliseconds: 140);
  static const Duration _abortHold = Duration(seconds: 5);
  static const Duration _abortTick = Duration(milliseconds: 400);

  final Map<int, Timer> _timers = <int, Timer>{};

  bool get isBusy => _timers.isNotEmpty;

  bool isRunning(int unitId) => _timers.containsKey(unitId);

  void cancel(int unitId) {
    _timers.remove(unitId)?.cancel();
  }

  /// Runs a full sale: DISPENSING animation, then IDLE hang-up at [targetLiters].
  void simulateDispense({
    required int unitId,
    required double rate,
    required double targetLiters,
    required int meterCount,
    required bool keypadLocked,
  }) {
    cancel(unitId);
    final double safeRate = rate > 0 ? rate : demoSaleRate;
    final double saleLiters = targetLiters > 0
        ? double.parse(targetLiters.toStringAsFixed(2))
        : demoSaleLiters;
    int tick = 0;

    void pulse(double liters, DispenserRunState status) {
      emit(
        DispenserTelemetry(
          unitId: unitId,
          amountPkr: double.parse((liters * safeRate).toStringAsFixed(2)),
          volumeLiters: double.parse(liters.toStringAsFixed(2)),
          rate: safeRate,
          meterCount: meterCount,
          status: status,
          keypadLocked: keypadLocked,
        ),
      );
    }

    pulse(0, DispenserRunState.dispensing);
    _timers[unitId] = Timer.periodic(_tick, (Timer timer) {
      tick += 1;
      final double liters = saleLiters * (tick / _saleTicks);
      if (tick >= _saleTicks) {
        timer.cancel();
        _timers.remove(unitId);
        pulse(saleLiters, DispenserRunState.idle);
        return;
      }
      pulse(liters, DispenserRunState.dispensing);
    });
  }

  /// DISPENSING at 0.00 L for ~12s, then IDLE hang-up (zero-volume abort).
  void simulateZeroVolumeAbort({
    required int unitId,
    required double rate,
    required int meterCount,
    required bool keypadLocked,
  }) {
    cancel(unitId);
    final double safeRate = rate > 0 ? rate : demoSaleRate;
    final int abortTicks =
        _abortHold.inMilliseconds ~/ _abortTick.inMilliseconds;
    int tick = 0;

    void pulse(DispenserRunState status) {
      emit(
        DispenserTelemetry(
          unitId: unitId,
          amountPkr: 0,
          volumeLiters: 0,
          rate: safeRate,
          meterCount: meterCount,
          status: status,
          keypadLocked: keypadLocked,
        ),
      );
    }

    pulse(DispenserRunState.dispensing);
    _timers[unitId] = Timer.periodic(_abortTick, (Timer timer) {
      tick += 1;
      if (tick >= abortTicks) {
        timer.cancel();
        _timers.remove(unitId);
        pulse(DispenserRunState.idle);
        return;
      }
      pulse(DispenserRunState.dispensing);
    });
  }

  void dispose() {
    for (final Timer timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }
}
