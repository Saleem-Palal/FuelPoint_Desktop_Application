import 'package:flutter/material.dart';

import '../../../core/theme/dispensr_theme.dart';
import '../../../features/station/domain/dispenser_models.dart';
import '../../../features/station/domain/money_format.dart';
import '../../../features/station/domain/shift_ledger_models.dart';
import '../../../features/station/domain/shift_transaction_audit.dart';

Future<void> showShiftTransactionAuditDialog(
  BuildContext context, {
  required ShiftLedgerSummary summary,
  required List<SaleTransaction> rows,
  int? unitId,
}) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return ShiftTransactionAuditDialog(
        summary: summary,
        rows: rows,
        unitId: unitId,
      );
    },
  );
}

class ShiftTransactionAuditDialog extends StatelessWidget {
  const ShiftTransactionAuditDialog({
    super.key,
    required this.summary,
    required this.rows,
    this.unitId,
  });

  final ShiftLedgerSummary summary;
  final List<SaleTransaction> rows;
  final int? unitId;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final ShiftTransactionAudit audit = auditShiftTransactions(
      rows: rows,
      summary: summary,
      unitId: unitId,
    );

    return AlertDialog(
      backgroundColor: tokens.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius20),
        side: BorderSide(color: tokens.line),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      title: Row(
        children: <Widget>[
          Icon(Icons.fact_check_outlined, size: 20, color: tokens.coral),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Shift transaction audit · ${summary.shiftId}',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: tokens.ink,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 720,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 520),
          child: audit.units.isEmpty
              ? Text(
                  'No sales in this shift to audit.',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 13,
                    color: tokens.inkMuted,
                  ),
                )
              : ListView(
                  primary: false,
                  children: <Widget>[
                    Text(
                      audit.ok
                          ? 'All ${audit.units.length} unit${audit.units.length == 1 ? '' : 's'} passed.'
                          : '${audit.findingCount} mismatch${audit.findingCount == 1 ? '' : 'es'} found.',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: audit.ok ? tokens.good : tokens.bad,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final ShiftUnitAudit unit in audit.units) ...<Widget>[
                      _UnitAuditSection(unit: unit),
                      const SizedBox(height: 14),
                    ],
                  ],
                ),
        ),
      ),
      actions: <Widget>[
        DsPillButton(
          label: 'Close',
          compact: true,
          variant: DsPillVariant.outline,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _UnitAuditSection extends StatelessWidget {
  const _UnitAuditSection({required this.unit});

  final ShiftUnitAudit unit;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final Set<int> flaggedTokens = <int>{
      for (final ShiftAuditFinding finding in unit.findings)
        if (finding.tokenNo != null) finding.tokenNo!,
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.canvas,
        borderRadius: BorderRadius.circular(tokens.radius12),
        border: Border.all(color: tokens.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                formatUnitLabel(unit.unitId),
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: tokens.ink,
                ),
              ),
              const Spacer(),
              Text(
                unit.ok ? 'Pass' : 'Mismatch',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: unit.ok ? tokens.good : tokens.bad,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _volumeSummary(unit),
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 12,
              color: tokens.inkMuted,
            ),
          ),
          if (unit.findings.isEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              unit.testFillCount == 0
                  ? 'Liters match Closing − Opening, and opening/closing readings chain without gaps.'
                  : 'Readings chain including test fills. Test liters are left out of KPI volume.',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 12,
                color: tokens.ink,
              ),
            ),
          ] else ...<Widget>[
            const SizedBox(height: 8),
            for (final ShiftAuditFinding finding in unit.findings)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  finding.message,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: tokens.bad,
                  ),
                ),
              ),
          ],
          if (unit.chronological.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Table(
              columnWidths: const <int, TableColumnWidth>{
                0: FlexColumnWidth(1.2),
                1: FlexColumnWidth(1.1),
                2: FlexColumnWidth(1.1),
                3: FlexColumnWidth(1.0),
              },
              children: <TableRow>[
                TableRow(
                  children: <Widget>[
                    _cell(tokens, 'TOKEN', muted: true, header: true),
                    _cell(tokens, 'OPENING', muted: true, header: true),
                    _cell(tokens, 'CLOSING', muted: true, header: true),
                    _cell(tokens, 'LITERS', muted: true, header: true),
                  ],
                ),
                for (final SaleTransaction row in unit.chronological)
                  TableRow(
                    decoration: BoxDecoration(
                      color: flaggedTokens.contains(row.tokenNo)
                          ? tokens.bad.withValues(alpha: 0.10)
                          : Colors.transparent,
                    ),
                    children: <Widget>[
                      _cell(
                        tokens,
                        '${formatLedgerToken(row.tokenNo)}'
                        '${row.isTest ? ' TEST' : ''}',
                      ),
                      _cell(tokens, formatMeterReading(row.openingMeter)),
                      _cell(tokens, formatMeterReading(row.closingMeter)),
                      _cell(tokens, formatTableLiters(row.volumeLiters)),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _cell(
    DispensrTokens tokens,
    String text, {
    bool muted = false,
    bool header = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Roboto',
          fontWeight: header ? FontWeight.w700 : FontWeight.w500,
          fontSize: header ? 10 : 12,
          letterSpacing: header ? 0.6 : 0,
          color: muted ? tokens.inkMuted : tokens.ink,
        ),
      ),
    );
  }
}

String _volumeSummary(ShiftUnitAudit unit) {
  final String fills = unit.testFillCount == 0
      ? 'Pump fills ${formatLiters(unit.saleLiters)}'
      : 'Pump fills ${formatLiters(unit.saleLiters)} '
            '(including ${unit.testFillCount} test)';
  if (unit.shiftVolumeLiters == null) {
    return fills;
  }
  return '$fills · Shift Volume Dispensed ${formatLiters(unit.shiftVolumeLiters!)}';
}
