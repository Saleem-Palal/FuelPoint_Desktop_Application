import 'package:flutter/material.dart';

import '../../../core/theme/dispensr_theme.dart';
import '../../../core/widgets/fuel_point_stat_card.dart';
import '../../../features/shift/domain/shift_models.dart';
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
  });

  final List<HelperSaleRecord> rows;
  final bool showPayment;
  final bool showFooter;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final double liters = rows.fold<double>(
      0,
      (double sum, HelperSaleRecord row) => sum + row.volumeLiters,
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double floor = showPayment ? 1240 : 1100;
        final double minWidth = constraints.maxWidth < floor
            ? floor
            : constraints.maxWidth;
        final Widget table = ShiftTwoAxisScroll(
          minWidth: minWidth,
          child: DataTable(
            headingRowHeight: 32,
            dataRowMinHeight: 44,
            dataRowMaxHeight: 52,
            horizontalMargin: 14,
            columnSpacing: 14,
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
              const DataColumn(label: Text('DATE & TIME')),
              const DataColumn(label: Text('DISPENSER UNIT')),
              const DataColumn(label: Text('FUEL TYPE')),
              const DataColumn(label: Text('VOLUME (L)'), numeric: true),
              const DataColumn(label: Text('RATE (PKR)'), numeric: true),
              const DataColumn(
                label: Text('TOTAL AMOUNT (PKR)'),
                numeric: true,
              ),
              if (showPayment) const DataColumn(label: Text('PAYMENT METHOD')),
              const DataColumn(label: Text('HELPER NAME')),
            ],
            rows: <DataRow>[
              for (final HelperSaleRecord row in rows)
                DataRow(
                  cells: <DataCell>[
                    DataCell(
                      Text(
                        formatLedgerToken(row.tokenNo),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: tokens.coralPressed,
                        ),
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
                    DataCell(Text(formatLiters(row.volumeLiters))),
                    DataCell(Text(formatRate(row.rate))),
                    DataCell(
                      Text(
                        formatPkr(row.amountPkr),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (showPayment) DataCell(Text(row.payment.label)),
                    DataCell(
                      Text(
                        row.helperName.trim().isEmpty ? '—' : row.helperName,
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
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              child: Row(
                children: <Widget>[
                  Text(
                    '${rows.length} transaction${rows.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: tokens.ink,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Total volume  ${formatLiters(liters)}',
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
