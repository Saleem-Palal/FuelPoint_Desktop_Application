import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/widgets/segment_lcd.dart';
import '../../../../features/station/domain/dispenser_models.dart';
import 'generate_receipt.dart';

class UnitReceiptOverlay extends StatefulWidget {
  const UnitReceiptOverlay({
    super.key,
    required this.txn,
    required this.onDismiss,
  });

  final SaleTransaction txn;
  final VoidCallback onDismiss;

  @override
  State<UnitReceiptOverlay> createState() => _UnitReceiptOverlayState();
}

class _UnitReceiptOverlayState extends State<UnitReceiptOverlay> {
  final GlobalKey _previewKey = GlobalKey();

  ReceiptTicket get ticket => ReceiptTicket.fromTransaction(widget.txn);

  Future<void> _run(
    Future<void> Function() action,
    String okMessage,
  ) async {
    try {
      await action();
    } catch (error, stack) {
      debugPrint('Receipt action failed: $error\n$stack');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not complete receipt. $error')),
      );
      return;
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(okMessage)));
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Material(
      color: colors.scrim.withValues(alpha: 0.62),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              tooltip: 'Close receipt',
              onPressed: widget.onDismiss,
              color: colors.onInverseSurface,
              icon: const Icon(Icons.close, size: 18),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: FittedBox(
                fit: BoxFit.contain,
                child: RepaintBoundary(
                  key: _previewKey,
                  child: ThermalReceiptView(ticket: ticket),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _ReceiptActionButton(
                  label: 'Print',
                  icon: Icons.print_outlined,
                  color: const Color(ColorData.printTerracotta),
                  onPressed: () {
                    unawaited(
                      _run(
                        () => ReceiptGenerator.instance.printPreview(
                          _previewKey,
                          ticket,
                        ),
                        'Receipt sent to printer',
                      ),
                    );
                  },
                ),
                const SizedBox(height: 6),
                _ReceiptActionButton(
                  label: 'WhatsApp',
                  icon: Icons.chat_outlined,
                  color: const Color(ColorData.whatsAppGreen),
                  onPressed: () {
                    unawaited(
                      _run(
                        () => ReceiptGenerator.instance.sharePreview(
                          _previewKey,
                          ticket,
                        ),
                        'Receipt shared',
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact thermal slip. Reuse for the live preview and print/export views.
class ThermalReceiptView extends StatelessWidget {
  const ThermalReceiptView({super.key, required this.ticket});

  static const double width = 272;

  static const Color _paper = Color(ColorData.paper);
  static const Color _ink = Color(ColorData.ink);
  static const Color _muted = Color(0xFF6F6560);
  static const Color _steel = Color(ColorData.steel);
  static const Color _rule = Color(0x06211C1A);

  final ReceiptTicket ticket;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: _paper,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0x29211C1A),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _SquareDashEdge(),
          CustomPaint(
            painter: const _PaperRulePainter(color: _rule),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _UrduText(
                    ReceiptCopy.stationNameUrdu,
                    size: 19,
                    weight: FontWeight.w700,
                    color: _ink,
                    height: 1.55,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Text(
                        'Date  ${ticket.dateLabel}',
                        style: const TextStyle(
                          fontFamily: ReceiptCopy.latinFontFamily,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                          color: _ink,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: _steel,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        ticket.unitBadge,
                        style: const TextStyle(
                          fontFamily: ReceiptCopy.latinFontFamily,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                          color: _steel,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: <Widget>[
                      Text(
                        'Time  ${ticket.timeLabel}',
                        style: const TextStyle(
                          fontFamily: ReceiptCopy.latinFontFamily,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                          color: _ink,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Token  ${ticket.tokenLabel}',
                        style: const TextStyle(
                          fontFamily: ReceiptCopy.latinFontFamily,
                          fontWeight: FontWeight.w500,
                          fontSize: 11,
                          color: _ink,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SegmentLcd.receipt(
                    lines: <SegmentLcdLine>[
                      SegmentLcdLine(label: 'AMOUNT', value: ticket.amount),
                      SegmentLcdLine(label: 'LITERS', value: ticket.liters),
                      SegmentLcdLine(label: 'RATE', value: ticket.rate),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _DetailRow(label: 'Customer', value: ticket.customerName),
                  _DetailRow(
                    label: 'Vehicle No.',
                    value: ticket.vehicleDisplay,
                  ),
                  _DetailRow(label: 'Payment', value: ticket.paymentLabel),
                  _DetailRow(label: 'Cashier', value: ticket.cashierName),
                  const SizedBox(height: 8),
                  const _DashRule(color: Color(0x55211C1A)),
                  const SizedBox(height: 8),
                  _UrduText(
                    ReceiptCopy.addressUrdu,
                    size: 11,
                    color: _ink,
                    height: 1.7,
                  ),
                  const SizedBox(height: 4),
                  _UrduText(
                    ReceiptCopy.staffLineUrdu,
                    size: 10.5,
                    color: _ink,
                    height: 1.7,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    ReceiptCopy.stationPhone,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: ReceiptCopy.latinFontFamily,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _UrduText(
                    ReceiptCopy.thankYouUrdu,
                    size: 12,
                    weight: FontWeight.w700,
                    color: _ink,
                    height: 1.7,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    ReceiptCopy.developerFooter,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: ReceiptCopy.latinFontFamily,
                      fontWeight: FontWeight.w500,
                      fontSize: 8.5,
                      color: _muted,
                    ),
                  ),
                  const SizedBox(height: 3),
                  _UrduText(
                    ReceiptCopy.developerPitchUrdu,
                    size: 8,
                    color: _muted,
                    height: 1.7,
                  ),
                ],
              ),
            ),
          ),
          const _SquareDashEdge(),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              fontFamily: ReceiptCopy.latinFontFamily,
              fontWeight: FontWeight.w500,
              fontSize: 11.5,
              color: ThermalReceiptView._muted,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFamily: ReceiptCopy.latinFontFamily,
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
                color: ThermalReceiptView._ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UrduText extends StatelessWidget {
  const _UrduText(
    this.text, {
    required this.size,
    required this.color,
    this.weight = FontWeight.w400,
    this.height = 1.85,
  });

  final String text;
  final double size;
  final Color color;
  final FontWeight weight;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: ReceiptCopy.urduFontFamily,
          fontFamilyFallback: const <String>[ReceiptCopy.latinFontFamily],
          fontWeight: weight,
          fontSize: size,
          height: height,
          color: color,
        ),
      ),
    );
  }
}

class _ReceiptActionButton extends StatelessWidget {
  const _ReceiptActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(9),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: ReceiptCopy.latinFontFamily,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SquareDashEdge extends StatelessWidget {
  const _SquareDashEdge();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 8,
      width: double.infinity,
      child: CustomPaint(painter: _SquareDashPainter()),
    );
  }
}

class _SquareDashPainter extends CustomPainter {
  const _SquareDashPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = ThermalReceiptView._ink.withValues(alpha: 0.55);
    const double dash = 4;
    const double gap = 4;
    double x = 0;
    final double y = (size.height - dash) / 2;
    while (x < size.width) {
      canvas.drawRect(Rect.fromLTWH(x, y, dash, dash), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _SquareDashPainter oldDelegate) {
    return false;
  }
}

class _PaperRulePainter extends CustomPainter {
  const _PaperRulePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const double step = 27;
    for (double y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PaperRulePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _DashRule extends StatelessWidget {
  const _DashRule({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashPainter(color: color),
      size: const Size(double.infinity, 1),
    );
  }
}

class _DashPainter extends CustomPainter {
  const _DashPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const double dash = 4;
    const double gap = 3;
    double x = 0;
    final double y = size.height / 2;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, y),
        Offset((x + dash).clamp(0, size.width), y),
        paint,
      );
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
