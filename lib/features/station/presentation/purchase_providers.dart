import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shift/presentation/shift_providers.dart';
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
      unawaited(
        ref
            .read(shiftWorkspaceProvider.notifier)
            .refreshExpectedCashComponents(),
      );
    },
  );

  void publishDieselRate() {
    ref
        .read(stationControllerProvider.notifier)
        .setDieselAverageRate(controller.weightedAverageRate);
  }

  controller.addListener(publishDieselRate);
  ref.onDispose(() {
    controller.removeListener(publishDieselRate);
  });
  return controller;
});
