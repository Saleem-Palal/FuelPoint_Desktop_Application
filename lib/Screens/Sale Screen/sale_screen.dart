import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../Shell/shell_navigation.dart';
import '../../core/theme/dispensr_theme.dart';
import '../../core/widgets/app_screen_header.dart';
import '../../core/widgets/station_lock_banner.dart';
import '../../features/access/domain/access_policy.dart';
import '../../features/shift/domain/shift_models.dart';
import '../../features/shift/presentation/shift_providers.dart';
import '../../features/station/domain/dispenser_models.dart';
import '../../features/station/domain/dispenser_monitor_models.dart';
import '../../features/station/domain/money_format.dart';
import '../../features/station/domain/station_link_alerts.dart';
import '../../features/station/presentation/dispenser_monitor_providers.dart';
import '../../features/station/presentation/office_lan_provider.dart';
import '../../features/station/presentation/station_providers.dart';
import '../../features/station/presentation/workspace_refresh.dart';
import '../../providers/settings_provider.dart';
import '../Ledger Screen/ledger_screen.dart';
import 'Widgets/pending_account_banner.dart';
import 'Widgets/direct_sale_card_dialog.dart';
import 'Widgets/Services/demo_controls_bar.dart';
import 'Widgets/Services/dispenser_units_widget.dart';
import 'Widgets/Services/generate_receipt.dart';
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
    _mismatchHide?.cancel();
    super.dispose();
  }

  Timer? _mismatchHide;

  void _armMismatchHide() {
    _mismatchHide?.cancel();
    _mismatchHide = Timer(const Duration(seconds: 20), () {
      if (!mounted) {
        return;
      }
      ref.read(meterMismatchNoticeProvider.notifier).state = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final int selected = ref.watch(selectedDispenserIndexProvider);
    final List<int> unitIds = visibleDispenserUnitIds(
      showUnit5: ref.watch(
        settingsProvider.select((SettingsState settings) => settings.showUnit5),
      ),
    );
    final bool liveShift =
        ref.watch(shiftWorkspaceProvider).activeShift?.isOpen == true;
    final bool onOfficeLan = ref.watch(officeLanProvider).asData?.value ?? true;
    final StationState station = ref.watch(stationControllerProvider);
    final DispenserMonitorState monitor = ref.watch(dispenserMonitorProvider);
    final List<StationLinkAlert> linkAlerts = buildStationLinkAlerts(
      onOfficeLan: onOfficeLan,
      unitIds: unitIds,
      station: station,
      monitor: monitor,
    );
    final MeterMismatchNotice? mismatch = ref.watch(
      meterMismatchNoticeProvider,
    );
    ref.listen<MeterMismatchNotice?>(meterMismatchNoticeProvider, (
      MeterMismatchNotice? previous,
      MeterMismatchNotice? next,
    ) {
      if (next == null) {
        _mismatchHide?.cancel();
        return;
      }
      _armMismatchHide();
    });

    return Stack(
      children: <Widget>[
        ColoredBox(
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
                          constraints: BoxConstraints(
                            minWidth: viewport.maxWidth,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                if (shouldEnforceStationGuards &&
                                    !liveShift) ...<Widget>[
                                  StationLockBanner(
                                    color: tokens.warn,
                                    icon: Icons.lock_clock,
                                    message:
                                        'No LIVE shift — start a manager shift to enable keypads and sales.',
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                if (linkAlerts.isNotEmpty) ...<Widget>[
                                  StationLinkAlertStrip(
                                    alerts: linkAlerts,
                                    tokens: tokens,
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                const _ShiftPeekKpis(),
                                const SizedBox(height: 10),
                                if (DemoControlsBar.visible) ...<Widget>[
                                  const DemoControlsBar(),
                                  const SizedBox(height: 10),
                                ],
                                _UnitsRow(
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
                                  receiptOverlays: ref.watch(
                                    receiptOverlayTxnsProvider,
                                  ),
                                  onDismissReceipt: (int unitId) {
                                    dismissUnitReceiptOverlay(ref, unitId);
                                  },
                                ),
                                const SizedBox(height: 10),
                                const PendingAccountBanner(),
                                _TransactionsCard(
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
        ),
        if (mismatch != null)
          Positioned(
            right: 16,
            bottom: 16,
            child: _MeterMismatchToast(
              notice: mismatch,
              onClose: () {
                _mismatchHide?.cancel();
                ref.read(meterMismatchNoticeProvider.notifier).state = null;
              },
            ),
          ),
      ],
    );
  }
}

class _UnitsRow extends ConsumerWidget {
  const _UnitsRow({
    required this.unitIds,
    required this.selectedUnitId,
    required this.onSelect,
    required this.receiptOverlays,
    required this.onDismissReceipt,
  });

  final List<int> unitIds;
  final int selectedUnitId;
  final ValueChanged<int> onSelect;
  final Map<int, SaleTransaction> receiptOverlays;
  final ValueChanged<int> onDismissReceipt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final StationState station = ref.watch(stationControllerProvider);
    final DispenserMonitorState monitor = ref.watch(dispenserMonitorProvider);
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < unitIds.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _unitCell(tokens, station.bay(unitIds[i]), station, monitor),
          ),
        ],
      ],
    );
  }

  Widget _unitCell(
    DispensrTokens tokens,
    DispenserBay bay,
    StationState station,
    DispenserMonitorState monitor,
  ) {
    final SaleTransaction? receiptTxn = receiptOverlays[bay.unitId];
    return ClipRRect(
      borderRadius: BorderRadius.circular(tokens.radius20),
      child: Stack(
        children: <Widget>[
          DispenserUnitsWidget(
            key: ValueKey<int>(bay.unitId),
            data: DispenserUnitData.fromBay(
              bay,
              espConnected:
                  !shouldEnforceStationGuards ||
                  station.endpoint(bay.unitId).connected,
              fdxBoardLinked:
                  !shouldEnforceStationGuards ||
                  monitor.diagnosticFor(bay.unitId).espToBoardLink != false,
            ),
            isSelected: selectedUnitId == bay.unitId,
            abortNotice: station.abortNoticeFor(bay.unitId),
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

class _TransactionsCard extends ConsumerWidget {
  const _TransactionsCard({required this.onViewAll});

  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final List<SaleTransaction> rows = ref.watch(
      stationControllerProvider.select(
        (StationState station) => station.recentTransactions,
      ),
    );
    final bool showEdit = ref.watch(
      settingsProvider.select(
        (SettingsState settings) => settings.showRecentSaleEdit,
      ),
    );

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
            SizedBox(
              height: 280,
              child: SingleChildScrollView(
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final double tableWidth = constraints.maxWidth < 1600
                        ? 1600
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
                          columns: <DataColumn>[
                            const DataColumn(label: Text('TOKEN #')),
                            const DataColumn(label: Text('DATETIME')),
                            const DataColumn(label: Text('UNIT NO.')),
                            const DataColumn(label: Text('AMOUNT')),
                            const DataColumn(label: Text('LITERS')),
                            const DataColumn(label: Text('RATE')),
                            const DataColumn(label: Text('OPENING READING')),
                            const DataColumn(label: Text('CLOSING READING')),
                            const DataColumn(label: Text('PAYMENT METHOD')),
                            const DataColumn(
                              label: Text('CASH'),
                              numeric: true,
                            ),
                            const DataColumn(
                              label: Text('ACCOUNT'),
                              numeric: true,
                            ),
                            const DataColumn(label: Text('CUSTOMER NAME')),
                            const DataColumn(label: Text('VEHICLE NO')),
                            const DataColumn(label: Text('HELPER')),
                            const DataColumn(label: Text('MANAGER')),
                            const DataColumn(label: Text('ACTIONS')),
                          ],
                          rows: <DataRow>[
                            for (final SaleTransaction row in rows)
                              DataRow(
                                cells: <DataCell>[
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        Text(
                                          isDirectSaleToken(row.tokenNo)
                                              ? formatLedgerToken(row.tokenNo)
                                              : formatTokenNo(row.tokenNo),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        if (row.isTest) ...<Widget>[
                                          const SizedBox(width: 6),
                                          Text(
                                            'Test',
                                            style: TextStyle(
                                              fontFamily: 'Roboto',
                                              fontWeight: FontWeight.w700,
                                              fontSize: 10,
                                              color: tokens.warn,
                                            ),
                                          ),
                                        ] else if (row.edited) ...<Widget>[
                                          const SizedBox(width: 6),
                                          Text(
                                            'Edited',
                                            style: TextStyle(
                                              fontFamily: 'Roboto',
                                              fontWeight: FontWeight.w700,
                                              fontSize: 10,
                                              color: tokens.coralPressed,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      formatDateTime(row.timestamp),
                                      style: TextStyle(color: tokens.inkMuted),
                                    ),
                                  ),
                                  DataCell(
                                    Text(formatSaleUnitColumn(row.unitId)),
                                  ),
                                  DataCell(
                                    Text(
                                      formatTablePkr(row.amountPkr),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      formatTruncatedDecimal(row.volumeLiters),
                                    ),
                                  ),
                                  DataCell(
                                    Text(formatTruncatedDecimal(row.rate)),
                                  ),
                                  DataCell(
                                    Text(formatMeterReading(row.openingMeter)),
                                  ),
                                  DataCell(
                                    Text(formatMeterReading(row.closingMeter)),
                                  ),
                                  DataCell(
                                    Text(
                                      row.isTest ? 'Test' : row.payment.label,
                                    ),
                                  ),
                                  DataCell(
                                    Text(formatTableTenderPkr(row.cashAmount)),
                                  ),
                                  DataCell(
                                    Text(formatTableTenderPkr(row.accountAmount)),
                                  ),
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
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        if (row.isTest)
                                          Text(
                                            '—',
                                            style: TextStyle(
                                              color: tokens.inkMuted,
                                            ),
                                          )
                                        else ...<Widget>[
                                          IconButton(
                                            tooltip: 'Print',
                                            visualDensity:
                                                VisualDensity.compact,
                                            iconSize: 18,
                                            onPressed: () {
                                              unawaited(
                                                _printRecent(context, row),
                                              );
                                            },
                                            icon: Icon(
                                              Icons.print_outlined,
                                              color: tokens.ink,
                                            ),
                                          ),
                                          if (showEdit)
                                            IconButton(
                                              tooltip: 'Edit',
                                              visualDensity:
                                                  VisualDensity.compact,
                                              iconSize: 18,
                                              onPressed: () {
                                                unawaited(
                                                  _editRecent(
                                                    context,
                                                    ref,
                                                    row,
                                                  ),
                                                );
                                              },
                                              icon: Icon(
                                                Icons.edit_outlined,
                                                color: tokens.ink,
                                              ),
                                            ),
                                        ],
                                      ],
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
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> _printRecent(BuildContext context, SaleTransaction row) async {
  try {
    await spoolSaleReceipt(
      context: context,
      txn: row,
      kind: ReceiptPrintKind.secondCopy,
    );
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          row.payment.printsTwoCopies
              ? 'Second copy — 2 slips sent to printer'
              : 'Second copy sent to printer',
        ),
      ),
    );
  } catch (error, stack) {
    debugPrint('Recent reprint failed: $error\n$stack');
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Could not print receipt. $error')));
  }
}

Future<void> _editRecent(
  BuildContext context,
  WidgetRef ref,
  SaleTransaction row,
) async {
  final bool? saved = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return EditSaleDialog(txn: row);
    },
  );
  if (!context.mounted || saved != true) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('${formatLedgerToken(row.tokenNo)} updated')),
  );
}

class _MeterMismatchToast extends StatelessWidget {
  const _MeterMismatchToast({required this.notice, required this.onClose});

  final MeterMismatchNotice notice;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(tokens.radius12),
      color: tokens.card,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Meter does not match previous sale',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: tokens.bad,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
                    onPressed: onClose,
                    icon: Icon(Icons.close, size: 18, color: tokens.inkMuted),
                  ),
                ],
              ),
              Text(
                'Unit ${notice.unitId} only — not compared to other pumps.\n'
                'Sale was still saved.',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 12,
                  color: tokens.inkMuted,
                ),
              ),
              const SizedBox(height: 8),
              _mathLine(
                tokens,
                'Previous ${formatLedgerToken(notice.previousTokenNo)} closing',
                notice.previousClosingLabel,
              ),
              _mathLine(
                tokens,
                'This ${formatLedgerToken(notice.currentTokenNo)} opening',
                notice.currentOpeningLabel,
              ),
              _mathLine(tokens, 'Difference', notice.differenceLabel),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mathLine(DispensrTokens tokens, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 11,
                color: tokens.inkMuted,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w700,
              fontSize: 11,
              color: tokens.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShiftPeekKpis extends ConsumerStatefulWidget {
  const _ShiftPeekKpis();

  @override
  ConsumerState<_ShiftPeekKpis> createState() => _ShiftPeekKpisState();
}

class _ShiftPeekKpisState extends ConsumerState<_ShiftPeekKpis> {
  bool _revealed = false;

  void _hold(bool on) {
    if (_revealed == on) {
      return;
    }
    setState(() {
      _revealed = on;
    });
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final ShiftWindowMetrics metrics = ref.watch(activeShiftMetricsProvider);
    final bool liveShift =
        ref.watch(shiftWorkspaceProvider).activeShift?.isOpen == true;
    const String hidden = '••••••';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Material(
            color: liveShift ? tokens.coral : tokens.card,
            borderRadius: BorderRadius.circular(tokens.radius20),
            child: InkWell(
              onTap: liveShift
                  ? () {
                      unawaited(showDirectSaleCard(context));
                    }
                  : null,
              borderRadius: BorderRadius.circular(tokens.radius20),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(tokens.radius20),
                  border: liveShift
                      ? null
                      : Border.all(color: tokens.line),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.add_card_outlined,
                      size: 18,
                      color: liveShift ? Colors.white : tokens.inkMuted,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Direct Sale',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: liveShift ? Colors.white : tokens.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _PeekKpiCard(
              tokens: tokens,
              title: 'Current Shift Total Volume Dispensed',
              value: _revealed ? formatLiters(metrics.totalLiters) : hidden,
              icon: Icons.opacity_outlined,
              tint: tokens.good,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _PeekKpiCard(
              tokens: tokens,
              title: 'Total Amount',
              value: _revealed ? formatPkr(metrics.totalSale) : hidden,
              icon: Icons.payments_outlined,
              tint: tokens.coral,
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: liveShift
                ? 'Hold to show shift totals'
                : 'Hold to show totals (no LIVE shift)',
            child: Listener(
              onPointerDown: (_) => _hold(true),
              onPointerUp: (_) => _hold(false),
              onPointerCancel: (_) => _hold(false),
              child: Material(
                color: tokens.card,
                borderRadius: BorderRadius.circular(tokens.radius20),
                child: Container(
                  width: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(tokens.radius20),
                    border: Border.all(color: tokens.line),
                  ),
                  child: Icon(
                    _revealed
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 22,
                    color: _revealed ? tokens.good : tokens.inkMuted,
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

class _PeekKpiCard extends StatelessWidget {
  const _PeekKpiCard({
    required this.tokens,
    required this.title,
    required this.value,
    required this.icon,
    required this.tint,
  });

  final DispensrTokens tokens;
  final String title;
  final String value;
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
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
              color: tint.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: tint, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 9,
                    letterSpacing: 0.7,
                    color: tokens.inkMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    height: 1.2,
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
