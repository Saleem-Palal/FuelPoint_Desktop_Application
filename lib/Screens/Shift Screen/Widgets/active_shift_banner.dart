import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/dispensr_theme.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../../../features/shift/domain/shift_models.dart';
import '../../../features/station/domain/money_format.dart';

class ActiveShiftBanner extends StatefulWidget {
  const ActiveShiftBanner({
    super.key,
    required this.shift,
    required this.expectedCash,
    required this.onEndShift,
    this.onManualEndShift,
  });

  final ManagerShiftRecord? shift;
  final double expectedCash;
  final VoidCallback? onEndShift;
  final VoidCallback? onManualEndShift;

  @override
  State<ActiveShiftBanner> createState() => _ActiveShiftBannerState();
}

class _ActiveShiftBannerState extends State<ActiveShiftBanner> {
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _now = DateTime.now();
      });
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final ManagerShiftRecord? shift = widget.shift;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: tokens.ink,
        borderRadius: BorderRadius.circular(tokens.radius20),
        boxShadow: tokens.cardShadow,
      ),
      child: shift == null
          ? _IdleBanner(tokens: tokens)
          : _LiveBanner(
              tokens: tokens,
              shift: shift,
              expectedCash: widget.expectedCash,
              now: _now,
              onEndShift: widget.onEndShift,
              onManualEndShift: widget.onManualEndShift,
            ),
    );
  }
}

class _IdleBanner extends StatelessWidget {
  const _IdleBanner({required this.tokens});

  final DispensrTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tokens.card.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(tokens.radius12),
          ),
          child: Icon(Icons.nightlight_outlined, color: tokens.card, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'No active manager shift',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: tokens.card,
                ),
              ),
              Text(
                'Select a manager on the left to start the next shift.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w400,
                  fontSize: 12,
                  color: tokens.canvas.withValues(alpha: 0.72),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LiveBanner extends StatelessWidget {
  const _LiveBanner({
    required this.tokens,
    required this.shift,
    required this.expectedCash,
    required this.now,
    required this.onEndShift,
    this.onManualEndShift,
  });

  final DispensrTokens tokens;
  final ManagerShiftRecord shift;
  final double expectedCash;
  final DateTime now;
  final VoidCallback? onEndShift;
  final VoidCallback? onManualEndShift;

  @override
  Widget build(BuildContext context) {
    final Duration elapsed = now.difference(shift.startTime);
    final String duration = elapsed.isNegative
        ? formatShiftDuration(Duration.zero)
        : formatShiftDuration(elapsed);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tokens.coral.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(tokens.radius12),
          ),
          child: Icon(Icons.person_outline, color: tokens.card, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Wrap(
            spacing: 18,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              _BannerIdentity(tokens: tokens, shift: shift),
              _BannerStat(
                tokens: tokens,
                label: 'Shift start',
                value: formatDateTime(shift.startTime),
              ),
              _BannerStat(
                tokens: tokens,
                label: 'Live duration',
                value: duration,
              ),
              _BannerStat(
                tokens: tokens,
                label: 'Expected cash in hand',
                value: formatPkr(expectedCash),
                emphasize: true,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: <Widget>[
            DsPillButton(
              label: 'End Shift (Manual)',
              icon: Icons.account_balance_wallet_outlined,
              compact: true,
              variant: DsPillVariant.outline,
              onPressed: onManualEndShift,
            ),
            DsPillButton(
              label: 'End Shift & Handover',
              icon: Icons.logout,
              compact: true,
              onPressed: onEndShift,
            ),
          ],
        ),
      ],
    );
  }
}

class _BannerIdentity extends StatelessWidget {
  const _BannerIdentity({required this.tokens, required this.shift});

  final DispensrTokens tokens;
  final ManagerShiftRecord shift;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          shift.managerName,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: tokens.card,
          ),
        ),
        const SizedBox(height: 4),
        DsStatusPill(
          label: managerRoleLabel(shift.role),
          foreground: tokens.coral,
          background: tokens.coral.withValues(alpha: 0.18),
          border: tokens.coral.withValues(alpha: 0.45),
        ),
      ],
    );
  }
}

class _BannerStat extends StatelessWidget {
  const _BannerStat({
    required this.tokens,
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final DispensrTokens tokens;
  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w700,
              fontSize: 9,
              letterSpacing: 0.8,
              color: tokens.canvas.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 2),
          ScaleDownMetric(
            text: value,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w700,
              fontSize: emphasize ? 16 : 13,
              color: emphasize ? tokens.coral : tokens.card,
            ),
          ),
        ],
      ),
    );
  }
}
