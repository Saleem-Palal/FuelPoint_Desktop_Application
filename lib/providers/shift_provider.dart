import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/shift/domain/shift_models.dart';
import '../features/shift/presentation/shift_providers.dart';

/// Close-policy and session snapshot over [shiftWorkspaceProvider].
///
/// Mutations stay on [ShiftWorkspaceNotifier] (`beginManualEnd`,
/// `forceCloseActiveShift`, `resumeUnverifiedSession`). This type exists so
/// window lifecycle and dialogs can query shift state without a second store.
@immutable
class ShiftProvider {
  const ShiftProvider({
    required this.hasActiveShift,
    required this.activeShift,
    required this.pendingReconciliation,
    required this.isUnverifiedSession,
  });

  final bool hasActiveShift;
  final ManagerShiftRecord? activeShift;
  final ReconciliationSnapshot? pendingReconciliation;
  final bool isUnverifiedSession;

  ManagerShiftRecord? get blockingShift {
    return activeShift ?? pendingReconciliation?.shift;
  }

  String get liveManagerName {
    return blockingShift?.managerName.trim().isNotEmpty == true
        ? blockingShift!.managerName.trim()
        : 'Unknown';
  }
}

final shiftProvider = Provider<ShiftProvider>((Ref ref) {
  final ShiftWorkspaceState workspace = ref.watch(shiftWorkspaceProvider);
  return ShiftProvider(
    hasActiveShift: workspace.hasActiveShift,
    activeShift: workspace.activeShift,
    pendingReconciliation: workspace.pendingReconciliation,
    isUnverifiedSession: workspace.isUnverifiedSession,
  );
});
