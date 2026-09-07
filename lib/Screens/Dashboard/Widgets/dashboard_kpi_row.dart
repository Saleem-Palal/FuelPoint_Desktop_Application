import 'package:flutter/material.dart';

import '../../../core/theme/dispensr_theme.dart';
import '../../../core/widgets/fuel_point_stat_card.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../../../features/station/domain/dashboard_models.dart';
import '../../../features/station/domain/money_format.dart';

class DashboardKpiRow extends StatelessWidget {
  const DashboardKpiRow({super.key, required this.kpis});

  final DashboardKpis kpis;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return ExtentWrap(
      maxCrossAxisExtent: 320,
      children: <Widget>[
        FuelPointStatCard(
          title: "Today's Diesel Sold",
          value: formatLiters(kpis.dieselSoldLiters24h),
          subtitle: '${kpis.dieselSoldTxnCount24h} fills · last 24 hours',
          icon: Icons.local_gas_station_outlined,
          badgeBackgroundColor: tokens.coral.withValues(alpha: 0.12),
          badgeIconColor: tokens.coral,
        ),
        FuelPointStatCard(
          title: "Today's Direct Cash Sales",
          value: formatPkrWhole(kpis.cashSalesPkrToday),
          subtitle: '${kpis.cashTxnCountToday} cash diesel transactions today',
          icon: Icons.payments_outlined,
          badgeBackgroundColor: tokens.good.withValues(alpha: 0.12),
          badgeIconColor: tokens.good,
          valueColor: tokens.good,
        ),
        FuelPointStatCard(
          title: "Today's Udhaar Extended",
          value: formatPkrWhole(kpis.udhaarExtendedPkrToday),
          subtitle:
              '${kpis.udhaarTxnCountToday} credit transactions issued today',
          icon: Icons.handshake_outlined,
          badgeBackgroundColor: tokens.warn.withValues(alpha: 0.12),
          badgeIconColor: tokens.warn,
          borderColor: tokens.warn.withValues(alpha: 0.35),
          valueColor: tokens.warn,
        ),
        FuelPointStatCard(
          title: 'Total Outstanding Udhaar',
          value: formatPkrStatementWhole(kpis.totalOutstandingPkr),
          subtitle: '${kpis.activeDebtAccounts} accounts still owing',
          icon: Icons.account_balance_wallet_outlined,
          badgeBackgroundColor: tokens.bad.withValues(alpha: 0.12),
          badgeIconColor: tokens.bad,
          borderColor: tokens.bad.withValues(alpha: 0.35),
          valueColor: tokens.bad,
        ),
      ],
    );
  }
}
