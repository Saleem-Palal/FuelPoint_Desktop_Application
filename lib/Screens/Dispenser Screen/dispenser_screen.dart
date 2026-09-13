import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/dispensr_theme.dart';
import '../../core/widgets/app_screen_header.dart';
import '../../core/widgets/responsive_layout.dart';
import '../../features/station/domain/dispenser_models.dart';
import '../../features/station/domain/dispenser_monitor_models.dart';
import '../../features/station/presentation/dispenser_monitor_providers.dart';
import '../../features/station/presentation/station_providers.dart';
import '../../providers/settings_provider.dart';
import 'Widgets/diagnostic_bay_card.dart';
import 'Widgets/gateway_header_card.dart';
import 'Widgets/telemetry_terminal.dart';

class DispenserScreen extends ConsumerWidget {
  const DispenserScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final StationState station = ref.watch(stationControllerProvider);
    final DispenserMonitorState monitor = ref.watch(dispenserMonitorProvider);
    final StationController stationCtl = ref.read(
      stationControllerProvider.notifier,
    );
    final DispenserMonitorController monitorCtl = ref.read(
      dispenserMonitorProvider.notifier,
    );
    final List<int> unitIds = visibleDispenserUnitIds(
      showUnit5: ref.watch(settingsProvider).showUnit5,
    );

    return ColoredBox(
      color: tokens.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: AppScreenHeader(
              title: 'Dispenser Monitor',
              icon: Icons.speed_outlined,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  GatewayHeaderCard(
                    station: station,
                    monitor: monitor,
                    onGlobalLock: () {
                      stationCtl.lockAllKeypads();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Global keypad lock dispatched to all 4 bays.',
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    flex: 3,
                    child: SingleChildScrollView(
                      child: ExtentWrap(
                        maxCrossAxisExtent: 320,
                        spacing: 10,
                        runSpacing: 10,
                        children: <Widget>[
                          for (final int unitId in unitIds)
                            DiagnosticBayCard(
                              bay: station.bay(unitId),
                              endpoint: station.endpoint(unitId),
                              snapshot: monitor.diagnosticFor(unitId),
                              clock: monitor.clock,
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    flex: 2,
                    child: TelemetryTerminal(
                      monitor: monitor,
                      onUnitFilter: monitorCtl.setUnitFilter,
                      onKindFilter: monitorCtl.setKindFilter,
                      onPause: monitorCtl.setPaused,
                      onClear: monitorCtl.clearLog,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
