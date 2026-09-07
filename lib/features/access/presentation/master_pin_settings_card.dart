import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/pin_hasher.dart';
import '../../../core/theme/dispensr_theme.dart';
import '../domain/access_policy.dart';
import 'access_controller.dart';

/// Settings form to rotate the Owner Master PIN stored in `app_settings`.
class MasterPinSettingsCard extends ConsumerStatefulWidget {
  const MasterPinSettingsCard({super.key});

  @override
  ConsumerState<MasterPinSettingsCard> createState() =>
      _MasterPinSettingsCardState();
}

class _MasterPinSettingsCardState extends ConsumerState<MasterPinSettingsCard> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNext = true;
  bool _obscureConfirm = true;
  String? _fieldError;
  bool _submitting = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _fieldError = MasterPinChangeInput.validate(
        currentPin: _current.text,
        newPin: _next.text,
        confirmPin: _confirm.text,
        isValidPlainPin: PinHasher.isValidPlainPin,
        minPinLength: PinHasher.minPinLength,
        maxPinLength: PinHasher.maxPinLength,
      );
    });
    if (_fieldError != null) {
      return;
    }
    setState(() {
      _submitting = true;
    });
    try {
      final MasterPinChangeResult result = await ref
          .read(accessControllerProvider.notifier)
          .changeMasterPin(
            currentPin: _current.text,
            newPin: _next.text,
            confirmPin: _confirm.text,
          );
      if (!mounted) {
        return;
      }
      if (!result.isSuccess) {
        setState(() {
          _fieldError = result.message;
          _submitting = false;
        });
        return;
      }
      _current.clear();
      _next.clear();
      _confirm.clear();
      setState(() {
        _fieldError = null;
        _submitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? 'Master PIN updated.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _fieldError = 'Could not update Master PIN. $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final AccessState access = ref.watch(accessControllerProvider);
    final bool enabled = !access.busy && !_submitting;
    return Container(
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.radius20),
        border: Border.all(color: tokens.line),
        boxShadow: tokens.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: tokens.coral.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(tokens.radius12),
                  ),
                  child: Icon(
                    Icons.shield_outlined,
                    size: 18,
                    color: tokens.coralPressed,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Security & Access Control',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: tokens.ink,
                        ),
                      ),
                      Text(
                        'Owner Master PIN unlocks every screen except Sales and Customers',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontWeight: FontWeight.w500,
                          fontSize: 11,
                          color: tokens.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: tokens.line),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _PinField(
                  controller: _current,
                  label: 'Current Master PIN',
                  hint: '4–6 digits',
                  obscure: _obscureCurrent,
                  enabled: enabled,
                  onToggle: () {
                    setState(() {
                      _obscureCurrent = !_obscureCurrent;
                    });
                  },
                ),
                const SizedBox(height: 10),
                _PinField(
                  controller: _next,
                  label: 'New Master PIN',
                  hint: '4–6 digits',
                  obscure: _obscureNext,
                  enabled: enabled,
                  onToggle: () {
                    setState(() {
                      _obscureNext = !_obscureNext;
                    });
                  },
                ),
                const SizedBox(height: 10),
                _PinField(
                  controller: _confirm,
                  label: 'Confirm New Master PIN',
                  hint: 'Re-enter new PIN',
                  obscure: _obscureConfirm,
                  enabled: enabled,
                  onToggle: () {
                    setState(() {
                      _obscureConfirm = !_obscureConfirm;
                    });
                  },
                ),
                if (_fieldError != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(
                    _fieldError!,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 12,
                      color: tokens.bad,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: DsPillButton(
                    label: _submitting ? 'Saving…' : 'Update Master PIN',
                    icon: Icons.lock_reset,
                    onPressed: enabled
                        ? () {
                            unawaited(_submit());
                          }
                        : null,
                    compact: true,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PinField extends StatelessWidget {
  const _PinField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.obscure,
    required this.enabled,
    required this.onToggle,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool obscure;
  final bool enabled;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: obscure,
      enableSuggestions: false,
      autocorrect: false,
      maxLength: PinHasher.maxPinLength,
      keyboardType: TextInputType.number,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
      ],
      style: const TextStyle(fontFamily: 'Roboto', fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
        suffixIcon: IconButton(
          tooltip: obscure ? 'Show' : 'Hide',
          onPressed: onToggle,
          icon: Icon(
            obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          ),
        ),
      ),
    );
  }
}
