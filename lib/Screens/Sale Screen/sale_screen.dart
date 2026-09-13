import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../Shell/shell_navigation.dart';
import '../../core/theme/dispensr_theme.dart';
import '../../core/widgets/app_screen_header.dart';
import '../../features/access/domain/access_policy.dart';
import '../../features/shift/presentation/shift_providers.dart';
import '../../features/station/domain/dispenser_models.dart';
import '../../features/station/domain/money_format.dart';
import '../../features/station/presentation/station_providers.dart';
import '../../features/station/presentation/workspace_refresh.dart';
import '../../providers/settings_provider.dart';
import '../../utils/fuel_formatter.dart';
import 'Widgets/Services/dispenser_units_widget.dart';
import 'Widgets/Services/receipt_preview_widget.dart';

class SaleScreen extends ConsumerStatefulWidget {
  const SaleScreen({super.key});

  @override
  ConsumerState<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends ConsumerState<SaleScreen> {
  final ScrollController _pageScroll = ScrollController();
  bool _recoveryDialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(refreshSalesFromDatabase(ref));
        _maybePromptRecovery(ref.read(pendingEspSalesProvider));
      }
    });
  }

  @override
  void dispose() {
    _pageScroll.dispose();
    super.dispose();
  }

  void _maybePromptRecovery(List<PendingEspSale> pending) {
    if (_recoveryDialogOpen || pending.isEmpty || !mounted) {
      return;
    }
    final PendingEspSale sale = pending.first;
    _recoveryDialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _recoveryDialogOpen = false;
        return;
      }
      final bool? save = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Incomplete transaction'),
            content: Text(
              'This transaction was left incomplete due to connection loss. '
              'Would you like to save this transaction to the database?\n\n'
              'Unit ${sale.unitId}  ·  '
              '${FuelFormatter.lcdVolume(sale.volumeLiters)} L  ·  '
              'Rs. ${FuelFormatter.lcdDispenserAmount(sale.amountPkr)}'
              '${sale.isIncomplete ? '\n(Power loss / Incomplete)' : ''}',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Dismiss'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
      if (!mounted) {
        _recoveryDialogOpen = false;
        return;
      }
      final StationController ctl = ref.read(stationControllerProvider.notifier);
      if (save == true) {
        await ctl.savePendingEspSale(sale);
      } else {
        ctl.dismissPendingEspSale(sale);
      }
      _recoveryDialogOpen = false;
      _maybePromptRecovery(ref.read(pendingEspSalesProvider));
    });
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final StationState station = ref.watch(stationControllerProvider);
    final int selected = ref.watch(selectedDispenserIndexProvider);
    final List<int> unitIds = visibleDispenserUnitIds(
      showUnit5: ref.watch(settingsProvider).showUnit5,
    );
    final bool liveShift =
        ref.watch(shiftWorkspaceProvider).activeShift?.isOpen == true;
    final bool hardwareOffline = ref.watch(hardwareOfflineProvider);
    ref.listen<List<PendingEspSale>>(pendingEspSalesProvider, (
      List<PendingEspSale>? previous,
      List<PendingEspSale> next,
    ) {
      _maybePromptRecovery(next);
    });

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
                            if (shouldEnforceStationGuards &&
                                !liveShift) ...<Widget>[
                              _SaleLockBanner(
                                color: tokens.warn,
                                icon: Icons.lock_clock,
                                message:
                                    'No LIVE shift — start a manager shift to enable keypads and sales.',
                              ),
                              const SizedBox(height: 10),
                            ],
                            if (hardwareOffline) ...<Widget>[
                              _SaleLockBanner(
                                color: tokens.bad,
                                icon: Icons.wifi_off,
                                message:
                                    'HARDWARE OFFLINE — shift stays live. Waiting for ESP32 reconnect.',
                              ),
                              const SizedBox(height: 10),
                            ],
                            _UnitsRow(
                              station: station,
                              unitIds: unitIds,
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
    required this.station,
    required this.unitIds,
    required this.selectedUnitId,
    required this.onSelect,
    required this.abortNoticeFor,
    required this.receiptOverlays,
    required this.onDismissReceipt,
  });

  final StationState station;
  final List<int> unitIds;
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
        for (int i = 0; i < unitIds.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _unitCell(tokens, station.bay(unitIds[i]))),
        ],
      ],
    );
  }

  Widget _unitCell(DispensrTokens tokens, DispenserBay bay) {
    final SaleTransaction? receiptTxn = receiptOverlays[bay.unitId];
    return ClipRRect(
      borderRadius: BorderRadius.circular(tokens.radius20),
      child: Stack(
        children: <Widget>[
          DispenserUnitsWidget(
            key: ValueKey<int>(bay.unitId),
            data: DispenserUnitData.fromBay(
              bay,
              linkOnline: station.isUnitLinkOnline(bay.unitId),
            ),
            isSelected: selectedUnitId == bay.unitId,
            abortNotice: abortNoticeFor(bay.unitId),
            onSelect: () => onSelect(bay.unitId),
          ),
          if (receiptTxn != null)
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
                        DataColumn(label: Text('MANAGER')),
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
                                Text(formatTruncatedDecimal(row.volumeLiters)),
                              ),
                              DataCell(Text(formatTruncatedDecimal(row.rate))),
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

class _SaleLockBanner extends StatelessWidget {
  const _SaleLockBanner({
    required this.color,
    required this.icon,
    required this.message,
  });

  final Color color;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(tokens.radius12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: tokens.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
