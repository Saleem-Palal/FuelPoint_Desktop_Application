import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/dispensr_theme.dart';
import '../../../../core/widgets/segment_lcd.dart';
import '../../../../features/station/data/receipt_proof_raster.dart';
import '../../../../features/station/data/receipt_widget_capture.dart';
import '../../../../features/station/domain/dispenser_models.dart';
import '../../../../features/station/domain/fuel_precision.dart';
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
    this.baqayaPkr = 0,
  });

  final SaleTransaction txn;
  final VoidCallback onDismiss;
  final ReceiptPrintKind printKind;
  final int baqayaPkr;

  @override
  State<UnitReceiptOverlay> createState() => _UnitReceiptOverlayState();
}

class _UnitReceiptOverlayState extends State<UnitReceiptOverlay> {
  ReceiptTicket get ticket => ReceiptTicket.fromTransaction(widget.txn);

  bool get _twoCopies => widget.txn.payment.printsTwoCopies;

  Future<void> _printThenClose() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final ReceiptTicket slip = ticket;
    late final Uint8List customerPng;
    late final Uint8List stationPng;
    Uint8List? screenshotPng;
    try {
      if (!mounted) {
        return;
      }
      customerPng = await captureReceiptWidget(
        context: context,
        child: buildSaleReceiptSlip(
          txn: widget.txn,
          stationCopy: false,
          kind: widget.printKind,
          baqayaPkr: widget.baqayaPkr,
        ),
      );
      if (_twoCopies) {
        if (!mounted) {
          return;
        }
        stationPng = await captureReceiptWidget(
          context: context,
          child: buildSaleReceiptSlip(
            txn: widget.txn,
            stationCopy: true,
            kind: widget.printKind,
            baqayaPkr: widget.baqayaPkr,
          ),
        );
      } else {
        stationPng = customerPng;
      }
      if (!mounted) {
        return;
      }
      screenshotPng = await captureScreenshotCopyPng(
        context: context,
        facts: ScreenshotCopyFacts.fromSale(widget.txn),
        proofImagePath: widget.txn.proofImagePath,
      );
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
            screenshotPng: screenshotPng,
            proofImagePath: widget.txn.proofImagePath,
          );
          messenger.showSnackBar(
            SnackBar(
              content: Text(ReceiptCopy.printedSlipsMessage(widget.txn)),
            ),
          );
        } else {
          await ReceiptGenerator.instance.printCapturedPng(
            customerPng,
            slip,
            screenshotPng: screenshotPng,
            proofImagePath: widget.txn.proofImagePath,
          );
          messenger.showSnackBar(
            SnackBar(
              content: Text(ReceiptCopy.printedSlipsMessage(widget.txn)),
            ),
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
              child: ThermalPrintLook(
                txn: widget.txn,
                printKind: widget.printKind,
                stationCopy: widget.txn.proofImagePath.trim().isNotEmpty,
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

/// Station-copy preview: crisp grayscale receipt PNG stacked over the
/// Bayer-dithered proof photo — the same dual-segment layout the spooler prints.
class ThermalPrintLook extends StatefulWidget {
  const ThermalPrintLook({
    super.key,
    required this.txn,
    this.proofJpeg,
    this.printKind = ReceiptPrintKind.live,
    this.stationCopy = true,
  });

  final SaleTransaction txn;
  final Uint8List? proofJpeg;
  final ReceiptPrintKind printKind;
  final bool stationCopy;

  @override
  State<ThermalPrintLook> createState() => _ThermalPrintLookState();
}

class _ThermalPrintLookState extends State<ThermalPrintLook> {
  Uint8List? _mono;
  Object? _error;
  int _buildGen = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_rebuild());
    });
  }

  @override
  void didUpdateWidget(ThermalPrintLook oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.txn.tokenNo != widget.txn.tokenNo ||
        oldWidget.txn.proofImagePath != widget.txn.proofImagePath ||
        oldWidget.proofJpeg != widget.proofJpeg ||
        oldWidget.stationCopy != widget.stationCopy) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_rebuild());
      });
    }
  }

  Future<void> _rebuild() async {
    final int gen = ++_buildGen;
    try {
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || gen != _buildGen) {
        return;
      }
      final Uint8List receiptPng = await captureReceiptWidget(
        context: context,
        child: buildSaleReceiptSlip(
          txn: widget.txn,
          stationCopy: widget.stationCopy,
          kind: widget.printKind,
        ),
      );
      final Uint8List mono = await compute(composeThermalPreviewJob, <Object?>[
        Uint8List.fromList(receiptPng),
        null,
      ]);
      if (!mounted || gen != _buildGen) {
        return;
      }
      setState(() {
        _mono = mono;
        _error = null;
      });
    } catch (error, stack) {
      debugPrint('Thermal print preview failed: $error\n$stack');
      if (!mounted || gen != _buildGen) {
        return;
      }
      setState(() {
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFFFFFFF),
      child: _mono == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Text(
                      'Could not build thermal preview.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: ReceiptCopy.latinFontFamily,
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
            )
          : FittedBox(
              fit: BoxFit.contain,
              child: Image.memory(
                _mono!,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
              ),
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
    return RepaintBoundary(key: captureKey, child: child);
  }
}

class ThermalReceiptDetail {
  const ThermalReceiptDetail({required this.label, required this.value});

  final String label;
  final String value;
}

Widget buildSaleReceiptSlip({
  required SaleTransaction txn,
  required bool stationCopy,
  ReceiptPrintKind kind = ReceiptPrintKind.live,
  int baqayaPkr = 0,
}) {
  return ThermalReceiptView(
    ticket: ReceiptTicket.fromTransaction(txn),
    details: saleReceiptDetails(txn, baqayaPkr: baqayaPkr),
    forPrint: true,
    showFooter: ReceiptCopy.showFooterFor(
      payment: txn.payment,
      stationCopy: stationCopy,
    ),
    copyBanner: ReceiptCopy.bannerFor(
      payment: txn.payment,
      stationCopy: stationCopy,
      kind: kind,
      recovered: txn.isRecoveredSale,
    ),
    handwritingLines: saleReceiptHandwriting(
      txn: txn,
      stationCopy: stationCopy,
      kind: kind,
    ),
    proofImage: saleProofPreviewImage(txn, stationCopy: stationCopy),
  );
}

List<String> saleReceiptHandwriting({
  required SaleTransaction txn,
  required bool stationCopy,
  ReceiptPrintKind kind = ReceiptPrintKind.live,
}) {
  if (txn.proofImagePath.trim().isNotEmpty) {
    return const <String>[];
  }
  return ReceiptCopy.handwritingLinesFor(
    payment: txn.payment,
    stationCopy: stationCopy,
    kind: kind,
  );
}

ImageProvider? saleProofPreviewImage(
  SaleTransaction txn, {
  required bool stationCopy,
}) {
  if (!stationCopy) {
    return null;
  }
  final String path = txn.proofImagePath.trim();
  if (path.isEmpty) {
    return null;
  }
  final File file = File(path);
  if (!file.existsSync()) {
    return null;
  }
  return FileImage(file);
}

List<ThermalReceiptDetail> saleReceiptDetails(
  SaleTransaction txn, {
  int baqayaPkr = 0,
}) {
  final List<ThermalReceiptDetail> rows = <ThermalReceiptDetail>[
    ThermalReceiptDetail(label: 'Customer', value: txn.customerName),
    ThermalReceiptDetail(
      label: 'Vehicle No.',
      value: txn.vehicleNo.trim().isEmpty ? '—' : txn.vehicleNo.trim(),
    ),
    ThermalReceiptDetail(
      label: 'Payment',
      value: txn.isAccountPending
          ? '${txn.payment.label} · Pending'
          : txn.payment.label,
    ),
  ];
  if (txn.isAccountPending) {
    rows.add(
      const ThermalReceiptDetail(label: 'Status', value: 'Account pending'),
    );
  }
  switch (txn.payment) {
    case PaymentMethod.bankAccount:
    case PaymentMethod.easyPaisa:
      final int cashBack = baqayaPkr > 0 ? baqayaPkr : txn.receiptBaqayaPkr;
      rows.add(
        ThermalReceiptDetail(
          label: 'Account',
          value: formatPkr(txn.receiptAccountAmount),
        ),
      );
      rows.add(
        ThermalReceiptDetail(label: 'Cash', value: formatPkr(txn.cashAmount)),
      );
      if (cashBack > 0) {
        rows.add(
          ThermalReceiptDetail(
            label: 'Baqaya Dene hain',
            value: formatPkr(cashBack.toDouble()),
          ),
        );
      }
      break;
    case PaymentMethod.cash:
      break;
    case PaymentMethod.udhaar:
      final double accountShown = txn.accountAmount + txn.pendingAccountAmount;
      if (roundRupees(txn.cashAmount) > 0 || roundRupees(accountShown) > 0) {
        rows.add(
          ThermalReceiptDetail(label: 'Cash', value: formatPkr(txn.cashAmount)),
        );
        rows.add(
          ThermalReceiptDetail(
            label: 'Account',
            value: formatPkr(accountShown),
          ),
        );
        rows.add(
          ThermalReceiptDetail(
            label: 'Udhaar',
            value: formatPkr(
              udhaarCreditRupees(
                saleAmount: txn.amountPkr,
                cashAmount: txn.cashAmount,
                accountAmount: accountShown,
              ).toDouble(),
            ),
          ),
        );
      }
      break;
  }
  rows.add(ThermalReceiptDetail(label: 'Operator', value: txn.cashierName));
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
  int baqayaPkr = 0,
}) async {
  final Uint8List customerPng = await captureReceiptWidget(
    context: context,
    child: buildSaleReceiptSlip(
      txn: txn,
      stationCopy: false,
      kind: kind,
      baqayaPkr: baqayaPkr,
    ),
  );
  Uint8List stationPng = customerPng;
  if (txn.payment.printsTwoCopies && kind == ReceiptPrintKind.live) {
    if (!context.mounted) {
      return;
    }
    stationPng = await captureReceiptWidget(
      context: context,
      child: buildSaleReceiptSlip(
        txn: txn,
        stationCopy: true,
        kind: kind,
        baqayaPkr: baqayaPkr,
      ),
    );
  }
  if (!context.mounted) {
    return;
  }
  final ReceiptTicket slip = ReceiptTicket.fromTransaction(txn);
  final Uint8List? screenshotPng = await captureScreenshotCopyPng(
    context: context,
    facts: ScreenshotCopyFacts.fromSale(txn),
    proofImagePath: txn.proofImagePath,
  );
  if (txn.payment.printsTwoCopies) {
    await ReceiptGenerator.instance.printDualCopies(
      customerPng: customerPng,
      stationPng: stationPng,
      ticket: slip,
      screenshotPng: screenshotPng,
      proofImagePath: txn.proofImagePath,
    );
  } else {
    await ReceiptGenerator.instance.printCapturedPng(
      customerPng,
      slip,
      screenshotPng: screenshotPng,
      proofImagePath: txn.proofImagePath,
    );
  }
}

bool receiptPreviewEnabled(BuildContext context) {
  return ProviderScope.containerOf(
    context,
  ).read(settingsProvider).showReceiptPreview;
}

String printedSaleReceiptMessage({
  required SaleTransaction txn,
  required ReceiptPrintKind kind,
}) {
  switch (kind) {
    case ReceiptPrintKind.live:
      return ReceiptCopy.printedSlipsMessage(txn);
    case ReceiptPrintKind.secondCopy:
      return txn.thermalSlipCount > 1
          ? 'Second copy — ${txn.thermalSlipCount} slips sent to printer'
          : 'Second copy sent to printer';
    case ReceiptPrintKind.editedCopy:
      return 'Edited copy sent to printer';
  }
}

/// Shows the on-screen receipt when Settings → Show receipt preview is on.
/// Otherwise captures off-screen and sends straight to the printer.
Future<void> presentSaleReceipt({
  required BuildContext context,
  required SaleTransaction txn,
  ReceiptPrintKind kind = ReceiptPrintKind.live,
  String? title,
  int baqayaPkr = 0,
}) async {
  if (!receiptPreviewEnabled(context)) {
    await spoolSaleReceipt(
      context: context,
      txn: txn,
      kind: kind,
      baqayaPkr: baqayaPkr,
    );
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(printedSaleReceiptMessage(txn: txn, kind: kind)),
      ),
    );
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return SaleReceiptPreviewDialog(
        txn: txn,
        printKind: kind,
        title: title,
        baqayaPkr: baqayaPkr,
      );
    },
  );
}

class SaleReceiptPreviewDialog extends StatefulWidget {
  const SaleReceiptPreviewDialog({
    super.key,
    required this.txn,
    this.printKind = ReceiptPrintKind.live,
    this.title,
    this.baqayaPkr = 0,
  });

  final SaleTransaction txn;
  final ReceiptPrintKind printKind;
  final String? title;
  final int baqayaPkr;

  @override
  State<SaleReceiptPreviewDialog> createState() =>
      _SaleReceiptPreviewDialogState();
}

class _SaleReceiptPreviewDialogState extends State<SaleReceiptPreviewDialog> {
  final GlobalKey _previewKey = GlobalKey();
  bool _busy = false;
  bool _stationCapture = false;
  bool _forPrint = false;

  ReceiptTicket get _ticket => ReceiptTicket.fromTransaction(widget.txn);

  bool get _twoCopies => widget.txn.payment.printsTwoCopies;

  Future<void> _print() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _forPrint = true;
    });
    try {
      final Uint8List customerPng = await captureReceiptWidget(
        context: context,
        child: buildSaleReceiptSlip(
          txn: widget.txn,
          stationCopy: false,
          kind: widget.printKind,
          baqayaPkr: widget.baqayaPkr,
        ),
      );
      Uint8List stationPng = customerPng;
      if (_twoCopies) {
        if (!mounted) {
          return;
        }
        stationPng = await captureReceiptWidget(
          context: context,
          child: buildSaleReceiptSlip(
            txn: widget.txn,
            stationCopy: true,
            kind: widget.printKind,
            baqayaPkr: widget.baqayaPkr,
          ),
        );
      }
      if (!mounted) {
        return;
      }
      final Uint8List? screenshotPng = await captureScreenshotCopyPng(
        context: context,
        facts: ScreenshotCopyFacts.fromSale(widget.txn),
        proofImagePath: widget.txn.proofImagePath,
      );
      if (_twoCopies) {
        await ReceiptGenerator.instance.printDualCopies(
          customerPng: customerPng,
          stationPng: stationPng,
          ticket: _ticket,
          screenshotPng: screenshotPng,
          proofImagePath: widget.txn.proofImagePath,
        );
      } else {
        await ReceiptGenerator.instance.printCapturedPng(
          customerPng,
          _ticket,
          screenshotPng: screenshotPng,
          proofImagePath: widget.txn.proofImagePath,
        );
      }
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            printedSaleReceiptMessage(txn: widget.txn, kind: widget.printKind),
          ),
        ),
      );
    } catch (error, stack) {
      debugPrint('Receipt preview print failed: $error\n$stack');
      if (!mounted) {
        return;
      }
      setState(() {
        _forPrint = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not print receipt. $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Dialog(
      backgroundColor: tokens.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius20),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      widget.title ??
                          'Receipt ${formatLedgerToken(widget.txn.tokenNo)}',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: tokens.ink,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Center(
                    child: ThermalReceiptCapture(
                      captureKey: _previewKey,
                      child: ThermalReceiptView(
                        ticket: _ticket,
                        forPrint: _forPrint,
                        showFooter: ReceiptCopy.showFooterFor(
                          payment: widget.txn.payment,
                          stationCopy: _stationCapture,
                        ),
                        copyBanner: ReceiptCopy.bannerFor(
                          payment: widget.txn.payment,
                          stationCopy: _stationCapture,
                          kind: widget.printKind,
                          recovered: widget.txn.isRecoveredSale,
                        ),
                        details: saleReceiptDetails(
                          widget.txn,
                          baqayaPkr: widget.baqayaPkr,
                        ),
                        handwritingLines: saleReceiptHandwriting(
                          txn: widget.txn,
                          stationCopy: _stationCapture,
                          kind: widget.printKind,
                        ),
                        proofImage: saleProofPreviewImage(
                          widget.txn,
                          stationCopy: _stationCapture,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: DsPillButton(
                      label: 'Cancel',
                      variant: DsPillVariant.outline,
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DsPillButton(
                      label: _busy ? 'Printing…' : 'Print',
                      icon: Icons.print_outlined,
                      onPressed: _busy ? null : _print,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

ThermalReceiptView screenshotCopyReceipt({
  required ScreenshotCopyFacts facts,
  ImageProvider? proofImage,
  bool forPrint = false,
}) {
  return ThermalReceiptView.custom(
    dateLabel: '',
    timeLabel: '',
    badge: '',
    referenceLabel: '',
    referenceValue: '',
    showLcd: false,
    forPrint: forPrint,
    padToCashHeight: false,
    showProofFrame: true,
    showDateTime: false,
    showFooter: false,
    proofMinHeight: 520,
    copyBanner: ReceiptCopy.screenshotCopyBanner,
    proofImage: proofImage,
    details: <ThermalReceiptDetail>[
      ThermalReceiptDetail(label: 'TKN', value: facts.tokenLabel),
      ThermalReceiptDetail(label: 'Customer Name', value: facts.customerName),
      ThermalReceiptDetail(
        label: 'Account Amount',
        value: formatPkr(facts.accountAmountPkr),
      ),
      ThermalReceiptDetail(label: 'Operator', value: facts.operatorName),
    ],
  );
}

Future<Uint8List?> captureScreenshotCopyPng({
  required BuildContext context,
  required ScreenshotCopyFacts facts,
  Uint8List? proofBytes,
  String proofImagePath = '',
}) async {
  Uint8List? bytes = proofBytes;
  if (bytes == null) {
    final String path = proofImagePath.trim();
    if (path.isEmpty) {
      return null;
    }
    final File file = File(path);
    if (!file.existsSync()) {
      return null;
    }
    bytes = await file.readAsBytes();
  }
  if (bytes.isEmpty) {
    return null;
  }
  if (!context.mounted) {
    return null;
  }
  final MemoryImage proof = MemoryImage(bytes);
  try {
    await precacheImage(proof, context);
  } catch (error, stack) {
    debugPrint('Screenshot precache skipped: $error\n$stack');
  }
  if (!context.mounted) {
    return null;
  }
  return captureReceiptWidget(
    context: context,
    child: screenshotCopyReceipt(
      facts: facts,
      proofImage: proof,
      forPrint: true,
    ),
  );
}

/// Compact thermal slip. Sale tickets keep the LCD; other slips can hide it.
class ThermalReceiptView extends StatelessWidget {
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
    ImageProvider? proofImage,
    bool padToCashHeight = true,
    bool showProofFrame = false,
    bool showDateTime = true,
    bool showFooter = true,
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
         proofImage: proofImage,
         padToCashHeight: padToCashHeight,
         showProofFrame: showProofFrame,
         showDateTime: showDateTime,
         showFooter: showFooter,
         proofMinHeight: 280,
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
                 label: 'Operator',
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
    this.proofImage,
    this.padToCashHeight = true,
    this.showProofFrame = false,
    this.showDateTime = true,
    this.showFooter = true,
    this.proofMinHeight = 280,
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
  final ImageProvider? proofImage;
  final bool padToCashHeight;
  final bool showProofFrame;
  final bool showDateTime;
  final bool showFooter;
  final double proofMinHeight;

  @override
  Widget build(BuildContext context) {
    final ReceiptFooterSettings? pinned = ReceiptPrintFooter.maybeOf(context);
    if (pinned != null) {
      return _slip(pinned);
    }
    return _ThermalReceiptWatching(slip: this);
  }

  Widget _slip(ReceiptFooterSettings footer) {
    final Color paper = forPrint ? const Color(0xFFFFFFFF) : _paper;
    final String banner = (copyBanner ?? '').trim();
    final ImageProvider? proof = proofImage;
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
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const _SquareDashEdge(),
            CustomPaint(
              painter: const _PaperRulePainter(color: _rule),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
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
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
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
                    if (showDateTime) ...<Widget>[
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
                    ],
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: padToCashHeight ? _cashMiddleMinHeight : 0,
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
                    if (proof != null || showProofFrame) ...<Widget>[
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: paper,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _ink, width: 1.6),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: proof == null
                                ? SizedBox(
                                    width: double.infinity,
                                    height: proofMinHeight,
                                    child: const ColoredBox(
                                      color: Color(0xFFF3F3F3),
                                    ),
                                  )
                                : Image(
                                    image: proof,
                                    fit: BoxFit.fitWidth,
                                    width: double.infinity,
                                    alignment: Alignment.topCenter,
                                    filterQuality: forPrint
                                        ? FilterQuality.none
                                        : FilterQuality.medium,
                                    errorBuilder:
                                        (
                                          BuildContext context,
                                          Object error,
                                          StackTrace? stack,
                                        ) {
                                          return SizedBox(
                                            height: proofMinHeight,
                                            width: double.infinity,
                                          );
                                        },
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ] else if (handwritingLines.isNotEmpty) ...<Widget>[
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
                    if (showFooter) ...<Widget>[
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

class _ThermalReceiptWatching extends ConsumerWidget {
  const _ThermalReceiptWatching({required this.slip});

  final ThermalReceiptView slip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ReceiptFooterSettings footer = ref.watch(
      settingsProvider.select(
        (SettingsState settings) => settings.receiptFooter,
      ),
    );
    return slip._slip(footer);
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
        overflow: maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
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
