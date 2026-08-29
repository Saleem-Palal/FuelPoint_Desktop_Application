import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/dispensr_theme.dart';
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
  final TextEditingController _customer = TextEditingController();
  final TextEditingController _vehicle = TextEditingController();

  _PayPill _pill = _PayPill.cash;
  _AccountRail _rail = _AccountRail.bank;
  bool _submitting = false;

  bool get _udhaarRequiresName => _pill == _PayPill.udhaar;

  void _selectThisUnit() {
    ref.read(selectedDispenserIndexProvider.notifier).state = widget.unitId;
  }

  @override
  void initState() {
    super.initState();
    _customer.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
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

  InputDecoration _fieldDecoration({
    required String label,
    required String hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    );
  }

  bool _canSubmit(DispenserBay bay) {
    if (_submitting || !bay.canConfirmPayment) {
      return false;
    }
    if (_udhaarRequiresName && _customer.text.trim().isEmpty) {
      return false;
    }
    return true;
  }

  Future<void> _confirm() async {
    _selectThisUnit();
    final DispenserBay bay = ref
        .read(stationControllerProvider)
        .bay(widget.unitId);
    if (_submitting) {
      return;
    }
    if (_udhaarRequiresName && _customer.text.trim().isEmpty) {
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
            customerName: _udhaarRequiresName ? _customer.text : '',
            vehicleNo: _vehicle.text,
            payment: _paymentMethod,
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
      _customer.clear();
      _vehicle.clear();
      setState(() {
        _submitting = false;
      });
      showUnitReceiptOverlay(ref, txn);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not commit this sale')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
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
    final DsPillVariant actionVariant;
    final VoidCallback? actionPressed;
    if (bay.isOffline) {
      actionLabel = 'Unit Offline';
      actionVariant = DsPillVariant.muted;
      actionPressed = null;
    } else if (bay.isDispensing) {
      actionLabel = 'Confirm Payment';
      actionVariant = DsPillVariant.coral;
      actionPressed = null;
    } else if (bay.canConfirmPayment) {
      actionLabel = 'Confirm Payment';
      actionVariant = DsPillVariant.coral;
      actionPressed = _canSubmit(bay) ? _confirm : null;
    } else {
      actionLabel = 'Waiting...';
      actionVariant = DsPillVariant.muted;
      actionPressed = null;
    }

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter): _confirm,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _confirm,
      },
      child: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'PAYMENT METHOD',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w700,
                fontSize: 8,
                letterSpacing: 0.8,
                color: tokens.inkMuted,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Expanded(
                  child: _MethodPill(
                    label: 'Cash',
                    icon: Icons.payments_outlined,
                    radius: 8,
                    selected: _pill == _PayPill.cash,
                    onTap: () {
                      _selectThisUnit();
                      setState(() {
                        _pill = _PayPill.cash;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _MethodPill(
                    label: 'Udhaar',
                    icon: Icons.handshake_outlined,
                    radius: 8,
                    selected: _pill == _PayPill.udhaar,
                    onTap: () {
                      _selectThisUnit();
                      setState(() {
                        _pill = _PayPill.udhaar;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _MethodPill(
                    label: 'Account',
                    icon: Icons.account_balance_outlined,
                    radius: 8,
                    selected: _pill == _PayPill.account,
                    onTap: () {
                      _selectThisUnit();
                      setState(() {
                        _pill = _PayPill.account;
                      });
                    },
                  ),
                ),
              ],
            ),
            if (_pill == _PayPill.account) ...<Widget>[
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _MethodPill(
                      label: 'Bank',
                      icon: Icons.account_balance,
                      radius: 4,
                      compact: true,
                      selected: _rail == _AccountRail.bank,
                      onTap: () {
                        _selectThisUnit();
                        setState(() {
                          _rail = _AccountRail.bank;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _MethodPill(
                      label: 'EasyPaisa',
                      icon: Icons.phone_android_outlined,
                      radius: 4,
                      compact: true,
                      selected: _rail == _AccountRail.easyPaisa,
                      onTap: () {
                        _selectThisUnit();
                        setState(() {
                          _rail = _AccountRail.easyPaisa;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: _vehicle,
              textInputAction: _udhaarRequiresName
                  ? TextInputAction.next
                  : TextInputAction.done,
              onTap: _selectThisUnit,
              onSubmitted: (_) => _confirm(),
              style: const TextStyle(fontFamily: 'Roboto', fontSize: 12),
              decoration: _fieldDecoration(
                label: 'Vehicle Number',
                hint: 'Optional',
              ),
            ),
            if (_udhaarRequiresName) ...<Widget>[
              const SizedBox(height: 6),
              TextField(
                controller: _customer,
                textInputAction: TextInputAction.done,
                onTap: _selectThisUnit,
                onSubmitted: (_) => _confirm(),
                style: const TextStyle(fontFamily: 'Roboto', fontSize: 12),
                decoration: _fieldDecoration(
                  label: 'Customer Name',
                  hint: 'Required for Udhaar',
                ),
              ),
            ],
            const SizedBox(height: 8),
            DsPillButton(
              label: actionLabel,
              variant: actionVariant,
              onPressed: actionPressed,
              compact: true,
            ),
          ],
        ),
      ),
    );
  }
}

enum _PayPill { cash, udhaar, account }

enum _AccountRail { bank, easyPaisa }

class _MethodPill extends StatelessWidget {
  const _MethodPill({
    required this.label,
    required this.icon,
    required this.radius,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final IconData icon;
  final double radius;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final Color fg = selected ? tokens.coralPressed : tokens.inkMuted;
    final Color bg = selected
        ? tokens.coral.withValues(alpha: 0.14)
        : tokens.card;
    final Color border = selected ? tokens.coral : tokens.line;
    final BorderRadius radii = BorderRadius.circular(radius);

    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: radii,
        side: BorderSide(color: border),
      ),
      child: InkWell(
        onTap: onTap,
        canRequestFocus: false,
        borderRadius: radii,
        hoverColor: tokens.ink.withValues(alpha: 0.05),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 4,
            vertical: compact ? 4 : 6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: compact ? 12 : 14, color: fg),
              const SizedBox(height: 2),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w600,
                  fontSize: compact ? 8 : 9,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
