import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/dispensr_theme.dart';
import '../../core/widgets/app_screen_header.dart';
import '../../core/widgets/responsive_layout.dart';
import '../../core/widgets/station_lock_banner.dart';
import '../../features/station/domain/dispenser_models.dart';
import '../../features/station/domain/dispenser_monitor_models.dart';
import '../../features/station/domain/station_link_alerts.dart';
import '../../features/station/presentation/dispenser_monitor_providers.dart';
import '../../features/station/presentation/office_lan_provider.dart';
import '../../features/station/presentation/station_providers.dart';
import '../../providers/settings_provider.dart';
import 'Widgets/diagnostic_unit_card.dart';
import 'Widgets/gateway_header_card.dart';
import 'Widgets/telemetry_terminal.dart';

class DispenserScreen extends ConsumerStatefulWidget {
  const DispenserScreen({super.key});

  @override
  ConsumerState<DispenserScreen> createState() => _DispenserScreenState();
}

class _DispenserScreenState extends ConsumerState<DispenserScreen> {
  bool _telemetryExpanded = true;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final StationState station = ref.watch(stationControllerProvider);
    final DispenserMonitorState monitor = ref.watch(dispenserMonitorProvider);
    final StationController stationCtl = ref.read(
      stationControllerProvider.notifier,
    );
    final DispenserMonitorController monitorCtl = ref.read(
      dispenserMonitorProvider.notifier,
    );
    final bool showManualKeypadUnlock = ref.watch(
      settingsProvider.select(
        (SettingsState settings) => settings.showManualKeypadUnlock,
      ),
    );
    final List<int> unitIds = visibleDispenserUnitIds(
      showUnit5: ref.watch(settingsProvider).showUnit5,
    );
    final bool onOfficeLan = ref.watch(officeLanProvider).asData?.value ?? true;
    final List<StationLinkAlert> linkAlerts = buildStationLinkAlerts(
      onOfficeLan: onOfficeLan,
      unitIds: unitIds,
      station: station,
      monitor: monitor,
    );

    final Widget terminal = TelemetryTerminal(
      monitor: monitor,
      expanded: _telemetryExpanded,
      onToggleExpanded: () {
        setState(() {
          _telemetryExpanded = !_telemetryExpanded;
        });
      },
      onUnitFilter: monitorCtl.setUnitFilter,
      onKindFilter: monitorCtl.setKindFilter,
      onPause: monitorCtl.setPaused,
      onClear: monitorCtl.clearLog,
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
                  if (linkAlerts.isNotEmpty) ...<Widget>[
                    StationLinkAlertStrip(alerts: linkAlerts, tokens: tokens),
                    const SizedBox(height: 10),
                  ],
                  GatewayHeaderCard(
                    station: station,
                    monitor: monitor,
                    onOfficeLan: onOfficeLan,
                    showManualKeypadUnlock: showManualKeypadUnlock,
                    anyKeypadLocked: unitIds.any(
                      (int unitId) => station.unit(unitId).keypadLocked,
                    ),
                    onGlobalLock: () {
                      final bool unlocking = unitIds.any(
                        (int unitId) => station.unit(unitId).keypadLocked,
                      );
                      stationCtl.toggleAllMonitorKeypads();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            unlocking
                                ? 'Global keypad unlock for 5 seconds, then auto-lock.'
                                : 'Global keypad lock dispatched to all ${unitIds.length} units.',
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    flex: _telemetryExpanded ? 3 : 1,
                    child: SingleChildScrollView(
                      child: ExtentWrap(
                        maxCrossAxisExtent: 320,
                        spacing: 10,
                        runSpacing: 10,
                        children: <Widget>[
                          for (final int unitId in unitIds)
                            DiagnosticUnitCard(
                              unit: station.unit(unitId),
                              endpoint: station.endpoint(unitId),
                              snapshot: monitor.diagnosticFor(unitId),
                              clock: monitor.clock,
                              showManualKeypadUnlock: showManualKeypadUnlock,
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_telemetryExpanded)
                    Expanded(flex: 2, child: terminal)
                  else
                    terminal,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
