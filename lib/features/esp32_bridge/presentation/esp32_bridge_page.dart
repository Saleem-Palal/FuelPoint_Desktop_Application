import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/constants.dart';
import '../../../core/widgets/metric_card.dart';
import '../../../core/widgets/section_card.dart';
import '../../connection/domain/models.dart';
import '../../dashboard/widgets/stream_log_panel.dart';
import '../domain/esp32_bridge_models.dart';
import 'esp32_bridge_controller.dart';

class Esp32BridgePage extends StatefulWidget {
  const Esp32BridgePage({super.key});

  @override
  State<Esp32BridgePage> createState() => _Esp32BridgePageState();
}

class _Esp32BridgePageState extends State<Esp32BridgePage> {
  late final TextEditingController _ipController;
  late final TextEditingController _portController;

  @override
  void initState() {
    super.initState();
    final Esp32BridgeController controller = context
        .read<Esp32BridgeController>();
    _ipController = TextEditingController(text: controller.targetIp);
    _portController = TextEditingController(text: '${controller.targetPort}');
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Esp32BridgeController controller = context
        .watch<Esp32BridgeController>();
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Esp32BridgeSnapshot data = controller.snapshot;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool wide = constraints.maxWidth >= 980;
        final EdgeInsets padding = EdgeInsets.symmetric(
          horizontal: wide ? 24 : 12,
          vertical: 12,
        );

        final Widget controls = Column(
          children: <Widget>[
            SectionCard(
              title: 'ESP32-2 on office Wi-Fi',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Laptop must be on FDX-MUXTRONICS. This tab does not use 192.168.5.1.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _ipController,
                          enabled:
                              !controller.isBusy && !controller.isConnected,
                          decoration: const InputDecoration(
                            labelText: 'ESP32-2 IP',
                            hintText: Esp32BridgeDefaults.defaultIp,
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _portController,
                          enabled:
                              !controller.isBusy && !controller.isConnected,
                          decoration: const InputDecoration(
                            labelText: 'Port',
                            hintText: '9877',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      FilledButton.icon(
                        onPressed: controller.isBusy || controller.isConnected
                            ? null
                            : () => controller.connect(
                                ip: _ipController.text.trim(),
                                port: int.tryParse(_portController.text.trim()),
                              ),
                        icon: const Icon(Icons.link),
                        label: Text(
                          controller.linkState == LinkState.connecting
                              ? 'Connecting…'
                              : 'Connect',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: controller.isConnected
                            ? controller.disconnect
                            : null,
                        icon: const Icon(Icons.link_off),
                        label: const Text('Disconnect'),
                      ),
                      OutlinedButton.icon(
                        onPressed: controller.clearLogs,
                        icon: const Icon(Icons.clear_all),
                        label: const Text('Clear Logs'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    controller.statusMessage,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: 'Relay (ESP32-2 GPIO 27)',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Relay: IN = GPIO 27, VCC = 3V3 (not VIN), GND = GND. '
                    'Finger on GPIO 13 = ON, GPIO 14 = OFF. App buttons send RELAY ON / OFF.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  MetricCard(
                    label: 'Relay status',
                    value: data.relayState == null
                        ? 'Unknown'
                        : data.relaySource == null
                        ? data.relayState!
                        : '${data.relayState} (${data.relaySource})',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: controller.isConnected
                              ? controller.sendRelayOn
                              : null,
                          icon: const Icon(Icons.power_settings_new),
                          label: const Text('Relay ON'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: controller.isConnected
                              ? controller.sendRelayOff
                              : null,
                          icon: const Icon(Icons.power_off),
                          label: const Text('Relay OFF'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: 'Bridge readings',
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints inner) {
                  final int columns = inner.maxWidth >= 640
                      ? 3
                      : inner.maxWidth >= 420
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
                        label: 'Office Wi-Fi (ESP32-2)',
                        value: data.bridgeIp ?? _linkLabel(controller.linkState),
                      ),
                      MetricCard(
                        label: 'UART wire ESP32-1 → 2',
                        value: data.haveFdx || data.uartLive
                            ? 'LIVE (${data.uartLineCount} lines)'
                            : data.uartWaiting
                            ? 'Waiting'
                            : '—',
                      ),
                      MetricCard(
                        label: 'Dispenser Wi-Fi (ESP32-1)',
                        value: data.dispenserWifi ?? '—',
                      ),
                      MetricCard(
                        label: 'Dispenser TCP 9876',
                        value: data.dispenserSocket ?? '—',
                      ),
                      MetricCard(
                        label: 'Type-33 from pump',
                        value: data.haveFdx
                            ? 'Live FDX'
                            : (data.dispenserLive ?? '—'),
                      ),
                      MetricCard(
                        label: 'Current volume',
                        value: _number(data.volume, suffix: ' L'),
                      ),
                      MetricCard(
                        label: 'Total amount',
                        value: _number(data.amount),
                      ),
                      MetricCard(
                        label: 'Price per liter',
                        value: _number(data.rate),
                      ),
                      MetricCard(
                        label: 'Total meter',
                        value: _number(data.meter),
                      ),
                      MetricCard(
                        label: 'Pump status',
                        value: data.status ?? '—',
                      ),
                      MetricCard(
                        label: 'Product',
                        value: data.product ?? '—',
                      ),
                      MetricCard(label: 'Time', value: data.time ?? '—'),
                    ],
                  );
                },
              ),
            ),
            if (controller.isConnected &&
                data.uartLive &&
                !data.haveFdx) ...<Widget>[
              const SizedBox(height: 12),
              SectionCard(
                title: 'Why fuel numbers are empty',
                child: Text(
                  'ESP32-2 is on the office router (TCP 9877 works). UART from ESP32-1 is LIVE. '
                  'The log line "wifi offline" is ESP32-1, not ESP32-2. '
                  'ESP32-1 is not on FDX-57608F / 192.168.5.1:9876, so there is no Type-33 frame yet. '
                  'Keep ESP32-1 in range of the dispenser AP; amount and volume will fill when that socket comes up.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurface,
                  ),
                ),
              ),
            ],
          ],
        );

        final Widget log = StreamLogPanel(
          title: 'ESP32-2 text log',
          text: controller.logText,
          emptyHint:
              'Connect, then lines from ESP32-2 appear here. FDX,AMT:… means UART from ESP32-1 is working.',
          minHeight: wide ? 360 : 220,
        );

        if (wide) {
          return Padding(
            padding: padding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  flex: 5,
                  child: SingleChildScrollView(child: controls),
                ),
                const SizedBox(width: 12),
                Expanded(flex: 6, child: SingleChildScrollView(child: log)),
              ],
            ),
          );
        }

        return ListView(
          padding: padding,
          children: <Widget>[controls, const SizedBox(height: 12), log],
        );
      },
    );
  }

  String _linkLabel(LinkState state) {
    switch (state) {
      case LinkState.connected:
        return 'Connected';
      case LinkState.connecting:
        return 'Connecting';
      case LinkState.offline:
        return 'Offline';
      case LinkState.disconnected:
        return 'Not connected';
    }
  }

  String _number(double? value, {String suffix = ''}) {
    if (value == null) {
      return '—';
    }
    return '${value.toStringAsFixed(2)}$suffix';
  }
}
