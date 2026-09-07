import 'package:flutter/material.dart';

import '../../../core/theme/dispensr_theme.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../../../features/station/domain/dashboard_models.dart';
import '../../../features/station/domain/money_format.dart';
import 'dashboard_ui_kit.dart';

class DashboardUdhaarWatchlist extends StatelessWidget {
  const DashboardUdhaarWatchlist({
    super.key,
    required this.rows,
    required this.totalDebtors,
  });

  final List<DashboardWatchlistRow> rows;
  final int totalDebtors;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return DashboardPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: DashboardSectionTitle(
              title: 'Top udhaar customers',
              subtitle: totalDebtors <= rows.length
                  ? 'Highest outstanding balances'
                  : 'Showing top ${rows.length} of $totalDebtors debtors',
            ),
          ),
          const SizedBox(height: 8),
          _Header(tokens: tokens),
          Divider(height: 1, color: tokens.line),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 28, 14, 32),
              child: Text(
                'No outstanding udhaar on file.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Roboto', color: tokens.inkMuted),
              ),
            )
          else
            for (int i = 0; i < rows.length; i++)
              _WatchlistRow(row: rows[i], striped: i.isOdd, tokens: tokens),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.tokens});

  final DispensrTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: tokens.canvas,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 5,
            child: Text('CUSTOMER NAME', style: _headStyle(tokens)),
          ),
          Expanded(
            flex: 4,
            child: Text(
              'OUTSTANDING BALANCE (PKR)',
              textAlign: TextAlign.right,
              style: _headStyle(tokens),
            ),
          ),
        ],
      ),
    );
  }

  static TextStyle _headStyle(DispensrTokens tokens) {
    return TextStyle(
      fontFamily: 'Roboto',
      fontWeight: FontWeight.w700,
      fontSize: 9,
      letterSpacing: 0.7,
      color: tokens.inkMuted,
    );
  }
}

class _WatchlistRow extends StatelessWidget {
  const _WatchlistRow({
    required this.row,
    required this.striped,
    required this.tokens,
  });

  final DashboardWatchlistRow row;
  final bool striped;
  final DispensrTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: BoxDecoration(
        color: striped ? tokens.canvas.withValues(alpha: 0.55) : tokens.card,
        border: Border(bottom: BorderSide(color: tokens.line)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  row.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: tokens.ink,
                  ),
                ),
                Text(
                  'ID ${row.customerId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w500,
                    fontSize: 10,
                    color: tokens.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: ScaleDownMetric(
              text: formatPkrStatementWhole(row.outstandingPkr),
              alignment: Alignment.centerRight,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: tokens.bad,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
