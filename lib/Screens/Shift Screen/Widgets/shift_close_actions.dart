import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/shift/domain/shift_models.dart';
import '../../../features/shift/presentation/shift_providers.dart';
import 'shift_close_warning_dialog.dart';

Future<void> promptManualEndShift(BuildContext context, WidgetRef ref) async {
  final ShiftWorkspaceState workspace = ref.read(shiftWorkspaceProvider);
  if (!workspace.canEndShift) {
    if (workspace.pendingReconciliation != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Finish the pending cash tally in the sidebar.'),
        ),
      );
    }
    return;
  }
  final ManagerShiftRecord? shift = workspace.activeShift;
  if (shift == null) {
    return;
  }
  final String? pin = await showManagerPinDialog(
    context,
    managerName: shift.managerName,
    title: 'End Shift (Manual)',
    message:
        'Enter ${shift.managerName}\'s PIN to freeze ${shift.shiftId} and '
        'open the cash tally. All helpers will be taken off duty. '
        'Dispenser keypads are not locked.',
  );
  if (pin == null || !context.mounted) {
    return;
  }
  try {
    final ShiftHandoverResult result = await ref
        .read(shiftWorkspaceProvider.notifier)
        .beginManualEnd(pin: pin);
    if (!context.mounted) {
      return;
    }
    if (result.outcome == HandoverOutcome.invalidPin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PIN does not match the on-duty manager.'),
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
  final ManagerShiftRecord? shift =
      workspace.activeShift ?? workspace.pendingReconciliation?.shift;
  if (shift == null) {
    return true;
  }
  final String? pin = await showManagerPinDialog(
    context,
    managerName: shift.managerName,
    title: 'Force Close Application',
    message:
        'Enter ${shift.managerName}\'s PIN to mark ${shift.shiftId} as '
        'FORCE_CLOSED and quit. This is written to the audit log.',
  );
  if (pin == null || !context.mounted) {
    return false;
  }
  try {
    final bool ok = await ref
        .read(shiftWorkspaceProvider.notifier)
        .forceCloseActiveShift(pin: pin);
    if (!context.mounted) {
      return ok;
    }
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PIN does not match the on-duty manager.'),
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
  final ManagerShiftRecord? shift = workspace.activeShift;
  if (shift == null || !workspace.isUnverifiedSession) {
    return;
  }
  final UnverifiedShiftAction? action = await showUnverifiedShiftDialog(
    context,
    shift: shift,
  );
  if (action == null || !context.mounted) {
    return;
  }
  final String? pin = await showManagerPinDialog(
    context,
    managerName: shift.managerName,
    title: action == UnverifiedShiftAction.resume
        ? 'Resume open shift'
        : 'Reconcile previous shift',
    message:
        'Enter ${shift.managerName}\'s PIN to '
        '${action == UnverifiedShiftAction.resume ? 'resume' : 'close'} '
        '${shift.shiftId}.',
  );
  if (pin == null || !context.mounted) {
    return promptUnverifiedShift(context, ref);
  }
  if (action == UnverifiedShiftAction.resume) {
    final bool ok = await ref
        .read(shiftWorkspaceProvider.notifier)
        .resumeUnverifiedSession(pin);
    if (!context.mounted) {
      return;
    }
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PIN does not match the on-duty manager.'),
        ),
      );
      return promptUnverifiedShift(context, ref);
    }
    return;
  }
  final ShiftHandoverResult result = await ref
      .read(shiftWorkspaceProvider.notifier)
      .beginManualEnd(pin: pin);
  if (!context.mounted) {
    return;
  }
  if (result.outcome == HandoverOutcome.invalidPin) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PIN does not match the on-duty manager.')),
    );
    return promptUnverifiedShift(context, ref);
  }
}
