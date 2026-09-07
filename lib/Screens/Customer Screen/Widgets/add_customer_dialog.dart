import 'package:flutter/material.dart';

import '../../../core/theme/dispensr_theme.dart';

class AddCustomerResult {
  const AddCustomerResult({required this.name, this.phone = ''});

  final String name;
  final String phone;
}

Future<AddCustomerResult?> showAddCustomerDialog(
  BuildContext context, {
  required String nextId,
}) {
  return showDialog<AddCustomerResult>(
    context: context,
    builder: (BuildContext context) {
      return _AddCustomerDialog(nextId: nextId);
    },
  );
}

class _AddCustomerDialog extends StatefulWidget {
  const _AddCustomerDialog({required this.nextId});

  final String nextId;

  @override
  State<_AddCustomerDialog> createState() => _AddCustomerDialogState();
}

class _AddCustomerDialogState extends State<_AddCustomerDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  bool get _canSave => _name.text.trim().isNotEmpty;

  void _save() {
    if (!_canSave) {
      return;
    }
    Navigator.of(context).pop(
      AddCustomerResult(name: _name.text.trim(), phone: _phone.text.trim()),
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
          Icon(Icons.person_add_alt_1_outlined, size: 20, color: tokens.coral),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Add Customer',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: tokens.ink,
              ),
            ),
          ),
          DsStatusPill(
            label: 'ID ${widget.nextId}',
            foreground: tokens.coralPressed,
            background: tokens.coral.withValues(alpha: 0.12),
            border: tokens.coral.withValues(alpha: 0.35),
            dot: false,
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Next sequential ID is assigned automatically.',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 12,
                color: tokens.inkMuted,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
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
              decoration: const InputDecoration(
                labelText: 'Customer Name',
                hintText: 'e.g. Haji Karim',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              onSubmitted: (_) => _save(),
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w500,
                fontSize: 14,
                color: tokens.ink,
              ),
              decoration: const InputDecoration(
                labelText: 'Phone (optional)',
                hintText: '03XX XXXXXXX',
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
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DsPillButton(
                label: 'Save Customer',
                onPressed: _canSave ? _save : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
