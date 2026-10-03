import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/dispensr_theme.dart';
import '../../../core/widgets/segment_lcd.dart';
import '../../../features/access/domain/access_policy.dart';
import '../../../features/shift/presentation/shift_providers.dart';
import '../../../features/station/domain/dispenser_models.dart';
import '../../../features/station/domain/fuel_precision.dart';
import '../../../features/station/presentation/station_providers.dart';
import '../../../utils/fuel_formatter.dart';
import 'Services/receipt_preview_widget.dart';

Future<void> showDirectSaleCard(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return const DirectSaleCardDialog();
    },
  );
}

class DirectSaleCardDialog extends ConsumerStatefulWidget {
  const DirectSaleCardDialog({super.key});

  @override
  ConsumerState<DirectSaleCardDialog> createState() =>
      _DirectSaleCardDialogState();
}

class _DirectSaleCardDialogState extends ConsumerState<DirectSaleCardDialog> {
  final TextEditingController _customer = TextEditingController();
  final TextEditingController _rate = TextEditingController();
  final TextEditingController _liters = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final double wac = ref.read(stationControllerProvider).dieselAverageRate;
    if (wac > 0) {
      _rate.text = FuelFormatter.fieldRate(wac);
    }
    _rate.addListener(_onInputsChanged);
    _liters.addListener(_onInputsChanged);
  }

  @override
  void dispose() {
    _rate.removeListener(_onInputsChanged);
    _liters.removeListener(_onInputsChanged);
    _customer.dispose();
    _rate.dispose();
    _liters.dispose();
    super.dispose();
  }

  void _onInputsChanged() {
    setState(() {});
  }

  Decimal get _rateValue => parseFuel(_rate.text);
  Decimal get _litersValue => parseFuel(_liters.text);

  int get _amountPkr {
    if (_rateValue <= Decimal.zero || _litersValue <= Decimal.zero) {
      return 0;
    }
    return roundRupees(_litersValue * _rateValue);
  }

  bool get _canSave {
    return !_saving && _amountPkr > 0;
  }

  SaleTransaction _draft(int tokenNo) {
    final String name = _customer.text.trim();
    return SaleTransaction(
      tokenNo: tokenNo,
      unitId: kDirectSaleUnitId,
      fuelType: kDieselFuelType,
      amountPkr: _amountPkr.toDouble(),
      volumeLiters: _litersValue.toDouble(),
      rate: _rateValue.toDouble(),
      meterCount: 0,
      timestamp: DateTime.now(),
      customerName: name.isEmpty ? 'Walk-in' : name,
      payment: PaymentMethod.cash,
      cashierName: ref.read(shiftWorkspaceProvider).activeShift?.operatorName ??
          'Operator',
      cashAmount: _amountPkr.toDouble(),
    );
  }

  Future<void> _printDraft() async {
    if (_amountPkr <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter rate and liters first')),
      );
      return;
    }
    final int tokenNo = ref
        .read(stationControllerProvider.notifier)
        .peekDirectTokenNo();
    try {
      await spoolSaleReceipt(context: context, txn: _draft(tokenNo));
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Receipt ${formatLedgerToken(tokenNo)} sent to printer',
          ),
        ),
      );
    } catch (error, stack) {
      debugPrint('Direct sale print failed: $error\n$stack');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not print this Direct sale')),
      );
    }
  }

  Future<void> _save() async {
    if (!_canSave) {
      return;
    }
    final bool liveShift =
        ref.read(shiftWorkspaceProvider).activeShift?.isOpen == true;
    if (shouldEnforceStationGuards && !liveShift) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Start a LIVE shift to save a Direct sale')),
      );
      return;
    }
    setState(() {
      _saving = true;
    });
    try {
      final SaleTransaction? saved = await ref
          .read(stationControllerProvider.notifier)
          .insertDirectCashSale(
            rate: _rateValue.toDouble(),
            liters: _litersValue.toDouble(),
            customerName: _customer.text,
          );
      if (!mounted) {
        return;
      }
      if (saved == null) {
        setState(() {
          _saving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save this Direct sale')),
        );
        return;
      }
      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${formatLedgerToken(saved.tokenNo)} saved. Stock updated.',
          ),
        ),
      );
    } catch (error, stack) {
      debugPrint('Direct sale save failed: $error\n$stack');
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save this Direct sale')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final int tokenNo = ref.watch(
      stationControllerProvider.select(
        (StationState station) =>
            tokenIdFor(
              unitId: kDirectSaleUnitId,
              sequence: station.sequences[kDirectSaleUnitId] ?? 0,
            ),
      ),
    );
    final bool liveShift =
        ref.watch(shiftWorkspaceProvider).activeShift?.isOpen == true;
    final bool locked = shouldEnforceStationGuards && !liveShift;

    return AlertDialog(
      backgroundColor: tokens.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius20),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      title: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              'Direct Sale Card',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: tokens.ink,
              ),
            ),
          ),
          Text(
            formatLedgerToken(tokenNo),
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: tokens.coral,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              height: 168,
              child: SegmentLcd.dispenser(
                lines: <SegmentLcdLine>[
                  SegmentLcdLine(
                    label: 'AMOUNT',
                    value: FuelFormatter.lcdDispenserAmount(
                      _amountPkr.toDouble(),
                    ),
                  ),
                  SegmentLcdLine(
                    label: 'LITERS',
                    value: FuelFormatter.lcdVolume(_litersValue.toDouble()),
                  ),
                  SegmentLcdLine(
                    label: 'RATE',
                    value: FuelFormatter.lcdAverageRate(_rateValue.toDouble()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _DirectField(
              tokens: tokens,
              label: 'Customer name',
              hint: 'Optional',
              controller: _customer,
              icon: Icons.person_outline,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: _DirectField(
                    tokens: tokens,
                    label: 'Rate',
                    hint: '0.00',
                    controller: _rate,
                    icon: Icons.sell_outlined,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    textInputAction: TextInputAction.next,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DirectField(
                    tokens: tokens,
                    label: 'Liters',
                    hint: '0.00',
                    controller: _liters,
                    icon: Icons.water_drop_outlined,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => unawaited(_save()),
                  ),
                ),
              ],
            ),
            if (locked) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                'Start a LIVE shift to save.',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 12,
                  color: tokens.warn,
                ),
              ),
            ],
          ],
        ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton.icon(
          onPressed: _saving || _amountPkr <= 0 ? null : () => unawaited(_printDraft()),
          icon: const Icon(Icons.print_outlined, size: 18),
          label: const Text('Print'),
        ),
        FilledButton(
          onPressed: locked || !_canSave ? null : () => unawaited(_save()),
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}

class _DirectField extends StatelessWidget {
  const _DirectField({
    required this.tokens,
    required this.label,
    required this.hint,
    required this.controller,
    required this.icon,
    this.keyboardType,
    this.inputFormatters,
    this.textInputAction,
    this.onSubmitted,
  });

  final DispensrTokens tokens;
  final String label;
  final String hint;
  final TextEditingController controller;
  final IconData icon;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      style: TextStyle(
        fontFamily: 'Roboto',
        fontWeight: FontWeight.w500,
        fontSize: 13,
        color: tokens.ink,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 18, color: tokens.inkMuted),
        isDense: true,
        filled: true,
        fillColor: tokens.canvas,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: tokens.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: tokens.line),
        ),
      ),
    );
  }
}
