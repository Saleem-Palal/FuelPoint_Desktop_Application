import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/dispensr_theme.dart';
import '../../../features/customer/domain/customer_models.dart';
import '../../../features/station/domain/money_format.dart';

class SettleBillDraft {
  const SettleBillDraft({required this.amountPkr, required this.notes});

  final double amountPkr;
  final String notes;
}

Future<SettleBillDraft?> showSettleBillDialog(
  BuildContext context, {
  required CustomerAccount account,
}) {
  return showDialog<SettleBillDraft>(
    context: context,
    builder: (BuildContext context) {
      return _SettleBillDialog(account: account);
    },
  );
}

class _SettleBillDialog extends StatefulWidget {
  const _SettleBillDialog({required this.account});

  final CustomerAccount account;

  @override
  State<_SettleBillDialog> createState() => _SettleBillDialogState();
}

class _SettleBillDialogState extends State<_SettleBillDialog> {
  static final FilteringTextInputFormatter _decimalFormatter =
      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'));

  late final TextEditingController _amount;
  late final TextEditingController _notes;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final double outstanding = widget.account.outstanding < 0
        ? 0
        : widget.account.outstanding;
    _amount = TextEditingController(text: outstanding.round().toString());
    _notes = TextEditingController();
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _confirm() {
    if (_saving) {
      return;
    }
    final double? value = double.tryParse(_amount.text.trim());
    if (value == null || value <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount paid')),
      );
      return;
    }
    setState(() {
      _saving = true;
    });
    Navigator.of(context).pop(
      SettleBillDraft(amountPkr: value, notes: _notes.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final CustomerProfile profile = widget.account.profile;
    return Dialog(
      backgroundColor: tokens.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius20),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Settle Bill',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: tokens.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${profile.id}  ·  ${profile.name}',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 12,
                  color: tokens.inkMuted,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: tokens.canvas,
                  borderRadius: BorderRadius.circular(tokens.radius12),
                  border: Border.all(color: tokens.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'CURRENT OUTSTANDING',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.w700,
                        fontSize: 9,
                        letterSpacing: 0.8,
                        color: tokens.inkMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatPkrStatement(widget.account.outstanding),
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                        color: widget.account.hasDebt
                            ? tokens.bad
                            : tokens.good,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: <TextInputFormatter>[_decimalFormatter],
                style: const TextStyle(fontFamily: 'Roboto', fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Amount Paid (PKR)',
                  hintText: '0.00',
                  suffixText: 'Rs',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _notes,
                maxLines: 2,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _confirm(),
                style: const TextStyle(fontFamily: 'Roboto', fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Notes / Reference',
                  hintText: 'Optional slip no. or remark',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: DsPillButton(
                      label: 'Cancel',
                      variant: DsPillVariant.outline,
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DsPillButton(
                      label: 'Confirm Settlement',
                      onPressed: _saving ? null : _confirm,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
