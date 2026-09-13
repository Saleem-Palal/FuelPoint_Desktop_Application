import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/dispensr_theme.dart';
import '../../../features/shift/domain/shift_models.dart';
import '../../../features/station/domain/money_format.dart';
import '../../../features/station/domain/shift_ledger_models.dart';
import '../../../features/station/presentation/ledger_providers.dart';

/// Identity row for the shared sales table when Shift-Wise is selected.
class ShiftLedgerTableHeader extends StatelessWidget {
  const ShiftLedgerTableHeader({super.key, required this.summary});

  final ShiftLedgerSummary? summary;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final ShiftLedgerSummary? summary = this.summary;
    if (summary == null) {
      return Text(
        'Shift Ledger',
        style: TextStyle(
          fontFamily: 'Roboto',
          fontWeight: FontWeight.w700,
          fontSize: 14,
          color: tokens.ink,
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Text(
          summary.managerBadgeLabel,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: tokens.ink,
          ),
        ),
        DsStatusPill(
          label: summary.shiftId,
          foreground: tokens.coralPressed,
          background: tokens.coral.withValues(alpha: 0.12),
          border: tokens.coral.withValues(alpha: 0.35),
          dot: false,
        ),
        if (summary.isLive)
          DsStatusPill(
            label: 'LIVE',
            foreground: tokens.good,
            background: tokens.good.withValues(alpha: 0.14),
            border: tokens.good.withValues(alpha: 0.4),
          )
        else
          DsStatusPill(
            label: shiftStatusLabel(summary.status).toUpperCase(),
            foreground: tokens.inkMuted,
            background: tokens.inkMuted.withValues(alpha: 0.12),
            border: tokens.inkMuted.withValues(alpha: 0.35),
            dot: false,
          ),
        _MetaLine(label: 'Start', value: formatDateTime(summary.startTime)),
        _MetaLine(
          label: 'End',
          value: summary.isLive
              ? 'In progress'
              : (summary.endTime == null
                    ? '—'
                    : formatDateTime(summary.endTime!)),
        ),
      ],
    );
  }
}

class ShiftLedgerPager extends ConsumerWidget {
  const ShiftLedgerPager({super.key, required this.shifts});

  final List<ShiftLedgerSummary> shifts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    if (shifts.isEmpty) {
      return const SizedBox.shrink();
    }

    final String? selectedId = ref.watch(
      ledgerQueryProvider.select((LedgerQuery query) => query.selectedShiftId),
    );
    final int index = resolveShiftIndex(shifts, selectedId);
    final int safeIndex = index < 0 ? 0 : index;
    final bool canPrev = safeIndex > 0;
    final bool canNext = safeIndex < shifts.length - 1;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _PagerArrow(
          icon: Icons.chevron_left,
          enabled: canPrev,
          tooltip: 'Previous shift',
          onPressed: () {
            ref.read(ledgerQueryProvider.notifier).stepShift(-1, shifts);
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '${safeIndex + 1} of ${shifts.length}',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: tokens.inkMuted,
            ),
          ),
        ),
        _PagerArrow(
          icon: Icons.chevron_right,
          enabled: canNext,
          tooltip: 'Next shift',
          onPressed: () {
            ref.read(ledgerQueryProvider.notifier).stepShift(1, shifts);
          },
        ),
      ],
    );
  }
}

class _PagerArrow extends StatelessWidget {
  const _PagerArrow({
    required this.icon,
    required this.enabled,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final bool enabled;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: tokens.canvas,
        shape: CircleBorder(side: BorderSide(color: tokens.line)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onPressed : null,
          hoverColor: tokens.ink.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              icon,
              size: 20,
              color: enabled
                  ? tokens.ink
                  : tokens.inkMuted.withValues(alpha: 0.45),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          '$label  ',
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w700,
            fontSize: 10,
            letterSpacing: 0.6,
            color: tokens.inkMuted,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w500,
            fontSize: 12,
            color: tokens.ink,
          ),
        ),
      ],
    );
  }
}
