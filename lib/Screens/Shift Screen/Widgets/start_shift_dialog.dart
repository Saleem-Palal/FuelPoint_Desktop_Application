import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/dispensr_theme.dart';
import '../../../features/shift/domain/shift_models.dart';
import 'helper_unit_assignment_panel.dart';

typedef StartShiftSubmit =
    Future<StartShiftOutcome> Function({
      required String pin,
      required Map<int, String?> unitAssignments,
    });

Future<StartShiftOutcome?> showStartShiftDialog(
  BuildContext context, {
  required ManagerProfile manager,
  required List<HelperProfile> helpers,
  required Map<int, String?> currentAssignments,
  required StartShiftSubmit onConfirm,
}) {
  return showDialog<StartShiftOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return StartShiftDialog(
        manager: manager,
        helpers: helpers,
        currentAssignments: currentAssignments,
        onConfirm: onConfirm,
      );
    },
  );
}

class StartShiftDialog extends StatefulWidget {
  const StartShiftDialog({
    super.key,
    required this.manager,
    required this.helpers,
    required this.currentAssignments,
    required this.onConfirm,
  });

  final ManagerProfile manager;
  final List<HelperProfile> helpers;
  final Map<int, String?> currentAssignments;
  final StartShiftSubmit onConfirm;

  @override
  State<StartShiftDialog> createState() => _StartShiftDialogState();
}

class _StartShiftDialogState extends State<StartShiftDialog> {
  final TextEditingController _pin = TextEditingController();
  late Map<int, String?> _assignments;
  String? _pinError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _assignments = Map<int, String?>.from(widget.currentAssignments);
  }

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  bool get _canConfirm => !_busy && _pin.text.trim().length >= 4;

  Future<void> _submit() async {
    if (!_canConfirm) {
      return;
    }
    setState(() {
      _busy = true;
      _pinError = null;
    });
    final StartShiftOutcome outcome = await widget.onConfirm(
      pin: _pin.text.trim(),
      unitAssignments: Map<int, String?>.from(_assignments),
    );
    if (!mounted) {
      return;
    }
    if (outcome == StartShiftOutcome.invalidPin) {
      setState(() {
        _busy = false;
        _pinError = 'PIN does not match ${widget.manager.name}.';
      });
      return;
    }
    Navigator.of(context).pop(outcome);
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
          Icon(Icons.badge_outlined, size: 20, color: tokens.coral),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Start this ${widget.manager.name} Shift?',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: tokens.ink,
                  ),
                ),
                Text(
                  'Enter PIN and assign helpers to units',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                    color: tokens.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Sales and cash will tag to ${widget.manager.name}. '
              'Assign a helper to each dispenser, or leave a unit unassigned.',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w500,
                fontSize: 13,
                color: tokens.inkMuted,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '${widget.manager.name}\'s PIN',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: tokens.inkMuted,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _pin,
              obscureText: true,
              enabled: !_busy,
              maxLength: 6,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              onChanged: (_) {
                setState(() {
                  _pinError = null;
                });
              },
              onSubmitted: (_) => _submit(),
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w700,
                fontSize: 16,
                letterSpacing: 4,
                color: tokens.ink,
              ),
              decoration: InputDecoration(
                hintText: '••••',
                counterText: '',
                errorText: _pinError,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Helper assignment',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: tokens.inkMuted,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: HelperUnitAssignmentPanel(
                helpers: widget.helpers,
                assignments: _assignments,
                originalAssignments: widget.currentAssignments,
                onChanged: (Map<int, String?> next) {
                  setState(() {
                    _assignments = next;
                  });
                },
              ),
            ),
          ],
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
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DsPillButton(
                label: _busy ? 'Starting…' : 'Start Shift',
                compact: true,
                icon: Icons.play_arrow_rounded,
                onPressed: _canConfirm ? _submit : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
