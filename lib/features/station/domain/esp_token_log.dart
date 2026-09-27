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

bool _sameFillAsLedger(EspTokenLogRow row, SaleTransaction sale) {
  if (row.unitId != sale.unitId) {
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
  // SQLite stores whole liters of total meter (truncate/round). ESP logs
  // hundredths — 78.74 vs 78 must still count as the same fill.
  final int espMeter = row.meterCount.round();
  return (espMeter - sale.meterCount).abs() <= 1;
}

/// ESP last-10 Token# rows that unit does not already have in SQLite.
///
/// A row is already on the ledger when Token# matches, or when unit + rupees
/// + liters + rate + meter match a saved sale (duplicate hang-up Token#).
List<EspTokenLogRow> missingEspTokenRows({
  required List<EspTokenLogRow> espRows,
  required List<SaleTransaction> appRows,
}) {
  final Set<int> savedTokens = <int>{
    for (final SaleTransaction sale in appRows)
      if (sale.tokenNo > 0) sale.tokenNo,
  };
  final List<EspTokenLogRow> missing = <EspTokenLogRow>[];
  final Set<int> seen = <int>{};
  for (final EspTokenLogRow row in espRows) {
    if (row.token < 1 || row.unitId < 1) {
      continue;
    }
    if (row.volumeLiters.abs() < DispenserBay.zeroVolumeEpsilon) {
      continue;
    }
    if (savedTokens.contains(row.token) || !seen.add(row.token)) {
      continue;
    }
    final bool duplicateFill = appRows.any(
      (SaleTransaction sale) => _sameFillAsLedger(row, sale),
    );
    if (duplicateFill) {
      continue;
    }
    missing.add(row);
  }
  missing.sort((EspTokenLogRow a, EspTokenLogRow b) {
    final int unit = a.unitId.compareTo(b.unitId);
    if (unit != 0) {
      return unit;
    }
    return a.token.compareTo(b.token);
  });
  return missing;
}
