import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/station/domain/money_format.dart';
import '../../features/station/presentation/station_providers.dart';
import '../../providers/settings_provider.dart';
import '../theme/dispensr_theme.dart';

/// Persistent bottom-right low-stock badge. Clicks pass through to the floor.
class LowStockToastHost extends ConsumerStatefulWidget {
  const LowStockToastHost({super.key});

  @override
  ConsumerState<LowStockToastHost> createState() => _LowStockToastHostState();
}

class _LowStockToastHostState extends ConsumerState<LowStockToastHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  LowStockAlert? _held;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _slide = Tween<Offset>(begin: const Offset(0.12, 0.35), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(ref.read(lowStockAlertProvider.notifier).sync());
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<double>(
      settingsProvider.select(
        (SettingsState settings) => settings.lowStockThresholdLiters,
      ),
      (double? previous, double next) {
        unawaited(ref.read(lowStockAlertProvider.notifier).sync());
      },
    );
    ref.listen<LowStockAlert?>(lowStockAlertProvider, (
      LowStockAlert? previous,
      LowStockAlert? next,
    ) {
      if (next != null) {
        setState(() {
          _held = next;
        });
        if (previous == null) {
          unawaited(_controller.forward());
        }
        return;
      }
      if (previous != null) {
        unawaited(
          _controller.reverse().then((_) {
            if (!mounted) {
              return;
            }
            if (ref.read(lowStockAlertProvider) == null) {
              setState(() {
                _held = null;
              });
            }
          }),
        );
      }
    });

    final LowStockAlert? alert = _held;
    return Positioned(
      right: 16,
      bottom: 16,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _controller,
          child: SlideTransition(
            position: _slide,
            child: alert == null
                ? const SizedBox.shrink()
                : _LowStockToastCard(alert: alert),
          ),
        ),
      ),
    );
  }
}

class _LowStockToastCard extends StatelessWidget {
  const _LowStockToastCard({required this.alert});

  final LowStockAlert alert;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Material(
      color: tokens.card.withValues(alpha: 0.94),
      elevation: 0,
      borderRadius: BorderRadius.circular(tokens.radius20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(tokens.radius20),
            border: Border.all(color: tokens.warn.withValues(alpha: 0.5)),
            boxShadow: tokens.cardShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.warning_amber_rounded, size: 18, color: tokens.warn),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Low diesel — ${formatLiters(alert.remainingLiters)} '
                    '(min ${formatLiters(alert.thresholdLiters)})',
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      height: 1.3,
                      color: tokens.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
