import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/dispensr_theme.dart';
import '../../../../features/station/domain/dispenser_models.dart';
import '../../../../features/station/domain/money_format.dart';
import '../../../../features/station/presentation/station_providers.dart';

class TokenSystemWidget extends ConsumerWidget {
  const TokenSystemWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final DispenserBay bay = ref.watch(selectedBayProvider);
    final int tokenId = ref.watch(currentTokenIdProvider);

    final String statusLabel;
    final Color statusFg;
    final Color statusBg;
    if (bay.isOffline) {
      statusLabel = 'Offline';
      statusFg = tokens.inkMuted;
      statusBg = tokens.line.withValues(alpha: 0.7);
    } else if (bay.isDispensing) {
      statusLabel = 'Dispensing';
      statusFg = tokens.coralPressed;
      statusBg = tokens.coral.withValues(alpha: 0.12);
    } else if (bay.isCycleComplete) {
      statusLabel = 'Awaiting Payment';
      statusFg = tokens.good;
      statusBg = tokens.good.withValues(alpha: 0.12);
    } else {
      statusLabel = 'Online';
      statusFg = tokens.good;
      statusBg = tokens.good.withValues(alpha: 0.12);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.radius20),
        border: Border.all(color: tokens.line),
        boxShadow: tokens.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Token System',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: tokens.ink,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: tokens.canvas,
              borderRadius: BorderRadius.circular(tokens.radius12),
              border: Border.all(color: tokens.line),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${bay.name} — ${bay.productLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: tokens.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                DsStatusPill(
                  label: statusLabel,
                  foreground: statusFg,
                  background: statusBg,
                  border: statusFg.withValues(alpha: 0.3),
                  dot: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Text(
                'Token No.',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                  color: tokens.inkMuted,
                ),
              ),
              const Spacer(),
              Text(
                formatTokenNo(tokenId),
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: tokens.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: tokens.canvas,
              borderRadius: BorderRadius.circular(tokens.radius12),
              border: Border.all(color: tokens.line),
            ),
            child: Column(
              children: <Widget>[
                _TelemetryLine(
                  label: 'Liters',
                  value: formatLiters(bay.volumeLiters),
                ),
                const SizedBox(height: 6),
                _TelemetryLine(label: 'Rate', value: formatRate(bay.rate)),
                const SizedBox(height: 6),
                _TelemetryLine(
                  label: 'Amount',
                  value: formatDispenserPkr(bay.amountPkr),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          DsPillButton(
            label: bay.keypadLocked ? 'Unlock Keypad' : 'Lock Keypad',
            variant: DsPillVariant.outline,
            onPressed: () {
              unawaitedLock(ref, !bay.keypadLocked);
            },
            compact: true,
          ),
          const SizedBox(height: 8),
          DsPillButton(
            label: 'New Token',
            variant: DsPillVariant.ink,
            onPressed: () {
              ref.read(stationControllerProvider.notifier).issueNewToken();
            },
            compact: true,
          ),
        ],
      ),
    );
  }

  void unawaitedLock(WidgetRef ref, bool lock) {
    final int unitId = ref.read(selectedDispenserIndexProvider);
    ref
        .read(stationControllerProvider.notifier)
        .setKeypadLock(unitId: unitId, lock: lock);
  }
}

class _TelemetryLine extends StatelessWidget {
  const _TelemetryLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Row(
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w500,
            fontSize: 11,
            color: tokens.inkMuted,
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: tokens.ink,
            ),
          ),
        ),
      ],
    );
  }
}
