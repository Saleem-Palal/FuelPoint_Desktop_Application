import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/dispensr_theme.dart';
import '../../../features/shift/domain/shift_models.dart';

class AddManagerResult {
  const AddManagerResult({
    required this.name,
    required this.role,
    this.pin = kDefaultManagerPin,
  });

  final String name;
  final ManagerRole role;
  final String pin;
}

Future<String?> showAddHelperDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext context) => const _AddHelperDialog(),
  );
}

Future<double?> showEditRewardRateDialog(
  BuildContext context, {
  required double currentRate,
}) {
  return showDialog<double>(
    context: context,
    builder: (BuildContext context) {
      return _EditRewardRateDialog(currentRate: currentRate);
    },
  );
}

Future<AddManagerResult?> showAddManagerDialog(BuildContext context) {
  return showDialog<AddManagerResult>(
    context: context,
    builder: (BuildContext context) => const _AddManagerDialog(),
  );
}

class _AddManagerDialog extends StatefulWidget {
  const _AddManagerDialog();

  @override
  State<_AddManagerDialog> createState() => _AddManagerDialogState();
}

class _AddManagerDialogState extends State<_AddManagerDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _pin = TextEditingController(
    text: kDefaultManagerPin,
  );
  ManagerRole _role = ManagerRole.manager;

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    super.dispose();
  }

  bool get _canSave {
    final String pin = _pin.text.trim();
    return _name.text.trim().isNotEmpty && pin.length >= 4;
  }

  void _save() {
    if (!_canSave) {
      return;
    }
    Navigator.of(context).pop(
      AddManagerResult(
        name: _name.text.trim(),
        role: _role,
        pin: _pin.text.trim(),
      ),
    );
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
            child: Text(
              'Add Manager',
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
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _LabeledField(
              label: 'Name',
              child: TextField(
                controller: _name,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _save(),
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: tokens.ink,
                ),
                decoration: const InputDecoration(hintText: 'e.g. Ali Khan'),
              ),
            ),
            const SizedBox(height: 12),
            _LabeledField(
              label: 'Role',
              child: DropdownButtonFormField<ManagerRole>(
                initialValue: _role,
                decoration: const InputDecoration(),
                items: const <DropdownMenuItem<ManagerRole>>[
                  DropdownMenuItem<ManagerRole>(
                    value: ManagerRole.manager,
                    child: Text('Manager'),
                  ),
                  DropdownMenuItem<ManagerRole>(
                    value: ManagerRole.owner,
                    child: Text('Owner'),
                  ),
                ],
                onChanged: (ManagerRole? value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _role = value;
                  });
                },
              ),
            ),
            const SizedBox(height: 12),
            _LabeledField(
              label: 'PIN (4–6 digits)',
              child: TextField(
                controller: _pin,
                obscureText: true,
                maxLength: 6,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                onChanged: (_) => setState(() {}),
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: tokens.ink,
                ),
                decoration: const InputDecoration(
                  hintText: '0000',
                  counterText: '',
                ),
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
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DsPillButton(
                label: 'Save Manager',
                compact: true,
                icon: Icons.check,
                onPressed: _canSave ? _save : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AddHelperDialog extends StatefulWidget {
  const _AddHelperDialog();

  @override
  State<_AddHelperDialog> createState() => _AddHelperDialogState();
}

class _AddHelperDialogState extends State<_AddHelperDialog> {
  final TextEditingController _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _canSave => _name.text.trim().isNotEmpty;

  void _save() {
    if (!_canSave) {
      return;
    }
    Navigator.of(context).pop(_name.text.trim());
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
          Icon(Icons.engineering_outlined, size: 20, color: tokens.coral),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Add New Helper',
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
        width: 380,
        child: _LabeledField(
          label: 'Helper Name',
          child: TextField(
            controller: _name,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _save(),
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: tokens.ink,
            ),
            decoration: const InputDecoration(hintText: 'e.g. Sajjad Ali'),
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
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DsPillButton(
                label: 'Save Helper',
                compact: true,
                icon: Icons.check,
                onPressed: _canSave ? _save : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EditRewardRateDialog extends StatefulWidget {
  const _EditRewardRateDialog({required this.currentRate});

  final double currentRate;

  @override
  State<_EditRewardRateDialog> createState() => _EditRewardRateDialogState();
}

class _EditRewardRateDialogState extends State<_EditRewardRateDialog> {
  late final TextEditingController _rate;

  @override
  void initState() {
    super.initState();
    _rate = TextEditingController(text: widget.currentRate.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _rate.dispose();
    super.dispose();
  }

  double? get _parsed {
    return double.tryParse(_rate.text.trim());
  }

  bool get _canSave {
    final double? value = _parsed;
    return value != null && value >= 0;
  }

  void _save() {
    final double? value = _parsed;
    if (value == null) {
      return;
    }
    Navigator.of(context).pop(value);
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
          Icon(Icons.payments_outlined, size: 20, color: tokens.coral),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Edit Global Reward Rate',
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
        width: 360,
        child: _LabeledField(
          label: 'Reward per transaction (PKR)',
          child: TextField(
            controller: _rate,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _save(),
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: tokens.ink,
            ),
            decoration: const InputDecoration(
              hintText: '5.00',
              suffixText: 'Rs / Tx',
            ),
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
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DsPillButton(
                label: 'Save Rate',
                compact: true,
                icon: Icons.check,
                onPressed: _canSave ? _save : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w600,
            fontSize: 12,
            color: tokens.inkMuted,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}
