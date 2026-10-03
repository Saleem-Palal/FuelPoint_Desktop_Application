import 'package:decimal/decimal.dart';

import '../../station/domain/dispenser_models.dart';
import '../../station/domain/fuel_precision.dart';
import '../../station/domain/ledger_rate_bands.dart';
import '../../station/domain/money_format.dart';
import '../../station/domain/shift_ledger_models.dart';
import '../../station/domain/shift_transaction_audit.dart';
import 'shift_models.dart';

class ShiftRateReadingRow {
  const ShiftRateReadingRow({
    required this.unitId,
    required this.opening,
    required this.closing,
    required this.dispensed,
    this.testLiters = 0,
    this.rate,
  });

  final int unitId;
  final double? rate;
  final double? opening;
  final double? closing;

  /// Meter closing minus opening. Includes test liters.
  final double? dispensed;

  /// Test liters inside this unit/rate row.
  final double testLiters;

  String get rateLabel {
    final double? value = rate;
    if (value == null) {
      return '-';
    }
    return formatTableRate(value);
  }

  /// Dispensed minus test liters. Null when the meter delta is unknown.
  double? get netVolume {
    final double? liters = dispensed;
    if (liters == null) {
      return null;
    }
    return liters - testLiters;
  }

  /// Whole rupees from rate times [netVolume]. Test liters are not priced.
  int? get amountPkr {
    final double? liters = netVolume;
    final double? unitRate = rate;
    if (liters == null || unitRate == null) {
      return null;
    }
    return roundRupees(parseDecimal(liters) * parseDecimal(unitRate));
  }
}

class ShiftUnitReading {
  const ShiftUnitReading({required this.unitId, required this.rows});

  final int unitId;
  final List<ShiftRateReadingRow> rows;
}

class ShiftUnitSaleGroup {
  const ShiftUnitSaleGroup({required this.unitId, required this.sales});

  final int unitId;
  final List<HelperSaleRecord> sales;
}

bool isShiftReportUnit(int unitId, {required bool showUnit5}) {
  if (isDirectSaleUnit(unitId)) {
    return false;
  }
  if (unitId == kOptionalDispenserUnitId && !showUnit5) {
    return false;
  }
  return true;
}

String shiftReportPaymentLabel(PaymentMethod payment) {
  switch (payment) {
    case PaymentMethod.cash:
      return 'Cash';
    case PaymentMethod.udhaar:
      return 'Udhr';
    case PaymentMethod.bankAccount:
    case PaymentMethod.easyPaisa:
      return 'ACC';
  }
}

/// Payment cell for a shift row. Waiting account sales keep a Pending mark.
String shiftSalePaymentLabel(HelperSaleRecord row, {bool short = false}) {
  if (row.isTest) {
    return 'Test';
  }
  final String base = short
      ? shiftReportPaymentLabel(row.payment)
      : row.payment.label;
  if (row.pendingAccountAmount > 0) {
    return '$base · Pending';
  }
  return base;
}

/// Account cell for a shift row. The shift Account total still uses
/// [HelperSaleRecord.accountTender], which leaves this hold out.
double shiftSaleAccountColumn(
  HelperSaleRecord row, {
  bool tenderFallback = false,
}) {
  if (!row.isTest && row.pendingAccountAmount > 0) {
    return row.pendingAccountAmount;
  }
  return tenderFallback ? row.accountTender : row.accountAmount;
}

String pdfSafeText(String value) {
  return value.replaceAll(
    RegExp(r'[\u2010-\u2015\u2212\uFE58\uFE63\uFF0D]'),
    '-',
  );
}

List<HelperSaleRecord> shiftReportDirectSales(List<HelperSaleRecord> sales) {
  final List<HelperSaleRecord> rows = sales
      .where((HelperSaleRecord row) => isDirectSaleUnit(row.unitId))
      .toList();
  rows.sort(compareShiftReportSales);
  return rows;
}

int compareShiftReportSales(HelperSaleRecord a, HelperSaleRecord b) {
  final int byUnit = a.unitId.compareTo(b.unitId);
  if (byUnit != 0) {
    return byUnit;
  }
  final int byTime = a.timestamp.compareTo(b.timestamp);
  if (byTime != 0) {
    return byTime;
  }
  return a.tokenNo.compareTo(b.tokenNo);
}

List<HelperSaleRecord> shiftReportSalesChronological(
  List<HelperSaleRecord> sales, {
  bool showUnit5 = false,
}) {
  final List<HelperSaleRecord> rows = sales
      .where(
        (HelperSaleRecord row) =>
            isShiftReportUnit(row.unitId, showUnit5: showUnit5),
      )
      .toList();
  rows.sort(compareShiftReportSales);
  return rows;
}

List<ShiftUnitSaleGroup> groupShiftReportSalesByUnit(
  List<HelperSaleRecord> sales, {
  bool showUnit5 = false,
}) {
  final List<HelperSaleRecord> sorted = shiftReportSalesChronological(
    sales,
    showUnit5: showUnit5,
  );
  final Map<int, List<HelperSaleRecord>> grouped =
      <int, List<HelperSaleRecord>>{};
  for (final HelperSaleRecord row in sorted) {
    grouped.putIfAbsent(row.unitId, () => <HelperSaleRecord>[]).add(row);
  }
  final List<int> unitIds = grouped.keys.toList()..sort();
  return <ShiftUnitSaleGroup>[
    for (final int id in unitIds)
      ShiftUnitSaleGroup(unitId: id, sales: grouped[id]!),
  ];
}

List<ShiftUnitReading> buildShiftReportReadings({
  required OperatorShiftRecord shift,
  required List<HelperSaleRecord> sales,
  bool showUnit5 = false,
}) {
  final List<HelperSaleRecord> sorted = shiftReportSalesChronological(
    sales,
    showUnit5: showUnit5,
  );
  final Set<int> unitIds = <int>{};
  for (final int id in shift.openingMeters.keys) {
    if (isShiftReportUnit(id, showUnit5: showUnit5)) {
      unitIds.add(id);
    }
  }
  for (final int id in shift.closingMeters.keys) {
    if (isShiftReportUnit(id, showUnit5: showUnit5)) {
      unitIds.add(id);
    }
  }
  for (final HelperSaleRecord row in sorted) {
    unitIds.add(row.unitId);
  }
  final List<int> ordered = unitIds.toList()..sort();
  return <ShiftUnitReading>[
    for (final int unitId in ordered)
      ShiftUnitReading(
        unitId: unitId,
        rows: _readingRowsForUnit(
          unitId: unitId,
          shift: shift,
          sales: sorted
              .where((HelperSaleRecord row) => row.unitId == unitId)
              .toList(),
        ),
      ),
  ];
}

List<ShiftRateReadingRow> _readingRowsForUnit({
  required int unitId,
  required OperatorShiftRecord shift,
  required List<HelperSaleRecord> sales,
}) {
  final double? shiftOpening = shift.openingMeters[unitId];
  final double? shiftClosing = shift.closingMeters[unitId];
  if (sales.isEmpty) {
    return <ShiftRateReadingRow>[
      ShiftRateReadingRow(
        unitId: unitId,
        opening: shiftOpening,
        closing: shiftClosing,
        dispensed: _meterDispensed(shiftOpening, shiftClosing),
      ),
    ];
  }

  final List<List<HelperSaleRecord>> runs = <List<HelperSaleRecord>>[];
  for (final HelperSaleRecord sale in sales) {
    if (runs.isEmpty) {
      runs.add(<HelperSaleRecord>[sale]);
      continue;
    }
    final HelperSaleRecord previous = runs.last.last;
    if (displayedRateKey(previous.rate) == displayedRateKey(sale.rate)) {
      runs.last.add(sale);
    } else {
      runs.add(<HelperSaleRecord>[sale]);
    }
  }

  if (runs.length == 1) {
    final HelperSaleRecord first = sales.first;
    final HelperSaleRecord last = sales.last;
    final double opening = shiftOpening ?? first.openingMeter;
    final double closing = shiftClosing ?? last.closingMeter;
    return <ShiftRateReadingRow>[
      ShiftRateReadingRow(
        unitId: unitId,
        rate: first.rate,
        opening: opening,
        closing: closing,
        dispensed: _meterDispensed(opening, closing),
        testLiters: _testLitersIn(sales),
      ),
    ];
  }

  return <ShiftRateReadingRow>[
    for (int i = 0; i < runs.length; i++)
      _rateRunRow(
        unitId: unitId,
        run: runs[i],
        isFirst: i == 0,
        isLast: i == runs.length - 1,
        shiftOpening: shiftOpening,
        shiftClosing: shiftClosing,
      ),
  ];
}

ShiftRateReadingRow _rateRunRow({
  required int unitId,
  required List<HelperSaleRecord> run,
  required bool isFirst,
  required bool isLast,
  required double? shiftOpening,
  required double? shiftClosing,
}) {
  final HelperSaleRecord first = run.first;
  final HelperSaleRecord last = run.last;
  final double opening = isFirst
      ? (shiftOpening ?? first.openingMeter)
      : first.openingMeter;
  final double closing = isLast
      ? (shiftClosing ?? last.closingMeter)
      : last.closingMeter;
  return ShiftRateReadingRow(
    unitId: unitId,
    rate: first.rate,
    opening: opening,
    closing: closing,
    dispensed: _meterDispensed(opening, closing),
    testLiters: _testLitersIn(run),
  );
}

double _testLitersIn(List<HelperSaleRecord> sales) {
  double total = 0;
  for (final HelperSaleRecord row in sales) {
    if (row.isTest) {
      total += row.volumeLiters;
    }
  }
  return total;
}

double? _meterDispensed(double? opening, double? closing) {
  if (opening == null || closing == null) {
    return null;
  }
  return meterDeltaLiters(opening, closing).toDouble();
}

SaleTransaction saleTransactionForShiftReport(HelperSaleRecord row) {
  return SaleTransaction(
    tokenNo: row.tokenNo,
    unitId: row.unitId,
    fuelType: row.fuelType,
    amountPkr: row.amountPkr,
    volumeLiters: row.volumeLiters,
    rate: row.rate,
    meterCount: row.closingMeter.truncate(),
    timestamp: row.timestamp,
    openingMeter: row.openingMeter,
    closingMeter: row.closingMeter,
    customerName: row.customerName,
    vehicleNo: row.vehicleNo,
    payment: row.payment,
    cashierName: row.cashierName,
    helperName: row.helperName,
    shiftId: row.shiftId,
    espTxId: row.espTxId,
    cashAmount: row.cashAmount,
    accountAmount: row.accountAmount,
    pendingAccountAmount: row.pendingAccountAmount,
    edited: row.edited,
    isTest: row.isTest,
    drumQty: row.drumQty,
  );
}

ShiftLedgerSummary shiftReportLedgerSummary(OperatorShiftRecord shift) {
  return ShiftLedgerSummary(
    shiftId: shift.shiftId,
    operatorId: shift.operatorId,
    operatorName: shift.operatorName,
    role: shift.role,
    startTime: shift.startTime,
    endTime: shift.endTime,
    status: shift.status,
    totalTransactions: 0,
    totalShiftPkr: 0,
    totalShiftLiters: 0,
    openingMeters: shift.openingMeters,
    closingMeters: shift.closingMeters,
  );
}

List<String> shiftReportAuditLines({
  required OperatorShiftRecord shift,
  required List<HelperSaleRecord> sales,
  bool showUnit5 = false,
}) {
  final ShiftLedgerSummary summary = shiftReportLedgerSummary(shift);
  final List<SaleTransaction> rows = shiftReportSalesChronological(
    sales,
    showUnit5: showUnit5,
  ).map(saleTransactionForShiftReport).toList();
  final ShiftTransactionAudit audit = auditShiftTransactions(
    rows: rows,
    summary: summary,
  );
  final Map<int, ShiftUnitAudit> byUnit = <int, ShiftUnitAudit>{
    for (final ShiftUnitAudit unit in audit.units) unit.unitId: unit,
  };
  final Set<int> unitIds = Set<int>.from(byUnit.keys);
  for (final int id in <int>{
    ...shift.openingMeters.keys,
    ...shift.closingMeters.keys,
  }) {
    if (!isShiftReportUnit(id, showUnit5: showUnit5) ||
        byUnit.containsKey(id)) {
      continue;
    }
    final double? volume = shiftVolumeLitersFor(summary: summary, unitId: id);
    if (volume != null && !metersMatchAtAuditScale(volume, 0)) {
      unitIds.add(id);
    }
  }
  final List<int> ordered = unitIds.toList()..sort();
  return <String>[
    for (final int id in ordered)
      byUnit.containsKey(id)
          ? shiftAuditPdfLine(byUnit[id]!)
          : _emptyUnitVolumeMismatchLine(
              unitId: id,
              volume: shiftVolumeLitersFor(summary: summary, unitId: id) ?? 0,
            ),
  ];
}

String shiftAuditPdfLine(ShiftUnitAudit unit) {
  if (unit.ok) {
    return 'UNIT ${unit.unitId}: PASS';
  }
  final List<String> parts = <String>[];
  for (final ShiftAuditFinding finding in unit.findings) {
    if (finding.kind == ShiftAuditKind.shiftVolume) {
      parts.add(shiftVolumeMismatchCopy(unit));
      continue;
    }
    parts.add(finding.message);
  }
  return 'UNIT ${unit.unitId}: MISMATCH - ${parts.join('; ')}';
}

String shiftVolumeMismatchCopy(ShiftUnitAudit unit) {
  final double meter = unit.shiftVolumeLiters ?? 0;
  final double ledger = unit.saleLiters + unit.testLiters;
  return _volumeDeltaCopy(meter: meter, ledger: ledger);
}

String _emptyUnitVolumeMismatchLine({
  required int unitId,
  required double volume,
}) {
  return 'UNIT $unitId: MISMATCH - ${_volumeDeltaCopy(meter: volume, ledger: 0)}';
}

String _volumeDeltaCopy({required double meter, required double ledger}) {
  final Decimal meterDec = truncateMeterCheck(meter);
  final Decimal ledgerDec = truncateMeterCheck(ledger);
  final double delta = (meterDec - ledgerDec).abs().toDouble();
  final String amount = formatTableLiters(delta);
  if (meterDec > ledgerDec) {
    return 'Meter volume exceeds ledger transactions by $amount L';
  }
  return 'Ledger transactions exceed meter volume by $amount L';
}
