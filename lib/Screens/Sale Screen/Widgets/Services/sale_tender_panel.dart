import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/dispensr_theme.dart';
import '../../../../features/station/domain/dispenser_models.dart';
import '../../../../features/station/domain/money_format.dart';
import '../../../../features/station/domain/sale_fulfillment.dart';

enum SaleTenderPill { cash, udhaar, account }

enum SaleAccountRail { bank, easyPaisa }

int readTenderRupees(String text) {
  return int.tryParse(text.trim()) ?? 0;
}

void writeTenderRupees(TextEditingController controller, int rupees) {
  final String next = rupees <= 0 ? '' : '$rupees';
  if (controller.text == next) {
    return;
  }
  controller.value = TextEditingValue(
    text: next,
    selection: TextSelection.collapsed(offset: next.length),
  );
}

/// Seeds Cash and Account the same way the sale screen does when the pill changes.
void seedSaleTenderPill({
  required SaleTenderPill next,
  required int saleRupees,
  required TextEditingController cash,
  required TextEditingController account,
  required void Function(bool syncing) setSyncing,
}) {
  final int cashRupees = readTenderRupees(cash.text);
  final int accountRupees = readTenderRupees(account.text);
  if (next == SaleTenderPill.account) {
    if (cashRupees + accountRupees == saleRupees) {
      return;
    }
    setSyncing(true);
    cash.clear();
    writeTenderRupees(account, saleRupees);
    setSyncing(false);
    return;
  }
  if (next == SaleTenderPill.udhaar) {
    if (cashRupees + accountRupees >= saleRupees) {
      cash.clear();
      account.clear();
    }
    return;
  }
  cash.clear();
  account.clear();
}

bool saleTenderUdhaarOverflow({
  required SaleTenderPill pill,
  required int saleRupees,
  required int cash,
  required int account,
}) {
  return pill == SaleTenderPill.udhaar &&
      saleRupees > 0 &&
      cash + account >= saleRupees;
}

bool saleTenderReady({
  required SaleTenderPill pill,
  required int saleRupees,
  required int cash,
  required int account,
  required bool customerMatched,
}) {
  if (cash < 0 || account < 0) {
    return false;
  }
  switch (pill) {
    case SaleTenderPill.cash:
      return true;
    case SaleTenderPill.account:
      return account > saleRupees || cash + account == saleRupees;
    case SaleTenderPill.udhaar:
      return customerMatched && cash + account < saleRupees;
  }
}

/// Cash, Udhaar, and Account controls shared by the sale sheet and edit sale.
class SaleTenderPanel extends StatelessWidget {
  const SaleTenderPanel({
    super.key,
    required this.pill,
    required this.rail,
    required this.onPill,
    required this.onRail,
    required this.customerId,
    required this.customerName,
    required this.cash,
    required this.account,
    required this.saleRupees,
    required this.onSplitChanged,
    required this.vehicle,
    this.onFieldTap,
    this.onSubmitted,
    this.vehicleFocus,
    this.enabled = true,
    this.showVehicleHint = false,
    this.header,
    this.footer,
  });

  final SaleTenderPill pill;
  final SaleAccountRail rail;
  final ValueChanged<SaleTenderPill> onPill;
  final ValueChanged<SaleAccountRail> onRail;
  final TextEditingController customerId;
  final TextEditingController customerName;
  final TextEditingController cash;
  final TextEditingController account;
  final TextEditingController vehicle;
  final int saleRupees;
  final ValueChanged<String> onSplitChanged;
  final VoidCallback? onFieldTap;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? vehicleFocus;
  final bool enabled;
  final bool showVehicleHint;
  final Widget? header;
  final Widget? footer;

  int get _cashRupees => readTenderRupees(cash.text);

  int get _accountRupees => readTenderRupees(account.text);

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final bool showUdhaar = enabled && pill == SaleTenderPill.udhaar;
    final bool showAccount = enabled && pill == SaleTenderPill.account;
    final int methodIndex = enabled ? pill.index : 0;
    final VoidCallback tap = onFieldTap ?? () {};
    return Container(
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
          if (header != null) ...<Widget>[
            header!,
            const SizedBox(height: _kGap),
          ],
          _SlidingPill(
            selectedIndex: methodIndex,
            enabled: enabled,
            segments: <_PillSegment>[
              _PillSegment(
                label: 'Cash',
                icon: Icons.payments_outlined,
                onTap: () => onPill(SaleTenderPill.cash),
              ),
              _PillSegment(
                label: 'Udhaar',
                icon: Icons.person_outline,
                onTap: () => onPill(SaleTenderPill.udhaar),
              ),
              _PillSegment(
                label: 'Account',
                icon: Icons.credit_card_outlined,
                onTap: () => onPill(SaleTenderPill.account),
              ),
            ],
          ),
          if (showUdhaar) ...<Widget>[
            const SizedBox(height: _kGap),
            _UdhaarPartyField(
              idController: customerId,
              nameController: customerName,
              onTap: tap,
              onSubmitted: onSubmitted ?? (_) {},
            ),
            const SizedBox(height: _kGap),
            _SplitAmountRow(
              cash: cash,
              account: account,
              onTap: tap,
              onChanged: onSplitChanged,
              onSubmitted: onSubmitted ?? (_) {},
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
              child: _TenderBar(
                cash: _cashRupees,
                account: _accountRupees,
                remainder: udhaarCreditRupees(
                  saleAmount: saleRupees.toDouble(),
                  cashAmount: _cashRupees.toDouble(),
                  accountAmount: _accountRupees.toDouble(),
                ),
                remainderLabel: 'Udhaar',
              ),
            ),
          ],
          if (showAccount) ...<Widget>[
            const SizedBox(height: _kGap),
            _SlidingPill(
              selectedIndex: rail == SaleAccountRail.bank ? 0 : 1,
              segments: <_PillSegment>[
                _PillSegment(
                  label: 'Bank',
                  icon: Icons.account_balance_outlined,
                  onTap: () => onRail(SaleAccountRail.bank),
                ),
                _PillSegment(
                  label: 'EasyPaisa',
                  icon: Icons.smartphone_outlined,
                  onTap: () => onRail(SaleAccountRail.easyPaisa),
                ),
              ],
            ),
            const SizedBox(height: _kGap),
            _SplitAmountRow(
              cash: cash,
              account: account,
              onTap: tap,
              onChanged: onSplitChanged,
              onSubmitted: onSubmitted ?? (_) {},
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
              child: _TenderBar(
                cash: _cashRupees,
                account: _accountRupees,
                remainder: accountOverpayBaqaya(
                  saleAmount: saleRupees.toDouble(),
                  accountNow: _accountRupees.toDouble(),
                ),
                remainderLabel: 'Baqaya',
              ),
            ),
          ],
          const SizedBox(height: _kGap),
          _ShellField(
            hint: 'Vehicle number',
            icon: Icons.directions_car_outlined,
            height: _kControlHeight,
            controller: vehicle,
            focusNode: vehicleFocus,
            onTap: tap,
            textInputAction: showUdhaar
                ? TextInputAction.next
                : TextInputAction.done,
            inputFormatters: <TextInputFormatter>[
              VehicleRegistrationFormatter(),
            ],
            textCapitalization: TextCapitalization.characters,
            onSubmitted: showUdhaar ? null : onSubmitted,
          ),
          if (showVehicleHint) ...<Widget>[
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
          if (footer != null) ...<Widget>[
            const SizedBox(height: _kGap),
            footer!,
          ],
        ],
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
                    <int>[
                      for (final _TenderSlice slice in slices) slice.amount,
                    ],
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

List<double> _tenderSliceWidths(double maxWidth, List<int> amounts) {
  const double minSlice = 32;
  final int count = amounts.length;
  if (count == 0 || maxWidth <= 0) {
    return <double>[];
  }
  final int sum = amounts.fold<int>(
    0,
    (int total, int amount) => total + amount,
  );
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
    this.height = _kControlHeight,
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
const double _kControlRadius = 12;
const double _kGap = 2;
const Color _kAccountBlue = Color(0xFF4A7FA7);
