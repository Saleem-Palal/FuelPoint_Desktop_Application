import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../Shell/shell_navigation.dart';
import '../../core/theme/dispensr_theme.dart';
import '../../core/widgets/app_screen_header.dart';
import '../../core/widgets/responsive_layout.dart';
import '../../features/station/domain/dispenser_models.dart';
import '../../features/station/domain/money_format.dart';
import '../../features/station/presentation/station_providers.dart';
import '../../features/station/presentation/workspace_refresh.dart';
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(refreshSalesFromDatabase(ref));
      }
    });
  }

  @override
  void dispose() {
    _pageScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final StationState station = ref.watch(stationControllerProvider);
    final int selected = ref.watch(selectedDispenserIndexProvider);

    return ColoredBox(
      color: tokens.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: AppScreenHeader(
              title: 'Sale Screen',
              icon: Icons.local_gas_station_outlined,
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints viewport) {
                return Scrollbar(
                  controller: _pageScroll,
                  child: SingleChildScrollView(
                    controller: _pageScroll,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: viewport.maxWidth),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            if (DemoControlsBar.visible) ...<Widget>[
                              const DemoControlsBar(),
                              const SizedBox(height: 10),
                            ],
                            _UnitsRow(
                              bays: <DispenserBay>[
                                for (final int unitId in dispenserUnitIds)
                                  station.bay(unitId),
                              ],
                              selectedUnitId: selected,
                              onSelect: (int unitId) {
                                ref
                                        .read(
                                          selectedDispenserIndexProvider
                                              .notifier,
                                        )
                                        .state =
                                    unitId;
                              },
                              abortNoticeFor: station.abortNoticeFor,
                              receiptOverlays: ref.watch(
                                receiptOverlayTxnsProvider,
                              ),
                              onDismissReceipt: (int unitId) {
                                dismissUnitReceiptOverlay(ref, unitId);
                              },
                            ),
                            const SizedBox(height: 10),
                            _TransactionsCard(
                              rows: station.recentTransactions
                                  .take(10)
                                  .toList(),
                              onViewAll: () {
                                unawaited(openLedgerSales(context, ref));
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
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
    return ExtentWrap(
      maxCrossAxisExtent: 320,
      children: <Widget>[
        for (final DispenserBay bay in bays) _unitCell(tokens, bay),
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
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'No committed sales yet.',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    color: tokens.inkMuted,
                  ),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double tableWidth = constraints.maxWidth < 1480
                    ? 1480
                    : constraints.maxWidth;
                final double gutter = tableWidth >= 1400 ? 24 : 16;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: tableWidth),
                    child: DataTable(
                      headingRowHeight: 32,
                      dataRowMinHeight: 36,
                      dataRowMaxHeight: 40,
                      horizontalMargin: tableWidth >= 1400 ? 20 : 12,
                      columnSpacing: gutter,
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
                        DataColumn(label: Text('LITERS')),
                        DataColumn(label: Text('RATE')),
                        DataColumn(label: Text('OPENING READING')),
                        DataColumn(label: Text('CLOSING READING')),
                        DataColumn(label: Text('PAYMENT METHOD')),
                        DataColumn(label: Text('CUSTOMER NAME')),
                        DataColumn(label: Text('VEHICLE NO')),
                        DataColumn(label: Text('HELPER')),
                        DataColumn(label: Text('CASHIER')),
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
                              DataCell(
                                Text(row.unitId.toString().padLeft(2, '0')),
                              ),
                              DataCell(
                                Text(
                                  formatPkr(row.amountPkr),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(row.volumeLiters.toStringAsFixed(2)),
                              ),
                              DataCell(Text(row.rate.toStringAsFixed(2))),
                              DataCell(
                                Text(formatMeterReading(row.openingMeter)),
                              ),
                              DataCell(
                                Text(formatMeterReading(row.closingMeter)),
                              ),
                              DataCell(Text(row.payment.label)),
                              DataCell(
                                Text(
                                  displayCustomerName(row.customerName),
                                  style: TextStyle(color: tokens.inkMuted),
                                ),
                              ),
                              DataCell(
                                Text(
                                  displayVehicleNo(row.vehicleNo),
                                  style: TextStyle(color: tokens.inkMuted),
                                ),
                              ),
                              DataCell(
                                Text(
                                  row.helperName.trim().isEmpty
                                      ? '—'
                                      : row.helperName,
                                  style: TextStyle(color: tokens.inkMuted),
                                ),
                              ),
                              DataCell(
                                Text(
                                  row.cashierName,
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
