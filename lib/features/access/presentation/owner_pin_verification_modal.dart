import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/pin_hasher.dart';
import '../../../core/theme/dispensr_theme.dart';
import '../../../services/database_helper.dart';
import '../data/fingerprint_helper_client.dart';
import '../domain/fingerprint_protocol.dart';
import 'access_controller.dart';
import 'fingerprint_listen_mark.dart';

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
    extends ConsumerState<OwnerPinVerificationModal>
    with WidgetsBindingObserver {
  static const int _pinFallbackAfterMisses = 6;

  final TextEditingController _pin = TextEditingController();
  final FocusNode _pinFocus = FocusNode();
  FingerprintHelperSession? _session;
  String? _error;
  String? _fingerprintNote;
  int _fingerMisses = 0;
  bool _forcePin = false;
  bool _pinRevealed = false;
  bool _listening = false;
  bool _watchStopped = false;
  bool _watchInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_watchFingerprint());
  }

  Future<void> _watchFingerprint() async {
    await ref
        .read(accessControllerProvider.notifier)
        .refreshFingerprintEnrollment();
    if (!mounted || _watchStopped || _watchInFlight) {
      return;
    }
    if (!Platform.isWindows || !FingerprintHelperSession.isSupported) {
      return;
    }
    if (!ref.read(accessControllerProvider).fingerprintEnrolled) {
      return;
    }

    final FingerprintHelperSession session =
        _session ?? FingerprintHelperSession();
    _session = session;
    _watchInFlight = true;
    if (mounted) {
      setState(() {
        _listening = true;
      });
    }
    try {
      await session.start();
      final String? stored = await DatabaseHelper.instance
          .readOwnerFingerprintFmd();
      if (!mounted || _watchStopped || stored == null) {
        return;
      }
      final FingerprintVerifyResult result = await session.verify(<String>[
        stored,
      ], timeoutMs: 120000);
      if (!mounted || _watchStopped) {
        return;
      }
      if (!result.match) {
        final bool incorrect = _isIncorrectScan(result);
        if (incorrect && mounted) {
          final bool revealPin = _fingerMisses + 1 >= _pinFallbackAfterMisses;
          setState(() {
            _fingerMisses += 1;
            _fingerprintNote = 'Fingerprint did not match. Try again.';
            if (revealPin) {
              _pinRevealed = true;
            }
          });
          if (revealPin) {
            _requestPinFocus();
          }
        }
        _watchInFlight = false;
        unawaited(_watchFingerprint());
        return;
      }
      final bool ok = await ref
          .read(accessControllerProvider.notifier)
          .elevateOwnerFromFingerprint();
      if (!mounted || _watchStopped) {
        return;
      }
      if (!ok) {
        setState(() {
          _fingerprintNote =
              ref.read(accessControllerProvider).errorMessage ??
              'Could not unlock with fingerprint.';
        });
        _watchInFlight = false;
        unawaited(_watchFingerprint());
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      _watchInFlight = false;
      if (!mounted || _watchStopped) {
        return;
      }
      setState(() {
        _forcePin = true;
        _error = error is FingerprintHelperException
            ? error.message
            : 'Fingerprint reader is not ready. You can still use the Master PIN.';
      });
      _requestPinFocus();
      await Future<void>.delayed(const Duration(seconds: 2));
      if (mounted && !_watchStopped) {
        unawaited(_watchFingerprint());
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stopSession());
    _pin.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  bool _isIncorrectScan(FingerprintVerifyResult result) {
    if (result.match) {
      return false;
    }
    if ((result.message ?? '').trim().isNotEmpty) {
      return true;
    }
    return result.score > 0;
  }

  void _requestPinFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pinFocus.canRequestFocus) {
        _pinFocus.requestFocus();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_releaseSession());
      return;
    }
    if (state == AppLifecycleState.resumed && mounted && !_watchStopped) {
      unawaited(_watchFingerprint());
    }
  }

  Future<void> _releaseSession() async {
    final FingerprintHelperSession? session = _session;
    _session = null;
    await session?.stop();
  }

  Future<void> _stopSession() async {
    _watchStopped = true;
    await _releaseSession();
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
    final bool showFingerprint =
        Platform.isWindows &&
        FingerprintHelperSession.isSupported &&
        (access.fingerprintEnrolled || _listening);
    final bool showPin = !showFingerprint || _forcePin || _pinRevealed;
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
              showPin ? 'Owner Master PIN' : 'Owner unlock',
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                showFingerprint
                    ? (showPin
                          ? 'Place your finger on the reader, or enter the Master PIN. '
                                'The operator shift stays active.'
                          : 'Place your finger on the reader. It does not have to sit '
                                'in the same spot as enrollment. '
                                'The operator shift stays active.')
                    : 'This screen is locked. Enter the Owner Master PIN to continue. '
                          'The operator shift stays active.',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                  height: 1.4,
                  color: tokens.inkMuted,
                ),
              ),
              if (showFingerprint) ...<Widget>[
                const SizedBox(height: 16),
                Center(
                  child: FingerprintListenMark(
                    listening: _listening,
                    misses: _fingerMisses,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _fingerprintNote ??
                      (_listening ? 'Scanning…' : 'Starting the reader…'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    height: 1.35,
                    color: _fingerprintNote == null ? tokens.ink : tokens.bad,
                  ),
                ),
                if (_listening && _fingerprintNote != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    'Still scanning…',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: tokens.inkMuted,
                    ),
                  ),
                ],
              ],
              if (showPin) ...<Widget>[
                const SizedBox(height: 14),
                TextField(
                  controller: _pin,
                  focusNode: _pinFocus,
                  obscureText: true,
                  autofocus: !showFingerprint,
                  enabled: !access.busy,
                  maxLength: PinHasher.maxPinLength,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  onSubmitted: (_) {
                    if (!access.busy) {
                      unawaited(_submit());
                    }
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
            ],
          ),
        ),
      ),
      actions: <Widget>[
        DsPillButton(
          label: 'Cancel',
          compact: true,
          variant: DsPillVariant.outline,
          onPressed: () {
            unawaited(_stopSession());
            Navigator.of(context).pop(false);
          },
        ),
        if (showPin)
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
