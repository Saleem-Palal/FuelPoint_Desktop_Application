import 'package:flutter/material.dart';

import '../../../core/theme/dispensr_theme.dart';
import '../../../features/station/domain/dashboard_models.dart';
import '../../../features/station/domain/money_format.dart';
import 'dashboard_ui_kit.dart';

class DashboardPeakHours extends StatelessWidget {
  const DashboardPeakHours({super.key, required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final DashboardHourlyBucket? busiest = snapshot.busiestHour;
    return DashboardPanel(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const DashboardSectionTitle(
            title: 'Peak / rush hours',
            subtitle: 'Weekly throughput from sales_history · last 7 days',
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _PeakBanner(
                icon: Icons.wb_sunny_outlined,
                label: snapshot.morningPeak.bannerLabel,
                tint: tokens.warn,
              ),
              _PeakBanner(
                icon: Icons.nights_stay_outlined,
                label: snapshot.eveningPeak.bannerLabel,
                tint: tokens.coral,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'HOURLY VOLUME',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w700,
              fontSize: 9,
              letterSpacing: 0.8,
              color: tokens.inkMuted,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(height: 148, child: _HourlyChart(buckets: snapshot.hourly)),
          const SizedBox(height: 10),
          Text(
            busiest == null
                ? 'No fills in the last 7 days — heatmap waits on sales_history.'
                : 'Heaviest load at ${busiest.hourLabel} · ${formatLiters(busiest.volumeLiters)} — staff an extra cashier in that window.',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w500,
              fontSize: 11,
              height: 1.35,
              color: tokens.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _PeakBanner extends StatelessWidget {
  const _PeakBanner({
    required this.icon,
    required this.label,
    required this.tint,
  });

  final IconData icon;
  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(tokens.radius12),
          border: Border.all(color: tint.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 16, color: tint),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: tokens.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HourlyChart extends StatelessWidget {
  const _HourlyChart({required this.buckets});

  final List<DashboardHourlyBucket> buckets;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < buckets.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 3),
          Expanded(
            child: _HourBar(bucket: buckets[i], tokens: tokens),
          ),
        ],
      ],
    );
  }
}

class _HourBar extends StatelessWidget {
  const _HourBar({required this.bucket, required this.tokens});

  final DashboardHourlyBucket bucket;
  final DispensrTokens tokens;

  @override
  Widget build(BuildContext context) {
    final bool labeled = bucket.hour % 3 == 0;
    final Color fill =
        Color.lerp(tokens.line, tokens.coral, bucket.intensity.clamp(0, 1)) ??
        tokens.coral;
    return Tooltip(
      message:
          '${bucket.hourLabel}\n${formatLiters(bucket.volumeLiters)} · ${bucket.txnCount} fills',
      waitDuration: Duration.zero,
      child: Column(
        children: <Widget>[
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: bucket.intensity <= 0
                    ? 0.04
                    : 0.08 + (bucket.intensity * 0.92),
                widthFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 28,
            child: labeled
                ? Text(
                    _shortHour(bucket.hour),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w600,
                      fontSize: 8,
                      height: 1.1,
                      color: tokens.inkMuted,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  static String _shortHour(int hour) {
    final int display = hour % 12 == 0 ? 12 : hour % 12;
    final String period = hour >= 12 ? 'P' : 'A';
    return '$display$period';
  }
}
