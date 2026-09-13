import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/dispensr_theme.dart';
import '../../../../features/customer/domain/customer_models.dart';
import '../../../../features/customer/presentation/customer_providers.dart';
import '../../../../features/station/domain/dispenser_models.dart';
import '../../../../features/station/presentation/station_providers.dart';

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

  _PayPill _pill = _PayPill.cash;
  _AccountRail _rail = _AccountRail.bank;
  bool _submitting = false;

  bool get _udhaarSelected => _pill == _PayPill.udhaar;

  void _selectThisUnit() {
    ref.read(selectedDispenserIndexProvider.notifier).state = widget.unitId;
  }

  @override
  void initState() {
    super.initState();
    _customer.addListener(_onFieldChanged);
    _customerId.addListener(_onCustomerIdChanged);
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
    _vehicle.dispose();
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
    });
  }

  void _cycleRail(int delta) {
    setState(() {
      if (_pill != _PayPill.account) {
        _pill = _PayPill.account;
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

  bool _canSubmit(DispenserBay bay) {
    if (_submitting || !bay.canConfirmPayment) {
      return false;
    }
    if (_udhaarSelected && _matchedCustomer() == null) {
      return false;
    }
    return true;
  }

  bool _canPreview(DispenserBay bay) {
    return !_submitting && bay.canConfirmPayment;
  }

  void _preview() {
    _selectThisUnit();
    final DispenserBay bay = ref
        .read(stationControllerProvider)
        .bay(widget.unitId);
    if (!_canPreview(bay)) {
      return;
    }
    if (_udhaarSelected && _matchedCustomer() == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid customer ID')),
      );
      return;
    }
    final bool shown = ref
        .read(stationControllerProvider.notifier)
        .previewReceiptForBay(
          unitId: widget.unitId,
          customerName: _udhaarSelected ? (_matchedCustomer()?.name ?? '') : '',
          vehicleNo: _vehicle.text,
          payment: _paymentMethod,
        );
    if (!shown && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This bay is not ready to print')),
      );
    }
  }

  Future<void> _confirm() async {
    _selectThisUnit();
    final DispenserBay bay = ref
        .read(stationControllerProvider)
        .bay(widget.unitId);
    if (_submitting) {
      return;
    }
    if (_udhaarSelected && _matchedCustomer() == null) {
      return;
    }
    if (!_canSubmit(bay)) {
      return;
    }
    _submitting = true;
    if (mounted) {
      setState(() {});
    }
    try {
      final SaleTransaction? txn = await ref
          .read(stationControllerProvider.notifier)
          .confirmAndClearBay(
            unitId: widget.unitId,
            customerName: _udhaarSelected
                ? (_matchedCustomer()?.name ?? '')
                : '',
            vehicleNo: _vehicle.text,
            payment: _paymentMethod,
            customerId: _udhaarSelected ? (_matchedCustomer()?.id ?? '') : '',
          );
      if (!mounted) {
        return;
      }
      if (txn == null) {
        setState(() {
          _submitting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This bay is no longer ready to clear')),
        );
        return;
      }
      _customerId.clear();
      _customer.clear();
      _vehicle.clear();
      setState(() {
        _submitting = false;
      });
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
    final DispenserBay bay = ref
        .watch(stationControllerProvider)
        .bay(widget.unitId);

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
    if (bay.canConfirmPayment) {
      actionLabel = 'Confirm';
      actionEnabled = _canSubmit(bay);
    } else if (bay.isDispensing) {
      actionLabel = 'Confirm';
      actionEnabled = false;
    } else if (bay.isOffline) {
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
                'Payment method',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                  color: tokens.inkMuted,
                ),
              ),
              const SizedBox(height: _kGap),
              Row(
                children: <Widget>[
                  _MethodChip(
                    label: 'Cash',
                    icon: Icons.payments_outlined,
                    selected: _pill == _PayPill.cash,
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
                    selected: _pill == _PayPill.udhaar,
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
                    selected: _pill == _PayPill.account,
                    onTap: () {
                      _selectThisUnit();
                      setState(() {
                        _pill = _PayPill.account;
                      });
                    },
                  ),
                ],
              ),
              if (_pill == _PayPill.account) ...<Widget>[
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
              ],
              const SizedBox(height: _kGap),
              _ShellField(
                tokens: tokens,
                hint: 'Vehicle number (optional)',
                icon: Icons.directions_car_outlined,
                controller: _vehicle,
                onTap: _selectThisUnit,
                textInputAction: _udhaarSelected
                    ? TextInputAction.next
                    : TextInputAction.done,
                onSubmitted: _udhaarSelected ? null : (_) => _confirm(),
              ),
              if (_udhaarSelected) ...<Widget>[
                const SizedBox(height: _kGap),
                _CustomerPickRow(
                  tokens: tokens,
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
                      background: _canPreview(bay) ? tokens.ink : tokens.line,
                      foreground: _canPreview(bay)
                          ? tokens.card
                          : tokens.inkMuted,
                      onTap: _canPreview(bay) ? _preview : null,
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
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final Color foreground = selected ? tokens.card : tokens.ink;
    final RoundedRectangleBorder shape = _controlShape(
      side: selected ? BorderSide.none : BorderSide(color: tokens.line),
    );
    return Expanded(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_kControlRadius),
          boxShadow: selected
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
          color: selected ? tokens.coral : tokens.card,
          shape: shape,
          child: InkWell(
            onTap: onTap,
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
    this.onSubmitted,
  });

  final DispensrTokens tokens;
  final String hint;
  final IconData icon;
  final TextEditingController controller;
  final VoidCallback onTap;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _kFieldHeight,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(_kControlRadius),
        border: Border.all(color: tokens.line),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: tokens.inkMuted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onTap: onTap,
              maxLines: 1,
              textAlignVertical: TextAlignVertical.center,
              textInputAction: textInputAction,
              onSubmitted: onSubmitted,
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

class _CustomerPickRow extends StatelessWidget {
  const _CustomerPickRow({
    required this.tokens,
    required this.idController,
    required this.nameController,
    required this.onTap,
    required this.onSubmitted,
  });

  final DispensrTokens tokens;
  final TextEditingController idController;
  final TextEditingController nameController;
  final VoidCallback onTap;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _kFieldHeight,
      padding: const EdgeInsets.fromLTRB(4, 0, 10, 0),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(_kControlRadius),
        border: Border.all(color: tokens.line),
      ),
      child: Row(
        children: <Widget>[
          _CustomerIdBadge(
            tokens: tokens,
            controller: idController,
            onTap: onTap,
            onSubmitted: onSubmitted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  nameController.text.isEmpty
                      ? 'Customer name'
                      : nameController.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: nameController.text.isEmpty
                        ? tokens.inkMuted.withValues(alpha: 0.72)
                        : tokens.ink,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerIdBadge extends StatelessWidget {
  const _CustomerIdBadge({
    required this.tokens,
    required this.controller,
    required this.onTap,
    required this.onSubmitted,
  });

  final DispensrTokens tokens;
  final TextEditingController controller;
  final VoidCallback onTap;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _kIdBadgeSize,
      height: _kIdBadgeSize,
      child: Material(
        color: tokens.ink,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: Align(
          alignment: Alignment.center,
          child: TextField(
            controller: controller,
            onTap: onTap,
            maxLength: 4,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            textAlign: TextAlign.center,
            textAlignVertical: TextAlignVertical.center,
            textInputAction: TextInputAction.done,
            onSubmitted: onSubmitted,
            scrollPadding: EdgeInsets.zero,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w700,
              fontSize: 11,
              height: 1,
              leadingDistribution: TextLeadingDistribution.even,
              color: tokens.card,
            ),
            strutStyle: const StrutStyle(
              fontFamily: 'Roboto',
              fontSize: 11,
              height: 1,
              forceStrutHeight: true,
              leadingDistribution: TextLeadingDistribution.even,
            ),
            cursorColor: tokens.card,
            decoration: InputDecoration(
              isCollapsed: true,
              isDense: true,
              filled: false,
              counterText: '',
              hintText: 'ID',
              hintStyle: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w600,
                fontSize: 9,
                height: 1,
                leadingDistribution: TextLeadingDistribution.even,
                color: tokens.card.withValues(alpha: 0.55),
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ),
    );
  }
}

const double _kControlHeight = 32;
const double _kFieldHeight = 36;
const double _kControlRadius = 10;
const double _kGap = 6;
const double _kIdBadgeSize = 28;

RoundedRectangleBorder _controlShape({BorderSide side = BorderSide.none}) {
  return RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(_kControlRadius),
    side: side,
  );
}

enum _PayPill { cash, udhaar, account }

enum _AccountRail { bank, easyPaisa }
