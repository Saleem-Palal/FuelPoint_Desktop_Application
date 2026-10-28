import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/dispensr_theme.dart';
import '../../../../features/customer/domain/customer_models.dart';
import '../../../../features/customer/presentation/customer_providers.dart';
import '../../../../features/station/domain/dispenser_models.dart';
import '../../../../features/station/domain/fuel_precision.dart';
import '../../../../features/station/domain/sale_fulfillment.dart';
import 'sale_tender_panel.dart';
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

  SaleTenderPill _pill = SaleTenderPill.cash;
  SaleAccountRail _rail = SaleAccountRail.bank;
  bool _submitting = false;
  bool _syncingSplit = false;

  bool get _udhaarSelected => _pill == SaleTenderPill.udhaar;

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
      case SaleTenderPill.cash:
        return PaymentMethod.cash;
      case SaleTenderPill.udhaar:
        return PaymentMethod.udhaar;
      case SaleTenderPill.account:
        return _rail == SaleAccountRail.bank
            ? PaymentMethod.bankAccount
            : PaymentMethod.easyPaisa;
    }
  }

  void _cycleMethod(int delta) {
    if (ref.read(stationControllerProvider).unit(widget.unitId).isTestRun) {
      return;
    }
    const List<SaleTenderPill> methods = <SaleTenderPill>[
      SaleTenderPill.cash,
      SaleTenderPill.udhaar,
      SaleTenderPill.account,
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
      if (_pill != SaleTenderPill.account) {
        _applyPill(SaleTenderPill.account);
        _rail = delta < 0 ? SaleAccountRail.bank : SaleAccountRail.easyPaisa;
      } else {
        int index = _rail == SaleAccountRail.bank ? 0 : 1;
        index = (index + delta) % 2;
        if (index < 0) {
          index += 2;
        }
        _rail = index == 0 ? SaleAccountRail.bank : SaleAccountRail.easyPaisa;
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
    return saleTenderReady(
      pill: _pill,
      saleRupees: _saleRupees,
      cash: _cashRupees,
      account: _accountRupees,
      customerMatched: _matchedCustomer() != null,
    );
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
    if (_pill != SaleTenderPill.account) {
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

  void _applyPill(SaleTenderPill next) {
    seedSaleTenderPill(
      next: next,
      saleRupees: _saleRupees,
      cash: _cashNow,
      account: _accountNow,
      setSyncing: (bool value) {
        _syncingSplit = value;
      },
    );
    _pill = next;
  }

  void _onSplitChanged(String _) {
    if (_syncingSplit) {
      _onFieldChanged();
      return;
    }
    if (saleTenderUdhaarOverflow(
      pill: _pill,
      saleRupees: _saleRupees,
      cash: _cashRupees,
      account: _accountRupees,
    )) {
      setState(() {
        _pill = SaleTenderPill.account;
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
                ReceiptCopy.printedSlipsMessage(draft),
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
        _pill = SaleTenderPill.cash;
        _rail = SaleAccountRail.bank;
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
    return AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        child: SaleTenderPanel(
          pill: _pill,
          rail: _rail,
          enabled: !unit.isTestRun,
          saleRupees: _saleRupees,
          customerId: _customerId,
          customerName: _customer,
          cash: _cashNow,
          account: _accountNow,
          vehicle: _vehicle,
          vehicleFocus: _vehicleFocus,
          showVehicleHint:
              !unit.isTestRun && unit.canConfirmPayment && !_isVehicleValid,
          onFieldTap: _selectThisUnit,
          onSplitChanged: _onSplitChanged,
          onPill: (SaleTenderPill next) {
            _selectThisUnit();
            setState(() {
              _applyPill(next);
            });
          },
          onRail: (SaleAccountRail next) {
            _selectThisUnit();
            setState(() {
              _rail = next;
            });
          },
          header: unit.isTestRun
              ? Text(
                  'Test fill — stock and liters count. Not a sale. Cash unchanged.',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w500,
                    fontSize: 10,
                    height: 1.25,
                    color: tokens.warn,
                  ),
                )
              : null,
          footer: SizedBox(
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
                          icon: actionLabel == 'Confirm' ? Icons.check : null,
                          height: _kButtonHeight,
                          background: confirmOn ? tokens.coral : tokens.card,
                          foreground: confirmOn ? tokens.card : tokens.inkMuted,
                          borderColor: confirmOn ? tokens.coral : tokens.line,
                          shadows: confirmOn ? _coralButtonShadow(tokens) : null,
                          onTap: _canSubmit(unit) ? _confirm : null,
                        ),
                ),
              ],
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

const double _kButtonHeight = 38;
const double _kControlRadius = 12;

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
