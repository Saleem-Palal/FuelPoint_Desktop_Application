import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/dispensr_theme.dart';
import '../../../../features/customer/domain/customer_models.dart';
import '../../../../features/customer/presentation/customer_providers.dart';
import '../../../../features/customer/presentation/widgets/customer_pick_field.dart';
import '../../../../features/station/domain/dispenser_models.dart';
import '../../../../features/station/domain/fuel_precision.dart';
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
      _pill = methods[index];
      if (_pill == _PayPill.account) {
        _seedAccountSplit();
      }
    });
  }

  void _cycleRail(int delta) {
    if (ref.read(stationControllerProvider).unit(widget.unitId).isTestRun) {
      return;
    }
    setState(() {
      if (_pill != _PayPill.account) {
        _pill = _PayPill.account;
        _rail = delta < 0 ? _AccountRail.bank : _AccountRail.easyPaisa;
        _seedAccountSplit();
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
    if (!unit.isTestRun && _udhaarSelected && _matchedCustomer() == null) {
      return false;
    }
    return true;
  }

  bool _canPreview(DispenserUnit unit) {
    return !_submitting &&
        unit.canConfirmPayment &&
        (unit.isTestRun || _isVehicleValid);
  }

  double get _cashNowValue {
    return double.tryParse(_cashNow.text.trim()) ?? 0;
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

  void _seedAccountSplit() {
    _syncingSplit = true;
    _cashNow.clear();
    _setSplitText(_accountNow, _saleRupees);
    _syncingSplit = false;
  }

  void _onCashSplitChanged(String _) {
    if (_syncingSplit) {
      _onFieldChanged();
      return;
    }
    _syncingSplit = true;
    final int sale = _saleRupees;
    final int cash = (int.tryParse(_cashNow.text.trim()) ?? 0).clamp(0, sale);
    _setSplitText(_cashNow, cash);
    _setSplitText(_accountNow, sale - cash);
    _syncingSplit = false;
    _onFieldChanged();
  }

  void _onAccountSplitChanged(String _) {
    if (_syncingSplit) {
      _onFieldChanged();
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
    final bool actionEnabled;
    if (unit.canConfirmPayment) {
      actionLabel = 'Confirm';
      actionEnabled = _canSubmit(unit);
    } else if (unit.isDispensing) {
      actionLabel = 'Confirm';
      actionEnabled = false;
    } else if (unit.isOffline) {
      actionLabel = 'Unit Offline';
      actionEnabled = false;
    } else {
      actionLabel = 'Waiting';
      actionEnabled = false;
    }

    final bool waitingLook = !actionEnabled && actionLabel == 'Waiting';

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
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
          decoration: BoxDecoration(
            color: tokens.canvas,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: tokens.line),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                unit.isTestRun
                    ? 'Test fill — stock and liters count. Not a sale. Cash unchanged.'
                    : 'Payment method',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w500,
                  fontSize: unit.isTestRun ? 10 : 13,
                  height: unit.isTestRun ? 1.25 : null,
                  color: unit.isTestRun ? tokens.warn : tokens.inkMuted,
                ),
              ),
              const SizedBox(height: _kGap),
              Row(
                children: <Widget>[
                  _MethodChip(
                    label: 'Cash',
                    icon: Icons.payments_outlined,
                    selected: unit.isTestRun || _pill == _PayPill.cash,
                    enabled: !unit.isTestRun,
                    onTap: () {
                      _selectThisUnit();
                      setState(() {
                        _pill = _PayPill.cash;
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  _MethodChip(
                    label: 'Udhaar',
                    icon: Icons.person_outline,
                    selected: !unit.isTestRun && _pill == _PayPill.udhaar,
                    enabled: !unit.isTestRun,
                    onTap: () {
                      _selectThisUnit();
                      setState(() {
                        _pill = _PayPill.udhaar;
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  _MethodChip(
                    label: 'Account',
                    icon: Icons.credit_card_outlined,
                    selected: !unit.isTestRun && _pill == _PayPill.account,
                    enabled: !unit.isTestRun,
                    onTap: () {
                      _selectThisUnit();
                      setState(() {
                        _pill = _PayPill.account;
                        _seedAccountSplit();
                      });
                    },
                  ),
                ],
              ),
              if (!unit.isTestRun && _pill == _PayPill.account) ...<Widget>[
                const SizedBox(height: _kGap),
                Row(
                  children: <Widget>[
                    _MethodChip(
                      label: 'Bank',
                      icon: Icons.account_balance,
                      selected: _rail == _AccountRail.bank,
                      onTap: () {
                        _selectThisUnit();
                        setState(() {
                          _rail = _AccountRail.bank;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    _MethodChip(
                      label: 'EasyPaisa',
                      icon: Icons.phone_android_outlined,
                      selected: _rail == _AccountRail.easyPaisa,
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: _ShellField(
                        tokens: tokens,
                        hint: '0',
                        inlineLabel: 'Cash',
                        icon: Icons.payments_outlined,
                        controller: _cashNow,
                        onTap: _selectThisUnit,
                        textInputAction: TextInputAction.next,
                        keyboardType: TextInputType.number,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: _onCashSplitChanged,
                        onSubmitted: (_) => _confirm(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ShellField(
                        tokens: tokens,
                        hint: '0',
                        inlineLabel: 'Account',
                        icon: Icons.account_balance_outlined,
                        controller: _accountNow,
                        onTap: _selectThisUnit,
                        textInputAction: TextInputAction.done,
                        keyboardType: TextInputType.number,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: _onAccountSplitChanged,
                        onSubmitted: (_) => _confirm(),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: _kGap),
              _ShellField(
                tokens: tokens,
                hint: 'Vehicle number',
                icon: Icons.directions_car_outlined,
                controller: _vehicle,
                focusNode: _vehicleFocus,
                borderColor: unit.isTestRun
                    ? tokens.line
                    : (_isVehicleValid
                          ? tokens.good
                          : (_vehicleFocus.hasFocus
                                ? tokens.warn
                                : tokens.line)),
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
              if (!unit.isTestRun && _udhaarSelected) ...<Widget>[
                const SizedBox(height: _kGap),
                CustomerPickField(
                  idController: _customerId,
                  nameController: _customer,
                  onTap: _selectThisUnit,
                  onSubmitted: (_) => _confirm(),
                ),
              ],
              const SizedBox(height: _kGap),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _ActionChip(
                      label: 'Print',
                      icon: Icons.print_outlined,
                      height: _kControlHeight,
                      background: _canPreview(unit) ? tokens.ink : tokens.line,
                      foreground: _canPreview(unit)
                          ? tokens.card
                          : tokens.inkMuted,
                      onTap: _canPreview(unit) ? _preview : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: waitingLook
                        ? _WaitingChip(height: _kControlHeight, tokens: tokens)
                        : _ActionChip(
                            label: actionLabel,
                            height: _kControlHeight,
                            background: actionEnabled
                                ? tokens.coral
                                : tokens.line,
                            foreground: actionEnabled
                                ? tokens.card
                                : tokens.inkMuted,
                            shadows: actionEnabled
                                ? <BoxShadow>[
                                    BoxShadow(
                                      color: tokens.coral.withValues(
                                        alpha: 0.38,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
                                : null,
                            onTap: actionEnabled ? _confirm : null,
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

class _MethodChip extends StatelessWidget {
  const _MethodChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final Color foreground = selected
        ? tokens.card
        : (enabled ? tokens.ink : tokens.inkMuted);
    final RoundedRectangleBorder shape = _controlShape(
      side: selected ? BorderSide.none : BorderSide(color: tokens.line),
    );
    return Expanded(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_kControlRadius),
          boxShadow: selected && enabled
              ? <BoxShadow>[
                  BoxShadow(
                    color: tokens.coral.withValues(alpha: 0.32),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : const <BoxShadow>[],
        ),
        child: Material(
          color: selected
              ? (enabled ? tokens.coral : tokens.coral.withValues(alpha: 0.55))
              : (enabled ? tokens.card : tokens.line),
          shape: shape,
          child: InkWell(
            onTap: enabled ? onTap : null,
            customBorder: shape,
            hoverColor: tokens.ink.withValues(alpha: 0.06),
            child: SizedBox(
              height: _kControlHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(icon, size: 14, color: foreground),
                      const SizedBox(width: 5),
                      Text(
                        label,
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                          color: foreground,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
    this.shadows,
    this.onTap,
  });

  final String label;
  final Color background;
  final Color foreground;
  final double height;
  final IconData? icon;
  final List<BoxShadow>? shadows;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final RoundedRectangleBorder shape = _controlShape();
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
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (icon != null) ...<Widget>[
                      Icon(icon, size: 14, color: foreground),
                      const SizedBox(width: 5),
                    ],
                    Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: foreground,
                      ),
                    ),
                  ],
                ),
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
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: tokens.coral,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Waiting',
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
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

class _ShellField extends StatelessWidget {
  const _ShellField({
    required this.tokens,
    required this.hint,
    required this.icon,
    required this.controller,
    required this.onTap,
    required this.textInputAction,
    this.inlineLabel,
    this.focusNode,
    this.borderColor,
    this.onSubmitted,
    this.onChanged,
    this.keyboardType,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
  });

  final DispensrTokens tokens;
  final String hint;
  final String? inlineLabel;
  final IconData icon;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final Color? borderColor;
  final VoidCallback onTap;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _kFieldHeight,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(_kControlRadius),
        border: Border.all(color: borderColor ?? tokens.line),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: tokens.inkMuted),
          if (inlineLabel case final String label) ...<Widget>[
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: tokens.inkMuted,
              ),
            ),
          ],
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onTap: onTap,
              maxLines: 1,
              textAlignVertical: TextAlignVertical.center,
              textInputAction: textInputAction,
              textCapitalization: textCapitalization,
              onSubmitted: onSubmitted,
              onChanged: onChanged,
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.1,
                color: tokens.ink,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: hint,
                hintStyle: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: tokens.inkMuted.withValues(alpha: 0.72),
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const double _kControlHeight = 32;
const double _kFieldHeight = 36;
const double _kControlRadius = 10;
const double _kGap = 6;

RoundedRectangleBorder _controlShape({BorderSide side = BorderSide.none}) {
  return RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(_kControlRadius),
    side: side,
  );
}

enum _PayPill { cash, udhaar, account }

enum _AccountRail { bank, easyPaisa }
