import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/security/pin_hasher.dart';
import '../../../core/theme/dispensr_theme.dart';
import '../../../features/shift/domain/shift_models.dart';
import 'shift_ui_kit.dart';

enum ShiftCloseWarningAction { stay, proceedEndShift }

Future<String?> showManagerPinDialog(
  BuildContext context, {
  required String managerName,
  required String title,
  required String message,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return _ManagerPinDialog(
        managerName: managerName,
        title: title,
        message: message,
      );
    },
  );
}

Future<ShiftCloseWarningAction?> showShiftCloseWarningDialog(
  BuildContext context, {
  required String managerName,
}) {
  return showDialog<ShiftCloseWarningAction>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return _ShiftCloseWarningDialog(managerName: managerName);
    },
  );
}

Future<UnverifiedShiftAction?> showUnverifiedShiftDialog(
  BuildContext context, {
  required ManagerShiftRecord shift,
  DateTime? uncleanExitAt,
}) {
  return showDialog<UnverifiedShiftAction>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return _UnverifiedShiftDialog(shift: shift, uncleanExitAt: uncleanExitAt);
    },
  );
}

enum UnverifiedShiftAction { resume, reconcile }

class _ManagerPinDialog extends StatefulWidget {
  const _ManagerPinDialog({
    required this.managerName,
    required this.title,
    required this.message,
  });

  final String managerName;
  final String title;
  final String message;

  @override
  State<_ManagerPinDialog> createState() => _ManagerPinDialogState();
}

class _ManagerPinDialogState extends State<_ManagerPinDialog> {
  final TextEditingController _pin = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  void _submit() {
    final String pin = _pin.text.trim();
    if (!PinHasher.isValidPlainPin(pin)) {
      setState(() {
        _error =
            'Enter the ${PinHasher.minPinLength}–${PinHasher.maxPinLength} digit manager PIN.';
      });
      return;
    }
    Navigator.of(context).pop(pin);
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
      title: Text(
        widget.title,
        style: TextStyle(
          fontFamily: 'Roboto',
          fontWeight: FontWeight.w700,
          fontSize: 16,
          color: tokens.ink,
        ),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              widget.message,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w500,
                fontSize: 13,
                color: tokens.inkMuted,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _pin,
              obscureText: true,
              autofocus: true,
              maxLength: PinHasher.maxPinLength,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              onSubmitted: (_) => _submit(),
              onChanged: (_) {
                if (_error != null) {
                  setState(() {
                    _error = null;
                  });
                }
              },
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w700,
                fontSize: 18,
                letterSpacing: 6,
                color: tokens.ink,
              ),
              decoration: InputDecoration(
                labelText: '${widget.managerName} PIN',
                counterText: '',
                errorText: _error,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        DsPillButton(
          label: 'Cancel',
          variant: DsPillVariant.outline,
          compact: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
        DsPillButton(label: 'Verify PIN', compact: true, onPressed: _submit),
      ],
    );
  }
}

class _ShiftCloseWarningDialog extends StatelessWidget {
  const _ShiftCloseWarningDialog({required this.managerName});

  final String managerName;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return AlertDialog(
      backgroundColor: tokens.card,
      surfaceTintColor: tokens.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius20),
        side: BorderSide(color: tokens.bad.withValues(alpha: 0.45)),
      ),
      title: Row(
        children: <Widget>[
          Icon(Icons.warning_amber_rounded, color: tokens.bad),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Live shift — close blocked',
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
        width: 520,
        child: Text(
          'Live Shift Under Manager $managerName Active. '
          'Closing app will suspend telemetry.',
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w500,
            fontSize: 14,
            height: 1.45,
            color: tokens.ink,
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            DsPillButton(
              label: 'Cancel & Stay',
              variant: DsPillVariant.outline,
              compact: true,
              onPressed: () {
                Navigator.of(context).pop(ShiftCloseWarningAction.stay);
              },
            ),
            const SizedBox(height: 8),
            DsPillButton(
              label: 'End Shift & Reconcile',
              compact: true,
              icon: Icons.account_balance_wallet_outlined,
              onPressed: () {
                Navigator.of(
                  context,
                ).pop(ShiftCloseWarningAction.proceedEndShift);
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _UnverifiedShiftDialog extends StatelessWidget {
  const _UnverifiedShiftDialog({required this.shift, this.uncleanExitAt});

  final ManagerShiftRecord shift;
  final DateTime? uncleanExitAt;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return AlertDialog(
      backgroundColor: tokens.card,
      surfaceTintColor: tokens.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius20),
        side: BorderSide(color: tokens.coral),
      ),
      title: Text(
        'Crash recovery',
        style: TextStyle(
          fontFamily: 'Roboto',
          fontWeight: FontWeight.w700,
          fontSize: 16,
          color: tokens.ink,
        ),
      ),
      content: SizedBox(
        width: 480,
        child: Text(
          '${shift.shiftId} is still LIVE under ${shift.managerName} after an '
          'unclean exit'
          '${uncleanExitAt == null ? '' : ' at ${_formatStamp(uncleanExitAt!)}'}'
          '. Enter that manager PIN to resume telemetry and re-enable keypads, '
          'or force-end and reconcile using last hardware meters.',
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w500,
            fontSize: 14,
            height: 1.45,
            color: tokens.ink,
          ),
        ),
      ),
      actions: <Widget>[
        DsPillButton(
          label: 'Force End & Reconcile',
          variant: DsPillVariant.outline,
          compact: true,
          onPressed: () {
            Navigator.of(context).pop(UnverifiedShiftAction.reconcile);
          },
        ),
        DsPillButton(
          label: 'Resume Shift',
          compact: true,
          onPressed: () {
            Navigator.of(context).pop(UnverifiedShiftAction.resume);
          },
        ),
      ],
    );
  }
}

String _formatStamp(DateTime value) {
  final String y = value.year.toString().padLeft(4, '0');
  final String m = value.month.toString().padLeft(2, '0');
  final String d = value.day.toString().padLeft(2, '0');
  final String hh = value.hour.toString().padLeft(2, '0');
  final String mm = value.minute.toString().padLeft(2, '0');
  return '$y-$m-$d $hh:$mm';
}
