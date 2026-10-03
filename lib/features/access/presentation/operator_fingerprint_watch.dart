import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/theme/dispensr_theme.dart';
import '../../../services/database_helper.dart';
import '../data/fingerprint_helper_client.dart';
import '../domain/fingerprint_protocol.dart';
import 'fingerprint_listen_mark.dart';

/// Listens for one operator's fingerprint. PIN stays hidden until
/// [FingerprintProtocol.operatorPinFallbackAfterMisses] real mismatches.
class OperatorFingerprintWatch extends StatefulWidget {
  const OperatorFingerprintWatch({
    super.key,
    required this.operatorId,
    required this.onMatched,
    required this.onShowPin,
    this.enabled = true,
    this.onDark = false,
    this.showScanMark = false,
  });

  final String? operatorId;
  final VoidCallback onMatched;
  final ValueChanged<bool> onShowPin;
  final bool enabled;
  final bool onDark;
  final bool showScanMark;

  @override
  State<OperatorFingerprintWatch> createState() =>
      _OperatorFingerprintWatchState();
}

class _OperatorFingerprintWatchState extends State<OperatorFingerprintWatch>
    with WidgetsBindingObserver {
  FingerprintHelperSession? _session;
  int _generation = 0;
  int _misses = 0;
  bool _listening = false;
  bool _armed = false;
  bool _matched = false;
  bool? _announcedPin;
  String? _note;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_arm());
  }

  @override
  void didUpdateWidget(covariant OperatorFingerprintWatch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.operatorId != widget.operatorId ||
        oldWidget.enabled != widget.enabled) {
      unawaited(_arm());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation += 1;
    unawaited(_stopSession());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _generation += 1;
      unawaited(_stopSession());
      return;
    }
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(_arm());
    }
  }

  Future<void> _stopSession() async {
    final FingerprintHelperSession? session = _session;
    _session = null;
    await session?.stop();
  }

  void _announcePin(bool show) {
    if (!mounted || _announcedPin == show) {
      return;
    }
    _announcedPin = show;
    widget.onShowPin(show);
  }

  Future<void> _arm() async {
    final int generation = ++_generation;
    await _stopSession();
    _misses = 0;
    _announcedPin = null;
    _matched = false;
    if (mounted) {
      setState(() {
        _note = null;
        _listening = false;
        _armed = false;
      });
    }
    final String? operatorId = widget.operatorId?.trim();
    if (!widget.enabled ||
        operatorId == null ||
        operatorId.isEmpty ||
        !Platform.isWindows ||
        !FingerprintHelperSession.isSupported) {
      _announcePin(true);
      return;
    }

    final String? stored = await DatabaseHelper.instance
        .readOperatorFingerprintFmd(operatorId);
    if (!mounted || generation != _generation) {
      return;
    }
    if (stored == null) {
      _announcePin(true);
      return;
    }

    _announcePin(false);
    final FingerprintHelperSession session = FingerprintHelperSession();
    _session = session;
    if (mounted) {
      setState(() {
        _listening = true;
        _armed = true;
      });
    }
    try {
      await session.start();
      while (mounted && generation == _generation && _session == session) {
        final FingerprintVerifyResult result = await session.verify(<String>[
          stored,
        ], timeoutMs: 120000);
        if (!mounted || generation != _generation) {
          return;
        }
        if (result.match) {
          _generation += 1;
          await _stopSession();
          if (mounted) {
            setState(() {
              _listening = false;
              _matched = true;
              _note = null;
            });
          }
          widget.onMatched();
          return;
        }
        if (!FingerprintProtocol.incorrectFingerprint(
          match: result.match,
          score: result.score,
          message: result.message,
        )) {
          continue;
        }
        _misses += 1;
        if (mounted) {
          setState(() {
            _note = FingerprintProtocol.fingerprintMismatchNote(result.message);
          });
        }
        if (_misses >= FingerprintProtocol.operatorPinFallbackAfterMisses) {
          _announcePin(true);
        }
      }
    } catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _listening = false;
        _note = error is FingerprintHelperException
            ? error.message
            : 'Fingerprint reader is not ready.';
      });
      _announcePin(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_armed && _note == null) {
      return const SizedBox.shrink();
    }
    final DispensrTokens tokens = DispensrTokens.of(context);
    final Color ink = widget.onDark ? const Color(0xFFFFFFFF) : tokens.ink;
    final Color accent = widget.onDark
        ? const Color(0xFF7CC4FF)
        : tokens.coralPressed;
    final Color bad = widget.onDark ? const Color(0xFFFF8A80) : tokens.bad;
    final Color muted = widget.onDark
        ? const Color(0xFFB7C3D4)
        : tokens.inkMuted;
    final Color good = widget.onDark ? const Color(0xFF7DCEA0) : tokens.good;
    if (widget.showScanMark) {
      final String status = _matched
          ? 'Fingerprint matched.'
          : (_note ??
                (_listening ? 'Scanning…' : 'Fingerprint reader is starting…'));
      final bool miss = _note != null && !_matched;
      return Column(
        children: <Widget>[
          FingerprintListenMark(
            listening: _listening,
            misses: _misses,
            matched: _matched,
            diameter: 132,
          ),
          const SizedBox(height: 8),
          Text(
            status,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w600,
              fontSize: 13,
              height: 1.35,
              color: _matched ? good : (miss ? bad : ink),
            ),
          ),
          if (_listening && miss) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              'Still scanning…',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: muted,
              ),
            ),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.fingerprint, size: 18, color: accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _matched
                    ? 'Fingerprint matched.'
                    : (_listening
                          ? 'Listening for a fingerprint…'
                          : 'Fingerprint reader is starting…'),
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: _matched
                      ? (widget.onDark
                            ? const Color(0xFF7DCEA0)
                            : DispensrTokens.of(context).good)
                      : ink,
                ),
              ),
            ),
          ],
        ),
        if (_note != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            _note!,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w600,
              fontSize: 13,
              height: 1.35,
              color: bad,
            ),
          ),
        ],
      ],
    );
  }
}
