import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/segment_lcd.dart';
import '../../../../features/station/domain/dispenser_models.dart';
import '../../../../features/station/domain/money_format.dart';
import '../../../../features/station/domain/receipt_footer_settings.dart';
import '../../../../providers/settings_provider.dart';
import 'generate_receipt.dart';

class UnitReceiptOverlay extends StatefulWidget {
  const UnitReceiptOverlay({
    super.key,
    required this.txn,
    required this.onDismiss,
    this.printKind = ReceiptPrintKind.live,
  });

  final SaleTransaction txn;
  final VoidCallback onDismiss;
  final ReceiptPrintKind printKind;

  @override
  State<UnitReceiptOverlay> createState() => _UnitReceiptOverlayState();
}

class _UnitReceiptOverlayState extends State<UnitReceiptOverlay> {
  final GlobalKey _previewKey = GlobalKey();
  bool _stationCapture = false;
  bool _forPrint = false;

  ReceiptTicket get ticket => ReceiptTicket.fromTransaction(widget.txn);

  bool get _twoCopies => widget.txn.payment.printsTwoCopies;

  String? get _copyBanner {
    return ReceiptCopy.bannerFor(
      payment: widget.txn.payment,
      stationCopy: _stationCapture,
      kind: widget.printKind,
    );
  }

  Future<void> _printThenClose() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final ReceiptTicket slip = ticket;
    late final Uint8List customerPng;
    late final Uint8List stationPng;
    try {
      if (!mounted) {
        return;
      }
      setState(() {
        _forPrint = true;
      });
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
      customerPng = await ReceiptGenerator.instance.capturePreview(_previewKey);
      if (_twoCopies) {
        if (!mounted) {
          return;
        }
        setState(() {
          _stationCapture = true;
        });
        await WidgetsBinding.instance.endOfFrame;
        await WidgetsBinding.instance.endOfFrame;
        stationPng = await ReceiptGenerator.instance.capturePreview(
          _previewKey,
        );
      } else {
        stationPng = customerPng;
      }
    } catch (error, stack) {
      debugPrint('Receipt snapshot failed: $error\n$stack');
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Could not prepare receipt. $error')),
      );
      return;
    }
    widget.onDismiss();
    unawaited(() async {
      try {
        if (slip.payment.printsTwoCopies) {
          await ReceiptGenerator.instance.printDualCopies(
            customerPng: customerPng,
            stationPng: stationPng,
            ticket: slip,
          );
          messenger.showSnackBar(
            const SnackBar(content: Text('2 copies sent to printer')),
          );
        } else {
          await ReceiptGenerator.instance.printCapturedPng(customerPng, slip);
          messenger.showSnackBar(
            const SnackBar(content: Text('Receipt sent to printer')),
          );
        }
      } catch (error, stack) {
        debugPrint('Print failed: $error\n$stack');
        messenger.showSnackBar(
          SnackBar(content: Text('Could not complete receipt. $error')),
        );
      }
    }());
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
              child: ThermalReceiptCapture(
                captureKey: _previewKey,
                child: ThermalReceiptView(
                  ticket: ticket,
                  copyBanner: _copyBanner,
                  forPrint: _forPrint,
                  details: saleReceiptDetails(widget.txn),
                  handwritingLines: ReceiptCopy.handwritingLinesFor(
                    payment: widget.txn.payment,
                    stationCopy: _stationCapture,
                    kind: widget.printKind,
                  ),
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
                    unawaited(_printThenClose());
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

class ThermalReceiptCapture extends StatelessWidget {
  const ThermalReceiptCapture({
    super.key,
    required this.captureKey,
    required this.child,
  });

  final Key captureKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.contain,
      child: RepaintBoundary(key: captureKey, child: child),
    );
  }
}

class ThermalReceiptDetail {
  const ThermalReceiptDetail({required this.label, required this.value});

  final String label;
  final String value;
}

List<ThermalReceiptDetail> saleReceiptDetails(SaleTransaction txn) {
  final List<ThermalReceiptDetail> rows = <ThermalReceiptDetail>[
    ThermalReceiptDetail(label: 'Customer', value: txn.customerName),
    ThermalReceiptDetail(
      label: 'Vehicle No.',
      value: txn.vehicleNo.trim().isEmpty ? '—' : txn.vehicleNo.trim(),
    ),
    ThermalReceiptDetail(label: 'Payment', value: txn.payment.label),
  ];
  switch (txn.payment) {
    case PaymentMethod.bankAccount:
    case PaymentMethod.easyPaisa:
      rows.add(
        ThermalReceiptDetail(
          label: 'Account',
          value: formatPkr(txn.receiptAccountAmount),
        ),
      );
      rows.add(
        ThermalReceiptDetail(label: 'Cash', value: formatPkr(txn.cashAmount)),
      );
    case PaymentMethod.cash:
    case PaymentMethod.udhaar:
      break;
  }
  rows.add(ThermalReceiptDetail(label: 'Manager', value: txn.cashierName));
  rows.add(
    ThermalReceiptDetail(
      label: 'Helper',
      value: txn.helperName.trim().isEmpty ? '—' : txn.helperName.trim(),
    ),
  );
  return rows;
}

Future<void> spoolSaleReceipt({
  required BuildContext context,
  required SaleTransaction txn,
  ReceiptPrintKind kind = ReceiptPrintKind.live,
}) async {
  final OverlayState overlay = Overlay.of(context, rootOverlay: true);
  final GlobalKey previewKey = GlobalKey();
  bool stationCapture = false;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (BuildContext context) {
      return Positioned(
        left: -2400,
        top: 0,
        child: Material(
          color: Colors.transparent,
          child: ThermalReceiptCapture(
            captureKey: previewKey,
            child: ThermalReceiptView(
              ticket: ReceiptTicket.fromTransaction(txn),
              details: saleReceiptDetails(txn),
              forPrint: true,
              copyBanner: ReceiptCopy.bannerFor(
                payment: txn.payment,
                stationCopy: stationCapture,
                kind: kind,
              ),
              handwritingLines: ReceiptCopy.handwritingLinesFor(
                payment: txn.payment,
                stationCopy: stationCapture,
                kind: kind,
              ),
            ),
          ),
        ),
      );
    },
  );
  overlay.insert(entry);
  try {
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    final Uint8List customerPng = await ReceiptGenerator.instance
        .capturePreview(previewKey);
    Uint8List stationPng = customerPng;
    if (txn.payment.printsTwoCopies && kind == ReceiptPrintKind.live) {
      stationCapture = true;
      entry.markNeedsBuild();
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
      stationPng = await ReceiptGenerator.instance.capturePreview(previewKey);
    }
    final ReceiptTicket slip = ReceiptTicket.fromTransaction(txn);
    if (txn.payment.printsTwoCopies) {
      await ReceiptGenerator.instance.printDualCopies(
        customerPng: customerPng,
        stationPng: stationPng,
        ticket: slip,
      );
    } else {
      await ReceiptGenerator.instance.printCapturedPng(customerPng, slip);
    }
  } finally {
    entry.remove();
  }
}

/// Compact thermal slip. Sale tickets keep the LCD; other slips can hide it.
class ThermalReceiptView extends ConsumerWidget {
  ThermalReceiptView({
    Key? key,
    required ReceiptTicket ticket,
    bool showLcd = true,
    bool forPrint = false,
    String? badge,
    String? referenceLabel,
    String? referenceValue,
    String? copyBanner,
    List<ThermalReceiptDetail>? details,
    List<String> handwritingLines = const <String>[],
  }) : this.custom(
         key: key,
         dateLabel: ticket.dateLabel,
         timeLabel: ticket.timeLabel,
         badge: badge ?? ticket.unitBadge,
         referenceLabel: referenceLabel ?? 'Token',
         referenceValue: referenceValue ?? ticket.tokenLabel,
         showLcd: showLcd,
         forPrint: forPrint,
         amount: ticket.amount,
         liters: ticket.liters,
         rate: ticket.rate,
         copyBanner: copyBanner,
         handwritingLines: handwritingLines,
         details:
             details ??
             <ThermalReceiptDetail>[
               ThermalReceiptDetail(
                 label: 'Customer',
                 value: ticket.customerName,
               ),
               ThermalReceiptDetail(
                 label: 'Vehicle No.',
                 value: ticket.vehicleDisplay,
               ),
               ThermalReceiptDetail(
                 label: 'Payment',
                 value: ticket.paymentLabel,
               ),
               ThermalReceiptDetail(
                 label: 'Manager',
                 value: ticket.cashierName,
               ),
               ThermalReceiptDetail(
                 label: 'Helper',
                 value: ticket.helperDisplay,
               ),
             ],
       );

  const ThermalReceiptView.custom({
    super.key,
    required this.dateLabel,
    required this.timeLabel,
    required this.badge,
    required this.referenceLabel,
    required this.referenceValue,
    required this.details,
    this.showLcd = true,
    this.forPrint = false,
    this.amount = '',
    this.liters = '',
    this.rate = '',
    this.copyBanner,
    this.handwritingLines = const <String>[],
  });

  static const double width = 456;
  static const double _legacyWidth = 272;
  static const double _bodyScale = width / _legacyWidth * 0.95;
  static const double _textScale = 1.04;
  static const double _titleScale = 1.06;

  static const double _titleSize = 19 * 1.05 * _bodyScale * _titleScale;
  static const double _latinSize = 13 * _bodyScale * _textScale;
  static const double _bannerSize = 10 * _bodyScale * _textScale;
  static const double _detailSize = 13 * _bodyScale * _textScale;

  /// Title-to-date gap on the cash sale slip (no copy banner).
  static const double _headerGap = 17;

  /// SegmentLcd.receipt block: bezel + glass pad + AMOUNT/LITERS/RATE.
  static const double _lcdBlockHeight =
      5 * 2 + 8 * 2 + 46 + 3 * 2 + 1 + 42 + 2 + 8 + 20;

  static const double _detailRowExtent = _detailSize + 6;

  /// Cash sale middle (LCD + 5 detail rows). Shorter slips pad to this.
  static const double _cashMiddleMinHeight =
      10 + _lcdBlockHeight + 10 + _detailRowExtent * 5;

  static const Color _paper = Color(ColorData.paper);
  static const Color _ink = Color(ColorData.ink);
  static const Color _muted = Color(0xFF6F6560);
  static const Color _steel = Color(ColorData.steel);
  static const Color _rule = Color(0x06211C1A);

  final String dateLabel;
  final String timeLabel;
  final String badge;
  final String referenceLabel;
  final String referenceValue;
  final bool showLcd;
  final bool forPrint;
  final String amount;
  final String liters;
  final String rate;
  final String? copyBanner;
  final List<ThermalReceiptDetail> details;
  final List<String> handwritingLines;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ReceiptFooterSettings footer = ref.watch(
      settingsProvider.select(
        (SettingsState settings) => settings.receiptFooter,
      ),
    );
    final Color paper = forPrint ? const Color(0xFFFFFFFF) : _paper;
    final String banner = (copyBanner ?? '').trim();
    return SizedBox(
      width: width,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: paper,
          boxShadow: forPrint
              ? const <BoxShadow>[]
              : const <BoxShadow>[
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
                      size: _titleSize,
                      weight: FontWeight.w700,
                      color: _ink,
                      height: 1.55,
                    ),
                    if (banner.isEmpty)
                      const SizedBox(height: _headerGap)
                    else ...<Widget>[
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          banner,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: ReceiptCopy.latinFontFamily,
                            fontWeight: FontWeight.w700,
                            fontSize: _bannerSize,
                            height: 1.25,
                            letterSpacing: 0.6,
                            color: _ink,
                          ),
                        ),
                      ),
                    ],
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            'Date  $dateLabel',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: ReceiptCopy.latinFontFamily,
                              fontWeight: FontWeight.w600,
                              fontSize: _latinSize,
                              color: _ink,
                            ),
                          ),
                        ),
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
                          badge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: ReceiptCopy.latinFontFamily,
                            fontWeight: FontWeight.w600,
                            fontSize: _latinSize,
                            color: _steel,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            'Time  $timeLabel',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: ReceiptCopy.latinFontFamily,
                              fontWeight: FontWeight.w600,
                              fontSize: _latinSize,
                              color: _ink,
                            ),
                          ),
                        ),
                        Text(
                          '$referenceLabel  $referenceValue',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: ReceiptCopy.latinFontFamily,
                            fontWeight: FontWeight.w500,
                            fontSize: _latinSize,
                            color: _ink,
                          ),
                        ),
                      ],
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: _cashMiddleMinHeight,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          if (showLcd) ...<Widget>[
                            const SizedBox(height: 10),
                            SegmentLcd.receipt(
                              forPrint: forPrint,
                              lines: <SegmentLcdLine>[
                                SegmentLcdLine(label: 'AMOUNT', value: amount),
                                SegmentLcdLine(label: 'LITERS', value: liters),
                                SegmentLcdLine(label: 'RATE', value: rate),
                              ],
                            ),
                          ],
                          const SizedBox(height: 10),
                          for (final ThermalReceiptDetail row in details)
                            _DetailRow(label: row.label, value: row.value),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (handwritingLines.isNotEmpty) ...<Widget>[
                      for (final String line in handwritingLines)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            line,
                            textAlign: TextAlign.left,
                            style: const TextStyle(
                              fontFamily: ReceiptCopy.latinFontFamily,
                              fontWeight: FontWeight.w600,
                              fontSize: _latinSize,
                              color: _ink,
                            ),
                          ),
                        ),
                      const SizedBox(height: 4),
                    ],
                    const _DashRule(color: Color(0x55211C1A)),
                    const SizedBox(height: 8),
                    for (int i = 0; i < footer.lines.length; i++) ...<Widget>[
                      if (i > 0) const SizedBox(height: 2),
                      _ReceiptFooterLine(
                        text: footer.lines[i],
                        fontSize: footer.fontSize,
                        lineHeight: footer.lineHeight,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const _SquareDashEdge(),
          ],
        ),
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: ReceiptCopy.latinFontFamily,
              fontWeight: FontWeight.w500,
              fontSize: ThermalReceiptView._detailSize,
              color: ThermalReceiptView._muted,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: ReceiptCopy.latinFontFamily,
                fontWeight: FontWeight.w700,
                fontSize: ThermalReceiptView._detailSize,
                color: ThermalReceiptView._ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptFooterLine extends StatelessWidget {
  const _ReceiptFooterLine({
    required this.text,
    required this.fontSize,
    required this.lineHeight,
  });

  final String text;
  final double fontSize;
  final double lineHeight;

  @override
  Widget build(BuildContext context) {
    if (ReceiptFooterSettings.isLatinLine(text)) {
      return Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: ReceiptCopy.latinFontFamily,
          fontWeight: FontWeight.w700,
          fontSize: fontSize,
          height: lineHeight,
          color: ThermalReceiptView._ink,
        ),
      );
    }
    return _UrduText(
      text,
      size: fontSize,
      color: ThermalReceiptView._ink,
      height: lineHeight,
      maxLines: 1,
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
    this.maxLines,
  });

  final String text;
  final double size;
  final Color color;
  final FontWeight weight;
  final double height;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: maxLines,
        overflow: maxLines == null
            ? TextOverflow.clip
            : TextOverflow.ellipsis,
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
