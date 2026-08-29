import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/section_card.dart';
import '../../dashboard/dashboard_controller.dart';

class FlowControlButtons extends StatelessWidget {
  const FlowControlButtons({super.key});

  @override
  Widget build(BuildContext context) {
    final DashboardController controller = context.watch<DashboardController>();
    final bool enabled = controller.isConnected;
    final ColorScheme colors = Theme.of(context).colorScheme;

    return SectionCard(
      title: 'Remote flow',
      child: Row(
        children: <Widget>[
          Expanded(
            child: FilledButton.icon(
              onPressed: enabled
                  ? () {
                      if (controller.startFlow()) {
                        _toast(context, 'Flow Authorized');
                      }
                    }
                  : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start Flow'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                disabledBackgroundColor: colors.surfaceContainerHighest,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: enabled
                  ? () {
                      if (controller.stopFlow()) {
                        _toast(context, 'Flow Stop Requested');
                      }
                    }
                  : null,
              icon: const Icon(Icons.stop),
              label: const Text('Stop Flow'),
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
                disabledBackgroundColor: colors.surfaceContainerHighest,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
