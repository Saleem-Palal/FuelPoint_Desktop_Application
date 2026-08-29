import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/status_chip.dart';
import '../../connection/domain/models.dart';
import '../dashboard_controller.dart';

class NetworkStatusChip extends StatelessWidget {
  const NetworkStatusChip({super.key});

  @override
  Widget build(BuildContext context) {
    final DashboardController controller = context.watch<DashboardController>();
    final NetworkSnapshot network = controller.network;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final LinkState link = controller.linkState;

    final Color bg;
    final Color fg;
    final IconData icon;
    if (link == LinkState.connected) {
      bg = colors.primaryContainer;
      fg = colors.onPrimaryContainer;
      icon = Icons.cloud_done;
    } else if (network.offline || link == LinkState.offline) {
      bg = colors.errorContainer;
      fg = colors.onErrorContainer;
      icon = Icons.cloud_off;
    } else if (network.onDispenserAp) {
      bg = colors.tertiaryContainer;
      fg = colors.onTertiaryContainer;
      icon = Icons.router;
    } else {
      bg = colors.surfaceContainerHighest;
      fg = colors.onSurfaceVariant;
      icon = Icons.wifi;
    }

    return StatusChip(
      label: network.summary,
      background: bg,
      foreground: fg,
      icon: icon,
    );
  }
}
