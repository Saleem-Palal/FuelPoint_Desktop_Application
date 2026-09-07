import 'package:flutter/material.dart';

import '../../../core/theme/dispensr_theme.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../../../features/station/domain/dashboard_models.dart';
import 'dashboard_ui_kit.dart';

class DashboardStaffStrip extends StatelessWidget {
  const DashboardStaffStrip({
    super.key,
    required this.title,
    required this.emptyMessage,
    required this.members,
    required this.range,
    required this.onRangeChanged,
  });

  final String title;
  final String emptyMessage;
  final List<DashboardStaffPerformance> members;
  final DashboardRangePreset range;
  final ValueChanged<DashboardRangePreset> onRangeChanged;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return DashboardPanel(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          DashboardSectionTitle(
            title: title,
            subtitle:
                'Sale amount, volume sold, and transactions · ${range.hint}',
            trailing: DashboardRangeChips(
              value: range,
              onChanged: onRangeChanged,
            ),
          ),
          const SizedBox(height: 12),
          if (members.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                emptyMessage,
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Roboto', color: tokens.inkMuted),
              ),
            )
          else
            ExtentWrap(
              maxCrossAxisExtent: 320,
              children: <Widget>[
                for (final DashboardStaffPerformance member in members)
                  DashboardVolumeCard(
                    title: member.name,
                    volumeLiters: member.volumeLiters,
                    revenuePkr: member.revenuePkr,
                    txnCount: member.txnCount,
                    shareOfPeak: member.shareOfPeak,
                    emphasize:
                        member.shareOfPeak >= 1 && member.volumeLiters > 0,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
