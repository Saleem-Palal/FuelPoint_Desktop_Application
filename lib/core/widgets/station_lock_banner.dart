import 'package:flutter/material.dart';

import '../../features/station/domain/station_link_alerts.dart';
import '../theme/dispensr_theme.dart';

class StationLockBanner extends StatelessWidget {
  const StationLockBanner({
    super.key,
    required this.color,
    required this.icon,
    required this.message,
  });

  factory StationLockBanner.fromAlert(
    StationLinkAlert alert, {
    required DispensrTokens tokens,
  }) {
    switch (alert.kind) {
      case StationLinkAlertKind.softwareWifi:
        return StationLockBanner(
          color: tokens.warn,
          icon: Icons.wifi_off,
          message: alert.message,
        );
      case StationLinkAlertKind.espWifi:
        return StationLockBanner(
          color: tokens.bad,
          icon: Icons.cloud_off,
          message: alert.message,
        );
      case StationLinkAlertKind.fdxBoard:
        return StationLockBanner(
          color: tokens.coral,
          icon: Icons.cable,
          message: alert.message,
        );
    }
  }

  final Color color;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(tokens.radius12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: tokens.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row of link banners so they do not stack over the unit cards.
class StationLinkAlertStrip extends StatelessWidget {
  const StationLinkAlertStrip({
    super.key,
    required this.alerts,
    required this.tokens,
  });

  final List<StationLinkAlert> alerts;
  final DispensrTokens tokens;

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final StationLinkAlert alert in alerts)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: StationLockBanner.fromAlert(alert, tokens: tokens),
          ),
      ],
    );
  }
}
