import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/dispensr_theme.dart';
import '../../../features/customer/domain/customer_models.dart';
import '../../../features/station/domain/fuel_precision.dart';
import '../../../features/station/domain/money_format.dart';

enum _SettlePill { cash, account }

enum _SettleRail { bank, easyPaisa }

class SettleBillDraft {
  const SettleBillDraft({
    required this.amountPkr,
    required this.paymentMode,
    required this.cashAmountPkr,
    required this.accountAmountPkr,
    required this.notes,
  });

  final double amountPkr;
  final SettlementPaymentMode paymentMode;
  final double cashAmountPkr;
  final double accountAmountPkr;
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
  late final TextEditingController _cashNow;
  late final TextEditingController _accountNow;
  late final TextEditingController _notes;
  _SettlePill _pill = _SettlePill.cash;
  _SettleRail _rail = _SettleRail.bank;
  bool _saving = false;

  double get _outstanding {
    final double value = widget.account.outstanding;
    return value < 0 ? 0 : value;
  }

  @override
  void initState() {
    super.initState();
    final String full = _outstanding.round().toString();
    _amount = TextEditingController(text: full);
    _cashNow = TextEditingController(text: '0');
    _accountNow = TextEditingController(text: full);
    _notes = TextEditingController();
  }

  @override
  void dispose() {
    _amount.dispose();
    _cashNow.dispose();
    _accountNow.dispose();
    _notes.dispose();
    super.dispose();
  }

  double _parse(TextEditingController controller) {
    return double.tryParse(controller.text.trim()) ?? 0;
  }

  void _seedAccountSplit() {
    _cashNow.text = '0';
    _accountNow.text = _outstanding.round().toString();
  }

  void _confirm() {
    if (_saving) {
      return;
    }
    final double outstanding = _outstanding;
    final double cash;
    final double account;
    final SettlementPaymentMode mode;
    if (_pill == _SettlePill.cash) {
      cash = _parse(_amount);
      account = 0;
      mode = SettlementPaymentMode.cash;
    } else {
      cash = _parse(_cashNow);
      account = _parse(_accountNow);
      mode = _rail == _SettleRail.bank
          ? SettlementPaymentMode.bankTransfer
          : SettlementPaymentMode.easyPaisa;
    }
    final double total = cash + account;
    if (total <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a cash and/or account amount')),
      );
      return;
    }
    if (roundRupees(total) > roundRupees(outstanding)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paid amount cannot exceed outstanding')),
      );
      return;
    }
    setState(() {
      _saving = true;
    });
    Navigator.of(context).pop(
      SettleBillDraft(
        amountPkr: total,
        paymentMode: mode,
        cashAmountPkr: cash,
        accountAmountPkr: account,
        notes: _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final CustomerProfile profile = widget.account.profile;
    final double outstanding = _outstanding;
    final double cash = _pill == _SettlePill.cash
        ? _parse(_amount)
        : _parse(_cashNow);
    final double account = _pill == _SettlePill.account
        ? _parse(_accountNow)
        : 0;
    final double paid = cash + account;
    final double remaining = outstanding - paid;
    final bool partial = remaining > 0.004 && paid > 0;
    return Dialog(
      backgroundColor: tokens.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius20),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
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
                      formatPkrStatement(outstanding),
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                        color: widget.account.hasDebt
                            ? tokens.bad
                            : tokens.good,
                      ),
                    ),
                    if (paid > 0) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        partial
                            ? 'After this payment  ${formatPkrStatement(remaining)} remaining (partial)'
                            : 'This payment clears the bill',
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 11,
                          color: partial ? tokens.warn : tokens.good,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'PAYMENT METHOD',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w700,
                  fontSize: 9,
                  letterSpacing: 0.8,
                  color: tokens.inkMuted,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  Expanded(
                    child: DsPillButton(
                      label: 'Cash',
                      icon: Icons.payments_outlined,
                      compact: true,
                      variant: _pill == _SettlePill.cash
                          ? DsPillVariant.coral
                          : DsPillVariant.outline,
                      onPressed: () {
                        setState(() {
                          _pill = _SettlePill.cash;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DsPillButton(
                      label: 'Account',
                      icon: Icons.account_balance_outlined,
                      compact: true,
                      variant: _pill == _SettlePill.account
                          ? DsPillVariant.coral
                          : DsPillVariant.outline,
                      onPressed: () {
                        setState(() {
                          _pill = _SettlePill.account;
                          _seedAccountSplit();
                        });
                      },
                    ),
                  ),
                ],
              ),
              if (_pill == _SettlePill.account) ...<Widget>[
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: DsPillButton(
                        label: 'Bank',
                        icon: Icons.account_balance,
                        compact: true,
                        variant: _rail == _SettleRail.bank
                            ? DsPillVariant.coral
                            : DsPillVariant.outline,
                        onPressed: () {
                          setState(() {
                            _rail = _SettleRail.bank;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DsPillButton(
                        label: 'EasyPaisa',
                        icon: Icons.phone_android_outlined,
                        compact: true,
                        variant: _rail == _SettleRail.easyPaisa
                            ? DsPillVariant.coral
                            : DsPillVariant.outline,
                        onPressed: () {
                          setState(() {
                            _rail = _SettleRail.easyPaisa;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _cashNow,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: <TextInputFormatter>[
                          _decimalFormatter,
                        ],
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 13,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Cash Now (PKR)',
                          hintText: '0',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _accountNow,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: <TextInputFormatter>[
                          _decimalFormatter,
                        ],
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 13,
                        ),
                        decoration: InputDecoration(
                          labelText: _rail == _SettleRail.bank
                              ? 'Bank (PKR)'
                              : 'EasyPaisa (PKR)',
                          hintText: '0',
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...<Widget>[
                const SizedBox(height: 10),
                TextField(
                  controller: _amount,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: <TextInputFormatter>[_decimalFormatter],
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontFamily: 'Roboto', fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Amount Paid (PKR)',
                    hintText: '0.00',
                    suffixText: 'Rs',
                  ),
                ),
              ],
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
                      label: partial
                          ? 'Confirm Partial'
                          : 'Confirm Settlement',
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
