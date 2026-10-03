import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/dispensr_theme.dart';
import '../../../../features/customer/domain/customer_models.dart';
import '../../../../features/customer/presentation/customer_providers.dart';
import '../../../../features/customer/presentation/widgets/customer_pick_field.dart';
import '../../../../features/station/domain/dispenser_models.dart';
import '../../../../features/station/domain/esp_token_log.dart';
import '../../../../features/station/domain/fuel_precision.dart';
import '../../../../features/station/domain/money_format.dart';
import '../../../../features/station/domain/sale_fulfillment.dart';
import '../../../../features/station/presentation/station_providers.dart';
import 'generate_receipt.dart';
import 'receipt_preview_widget.dart';

Future<void> showEspLastTenDialog(
  BuildContext context, {
  required int unitId,
}) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return _EspLastTenDialog(unitId: unitId);
    },
  );
}

Future<void> recoverEspSaleInteractively({
  required BuildContext context,
  required WidgetRef ref,
  required EspTokenLogRow row,
}) async {
  final List<SaleTransaction> ledger = ref.read(committedSalesProvider);
  if (espRowAlreadyOnLedger(row: row, appRows: ledger)) {
    final bool? proceed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Already on the ledger'),
          content: const Text(
            'This sale is already on the ledger. Recover still inserts a new Token#.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Recover anyway'),
            ),
          ],
        );
      },
    );
    if (proceed != true || !context.mounted) {
      return;
    }
  }
  if (!context.mounted) {
    return;
  }
  final _RecoverPaymentChoice? choice = await showDialog<_RecoverPaymentChoice>(
    context: context,
    builder: (BuildContext context) {
      return _RecoverPaymentDialog(row: row);
    },
  );
  if (choice == null || !context.mounted) {
    return;
  }
  final SaleTransaction? saved = await ref
      .read(stationControllerProvider.notifier)
      .recoverEspLogRow(
        row,
        payment: choice.payment,
        customerName: choice.customerName,
        vehicleNo: choice.vehicleNo,
        customerId: choice.customerId,
        cashNow: choice.cashNow,
      );
  if (!context.mounted) {
    return;
  }
  if (saved == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not recover this sale')),
    );
    return;
  }
  await spoolSaleReceipt(
    context: context,
    txn: saved,
    kind: ReceiptPrintKind.live,
  );
}

String espLogStamp(DateTime? at) {
  if (at == null) {
    return 'No date/time';
  }
  final DateTime local = at.toLocal();
  final String day = local.day.toString().padLeft(2, '0');
  final String month = local.month.toString().padLeft(2, '0');
  return '$day-$month-${local.year} ${formatClockWithSeconds(local)}';
}

class _EspLastTenDialog extends ConsumerStatefulWidget {
  const _EspLastTenDialog({required this.unitId});

  final int unitId;

  @override
  ConsumerState<_EspLastTenDialog> createState() => _EspLastTenDialogState();
}

class _EspLastTenDialogState extends ConsumerState<_EspLastTenDialog> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(stationControllerProvider.notifier)
          .requestEspSyncLog(widget.unitId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final List<EspTokenLogRow> rows =
        ref.watch(espLastTenByUnitProvider)[widget.unitId] ??
        const <EspTokenLogRow>[];
    final List<SaleTransaction> ledger = ref.watch(committedSalesProvider);
    return AlertDialog(
      title: Text('ESP last 10 — Unit ${widget.unitId}'),
      content: SizedBox(
        width: 460,
        height: 420,
        child: rows.isEmpty
            ? Text(
                'No ESP log yet. Connect the unit if this stays empty.',
                style: TextStyle(color: tokens.inkMuted),
              )
            : ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (BuildContext _, int __) =>
                    const SizedBox(height: 8),
                itemBuilder: (BuildContext context, int index) {
                  final EspTokenLogRow row = rows[index];
                  final bool onLedger = espRowAlreadyOnLedger(
                    row: row,
                    appRows: ledger,
                  );
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      color: tokens.canvas,
                      borderRadius: BorderRadius.circular(tokens.radius12),
                      border: Border.all(color: tokens.line),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              '${espLogStamp(row.at)}\n'
                              '${formatLiters(row.volumeLiters)}  ·  '
                              '${formatAverageRateValue(row.rate)}  ·  '
                              '${formatPkr(row.amountPkr)}'
                              '${onLedger ? '\nOn ledger' : ''}',
                              style: TextStyle(
                                fontFamily: 'Roboto',
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                height: 1.35,
                                color: tokens.ink,
                              ),
                            ),
                          ),
                          FilledButton(
                            onPressed: () {
                              unawaited(
                                recoverEspSaleInteractively(
                                  context: context,
                                  ref: ref,
                                  row: row,
                                ),
                              );
                            },
                            child: const Text('Recover'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _RecoverPaymentChoice {
  const _RecoverPaymentChoice({
    required this.payment,
    required this.customerName,
    required this.vehicleNo,
    required this.customerId,
    required this.cashNow,
  });

  final PaymentMethod payment;
  final String customerName;
  final String vehicleNo;
  final String customerId;
  final double cashNow;
}

class _RecoverPaymentDialog extends ConsumerStatefulWidget {
  const _RecoverPaymentDialog({required this.row});

  final EspTokenLogRow row;

  @override
  ConsumerState<_RecoverPaymentDialog> createState() =>
      _RecoverPaymentDialogState();
}

class _RecoverPaymentDialogState extends ConsumerState<_RecoverPaymentDialog> {
  final TextEditingController _customerId = TextEditingController();
  final TextEditingController _customer = TextEditingController();
  final TextEditingController _vehicle = TextEditingController();
  final TextEditingController _cashNow = TextEditingController();
  final TextEditingController _accountNow = TextEditingController();

  PaymentMethod _payment = PaymentMethod.cash;
  bool _syncingSplit = false;

  @override
  void initState() {
    super.initState();
    _customerId.addListener(_onCustomerIdChanged);
    _customer.addListener(_onFieldChanged);
    _vehicle.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    setState(() {});
  }

  int get _saleRupees => roundRupees(widget.row.amountPkr);

  CustomerProfile? _matchedCustomer() {
    final String key = normalizeCustomerIdQuery(_customerId.text);
    if (key.isEmpty) {
      return null;
    }
    return ref.read(customerIdCacheProvider)[key];
  }

  @override
  void dispose() {
    _customerId.dispose();
    _customer.dispose();
    _vehicle.dispose();
    _cashNow.dispose();
    _accountNow.dispose();
    super.dispose();
  }

  void _setSplitText(TextEditingController controller, int rupees) {
    final String next = rupees <= 0 ? '' : '$rupees';
    if (controller.text == next) {
      return;
    }
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  void _seedAccountSplit() {
    _syncingSplit = true;
    _cashNow.clear();
    _setSplitText(_accountNow, _saleRupees);
    _syncingSplit = false;
  }

  void _onCashSplitChanged(String _) {
    if (_syncingSplit) {
      return;
    }
    _syncingSplit = true;
    final int sale = _saleRupees;
    final int cash = (int.tryParse(_cashNow.text.trim()) ?? 0).clamp(0, sale);
    _setSplitText(_cashNow, cash);
    _setSplitText(_accountNow, sale - cash);
    _syncingSplit = false;
    setState(() {});
  }

  void _onAccountSplitChanged(String _) {
    if (_syncingSplit) {
      return;
    }
    _syncingSplit = true;
    final int sale = _saleRupees;
    final int account = (int.tryParse(_accountNow.text.trim()) ?? 0).clamp(
      0,
      sale,
    );
    _setSplitText(_accountNow, account);
    _setSplitText(_cashNow, sale - account);
    _syncingSplit = false;
    setState(() {});
  }

  void _onCustomerIdChanged() {
    final CustomerProfile? match = _matchedCustomer();
    if (match != null) {
      if (_customer.text != match.name) {
        _customer.value = TextEditingValue(
          text: match.name,
          selection: TextSelection.collapsed(offset: match.name.length),
        );
      }
    } else if (_customer.text.isNotEmpty) {
      _customer.clear();
    }
    _onFieldChanged();
  }

  bool get _accountSelected =>
      _payment == PaymentMethod.bankAccount ||
      _payment == PaymentMethod.easyPaisa;

  void _submit() {
    if (_payment == PaymentMethod.udhaar && _matchedCustomer() == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid customer ID for Udhaar')),
      );
      return;
    }
    Navigator.of(context).pop(
      _RecoverPaymentChoice(
        payment: _payment,
        customerName: _matchedCustomer()?.name ?? _customer.text,
        vehicleNo: _vehicle.text,
        customerId: _matchedCustomer()?.id ?? '',
        cashNow: double.tryParse(_cashNow.text.trim()) ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return AlertDialog(
      title: const Text('Recover sale'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                '${espLogStamp(widget.row.at)}\n'
                '${formatLiters(widget.row.volumeLiters)}  ·  '
                '${formatPkr(widget.row.amountPkr)}',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  height: 1.35,
                  color: tokens.ink,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  ChoiceChip(
                    label: const Text('Cash'),
                    selected: _payment == PaymentMethod.cash,
                    onSelected: (_) {
                      setState(() => _payment = PaymentMethod.cash);
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Udhaar'),
                    selected: _payment == PaymentMethod.udhaar,
                    onSelected: (_) {
                      setState(() => _payment = PaymentMethod.udhaar);
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Bank'),
                    selected: _payment == PaymentMethod.bankAccount,
                    onSelected: (_) {
                      setState(() {
                        _payment = PaymentMethod.bankAccount;
                        _seedAccountSplit();
                      });
                    },
                  ),
                  ChoiceChip(
                    label: const Text('EasyPaisa'),
                    selected: _payment == PaymentMethod.easyPaisa,
                    onSelected: (_) {
                      setState(() {
                        _payment = PaymentMethod.easyPaisa;
                        _seedAccountSplit();
                      });
                    },
                  ),
                ],
              ),
              if (_accountSelected) ...<Widget>[
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _cashNow,
                        keyboardType: TextInputType.number,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Cash now',
                        ),
                        onChanged: _onCashSplitChanged,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _accountNow,
                        keyboardType: TextInputType.number,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(labelText: 'Account'),
                        onChanged: _onAccountSplitChanged,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: _vehicle,
                inputFormatters: <TextInputFormatter>[
                  VehicleRegistrationFormatter(),
                ],
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Vehicle (optional)',
                ),
              ),
              const SizedBox(height: 10),
              CustomerPickField(
                idController: _customerId,
                nameController: _customer,
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Recover')),
      ],
    );
  }
}
