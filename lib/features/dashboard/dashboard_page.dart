import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'dashboard_controller.dart';
import 'widgets/connection_panel.dart';
import 'widgets/send_panel.dart';
import 'widgets/stream_log_panel.dart';
import '../telemetry/components/flow_control_buttons.dart';
import '../telemetry/widgets/telemetry_panel.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late final TextEditingController _ipController;
  late final TextEditingController _portController;

  @override
  void initState() {
    super.initState();
    final DashboardController controller = context.read<DashboardController>();
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
    final DashboardController controller = context.watch<DashboardController>();

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
          if (controller.isConnected || controller.isBusy) {
            return;
          }
          controller.connect(
            ip: _ipController.text.trim(),
            port: int.tryParse(_portController.text.trim()),
          );
        },
        const SingleActivator(LogicalKeyboardKey.keyD, control: true): () {
          if (controller.isConnected) {
            controller.disconnect();
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
          if (!controller.isBusy && !controller.isConnected) {
            controller.scanPorts(ip: _ipController.text.trim());
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyL, control: true):
            controller.clearLogs,
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool wide = constraints.maxWidth >= 980;
            final EdgeInsets padding = EdgeInsets.symmetric(
              horizontal: wide ? 24 : 12,
              vertical: 12,
            );

            final Widget controls = Column(
              children: <Widget>[
                ConnectionPanel(
                  ipController: _ipController,
                  portController: _portController,
                ),
                const SizedBox(height: 12),
                const TelemetryPanel(),
                const SizedBox(height: 12),
                const FlowControlButtons(),
                const SizedBox(height: 12),
                const SendPanel(),
              ],
            );

            final Widget logs = Column(
              children: <Widget>[
                StreamLogPanel(
                  title: 'Hex log',
                  text: controller.hexLogText,
                  emptyHint: 'Raw bytes will show here after you connect.',
                  minHeight: wide ? 220 : 160,
                ),
                const SizedBox(height: 12),
                StreamLogPanel(
                  title: 'Text log',
                  text: controller.asciiLogText,
                  emptyHint: 'Readable text from the board will show here.',
                  minHeight: wide ? 220 : 160,
                ),
              ],
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
                    Expanded(
                      flex: 6,
                      child: SingleChildScrollView(child: logs),
                    ),
                  ],
                ),
              );
            }

            return ListView(
              padding: padding,
              children: <Widget>[
                controls,
                const SizedBox(height: 12),
                logs,
                const SizedBox(height: 12),
                Text(
                  'Shortcuts: Ctrl+K scan · Ctrl+Enter connect · Ctrl+D disconnect · Ctrl+L clear',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
