import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/pin_hasher.dart';
import '../../../core/theme/dispensr_theme.dart';
import 'access_controller.dart';

Future<bool> showOwnerPinVerificationModal(BuildContext context) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return const OwnerPinVerificationModal();
    },
  );
  return ok == true;
}

class OwnerPinVerificationModal extends ConsumerStatefulWidget {
  const OwnerPinVerificationModal({super.key});

  @override
  ConsumerState<OwnerPinVerificationModal> createState() =>
      _OwnerPinVerificationModalState();
}

class _OwnerPinVerificationModalState
    extends ConsumerState<OwnerPinVerificationModal> {
  final TextEditingController _pin = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String pin = _pin.text.trim();
    if (!PinHasher.isValidPlainPin(pin)) {
      setState(() {
        _error =
            'Enter the ${PinHasher.minPinLength}–${PinHasher.maxPinLength} digit Owner Master PIN.';
      });
      return;
    }
    final bool ok = await ref
        .read(accessControllerProvider.notifier)
        .verifyOwnerMasterPin(pin);
    if (!mounted) {
      return;
    }
    if (!ok) {
      setState(() {
        _error =
            ref.read(accessControllerProvider).errorMessage ??
            'Incorrect Master PIN. Try again.';
      });
      _pin.clear();
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final AccessState access = ref.watch(accessControllerProvider);
    return AlertDialog(
      backgroundColor: tokens.card,
      surfaceTintColor: tokens.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius20),
        side: BorderSide(color: tokens.line),
      ),
      title: Row(
        children: <Widget>[
          Icon(Icons.lock_outline, color: tokens.coralPressed, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Owner Master PIN',
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'This screen is locked. Enter the Owner Master PIN to continue. '
              'The manager shift stays active.',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w500,
                fontSize: 13,
                height: 1.4,
                color: tokens.inkMuted,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _pin,
              obscureText: true,
              autofocus: true,
              enabled: !access.busy,
              maxLength: PinHasher.maxPinLength,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              onSubmitted: (_) {
                unawaited(_submit());
              },
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
                labelText: 'Owner Master PIN',
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
          compact: true,
          variant: DsPillVariant.outline,
          onPressed: access.busy
              ? null
              : () => Navigator.of(context).pop(false),
        ),
        DsPillButton(
          label: access.busy ? 'Verifying…' : 'Unlock',
          compact: true,
          icon: Icons.lock_open_outlined,
          onPressed: access.busy
              ? null
              : () {
                  unawaited(_submit());
                },
        ),
      ],
    );
  }
}
