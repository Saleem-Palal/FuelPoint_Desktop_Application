import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/dispensr_theme.dart';

/// Pulsing scan mark for an unlock listen. A miss flashes red, then the
/// rings go back to scanning so the wait for the right finger stays visible.
class FingerprintListenMark extends StatefulWidget {
  const FingerprintListenMark({
    required this.listening,
    required this.misses,
    this.matched = false,
    this.diameter = 148,
  });

  final bool listening;
  final int misses;
  final bool matched;
  final double diameter;

  @override
  State<FingerprintListenMark> createState() => _FingerprintListenMarkState();
}

class _FingerprintListenMarkState extends State<FingerprintListenMark>
    with TickerProviderStateMixin {
  late final AnimationController _pulse;
  late final AnimationController _sweep;
  late final AnimationController _flash;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _sweep = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _flash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    );
    _syncSweep();
  }

  @override
  void didUpdateWidget(covariant FingerprintListenMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSweep();
    if (widget.misses > oldWidget.misses) {
      _flash.forward(from: 0);
    }
  }

  void _syncSweep() {
    final bool live = widget.listening && !widget.matched;
    if (live) {
      if (!_sweep.isAnimating) {
        _sweep.repeat();
      }
      return;
    }
    if (_sweep.isAnimating) {
      _sweep.stop();
    }
    _sweep.value = widget.matched ? 1 : 0;
  }

  @override
  void dispose() {
    _pulse.dispose();
    _sweep.dispose();
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_pulse, _sweep, _flash]),
      builder: (BuildContext context, Widget? child) {
        final double flash = 1 - Curves.easeOut.transform(_flash.value);
        final bool flashing = _flash.isAnimating;
        final Color accent = widget.matched
            ? tokens.good
            : (flashing
                  ? Color.lerp(tokens.coral, tokens.bad, flash) ?? tokens.bad
                  : tokens.coral);
        final double shake = flashing
            ? math.sin(_flash.value * math.pi * 5) * 7 * (1 - _flash.value)
            : 0;
        return Column(
          children: <Widget>[
            SizedBox(
              width: widget.diameter,
              height: widget.diameter,
              child: FittedBox(
                child: SizedBox(
                  width: 148,
                  height: 148,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      CustomPaint(
                        size: const Size.square(148),
                        painter: _ListenRingPainter(
                          t: _pulse.value,
                          sweep: _sweep.value,
                          color: accent,
                          scanning: widget.listening && !widget.matched,
                          matched: widget.matched,
                        ),
                      ),
                      Transform.translate(
                        offset: Offset(shake, 0),
                        child: ClipOval(
                          child: SizedBox(
                            width: 86,
                            height: 86,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.14),
                                shape: BoxShape.circle,
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: <Widget>[
                                  Icon(
                                    widget.matched
                                        ? Icons.check_rounded
                                        : Icons.fingerprint,
                                    size: 46,
                                    color: accent,
                                  ),
                                  if (widget.listening && !widget.matched)
                                    Align(
                                      alignment: Alignment(
                                        0,
                                        -1 + (2 * _sweep.value),
                                      ),
                                      child: Container(
                                        height: 10,
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: <Color>[
                                              accent.withValues(alpha: 0),
                                              accent.withValues(alpha: 0.9),
                                              accent.withValues(alpha: 0),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ListenRingPainter extends CustomPainter {
  const _ListenRingPainter({
    required this.t,
    required this.sweep,
    required this.color,
    required this.scanning,
    required this.matched,
  });

  final double t;
  final double sweep;
  final Color color;
  final bool scanning;
  final bool matched;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    if (matched) {
      final Paint ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = color.withValues(alpha: 0.9);
      canvas.drawCircle(center, 52, ring);
      return;
    }

    for (int i = 0; i < 3; i++) {
      final double local = (t + (i / 3)) % 1;
      final double radius = 30 + (local * 40);
      final Paint paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withValues(
          alpha: (1 - local) * (scanning ? 0.6 : 0.28),
        );
      canvas.drawCircle(center, radius, paint);
    }

    if (!scanning) {
      return;
    }
    final Paint arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 56),
      (sweep * math.pi * 2) - 1.2,
      1.2,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _ListenRingPainter oldDelegate) {
    return t != oldDelegate.t ||
        sweep != oldDelegate.sweep ||
        color != oldDelegate.color ||
        scanning != oldDelegate.scanning ||
        matched != oldDelegate.matched;
  }
}
