import 'package:flutter/material.dart';

import '../../../core/theme/dispensr_theme.dart';
import '../../../features/shift/data/shift_summary_export.dart';
import '../../../features/shift/domain/shift_models.dart';
import '../../../features/station/domain/money_format.dart';

Future<void> showShiftSummaryDialog(
  BuildContext context, {
  required ShiftSummary summary,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return ShiftSummaryDialog(summary: summary);
    },
  );
}

class ShiftSummaryDialog extends StatefulWidget {
  const ShiftSummaryDialog({super.key, required this.summary});

  final ShiftSummary summary;

  @override
  State<ShiftSummaryDialog> createState() => _ShiftSummaryDialogState();
}

class _ShiftSummaryDialogState extends State<ShiftSummaryDialog> {
  bool _busy = false;

  Future<void> _print() async {
    setState(() {
      _busy = true;
    });
    try {
      await ShiftSummaryExport.instance.printPdf(widget.summary);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not print PDF: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _whatsApp() async {
    setState(() {
      _busy = true;
    });
    try {
      final bool opened = await ShiftSummaryExport.instance.shareWhatsApp(
        widget.summary,
      );
      if (!mounted) {
        return;
      }
      if (!opened) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WhatsApp is not available on this PC')),
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not share on WhatsApp: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final ManagerShiftRecord shift = widget.summary.shift;
    final ShiftWindowMetrics metrics = widget.summary.metrics;
    final Color discColor = shift.discrepancy < 0
        ? tokens.bad
        : shift.discrepancy > 0
        ? tokens.good
        : tokens.ink;

    return AlertDialog(
      backgroundColor: tokens.card,
      surfaceTintColor: tokens.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius20),
        side: BorderSide(color: tokens.line),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Row(
        children: <Widget>[
          Icon(Icons.summarize_outlined, size: 20, color: tokens.coral),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Shift Summary',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: tokens.ink,
                  ),
                ),
                Text(
                  '${shift.shiftId} closed',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                    color: tokens.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _SummaryRow(label: 'Manager', value: shift.managerName),
            _SummaryRow(label: 'Role', value: managerRoleLabel(shift.role)),
            _SummaryRow(label: 'Start', value: formatDateTime(shift.startTime)),
            _SummaryRow(
              label: 'End',
              value: shift.endTime == null
                  ? '—'
                  : formatDateTime(shift.endTime!),
            ),
            _SummaryRow(
              label: 'Duration',
              value: formatShiftDuration(widget.summary.duration),
            ),
            _SummaryRow(
              label: 'Token range',
              value: shiftTokenRangeLabel(metrics),
            ),
            _SummaryRow(
              label: 'Volume sold',
              value: formatLiters(metrics.totalLiters),
            ),
            const SizedBox(height: 8),
            Divider(color: tokens.line, height: 1),
            const SizedBox(height: 8),
            _SummaryRow(
              label: 'Fuel cash sales',
              value: formatPkr(metrics.fuelCashSales),
            ),
            _SummaryRow(
              label: 'Udhaar issued',
              value: formatPkr(metrics.udhaarSales),
            ),
            _SummaryRow(
              label: 'Account payments',
              value: formatPkr(metrics.accountSales),
            ),
            _SummaryRow(
              label: 'Udhaar recovery',
              value: formatPkr(metrics.udhaarRecoveryTotal),
            ),
            _SummaryRow(
              label: 'Expected cash',
              value: formatPkr(shift.expectedCash),
            ),
            _SummaryRow(
              label: 'Actual cash',
              value: shift.actualCash == null
                  ? '—'
                  : formatPkr(shift.actualCash!),
            ),
            _SummaryRow(
              label: 'Discrepancy',
              value: formatSignedPkr(shift.discrepancy),
              valueColor: discColor,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: DsPillButton(
                    label: _busy ? 'Working…' : 'Download / Print PDF',
                    icon: Icons.picture_as_pdf_outlined,
                    compact: true,
                    onPressed: _busy ? null : _print,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DsPillButton(
                    label: 'Share via WhatsApp',
                    icon: Icons.chat_outlined,
                    variant: DsPillVariant.good,
                    compact: true,
                    onPressed: _busy ? null : _whatsApp,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DsPillButton(
              label: 'Done',
              variant: DsPillVariant.outline,
              compact: true,
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 140,
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w700,
                fontSize: 9,
                letterSpacing: 0.8,
                color: tokens.inkMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: valueColor ?? tokens.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
