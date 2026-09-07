import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/dispensr_theme.dart';
import '../../core/widgets/app_screen_header.dart';
import '../../core/widgets/fuel_point_stat_card.dart';
import '../../core/widgets/responsive_layout.dart';
import '../../core/widgets/segment_lcd.dart';
import '../../features/shift/presentation/shift_providers.dart';
import '../../features/station/data/purchase_repository.dart';
import '../../features/station/domain/money_format.dart';
import '../../features/station/presentation/workspace_refresh.dart';
import '../../utils/fuel_formatter.dart';
import 'Widgets/initial_dip_modal_dialog.dart';
import 'purchase_providers.dart';

class PurchaseScreen extends ConsumerStatefulWidget {
  const PurchaseScreen({super.key});

  @override
  ConsumerState<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends ConsumerState<PurchaseScreen> {
  static final FilteringTextInputFormatter _wholeFormatter =
      FilteringTextInputFormatter.allow(RegExp(r'^\d*'));
  static final FilteringTextInputFormatter _amountFormatter =
      FilteringTextInputFormatter.allow(RegExp(r'^[\d,]*'));
  static final FilteringTextInputFormatter _rateFormatter =
      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,8}'));

  final TextEditingController _litersController = TextEditingController();
  final TextEditingController _rateController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _tafseelController = TextEditingController();

  final FocusNode quantityFocus = FocusNode();
  final FocusNode rateFocus = FocusNode();
  final FocusNode amountFocus = FocusNode();
  final FocusNode tafseelFocus = FocusNode();
  final FocusNode submitFocus = FocusNode();

  bool _draftSaved = false;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _litersController.addListener(_onLitersOrRateChanged);
    _rateController.addListener(_onLitersOrRateChanged);
    _amountController.addListener(_onAmountChanged);
    _tafseelController.addListener(_onDraftInputsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(refreshPurchasesFromDatabase(ref));
      quantityFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _litersController.removeListener(_onLitersOrRateChanged);
    _rateController.removeListener(_onLitersOrRateChanged);
    _amountController.removeListener(_onAmountChanged);
    _tafseelController.removeListener(_onDraftInputsChanged);
    _litersController.dispose();
    _rateController.dispose();
    _amountController.dispose();
    _tafseelController.dispose();
    quantityFocus.dispose();
    rateFocus.dispose();
    amountFocus.dispose();
    tafseelFocus.dispose();
    submitFocus.dispose();
    super.dispose();
  }

  void _onDraftInputsChanged() {
    if (!mounted) {
      return;
    }
    setState(() {
      _draftSaved = false;
    });
  }

  void _onLitersOrRateChanged() {
    if (_syncing) {
      return;
    }
    final double amount = _purchasedLiters * _purchaseRate;
    _syncing = true;
    _writeField(_amountController, FuelFormatter.fieldAmount(amount));
    _syncing = false;
    _onDraftInputsChanged();
  }

  void _onAmountChanged() {
    if (_syncing) {
      return;
    }
    final double liters = _purchasedLiters;
    _syncing = true;
    if (liters > 0) {
      _writeField(
        _rateController,
        FuelFormatter.fieldRate(_totalCost / liters),
      );
    }
    _writeField(_amountController, FuelFormatter.fieldAmount(_totalCost));
    _syncing = false;
    _onDraftInputsChanged();
  }

  void _writeField(TextEditingController controller, String next) {
    if (controller.text == next) {
      return;
    }
    controller.text = next;
    controller.selection = TextSelection.collapsed(offset: next.length);
  }

  double _parse(TextEditingController controller) {
    return FuelFormatter.parseGrouped(controller.text);
  }

  double get _purchasedLiters => _parse(_litersController);
  double get _purchaseRate => _parse(_rateController);
  double get _totalCost => _parse(_amountController);

  bool get _inputsReady => _purchasedLiters > 0 && _purchaseRate > 0;

  _LcdStock _availableOf(PurchaseController controller) {
    return _LcdStock(
      amountPkr: controller.overallStockPkr,
      volumeLiters: controller.currentDipLiters,
      rate: controller.weightedAverageRate,
    );
  }

  _LcdStock get _incomingDraft {
    return _LcdStock(
      amountPkr: _totalCost,
      volumeLiters: _purchasedLiters,
      rate: _purchaseRate,
    );
  }

  _LcdStock _projectedOf(PurchaseController controller) {
    final double previousLiters = controller.currentDipLiters;
    final double previousCost = controller.overallStockPkr;
    final double nextLiters = previousLiters + _purchasedLiters;
    final double nextRate = nextLiters == 0
        ? 0
        : (previousCost + _totalCost) / nextLiters;
    return _LcdStock(
      amountPkr: nextLiters * nextRate,
      volumeLiters: nextLiters,
      rate: nextRate,
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _saveDraft() {
    setState(() {
      _draftSaved = true;
    });
    _snack('Draft saved. Add Stock when the tanker figures are final.');
  }

  ({String id, String name, String pin}) _managerCreds() {
    final ShiftWorkspaceState shift = ref.read(shiftWorkspaceProvider);
    return PurchaseRepository.managerCreds(
      activeShift: shift.activeShift,
      managers: shift.managers,
    );
  }

  Future<void> _addStock() async {
    if (!_inputsReady) {
      _snack('Enter quantity and rate before adding stock.');
      return;
    }
    final ({String id, String name, String pin}) manager = _managerCreds();
    try {
      await ref
          .read(purchaseControllerProvider)
          .recordPurchase(
            purchasedLiters: _purchasedLiters,
            totalAmountPkr: _totalCost,
            tafseel: _tafseelController.text,
            managerId: manager.id,
            managerName: manager.name,
            managerPin: manager.pin,
          );
    } catch (_) {
      if (!mounted) {
        return;
      }
      _snack(
        'Could not save this purchase. Check the tank figures and try again.',
      );
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _draftSaved = false;
      _litersController.clear();
      _rateController.clear();
      _amountController.clear();
      _tafseelController.clear();
    });
    _snack('Purchase recorded.');
    quantityFocus.requestFocus();
  }

  Future<void> _openInitialDip() async {
    final InitialDipResult? result = await showInitialDipModal(context);
    if (!mounted || result == null) {
      return;
    }
    final ({String id, String name, String pin}) manager = _managerCreds();
    try {
      await ref
          .read(purchaseControllerProvider)
          .recordInitialDip(
            liters: result.liters,
            ratePerLiter: result.rate,
            tafseel: result.description,
            managerId: manager.id,
            managerName: manager.name,
            managerPin: manager.pin,
          );
    } catch (_) {
      if (!mounted) {
        return;
      }
      _snack('Could not save the initial dip. Try again.');
      return;
    }
    if (!mounted) {
      return;
    }
    _snack(
      'Initial dip saved — ${FuelFormatter.formatVolume(result.liters)} at ${FuelFormatter.formatRate(result.rate)}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final PurchaseController controller = ref.watch(purchaseControllerProvider);

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter, control: true):
            _addStock,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true):
            _saveDraft,
      },
      child: ColoredBox(
        color: tokens.canvas,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: AppScreenHeader(
                title: 'Purchase Screen',
                icon: Icons.shopping_cart_outlined,
                invoiceLabel: formatInvoiceNo(controller.nextInvoiceNo),
                trailingAction: AppHeaderActionButton(
                  label: 'Initial Dip Setup',
                  icon: Icons.water_drop_outlined,
                  onPressed: _openInitialDip,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final bool wide = constraints.maxWidth >= 980;
                    final Widget kpis = _KpiBar(controller: controller);
                    final Widget purchase = _EntryCard(
                      litersController: _litersController,
                      rateController: _rateController,
                      amountController: _amountController,
                      tafseelController: _tafseelController,
                      quantityFocus: quantityFocus,
                      rateFocus: rateFocus,
                      amountFocus: amountFocus,
                      tafseelFocus: tafseelFocus,
                      wholeFormatter: _wholeFormatter,
                      amountFormatter: _amountFormatter,
                      rateFormatter: _rateFormatter,
                      onQuantitySubmitted: () => rateFocus.requestFocus(),
                      onRateSubmitted: () => amountFocus.requestFocus(),
                      onAmountSubmitted: () => tafseelFocus.requestFocus(),
                      onTafseelSubmitted: _addStock,
                    );
                    final Widget preview = _StockPreviewPanel(
                      available: _availableOf(controller),
                      incoming: _incomingDraft,
                      projected: _projectedOf(controller),
                      showProjected: _inputsReady,
                    );
                    final Widget history = _LastPurchasesTable(
                      rows: controller.lastTenPurchases,
                      totalCount: controller.purchases.length,
                      fillHeight: wide,
                    );
                    if (!wide) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          kpis,
                          const SizedBox(height: 10),
                          Expanded(
                            child: ListView(
                              children: <Widget>[
                                purchase,
                                const SizedBox(height: 10),
                                preview,
                                const SizedBox(height: 10),
                                history,
                              ],
                            ),
                          ),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        kpis,
                        const SizedBox(height: 10),
                        Expanded(
                          flex: 5,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Expanded(
                                child: ScrollableConstrainedBody(
                                  child: purchase,
                                ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox(
                                width: constraints.maxWidth < 1180 ? 280 : 328,
                                child: ScrollableConstrainedBody(
                                  child: preview,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Expanded(flex: 3, child: history),
                      ],
                    );
                  },
                ),
              ),
            ),
            _PurchaseFooter(
              canAdd: _inputsReady,
              draftSaved: _draftSaved,
              submitFocus: submitFocus,
              onSaveDraft: _saveDraft,
              onAddStock: _addStock,
            ),
          ],
        ),
      ),
    );
  }
}

class _LcdStock {
  const _LcdStock({
    required this.amountPkr,
    required this.volumeLiters,
    required this.rate,
  });

  final double amountPkr;
  final double volumeLiters;
  final double rate;

  static const _LcdStock empty = _LcdStock(
    amountPkr: 0,
    volumeLiters: 0,
    rate: 0,
  );

  bool sameAs(_LcdStock other) {
    return amountPkr == other.amountPkr &&
        volumeLiters == other.volumeLiters &&
        rate == other.rate;
  }

  _LcdStock lerpTo(_LcdStock other, double t) {
    return _LcdStock(
      amountPkr: amountPkr + (other.amountPkr - amountPkr) * t,
      volumeLiters: volumeLiters + (other.volumeLiters - volumeLiters) * t,
      rate: rate + (other.rate - rate) * t,
    );
  }
}

class _KpiBar extends StatelessWidget {
  const _KpiBar({required this.controller});

  final PurchaseController controller;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return ExtentWrap(
      maxCrossAxisExtent: 320,
      children: <Widget>[
        FuelPointStatCard(
          title: 'Overall Stock',
          value: FuelFormatter.formatCurrency(controller.overallStockPkr),
          subtitle: FuelFormatter.formatVolume(controller.currentDipLiters),
          icon: Icons.inventory_2_outlined,
          badgeBackgroundColor: tokens.good.withValues(alpha: 0.12),
          badgeIconColor: tokens.good,
        ),
        FuelPointStatCard(
          title: 'Current Dip',
          value: FuelFormatter.formatVolume(controller.currentDipLiters),
          subtitle: 'Tank volume',
          icon: Icons.water_drop_outlined,
          badgeBackgroundColor: tokens.coral.withValues(alpha: 0.12),
          badgeIconColor: tokens.coral,
        ),
        FuelPointStatCard(
          title: 'Weighted Average Rate',
          value: FuelFormatter.formatRate(controller.weightedAverageRate),
          subtitle: 'WAC',
          icon: Icons.speed_outlined,
          badgeBackgroundColor: tokens.warn.withValues(alpha: 0.12),
          badgeIconColor: tokens.warn,
        ),
      ],
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.litersController,
    required this.rateController,
    required this.amountController,
    required this.tafseelController,
    required this.quantityFocus,
    required this.rateFocus,
    required this.amountFocus,
    required this.tafseelFocus,
    required this.wholeFormatter,
    required this.amountFormatter,
    required this.rateFormatter,
    required this.onQuantitySubmitted,
    required this.onRateSubmitted,
    required this.onAmountSubmitted,
    required this.onTafseelSubmitted,
  });

  final TextEditingController litersController;
  final TextEditingController rateController;
  final TextEditingController amountController;
  final TextEditingController tafseelController;
  final FocusNode quantityFocus;
  final FocusNode rateFocus;
  final FocusNode amountFocus;
  final FocusNode tafseelFocus;
  final TextInputFormatter wholeFormatter;
  final TextInputFormatter amountFormatter;
  final TextInputFormatter rateFormatter;
  final VoidCallback onQuantitySubmitted;
  final VoidCallback onRateSubmitted;
  final VoidCallback onAmountSubmitted;
  final VoidCallback onTafseelSubmitted;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      alignment: Alignment.topLeft,
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.radius20),
        border: Border.all(color: tokens.line),
        boxShadow: tokens.cardShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _SectionTitle(title: 'Diesel Purchase', urdu: 'ڈیزل خریداری'),
          const SizedBox(height: 6),
          _LabeledField(
            label: 'Quantity',
            urdu: 'مقدار',
            controller: litersController,
            focusNode: quantityFocus,
            hint: '0',
            suffix: 'Ltr',
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[wholeFormatter],
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => onQuantitySubmitted(),
          ),
          const SizedBox(height: 2),
          _LabeledField(
            label: 'Rate',
            urdu: 'ریٹ',
            controller: rateController,
            focusNode: rateFocus,
            hint: '0',
            suffix: 'Rs / Ltr',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: <TextInputFormatter>[rateFormatter],
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => onRateSubmitted(),
          ),
          const SizedBox(height: 2),
          _LabeledField(
            label: 'Amount',
            urdu: 'رقم',
            controller: amountController,
            focusNode: amountFocus,
            hint: '0',
            suffix: 'Rs',
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[amountFormatter],
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => onAmountSubmitted(),
          ),
          const SizedBox(height: 2),
          _LabeledField(
            label: 'Tafseel',
            urdu: 'تفصیل',
            controller: tafseelController,
            focusNode: tafseelFocus,
            hint: 'Tanker note / supplier',
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => onTafseelSubmitted(),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.urdu});

  final String title;
  final String urdu;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Row(
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: tokens.coral,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: tokens.ink,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Directionality(
          textDirection: TextDirection.rtl,
          child: Text(
            urdu,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'NotoNastaliqUrdu',
              fontSize: 13,
              height: 1.1,
              color: tokens.inkMuted,
            ),
          ),
        ),
      ],
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.urdu,
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.textInputAction,
    required this.onFieldSubmitted,
    this.suffix,
    this.keyboardType,
    this.inputFormatters,
    this.autofocus = false,
  });

  final String label;
  final String urdu;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final TextInputAction textInputAction;
  final ValueChanged<String> onFieldSubmitted;
  final String? suffix;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w600,
                fontSize: 12,
                height: 1.2,
                color: tokens.inkMuted,
              ),
            ),
            const Spacer(),
            const SizedBox(width: 12),
            Directionality(
              textDirection: TextDirection.rtl,
              child: Text(
                urdu,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'NotoNastaliqUrdu',
                  fontSize: 12,
                  height: 1.1,
                  color: tokens.inkMuted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          autofocus: autofocus,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          textInputAction: textInputAction,
          onFieldSubmitted: onFieldSubmitted,
          textAlignVertical: TextAlignVertical.center,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w600,
            fontSize: 14,
            height: 1.2,
            color: tokens.ink,
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 12,
              horizontal: 16,
            ),
            suffixIcon: suffix == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Align(
                      alignment: Alignment.centerRight,
                      widthFactor: 1,
                      child: Text(
                        suffix!,
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                          height: 1,
                          color: tokens.inkMuted,
                        ),
                      ),
                    ),
                  ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 0,
              minHeight: 0,
            ),
          ),
        ),
      ],
    );
  }
}

class _StockPreviewPanel extends StatelessWidget {
  const _StockPreviewPanel({
    required this.available,
    required this.incoming,
    required this.projected,
    required this.showProjected,
  });

  final _LcdStock available;
  final _LcdStock incoming;
  final _LcdStock projected;
  final bool showProjected;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      alignment: Alignment.topCenter,
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.radius20),
        border: Border.all(color: tokens.line),
        boxShadow: tokens.cardShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'STOCK PREVIEW',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w700,
              fontSize: 10,
              letterSpacing: 1.0,
              color: tokens.inkMuted,
            ),
          ),
          const SizedBox(height: 10),
          _StockLcd(caption: 'Available Stock', stock: available),
          const SizedBox(height: 12),
          _StockLcd(caption: 'New Stock (this purchase)', stock: incoming),
          if (showProjected)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _RollingLcdBlock(
                caption: 'New Available Stock Would be Like',
                stock: projected,
              ),
            ),
        ],
      ),
    );
  }
}

class _RollingLcdBlock extends StatefulWidget {
  const _RollingLcdBlock({required this.caption, required this.stock});

  final String caption;
  final _LcdStock stock;

  @override
  State<_RollingLcdBlock> createState() => _RollingLcdBlockState();
}

class _RollingLcdBlockState extends State<_RollingLcdBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _roll;
  _LcdStock _from = _LcdStock.empty;
  late _LcdStock _to;

  @override
  void initState() {
    super.initState();
    _to = widget.stock;
    _roll =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 900),
        )..addListener(() {
          setState(() {});
        });
    _roll.forward();
  }

  @override
  void didUpdateWidget(covariant _RollingLcdBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stock.sameAs(widget.stock)) {
      return;
    }
    _from = _displayed;
    _to = widget.stock;
    _roll.forward(from: 0);
  }

  @override
  void dispose() {
    _roll.dispose();
    super.dispose();
  }

  _LcdStock get _displayed {
    final double t = Curves.easeOutCubic.transform(_roll.value);
    return _from.lerpTo(_to, t);
  }

  @override
  Widget build(BuildContext context) {
    return _StockLcd(caption: widget.caption, stock: _displayed, hint: true);
  }
}

class _StockLcd extends StatelessWidget {
  const _StockLcd({
    required this.caption,
    required this.stock,
    this.hint = false,
  });

  final String caption;
  final _LcdStock stock;
  final bool hint;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          caption,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w600,
            fontSize: 12,
            color: hint ? tokens.coralPressed : tokens.ink,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 108,
          child: SegmentLcd.purchase(
            labelSize: 13,
            valueSize: 22,
            lines: <SegmentLcdLine>[
              SegmentLcdLine(
                label: 'AMOUNT',
                value: FuelFormatter.lcdAmount(stock.amountPkr),
              ),
              SegmentLcdLine(
                label: 'LITERS',
                value: FuelFormatter.lcdVolume(stock.volumeLiters),
              ),
              SegmentLcdLine(
                label: 'RATE',
                value: FuelFormatter.lcdRate(stock.rate),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LastPurchasesTable extends StatelessWidget {
  const _LastPurchasesTable({
    required this.rows,
    required this.totalCount,
    this.fillHeight = false,
  });

  final List<PurchaseRecord> rows;
  final int totalCount;
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final int shown = rows.length;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.radius20),
        border: Border.all(color: tokens.line),
        boxShadow: tokens.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Row(
              children: <Widget>[
                Text(
                  'Last 10 Purchases',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: tokens.ink,
                  ),
                ),
                const Spacer(),
                Text(
                  '$shown of ${totalCount < 10 ? 10 : totalCount}',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                    color: tokens.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          Divider(color: tokens.line, height: 1),
          if (fillHeight) Expanded(child: _body(tokens)) else _body(tokens),
        ],
      ),
    );
  }

  Widget _body(DispensrTokens tokens) {
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No purchases yet. Set Initial Dip or add a purchase.',
          style: TextStyle(fontFamily: 'Roboto', color: tokens.inkMuted),
        ),
      );
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              headingRowHeight: 32,
              dataRowMinHeight: 36,
              dataRowMaxHeight: 40,
              horizontalMargin: 16,
              columnSpacing: 20,
              headingTextStyle: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w700,
                fontSize: 10,
                letterSpacing: 0.9,
                color: tokens.inkMuted,
              ),
              dataTextStyle: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w500,
                fontSize: 12,
                color: tokens.ink,
              ),
              columns: const <DataColumn>[
                DataColumn(label: Text('INV-NO')),
                DataColumn(label: Text('DATE & TIME')),
                DataColumn(label: Text('TAFSEEL')),
                DataColumn(label: Text('QUANTITY'), numeric: true),
                DataColumn(label: Text('RATE'), numeric: true),
                DataColumn(label: Text('AMOUNT'), numeric: true),
              ],
              rows: <DataRow>[
                for (final PurchaseRecord row in rows)
                  DataRow(
                    color: row.isInitialDip
                        ? WidgetStatePropertyAll<Color>(
                            tokens.bad.withValues(alpha: 0.10),
                          )
                        : null,
                    cells: <DataCell>[
                      DataCell(
                        Text(
                          row.invNo,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: row.isInitialDip
                                ? tokens.bad
                                : tokens.coralPressed,
                          ),
                        ),
                      ),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              formatDateTime(row.dateTime),
                              style: TextStyle(
                                color: row.isInitialDip
                                    ? tokens.bad
                                    : tokens.inkMuted,
                              ),
                            ),
                            if (row.isInitialDip) ...<Widget>[
                              const SizedBox(width: 8),
                              _DipTag(color: tokens.bad),
                            ],
                          ],
                        ),
                      ),
                      DataCell(
                        Text(
                          row.tafseel.isEmpty ? '—' : row.tafseel,
                          style: row.isInitialDip
                              ? TextStyle(color: tokens.bad)
                              : null,
                        ),
                      ),
                      DataCell(
                        Text(
                          FuelFormatter.formatVolume(row.quantity),
                          style: row.isInitialDip
                              ? TextStyle(color: tokens.bad)
                              : null,
                        ),
                      ),
                      DataCell(
                        Text(
                          FuelFormatter.formatRate(row.rate),
                          style: row.isInitialDip
                              ? TextStyle(color: tokens.bad)
                              : null,
                        ),
                      ),
                      DataCell(
                        Text(
                          FuelFormatter.formatCurrency(row.amount),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: row.isInitialDip ? tokens.bad : tokens.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DipTag extends StatelessWidget {
  const _DipTag({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        'DIP',
        style: TextStyle(
          fontFamily: 'Roboto',
          fontWeight: FontWeight.w700,
          fontSize: 9,
          letterSpacing: 0.8,
          color: color,
        ),
      ),
    );
  }
}

class _PurchaseFooter extends StatelessWidget {
  const _PurchaseFooter({
    required this.canAdd,
    required this.draftSaved,
    required this.submitFocus,
    required this.onSaveDraft,
    required this.onAddStock,
  });

  final bool canAdd;
  final bool draftSaved;
  final FocusNode submitFocus;
  final VoidCallback onSaveDraft;
  final VoidCallback onAddStock;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final String status = !canAdd
        ? 'Enter quantity and rate to continue'
        : draftSaved
        ? 'Draft saved — ready to add this purchase to stock'
        : 'Ready to add this purchase to stock';
    final Color statusColor = canAdd ? tokens.good : tokens.inkMuted;

    return Material(
      color: tokens.card,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: tokens.card,
          border: Border(top: BorderSide(color: tokens.line)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x14211C1A),
              blurRadius: 16,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Widget statusLine = Row(
              children: <Widget>[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                      color: tokens.inkMuted,
                    ),
                  ),
                ),
              ],
            );
            final Widget actions = Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                DsPillButton(
                  label: 'Save as Draft',
                  variant: DsPillVariant.outline,
                  onPressed: onSaveDraft,
                ),
                const SizedBox(width: 8),
                Focus(
                  focusNode: submitFocus,
                  child: DsPillButton(
                    label: 'Add Stock',
                    icon: Icons.check,
                    onPressed: canAdd ? onAddStock : null,
                  ),
                ),
              ],
            );
            if (constraints.maxWidth < 640) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  statusLine,
                  const SizedBox(height: 10),
                  Align(alignment: Alignment.centerRight, child: actions),
                ],
              );
            }
            return Row(
              children: <Widget>[
                Expanded(child: statusLine),
                const SizedBox(width: 12),
                actions,
              ],
            );
          },
        ),
      ),
    );
  }
}
