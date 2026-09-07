import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/dispensr_theme.dart';
import '../../../core/widgets/date_range_selector.dart';
import '../../../features/shift/domain/shift_models.dart';
import '../../../features/shift/presentation/shift_providers.dart';
import '../../../features/station/domain/money_format.dart';
import 'add_profile_dialogs.dart';
import 'shift_ui_kit.dart';

class HelperShiftsTab extends ConsumerWidget {
  const HelperShiftsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(width: 300, child: _HelperProfilePanel()),
        SizedBox(width: 10),
        Expanded(child: _HelperPerformancePanel()),
      ],
    );
  }
}

class _HelperProfilePanel extends ConsumerWidget {
  const _HelperProfilePanel();

  Future<void> _addHelper(BuildContext context, WidgetRef ref) async {
    try {
      final String? name = await showAddHelperDialog(context);
      if (name == null || !context.mounted) {
        return;
      }
      await ref.read(shiftWorkspaceProvider.notifier).addHelper(name: name);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$name added as helper')));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not add helper: $error')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final List<HelperProfile> helpers = ref.watch(helperRosterProvider);
    final String? selectedId = ref.watch(
      shiftWorkspaceProvider.select(
        (ShiftWorkspaceState s) => s.selectedHelperId,
      ),
    );

    return ShiftPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ShiftSectionHeader(
            title: 'Helpers',
            trailing: DsPillButton(
              label: '+ Add Helper',
              compact: true,
              onPressed: () {
                unawaited(_addHelper(context, ref));
              },
            ),
          ),
          Divider(color: tokens.line, height: 1),
          Expanded(
            child: helpers.isEmpty
                ? const ShiftEmptyHint(
                    message: 'No helpers yet. Add one to start.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                    itemCount: helpers.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (BuildContext context, int index) {
                      final HelperProfile helper = helpers[index];
                      return _HelperTile(
                        helper: helper,
                        selected: helper.id == selectedId,
                        onTap: () {
                          ref
                              .read(shiftWorkspaceProvider.notifier)
                              .selectHelper(helper.id);
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

class _HelperTile extends StatelessWidget {
  const _HelperTile({
    required this.helper,
    required this.selected,
    required this.onTap,
  });

  final HelperProfile helper;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final Color statusColor = switch (helper.status) {
      HelperDutyStatus.onDuty => tokens.good,
      HelperDutyStatus.offDuty => tokens.warn,
      HelperDutyStatus.inactive => tokens.inkMuted,
    };

    return Material(
      color: selected ? tokens.coral.withValues(alpha: 0.08) : tokens.canvas,
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
              color: selected
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
                  helper.initials,
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
                      helper.name,
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
                    DsStatusPill(
                      label: helperDutyLabel(helper),
                      foreground: statusColor,
                      background: statusColor.withValues(alpha: 0.12),
                      border: statusColor.withValues(alpha: 0.35),
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

class _HelperPerformancePanel extends ConsumerWidget {
  const _HelperPerformancePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final ShiftWorkspaceState workspace = ref.watch(shiftWorkspaceProvider);
    final AsyncValue<List<HelperSaleRecord>> salesAsync = ref.watch(
      helperFilteredSalesProvider,
    );
    final HelperPerformanceSnapshot slice = ref.watch(
      helperPerformanceProvider,
    );
    final HelperProfile? helper = workspace.selectedHelper;
    final String countLabel = slice.transactionCount == 1
        ? 'transaction'
        : 'transactions';
    final String emptyMessage;
    if (helper == null) {
      emptyMessage = 'Select a helper to see their sales.';
    } else if (salesAsync.hasError) {
      emptyMessage = 'Could not load helper sales from the database.';
    } else {
      emptyMessage = 'No sales in this date range.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _RangeFilterBar(
          preset: workspace.helperPreset,
          customRange: workspace.customRange,
          rewardRate: workspace.globalHelperRewardPerTx,
        ),
        const SizedBox(height: 10),
        _HelperKpiBar(slice: slice),
        const SizedBox(height: 10),
        Expanded(
          child: ShiftPanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ShiftSectionHeader(
                  title: helper == null
                      ? 'Filtered Sales Ledger'
                      : 'Sales · ${helper.name}',
                ),
                Divider(color: tokens.line, height: 1),
                Expanded(
                  child: salesAsync.isLoading && !salesAsync.hasValue
                      ? const Center(child: CircularProgressIndicator())
                      : slice.sales.isEmpty
                      ? ShiftEmptyHint(message: emptyMessage)
                      : ShiftSalesTable(rows: slice.sales),
                ),
                Divider(color: tokens.line, height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: Text(
                    '${slice.transactionCount} $countLabel',
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
          ),
        ),
      ],
    );
  }
}

class _RangeFilterBar extends ConsumerWidget {
  const _RangeFilterBar({
    required this.preset,
    required this.customRange,
    required this.rewardRate,
  });

  final HelperRangePreset preset;
  final DateTimeRange? customRange;
  final double rewardRate;

  Future<void> _openCustom(BuildContext context, WidgetRef ref) async {
    final DateRangeSelection? picked = await DateRangeSelector.show(
      context,
      initial: customRange ?? rangeForPreset(HelperRangePreset.today),
      title: 'Custom Range',
    );
    if (!context.mounted || picked == null) {
      return;
    }
    final DateTimeRange? range = picked.value;
    if (range == null) {
      ref
          .read(shiftWorkspaceProvider.notifier)
          .setHelperPreset(HelperRangePreset.today);
      return;
    }
    ref.read(shiftWorkspaceProvider.notifier).setCustomRange(range);
  }

  Future<void> _editRate(BuildContext context, WidgetRef ref) async {
    try {
      final double? next = await showEditRewardRateDialog(
        context,
        currentRate: rewardRate,
      );
      if (next == null || !context.mounted) {
        return;
      }
      ref
          .read(shiftWorkspaceProvider.notifier)
          .setGlobalHelperRewardPerTx(next);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not update rate: $error')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return ShiftPanelCard(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                _RangeChip(
                  label: 'Today',
                  selected: preset == HelperRangePreset.today,
                  onTap: () {
                    ref
                        .read(shiftWorkspaceProvider.notifier)
                        .setHelperPreset(HelperRangePreset.today);
                  },
                ),
                _RangeChip(
                  label: 'This Month',
                  selected: preset == HelperRangePreset.thisMonth,
                  onTap: () {
                    ref
                        .read(shiftWorkspaceProvider.notifier)
                        .setHelperPreset(HelperRangePreset.thisMonth);
                  },
                ),
                _RangeChip(
                  label: customRange == null
                      ? 'Custom Range'
                      : formatDateRangeLabel(
                          customRange!.start,
                          customRange!.end,
                        ),
                  selected: preset == HelperRangePreset.custom,
                  onTap: () {
                    unawaited(_openCustom(context, ref));
                  },
                ),
              ],
            ),
          ),
          _RewardRateChip(
            rate: rewardRate,
            onEdit: () {
              unawaited(_editRate(context, ref));
            },
          ),
        ],
      ),
    );
  }
}

class _RewardRateChip extends StatelessWidget {
  const _RewardRateChip({required this.rate, required this.onEdit});

  final double rate;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Material(
      color: tokens.coral.withValues(alpha: 0.10),
      shape: StadiumBorder(
        side: BorderSide(color: tokens.coral.withValues(alpha: 0.45)),
      ),
      child: InkWell(
        onTap: onEdit,
        customBorder: const StadiumBorder(),
        hoverColor: tokens.ink.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'Global Reward Rate: ${formatPkr(rate)} / Tx',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: tokens.coralPressed,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.edit_outlined, size: 14, color: tokens.coralPressed),
            ],
          ),
        ),
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({
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
      color: selected ? tokens.coral.withValues(alpha: 0.14) : tokens.canvas,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? tokens.coral : tokens.line),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        hoverColor: tokens.ink.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: selected ? tokens.coralPressed : tokens.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _HelperKpiBar extends StatelessWidget {
  const _HelperKpiBar({required this.slice});

  final HelperPerformanceSnapshot slice;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final String attendanceHint;
    if (slice.firstSaleAt == null) {
      attendanceHint = 'No sales in range';
    } else if (slice.lastSaleAt == null ||
        slice.lastSaleAt == slice.firstSaleAt) {
      attendanceHint = 'First sale ${formatClock(slice.firstSaleAt!)}';
    } else {
      attendanceHint =
          '${formatClock(slice.firstSaleAt!)} → ${formatClock(slice.lastSaleAt!)}';
    }

    return Row(
      children: <Widget>[
        Expanded(
          child: ShiftKpiCard(
            label: 'Total Transactions',
            value: '${slice.transactionCount}',
            hint: 'Completed sales',
            icon: Icons.receipt_long_outlined,
            tint: tokens.coral,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ShiftKpiCard(
            label: 'Total Liters Dispensed',
            value: formatLiters(slice.totalLiters),
            hint: 'Volume in range',
            icon: Icons.water_drop_outlined,
            tint: tokens.good,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ShiftKpiCard(
            label: 'Total Reward Payout',
            value: formatPkr(slice.rewardPayout),
            hint: '${formatPkr(slice.rewardRate)} × ${slice.transactionCount}',
            icon: Icons.card_giftcard_outlined,
            tint: tokens.warn,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ShiftKpiCard(
            label: 'Duty Hours & Attendance',
            value: slice.firstSaleAt == null
                ? '—'
                : formatShiftDuration(
                    (slice.lastSaleAt ?? slice.firstSaleAt!).difference(
                      slice.firstSaleAt!,
                    ),
                  ),
            hint: attendanceHint,
            icon: Icons.schedule_outlined,
            tint: tokens.inkMuted,
          ),
        ),
      ],
    );
  }
}
