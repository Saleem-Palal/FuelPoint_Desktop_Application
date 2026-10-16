import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/dispensr_theme.dart';
import '../../../../features/customer/domain/customer_models.dart';
import '../../../../features/customer/presentation/customer_providers.dart';
import '../../../../features/station/domain/dispenser_models.dart';
import '../../../../features/station/domain/fuel_precision.dart';
import '../../../../features/station/domain/money_format.dart';
import '../../../../features/station/domain/sale_fulfillment.dart';
import '../../../../features/station/presentation/station_providers.dart';
import '../../../../providers/settings_provider.dart';
import 'generate_receipt.dart';
import 'receipt_preview_widget.dart';

class ConfirmPaymentSheet extends ConsumerStatefulWidget {
  const ConfirmPaymentSheet({super.key, required this.unitId});

  final int unitId;

  @override
  ConsumerState<ConfirmPaymentSheet> createState() =>
      _ConfirmPaymentSheetState();
}

class _ConfirmPaymentSheetState extends ConsumerState<ConfirmPaymentSheet> {
  final TextEditingController _customerId = TextEditingController();
  final TextEditingController _customer = TextEditingController();
  final TextEditingController _vehicle = TextEditingController();
  final FocusNode _vehicleFocus = FocusNode();
  final TextEditingController _cashNow = TextEditingController();
  final TextEditingController _accountNow = TextEditingController();

  _PayPill _pill = _PayPill.cash;
  _AccountRail _rail = _AccountRail.bank;
  bool _submitting = false;
  bool _syncingSplit = false;

  bool get _udhaarSelected => _pill == _PayPill.udhaar;

  void _selectThisUnit() {
    ref.read(selectedDispenserIndexProvider.notifier).state = widget.unitId;
  }

  @override
  void initState() {
    super.initState();
    _customer.addListener(_onFieldChanged);
    _customerId.addListener(_onCustomerIdChanged);
    _vehicle.addListener(_onFieldChanged);
    _vehicleFocus.addListener(_onFieldChanged);
  }

  CustomerProfile? _matchedCustomer() {
    final String key = normalizeCustomerIdQuery(_customerId.text);
    if (key.isEmpty) {
      return null;
    }
    return ref.read(customerIdCacheProvider)[key];
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

  void _onFieldChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _customerId
      ..removeListener(_onCustomerIdChanged)
      ..dispose();
    _customer
      ..removeListener(_onFieldChanged)
      ..dispose();
    _vehicle
      ..removeListener(_onFieldChanged)
      ..dispose();
    _vehicleFocus
      ..removeListener(_onFieldChanged)
      ..dispose();
    _cashNow.dispose();
    _accountNow.dispose();
    super.dispose();
  }

  PaymentMethod get _paymentMethod {
    switch (_pill) {
      case _PayPill.cash:
        return PaymentMethod.cash;
      case _PayPill.udhaar:
        return PaymentMethod.udhaar;
      case _PayPill.account:
        return _rail == _AccountRail.bank
            ? PaymentMethod.bankAccount
            : PaymentMethod.easyPaisa;
    }
  }

  void _cycleMethod(int delta) {
    if (ref.read(stationControllerProvider).unit(widget.unitId).isTestRun) {
      return;
    }
    const List<_PayPill> methods = <_PayPill>[
      _PayPill.cash,
      _PayPill.udhaar,
      _PayPill.account,
    ];
    int index = methods.indexOf(_pill);
    if (index < 0) {
      index = 0;
    }
    index = (index + delta) % methods.length;
    if (index < 0) {
      index += methods.length;
    }
    setState(() {
      _applyPill(methods[index]);
    });
  }

  void _cycleRail(int delta) {
    if (ref.read(stationControllerProvider).unit(widget.unitId).isTestRun) {
      return;
    }
    setState(() {
      if (_pill != _PayPill.account) {
        _applyPill(_PayPill.account);
        _rail = delta < 0 ? _AccountRail.bank : _AccountRail.easyPaisa;
      } else {
        int index = _rail == _AccountRail.bank ? 0 : 1;
        index = (index + delta) % 2;
        if (index < 0) {
          index += 2;
        }
        _rail = index == 0 ? _AccountRail.bank : _AccountRail.easyPaisa;
      }
    });
  }

  bool get _isVehicleValid => isVehicleRegistrationValid(_vehicle.text);

  bool _canSubmit(DispenserUnit unit) {
    if (_submitting || !unit.canConfirmPayment) {
      return false;
    }
    if (!unit.isTestRun && !_isVehicleValid) {
      return false;
    }
    if (!unit.isTestRun && !_tenderReady) {
      return false;
    }
    return true;
  }

  bool _canPreview(DispenserUnit unit) {
    return !_submitting &&
        unit.canConfirmPayment &&
        (unit.isTestRun || (_isVehicleValid && _tenderReady));
  }

  bool get _tenderReady {
    final int cash = _cashRupees;
    final int account = _accountRupees;
    if (cash < 0 || account < 0) {
      return false;
    }
    switch (_pill) {
      case _PayPill.cash:
        return true;
      case _PayPill.account:
        return _accountRupees > _saleRupees || cash + account == _saleRupees;
      case _PayPill.udhaar:
        return _matchedCustomer() != null && cash + account < _saleRupees;
    }
  }

  int get _cashRupees {
    return int.tryParse(_cashNow.text.trim()) ?? 0;
  }

  int get _accountRupees {
    return int.tryParse(_accountNow.text.trim()) ?? 0;
  }

  double get _cashNowValue {
    return _cashRupees.toDouble();
  }

  double get _accountNowValue {
    return _accountRupees.toDouble();
  }

  int get _udhaarRemainder {
    return udhaarCreditRupees(
      saleAmount: _saleRupees.toDouble(),
      cashAmount: _cashNowValue,
      accountAmount: _accountNowValue,
    );
  }

  int get _baqayaRupees {
    if (_pill != _PayPill.account) {
      return 0;
    }
    return accountOverpayBaqaya(
      saleAmount: _saleRupees.toDouble(),
      accountNow: _accountNowValue,
    );
  }

  int get _saleRupees {
    return roundRupees(
      ref.read(stationControllerProvider).unit(widget.unitId).amountPkr,
    );
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

  void _applyPill(_PayPill next) {
    if (next == _PayPill.account) {
      _seedAccountSplit();
    } else if (next == _PayPill.udhaar) {
      if (_cashRupees + _accountRupees >= _saleRupees) {
        _cashNow.clear();
        _accountNow.clear();
      }
    } else {
      _cashNow.clear();
      _accountNow.clear();
    }
    _pill = next;
  }

  void _seedAccountSplit() {
    if (_cashRupees + _accountRupees == _saleRupees) {
      return;
    }
    _syncingSplit = true;
    _cashNow.clear();
    _setSplitText(_accountNow, _saleRupees);
    _syncingSplit = false;
  }

  void _onSplitChanged(String _) {
    if (_syncingSplit) {
      _onFieldChanged();
      return;
    }
    if (_pill == _PayPill.udhaar &&
        _saleRupees > 0 &&
        _cashRupees + _accountRupees >= _saleRupees) {
      setState(() {
        _pill = _PayPill.account;
      });
      return;
    }
    _onFieldChanged();
  }

  void _preview() {
    _selectThisUnit();
    final DispenserUnit unit = ref
        .read(stationControllerProvider)
        .unit(widget.unitId);
    if (!_canPreview(unit)) {
      return;
    }
    if (!unit.isTestRun && _udhaarSelected && _matchedCustomer() == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid customer ID')),
      );
      return;
    }
    final String customerName = unit.isTestRun
        ? 'TEST'
        : (_udhaarSelected ? (_matchedCustomer()?.name ?? '') : '');
    if (!ref.read(settingsProvider).showReceiptPreview) {
      final SaleTransaction? draft = ref
          .read(stationControllerProvider.notifier)
          .receiptDraftForUnit(
            unitId: widget.unitId,
            customerName: customerName,
            vehicleNo: _vehicle.text,
            payment: unit.isTestRun ? PaymentMethod.cash : _paymentMethod,
            cashNow: unit.isTestRun ? 0 : _cashNowValue,
            accountNow: unit.isTestRun ? 0 : _accountNowValue,
          );
      if (draft == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This unit is not ready to print')),
        );
        return;
      }
      unawaited(() async {
        try {
          await spoolSaleReceipt(
            context: context,
            txn: draft,
            kind: ReceiptPrintKind.live,
            baqayaPkr: unit.isTestRun ? 0 : _baqayaRupees,
          );
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                draft.payment.printsTwoCopies
                    ? '2 copies sent to printer'
                    : 'Receipt sent to printer',
              ),
            ),
          );
        } catch (error, stack) {
          debugPrint('Unit print failed: $error\n$stack');
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not print receipt. $error')),
          );
        }
      }());
      return;
    }
    final bool shown = ref
        .read(stationControllerProvider.notifier)
        .previewReceiptForUnit(
          unitId: widget.unitId,
          customerName: customerName,
          vehicleNo: _vehicle.text,
          payment: unit.isTestRun ? PaymentMethod.cash : _paymentMethod,
          cashNow: unit.isTestRun ? 0 : _cashNowValue,
          accountNow: unit.isTestRun ? 0 : _accountNowValue,
        );
    if (!shown && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This unit is not ready to print')),
      );
    }
  }

  Future<void> _confirm() async {
    _selectThisUnit();
    final DispenserUnit unit = ref
        .read(stationControllerProvider)
        .unit(widget.unitId);
    if (_submitting) {
      return;
    }
    if (!unit.isTestRun && _udhaarSelected && _matchedCustomer() == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid customer ID')),
      );
      return;
    }
    if (!_canSubmit(unit)) {
      return;
    }
    _submitting = true;
    if (mounted) {
      setState(() {});
    }
    try {
      final SaleTransaction? txn = await ref
          .read(stationControllerProvider.notifier)
          .confirmAndClearUnit(
            unitId: widget.unitId,
            customerName: _udhaarSelected
                ? (_matchedCustomer()?.name ?? '')
                : '',
            vehicleNo: persistVehicleNo(_vehicle.text),
            payment: unit.isTestRun ? PaymentMethod.cash : _paymentMethod,
            customerId: _udhaarSelected ? (_matchedCustomer()?.id ?? '') : '',
            cashNow: unit.isTestRun ? 0 : _cashNowValue,
            accountNow: unit.isTestRun ? 0 : _accountNowValue,
          );
      if (!mounted) {
        return;
      }
      if (txn == null) {
        setState(() {
          _submitting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This unit is no longer ready to clear'),
          ),
        );
        return;
      }
      final bool wasTest = txn.notes == 'TEST_METER';
      _customerId.clear();
      _customer.clear();
      _vehicle.clear();
      _cashNow.clear();
      _accountNow.clear();
      setState(() {
        _pill = _PayPill.cash;
        _rail = _AccountRail.bank;
        _submitting = false;
      });
      if (wasTest) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Test fill saved (opening/closing meters). Not a sale — stock unchanged.',
            ),
          ),
        );
      }
    } catch (error, stack) {
      debugPrint('Could not commit this sale: $error\n$stack');
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not commit this sale: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    ref.watch(customerIdCacheProvider);
    final DispenserUnit unit = ref
        .watch(stationControllerProvider)
        .unit(widget.unitId);

    ref.listen<int>(paymentSubmitNonceProvider, (int? previous, int next) {
      if (ref.read(selectedDispenserIndexProvider) == widget.unitId) {
        _confirm();
      }
    });
    ref.listen<PaymentCycleSignal?>(paymentCycleSignalProvider, (
      PaymentCycleSignal? previous,
      PaymentCycleSignal? next,
    ) {
      if (next == null) {
        return;
      }
      if (ref.read(selectedDispenserIndexProvider) != widget.unitId) {
        return;
      }
      if (next.axis == PaymentCycleAxis.method) {
        _cycleMethod(next.delta);
        return;
      }
      _cycleRail(next.delta);
    });

    final String actionLabel;
    if (unit.canConfirmPayment) {
      actionLabel = 'Confirm';
    } else if (unit.isDispensing) {
      actionLabel = 'Confirm';
    } else if (unit.isOffline) {
      actionLabel = 'Unit Offline';
    } else {
      actionLabel = 'Waiting';
    }

    final bool waitingLook = actionLabel == 'Waiting';
    final bool paymentReady = !_submitting && unit.canConfirmPayment;
    final bool printOn = paymentReady;
    final bool confirmOn = paymentReady;
    final int methodIndex = unit.isTestRun ? 0 : _PayPill.values.indexOf(_pill);

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter): _confirm,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _confirm,
      },
      child: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          decoration: BoxDecoration(
            color: tokens.canvas,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: tokens.line),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (unit.isTestRun) ...<Widget>[
                Text(
                  'Test fill — stock and liters count. Not a sale. Cash unchanged.',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w500,
                    fontSize: 10,
                    height: 1.25,
                    color: tokens.warn,
                  ),
                ),
                const SizedBox(height: _kGap),
              ],
              _SlidingPill(
                selectedIndex: methodIndex,
                enabled: !unit.isTestRun,
                segments: <_PillSegment>[
                  _PillSegment(
                    label: 'Cash',
                    icon: Icons.payments_outlined,
                    onTap: () {
                      _selectThisUnit();
                      setState(() {
                        _applyPill(_PayPill.cash);
                      });
                    },
                  ),
                  _PillSegment(
                    label: 'Udhaar',
                    icon: Icons.person_outline,
                    onTap: () {
                      _selectThisUnit();
                      setState(() {
                        _applyPill(_PayPill.udhaar);
                      });
                    },
                  ),
                  _PillSegment(
                    label: 'Account',
                    icon: Icons.credit_card_outlined,
                    onTap: () {
                      _selectThisUnit();
                      setState(() {
                        _applyPill(_PayPill.account);
                      });
                    },
                  ),
                ],
              ),
              if (!unit.isTestRun && _pill == _PayPill.udhaar) ...<Widget>[
                const SizedBox(height: _kGap),
                _UdhaarPartyField(
                  idController: _customerId,
                  nameController: _customer,
                  onTap: _selectThisUnit,
                  onSubmitted: (_) => _confirm(),
                ),
                const SizedBox(height: _kGap),
                _SplitAmountRow(
                  cash: _cashNow,
                  account: _accountNow,
                  onTap: _selectThisUnit,
                  onChanged: _onSplitChanged,
                  onSubmitted: (_) => _confirm(),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 2,
                  ),
                  child: _TenderBar(
                    cash: _cashRupees,
                    account: _accountRupees,
                    remainder: _udhaarRemainder,
                    remainderLabel: 'Udhaar',
                  ),
                ),
              ],
              if (!unit.isTestRun && _pill == _PayPill.account) ...<Widget>[
                const SizedBox(height: _kGap),
                _SlidingPill(
                  selectedIndex: _rail == _AccountRail.bank ? 0 : 1,
                  segments: <_PillSegment>[
                    _PillSegment(
                      label: 'Bank',
                      icon: Icons.account_balance_outlined,
                      onTap: () {
                        _selectThisUnit();
                        setState(() {
                          _rail = _AccountRail.bank;
                        });
                      },
                    ),
                    _PillSegment(
                      label: 'EasyPaisa',
                      icon: Icons.smartphone_outlined,
                      onTap: () {
                        _selectThisUnit();
                        setState(() {
                          _rail = _AccountRail.easyPaisa;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: _kGap),
                _SplitAmountRow(
                  cash: _cashNow,
                  account: _accountNow,
                  onTap: _selectThisUnit,
                  onChanged: _onSplitChanged,
                  onSubmitted: (_) => _confirm(),
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 2,
                  ),
                  child: _TenderBar(
                    cash: _cashRupees,
                    account: _accountRupees,
                    remainder: _baqayaRupees,
                    remainderLabel: 'Baqaya',
                  ),
                ),
              ],
              const SizedBox(height: _kGap),
              _ShellField(
                hint: 'Vehicle number',
                icon: Icons.directions_car_outlined,
                height: _kVehicleHeight,
                controller: _vehicle,
                focusNode: _vehicleFocus,
                onTap: _selectThisUnit,
                textInputAction: _udhaarSelected
                    ? TextInputAction.next
                    : TextInputAction.done,
                inputFormatters: <TextInputFormatter>[
                  VehicleRegistrationFormatter(),
                ],
                textCapitalization: TextCapitalization.characters,
                onSubmitted: _udhaarSelected ? null : (_) => _confirm(),
              ),
              if (!unit.isTestRun &&
                  unit.canConfirmPayment &&
                  !_isVehicleValid) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  'Enter letters and digits (any order) to proceed.',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                    color: tokens.inkMuted,
                  ),
                ),
              ],
              const SizedBox(height: _kGap),
              SizedBox(
                height: _kButtonHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(
                      child: _ActionChip(
                        label: 'Print',
                        icon: Icons.print_outlined,
                        height: _kButtonHeight,
                        background: printOn ? tokens.ink : tokens.card,
                        foreground: printOn ? tokens.card : tokens.inkMuted,
                        borderColor: printOn ? tokens.ink : tokens.line,
                        onTap: _canPreview(unit) ? _preview : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: waitingLook
                          ? _WaitingChip(height: _kButtonHeight, tokens: tokens)
                          : _ActionChip(
                              label: actionLabel,
                              icon: actionLabel == 'Confirm'
                                  ? Icons.check
                                  : null,
                              height: _kButtonHeight,
                              background: confirmOn
                                  ? tokens.coral
                                  : tokens.card,
                              foreground: confirmOn
                                  ? tokens.card
                                  : tokens.inkMuted,
                              borderColor: confirmOn
                                  ? tokens.coral
                                  : tokens.line,
                              shadows: confirmOn
                                  ? _coralButtonShadow(tokens)
                                  : null,
                              onTap: _canSubmit(unit) ? _confirm : null,
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillSegment {
  const _PillSegment({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

class _SlidingPill extends StatelessWidget {
  const _SlidingPill({
    required this.segments,
    required this.selectedIndex,
    this.enabled = true,
  });

  final List<_PillSegment> segments;
  final int selectedIndex;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final int count = segments.length;
    final int index = selectedIndex.clamp(0, count - 1);
    return Container(
      height: _kPillHeight,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tokens.line),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double inner = (constraints.maxWidth - 6).clamp(0, 10000);
          final double knobWidth = inner / count;
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              AnimatedPositioned(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                left: 3 + (index * knobWidth),
                top: 3,
                bottom: 3,
                width: knobWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: enabled
                        ? tokens.coral
                        : tokens.coral.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Row(
                children: <Widget>[
                  for (int i = 0; i < count; i++)
                    Expanded(
                      child: InkWell(
                        onTap: enabled ? segments[i].onTap : null,
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                segments[i].icon,
                                size: 14,
                                color: i == index
                                    ? tokens.card
                                    : (enabled ? tokens.ink : tokens.inkMuted),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                segments[i].label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Roboto',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                  height: 1,
                                  color: i == index
                                      ? tokens.card
                                      : (enabled
                                            ? tokens.ink
                                            : tokens.inkMuted),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SplitAmountRow extends StatelessWidget {
  const _SplitAmountRow({
    required this.cash,
    required this.account,
    required this.onTap,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController cash;
  final TextEditingController account;
  final VoidCallback onTap;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _ShellField(
            hint: '0',
            inlineLabel: 'Cash',
            icon: Icons.payments_outlined,
            controller: cash,
            amount: true,
            onTap: onTap,
            textInputAction: TextInputAction.next,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            onChanged: onChanged,
            onSubmitted: onSubmitted,
          ),
        ),
        const SizedBox(width: 2),
        Expanded(
          child: _ShellField(
            hint: '0',
            inlineLabel: 'Account',
            icon: Icons.account_balance_outlined,
            controller: account,
            amount: true,
            onTap: onTap,
            textInputAction: TextInputAction.done,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            onChanged: onChanged,
            onSubmitted: onSubmitted,
          ),
        ),
      ],
    );
  }
}

class _UdhaarPartyField extends StatelessWidget {
  const _UdhaarPartyField({
    required this.idController,
    required this.nameController,
    required this.onTap,
    required this.onSubmitted,
  });

  final TextEditingController idController;
  final TextEditingController nameController;
  final VoidCallback onTap;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final TextStyle textStyle = TextStyle(
      fontFamily: 'Roboto',
      fontWeight: FontWeight.w500,
      fontSize: 13,
      height: 1,
      color: tokens.ink,
    );
    final TextStyle hintStyle = textStyle.copyWith(
      fontWeight: FontWeight.w400,
      color: tokens.inkMuted.withValues(alpha: 0.72),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        SizedBox(
          width: 65,
          height: _kControlHeight,
          child: TextField(
            controller: idController,
            onTap: onTap,
            onSubmitted: onSubmitted,
            maxLength: 4,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            textAlign: TextAlign.center,
            textAlignVertical: TextAlignVertical.center,
            style: textStyle.copyWith(fontWeight: FontWeight.w700),
            decoration: _outlineField(
              tokens: tokens,
              hint: 'ID',
              hintStyle: hintStyle,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 14,
                horizontal: 4,
              ),
            ),
          ),
        ),
        const SizedBox(width: 2),
        Expanded(
          child: SizedBox(
            height: _kControlHeight,
            child: TextField(
              controller: nameController,
              readOnly: true,
              enableInteractiveSelection: false,
              onTap: onTap,
              textAlignVertical: TextAlignVertical.center,
              style: textStyle,
              decoration: _outlineField(
                tokens: tokens,
                hint: 'Customer name',
                hintStyle: hintStyle,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TenderBar extends StatelessWidget {
  const _TenderBar({
    required this.cash,
    required this.account,
    required this.remainder,
    required this.remainderLabel,
  });

  final int cash;
  final int account;
  final int remainder;
  final String remainderLabel;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final int total = cash + account + remainder;
    final List<_TenderSlice> slices = <_TenderSlice>[
      if (cash > 0) _TenderSlice('Cash', cash, tokens.good),
      if (account > 0) _TenderSlice('Account', account, _kAccountBlue),
      if (remainder > 0) _TenderSlice(remainderLabel, remainder, tokens.coral),
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 12,
        width: double.infinity,
        child: total <= 0 || slices.isEmpty
            ? ColoredBox(color: tokens.line)
            : LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final List<double> widths = _tenderSliceWidths(
                    constraints.maxWidth,
                    <int>[for (final _TenderSlice slice in slices) slice.amount],
                  );
                  return Row(
                    children: <Widget>[
                      for (int i = 0; i < slices.length; i++)
                        SizedBox(
                          width: widths[i],
                          child: _TenderSegment(
                            label: slices[i].label,
                            amount: slices[i].amount,
                            color: slices[i].color,
                            width: widths[i],
                          ),
                        ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

class _TenderSlice {
  const _TenderSlice(this.label, this.amount, this.color);

  final String label;
  final int amount;
  final Color color;
}

/// Keeps a 1-rupee or 100-rupee slice wide enough to read.
List<double> _tenderSliceWidths(double maxWidth, List<int> amounts) {
  const double minSlice = 32;
  final int count = amounts.length;
  if (count == 0 || maxWidth <= 0) {
    return <double>[];
  }
  final int sum = amounts.fold<int>(0, (int total, int amount) => total + amount);
  if (sum <= 0) {
    final double each = maxWidth / count;
    return List<double>.filled(count, each);
  }
  final double reserved = minSlice * count;
  if (reserved >= maxWidth) {
    final double each = maxWidth / count;
    return List<double>.filled(count, each);
  }
  final double extra = maxWidth - reserved;
  return <double>[
    for (final int amount in amounts) minSlice + extra * (amount / sum),
  ];
}

class _TenderSegment extends StatelessWidget {
  const _TenderSegment({
    required this.label,
    required this.amount,
    required this.color,
    required this.width,
  });

  final String label;
  final int amount;
  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) {
    final String amountText = formatTablePkr(amount.toDouble());
    final String full = '$label: $amountText';
    final String text = width >= (full.length * 6.2) ? full : amountText;
    return ColoredBox(
      color: color,
      child: Center(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 10,
            height: 1,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.label,
    required this.background,
    required this.foreground,
    required this.height,
    this.icon,
    this.borderColor,
    this.shadows,
    this.onTap,
  });

  final String label;
  final Color background;
  final Color foreground;
  final double height;
  final IconData? icon;
  final Color? borderColor;
  final List<BoxShadow>? shadows;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final RoundedRectangleBorder shape = _controlShape(
      side: BorderSide(color: borderColor ?? background),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_kControlRadius),
        boxShadow: shadows ?? const <BoxShadow>[],
      ),
      child: Material(
        color: background,
        shape: shape,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          hoverColor: tokens.ink.withValues(alpha: 0.08),
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Icon(icon, size: 14, color: foreground),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        height: 1,
                        color: foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WaitingChip extends StatelessWidget {
  const _WaitingChip({required this.height, required this.tokens});

  final double height;
  final DispensrTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: tokens.coral.withValues(alpha: 0.14),
      shape: _controlShape(),
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: tokens.coral,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  'Waiting',
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    height: 1,
                    color: tokens.coral,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellField extends StatefulWidget {
  const _ShellField({
    required this.hint,
    required this.icon,
    required this.controller,
    required this.onTap,
    required this.textInputAction,
    this.inlineLabel,
    this.focusNode,
    this.onSubmitted,
    this.onChanged,
    this.keyboardType,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.amount = false,
    this.height = _kFieldHeight,
  });

  final String hint;
  final String? inlineLabel;
  final IconData icon;
  final double height;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final VoidCallback onTap;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final bool amount;

  @override
  State<_ShellField> createState() => _ShellFieldState();
}

class _ShellFieldState extends State<_ShellField> {
  FocusNode? _ownedFocus;
  late FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _bindFocus();
  }

  @override
  void didUpdateWidget(_ShellField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _ownedFocus?.dispose();
      _ownedFocus = null;
      _bindFocus();
    }
  }

  void _bindFocus() {
    final FocusNode? external = widget.focusNode;
    if (external != null) {
      _focus = external;
    } else {
      _ownedFocus = FocusNode();
      _focus = _ownedFocus!;
    }
  }

  @override
  void dispose() {
    _ownedFocus?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final bool amount = widget.amount;
    final double fontSize = amount ? 14 : 13;
    final TextStyle fieldStyle = TextStyle(
      fontFamily: 'Roboto',
      fontSize: fontSize,
      fontWeight: amount ? FontWeight.w700 : FontWeight.w500,
      height: 1,
      color: tokens.ink,
    );
    final String? label = widget.inlineLabel;
    return SizedBox(
      height: widget.height,
      child: TextField(
        controller: widget.controller,
        focusNode: _focus,
        onTap: widget.onTap,
        maxLines: 1,
        textAlign: amount ? TextAlign.right : TextAlign.left,
        textAlignVertical: TextAlignVertical.center,
        textInputAction: widget.textInputAction,
        textCapitalization: widget.textCapitalization,
        onSubmitted: widget.onSubmitted,
        onChanged: widget.onChanged,
        keyboardType: widget.keyboardType,
        inputFormatters: widget.inputFormatters,
        cursorHeight: fontSize,
        style: fieldStyle,
        decoration: _outlineField(
          tokens: tokens,
          hint: widget.hint,
          hintStyle: fieldStyle.copyWith(
            fontWeight: FontWeight.w400,
            color: tokens.inkMuted.withValues(alpha: 0.72),
          ),
          prefixIcon: Icon(widget.icon, size: 14, color: tokens.inkMuted),
          prefixText: label == null ? null : '$label  ',
          prefixStyle: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            height: 1,
            color: tokens.inkMuted,
          ),
        ),
      ),
    );
  }
}

InputDecoration _outlineField({
  required DispensrTokens tokens,
  required String hint,
  required TextStyle hintStyle,
  Widget? prefixIcon,
  String? prefixText,
  TextStyle? prefixStyle,
  EdgeInsetsGeometry contentPadding = const EdgeInsets.symmetric(
    vertical: 14,
    horizontal: 12,
  ),
}) {
  final OutlineInputBorder line = OutlineInputBorder(
    borderRadius: BorderRadius.circular(_kControlRadius),
    borderSide: BorderSide(color: tokens.line),
  );
  final OutlineInputBorder focus = OutlineInputBorder(
    borderRadius: BorderRadius.circular(_kControlRadius),
    borderSide: BorderSide(color: tokens.coral),
  );
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: tokens.card,
    hintText: hint,
    hintStyle: hintStyle,
    counterText: '',
    contentPadding: contentPadding,
    prefixIcon: prefixIcon,
    prefixIconConstraints: const BoxConstraints(
      minWidth: 36,
      minHeight: 0,
      maxHeight: 20,
    ),
    prefixText: prefixText,
    prefixStyle: prefixStyle,
    border: line,
    enabledBorder: line,
    focusedBorder: focus,
    disabledBorder: line,
    errorBorder: line,
    focusedErrorBorder: focus,
  );
}

const double _kPillHeight = 30;
const double _kControlHeight = 36;
const double _kFieldHeight = _kControlHeight;
const double _kVehicleHeight = _kControlHeight;
const double _kButtonHeight = 38;
const double _kControlRadius = 12;
const double _kGap = 2;
const Color _kAccountBlue = Color(0xFF4A7FA7);

List<BoxShadow> _coralButtonShadow(DispensrTokens tokens) {
  return <BoxShadow>[
    BoxShadow(
      color: tokens.coral.withValues(alpha: 0.35),
      blurRadius: 10,
      offset: const Offset(0, 3),
    ),
  ];
}

RoundedRectangleBorder _controlShape({BorderSide side = BorderSide.none}) {
  return RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(_kControlRadius),
    side: side,
  );
}

enum _PayPill { cash, udhaar, account }

enum _AccountRail { bank, easyPaisa }
