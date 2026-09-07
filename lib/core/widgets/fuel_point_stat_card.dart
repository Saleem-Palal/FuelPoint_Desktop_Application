import 'package:flutter/material.dart';

import '../theme/dispensr_theme.dart';
import 'responsive_layout.dart';

/// Shared KPI tile used on Sale Screen and Shift Management.
class FuelPointStatCard extends StatelessWidget {
  const FuelPointStatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.badgeBackgroundColor,
    required this.badgeIconColor,
    this.subtitle,
    this.borderColor,
    this.valueColor,
    this.onTap,
  });

  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color badgeBackgroundColor;
  final Color badgeIconColor;
  final Color? borderColor;
  final Color? valueColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color outline = borderColor ?? tokens.line;

    final Widget body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: badgeBackgroundColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: badgeIconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 9,
                    letterSpacing: 0.8,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                ScaleDownMetric(
                  text: value,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    height: 1.2,
                    color: valueColor ?? colors.onSurface,
                  ),
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.w500,
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    final BorderRadius radii = BorderRadius.circular(tokens.radius20);

    return Container(
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: radii,
        border: Border.all(color: outline),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radii,
        clipBehavior: Clip.antiAlias,
        child: onTap == null
            ? body
            : InkWell(
                onTap: onTap,
                hoverColor: colors.onSurface.withValues(alpha: 0.04),
                child: body,
              ),
      ),
    );
  }
}
