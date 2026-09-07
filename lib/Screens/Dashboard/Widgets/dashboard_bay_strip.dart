import 'package:flutter/material.dart';

import '../../../core/widgets/responsive_layout.dart';
import '../../../features/station/domain/dashboard_models.dart';
import 'dashboard_ui_kit.dart';

class DashboardBayStrip extends StatelessWidget {
  const DashboardBayStrip({
    super.key,
    required this.bays,
    required this.range,
    required this.onRangeChanged,
  });

  final List<DashboardBayPerformance> bays;
  final DashboardRangePreset range;
  final ValueChanged<DashboardRangePreset> onRangeChanged;

  @override
  Widget build(BuildContext context) {
    return DashboardPanel(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          DashboardSectionTitle(
            title: 'Per-dispenser volume',
            subtitle: 'Liters and revenue from sales_history · ${range.hint}',
            trailing: DashboardRangeChips(
              value: range,
              onChanged: onRangeChanged,
            ),
          ),
          const SizedBox(height: 12),
          ExtentWrap(
            maxCrossAxisExtent: 320,
            children: <Widget>[
              for (final DashboardBayPerformance bay in bays)
                DashboardVolumeCard(
                  title: bay.label,
                  volumeLiters: bay.volumeLiters,
                  revenuePkr: bay.revenuePkr,
                  txnCount: bay.txnCount,
                  shareOfPeak: bay.shareOfPeak,
                  emphasize: bay.isPeakLane,
                  badge: bay.isPeakLane ? 'PEAK LANE' : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
