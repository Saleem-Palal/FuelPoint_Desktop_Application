import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../Shell/shell_navigation.dart';
import '../../../core/theme/dispensr_theme.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../../../features/access/domain/access_policy.dart';
import '../../../features/access/presentation/access_controller.dart';
import '../../../features/access/presentation/owner_access_gate.dart';
import '../../../features/access/domain/operator_credential.dart';
import '../../../features/shift/domain/shift_lifecycle.dart';
import '../../../features/shift/domain/shift_models.dart';
import '../../../features/shift/presentation/shift_hardware.dart';
import '../../../features/shift/presentation/shift_providers.dart';
import '../../../features/station/domain/money_format.dart';
import 'add_profile_dialogs.dart';
import 'active_shift_banner.dart';
import 'shift_close_actions.dart';
import 'shift_close_warning_dialog.dart';
import 'shift_handover_dialog.dart';
import 'start_shift_dialog.dart';
import 'shift_ui_kit.dart';

class OperatorShiftsTab extends ConsumerWidget {
  const OperatorShiftsTab({super.key});

  Future<void> _endShift(BuildContext context, WidgetRef ref) async {
    final ShiftWorkspaceState workspace = ref.read(shiftWorkspaceProvider);
    if (!workspace.canEndShift) {
      if (workspace.hasUnconfirmedAccount && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ShiftLifecycleGuard.pendingAccountBlockedMessage()),
            backgroundColor: DispensrTokens.of(context).warn,
          ),
        );
      } else if (workspace.pendingReconciliation != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Finish the pending cash tally before starting another handoff.',
            ),
          ),
        );
      }
      return;
    }
    final OperatorShiftRecord? shift = workspace.activeShift;
    if (shift == null) {
      return;
    }
    if (workspace.hasUnconfirmedAccount) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ShiftLifecycleGuard.pendingAccountBlockedMessage()),
            backgroundColor: DispensrTokens.of(context).warn,
          ),
        );
      }
      return;
    }
    final int? blockingUnit = shouldEnforceStationGuards
        ? dispensingUnitIdOf(ref)
        : null;
    if (blockingUnit != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ShiftLifecycleGuard.handoverBlockedMessage(blockingUnit),
            ),
            backgroundColor: DispensrTokens.of(context).warn,
          ),
        );
      }
      return;
    }
    final OperatorCredential? outgoing = await showOperatorPinDialog(
      context,
      operatorId: shift.operatorId,
      operatorName: shift.operatorName,
      title: 'End Shift & Handover',
      message:
          'Confirm ${shift.operatorName} to freeze ${shift.shiftId} for '
          'cash tally, then authenticate the incoming operator.',
    );
    if (outgoing == null || !context.mounted) {
      return;
    }
    final bool outgoingOk =
        outgoing.fingerprintVerified ||
        await ref
            .read(shiftWorkspaceProvider.notifier)
            .verifyActiveOperatorPin(outgoing.pin);
    if (!outgoingOk) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PIN does not match the on-duty operator.'),
          ),
        );
      }
      return;
    }
    try {
      final ShiftHandoverResult? result = await showIncomingOperatorAuthDialog(
        context,
        outgoingShift: shift,
        incomingOperators: workspace.incomingHandoverCandidates,
        helpers: workspace.assignableHelpers,
        currentAssignments: unitHelperAssignmentsOf(workspace.helpers),
        onConfirm:
            ({
              required String incomingOperatorId,
              required String pin,
              bool fingerprintVerified = false,
              required Map<int, String?> unitAssignments,
            }) {
              return ref
                  .read(shiftWorkspaceProvider.notifier)
                  .beginHandover(
                    incomingOperatorId: incomingOperatorId,
                    pin: pin,
                    fingerprintVerified: fingerprintVerified,
                    unitAssignments: unitAssignments,
                    blockingDispensingUnit: shouldEnforceStationGuards
                        ? dispensingUnitIdOf(ref)
                        : null,
                    closingMeters: currentUnitMetersOf(ref),
                    openingMeters: currentUnitMetersOf(ref),
                  );
            },
      );
      if (result == null || !context.mounted) {
        return;
      }
      if (result.outcome == HandoverOutcome.unitsDispensing &&
          context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ShiftLifecycleGuard.handoverBlockedMessage(
                result.blockedUnitId ?? 0,
              ),
            ),
          ),
        );
        return;
      }
      if (result.outcome == HandoverOutcome.pendingAccount && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ShiftLifecycleGuard.pendingAccountBlockedMessage()),
            backgroundColor: DispensrTokens.of(context).warn,
          ),
        );
        return;
      }
      final OperatorShiftRecord? opened = result.opened;
      if (result.isSuccess && opened != null) {
        ref.read(accessControllerProvider.notifier).lockOwnerAccess();
        ref.read(shellDestinationProvider.notifier).state =
            ShellDestinations.shifts;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${shift.shiftId} is pending tally. ${opened.operatorName} is '
              'live on ${opened.shiftId}. Enter counted cash in the sidebar.',
            ),
          ),
        );
      }
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start shift handoff: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ShiftWorkspaceState workspace = ref.watch(shiftWorkspaceProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ActiveShiftBanner(
          shift: workspace.activeShift,
          expectedCash: workspace.activeMetrics.expectedCashInHand,
          onManualEndShift: workspace.canEndShift
              ? () {
                  unawaited(promptManualEndShift(context, ref));
                }
              : null,
          onEndShift: workspace.canEndShift
              ? () {
                  unawaited(_endShift(context, ref));
                }
              : null,
        ),
        const SizedBox(height: 10),
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool stacked = constraints.maxWidth < 900;
              const Widget operators = _OperatorProfilePanel();
              const Widget tally = ShiftTallySidebar();
              if (stacked) {
                return ScrollableConstrainedBody(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const SizedBox(height: 280, child: operators),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: constraints.maxHeight > 420
                            ? constraints.maxHeight
                            : 420,
                        child: tally,
                      ),
                    ],
                  ),
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(
                    width: constraints.maxWidth < 1100 ? 260 : 300,
                    child: operators,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(child: tally),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _OperatorProfilePanel extends ConsumerWidget {
  const _OperatorProfilePanel();

  Future<void> _addOperator(BuildContext context, WidgetRef ref) async {
    try {
      final AddOperatorResult? result = await showAddOperatorDialog(context);
      if (result == null || !context.mounted) {
        return;
      }
      await ref
          .read(shiftWorkspaceProvider.notifier)
          .addOperator(name: result.name, role: result.role, pin: result.pin);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result.name} added as ${operatorRoleLabel(result.role)}',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not add operator: $error')));
    }
  }

  Future<void> _onOperatorTap(
    BuildContext context,
    WidgetRef ref,
    OperatorProfile operator,
  ) async {
    final OperatorShiftRecord? open = ref
        .read(shiftWorkspaceProvider)
        .activeShift;
    if (open != null) {
      if (open.operatorId == operator.id) {
        return;
      }
      if (!context.mounted) {
        return;
      }
      await _showBlockedDialog(context, open);
      return;
    }

    final ShiftWorkspaceState workspace = ref.read(shiftWorkspaceProvider);
    final StartShiftOutcome? outcome = await showStartShiftDialog(
      context,
      operator: operator,
      helpers: workspace.assignableHelpers,
      currentAssignments: unitHelperAssignmentsOf(workspace.helpers),
      onConfirm:
          ({
            required String pin,
            bool fingerprintVerified = false,
            required Map<int, String?> unitAssignments,
          }) {
            return ref
                .read(shiftWorkspaceProvider.notifier)
                .startShift(
                  operator.id,
                  pin: pin,
                  fingerprintVerified: fingerprintVerified,
                  unitAssignments: unitAssignments,
                  openingMeters: currentUnitMetersOf(ref),
                );
          },
    );
    if (outcome == null || !context.mounted) {
      return;
    }
    switch (outcome) {
      case StartShiftOutcome.started:
        ref.read(shellDestinationProvider.notifier).state =
            ShellDestinations.sale;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${operator.name} is now on shift')),
        );
      case StartShiftOutcome.alreadyOnDuty:
        return;
      case StartShiftOutcome.invalidPin:
        return;
      case StartShiftOutcome.blocked:
        final OperatorShiftRecord? stillOpen = ref
            .read(shiftWorkspaceProvider)
            .activeShift;
        if (!context.mounted || stillOpen == null) {
          return;
        }
        await _showBlockedDialog(context, stillOpen);
    }
  }

  Future<void> _showBlockedDialog(
    BuildContext context,
    OperatorShiftRecord open,
  ) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: tokens.card,
          surfaceTintColor: tokens.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radius20),
            side: BorderSide(color: tokens.line),
          ),
          title: Text(
            'Close the open shift first',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: tokens.ink,
            ),
          ),
          content: Text(
            '${open.operatorName} is already on ${open.shiftId}. '
            'End that shift and reconcile before starting another operator.',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 13,
              height: 1.4,
              color: tokens.inkMuted,
            ),
          ),
          actions: <Widget>[
            DsPillButton(
              label: 'Understood',
              compact: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final List<OperatorProfile> operators = ref.watch(
      shiftWorkspaceProvider.select((ShiftWorkspaceState s) => s.operators),
    );
    final String? activeOperatorId = ref.watch(
      shiftWorkspaceProvider.select(
        (ShiftWorkspaceState s) => s.activeShift?.operatorId,
      ),
    );

    return ShiftPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ShiftSectionHeader(
            title: 'Operators',
            trailing: DsPillButton(
              label: '+ Add Operator',
              compact: true,
              onPressed: () {
                unawaited(_addOperator(context, ref));
              },
            ),
          ),
          Divider(color: tokens.line, height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              itemCount: operators.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (BuildContext context, int index) {
                final OperatorProfile operator = operators[index];
                return _OperatorTile(
                  operator: operator,
                  onShift: operator.id == activeOperatorId,
                  onTap: () {
                    unawaited(_onOperatorTap(context, ref, operator));
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OperatorTile extends StatelessWidget {
  const _OperatorTile({
    required this.operator,
    required this.onShift,
    required this.onTap,
  });

  final OperatorProfile operator;
  final bool onShift;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final bool profileActive = onShift;
    return Material(
      color: onShift ? tokens.coral.withValues(alpha: 0.08) : tokens.canvas,
      borderRadius: BorderRadius.circular(tokens.radius12),
      child: InkWell(
        onTap: onTap,
        hoverColor: tokens.ink.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(tokens.radius12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(tokens.radius12),
            border: Border.all(
              color: onShift
                  ? tokens.coral.withValues(alpha: 0.45)
                  : tokens.line,
            ),
          ),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 16,
                backgroundColor: tokens.line,
                child: Text(
                  operator.initials,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    color: tokens.inkMuted,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      operator.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: tokens.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: <Widget>[
                        DsStatusPill(
                          label: operatorRoleLabel(operator.role),
                          foreground: tokens.coralPressed,
                          background: tokens.coral.withValues(alpha: 0.12),
                          border: tokens.coral.withValues(alpha: 0.35),
                          dot: false,
                        ),
                        DsStatusPill(
                          label: profileActive ? 'On Shift' : 'Idle',
                          foreground: profileActive
                              ? tokens.good
                              : tokens.inkMuted,
                          background:
                              (profileActive ? tokens.good : tokens.inkMuted)
                                  .withValues(alpha: 0.12),
                          border:
                              (profileActive ? tokens.good : tokens.inkMuted)
                                  .withValues(alpha: 0.35),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cash tally / historical shift figures. Locked until owner elevation.
class ShiftTallySidebar extends ConsumerWidget {
  const ShiftTallySidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ShiftWorkspaceState workspace = ref.watch(shiftWorkspaceProvider);
    if (workspace.pendingReconciliation != null) {
      return const _ShiftHandoverPanel();
    }
    final bool elevated = ref.watch(accessControllerProvider).isOwnerElevated;
    if (!elevated) {
      return const OwnerLockedTallyPanel();
    }
    return const _ShiftHandoverPanel();
  }
}

class _ShiftHandoverPanel extends ConsumerWidget {
  const _ShiftHandoverPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ShiftWorkspaceState workspace = ref.watch(shiftWorkspaceProvider);
    final ShiftWindowMetrics liveMetrics = ref.watch(
      activeShiftMetricsProvider,
    );
    final ReconciliationSnapshot? pending = workspace.pendingReconciliation;
    final OperatorShiftRecord? displayShift =
        pending?.shift ?? workspace.activeShift;
    final ShiftWindowMetrics displayMetrics = pending?.metrics ?? liveMetrics;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * 0.68,
              ),
              child: SingleChildScrollView(
                child: _ActiveShiftCard(
                  shift: displayShift,
                  metrics: displayMetrics,
                  pendingTally: pending != null,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: workspace.tallyPane == OperatorTallyPane.todaySales
                  ? _TodaySalesCard(
                      metrics: displayMetrics,
                      hasShift: displayShift != null,
                    )
                  : _HistoricalShiftsCard(rows: workspace.closedShifts),
            ),
          ],
        );
      },
    );
  }
}

class _ActiveShiftCard extends ConsumerWidget {
  const _ActiveShiftCard({
    required this.shift,
    required this.metrics,
    this.pendingTally = false,
  });

  final OperatorShiftRecord? shift;
  final ShiftWindowMetrics metrics;
  final bool pendingTally;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final OperatorShiftRecord? open = shift;
    final OperatorTallyPane pane = ref.watch(
      shiftWorkspaceProvider.select((ShiftWorkspaceState s) => s.tallyPane),
    );

    return ShiftPanelCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (open == null)
            Text(
              'No open shift — tap an operator to start. Expected cash is fuel cash + cash udhaar recovery (account recoveries stay off the drawer).',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w500,
                fontSize: 13,
                color: tokens.inkMuted,
              ),
            )
          else ...<Widget>[
            Row(
              children: <Widget>[
                Flexible(
                  child: Text(
                    pendingTally ? 'Pending tally' : 'Active Shift',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: tokens.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: DsStatusPill(
                    label: open.shiftId,
                    foreground: tokens.coralPressed,
                    background: tokens.coral.withValues(alpha: 0.12),
                    border: tokens.coral.withValues(alpha: 0.35),
                    dot: false,
                  ),
                ),
                const SizedBox(width: 8),
                DsStatusPill(
                  label: pendingTally ? 'Pending' : 'Open',
                  foreground: pendingTally ? tokens.warn : tokens.good,
                  background: (pendingTally ? tokens.warn : tokens.good)
                      .withValues(alpha: 0.12),
                  border: (pendingTally ? tokens.warn : tokens.good).withValues(
                    alpha: 0.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: ShiftKpiCard(
                    label: 'Operator',
                    value: open.operatorName,
                    hint: operatorRoleLabel(open.role),
                    icon: Icons.person_outline,
                    tint: tokens.coral,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ShiftKpiCard(
                    label: 'Total Sale',
                    value: formatPkr(metrics.totalSale),
                    hint: ShiftWindowMetrics.totalSaleFormula,
                    icon: Icons.local_gas_station_outlined,
                    tint: tokens.good,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: ShiftKpiCard(
                    label: 'Udhaar Issued',
                    value: formatPkr(metrics.udhaarSales),
                    hint: ShiftWindowMetrics.udhaarIssuedHint,
                    icon: Icons.receipt_long_outlined,
                    tint: tokens.warn,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ShiftKpiCard(
                    label: 'Account Payments',
                    value: formatPkr(metrics.accountSales),
                    hint: ShiftWindowMetrics.accountPaymentsHint,
                    icon: Icons.account_balance_outlined,
                    tint: tokens.coral,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(child: ShiftUdhaarRecoveryCard(metrics: metrics)),
                const SizedBox(width: 8),
                Expanded(
                  child: ShiftKpiCard(
                    label: 'Expected Cash in Hand',
                    value: formatPkr(metrics.expectedCashInHand),
                    hint: ShiftWindowMetrics.expectedCashFormula,
                    icon: Icons.payments_outlined,
                    tint: tokens.warn,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          _TallyPaneToggle(
            pane: pane,
            onChanged: (OperatorTallyPane next) {
              ref.read(shiftWorkspaceProvider.notifier).setTallyPane(next);
            },
          ),
        ],
      ),
    );
  }
}

class _TallyPaneToggle extends StatelessWidget {
  const _TallyPaneToggle({required this.pane, required this.onChanged});

  final OperatorTallyPane pane;
  final ValueChanged<OperatorTallyPane> onChanged;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: tokens.canvas,
        borderRadius: BorderRadius.circular(tokens.radius12),
        border: Border.all(color: tokens.line),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _PaneChip(
              label: "Today's Sales Transactions",
              selected: pane == OperatorTallyPane.todaySales,
              onTap: () => onChanged(OperatorTallyPane.todaySales),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _PaneChip(
              label: 'Historical Shift Logs',
              selected: pane == OperatorTallyPane.historical,
              onTap: () => onChanged(OperatorTallyPane.historical),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaneChip extends StatelessWidget {
  const _PaneChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Material(
      color: selected
          ? tokens.coral.withValues(alpha: 0.14)
          : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: selected ? tokens.coral : Colors.transparent),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        hoverColor: tokens.ink.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: selected ? tokens.coralPressed : tokens.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _TodaySalesCard extends StatelessWidget {
  const _TodaySalesCard({required this.metrics, required this.hasShift});

  final ShiftWindowMetrics metrics;
  final bool hasShift;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final String empty = hasShift
        ? 'No fuel sales on this open shift yet.'
        : 'Start a operator shift to load today’s transactions.';
    return ShiftPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const ShiftSectionHeader(title: "Today's Sales Transactions"),
          Divider(color: tokens.line, height: 1),
          Expanded(
            child: metrics.sales.isEmpty
                ? ShiftEmptyHint(message: empty)
                : ShiftSalesTable(rows: metrics.sales),
          ),
          Divider(color: tokens.line, height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Text(
              '${metrics.commercialSaleCount} ${metrics.commercialSaleCount == 1 ? 'transaction' : 'transactions'}',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w500,
                fontSize: 12,
                color: tokens.inkMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoricalShiftsCard extends StatelessWidget {
  const _HistoricalShiftsCard({required this.rows});

  final List<OperatorShiftRecord> rows;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return ShiftPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const ShiftSectionHeader(title: 'Historical Shift Logs'),
          Divider(color: tokens.line, height: 1),
          Expanded(
            child: rows.isEmpty
                ? const ShiftEmptyHint(message: 'No closed shifts yet.')
                : _HistoricalShiftTable(rows: rows),
          ),
          Divider(color: tokens.line, height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Text(
              '${rows.length} closed shifts',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w500,
                fontSize: 12,
                color: tokens.inkMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoricalShiftTable extends StatelessWidget {
  const _HistoricalShiftTable({required this.rows});

  final List<OperatorShiftRecord> rows;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double minWidth = constraints.maxWidth < 1180
            ? 1180
            : constraints.maxWidth;
        return ShiftTwoAxisScroll(
          minWidth: minWidth,
          child: DataTable(
            headingRowHeight: 32,
            dataRowMinHeight: 44,
            dataRowMaxHeight: 52,
            horizontalMargin: 14,
            columnSpacing: 14,
            headingTextStyle: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w700,
              fontSize: 10,
              letterSpacing: 0.9,
              color: tokens.inkMuted,
            ),
            dataTextStyle: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w500,
              fontSize: 12,
              color: tokens.ink,
            ),
            columns: const <DataColumn>[
              DataColumn(label: Text('SHIFT ID')),
              DataColumn(label: Text('OPERATOR')),
              DataColumn(label: Text('ROLE')),
              DataColumn(label: Text('START TIME')),
              DataColumn(label: Text('END TIME')),
              DataColumn(label: Text('EXPECTED CASH'), numeric: true),
              DataColumn(label: Text('ACTUAL CASH'), numeric: true),
              DataColumn(label: Text('DISCREPANCY'), numeric: true),
              DataColumn(label: Text('STATUS')),
            ],
            rows: <DataRow>[
              for (final OperatorShiftRecord row in rows)
                DataRow(
                  cells: <DataCell>[
                    DataCell(
                      Text(
                        row.shiftId,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: tokens.coralPressed,
                        ),
                      ),
                    ),
                    DataCell(Text(row.operatorName)),
                    DataCell(Text(operatorRoleLabel(row.role))),
                    DataCell(
                      Text(
                        formatDateTime(row.startTime),
                        style: TextStyle(color: tokens.inkMuted),
                      ),
                    ),
                    DataCell(
                      Text(
                        row.endTime == null
                            ? '—'
                            : formatDateTime(row.endTime!),
                        style: TextStyle(color: tokens.inkMuted),
                      ),
                    ),
                    DataCell(
                      Text(
                        formatTablePkr(row.expectedCash),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    DataCell(
                      Text(
                        row.actualCash == null
                            ? '—'
                            : formatTablePkr(row.actualCash!),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    DataCell(_DiscrepancyCell(value: row.discrepancy)),
                    DataCell(
                      DsStatusPill(
                        label: shiftStatusLabel(row.status),
                        foreground: tokens.inkMuted,
                        background: tokens.line.withValues(alpha: 0.55),
                        border: tokens.line,
                        dot: false,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DiscrepancyCell extends StatelessWidget {
  const _DiscrepancyCell({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final Color color = value < 0
        ? tokens.bad
        : value > 0
        ? tokens.good
        : tokens.ink;
    return Text(
      formatTableSignedPkr(value),
      style: TextStyle(fontWeight: FontWeight.w700, color: color),
    );
  }
}
