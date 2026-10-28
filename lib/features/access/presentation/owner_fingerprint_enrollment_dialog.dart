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
import '../domain/owner_fingerprint_gallery.dart';
import 'access_controller.dart';
import 'fingerprint_enroll_theater.dart';

/// Opens the owner fingerprint enroll / remove dialog.
Future<void> showOwnerFingerprintEnrollmentDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return const _OwnerFingerprintEnrollmentDialog();
    },
  );
}

class _OwnerFingerprintEnrollmentDialog extends ConsumerStatefulWidget {
  const _OwnerFingerprintEnrollmentDialog();

  @override
  ConsumerState<_OwnerFingerprintEnrollmentDialog> createState() =>
      _OwnerFingerprintEnrollmentDialogState();
}

class _OwnerFingerprintEnrollmentDialogState
    extends ConsumerState<_OwnerFingerprintEnrollmentDialog>
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
  List<String> _fingers = <String>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadFingers());
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

  Future<void> _loadFingers() async {
    final List<String> fingers = await DatabaseHelper.instance
        .readOwnerFingerprintFmds();
    if (!mounted) {
      return;
    }
    setState(() {
      _fingers = fingers;
    });
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
    final bool pinOk = await ref
        .read(accessControllerProvider.notifier)
        .confirmOwnerMasterPin(_pin.text);
    if (!mounted) {
      return false;
    }
    if (!pinOk) {
      setState(() {
        _phase = FingerprintEnrollPhase.ready;
        _error =
            ref.read(accessControllerProvider).errorMessage ??
            'Incorrect Master PIN. Try again.';
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
    if (_fingers.length >= OwnerFingerprintGallery.maxFingers) {
      setState(() {
        _error =
            'The owner already has ${OwnerFingerprintGallery.maxFingers} fingerprints enrolled. Remove one before adding another.';
      });
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
      if (mounted) {
        setState(() {
          _readerReady = true;
        });
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
              ? 'Place your finger flat on the reader.'
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
      final int saved = await DatabaseHelper.instance.addOwnerFingerprint(
        protectedFmd: enrolled,
      );
      await _loadFingers();
      await ref
          .read(accessControllerProvider.notifier)
          .refreshFingerprintEnrollment();
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = FingerprintEnrollPhase.done;
        _completed = total;
        _message = 'Finger $saved enrolled.';
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

  Future<void> _removeAt(int index) async {
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
      _message = 'Removing finger ${index + 1}…';
    });
    try {
      await DatabaseHelper.instance.removeOwnerFingerprintAt(index);
      await _loadFingers();
      await ref
          .read(accessControllerProvider.notifier)
          .refreshFingerprintEnrollment();
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = FingerprintEnrollPhase.ready;
        _completed = 0;
        _message = 'Finger ${index + 1} removed.';
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

  Future<void> _removeAll() async {
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
      _message = 'Removing all fingerprints…';
    });
    try {
      await DatabaseHelper.instance.clearOwnerFingerprint();
      await _loadFingers();
      await ref
          .read(accessControllerProvider.notifier)
          .refreshFingerprintEnrollment();
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = FingerprintEnrollPhase.done;
        _completed = 0;
        _message = 'All owner fingerprints removed.';
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

  void _prepareAnother() {
    setState(() {
      _phase = FingerprintEnrollPhase.ready;
      _completed = 0;
      _message = null;
      _error = null;
    });
  }

  void _close() {
    unawaited(_stopSession());
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final AccessState access = ref.watch(accessControllerProvider);
    final bool enrolled = _fingers.isNotEmpty;
    final bool canAdd = _fingers.length < OwnerFingerprintGallery.maxFingers;
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 680),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: tokens.coral.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(tokens.radius12),
                      ),
                      child: Icon(
                        Icons.fingerprint,
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
                            'Fingerprint enrollment',
                            style: TextStyle(
                              fontFamily: 'Roboto',
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: tokens.ink,
                            ),
                          ),
                          Text(
                            _fingers.isEmpty
                                ? 'Four presses of the same finger. You can add more after this one.'
                                : '${_fingers.length} of ${OwnerFingerprintGallery.maxFingers} fingers enrolled. A new scan adds another finger.',
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
                if (_fingers.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  for (int i = 0; i < _fingers.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _EnrolledFingerRow(
                        label: 'Finger ${i + 1}',
                        enabled: !working && !access.busy,
                        onRemove: () {
                          unawaited(_removeAt(i));
                        },
                      ),
                    ),
                ],
                const SizedBox(height: 8),
                FingerprintEnrollTheater(
                  phase: _phase,
                  completed: _completed,
                  total: total,
                ),
                const SizedBox(height: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Text(
                    _error ?? _message ?? readerLine,
                    key: ValueKey<String>(_error ?? _message ?? readerLine),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      height: 1.35,
                      color: _error != null
                          ? tokens.bad
                          : (_phase == FingerprintEnrollPhase.done
                                ? tokens.good
                                : tokens.ink),
                    ),
                  ),
                ),
                if (!working && !finished) ...<Widget>[
                  const SizedBox(height: 14),
                  TextField(
                    controller: _pin,
                    enabled: !working && !access.busy,
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
                      labelText: 'Current Master PIN',
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
                    if (!finished && enrolled && !working) ...<Widget>[
                      DsPillButton(
                        label: 'Remove all',
                        icon: Icons.delete_outline,
                        compact: true,
                        variant: DsPillVariant.outline,
                        onPressed: access.busy
                            ? null
                            : () {
                                unawaited(_removeAll());
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
                    if (finished && canAdd) ...<Widget>[
                      const SizedBox(width: 8),
                      DsPillButton(
                        label: 'Add another finger',
                        icon: Icons.fingerprint,
                        compact: true,
                        onPressed: access.busy ? null : _prepareAnother,
                      ),
                    ],
                    if (!finished && canAdd) ...<Widget>[
                      const SizedBox(width: 8),
                      DsPillButton(
                        label: working
                            ? (_phase == FingerprintEnrollPhase.saving
                                  ? 'Saving…'
                                  : 'Scanning…')
                            : (enrolled ? 'Add finger' : 'Start enrollment'),
                        icon: Icons.fingerprint,
                        compact: true,
                        onPressed: working || access.busy
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
      ),
    );
  }
}

class _EnrolledFingerRow extends StatelessWidget {
  const _EnrolledFingerRow({
    required this.label,
    required this.enabled,
    required this.onRemove,
  });

  final String label;
  final bool enabled;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(tokens.radius12),
        border: Border.all(color: tokens.line),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        child: Row(
          children: <Widget>[
            Icon(Icons.fingerprint, size: 18, color: tokens.coralPressed),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: tokens.ink,
                ),
              ),
            ),
            TextButton(
              onPressed: enabled ? onRemove : null,
              child: const Text('Remove'),
            ),
          ],
        ),
      ),
    );
  }
}
