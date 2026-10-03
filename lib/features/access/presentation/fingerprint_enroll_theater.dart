import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/dispensr_theme.dart';

enum FingerprintEnrollPhase { ready, scanning, saving, done, failed }

/// Pulsing rings, a moving scan line, and a four-step press meter.
class FingerprintEnrollTheater extends StatefulWidget {
  const FingerprintEnrollTheater({
    required this.phase,
    required this.completed,
    required this.total,
  });

  final FingerprintEnrollPhase phase;
  final int completed;
  final int total;

  @override
  State<FingerprintEnrollTheater> createState() =>
      _FingerprintEnrollTheaterState();
}

class _FingerprintEnrollTheaterState extends State<FingerprintEnrollTheater>
    with TickerProviderStateMixin {
  late final AnimationController _pulse;
  late final AnimationController _sweep;
  late final AnimationController _pop;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _sweep = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _syncSweep();
  }

  @override
  void didUpdateWidget(covariant FingerprintEnrollTheater oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSweep();
    if (widget.completed > oldWidget.completed) {
      _pop.forward(from: 0);
    }
  }

  void _syncSweep() {
    final bool live = widget.phase == FingerprintEnrollPhase.scanning;
    if (live) {
      if (!_sweep.isAnimating) {
        _sweep.repeat();
      }
      return;
    }
    if (_sweep.isAnimating) {
      _sweep.stop();
    }
    _sweep.value = widget.phase == FingerprintEnrollPhase.done ? 1 : 0;
  }

  @override
  void dispose() {
    _pulse.dispose();
    _sweep.dispose();
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final Color accent = switch (widget.phase) {
      FingerprintEnrollPhase.done => tokens.good,
      FingerprintEnrollPhase.failed => tokens.bad,
      _ => tokens.coral,
    };
    final bool scanning = widget.phase == FingerprintEnrollPhase.scanning;
    return Column(
      children: <Widget>[
        SizedBox(
          width: 168,
          height: 168,
          child: AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[_pulse, _sweep, _pop]),
            builder: (BuildContext context, Widget? child) {
              final double pop = Curves.easeOutBack.transform(_pop.value);
              final double scale = 1 + (0.08 * (1 - (pop - 0.5).abs() * 2));
              return Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  CustomPaint(
                    size: const Size.square(168),
                    painter: _RingPainter(
                      t: _pulse.value,
                      sweep: _sweep.value,
                      color: accent,
                      scanning: scanning,
                      settled: widget.phase == FingerprintEnrollPhase.done,
                    ),
                  ),
                  Transform.scale(
                    scale: widget.completed > 0 && _pop.value > 0 ? scale : 1,
                    child: child,
                  ),
                ],
              );
            },
            child: ClipOval(
              child: SizedBox(
                width: 96,
                height: 96,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      Icon(
                        widget.phase == FingerprintEnrollPhase.done
                            ? Icons.check_rounded
                            : Icons.fingerprint,
                        size: 52,
                        color: accent,
                      ),
                      if (scanning)
                        AnimatedBuilder(
                          animation: _sweep,
                          builder: (BuildContext context, Widget? child) {
                            return Align(
                              alignment: Alignment(0, -1 + (2 * _sweep.value)),
                              child: child,
                            );
                          },
                          child: Container(
                            height: 10,
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: <Color>[
                                  accent.withValues(alpha: 0),
                                  accent.withValues(alpha: 0.85),
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
        ),
        const SizedBox(height: 4),
        Row(
          children: <Widget>[
            for (int i = 0; i < widget.total; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: _ScanTick(
                    filled: i < widget.completed,
                    active: scanning && i == widget.completed,
                    color: accent,
                    pulse: _pulse,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          widget.phase == FingerprintEnrollPhase.done && widget.completed == 0
              ? 'Removed'
              : '${widget.completed.clamp(0, widget.total)} of ${widget.total}',
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w600,
            fontSize: 11,
            letterSpacing: 0.4,
            color: tokens.inkMuted,
          ),
        ),
      ],
    );
  }
}

class _ScanTick extends StatelessWidget {
  const _ScanTick({
    required this.filled,
    required this.active,
    required this.color,
    required this.pulse,
  });

  final bool filled;
  final bool active;
  final Color color;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    if (!active) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
        height: 6,
        decoration: BoxDecoration(
          color: filled ? color : tokens.line,
          borderRadius: BorderRadius.circular(99),
        ),
      );
    }
    return AnimatedBuilder(
      animation: pulse,
      builder: (BuildContext context, Widget? child) {
        final double glow =
            0.45 + (0.55 * ((math.sin(pulse.value * math.pi * 2) + 1) / 2));
        return Container(
          height: 6,
          decoration: BoxDecoration(
            color: color.withValues(alpha: glow),
            borderRadius: BorderRadius.circular(99),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.t,
    required this.sweep,
    required this.color,
    required this.scanning,
    required this.settled,
  });

  final double t;
  final double sweep;
  final Color color;
  final bool scanning;
  final bool settled;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    if (settled) {
      final Paint ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = color.withValues(alpha: 0.85);
      canvas.drawCircle(center, 58, ring);
      canvas.drawCircle(
        center,
        70,
        ring..color = color.withValues(alpha: 0.35),
      );
      return;
    }

    for (int i = 0; i < 3; i++) {
      final double local = (t + (i / 3)) % 1;
      final double radius = 34 + (local * 46);
      final Paint paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withValues(alpha: (1 - local) * 0.55);
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
      Rect.fromCircle(center: center, radius: 62),
      (sweep * math.pi * 2) - 1.2,
      1.15,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return t != oldDelegate.t ||
        sweep != oldDelegate.sweep ||
        color != oldDelegate.color ||
        scanning != oldDelegate.scanning ||
        settled != oldDelegate.settled;
  }
}
