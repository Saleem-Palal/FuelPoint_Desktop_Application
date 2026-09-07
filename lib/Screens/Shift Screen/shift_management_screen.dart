import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/dispensr_theme.dart';
import '../../core/widgets/app_screen_header.dart';
import '../../features/shift/domain/shift_models.dart';
import '../../features/shift/presentation/shift_providers.dart';
import '../../features/station/presentation/workspace_refresh.dart';
import 'Widgets/helper_shifts_tab.dart';
import 'Widgets/manager_shifts_tab.dart';

class ShiftManagementScreen extends ConsumerStatefulWidget {
  const ShiftManagementScreen({super.key});

  @override
  ConsumerState<ShiftManagementScreen> createState() =>
      _ShiftManagementScreenState();
}

class _ShiftManagementScreenState extends ConsumerState<ShiftManagementScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(refreshShiftsFromDatabase(ref));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final ShiftWorkspaceState workspace = ref.watch(shiftWorkspaceProvider);

    return ColoredBox(
      color: tokens.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: AppScreenHeader(
              title: 'Shift Management',
              icon: Icons.badge_outlined,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: _ShiftTabToggle(
              tab: workspace.tab,
              onChanged: (ShiftWorkspaceTab tab) {
                ref.read(shiftWorkspaceProvider.notifier).setTab(tab);
              },
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: workspace.tab == ShiftWorkspaceTab.managers
                  ? const ManagerShiftsTab()
                  : const HelperShiftsTab(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShiftTabToggle extends StatelessWidget {
  const _ShiftTabToggle({required this.tab, required this.onChanged});

  final ShiftWorkspaceTab tab;
  final ValueChanged<ShiftWorkspaceTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.radius20),
        border: Border.all(color: tokens.line),
        boxShadow: tokens.cardShadow,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _TabChip(
              label: 'Manager Shifts & Cash Tally',
              icon: Icons.account_balance_wallet_outlined,
              selected: tab == ShiftWorkspaceTab.managers,
              onTap: () => onChanged(ShiftWorkspaceTab.managers),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _TabChip(
              label: 'Helper Shifts & Performance',
              icon: Icons.engineering_outlined,
              selected: tab == ShiftWorkspaceTab.helpers,
              onTap: () => onChanged(ShiftWorkspaceTab.helpers),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final Color fg = selected ? tokens.coralPressed : tokens.inkMuted;
    final Color bg = selected
        ? tokens.coral.withValues(alpha: 0.14)
        : Colors.transparent;
    final Color border = selected ? tokens.coral : Colors.transparent;

    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius12),
        side: BorderSide(color: border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radius12),
        hoverColor: tokens.ink.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
