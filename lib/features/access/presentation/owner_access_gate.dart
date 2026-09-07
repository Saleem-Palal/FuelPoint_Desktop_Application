import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/dispensr_theme.dart';
import 'owner_pin_verification_modal.dart';

/// Placeholder shown when a restricted surface is visible without elevation.
class OwnerAccessGate extends StatelessWidget {
  const OwnerAccessGate({
    super.key,
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return ColoredBox(
      color: tokens.canvas,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            decoration: BoxDecoration(
              color: tokens.card,
              borderRadius: BorderRadius.circular(tokens.radius20),
              border: Border.all(color: tokens.line),
              boxShadow: tokens.cardShadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.lock_outline, size: 36, color: tokens.coralPressed),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: tokens.ink,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                    height: 1.4,
                    color: tokens.inkMuted,
                  ),
                ),
                const SizedBox(height: 16),
                DsPillButton(
                  label: 'Enter Owner Master PIN',
                  icon: Icons.lock_open_outlined,
                  onPressed: () {
                    unawaited(showOwnerPinVerificationModal(context));
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OwnerLockedTallyPanel extends StatelessWidget {
  const OwnerLockedTallyPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return const OwnerAccessGate(
      title: 'Shift tally locked',
      message:
          'Cash expected, sales totals, and historical shift figures require '
          'the Owner Master PIN.',
    );
  }
}
