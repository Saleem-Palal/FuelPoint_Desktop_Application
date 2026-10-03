import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/security/pin_hasher.dart';
import '../../../core/theme/dispensr_theme.dart';
import '../../../services/database_helper.dart';
import '../data/fingerprint_helper_client.dart';
import '../domain/fingerprint_protocol.dart';
import 'fingerprint_enroll_theater.dart';

/// Enrolls or removes the fingerprint stored on one operator row.
Future<bool> showOperatorFingerprintEnrollmentDialog(
  BuildContext context, {
  required String operatorId,
  required String operatorName,
  required bool enrolled,
}) async {
  final bool? changed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return _OperatorFingerprintEnrollmentDialog(
        operatorId: operatorId,
        operatorName: operatorName,
        enrolled: enrolled,
      );
    },
  );
  return changed == true;
}

class _OperatorFingerprintEnrollmentDialog extends StatefulWidget {
  const _OperatorFingerprintEnrollmentDialog({
    required this.operatorId,
    required this.operatorName,
    required this.enrolled,
  });

  final String operatorId;
  final String operatorName;
  final bool enrolled;

  @override
  State<_OperatorFingerprintEnrollmentDialog> createState() =>
      _OperatorFingerprintEnrollmentDialogState();
}

class _OperatorFingerprintEnrollmentDialogState
    extends State<_OperatorFingerprintEnrollmentDialog>
    with WidgetsBindingObserver {
  final TextEditingController _pin = TextEditingController();
  FingerprintHelperSession? _session;
  FingerprintHelperSession? _probe;
  FingerprintEnrollPhase _phase = FingerprintEnrollPhase.ready;
  int _completed = 0;
  String? _message;
  String? _error;
  bool _obscure = true;
  bool _pinVerified = false;
  bool _readerReady = false;
  late bool _enrolled;

  @override
  void initState() {
    super.initState();
    _enrolled = widget.enrolled;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_probeReader());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stopSession());
    _pin.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_stopSession());
    }
  }

  Future<void> _stopSession() async {
    final FingerprintHelperSession? session = _session;
    _session = null;
    await session?.stop();
    await _stopProbe();
  }

  Future<void> _stopProbe() async {
    final FingerprintHelperSession? probe = _probe;
    _probe = null;
    await probe?.stop();
  }

  Future<void> _probeReader() async {
    if (!Platform.isWindows || !FingerprintHelperSession.isSupported) {
      return;
    }
    final FingerprintHelperSession session = FingerprintHelperSession();
    _probe = session;
    try {
      await session.start();
      final FingerprintHealth health = await session.health();
      if (!mounted || !identical(_probe, session)) {
        return;
      }
      setState(() {
        _readerReady = health.hasReader;
      });
    } catch (_) {
      if (!mounted || !identical(_probe, session)) {
        return;
      }
      setState(() {
        _readerReady = false;
      });
    } finally {
      if (identical(_probe, session)) {
        _probe = null;
      }
      await session.stop();
    }
  }

  Future<bool> _confirmPin() async {
    if (_pinVerified) {
      return true;
    }
    final bool pinOk = await DatabaseHelper.instance.verifyOperatorPin(
      operatorId: widget.operatorId,
      pin: _pin.text,
    );
    if (!mounted) {
      return false;
    }
    if (!pinOk) {
      setState(() {
        _phase = FingerprintEnrollPhase.ready;
        _error = 'PIN does not match ${widget.operatorName}.';
      });
      return false;
    }
    _pinVerified = true;
    return true;
  }

  Future<void> _enroll() async {
    setState(() {
      _error = null;
      _message = null;
      _completed = 0;
    });
    if (!await _confirmPin()) {
      return;
    }
    if (!mounted) {
      return;
    }
    await _stopProbe();
    setState(() {
      _phase = FingerprintEnrollPhase.scanning;
      _message = 'Starting the reader…';
    });
    final FingerprintHelperSession session = FingerprintHelperSession();
    _session = session;
    try {
      await session.start();
      final FingerprintHealth health = await session.health();
      if (!health.hasReader) {
        throw const FingerprintHelperException(
          code: 'NO_READER',
          message: 'Fingerprint reader is not connected.',
        );
      }
      final int total = FingerprintProtocol.enrollScanCount;
      final List<String> scans = <String>[];
      for (int i = 0; i < total; i++) {
        if (!mounted) {
          return;
        }
        setState(() {
          _phase = FingerprintEnrollPhase.scanning;
          _completed = i;
          _message = i == 0
              ? 'Place ${widget.operatorName}\'s finger flat on the reader.'
              : 'Lift, then place the same finger again.';
        });
        scans.add(await session.capture());
        if (!mounted) {
          return;
        }
        setState(() {
          _completed = i + 1;
        });
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = FingerprintEnrollPhase.saving;
        _message = 'Saving the fingerprint…';
      });
      final String enrolled = await session.enroll(scans);
      await DatabaseHelper.instance.writeOperatorFingerprint(
        operatorId: widget.operatorId,
        protectedFmd: enrolled,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = FingerprintEnrollPhase.done;
        _enrolled = true;
        _completed = total;
        _message = 'Fingerprint enrolled for ${widget.operatorName}.';
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = FingerprintEnrollPhase.failed;
        _message = null;
        _error = error is FingerprintHelperException
            ? error.message
            : 'Could not enroll fingerprint. $error';
      });
    } finally {
      await _stopSession();
    }
  }

  Future<void> _remove() async {
    setState(() {
      _error = null;
      _message = null;
    });
    if (!await _confirmPin()) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _phase = FingerprintEnrollPhase.saving;
      _message = 'Removing the fingerprint…';
    });
    try {
      await DatabaseHelper.instance.clearOperatorFingerprint(widget.operatorId);
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = FingerprintEnrollPhase.done;
        _enrolled = false;
        _completed = 0;
        _message = 'Fingerprint removed for ${widget.operatorName}.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = FingerprintEnrollPhase.failed;
        _message = null;
        _error = 'Could not remove fingerprint. $error';
      });
    }
  }

  void _close() {
    unawaited(_stopSession());
    Navigator.of(context).pop(_phase == FingerprintEnrollPhase.done);
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final bool working =
        _phase == FingerprintEnrollPhase.scanning ||
        _phase == FingerprintEnrollPhase.saving;
    final bool finished = _phase == FingerprintEnrollPhase.done;
    final int total = FingerprintProtocol.enrollScanCount;
    final String readerLine = FingerprintHelperSession.isSupported
        ? (_readerReady
              ? 'DigitalPersona reader is ready.'
              : 'Plug in the fingerprint reader, then start.')
        : 'Fingerprint helper is not installed on this PC.';
    return Dialog(
      backgroundColor: tokens.card,
      surfaceTintColor: tokens.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius20),
        side: BorderSide(color: tokens.line),
      ),
      child: SizedBox(
        width: 440,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Fingerprint · ${widget.operatorName}',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: tokens.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _enrolled
                    ? 'A new scan replaces the fingerprint on file.'
                    : 'Four presses of the same finger.',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                  color: tokens.inkMuted,
                ),
              ),
              const SizedBox(height: 8),
              FingerprintEnrollTheater(
                phase: _phase,
                completed: _completed,
                total: total,
              ),
              const SizedBox(height: 8),
              Text(
                _error ?? _message ?? readerLine,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  height: 1.35,
                  color: _error != null
                      ? tokens.bad
                      : (finished ? tokens.good : tokens.ink),
                ),
              ),
              if (!working && !finished) ...<Widget>[
                const SizedBox(height: 14),
                TextField(
                  controller: _pin,
                  obscureText: _obscure,
                  autofocus: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  maxLength: PinHasher.maxPinLength,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  onSubmitted: (_) {
                    if (!working) {
                      unawaited(_enroll());
                    }
                  },
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    letterSpacing: 4,
                    color: tokens.ink,
                  ),
                  decoration: InputDecoration(
                    labelText: '${widget.operatorName} PIN',
                    hintText: 'Required to enroll or remove',
                    counterText: '',
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Show' : 'Hide',
                      onPressed: () {
                        setState(() {
                          _obscure = !_obscure;
                        });
                      },
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  if (!finished && _enrolled && !working) ...<Widget>[
                    DsPillButton(
                      label: 'Remove',
                      icon: Icons.delete_outline,
                      compact: true,
                      variant: DsPillVariant.outline,
                      onPressed: () {
                        unawaited(_remove());
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                  DsPillButton(
                    label: finished ? 'Close' : 'Cancel',
                    compact: true,
                    variant: DsPillVariant.outline,
                    onPressed: _close,
                  ),
                  if (!finished) ...<Widget>[
                    const SizedBox(width: 8),
                    DsPillButton(
                      label: working
                          ? (_phase == FingerprintEnrollPhase.saving
                                ? 'Saving…'
                                : 'Scanning…')
                          : (_enrolled ? 'Re-enroll' : 'Start enrollment'),
                      icon: Icons.fingerprint,
                      compact: true,
                      onPressed: working
                          ? null
                          : () {
                              unawaited(_enroll());
                            },
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
