import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../Screens/Sale Screen/Widgets/Services/esp_last_ten_dialog.dart';
import '../../features/station/domain/dispenser_models.dart';
import '../../features/station/domain/esp_token_log.dart';
import '../../features/station/domain/money_format.dart';
import '../../features/station/presentation/station_providers.dart';
import '../theme/dispensr_theme.dart';

/// Bottom-right list of ESP last-10 fills that unit is missing from SQLite.
class RecoverSaleToastHost extends ConsumerWidget {
  const RecoverSaleToastHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<EspTokenLogRow> offers = ref.watch(espRecoverOffersProvider);
    if (offers.isEmpty) {
      return const SizedBox.shrink();
    }
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Positioned(
      right: 16,
      bottom: 16,
      child: Material(
        color: tokens.card.withValues(alpha: 0.96),
        elevation: 0,
        borderRadius: BorderRadius.circular(tokens.radius20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380, maxHeight: 320),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(tokens.radius20),
              border: Border.all(color: tokens.warn.withValues(alpha: 0.5)),
              boxShadow: tokens.cardShadow,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.restore, size: 18, color: tokens.warn),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${offers.length} sale${offers.length == 1 ? '' : 's'} '
                          'not in ledger',
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: tokens.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: offers.length,
                      separatorBuilder: (BuildContext _, int __) =>
                          const SizedBox(height: 6),
                      itemBuilder: (BuildContext context, int index) {
                        return _RecoverSaleRow(row: offers[index]);
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      TextButton(
                        onPressed: () {
                          ref
                              .read(stationControllerProvider.notifier)
                              .dismissAllEspRecoverOffers();
                        },
                        child: const Text('Dismiss all'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () {
                          unawaited(
                            ref
                                .read(stationControllerProvider.notifier)
                                .recoverAllEspOffers(),
                          );
                        },
                        child: const Text('Recover all'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecoverSaleRow extends ConsumerWidget {
  const _RecoverSaleRow({required this.row});

  final EspTokenLogRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.canvas.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(tokens.radius12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Unit ${row.unitId}  ${espLogStamp(row.at)}\n'
                '${formatLiters(row.volumeLiters)}  ·  ${formatPkr(row.amountPkr)}',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  height: 1.3,
                  color: tokens.ink,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                ref
                    .read(stationControllerProvider.notifier)
                    .dismissEspRecoverOffer(row);
              },
              child: const Text('Dismiss'),
            ),
            FilledButton(
              onPressed: () {
                unawaited(
                  recoverEspSaleInteractively(
                    context: context,
                    ref: ref,
                    row: row,
                  ),
                );
              },
              child: const Text('Recover'),
            ),
          ],
        ),
      ),
    );
  }
}
