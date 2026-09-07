import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/dispensr_theme.dart';
import '../../../features/shift/domain/shift_models.dart';
import '../../../features/station/domain/money_format.dart';

class ShiftSettlementResult {
  const ShiftSettlementResult({required this.actualCash, required this.notes});

  final double actualCash;
  final String notes;
}

Future<ShiftSettlementResult?> showShiftSettlementDialog(
  BuildContext context, {
  required ManagerShiftRecord shift,
  required ShiftWindowMetrics metrics,
}) {
  return showDialog<ShiftSettlementResult>(
    context: context,
    builder: (BuildContext context) {
      return ShiftSettlementDialog(shift: shift, metrics: metrics);
    },
  );
}

class ShiftSettlementDialog extends StatefulWidget {
  const ShiftSettlementDialog({
    super.key,
    required this.shift,
    required this.metrics,
  });

  final ManagerShiftRecord shift;
  final ShiftWindowMetrics metrics;

  @override
  State<ShiftSettlementDialog> createState() => _ShiftSettlementDialogState();
}

class _ShiftSettlementDialogState extends State<ShiftSettlementDialog> {
  static final FilteringTextInputFormatter _decimalFormatter =
      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'));

  final TextEditingController _actual = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _actual.addListener(_onChanged);
  }

  @override
  void dispose() {
    _actual
      ..removeListener(_onChanged)
      ..dispose();
    _notes.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  double? get _actualCash {
    final String raw = _actual.text.trim();
    if (raw.isEmpty) {
      return null;
    }
    return double.tryParse(raw);
  }

  double? get _discrepancy {
    final double? actual = _actualCash;
    if (actual == null) {
      return null;
    }
    return actual - widget.metrics.expectedCashInHand;
  }

  bool get _canConfirm {
    final double? actual = _actualCash;
    return actual != null && actual >= 0;
  }

  void _confirm() {
    final double? actual = _actualCash;
    if (actual == null) {
      return;
    }
    Navigator.of(
      context,
    ).pop(ShiftSettlementResult(actualCash: actual, notes: _notes.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final double? discrepancy = _discrepancy;
    final Color discrepancyColor = discrepancy == null
        ? tokens.inkMuted
        : discrepancy < 0
        ? tokens.bad
        : discrepancy > 0
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
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 20,
            color: tokens.coral,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'End Shift & Reconcile',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: tokens.ink,
                  ),
                ),
                Text(
                  '${widget.shift.shiftId} · ${widget.shift.managerName}',
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
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _ReadOnlyField(
                label: 'Expected Cash in Hand (PKR)',
                value: formatPkr(widget.metrics.expectedCashInHand),
                hint: 'Fuel cash sales + Udhaar recovery',
              ),
              const SizedBox(height: 10),
              _ReadOnlyField(
                label: 'Udhaar Recovery (PKR)',
                value: formatPkr(widget.metrics.udhaarRecoveryTotal),
                hint: 'Cash settlements this shift',
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: _ReadOnlyField(
                      label: 'Udhaar Amount (PKR)',
                      value: formatPkr(widget.metrics.udhaarSales),
                      hint: 'Credit sales',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ReadOnlyField(
                      label: 'Account Amount (PKR)',
                      value: formatPkr(widget.metrics.accountSales),
                      hint: 'Bank / EasyPaisa',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Actual Physical Cash Collected (PKR)',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: tokens.inkMuted,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _actual,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: <TextInputFormatter>[_decimalFormatter],
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: tokens.ink,
                ),
                decoration: const InputDecoration(
                  hintText: '0.00',
                  suffixText: 'Rs',
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: discrepancyColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(tokens.radius12),
                  border: Border.all(
                    color: discrepancyColor.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Text(
                      'DISCREPANCY',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.w700,
                        fontSize: 9,
                        letterSpacing: 0.8,
                        color: tokens.inkMuted,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      discrepancy == null ? '—' : formatSignedPkr(discrepancy),
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: discrepancyColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Notes / Handover',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: tokens.inkMuted,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _notes,
                maxLines: 3,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                  color: tokens.ink,
                ),
                decoration: const InputDecoration(
                  hintText: 'Handover notes, till remarks…',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: DsPillButton(
                label: 'Cancel',
                variant: DsPillVariant.outline,
                compact: true,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DsPillButton(
                label: 'Confirm & Close Shift',
                variant: DsPillVariant.coral,
                compact: true,
                icon: Icons.check,
                onPressed: _canConfirm ? _confirm : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.label, required this.value, this.hint});

  final String label;
  final String value;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w600,
            fontSize: 12,
            color: tokens.inkMuted,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: tokens.line.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(tokens.radius12),
            border: Border.all(color: tokens.line),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: tokens.inkMuted,
                  ),
                ),
              ),
              Text(
                'Rs',
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
        const SizedBox(height: 4),
        SizedBox(
          height: 16,
          child: hint == null
              ? null
              : Text(
                  hint!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w500,
                    fontSize: 11,
                    color: tokens.inkMuted,
                  ),
                ),
        ),
      ],
    );
  }
}
