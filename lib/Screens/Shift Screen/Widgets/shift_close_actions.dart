import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../Shell/shell_navigation.dart';
import '../../../features/access/domain/access_policy.dart';
import '../../../features/access/domain/operator_credential.dart';
import '../../../features/shift/domain/shift_lifecycle.dart';
import '../../../features/shift/domain/shift_models.dart';
import '../../../features/shift/presentation/shift_hardware.dart';
import '../../../features/shift/presentation/shift_providers.dart';
import 'shift_close_warning_dialog.dart';

Future<void> promptManualEndShift(BuildContext context, WidgetRef ref) async {
  final ShiftWorkspaceState workspace = ref.read(shiftWorkspaceProvider);
  if (!workspace.canEndShift) {
    if (workspace.hasUnconfirmedAccount && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ShiftLifecycleGuard.pendingAccountBlockedMessage()),
        ),
      );
    } else if (workspace.pendingReconciliation != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Finish the pending cash tally in the sidebar.'),
        ),
      );
    }
    return;
  }
  final OperatorShiftRecord? shift = workspace.activeShift;
  if (shift == null) {
    return;
  }
  if (workspace.hasUnconfirmedAccount) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ShiftLifecycleGuard.pendingAccountBlockedMessage()),
        ),
      );
    }
    return;
  }
  final int? blockingUnit = shouldEnforceStationGuards
      ? dispensingUnitIdOf(ref)
      : null;
  if (blockingUnit != null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ShiftLifecycleGuard.endBlockedMessage(blockingUnit)),
        ),
      );
    }
    return;
  }
  final OperatorCredential? auth = await showOperatorPinDialog(
    context,
    operatorId: shift.operatorId,
    operatorName: shift.operatorName,
    title: 'End Shift (Manual)',
    message:
        'Confirm ${shift.operatorName} to freeze ${shift.shiftId} and '
        'open the cash tally. All helpers will be taken off duty.',
  );
  if (auth == null || !context.mounted) {
    return;
  }
  try {
    final ShiftHandoverResult result = await ref
        .read(shiftWorkspaceProvider.notifier)
        .beginManualEnd(
          pin: auth.pin,
          fingerprintVerified: auth.fingerprintVerified,
          blockingDispensingUnit: shouldEnforceStationGuards
              ? dispensingUnitIdOf(ref)
              : null,
          closingMeters: currentUnitMetersOf(ref),
        );
    if (!context.mounted) {
      return;
    }
    if (result.outcome == HandoverOutcome.invalidPin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PIN does not match the on-duty operator.'),
        ),
      );
      return;
    }
    if (result.outcome == HandoverOutcome.unitsDispensing) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ShiftLifecycleGuard.endBlockedMessage(result.blockedUnitId ?? 0),
          ),
        ),
      );
      return;
    }
    if (result.outcome == HandoverOutcome.pendingAccount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ShiftLifecycleGuard.pendingAccountBlockedMessage()),
        ),
      );
      return;
    }
    if (!result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not end the shift. Try again.')),
      );
      return;
    }
    ref.read(shellDestinationProvider.notifier).state =
        ShellDestinations.shifts;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${shift.shiftId} is pending tally. Enter counted cash in the sidebar.',
        ),
      ),
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Could not end shift: $error')));
  }
}

Future<bool> promptForceCloseShift(BuildContext context, WidgetRef ref) async {
  final ShiftWorkspaceState workspace = ref.read(shiftWorkspaceProvider);
  final OperatorShiftRecord? shift =
      workspace.activeShift ?? workspace.pendingReconciliation?.shift;
  if (shift == null) {
    return true;
  }
  final String pendingNote = workspace.hasUnconfirmedAccount
      ? ' Unconfirmed account transfers are still waiting on the Sale screen.'
      : '';
  final OperatorCredential? auth = await showOperatorPinDialog(
    context,
    operatorId: shift.operatorId,
    operatorName: shift.operatorName,
    title: 'Force Close Application',
    message:
        'Confirm ${shift.operatorName} to mark ${shift.shiftId} as '
        'FORCE_CLOSED and quit. This is written to the audit log.$pendingNote',
  );
  if (auth == null || !context.mounted) {
    return false;
  }
  try {
    final bool ok = await ref
        .read(shiftWorkspaceProvider.notifier)
        .forceCloseActiveShift(
          pin: auth.pin,
          fingerprintVerified: auth.fingerprintVerified,
        );
    if (!context.mounted) {
      return ok;
    }
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PIN does not match the on-duty operator.'),
        ),
      );
    }
    return ok;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not force-close: $error')));
    }
    return false;
  }
}

Future<void> promptUnverifiedShift(BuildContext context, WidgetRef ref) async {
  final ShiftWorkspaceState workspace = ref.read(shiftWorkspaceProvider);
  final OperatorShiftRecord? shift = workspace.activeShift;
  if (shift == null || !workspace.isUnverifiedSession) {
    return;
  }
  final UnverifiedShiftAction? action = await showUnverifiedShiftDialog(
    context,
    shift: shift,
    uncleanExitAt: workspace.uncleanExitAt,
  );
  if (action == null || !context.mounted) {
    return;
  }
  final OperatorCredential? auth = await showOperatorPinDialog(
    context,
    operatorId: shift.operatorId,
    operatorName: shift.operatorName,
    title: action == UnverifiedShiftAction.resume
        ? 'Resume open shift'
        : 'Reconcile previous shift',
    message:
        'Confirm ${shift.operatorName} to '
        '${action == UnverifiedShiftAction.resume ? 'resume' : 'close'} '
        '${shift.shiftId}.',
  );
  if (auth == null || !context.mounted) {
    return promptUnverifiedShift(context, ref);
  }
  if (action == UnverifiedShiftAction.resume) {
    final bool ok = await ref
        .read(shiftWorkspaceProvider.notifier)
        .resumeUnverifiedSession(
          auth.pin,
          fingerprintVerified: auth.fingerprintVerified,
        );
    if (!context.mounted) {
      return;
    }
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PIN does not match the on-duty operator.'),
        ),
      );
      return promptUnverifiedShift(context, ref);
    }
    ref.read(shellDestinationProvider.notifier).state = ShellDestinations.sale;
    return;
  }
  final ShiftHandoverResult result = await ref
      .read(shiftWorkspaceProvider.notifier)
      .beginManualEnd(
        pin: auth.pin,
        fingerprintVerified: auth.fingerprintVerified,
        closingMeters: currentUnitMetersOf(ref),
      );
  if (!context.mounted) {
    return;
  }
  if (result.outcome == HandoverOutcome.invalidPin) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PIN does not match the on-duty operator.')),
    );
    return promptUnverifiedShift(context, ref);
  }
}
