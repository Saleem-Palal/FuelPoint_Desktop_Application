import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/purchase_repository.dart';
import 'purchase_controller.dart';
import 'station_providers.dart';

export '../data/purchase_repository.dart'
    show PurchaseRecord, PurchaseRepository;
export 'purchase_controller.dart' show PurchaseController;

final purchaseRepositoryProvider = Provider<PurchaseRepository>((Ref ref) {
  return PurchaseRepository();
});

final purchaseControllerProvider = ChangeNotifierProvider<PurchaseController>((
  Ref ref,
) {
  final PurchaseController controller = PurchaseController(
    ref.watch(purchaseRepositoryProvider),
    onCommitted: () {
      bumpHistoryRevision(ref.read(historyRevisionProvider.notifier));
    },
  );

  void publishDieselRate() {
    ref
        .read(stationControllerProvider.notifier)
        .setDieselAverageRate(controller.weightedAverageRate);
  }

  void onPurchasesChanged() {
    publishDieselRate();
    unawaited(ref.read(lowStockAlertProvider.notifier).sync());
  }

  controller.addListener(onPurchasesChanged);
  ref.onDispose(() {
    controller.removeListener(onPurchasesChanged);
  });
  return controller;
});
