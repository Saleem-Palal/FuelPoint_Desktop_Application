import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/dispensr_theme.dart';
import '../../core/widgets/app_screen_header.dart';
import '../../features/station/domain/dispenser_models.dart';
import '../../features/station/domain/money_format.dart';
import '../../features/station/presentation/station_providers.dart';
import 'Widgets/Services/demo_controls_bar.dart';
import 'Widgets/Services/dispenser_units_widget.dart';
import 'Widgets/Services/receipt_preview_widget.dart';

class SaleScreen extends ConsumerStatefulWidget {
  const SaleScreen({super.key});

  @override
  ConsumerState<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends ConsumerState<SaleScreen> {
  final ScrollController _pageScroll = ScrollController();

  @override
  void dispose() {
    _pageScroll.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final StationState station = ref.watch(stationControllerProvider);
    final int selected = ref.watch(selectedDispenserIndexProvider);
    final DateTime now = DateTime.now();
    final List<SaleTransaction> rows = station.recentTransactions;
    DateTime saleDay = now;
    if (rows.isNotEmpty) {
      final bool hasToday = rows.any(
        (SaleTransaction row) => _isSameDay(row.timestamp, now),
      );
      if (!hasToday) {
        saleDay = rows.first.timestamp;
      }
    }
    final double committedSale = rows
        .where((SaleTransaction row) => _isSameDay(row.timestamp, saleDay))
        .fold<double>(
          0,
          (double sum, SaleTransaction row) => sum + row.amountPkr,
        );
    final double committedLiters = rows
        .where((SaleTransaction row) => _isSameDay(row.timestamp, saleDay))
        .fold<double>(
          0,
          (double sum, SaleTransaction row) => sum + row.volumeLiters,
        );
    final double liveSale = station.bays.values.fold<double>(
      0,
      (double sum, DispenserBay bay) => sum + bay.amountPkr,
    );
    final double liveLiters = station.bays.values.fold<double>(
      0,
      (double sum, DispenserBay bay) => sum + bay.volumeLiters,
    );
    final double monthLiters = rows
        .where(
          (SaleTransaction row) =>
              row.timestamp.year == saleDay.year &&
              row.timestamp.month == saleDay.month,
        )
        .fold<double>(
          0,
          (double sum, SaleTransaction row) => sum + row.volumeLiters,
        );
    const double remainingStockLiters = 3890.20;
    final double completeStockLiters = remainingStockLiters + monthLiters;

    return ColoredBox(
      color: tokens.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: AppScreenHeader(
              title: 'Sale Screen',
              icon: Icons.local_gas_station_outlined,
            ),
          ),
          Expanded(
            child: Scrollbar(
              controller: _pageScroll,
              child: SingleChildScrollView(
                controller: _pageScroll,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (DemoControlsBar.visible) ...<Widget>[
                      const DemoControlsBar(),
                      const SizedBox(height: 10),
                    ],
                    _KpiBar(
                      totalSale: formatPkr(committedSale + liveSale),
                      totalLiters: formatLiters(committedLiters + liveLiters),
                      completeStock: formatLiters(completeStockLiters),
                      remainingStock: formatLiters(remainingStockLiters),
                    ),
                    const SizedBox(height: 10),
                    _UnitsRow(
                      bays: <DispenserBay>[
                        for (final int unitId in dispenserUnitIds)
                          station.bay(unitId),
                      ],
                      selectedUnitId: selected,
                      onSelect: (int unitId) {
                        ref
                                .read(selectedDispenserIndexProvider.notifier)
                                .state =
                            unitId;
                      },
                      abortNoticeFor: station.abortNoticeFor,
                      receiptOverlays: ref.watch(receiptOverlayTxnsProvider),
                      onDismissReceipt: (int unitId) {
                        dismissUnitReceiptOverlay(ref, unitId);
                      },
                    ),
                    const SizedBox(height: 10),
                    _TransactionsCard(
                      rows: station.recentTransactions,
                      onViewAll: () => _snack('View all transactions'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

class _KpiBar extends StatelessWidget {
  const _KpiBar({
    required this.totalSale,
    required this.totalLiters,
    required this.completeStock,
    required this.remainingStock,
  });

  final String totalSale;
  final String totalLiters;
  final String completeStock;
  final String remainingStock;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final List<_StatSpec> stats = <_StatSpec>[
      _StatSpec(
        label: 'Total Sale Today',
        value: totalSale,
        icon: Icons.trending_up,
        tint: tokens.good,
      ),
      _StatSpec(
        label: 'Total Liters Today',
        value: totalLiters,
        icon: Icons.water_drop_outlined,
        tint: tokens.coral,
      ),
      _StatSpec(
        label: 'Complete Stock Quantity (This Month)',
        value: completeStock,
        icon: Icons.inventory_2_outlined,
        tint: tokens.warn,
      ),
      _StatSpec(
        label: 'Remaining Stock Quantity',
        value: remainingStock,
        icon: Icons.local_gas_station_outlined,
        tint: tokens.inkMuted,
      ),
    ];

    return Row(
      children: <Widget>[
        for (int i = 0; i < stats.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 6),
          Expanded(child: _StatCard(spec: stats[i])),
        ],
      ],
    );
  }
}

class _StatSpec {
  const _StatSpec({
    required this.label,
    required this.value,
    required this.icon,
    required this.tint,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color tint;
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.spec});

  final _StatSpec spec;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.radius20),
        border: Border.all(color: tokens.line),
        boxShadow: tokens.cardShadow,
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: spec.tint.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(spec.icon, color: spec.tint, size: 14),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  spec.label.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 8,
                    height: 1.2,
                    letterSpacing: 0.4,
                    color: tokens.inkMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  spec.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: tokens.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UnitsRow extends StatelessWidget {
  const _UnitsRow({
    required this.bays,
    required this.selectedUnitId,
    required this.onSelect,
    required this.abortNoticeFor,
    required this.receiptOverlays,
    required this.onDismissReceipt,
  });

  final List<DispenserBay> bays;
  final int selectedUnitId;
  final ValueChanged<int> onSelect;
  final String? Function(int unitId) abortNoticeFor;
  final Map<int, SaleTransaction> receiptOverlays;
  final ValueChanged<int> onDismissReceipt;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < bays.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _unitCell(tokens, bays[i])),
        ],
      ],
    );
  }

  Widget _unitCell(DispensrTokens tokens, DispenserBay bay) {
    final DispenserUnitsWidget card = DispenserUnitsWidget(
      data: DispenserUnitData.fromBay(bay),
      isSelected: selectedUnitId == bay.unitId,
      abortNotice: abortNoticeFor(bay.unitId),
      onSelect: () => onSelect(bay.unitId),
    );
    final SaleTransaction? receiptTxn = receiptOverlays[bay.unitId];
    if (receiptTxn == null) {
      return card;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(tokens.radius20),
      child: Stack(
        children: <Widget>[
          card,
          Positioned.fill(
            child: UnitReceiptOverlay(
              txn: receiptTxn,
              onDismiss: () => onDismissReceipt(bay.unitId),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionsCard extends StatelessWidget {
  const _TransactionsCard({required this.rows, required this.onViewAll});

  final List<SaleTransaction> rows;
  final VoidCallback onViewAll;

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
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
            child: Row(
              children: <Widget>[
                Text(
                  'Recent Transactions',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: tokens.ink,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: onViewAll,
                  child: Text(
                    'View all',
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: tokens.coralPressed,
                    ),
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
                'No committed sales yet.',
                style: TextStyle(fontFamily: 'Roboto', color: tokens.inkMuted),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 1180),
                child: DataTable(
                  headingRowHeight: 32,
                  dataRowMinHeight: 36,
                  dataRowMaxHeight: 40,
                  horizontalMargin: 12,
                  columnSpacing: 16,
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
                    DataColumn(label: Text('TOKEN #')),
                    DataColumn(label: Text('DATETIME')),
                    DataColumn(label: Text('UNIT NO.')),
                    DataColumn(label: Text('AMOUNT')),
                    DataColumn(label: Text('LITER')),
                    DataColumn(label: Text('RATE')),
                    DataColumn(label: Text('OPENING READING')),
                    DataColumn(label: Text('CLOSING READING')),
                    DataColumn(label: Text('PAYMENT')),
                    DataColumn(label: Text('CASHIER')),
                    DataColumn(label: Text('SHIFT')),
                  ],
                  rows: <DataRow>[
                    for (final SaleTransaction row in rows)
                      DataRow(
                        cells: <DataCell>[
                          DataCell(
                            Text(
                              formatTokenNo(row.tokenNo),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              formatDateTime(row.timestamp),
                              style: TextStyle(color: tokens.inkMuted),
                            ),
                          ),
                          DataCell(Text(row.unitId.toString().padLeft(2, '0'))),
                          DataCell(
                            Text(
                              formatPkr(row.amountPkr),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          DataCell(Text(row.volumeLiters.toStringAsFixed(2))),
                          DataCell(Text(row.rate.toStringAsFixed(2))),
                          DataCell(Text(formatMeterReading(row.openingMeter))),
                          DataCell(Text(formatMeterReading(row.closingMeter))),
                          DataCell(Text(row.payment.label)),
                          DataCell(
                            Text(
                              row.cashierName,
                              style: TextStyle(color: tokens.inkMuted),
                            ),
                          ),
                          DataCell(
                            Text(
                              row.shiftName,
                              style: TextStyle(color: tokens.inkMuted),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
