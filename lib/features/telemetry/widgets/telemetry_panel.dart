import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/metric_card.dart';
import '../../../core/widgets/section_card.dart';
import '../../connection/domain/models.dart';
import '../../dashboard/dashboard_controller.dart';
import '../domain/telemetry_models.dart';

class TelemetryPanel extends StatelessWidget {
  const TelemetryPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final DashboardController controller = context.watch<DashboardController>();
    final TelemetrySnapshot data = controller.telemetry;

    return SectionCard(
      title: 'Live readings',
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final int columns = constraints.maxWidth >= 640
              ? 3
              : constraints.maxWidth >= 420
              ? 2
              : 1;
          return GridView.count(
            crossAxisCount: columns,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.6,
            children: <Widget>[
              MetricCard(
                label: 'Connection',
                value: _linkLabel(controller.linkState),
              ),
              MetricCard(
                label: 'Current volume',
                value: _number(data.volumeLiters, suffix: ' L', decimals: 2),
              ),
              MetricCard(
                label: 'Total amount',
                value: _number(data.totalAmount, decimals: 2),
              ),
              MetricCard(
                label: 'Price per liter',
                value: _number(data.unitRate, decimals: 2),
              ),
              MetricCard(
                label: 'Total meter',
                value: _number(data.totalMeter, decimals: 2),
              ),
              MetricCard(label: 'Pump status', value: data.statusLabel),
              MetricCard(label: 'Product', value: data.productLabel),
              MetricCard(label: 'Time', value: data.timeLabel ?? '—'),
              MetricCard(
                label: 'Last event',
                value: data.lastEvent?.message ?? '—',
              ),
            ],
          );
        },
      ),
    );
  }

  String _linkLabel(LinkState state) {
    switch (state) {
      case LinkState.connected:
        return 'Connected';
      case LinkState.offline:
        return 'Offline';
      case LinkState.connecting:
        return 'Connecting';
      case LinkState.disconnected:
        return 'Not connected';
    }
  }

  String _number(double? value, {String suffix = '', int decimals = 2}) {
    if (value == null) {
      return '—';
    }
    return '${value.toStringAsFixed(decimals)}$suffix';
  }
}
