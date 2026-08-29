import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/dispensr_theme.dart';
import '../../core/widgets/app_screen_header.dart';
import '../../core/widgets/segment_lcd.dart';
import '../../features/station/domain/dispenser_models.dart';
import '../../features/station/domain/money_format.dart';
import '../../features/station/presentation/station_providers.dart';

class _TankStock {
  const _TankStock({
    required this.amountPkr,
    required this.volumeLiters,
    required this.rate,
  });

  final double amountPkr;
  final double volumeLiters;
  final double rate;

  _TankStock merge(_TankStock incoming) {
    final double availableAmount = amountPkr;
    final double newAmount = incoming.amountPkr;
    final double availableQuantity = volumeLiters;
    final double newQuantity = incoming.volumeLiters;
    final double totalQuantity = availableQuantity + newQuantity;
    final double nextRate = totalQuantity <= 0
        ? 0
        : (availableAmount + newAmount) / totalQuantity;
    final double nextQuantity = availableQuantity + newQuantity;
    final double nextAmount = nextRate * nextQuantity;
    return _TankStock(
      amountPkr: nextAmount,
      volumeLiters: nextQuantity,
      rate: nextRate,
    );
  }

  static const _TankStock empty = _TankStock(
    amountPkr: 0,
    volumeLiters: 0,
    rate: 0,
  );

  bool sameAs(_TankStock other) {
    return amountPkr == other.amountPkr &&
        volumeLiters == other.volumeLiters &&
        rate == other.rate;
  }

  _TankStock lerpTo(_TankStock other, double t) {
    return _TankStock(
      amountPkr: amountPkr + (other.amountPkr - amountPkr) * t,
      volumeLiters: volumeLiters + (other.volumeLiters - volumeLiters) * t,
      rate: rate + (other.rate - rate) * t,
    );
  }
}

class _PurchaseRecord {
  const _PurchaseRecord({
    required this.invoiceNo,
    required this.at,
    required this.quantity,
    required this.rate,
    required this.amount,
    required this.totalQuantity,
    required this.tafseel,
    required this.user,
  });

  final int invoiceNo;
  final DateTime at;
  final double quantity;
  final double rate;
  final double amount;
  final double totalQuantity;
  final String tafseel;
  final String user;

  static const String operatorName = 'Ali';

  static List<_PurchaseRecord> lastTen() {
    return <_PurchaseRecord>[
      _PurchaseRecord(
        invoiceNo: 999,
        at: DateTime(2026, 8, 29, 11, 42),
        quantity: 580.50,
        rate: 151.20,
        amount: 87771.60,
        totalQuantity: 3890.20,
        tafseel: 'PSO tanker — morning drop',
        user: 'Ali',
      ),
      _PurchaseRecord(
        invoiceNo: 998,
        at: DateTime(2026, 8, 29, 8, 15),
        quantity: 533.26,
        rate: 151.20,
        amount: 80628.40,
        totalQuantity: 3309.70,
        tafseel: 'Attock bowser',
        user: 'Amir R.',
      ),
      _PurchaseRecord(
        invoiceNo: 997,
        at: DateTime(2026, 8, 26, 16, 30),
        quantity: 3200.00,
        rate: 149.80,
        amount: 479360.00,
        totalQuantity: 4120.00,
        tafseel: 'Hascol refill — depot',
        user: 'Ali',
      ),
      _PurchaseRecord(
        invoiceNo: 996,
        at: DateTime(2026, 8, 24, 10, 5),
        quantity: 2100.00,
        rate: 149.50,
        amount: 313950.00,
        totalQuantity: 2450.00,
        tafseel: 'Shell tanker 12',
        user: 'Usman',
      ),
      _PurchaseRecord(
        invoiceNo: 995,
        at: DateTime(2026, 8, 21, 14, 48),
        quantity: 1750.00,
        rate: 148.90,
        amount: 260575.00,
        totalQuantity: 2680.00,
        tafseel: 'PSO evening load',
        user: 'Ali',
      ),
      _PurchaseRecord(
        invoiceNo: 994,
        at: DateTime(2026, 8, 18, 9, 20),
        quantity: 980.00,
        rate: 148.90,
        amount: 145922.00,
        totalQuantity: 1980.00,
        tafseel: 'Local tanker',
        user: 'Cashier',
      ),
      _PurchaseRecord(
        invoiceNo: 993,
        at: DateTime(2026, 8, 15, 13, 10),
        quantity: 2400.00,
        rate: 147.60,
        amount: 354240.00,
        totalQuantity: 3210.00,
        tafseel: 'Attock — full compartment',
        user: 'Amir R.',
      ),
      _PurchaseRecord(
        invoiceNo: 992,
        at: DateTime(2026, 8, 12, 17, 55),
        quantity: 640.00,
        rate: 147.60,
        amount: 94464.00,
        totalQuantity: 1420.00,
        tafseel: 'Top-up after drip',
        user: 'Usman',
      ),
      _PurchaseRecord(
        invoiceNo: 991,
        at: DateTime(2026, 8, 9, 11, 2),
        quantity: 1500.00,
        rate: 146.40,
        amount: 219600.00,
        totalQuantity: 2890.00,
        tafseel: 'Hascol morning',
        user: 'Ali',
      ),
      _PurchaseRecord(
        invoiceNo: 990,
        at: DateTime(2026, 8, 6, 15, 40),
        quantity: 1880.00,
        rate: 146.40,
        amount: 275232.00,
        totalQuantity: 2110.00,
        tafseel: 'PSO tanker 7',
        user: 'Amir R.',
      ),
    ];
  }
}

class PurchaseScreen extends ConsumerStatefulWidget {
  const PurchaseScreen({super.key});

  @override
  ConsumerState<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends ConsumerState<PurchaseScreen> {
  static final FilteringTextInputFormatter _decimalFormatter =
      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'));

  final ScrollController _pageScroll = ScrollController();
  final TextEditingController _tafseelController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _rateController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  int _todayCount = 2;
  int _invoiceNo = 1000;
  double _todayAmount = 168400;
  double _todayLiters = 1113.76;
  DateTime _lastRestockAt = DateTime(2026, 8, 26);
  double _lastRestockLiters = 3200;
  bool _draftSaved = false;
  bool _syncing = false;
  final List<_PurchaseRecord> _purchases = _PurchaseRecord.lastTen();

  _TankStock _available = const _TankStock(
    amountPkr: 512400,
    volumeLiters: 3890.20,
    rate: 131.72,
  );

  @override
  void initState() {
    super.initState();
    _quantityController.addListener(_onQuantityOrRateChanged);
    _rateController.addListener(_onQuantityOrRateChanged);
    _amountController.addListener(_onAmountChanged);
    _tafseelController.addListener(_onFormChanged);
  }

  @override
  void dispose() {
    _pageScroll.dispose();
    _quantityController.removeListener(_onQuantityOrRateChanged);
    _rateController.removeListener(_onQuantityOrRateChanged);
    _amountController.removeListener(_onAmountChanged);
    _tafseelController.removeListener(_onFormChanged);
    _quantityController.dispose();
    _rateController.dispose();
    _amountController.dispose();
    _tafseelController.dispose();
    super.dispose();
  }

  void _onFormChanged() {
    if (!mounted || _syncing) {
      return;
    }
    setState(() {
      _draftSaved = false;
    });
  }

  void _onQuantityOrRateChanged() {
    if (_syncing) {
      return;
    }
    final double qty = _quantity;
    final double rate = _rate;
    _syncing = true;
    _amountController.text = (qty * rate).toStringAsFixed(2);
    _syncing = false;
    _onFormChanged();
  }

  void _onAmountChanged() {
    if (_syncing) {
      return;
    }
    final double qty = _quantity;
    if (qty > 0) {
      _syncing = true;
      _rateController.text = (_amount / qty).toStringAsFixed(2);
      _syncing = false;
    }
    _onFormChanged();
  }

  double _parse(TextEditingController controller) {
    return double.tryParse(controller.text.trim()) ?? 0;
  }

  double get _quantity => _parse(_quantityController);
  double get _rate => _parse(_rateController);
  double get _amount => _parse(_amountController);

  _TankStock get _newStock =>
      _TankStock(amountPkr: _amount, volumeLiters: _quantity, rate: _rate);

  bool get _canAddStock => _quantity > 0 && _amount > 0;

  double get _avgRate {
    if (_todayLiters <= 0) {
      return _available.rate;
    }
    return _todayAmount / _todayLiters;
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

  Future<void> _addStock() async {
    if (!_canAddStock) {
      _snack('Enter diesel quantity and amount before adding stock.');
      return;
    }
    final _TankStock incoming = _newStock;
    final String tafseel = _tafseelController.text.trim();
    final int invoiceNo = _invoiceNo;
    setState(() {
      _purchases.insert(
        0,
        _PurchaseRecord(
          invoiceNo: invoiceNo,
          at: DateTime.now(),
          quantity: incoming.volumeLiters,
          rate: incoming.rate,
          amount: incoming.amountPkr,
          totalQuantity: _available.volumeLiters + incoming.volumeLiters,
          tafseel: tafseel.isEmpty ? '—' : tafseel,
          user: _PurchaseRecord.operatorName,
        ),
      );
      if (_purchases.length > 10) {
        _purchases.removeRange(10, _purchases.length);
      }
      _available = _available.merge(incoming);
      _todayAmount += incoming.amountPkr;
      _todayLiters += incoming.volumeLiters;
      _todayCount += 1;
      _invoiceNo += 1;
      _lastRestockAt = DateTime.now();
      _lastRestockLiters = incoming.volumeLiters;
      _draftSaved = false;
      _syncing = true;
      _quantityController.clear();
      _amountController.clear();
      _tafseelController.clear();
      _syncing = false;
    });
    const double sharah = 0.840;
    try {
      await ref
          .read(transactionStoreProvider)
          .insertPurchaseHistory(
            PurchaseTransaction(
              refNo: invoiceNo,
              timestamp: DateTime.now(),
              supplierName: tafseel.isEmpty ? 'Owner' : tafseel,
              fuelType: 'Diesel',
              weightKg: incoming.volumeLiters * sharah,
              sharahRatio: sharah,
              netLiters: incoming.volumeLiters,
              ratePerLiter: incoming.rate,
              totalAmount: incoming.amountPkr,
              paidAmount: incoming.amountPkr,
            ),
          );
      bumpHistoryRevision(ref.read(historyRevisionProvider.notifier));
    } catch (error, stack) {
      debugPrint('purchase_history insert failed: $error\n$stack');
    }
    _snack('Diesel stock updated.');
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter, control: true):
            _addStock,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true):
            _saveDraft,
      },
      child: Focus(
        autofocus: true,
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
                  invoiceLabel: formatInvoiceNo(_invoiceNo),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: LayoutBuilder(
                    builder:
                        (BuildContext context, BoxConstraints constraints) {
                          final bool wide = constraints.maxWidth >= 980;
                          final Widget kpis = _KpiBar(
                            todayAmount: formatPkr(_todayAmount),
                            todayCount: '$_todayCount entries',
                            avgRate: formatPkr(_avgRate),
                            lastRestockDate: _formatRestockDate(_lastRestockAt),
                            lastRestockLiters: formatLiters(_lastRestockLiters),
                          );
                          final Widget purchase = _EntryCard(
                            tafseelController: _tafseelController,
                            quantityController: _quantityController,
                            rateController: _rateController,
                            amountController: _amountController,
                            decimalFormatter: _decimalFormatter,
                          );
                          final Widget preview = _StockPreviewPanel(
                            available: _available,
                            incoming: _newStock,
                            projected: _available.merge(_newStock),
                            showProjected: _canAddStock,
                          );
                          final Widget history = _LastPurchasesTable(
                            rows: _purchases,
                          );
                          final Widget cards = wide
                              ? IntrinsicHeight(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: <Widget>[
                                      Expanded(child: purchase),
                                      const SizedBox(width: 10),
                                      SizedBox(width: 328, child: preview),
                                    ],
                                  ),
                                )
                              : Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: <Widget>[
                                    purchase,
                                    const SizedBox(height: 10),
                                    preview,
                                  ],
                                );
                          return Scrollbar(
                            controller: _pageScroll,
                            child: SingleChildScrollView(
                              controller: _pageScroll,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  kpis,
                                  const SizedBox(height: 10),
                                  cards,
                                  const SizedBox(height: 10),
                                  history,
                                ],
                              ),
                            ),
                          );
                        },
                  ),
                ),
              ),
              _PurchaseFooter(
                canAdd: _canAddStock,
                draftSaved: _draftSaved,
                onSaveDraft: _saveDraft,
                onAddStock: _addStock,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatRestockDate(DateTime time) {
    const List<String> months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[time.month - 1]} ${time.day}';
  }
}

class _KpiBar extends StatelessWidget {
  const _KpiBar({
    required this.todayAmount,
    required this.todayCount,
    required this.avgRate,
    required this.lastRestockDate,
    required this.lastRestockLiters,
  });

  final String todayAmount;
  final String todayCount;
  final String avgRate;
  final String lastRestockDate;
  final String lastRestockLiters;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final List<_KpiSpec> stats = <_KpiSpec>[
      _KpiSpec(
        label: "Today's Purchases",
        value: todayAmount,
        hint: todayCount,
        icon: Icons.trending_up,
        tint: tokens.good,
      ),
      _KpiSpec(
        label: 'Avg Rate',
        value: avgRate,
        hint: '/ Ltr',
        icon: Icons.water_drop_outlined,
        tint: tokens.coral,
      ),
      _KpiSpec(
        label: 'Last Restock',
        value: lastRestockDate,
        hint: lastRestockLiters,
        icon: Icons.inventory_2_outlined,
        tint: tokens.warn,
      ),
    ];

    return Row(
      children: <Widget>[
        for (int i = 0; i < stats.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _KpiCard(spec: stats[i])),
        ],
      ],
    );
  }
}

class _KpiSpec {
  const _KpiSpec({
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
    required this.tint,
  });

  final String label;
  final String value;
  final String hint;
  final IconData icon;
  final Color tint;
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.spec});

  final _KpiSpec spec;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.radius20),
        border: Border.all(color: tokens.line),
        boxShadow: tokens.cardShadow,
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: spec.tint.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(spec.icon, color: spec.tint, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  spec.label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 9,
                    letterSpacing: 0.8,
                    color: tokens.inkMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: spec.value,
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: tokens.ink,
                        ),
                      ),
                      TextSpan(
                        text: '  ${spec.hint}',
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontWeight: FontWeight.w500,
                          fontSize: 11,
                          color: tokens.inkMuted,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.tafseelController,
    required this.quantityController,
    required this.rateController,
    required this.amountController,
    required this.decimalFormatter,
  });

  final TextEditingController tafseelController;
  final TextEditingController quantityController;
  final TextEditingController rateController;
  final TextEditingController amountController;
  final TextInputFormatter decimalFormatter;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      alignment: Alignment.topCenter,
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.radius20),
        border: Border.all(color: tokens.line),
        boxShadow: tokens.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SectionTitle(title: 'Diesel Purchase', urdu: 'ڈیزل خریداری'),
          const SizedBox(height: 14),
          _FieldRow(
            left: _LabeledField(
              label: 'Tafseel',
              urdu: 'تفصیل',
              controller: tafseelController,
              hint: 'Tanker / invoice note',
            ),
            right: _LabeledField(
              label: 'Diesel Quantity',
              urdu: 'مقدار',
              controller: quantityController,
              hint: '0',
              suffix: 'Ltr',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: <TextInputFormatter>[decimalFormatter],
            ),
          ),
          const SizedBox(height: 12),
          _FieldRow(
            left: _LabeledField(
              label: 'Rate',
              urdu: 'ریٹ',
              controller: rateController,
              hint: '0.00',
              suffix: 'Rs / Ltr',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: <TextInputFormatter>[decimalFormatter],
            ),
            right: _LabeledField(
              label: 'Amount',
              urdu: 'رقم',
              controller: amountController,
              hint: '0.00',
              suffix: 'Rs',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: <TextInputFormatter>[decimalFormatter],
            ),
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
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: tokens.ink,
          ),
        ),
        const Spacer(),
        Directionality(
          textDirection: TextDirection.rtl,
          child: Text(
            urdu,
            style: TextStyle(
              fontFamily: 'NotoNastaliqUrdu',
              fontSize: 13,
              height: 1.6,
              color: tokens.inkMuted,
            ),
          ),
        ),
      ],
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ],
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.urdu,
    required this.controller,
    required this.hint,
    this.suffix,
    this.keyboardType,
    this.inputFormatters,
  });

  final String label;
  final String urdu;
  final TextEditingController controller;
  final String hint;
  final String? suffix;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: tokens.inkMuted,
              ),
            ),
            const Spacer(),
            Directionality(
              textDirection: TextDirection.rtl,
              child: Text(
                urdu,
                style: TextStyle(
                  fontFamily: 'NotoNastaliqUrdu',
                  fontSize: 12,
                  height: 1.6,
                  color: tokens.inkMuted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: tokens.ink,
          ),
          decoration: InputDecoration(
            hintText: hint,
            suffixText: suffix,
            suffixStyle: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w500,
              fontSize: 12,
              color: tokens.inkMuted,
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

  final _TankStock available;
  final _TankStock incoming;
  final _TankStock projected;
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
          _LcdBlock(caption: 'Available Stock', stock: available),
          const SizedBox(height: 12),
          _LcdBlock(caption: 'New Stock (this purchase)', stock: incoming),
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: showProjected
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _RollingLcdBlock(
                      caption: 'New Available Stock would be Like',
                      stock: projected,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _LcdBlock extends StatelessWidget {
  const _LcdBlock({required this.caption, required this.stock});

  final String caption;
  final _TankStock stock;

  @override
  Widget build(BuildContext context) {
    return _StockLcd(caption: caption, stock: stock);
  }
}

class _RollingLcdBlock extends StatefulWidget {
  const _RollingLcdBlock({required this.caption, required this.stock});

  final String caption;
  final _TankStock stock;

  @override
  State<_RollingLcdBlock> createState() => _RollingLcdBlockState();
}

class _RollingLcdBlockState extends State<_RollingLcdBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _roll;
  _TankStock _from = _TankStock.empty;
  late _TankStock _to;

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

  _TankStock get _displayed {
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
  final _TankStock stock;
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
                value: stock.amountPkr.toStringAsFixed(2),
              ),
              SegmentLcdLine(
                label: 'LITERS',
                value: stock.volumeLiters.toStringAsFixed(2),
              ),
              SegmentLcdLine(
                label: 'RATE',
                value: stock.rate.toStringAsFixed(2),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LastPurchasesTable extends StatelessWidget {
  const _LastPurchasesTable({required this.rows});

  final List<_PurchaseRecord> rows;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);

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
                  'Last Purchases',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: tokens.ink,
                  ),
                ),
                const Spacer(),
                Text(
                  '${rows.length} of 10',
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
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No purchases yet.',
                style: TextStyle(fontFamily: 'Roboto', color: tokens.inkMuted),
              ),
            )
          else
            LayoutBuilder(
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
                        DataColumn(label: Text('DATETIME')),
                        DataColumn(label: Text('QUANTITY'), numeric: true),
                        DataColumn(label: Text('RATE'), numeric: true),
                        DataColumn(label: Text('AMOUNT'), numeric: true),
                        DataColumn(
                          label: Text('TOTAL QUANTITY'),
                          numeric: true,
                        ),
                        DataColumn(label: Text('TAFSEEL')),
                        DataColumn(label: Text('USER')),
                      ],
                      rows: <DataRow>[
                        for (final _PurchaseRecord row in rows)
                          DataRow(
                            cells: <DataCell>[
                              DataCell(
                                Text(
                                  formatInvoiceNo(row.invoiceNo),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  formatDateTime(row.at),
                                  style: TextStyle(color: tokens.inkMuted),
                                ),
                              ),
                              DataCell(Text(formatLiters(row.quantity))),
                              DataCell(Text(row.rate.toStringAsFixed(2))),
                              DataCell(
                                Text(
                                  formatPkr(row.amount),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              DataCell(Text(formatLiters(row.totalQuantity))),
                              DataCell(
                                SizedBox(
                                  width: 180,
                                  child: Text(
                                    row.tafseel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  row.user,
                                  style: TextStyle(color: tokens.inkMuted),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _PurchaseFooter extends StatelessWidget {
  const _PurchaseFooter({
    required this.canAdd,
    required this.draftSaved,
    required this.onSaveDraft,
    required this.onAddStock,
  });

  final bool canAdd;
  final bool draftSaved;
  final VoidCallback onSaveDraft;
  final VoidCallback onAddStock;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final String status = !canAdd
        ? 'Enter diesel quantity and amount to continue'
        : draftSaved
        ? 'Draft saved — ready to add this purchase to stock'
        : 'Ready to add this purchase to stock';
    final Color statusColor = canAdd ? tokens.good : tokens.inkMuted;

    return Material(
      color: tokens.card,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
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
        child: Row(
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
            DsPillButton(
              label: 'Save as Draft',
              variant: DsPillVariant.outline,
              onPressed: onSaveDraft,
            ),
            const SizedBox(width: 8),
            DsPillButton(
              label: 'Add Stock',
              icon: Icons.check,
              onPressed: canAdd ? onAddStock : null,
            ),
          ],
        ),
      ),
    );
  }
}
