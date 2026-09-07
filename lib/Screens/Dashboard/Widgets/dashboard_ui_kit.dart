import 'package:flutter/material.dart';

import '../../../core/theme/dispensr_theme.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../../../features/station/domain/dashboard_models.dart';
import '../../../features/station/domain/money_format.dart';

class DashboardPanel extends StatelessWidget {
  const DashboardPanel({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.radius20),
        border: Border.all(color: tokens.line),
        boxShadow: tokens.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
  }
}

class DashboardSectionTitle extends StatelessWidget {
  const DashboardSectionTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final String? subtitleText = subtitle?.trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: tokens.ink,
                ),
              ),
              if (subtitleText != null && subtitleText.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitleText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w500,
                      fontSize: 11,
                      color: tokens.inkMuted,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (trailing != null)
          Flexible(
            child: Align(alignment: Alignment.centerRight, child: trailing),
          ),
      ],
    );
  }
}

class DashboardRangeChips extends StatelessWidget {
  const DashboardRangeChips({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final DashboardRangePreset value;
  final ValueChanged<DashboardRangePreset> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (final DashboardRangePreset preset in DashboardRangePreset.values)
          _RangeChip(
            label: preset.chipLabel,
            selected: value == preset,
            onTap: () => onChanged(preset),
          ),
      ],
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

class DashboardVolumeCard extends StatelessWidget {
  const DashboardVolumeCard({
    super.key,
    required this.title,
    required this.volumeLiters,
    required this.revenuePkr,
    required this.txnCount,
    required this.shareOfPeak,
    this.badge,
    this.emphasize = false,
  });

  final String title;
  final double volumeLiters;
  final double revenuePkr;
  final int txnCount;
  final double shareOfPeak;
  final String? badge;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color accent = emphasize ? tokens.coral : tokens.ink;
    final String? badgeLabel = badge?.trim();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: emphasize ? tokens.coral.withValues(alpha: 0.06) : tokens.canvas,
        borderRadius: BorderRadius.circular(tokens.radius12),
        border: Border.all(
          color: emphasize ? tokens.coral : tokens.line,
          width: emphasize ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    letterSpacing: 0.7,
                    color: tokens.ink,
                  ),
                ),
              ),
              if (badgeLabel != null && badgeLabel.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.ink,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badgeLabel,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w700,
                      fontSize: 8,
                      letterSpacing: 0.7,
                      color: tokens.card,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ScaleDownMetric(
            text: formatLiters(volumeLiters),
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w700,
              fontSize: 18,
              height: 1.15,
              color: accent,
            ),
          ),
          const SizedBox(height: 2),
          ScaleDownMetric(
            text: formatPkrWhole(revenuePkr),
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: shareOfPeak,
              minHeight: 7,
              backgroundColor: tokens.line,
              color: emphasize ? tokens.coral : tokens.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$txnCount ${txnCount == 1 ? 'transaction' : 'transactions'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w500,
              fontSize: 10,
              color: tokens.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}
