import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/dispensr_theme.dart';
import '../../../features/station/domain/dispenser_models.dart';
import '../../../features/station/domain/fuel_precision.dart';
import '../../../features/station/domain/money_format.dart';
import '../../../features/station/presentation/station_providers.dart';
import 'Services/receipt_preview_widget.dart';

class PendingAccountBanner extends ConsumerWidget {
  const PendingAccountBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<SaleTransaction>> pending = ref.watch(
      pendingAccountSalesProvider,
    );
    return pending.when(
      data: (List<SaleTransaction> rows) {
        if (rows.isEmpty) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            children: <Widget>[
              for (final SaleTransaction row in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _PendingAccountCard(txn: row),
                ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (Object error, StackTrace stack) => const _PendingLoadError(),
    );
  }
}

class _PendingLoadError extends StatelessWidget {
  const _PendingLoadError();

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: tokens.bad.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(tokens.radius20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(tokens.radius20),
            border: Border.all(color: tokens.bad.withValues(alpha: 0.55)),
          ),
          child: Text(
            'Could not load pending account transfers.',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: tokens.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingAccountCard extends ConsumerWidget {
  const _PendingAccountCard({required this.txn});

  final SaleTransaction txn;

  Future<void> _openConfirm(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return _PendingAccountDialog(txn: txn);
      },
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Account confirmed for ${formatTokenNo(txn.tokenNo)}'),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Material(
      color: tokens.warn.withValues(alpha: 0.12),
      elevation: 6,
      shadowColor: tokens.ink.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(tokens.radius20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(tokens.radius20),
          border: Border.all(color: tokens.warn.withValues(alpha: 0.55)),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.hourglass_top_rounded, color: tokens.warn, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Wrap(
                spacing: 18,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  _Fact(
                    label: 'Token #',
                    value: formatTokenNo(txn.tokenNo),
                    tokens: tokens,
                  ),
                  _Fact(
                    label: 'DateTime',
                    value: formatDateTime(txn.timestamp),
                    tokens: tokens,
                  ),
                  _Fact(
                    label: 'Vehicle No',
                    value: displayVehicleNo(txn.vehicleNo),
                    tokens: tokens,
                  ),
                  _Fact(
                    label: 'Liters',
                    value: formatLiters(txn.volumeLiters),
                    tokens: tokens,
                  ),
                  _Fact(
                    label: 'Rate',
                    value: formatAverageRate(txn.rate),
                    tokens: tokens,
                  ),
                  _Fact(
                    label: 'Amount',
                    value: formatPkr(txn.amountPkr),
                    tokens: tokens,
                  ),
                  _Fact(
                    label: 'Cash Paid',
                    value: formatPkr(txn.cashAmount),
                    tokens: tokens,
                  ),
                  _Fact(
                    label: 'Pending Account Amount',
                    value: formatPkr(txn.pendingAccountAmount),
                    tokens: tokens,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: () {
                unawaited(_openConfirm(context, ref));
              },
              style: FilledButton.styleFrom(
                backgroundColor: tokens.coral,
                foregroundColor: tokens.card,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
              child: const Text(
                'Confirm / Update',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, required this.tokens});

  final String label;
  final String value;
  final DispensrTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w600,
            fontSize: 10,
            letterSpacing: 0.4,
            color: tokens.inkMuted,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: tokens.ink,
          ),
        ),
      ],
    );
  }
}

class _PendingAccountDialog extends ConsumerStatefulWidget {
  const _PendingAccountDialog({required this.txn});

  final SaleTransaction txn;

  @override
  ConsumerState<_PendingAccountDialog> createState() =>
      _PendingAccountDialogState();
}

class _PendingAccountDialogState extends ConsumerState<_PendingAccountDialog> {
  late final TextEditingController _cash;
  late final TextEditingController _account;
  bool _syncing = false;
  bool _busy = false;

  int get _sale => roundRupees(widget.txn.amountPkr);

  @override
  void initState() {
    super.initState();
    final int cash = roundRupees(widget.txn.cashAmount).clamp(0, _sale);
    final int account = (_sale - cash);
    _cash = TextEditingController(text: cash == 0 ? '' : '$cash');
    _account = TextEditingController(text: account == 0 ? '' : '$account');
  }

  @override
  void dispose() {
    _cash.dispose();
    _account.dispose();
    super.dispose();
  }

  void _setField(TextEditingController controller, int rupees) {
    final String next = rupees <= 0 ? '' : '$rupees';
    if (controller.text == next) {
      return;
    }
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  int _parsed(TextEditingController controller) {
    return (int.tryParse(controller.text.trim()) ?? 0).clamp(0, _sale);
  }

  void _onCashChanged(String _) {
    if (_syncing) {
      return;
    }
    _syncing = true;
    final int cash = _parsed(_cash);
    _setField(_cash, cash);
    _setField(_account, _sale - cash);
    _syncing = false;
    setState(() {});
  }

  void _onAccountChanged(String _) {
    if (_syncing) {
      return;
    }
    _syncing = true;
    final int account = _parsed(_account);
    _setField(_account, account);
    _setField(_cash, _sale - account);
    _syncing = false;
    setState(() {});
  }

  SaleTransaction _previewTxn() {
    final ({PaymentMethod payment, double cashAmount, double accountAmount})
    confirmed = resolvePendingAccountConfirm(
      payment: widget.txn.payment,
      saleAmount: widget.txn.amountPkr,
      cashAmount: _parsed(_cash).toDouble(),
    );
    final bool waiting = confirmed.accountAmount > 0;
    return widget.txn.copyWith(
      payment: confirmed.payment,
      cashAmount: confirmed.cashAmount,
      accountAmount: waiting ? 0 : confirmed.accountAmount,
      pendingAccountAmount: waiting ? confirmed.accountAmount : 0,
    );
  }

  Future<void> _print() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
    });
    try {
      await spoolSaleReceipt(context: context, txn: _previewTxn());
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.txn.payment.printsTwoCopies
                ? '2 copies sent to printer'
                : 'Receipt sent to printer',
          ),
        ),
      );
    } catch (error, stack) {
      debugPrint('Pending account print failed: $error\n$stack');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not print. $error')));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _confirm() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
    });
    try {
      final SaleTransaction? updated = await ref
          .read(stationControllerProvider.notifier)
          .confirmPendingAccountTransfer(
            tokenNo: widget.txn.tokenNo,
            cashAmount: _parsed(_cash).toDouble(),
          );
      if (!mounted) {
        return;
      }
      if (updated == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update this pending transfer'),
          ),
        );
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error, stack) {
      debugPrint('Pending account confirm failed: $error\n$stack');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not confirm pending account. $error')),
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
    return AlertDialog(
      backgroundColor: tokens.card,
      title: Text(
        'Confirm account ${formatTokenNo(widget.txn.tokenNo)}',
        style: TextStyle(
          fontFamily: 'Roboto',
          fontWeight: FontWeight.w700,
          fontSize: 16,
          color: tokens.ink,
        ),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Ticket ${formatPkr(_sale.toDouble())}. Cash and Account must add up to the sale.',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 13,
                height: 1.4,
                color: tokens.inkMuted,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _cash,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    onChanged: _onCashChanged,
                    decoration: const InputDecoration(labelText: 'Cash'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _account,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    onChanged: _onAccountChanged,
                    decoration: const InputDecoration(labelText: 'Account'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton.icon(
          onPressed: _busy ? null : _print,
          icon: const Icon(Icons.print_outlined, size: 18),
          label: const Text('Print'),
        ),
        FilledButton(
          onPressed: _busy ? null : _confirm,
          child: Text(_busy ? 'Saving…' : 'Confirm'),
        ),
      ],
    );
  }
}
