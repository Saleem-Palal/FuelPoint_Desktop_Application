import 'dart:convert';

import 'dispenser_models.dart';
import 'fuel_precision.dart';

/// One hang-up stored on the ESP last-10 Token# log.
class EspTokenLogRow {
  const EspTokenLogRow({
    required this.token,
    required this.unitId,
    required this.amountPkr,
    required this.volumeLiters,
    required this.rate,
    required this.meterCount,
    this.at,
    this.synced = false,
  });

  final int token;
  final int unitId;
  final double amountPkr;
  final double volumeLiters;
  final double rate;
  final double meterCount;
  final DateTime? at;
  final bool synced;

  static List<EspTokenLogRow> tryParseSyncLog(String raw) {
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const <EspTokenLogRow>[];
      }
      final Map<String, dynamic> map = Map<String, dynamic>.from(decoded);
      if ('${map['cmd'] ?? ''}'.toUpperCase() != 'SYNC_LOG') {
        return const <EspTokenLogRow>[];
      }
      final Object? rowsRaw = map['rows'];
      if (rowsRaw is! List) {
        return const <EspTokenLogRow>[];
      }
      final int unitFallback =
          int.tryParse('${map['unit'] ?? map['unit_id'] ?? '0'}') ?? 0;
      final List<EspTokenLogRow> rows = <EspTokenLogRow>[];
      for (final Object? item in rowsRaw) {
        if (item is! Map) {
          continue;
        }
        final EspTokenLogRow? row = fromMap(
          Map<String, dynamic>.from(item),
          unitFallback: unitFallback,
        );
        if (row != null) {
          rows.add(row);
        }
      }
      return rows;
    } catch (_) {
      return const <EspTokenLogRow>[];
    }
  }

  static EspTokenLogRow? fromMap(
    Map<String, dynamic> map, {
    int unitFallback = 0,
  }) {
    final int token = int.tryParse('${map['token'] ?? '0'}') ?? 0;
    final int unitId =
        int.tryParse('${map['unit'] ?? map['unit_id'] ?? unitFallback}') ??
        unitFallback;
    if (token < 1 || unitId < 1) {
      return null;
    }
    DateTime? at;
    final String stamp = '${map['at'] ?? ''}'.trim();
    if (stamp.isNotEmpty) {
      at = DateTime.tryParse(stamp);
    }
    return EspTokenLogRow(
      token: token,
      unitId: unitId,
      amountPkr: _num(map['amount'] ?? map['amount_pkr']),
      volumeLiters: _num(map['liters']),
      rate: _num(map['rate']),
      meterCount: _num(map['meter'] ?? map['total_meter']),
      at: at,
      synced: map['synced'] == true,
    );
  }

  static double _num(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse('$value') ?? 0;
  }
}

bool _sameCalendarSecond(DateTime a, DateTime b) {
  final DateTime left = a.toLocal();
  final DateTime right = b.toLocal();
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day &&
      left.hour == right.hour &&
      left.minute == right.minute &&
      left.second == right.second;
}

bool espRowMatchesLedger(EspTokenLogRow row, SaleTransaction sale) {
  if (row.unitId != sale.unitId) {
    return false;
  }
  final DateTime? stamp = row.at;
  if (stamp == null) {
    return false;
  }
  if (!_sameCalendarSecond(stamp, sale.timestamp)) {
    return false;
  }
  if (roundRupees(row.amountPkr) != roundRupees(sale.amountPkr)) {
    return false;
  }
  if (parseFuel(row.volumeLiters) != parseFuel(sale.volumeLiters)) {
    return false;
  }
  if (parseFuel(row.rate) != parseFuel(sale.rate)) {
    return false;
  }
  return true;
}

bool espRowAlreadyOnLedger({
  required EspTokenLogRow row,
  required List<SaleTransaction> appRows,
}) {
  return appRows.any((SaleTransaction sale) => espRowMatchesLedger(row, sale));
}

/// ESP last-10 rows that unit does not already have in SQLite.
///
/// Identity is unit + exact second + rupees + liters + rate.
List<EspTokenLogRow> missingEspTokenRows({
  required List<EspTokenLogRow> espRows,
  required List<SaleTransaction> appRows,
}) {
  final List<EspTokenLogRow> missing = <EspTokenLogRow>[];
  final Set<int> seen = <int>{};
  for (final EspTokenLogRow row in espRows) {
    if (row.token < 1 || row.unitId < 1) {
      continue;
    }
    if (row.volumeLiters.abs() < DispenserUnit.zeroVolumeEpsilon) {
      continue;
    }
    if (!seen.add(row.token)) {
      continue;
    }
    if (espRowAlreadyOnLedger(row: row, appRows: appRows)) {
      continue;
    }
    missing.add(row);
  }
  missing.sort((EspTokenLogRow a, EspTokenLogRow b) {
    final int unit = a.unitId.compareTo(b.unitId);
    if (unit != 0) {
      return unit;
    }
    final DateTime aAt = a.at ?? DateTime.fromMillisecondsSinceEpoch(0);
    final DateTime bAt = b.at ?? DateTime.fromMillisecondsSinceEpoch(0);
    return aAt.compareTo(bAt);
  });
  return missing;
}
