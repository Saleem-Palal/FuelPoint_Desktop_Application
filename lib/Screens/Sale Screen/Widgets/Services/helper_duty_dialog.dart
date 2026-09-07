import 'package:flutter/material.dart';

import '../../../../core/theme/dispensr_theme.dart';

enum HelperDutyPromptKind { endSession, addUnit, startDuty }

Future<bool> showHelperDutyConfirmDialog({
  required BuildContext context,
  required HelperDutyPromptKind kind,
  required String helperName,
  required int targetUnitId,
  String? currentUnitsLabel,
  bool remainingOnOtherUnits = false,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return _HelperDutyConfirmDialog(
        kind: kind,
        helperName: helperName,
        targetUnitId: targetUnitId,
        currentUnitsLabel: currentUnitsLabel,
        remainingOnOtherUnits: remainingOnOtherUnits,
      );
    },
  ).then((bool? value) => value ?? false);
}

class _HelperDutyConfirmDialog extends StatelessWidget {
  const _HelperDutyConfirmDialog({
    required this.kind,
    required this.helperName,
    required this.targetUnitId,
    this.currentUnitsLabel,
    this.remainingOnOtherUnits = false,
  });

  final HelperDutyPromptKind kind;
  final String helperName;
  final int targetUnitId;
  final String? currentUnitsLabel;
  final bool remainingOnOtherUnits;

  String get _title {
    switch (kind) {
      case HelperDutyPromptKind.endSession:
        return 'End Helper Duty Session?';
      case HelperDutyPromptKind.addUnit:
        return 'Assign Additional Unit?';
      case HelperDutyPromptKind.startDuty:
        return 'Start Duty Session?';
    }
  }

  String get _message {
    switch (kind) {
      case HelperDutyPromptKind.endSession:
        if (remainingOnOtherUnits) {
          return 'Unassign $helperName from Unit $targetUnitId? '
              'They will remain on duty on their other units. '
              'This unit can only have one helper.';
        }
        return 'Unassigning $helperName from Unit $targetUnitId will close '
            'their active duty session and finalize their sales tally for '
            'this unit. Do you wish to proceed?';
      case HelperDutyPromptKind.addUnit:
        return '$helperName is already on duty on $currentUnitsLabel. '
            'Assign them to Unit $targetUnitId as well? '
            'A unit can only have one helper.';
      case HelperDutyPromptKind.startDuty:
        return 'Assign $helperName to Unit $targetUnitId to begin tracking '
            'sales and rewards for this dispenser?';
    }
  }

  String get _confirmLabel {
    switch (kind) {
      case HelperDutyPromptKind.endSession:
        return 'End Session';
      case HelperDutyPromptKind.addUnit:
        return 'Assign Unit';
      case HelperDutyPromptKind.startDuty:
        return 'Start Duty';
    }
  }

  IconData get _icon {
    switch (kind) {
      case HelperDutyPromptKind.endSession:
        return Icons.logout;
      case HelperDutyPromptKind.addUnit:
        return Icons.add_circle_outline;
      case HelperDutyPromptKind.startDuty:
        return Icons.play_circle_outline;
    }
  }

  DsPillVariant get _confirmVariant {
    switch (kind) {
      case HelperDutyPromptKind.endSession:
        return DsPillVariant.danger;
      case HelperDutyPromptKind.addUnit:
        return DsPillVariant.coral;
      case HelperDutyPromptKind.startDuty:
        return DsPillVariant.good;
    }
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return AlertDialog(
      backgroundColor: tokens.card,
      surfaceTintColor: tokens.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius20),
        side: BorderSide(color: tokens.line),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Row(
        children: <Widget>[
          Icon(_icon, size: 20, color: tokens.coral),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _title,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: tokens.ink,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Text(
          _message,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 13,
            height: 1.45,
            color: tokens.inkMuted,
          ),
        ),
      ),
      actions: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: DsPillButton(
                label: 'Cancel',
                variant: DsPillVariant.outline,
                compact: true,
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DsPillButton(
                label: _confirmLabel,
                variant: _confirmVariant,
                compact: true,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
