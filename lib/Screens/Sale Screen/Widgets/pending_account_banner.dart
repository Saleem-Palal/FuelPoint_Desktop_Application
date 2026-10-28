import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/dispensr_theme.dart';
import '../../../features/station/domain/dispenser_models.dart';
import '../../../features/station/domain/fuel_precision.dart';
import '../../../features/station/domain/money_format.dart';
import '../../../features/station/presentation/station_providers.dart';
import '../../../providers/settings_provider.dart';
import 'Services/receipt_preview_widget.dart';
import 'proof_capture_dialog.dart';

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
    final SaleTransaction? confirmed = await showDialog<SaleTransaction>(
      context: context,
      builder: (BuildContext context) {
        return _PendingAccountDialog(txn: txn);
      },
    );
    if (confirmed == null || !context.mounted) {
      return;
    }
    SaleTransaction latest = await maybeCaptureAccountProof(
      context: context,
      txn: confirmed,
    );
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          txn.payment == PaymentMethod.udhaar
              ? 'Udhaar account transfer confirmed for ${formatTokenNo(txn.tokenNo)}'
              : 'Account confirmed for ${formatTokenNo(txn.tokenNo)}',
        ),
      ),
    );
    if (ref.read(settingsProvider).showReceiptPreview) {
      showUnitReceiptOverlay(ref, latest);
    }
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
                    label: 'Payment',
                    value: txn.payment == PaymentMethod.udhaar
                        ? 'Udhaar · Account pending'
                        : '${txn.payment.label} · Pending',
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
  late String _proofPath;
  bool _syncing = false;
  bool _busy = false;

  int get _sale => roundRupees(widget.txn.amountPkr);

  bool get _fromUdhaar => widget.txn.payment == PaymentMethod.udhaar;

  @override
  void initState() {
    super.initState();
    final int cash = roundRupees(widget.txn.cashAmount).clamp(0, _sale);
    final int received = roundRupees(widget.txn.pendingAccountAmount);
    final int account = _fromUdhaar
        ? received
        : (received > 0 ? received : (_sale - cash));
    _cash = TextEditingController(text: cash == 0 ? '' : '$cash');
    _account = TextEditingController(text: account == 0 ? '' : '$account');
    _proofPath = widget.txn.proofImagePath.trim();
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

  int _parsedCash() {
    return (int.tryParse(_cash.text.trim()) ?? 0).clamp(0, _sale);
  }

  int _parsedAccount() {
    final int account = int.tryParse(_account.text.trim()) ?? 0;
    return account < 0 ? 0 : account;
  }

  int get _baqayaRupees {
    return accountOverpayBaqaya(
      saleAmount: _sale.toDouble(),
      accountNow: _parsedAccount().toDouble(),
    );
  }

  void _onCashChanged(String _) {
    if (_syncing) {
      return;
    }
    _syncing = true;
    final int cash = _parsedCash();
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
    final int account = _parsedAccount();
    if (account > _sale) {
      _setField(_cash, 0);
    } else {
      _setField(_account, account);
      _setField(_cash, _sale - account);
    }
    _syncing = false;
    setState(() {});
  }

  SaleTransaction _previewTxn() {
    if (_fromUdhaar) {
      return widget.txn.copyWith(
        payment: PaymentMethod.udhaar,
        cashAmount: widget.txn.cashAmount,
        accountAmount: 0,
        pendingAccountAmount: widget.txn.pendingAccountAmount,
        proofImagePath: _proofPath,
      );
    }
    final ({PaymentMethod payment, double cashAmount, double accountAmount})
    confirmed = resolvePendingAccountConfirm(
      payment: widget.txn.payment,
      saleAmount: widget.txn.amountPkr,
      cashAmount: _parsedCash().toDouble(),
      pendingAccountAmount: _parsedAccount().toDouble(),
    );
    return widget.txn.copyWith(
      payment: confirmed.payment,
      cashAmount: confirmed.cashAmount,
      accountAmount: confirmed.accountAmount,
      pendingAccountAmount: 0,
      proofImagePath: _proofPath,
    );
  }

  Future<void> _addProof() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
    });
    try {
      final int account = _parsedAccount();
      final SaleTransaction? withProof = await showProofCaptureDialog(
        context: context,
        txn: widget.txn.copyWith(
          cashAmount: _parsedCash().toDouble(),
          accountAmount: account.toDouble(),
          pendingAccountAmount: 0,
          proofImagePath: _proofPath,
        ),
      );
      if (!mounted) {
        return;
      }
      final String path = withProof?.proofImagePath.trim() ?? '';
      if (path.isNotEmpty) {
        setState(() {
          _proofPath = path;
        });
      }
    } catch (error, stack) {
      debugPrint('Add proof failed: $error\n$stack');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not add proof. $error')));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _print() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
    });
    try {
      await presentSaleReceipt(context: context, txn: _previewTxn());
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
            cashAmount: _parsedCash().toDouble(),
            pendingAccountAmount: _parsedAccount().toDouble(),
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
      Navigator.of(context).pop(updated);
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
        _fromUdhaar
            ? 'Confirm Udhaar account ${formatTokenNo(widget.txn.tokenNo)}'
            : 'Confirm account ${formatTokenNo(widget.txn.tokenNo)}',
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
              _fromUdhaar
                  ? 'This Account amount is from an Udhaar sale. Confirm the transfer and add proof. Cash and Udhaar credit stay as they are.'
                  : 'Ticket ${formatPkr(_sale.toDouble())}. Cash and Account must add up to the sale.',
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
                    enabled: !_busy && !_fromUdhaar,
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
                    enabled: !_busy && !_fromUdhaar,
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
            if (_baqayaRupees > 0) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Baqaya Dene hain  ${formatPkr(_baqayaRupees.toDouble())}',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: tokens.warn,
                ),
              ),
            ],
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
        TextButton.icon(
          onPressed: _busy ? null : _addProof,
          icon: Icon(
            _proofPath.isEmpty
                ? Icons.add_a_photo_outlined
                : Icons.check_circle_outline,
            size: 18,
          ),
          label: Text(_proofPath.isEmpty ? 'Add Proof' : 'Proof added'),
        ),
        FilledButton(
          onPressed: _busy ? null : _confirm,
          child: Text(_busy ? 'Saving…' : 'Confirm'),
        ),
      ],
    );
  }
}
