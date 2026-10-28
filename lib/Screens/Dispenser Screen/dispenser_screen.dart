import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/dispensr_theme.dart';
import '../../features/station/data/esp_usb_wifi_windows.dart';
import '../../features/station/data/station_wifi_store.dart';
import '../../features/station/data/wifi_status.dart';
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
  DispenserMonitorController? _monitor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _monitor = ref.read(dispenserMonitorProvider.notifier);
      _monitor!.setScreenOpen(true);
    });
  }

  @override
  void dispose() {
    _monitor?.setScreenOpen(false);
    super.dispose();
  }

  void _openNetworkDialog(BuildContext context) {
    if (!kDebugMode) {
      return;
    }
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return const Center(child: _DebugStationWifiCard());
      },
    );
  }

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
    final bool onOfficeLan = ref.watch(stationLanOkProvider);
    final String officeSsid = ref.watch(stationOfficeSsidProvider);
    final List<StationLinkAlert> linkAlerts = buildStationLinkAlerts(
      onOfficeLan: onOfficeLan,
      unitIds: unitIds,
      station: station,
      monitor: monitor,
      networkName: stationWifiAlertName(officeSsid),
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
                    officeSsid: officeSsid,
                    showManualKeypadUnlock: showManualKeypadUnlock,
                    anyKeypadLocked: unitIds.any(
                      (int unitId) => station.unit(unitId).keypadLocked,
                    ),
                    onChangeNetwork: kDebugMode
                        ? () => _openNetworkDialog(context)
                        : null,
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

/// One network name for every unit. Built only when [kDebugMode] is true.
class _DebugStationWifiCard extends ConsumerStatefulWidget {
  const _DebugStationWifiCard();

  @override
  ConsumerState<_DebugStationWifiCard> createState() =>
      _DebugStationWifiCardState();
}

class _DebugStationWifiCardState extends ConsumerState<_DebugStationWifiCard> {
  final TextEditingController _ssid = TextEditingController(text: 'System');
  final TextEditingController _gateway = TextEditingController(
    text: '192.168.0.1',
  );
  final TextEditingController _password = TextEditingController();
  List<String> _ports = const <String>[];
  String? _port;
  bool _busy = false;
  String _status =
      'Every unit joins this one network. System keeps the fixed pump addresses.';

  @override
  void initState() {
    super.initState();
    unawaited(_loadSaved());
  }

  Future<void> _loadSaved() async {
    final String ssid = await StationWifiStore.read();
    final String gateway = await StationWifiStore.readGateway();
    if (!mounted) {
      return;
    }
    setState(() {
      _ssid.text = ssid;
      if (gateway.isNotEmpty) {
        _gateway.text = gateway;
      }
    });
  }

  @override
  void dispose() {
    _ssid.dispose();
    _gateway.dispose();
    _password.dispose();
    super.dispose();
  }

  bool _namesOk() {
    final String ssid = _ssid.text.trim();
    if (ssid.isEmpty || ssid.length > 32 || _password.text.length > 64) {
      _setStatus('Network name must be 1–32 characters. Password up to 64.');
      return false;
    }
    if (ssid.contains('"') || ssid.contains('\\')) {
      _setStatus('The network name cannot contain quotes or backslashes.');
      return false;
    }
    if (!StationWifiStore.isSystemNetwork(ssid) &&
        !StationWifiStore.isIpv4(_gateway.text.trim())) {
      _setStatus('Enter the gateway IP, such as 192.168.1.1.');
      return false;
    }
    return true;
  }

  void _setStatus(String text) {
    if (!mounted) {
      return;
    }
    setState(() => _status = text);
  }

  Future<void> _sendOnline() async {
    if (!kDebugMode || !_namesOk()) {
      return;
    }
    setState(() => _busy = true);
    try {
      final int sent = await ref
          .read(stationControllerProvider.notifier)
          .pushDebugWifi(
            ssid: _ssid.text.trim(),
            password: _password.text,
            gateway: _gateway.text.trim(),
          );
      _setStatus(
        sent == 0
            ? 'No unit is online. Plug a board into this computer and use USB.'
            : 'Sent to $sent unit${sent == 1 ? '' : 's'}. They will join ${_ssid.text.trim()}.',
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _refreshPorts() async {
    if (!kDebugMode) {
      return;
    }
    if (!Platform.isWindows) {
      _setStatus('USB setup is available on Windows.');
      return;
    }
    setState(() => _busy = true);
    try {
      final List<String> ports = await EspUsbWifi.listPorts();
      if (!mounted) {
        return;
      }
      setState(() {
        _ports = ports;
        _port = ports.contains(_port)
            ? _port
            : (ports.isEmpty ? null : ports.first);
        _status = ports.isEmpty
            ? 'No COM port found. Plug in the board and close the Arduino serial monitor.'
            : 'Choose the board’s COM port, then send.';
      });
    } on EspUsbWifiException catch (error) {
      _setStatus(error.message);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _sendUsb() async {
    if (!kDebugMode || !_namesOk()) {
      return;
    }
    final String? port = _port;
    if (port == null) {
      _setStatus('Choose a COM port first.');
      return;
    }
    setState(() => _busy = true);
    _setStatus('Opening $port. The board restarts, then joins the network.');
    try {
      final DispenserWifiStatus status = await ref
          .read(stationControllerProvider.notifier)
          .pushDebugWifiOverUsb(
            portName: port,
            ssid: _ssid.text.trim(),
            password: _password.text,
            gateway: _gateway.text.trim(),
          );
      final String where = status.dhcp
          ? 'Unit ${status.unitId} is at ${status.ip}. The monitor will use that address.'
          : 'Unit ${status.unitId} stayed on its fixed pump address.';
      _setStatus(where);
    } on EspUsbWifiException catch (error) {
      _setStatus(error.message);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final int online = ref.watch(
      stationControllerProvider.select(
        (StationState station) => station.endpoints.values
            .where((UnitEndpoint endpoint) => endpoint.connected)
            .length,
      ),
    );
    final TextStyle label = TextStyle(
      fontFamily: 'Roboto',
      fontWeight: FontWeight.w600,
      fontSize: 13,
      color: tokens.ink,
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.card,
          borderRadius: BorderRadius.circular(tokens.radius20),
          border: Border.all(color: tokens.line),
          boxShadow: tokens.cardShadow,
        ),
        child: Material(
          color: const Color(0x00000000),
          borderRadius: BorderRadius.circular(tokens.radius20),
          clipBehavior: Clip.antiAlias,
          child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: Text('Change network', style: label)),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close, size: 18, color: tokens.inkMuted),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Debug only. One network for every unit. $online online now.',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 11,
                color: tokens.inkMuted,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _ssid,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Network name',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _gateway,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Gateway IP',
                isDense: true,
                hintText: '192.168.1.1',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _password,
              enabled: !_busy,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                FilledButton(
                  onPressed: _busy ? null : _sendOnline,
                  child: const Text('Send to connected units'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _refreshPorts,
                  child: const Text('Find USB'),
                ),
                if (_ports.isNotEmpty)
                  DropdownButton<String>(
                    value: _port,
                    items: <DropdownMenuItem<String>>[
                      for (final String port in _ports)
                        DropdownMenuItem<String>(
                          value: port,
                          child: Text(port),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (String? port) => setState(() => _port = port),
                  ),
                if (_port != null)
                  OutlinedButton(
                    onPressed: _busy ? null : _sendUsb,
                    child: const Text('Send by USB'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _status,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 11,
                color: tokens.inkMuted,
              ),
            ),
          ],
        ),
      ),
        ),
      ),
    );
  }
}
