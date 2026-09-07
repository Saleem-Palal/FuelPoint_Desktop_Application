import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/dispensr_theme.dart';
import '../../../../features/station/domain/dispenser_models.dart';
import '../../../../features/station/presentation/station_providers.dart';

/// Collapsible mock-hardware bar on the Sale screen.
/// Kept visible in debug and release so client MSIX demos can run without ESP32 hardware.
class DemoControlsBar extends ConsumerStatefulWidget {
  const DemoControlsBar({super.key});

  static const bool visible = true;

  @override
  ConsumerState<DemoControlsBar> createState() => _DemoControlsBarState();
}

class _DemoControlsBarState extends ConsumerState<DemoControlsBar> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    if (!DemoControlsBar.visible) {
      return const SizedBox.shrink();
    }
    final DispensrTokens tokens = DispensrTokens.of(context);
    final StationState station = ref.watch(stationControllerProvider);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.radius20),
        border: Border.all(color: tokens.line),
        boxShadow: tokens.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            onTap: () {
              setState(() {
                _expanded = !_expanded;
              });
            },
            borderRadius: BorderRadius.circular(tokens.radius12),
            hoverColor: tokens.canvas,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.sports_esports_outlined,
                    size: 16,
                    color: tokens.inkMuted,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Demo Controls',
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: tokens.ink,
                    ),
                  ),
                  const SizedBox(width: 8),
                  DsStatusPill(
                    label: 'Demo',
                    foreground: tokens.warn,
                    background: tokens.warn.withValues(alpha: 0.12),
                    border: tokens.warn.withValues(alpha: 0.3),
                    dot: false,
                  ),
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: tokens.inkMuted,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...<Widget>[
            const SizedBox(height: 8),

            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final int unitId in dispenserUnitIds) ...<Widget>[
                  if (unitId > 1) const SizedBox(width: 8),
                  Expanded(
                    child: _UnitDemoColumn(
                      bay: station.bay(unitId),
                      onDispense: () {
                        ref
                            .read(stationControllerProvider.notifier)
                            .simulateDispense(unitId);
                      },
                      onAbort: () {
                        ref
                            .read(stationControllerProvider.notifier)
                            .simulateZeroVolumeAbort(unitId);
                      },
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _UnitDemoColumn extends StatelessWidget {
  const _UnitDemoColumn({
    required this.bay,
    required this.onDispense,
    required this.onAbort,
  });

  final DispenserBay bay;
  final VoidCallback onDispense;
  final VoidCallback onAbort;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: tokens.canvas,
        borderRadius: BorderRadius.circular(tokens.radius12),
        border: Border.all(color: tokens.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            bay.name,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: tokens.ink,
            ),
          ),
          const SizedBox(height: 8),
          DsPillButton(
            label: 'Simulate Dispense',
            variant: DsPillVariant.coral,
            compact: true,
            onPressed: onDispense,
          ),
          const SizedBox(height: 6),
          DsPillButton(
            label: 'Simulate Zero-Volume Abort',
            variant: DsPillVariant.outline,
            compact: true,
            onPressed: onAbort,
          ),
        ],
      ),
    );
  }
}
