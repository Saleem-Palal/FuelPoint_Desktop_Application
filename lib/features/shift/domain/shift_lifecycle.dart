import 'dart:convert';

import 'shift_models.dart';

/// SQLite `shifts.STATUS` strings. Dart still uses [ManagerShiftStatus.open]
/// for a live cashier window; storage is `LIVE` (legacy `OPEN` still reads).
class ShiftStatusStorage {
  ShiftStatusStorage._();

  static const String live = 'LIVE';
  static const String openLegacy = 'OPEN';
  static const String pending = 'PENDING_RECONCILIATION';
  static const String closed = 'CLOSED';
  static const String forceClosed = 'FORCE_CLOSED';

  static const String liveSql = "UPPER(TRIM(STATUS)) IN ('LIVE', 'OPEN')";
  static const String liveAliasSql =
      "UPPER(TRIM(s.STATUS)) IN ('LIVE', 'OPEN')";
  static const String blockingSql =
      "UPPER(TRIM(STATUS)) IN ('LIVE', 'OPEN', 'PENDING_RECONCILIATION')";

  static String toStorage(ManagerShiftStatus status) {
    switch (status) {
      case ManagerShiftStatus.open:
        return live;
      case ManagerShiftStatus.pendingReconciliation:
        return pending;
      case ManagerShiftStatus.closed:
        return closed;
      case ManagerShiftStatus.forceClosed:
        return forceClosed;
    }
  }

  static ManagerShiftStatus fromStorage(String raw) {
    switch (raw.trim().toUpperCase()) {
      case pending:
        return ManagerShiftStatus.pendingReconciliation;
      case closed:
        return ManagerShiftStatus.closed;
      case forceClosed:
        return ManagerShiftStatus.forceClosed;
      case live:
      case openLegacy:
      default:
        return ManagerShiftStatus.open;
    }
  }

  static bool isLiveStatus(String raw) {
    final String status = raw.trim().toUpperCase();
    return status == live || status == openLegacy;
  }
}

int elevatedByOwnerFlag(bool elevated) => elevated ? 1 : 0;

/// Bay totalizer snapshot keyed by dispenser unit id.
class ShiftMeterSnapshot {
  ShiftMeterSnapshot._();

  static String encode(Map<int, double> meters) {
    if (meters.isEmpty) {
      return '{}';
    }
    return jsonEncode(<String, double>{
      for (final MapEntry<int, double> entry in meters.entries)
        '${entry.key}': entry.value,
    });
  }

  static Map<int, double> decode(String? raw) {
    final String text = raw?.trim() ?? '';
    if (text.isEmpty || text == '{}') {
      return const <int, double>{};
    }
    try {
      final Object? decoded = jsonDecode(text);
      if (decoded is! Map) {
        return const <int, double>{};
      }
      final Map<int, double> meters = <int, double>{};
      decoded.forEach((Object? key, Object? value) {
        final int? unitId = int.tryParse('$key');
        if (unitId == null) {
          return;
        }
        meters[unitId] = value is num
            ? value.toDouble()
            : double.tryParse('$value') ?? 0;
      });
      return Map<int, double>.unmodifiable(meters);
    } catch (_) {
      return const <int, double>{};
    }
  }
}

/// Runtime session row in `app_session_state`.
class AppSessionSnapshot {
  const AppSessionSnapshot({
    required this.isCleanShutdown,
    this.lastHeartbeatAt,
    this.uncleanExitAt,
  });

  final bool isCleanShutdown;
  final DateTime? lastHeartbeatAt;
  final DateTime? uncleanExitAt;

  static const AppSessionSnapshot clean = AppSessionSnapshot(
    isCleanShutdown: true,
  );
}

/// Forecourt interlocks that do not need Flutter widgets.
class ShiftLifecycleGuard {
  ShiftLifecycleGuard._();

  static int? firstDispensingBay(Iterable<int> dispensingUnitIds) {
    final List<int> ids = dispensingUnitIds.toList()..sort();
    return ids.isEmpty ? null : ids.first;
  }

  static String handoverBlockedMessage(int bayId) {
    return 'Handover Blocked: Bay #$bayId is actively dispensing. '
        'Wait for nozzle stowage.';
  }

  static String endBlockedMessage(int bayId) {
    return 'End Shift Blocked: Bay #$bayId is actively dispensing. '
        'Wait for nozzle stowage.';
  }
}
