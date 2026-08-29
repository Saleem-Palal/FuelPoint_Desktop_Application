import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/constants.dart';
import '../../../core/widgets/section_card.dart';
import '../../connection/domain/models.dart';
import '../dashboard_controller.dart';

class ConnectionPanel extends StatefulWidget {
  const ConnectionPanel({
    super.key,
    required this.ipController,
    required this.portController,
  });

  final TextEditingController ipController;
  final TextEditingController portController;

  @override
  State<ConnectionPanel> createState() => _ConnectionPanelState();
}

class _ConnectionPanelState extends State<ConnectionPanel> {
  @override
  Widget build(BuildContext context) {
    final DashboardController controller = context.watch<DashboardController>();
    final ColorScheme colors = Theme.of(context).colorScheme;

    return SectionCard(
      title: 'Connection',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                flex: 3,
                child: TextField(
                  controller: widget.ipController,
                  enabled: !controller.isBusy && !controller.isConnected,
                  decoration: const InputDecoration(
                    labelText: 'Board IP',
                    hintText: FdxDefaults.defaultIp,
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
                  controller: widget.portController,
                  enabled: !controller.isBusy && !controller.isConnected,
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    hintText: '9876',
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
                    : () => _connect(controller),
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
                onPressed: controller.isBusy || controller.isConnected
                    ? null
                    : () => _scan(controller),
                icon: controller.scanning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: Text(controller.scanning ? 'Scanning…' : 'Scan Ports'),
              ),
              OutlinedButton.icon(
                onPressed: controller.clearLogs,
                icon: const Icon(Icons.clear_all),
                label: const Text('Clear Logs'),
              ),
            ],
          ),
          if (controller.scanResults.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              'Open ports (tap one to use it)',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: controller.scanResults.map((PortScanResult result) {
                return ActionChip(
                  avatar: Icon(
                    result.open
                        ? Icons.check_circle
                        : result.error == 'pending'
                        ? Icons.hourglass_empty
                        : Icons.cancel,
                    size: 16,
                    color: result.open
                        ? colors.primary
                        : colors.onSurfaceVariant,
                  ),
                  label: Text('${result.port}'),
                  tooltip: result.label,
                  onPressed: result.open
                      ? () {
                          widget.portController.text = '${result.port}';
                          controller.selectPort(result.port);
                        }
                      : null,
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            controller.statusMessage,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          if (controller.lastError != null &&
              controller.lastError != controller.statusMessage) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              controller.lastError ?? '',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.error),
            ),
          ],
        ],
      ),
    );
  }

  void _sync(DashboardController controller) {
    controller.targetIp = widget.ipController.text.trim();
    controller.targetPort =
        int.tryParse(widget.portController.text.trim()) ??
        controller.targetPort;
  }

  void _connect(DashboardController controller) {
    _sync(controller);
    controller.connect(
      ip: widget.ipController.text.trim(),
      port: int.tryParse(widget.portController.text.trim()),
    );
  }

  void _scan(DashboardController controller) {
    _sync(controller);
    controller.scanPorts(ip: widget.ipController.text.trim());
  }
}
