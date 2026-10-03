import 'dart:convert';

import 'shift_models.dart';

/// SQLite `shifts.STATUS` strings. Dart still uses [OperatorShiftStatus.open]
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

  static String toStorage(OperatorShiftStatus status) {
    switch (status) {
      case OperatorShiftStatus.open:
        return live;
      case OperatorShiftStatus.pendingReconciliation:
        return pending;
      case OperatorShiftStatus.closed:
        return closed;
      case OperatorShiftStatus.forceClosed:
        return forceClosed;
    }
  }

  static OperatorShiftStatus fromStorage(String raw) {
    switch (raw.trim().toUpperCase()) {
      case pending:
        return OperatorShiftStatus.pendingReconciliation;
      case closed:
        return OperatorShiftStatus.closed;
      case forceClosed:
        return OperatorShiftStatus.forceClosed;
      case live:
      case openLegacy:
      default:
        return OperatorShiftStatus.open;
    }
  }

  static bool isLiveStatus(String raw) {
    final String status = raw.trim().toUpperCase();
    return status == live || status == openLegacy;
  }
}

int elevatedByOwnerFlag(bool elevated) => elevated ? 1 : 0;

/// Unit totalizer snapshot keyed by dispenser unit id.
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

/// Persisted helper-to-unit duty. JSON array of unit ids, e.g. `[1,3]`.
class HelperUnitAssignmentSnapshot {
  HelperUnitAssignmentSnapshot._();

  static String encode(List<int> unitIds) {
    if (unitIds.isEmpty) {
      return '[]';
    }
    final List<int> ordered = unitIds.toSet().toList()..sort();
    return jsonEncode(ordered);
  }

  static List<int> decode(String? raw) {
    final String text = raw?.trim() ?? '';
    if (text.isEmpty || text == '[]') {
      return const <int>[];
    }
    try {
      final Object? decoded = jsonDecode(text);
      if (decoded is! List) {
        return const <int>[];
      }
      final Set<int> unique = <int>{};
      final List<int> ordered = <int>[];
      for (final Object? item in decoded) {
        final int? unitId = item is int ? item : int.tryParse('$item');
        if (unitId == null || !unique.add(unitId)) {
          continue;
        }
        ordered.add(unitId);
      }
      ordered.sort();
      return List<int>.unmodifiable(ordered);
    } catch (_) {
      return const <int>[];
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

  static int? firstDispensingUnit(Iterable<int> dispensingUnitIds) {
    final List<int> ids = dispensingUnitIds.toList()..sort();
    return ids.isEmpty ? null : ids.first;
  }

  static String handoverBlockedMessage(int unitId) {
    return 'Handover Blocked: Unit #$unitId is actively dispensing. '
        'Wait for nozzle stowage.';
  }

  static String endBlockedMessage(int unitId) {
    return 'End Shift Blocked: Unit #$unitId is actively dispensing. '
        'Wait for nozzle stowage.';
  }

  static String pendingAccountBlockedMessage() {
    return 'End Shift Blocked: Unconfirmed account transfers are pending. '
        'Confirm or clear them on the Sale screen first.';
  }
}
