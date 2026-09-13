import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/dispensr_theme.dart';
import '../../../features/shift/presentation/shift_providers.dart';
import '../../../features/station/data/purchase_repository.dart';
import '../../../features/station/domain/dispenser_models.dart';
import '../../../features/station/domain/money_format.dart';
import '../../../features/station/presentation/purchase_providers.dart';
import '../../../services/database_helper.dart';
import '../../../utils/fuel_formatter.dart';

Future<bool> showEditPurchaseDialog(
  BuildContext context, {
  required String invNo,
  required DateTime timestamp,
  required double quantity,
  required double rate,
  required double amount,
  required String tafseel,
}) {
  return showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return EditPurchaseDialog(
        invNo: invNo,
        timestamp: timestamp,
        quantity: quantity,
        rate: rate,
        amount: amount,
        tafseel: tafseel,
      );
    },
  ).then((bool? saved) => saved ?? false);
}

Future<bool> showEditPurchaseDialogFromLedger(
  BuildContext context,
  PurchaseTransaction row,
) {
  return showEditPurchaseDialog(
    context,
    invNo: formatInvoiceNo(row.refNo),
    timestamp: row.timestamp,
    quantity: row.netLiters,
    rate: row.ratePerLiter,
    amount: row.totalAmount,
    tafseel: row.tafseel,
  );
}

class EditPurchaseDialog extends ConsumerStatefulWidget {
  const EditPurchaseDialog({
    super.key,
    required this.invNo,
    required this.timestamp,
    required this.quantity,
    required this.rate,
    required this.amount,
    required this.tafseel,
  });

  final String invNo;
  final DateTime timestamp;
  final double quantity;
  final double rate;
  final double amount;
  final String tafseel;

  @override
  ConsumerState<EditPurchaseDialog> createState() => _EditPurchaseDialogState();
}

class _EditPurchaseDialogState extends ConsumerState<EditPurchaseDialog> {
  static final FilteringTextInputFormatter _litersFormatter =
      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,13}'));
  static final FilteringTextInputFormatter _rateFormatter =
      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,13}'));
  static final FilteringTextInputFormatter _amountFormatter =
      FilteringTextInputFormatter.allow(RegExp(r'^[\d,]*'));

  late final TextEditingController _liters;
  late final TextEditingController _rate;
  late final TextEditingController _amount;
  late final TextEditingController _tafseel;
  bool _syncing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _liters = TextEditingController(text: FuelFormatter.fieldWhole(widget.quantity));
    _rate = TextEditingController(text: FuelFormatter.fieldRate(widget.rate));
    _amount = TextEditingController(text: FuelFormatter.fieldAmount(widget.amount));
    _tafseel = TextEditingController(text: widget.tafseel);
    _liters.addListener(_onLitersOrRateChanged);
    _rate.addListener(_onLitersOrRateChanged);
    _amount.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _liters
      ..removeListener(_onLitersOrRateChanged)
      ..dispose();
    _rate
      ..removeListener(_onLitersOrRateChanged)
      ..dispose();
    _amount
      ..removeListener(_onAmountChanged)
      ..dispose();
    _tafseel.dispose();
    super.dispose();
  }

  double get _quantity => FuelFormatter.parseGrouped(_liters.text);
  double get _unitRate => FuelFormatter.parseGrouped(_rate.text);
  double get _total => FuelFormatter.parseGrouped(_amount.text);
  bool get _ready => _quantity > 0 && _unitRate > 0;

  void _writeField(TextEditingController controller, String next) {
    if (controller.text == next) {
      return;
    }
    controller.text = next;
    controller.selection = TextSelection.collapsed(offset: next.length);
  }

  void _onLitersOrRateChanged() {
    if (_syncing) {
      return;
    }
    _syncing = true;
    _writeField(_amount, FuelFormatter.fieldAmount(_quantity * _unitRate));
    _syncing = false;
    if (mounted) {
      setState(() {});
    }
  }

  void _onAmountChanged() {
    if (_syncing) {
      return;
    }
    _syncing = true;
    if (_quantity > 0) {
      _writeField(_rate, FuelFormatter.fieldRate(_total / _quantity));
    }
    _writeField(_amount, FuelFormatter.fieldAmount(_total));
    _syncing = false;
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _save() async {
    if (_saving || !_ready) {
      return;
    }
    setState(() {
      _saving = true;
    });
    final ({String id, String name, String pin}) manager =
        PurchaseRepository.managerCreds(
          activeShift: ref.read(shiftWorkspaceProvider).activeShift,
          managers: ref.read(shiftWorkspaceProvider).managers,
        );
    try {
      await ref
          .read(purchaseControllerProvider)
          .updatePurchase(
            invNo: widget.invNo,
            purchasedLiters: _quantity,
            purchaseRate: _unitRate,
            totalAmountPkr: _total,
            tafseel: _tafseel.text,
            managerId: manager.id,
          );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } on PurchaseStockOverdrawException {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This change would drop tank stock below zero. Reduce the cut or check later sales.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update ${widget.invNo}. $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
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
                'Edit ${widget.invNo}',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: tokens.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                formatDateTime(widget.timestamp),
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 12,
                  color: tokens.inkMuted,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _liters,
                enabled: !_saving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: <TextInputFormatter>[_litersFormatter],
                style: const TextStyle(fontFamily: 'Roboto', fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Quantity (Ltr)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _rate,
                enabled: !_saving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: <TextInputFormatter>[_rateFormatter],
                style: const TextStyle(fontFamily: 'Roboto', fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Rate (Rs / Ltr)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _amount,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[_amountFormatter],
                style: const TextStyle(fontFamily: 'Roboto', fontSize: 13),
                decoration: const InputDecoration(labelText: 'Amount (Rs)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _tafseel,
                enabled: !_saving,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => unawaited(_save()),
                style: const TextStyle(fontFamily: 'Roboto', fontSize: 13),
                decoration: const InputDecoration(labelText: 'Tafseel'),
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
                          : () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DsPillButton(
                      label: _saving ? 'Updating…' : 'Update Stock',
                      onPressed: _saving || !_ready
                          ? null
                          : () => unawaited(_save()),
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
