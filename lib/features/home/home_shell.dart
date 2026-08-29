import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/widgets/status_chip.dart';
import '../dashboard/dashboard_page.dart';
import '../dashboard/widgets/network_status_chip.dart';
import '../esp32_bridge/presentation/esp32_bridge_controller.dart';
import '../esp32_bridge/presentation/esp32_bridge_page.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(AppBrand.name),
          actions: const <Widget>[
            Padding(
              padding: EdgeInsets.only(right: 8),
              child: Center(child: NetworkStatusChip()),
            ),
            Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(child: _Esp32BridgeChip()),
            ),
          ],
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(icon: Icon(Icons.local_gas_station), text: 'FDX dispenser'),
              Tab(icon: Icon(Icons.cell_tower), text: 'ESP32-2 bridge'),
            ],
          ),
        ),
        body: const TabBarView(
          children: <Widget>[DashboardPage(), Esp32BridgePage()],
        ),
      ),
    );
  }
}

class _Esp32BridgeChip extends StatelessWidget {
  const _Esp32BridgeChip();

  @override
  Widget build(BuildContext context) {
    final Esp32BridgeController controller = context
        .watch<Esp32BridgeController>();
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool live =
        controller.isConnected &&
        (controller.snapshot.haveFdx || controller.snapshot.uartLive);

    final Color bg;
    final Color fg;
    final IconData icon;
    final String label;
    if (live) {
      bg = colors.primaryContainer;
      fg = colors.onPrimaryContainer;
      icon = Icons.sensors;
      label = 'ESP32-2 FDX live';
    } else if (controller.isConnected) {
      bg = colors.tertiaryContainer;
      fg = colors.onTertiaryContainer;
      icon = Icons.cell_tower;
      label = 'ESP32-2 TCP';
    } else if (controller.isBusy) {
      bg = colors.surfaceContainerHighest;
      fg = colors.onSurfaceVariant;
      icon = Icons.hourglass_empty;
      label = 'ESP32-2…';
    } else {
      bg = colors.surfaceContainerHighest;
      fg = colors.onSurfaceVariant;
      icon = Icons.cell_tower;
      label = 'ESP32-2';
    }

    return StatusChip(label: label, background: bg, foreground: fg, icon: icon);
  }
}
