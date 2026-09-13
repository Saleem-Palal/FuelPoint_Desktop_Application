import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/access/domain/access_policy.dart';
import '../features/access/presentation/access_controller.dart';
import '../features/access/presentation/owner_pin_verification_modal.dart';
import '../features/station/presentation/ledger_providers.dart';

class ShellDestinations {
  static const int dashboard = 0;
  static const int sale = 1;
  static const int purchase = 2;
  static const int ledger = 3;
  static const int reports = 4;
  static const int shifts = 5;
  static const int dispenserMonitor = 6;
  static const int settings = 7;
  static const int customers = 8;
  static const int managers = 9;
}

final shellDestinationProvider = StateProvider<int>(
  (Ref ref) => ShellDestinations.sale,
);

Future<void> openLedgerSales(BuildContext context, WidgetRef ref) async {
  if (shouldEnforceOwnerAccessLock &&
      AccessPolicy.destinationRequiresOwner(ShellDestinations.ledger) &&
      !ref.read(accessControllerProvider).isOwnerElevated) {
    final bool unlocked = await showOwnerPinVerificationModal(context);
    if (!unlocked) {
      return;
    }
  }
  ref.read(ledgerQueryProvider.notifier).setTab(LedgerTab.sales);
  ref.read(shellDestinationProvider.notifier).state = ShellDestinations.ledger;
}
