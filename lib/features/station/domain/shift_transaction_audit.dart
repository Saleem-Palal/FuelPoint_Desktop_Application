import 'dispenser_models.dart';
import 'fuel_precision.dart';
import 'money_format.dart';
import 'shift_ledger_models.dart';

enum ShiftAuditKind {
  litersVsMeter,
  chainGap,
  shiftVolume,
  firstOpening,
  lastClosing,
}

class ShiftAuditFinding {
  const ShiftAuditFinding({
    required this.kind,
    required this.unitId,
    required this.message,
    this.tokenNo,
    this.previousTokenNo,
  });

  final ShiftAuditKind kind;
  final int unitId;
  final String message;
  final int? tokenNo;
  final int? previousTokenNo;
}

class ShiftUnitAudit {
  const ShiftUnitAudit({
    required this.unitId,
    required this.chronological,
    required this.findings,
    required this.saleLiters,
    this.testLiters = 0,
    this.shiftVolumeLiters,
  });

  final int unitId;
  final List<SaleTransaction> chronological;
  final List<ShiftAuditFinding> findings;
  final double saleLiters;
  final double testLiters;
  final double? shiftVolumeLiters;

  bool get ok => findings.isEmpty;

  int get testFillCount {
    int count = 0;
    for (final SaleTransaction row in chronological) {
      if (row.isTest) {
        count += 1;
      }
    }
    return count;
  }
}

class ShiftTransactionAudit {
  const ShiftTransactionAudit({required this.units});

  final List<ShiftUnitAudit> units;

  int get findingCount {
    int count = 0;
    for (final ShiftUnitAudit unit in units) {
      count += unit.findings.length;
    }
    return count;
  }

  bool get ok => findingCount == 0;
}

double? latestSaleClosingMeter(List<SaleTransaction> rows, int unitId) {
  SaleTransaction? latest;
  for (final SaleTransaction row in rows) {
    if (row.unitId != unitId) {
      continue;
    }
    if (latest == null || row.timestamp.isAfter(latest.timestamp)) {
      latest = row;
    }
  }
  return latest?.closingMeter;
}

double? resolvedShiftClosingMeter({
  required ShiftLedgerSummary summary,
  required int unitId,
  List<SaleTransaction> sales = const <SaleTransaction>[],
}) {
  final double? stored = summary.closingMeters[unitId];
  if (!summary.isLive) {
    return stored;
  }
  return latestSaleClosingMeter(sales, unitId) ?? stored;
}

double? shiftVolumeLitersFor({
  required ShiftLedgerSummary summary,
  required int unitId,
  double? closingMeter,
}) {
  final double? opening = summary.openingMeters[unitId];
  final double? closing =
      closingMeter ?? (summary.isLive ? null : summary.closingMeters[unitId]);
  if (opening == null || closing == null) {
    return null;
  }
  return meterDeltaLiters(opening, closing).toDouble();
}

bool shiftVolumeMatchesSaleLiters({
  required double? shiftVolumeLiters,
  required double saleLiters,
  double testLiters = 0,
}) {
  if (shiftVolumeLiters == null) {
    return true;
  }
  return metersMatchAtAuditScale(shiftVolumeLiters, saleLiters + testLiters);
}

String shiftVolumeRemark({
  required double? shiftVolume,
  required double saleLiters,
  double testLiters = 0,
}) {
  if (shiftVolume != null &&
      shiftVolumeMatchesSaleLiters(
        shiftVolumeLiters: shiftVolume,
        saleLiters: saleLiters,
        testLiters: testLiters,
      )) {
    return 'Match';
  }
  return 'Mismatch';
}

ShiftTransactionAudit auditShiftTransactions({
  required List<SaleTransaction> rows,
  required ShiftLedgerSummary summary,
  int? unitId,
}) {
  final Map<int, List<SaleTransaction>> grouped =
      <int, List<SaleTransaction>>{};
  for (final SaleTransaction row in rows) {
    if (isDirectSaleUnit(row.unitId)) {
      continue;
    }
    if (unitId != null && row.unitId != unitId) {
      continue;
    }
    grouped.putIfAbsent(row.unitId, () => <SaleTransaction>[]).add(row);
  }
  final List<int> unitIds = grouped.keys.toList()..sort();
  return ShiftTransactionAudit(
    units: <ShiftUnitAudit>[
      for (final int id in unitIds)
        _auditUnit(unitId: id, rows: grouped[id]!, summary: summary),
    ],
  );
}

ShiftUnitAudit _auditUnit({
  required int unitId,
  required List<SaleTransaction> rows,
  required ShiftLedgerSummary summary,
}) {
  final List<SaleTransaction> chronological = List<SaleTransaction>.from(rows)
    ..sort((SaleTransaction a, SaleTransaction b) {
      final int byTime = a.timestamp.compareTo(b.timestamp);
      if (byTime != 0) {
        return byTime;
      }
      return a.tokenNo.compareTo(b.tokenNo);
    });

  final List<ShiftAuditFinding> findings = <ShiftAuditFinding>[];
  double saleLiters = 0;
  double testLiters = 0;
  for (final SaleTransaction row in chronological) {
    if (row.isTest) {
      testLiters += row.volumeLiters;
    } else {
      saleLiters += row.volumeLiters;
    }
    if (!row.litersMatchMeterDelta) {
      final double delta = meterDeltaLiters(
        row.openingMeter,
        row.closingMeter,
      ).toDouble();
      findings.add(
        ShiftAuditFinding(
          kind: ShiftAuditKind.litersVsMeter,
          unitId: unitId,
          tokenNo: row.tokenNo,
          message:
              '${formatLedgerToken(row.tokenNo)} liters ${formatLiters(row.volumeLiters)} ≠ '
              'Closing − Opening ${formatLiters(delta)} '
              '(${formatMeterReading(row.closingMeter)} − ${formatMeterReading(row.openingMeter)}).',
        ),
      );
    }
  }

  for (int i = 1; i < chronological.length; i++) {
    final SaleTransaction previous = chronological[i - 1];
    final SaleTransaction current = chronological[i];
    if (metersMatchAtAuditScale(current.openingMeter, previous.closingMeter)) {
      continue;
    }
    findings.add(
      ShiftAuditFinding(
        kind: ShiftAuditKind.chainGap,
        unitId: unitId,
        tokenNo: current.tokenNo,
        previousTokenNo: previous.tokenNo,
        message:
            '${formatLedgerToken(current.tokenNo)} opening ${formatMeterReading(current.openingMeter)} ≠ '
            'previous ${formatLedgerToken(previous.tokenNo)} closing ${formatMeterReading(previous.closingMeter)}.',
      ),
    );
  }

  final double? shiftVolume = shiftVolumeLitersFor(
    summary: summary,
    unitId: unitId,
  );
  final int testFillCount = chronological.where((SaleTransaction row) {
    return row.isTest;
  }).length;
  if (shiftVolume != null &&
      !shiftVolumeMatchesSaleLiters(
        shiftVolumeLiters: shiftVolume,
        saleLiters: saleLiters,
        testLiters: testLiters,
      )) {
    findings.add(
      ShiftAuditFinding(
        kind: ShiftAuditKind.shiftVolume,
        unitId: unitId,
        message:
            'Shift Volume Dispensed ${formatLiters(shiftVolume)} ≠ '
            'commercial ${formatLiters(saleLiters)}'
            '${testFillCount == 0 ? '' : ' + test ${formatLiters(testLiters)}'}.',
      ),
    );
  }

  if (chronological.isNotEmpty) {
    final SaleTransaction first = chronological.first;
    final double? shiftOpening = summary.openingMeters[unitId];
    if (shiftOpening != null &&
        !metersMatchAtAuditScale(first.openingMeter, shiftOpening)) {
      findings.add(
        ShiftAuditFinding(
          kind: ShiftAuditKind.firstOpening,
          unitId: unitId,
          tokenNo: first.tokenNo,
          message:
              'First sale ${formatLedgerToken(first.tokenNo)} opening ${formatMeterReading(first.openingMeter)} ≠ '
              'shift opening ${formatMeterReading(shiftOpening)}.',
        ),
      );
    }
    final SaleTransaction last = chronological.last;
    final double? shiftClosing = summary.closingMeters[unitId];
    if (!summary.isLive &&
        shiftClosing != null &&
        !metersMatchAtAuditScale(last.closingMeter, shiftClosing)) {
      findings.add(
        ShiftAuditFinding(
          kind: ShiftAuditKind.lastClosing,
          unitId: unitId,
          tokenNo: last.tokenNo,
          message:
              'Last sale ${formatLedgerToken(last.tokenNo)} closing ${formatMeterReading(last.closingMeter)} ≠ '
              'shift closing ${formatMeterReading(shiftClosing)}.',
        ),
      );
    }
  }

  return ShiftUnitAudit(
    unitId: unitId,
    chronological: chronological,
    findings: findings,
    saleLiters: saleLiters,
    testLiters: testLiters,
    shiftVolumeLiters: shiftVolume,
  );
}
