import 'package:flutter/material.dart';

import '../../../core/theme/dispensr_theme.dart';
import '../../../core/widgets/fuel_point_stat_card.dart';
import '../../../features/shift/domain/shift_models.dart';
import '../../../features/shift/domain/shift_report_layout.dart';
import '../../../features/station/domain/dispenser_models.dart';
import '../../../features/station/domain/money_format.dart';

class ShiftPanelCard extends StatelessWidget {
  const ShiftPanelCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

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
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
  }
}

class ShiftKpiCard extends StatelessWidget {
  const ShiftKpiCard({
    super.key,
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

  @override
  Widget build(BuildContext context) {
    return FuelPointStatCard(
      title: label,
      value: value,
      subtitle: hint,
      icon: icon,
      badgeBackgroundColor: tint.withValues(alpha: 0.12),
      badgeIconColor: tint,
    );
  }
}

String formatUdhaarRecoverySplit(ShiftWindowMetrics metrics) {
  return 'Cash: ${formatPkr(metrics.udhaarRecoveryTotal)}  |  Account: ${formatPkr(metrics.udhaarRecoveryAccountTotal)}';
}
class ShiftUdhaarRecoveryCard extends StatelessWidget {
  const ShiftUdhaarRecoveryCard({super.key, required this.metrics});

  final ShiftWindowMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.radius20),
        border: Border.all(color: tokens.line),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tokens.coral.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.handshake_outlined,
              color: tokens.coral,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'UDHAAR RECOVERY',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 9,
                    letterSpacing: 0.8,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatPkr(metrics.udhaarRecoveryCombined),
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    height: 1.15,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  formatUdhaarRecoverySplit(metrics),
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    color: tokens.inkMuted,
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

class ShiftEmptyHint extends StatelessWidget {
  const ShiftEmptyHint({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Center(
      child: Text(
        message,
        style: TextStyle(fontFamily: 'Roboto', color: tokens.inkMuted),
      ),
    );
  }
}

/// Desktop-safe 2-axis scroller. Scrollbars share controllers with the views.
class ShiftTwoAxisScroll extends StatefulWidget {
  const ShiftTwoAxisScroll({
    super.key,
    required this.minWidth,
    required this.child,
  });

  final double minWidth;
  final Widget child;

  @override
  State<ShiftTwoAxisScroll> createState() => _ShiftTwoAxisScrollState();
}

class _ShiftTwoAxisScrollState extends State<ShiftTwoAxisScroll> {
  final ScrollController _vertical = ScrollController();
  final ScrollController _horizontal = ScrollController();

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _vertical,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _vertical,
        primary: false,
        child: Scrollbar(
          controller: _horizontal,
          thumbVisibility: true,
          notificationPredicate: (ScrollNotification notification) {
            return notification.depth == 0;
          },
          child: SingleChildScrollView(
            controller: _horizontal,
            primary: false,
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: widget.minWidth),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class ShiftSectionHeader extends StatelessWidget {
  const ShiftSectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 8),
      child: Row(
        children: <Widget>[
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
          if (trailing != null) Flexible(child: trailing!),
        ],
      ),
    );
  }
}

class ShiftSalesTable extends StatelessWidget {
  const ShiftSalesTable({
    super.key,
    required this.rows,
    this.showPayment = true,
    this.showFooter = false,
    this.compact = false,
  });

  final List<HelperSaleRecord> rows;
  final bool showPayment;
  final bool showFooter;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final double liters = rows.fold<double>(
      0,
      (double sum, HelperSaleRecord row) => sum + row.volumeLiters,
    );
    final int commercialCount = rows.where((HelperSaleRecord row) {
      return !row.isTest;
    }).length;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double floor = compact ? 860 : (showPayment ? 1480 : 1100);
        final double minWidth = compact
            ? floor
            : (constraints.maxWidth < floor ? floor : constraints.maxWidth);
        final Widget table = ShiftTwoAxisScroll(
          minWidth: minWidth,
          child: DataTable(
            headingRowHeight: compact ? 28 : 32,
            dataRowMinHeight: compact ? 32 : 44,
            dataRowMaxHeight: compact ? 42 : 52,
            horizontalMargin: compact ? 6 : 14,
            columnSpacing: compact ? 8 : 14,
            headingTextStyle: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w700,
              fontSize: compact ? 11 : 10,
              letterSpacing: 0.6,
              color: tokens.inkMuted,
            ),
            dataTextStyle: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w500,
              fontSize: compact ? 13 : 12,
              color: tokens.ink,
            ),
            columns: compact
                ? const <DataColumn>[
                    DataColumn(label: Text('TKN')),
                    DataColumn(label: Text('DATETIME')),
                    DataColumn(label: Text('UNIT')),
                    DataColumn(label: Text('LITERS'), numeric: true),
                    DataColumn(label: Text('RATE'), numeric: true),
                    DataColumn(label: Text('AMOUNT'), numeric: true),
                    DataColumn(label: Text('OPENING'), numeric: true),
                    DataColumn(label: Text('CLOSING'), numeric: true),
                    DataColumn(label: Text('PM')),
                    DataColumn(label: Text('CASH AMOUNT'), numeric: true),
                    DataColumn(label: Text('ACCOUNT AMOUNT'), numeric: true),
                    DataColumn(label: Text('CUSTOMER / VEHICLE')),
                  ]
                : <DataColumn>[
                    const DataColumn(label: Text('TOKEN #')),
                    const DataColumn(label: Text('DATE & TIME')),
                    const DataColumn(label: Text('DISPENSER UNIT')),
                    const DataColumn(label: Text('FUEL TYPE')),
                    const DataColumn(label: Text('VOLUME (L)'), numeric: true),
                    const DataColumn(label: Text('RATE (PKR)'), numeric: true),
                    const DataColumn(
                      label: Text('TOTAL AMOUNT (PKR)'),
                      numeric: true,
                    ),
                    if (showPayment)
                      const DataColumn(label: Text('PAYMENT METHOD')),
                    if (showPayment)
                      const DataColumn(label: Text('CASH'), numeric: true),
                    if (showPayment)
                      const DataColumn(label: Text('ACCOUNT'), numeric: true),
                    const DataColumn(label: Text('HELPER NAME')),
                  ],
            rows: <DataRow>[
              for (final HelperSaleRecord row in rows)
                DataRow(
                  cells: compact
                      ? <DataCell>[
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  formatLedgerToken(row.tokenNo),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: tokens.coralPressed,
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
                                ],
                              ],
                            ),
                          ),
                          DataCell(
                            Text(
                              formatShiftTableTime(row.timestamp),
                              style: TextStyle(color: tokens.inkMuted),
                            ),
                          ),
                          DataCell(Text(formatUnitLabel(row.unitId))),
                          DataCell(Text(formatTableLiters(row.volumeLiters))),
                          DataCell(Text(formatTableRate(row.rate))),
                          DataCell(
                            Text(
                              formatTablePkr(row.amountPkr),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          DataCell(Text(formatMeterReading(row.openingMeter))),
                          DataCell(Text(formatMeterReading(row.closingMeter))),
                          DataCell(
                            Text(shiftSalePaymentLabel(row, short: true)),
                          ),
                          DataCell(Text(formatTableTenderPkr(row.cashTender))),
                          DataCell(
                            Text(
                              formatTableTenderPkr(
                                shiftSaleAccountColumn(
                                  row,
                                  tenderFallback: true,
                                ),
                              ),
                            ),
                          ),
                          DataCell(_customerVehicle(row, tokens)),
                        ]
                      : <DataCell>[
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  formatLedgerToken(row.tokenNo),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: tokens.coralPressed,
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
                          DataCell(Text(formatUnitLabel(row.unitId))),
                          DataCell(Text(row.fuelType.toUpperCase())),
                          DataCell(Text(formatTableLiters(row.volumeLiters))),
                          DataCell(Text(formatTableRate(row.rate))),
                          DataCell(
                            Text(
                              formatTablePkr(row.amountPkr),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (showPayment)
                            DataCell(Text(shiftSalePaymentLabel(row))),
                          if (showPayment)
                            DataCell(
                              Text(formatTableTenderPkr(row.cashAmount)),
                            ),
                          if (showPayment)
                            DataCell(
                              Text(
                                formatTableTenderPkr(
                                  shiftSaleAccountColumn(row),
                                ),
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
                        ],
                ),
            ],
          ),
        );
        if (!showFooter) {
          return table;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(child: table),
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 10 : 14,
                compact ? 6 : 8,
                compact ? 10 : 14,
                compact ? 8 : 10,
              ),
              child: Row(
                children: <Widget>[
                  Text(
                    '${commercialCount} transaction${commercialCount == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: tokens.ink,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Total volume  ${formatTableLiters(liters)}',
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: tokens.ink,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

Widget _customerVehicle(HelperSaleRecord row, DispensrTokens tokens) {
  final String raw = row.customerName.trim();
  final String customer = raw.isEmpty || raw.toLowerCase() == 'walk-in'
      ? 'Walk-in'
      : raw;
  final String vehicle = displayVehicleNo(row.vehicleNo);
  final bool hasVehicle = vehicle != '—' && vehicle.trim().isNotEmpty;
  if (!hasVehicle) {
    return Text(customer);
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisAlignment: MainAxisAlignment.center,
    children: <Widget>[
      Text(customer),
      Text(
        vehicle,
        style: TextStyle(
          fontFamily: 'Roboto',
          fontWeight: FontWeight.w500,
          fontSize: 10,
          color: tokens.inkMuted,
        ),
      ),
    ],
  );
}
