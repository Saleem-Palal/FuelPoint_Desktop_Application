import 'package:flutter/material.dart';

import '../../../core/widgets/responsive_layout.dart';
import '../../../features/station/domain/dashboard_models.dart';
import 'dashboard_ui_kit.dart';

class DashboardUnitStrip extends StatelessWidget {
  const DashboardUnitStrip({
    super.key,
    required this.units,
    required this.range,
    required this.onRangeChanged,
  });

  final List<DashboardUnitPerformance> units;
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
              for (final DashboardUnitPerformance unit in units)
                DashboardVolumeCard(
                  title: unit.label,
                  volumeLiters: unit.volumeLiters,
                  revenuePkr: unit.revenuePkr,
                  txnCount: unit.txnCount,
                  shareOfPeak: unit.shareOfPeak,
                  emphasize: unit.isPeakLane,
                  badge: unit.isPeakLane ? 'PEAK LANE' : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
