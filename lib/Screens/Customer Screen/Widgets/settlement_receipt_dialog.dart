import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/theme/dispensr_theme.dart';
import '../../../features/customer/domain/customer_models.dart';
import '../../../features/station/domain/money_format.dart';
import '../../Sale Screen/Widgets/Services/generate_receipt.dart';
import '../../Sale Screen/Widgets/Services/receipt_preview_widget.dart';

const String kSettlementCustomerCopy = 'COPY 1: CUSTOMER RECEIPT';
const String kSettlementStationCopy = 'COPY 2: STATION RECORD';

ThermalReceiptView settlementThermalReceipt(
  CustomerSettlement settlement, {
  String? copyBanner,
  bool forPrint = false,
}) {
  final List<ThermalReceiptDetail> details = <ThermalReceiptDetail>[
    ThermalReceiptDetail(label: 'Customer ID', value: settlement.customerId),
    ThermalReceiptDetail(label: 'Customer', value: settlement.customerName),
    ThermalReceiptDetail(label: 'Payment', value: settlement.paymentMode.label),
    ThermalReceiptDetail(
      label: 'Cashier',
      value: '${settlement.cashierId} · ${settlement.cashierName}',
    ),
    ThermalReceiptDetail(
      label: 'Previous Balance',
      value: formatPkrStatement(settlement.previousBalance),
    ),
    ThermalReceiptDetail(
      label: 'Amount Paid Now',
      value: formatPkrStatement(settlement.amountPkr),
    ),
    ThermalReceiptDetail(
      label: 'Remaining Outstanding',
      value: formatPkrStatement(settlement.remainingBalance),
    ),
  ];
  final String notes = settlement.notes.trim();
  if (notes.isNotEmpty) {
    details.add(ThermalReceiptDetail(label: 'Notes', value: notes));
  }
  return ThermalReceiptView.custom(
    dateLabel: formatDateOnly(settlement.timestamp),
    timeLabel: formatClock(settlement.timestamp),
    badge: 'Udhaar Recovery',
    referenceLabel: 'Receipt',
    referenceValue: settlementReceiptDisplay(
      settlement.receiptNo,
    ).replaceFirst('Receipt #', '#'),
    showLcd: false,
    forPrint: forPrint,
    copyBanner: copyBanner,
    details: details,
  );
}

Future<void> showSettlementReceiptDialog(
  BuildContext context, {
  required CustomerSettlement settlement,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return _SettlementReceiptDialog(settlement: settlement);
    },
  );
}

class _SettlementReceiptDialog extends StatefulWidget {
  const _SettlementReceiptDialog({required this.settlement});

  final CustomerSettlement settlement;

  @override
  State<_SettlementReceiptDialog> createState() =>
      _SettlementReceiptDialogState();
}

class _SettlementReceiptDialogState extends State<_SettlementReceiptDialog> {
  final GlobalKey _customerKey = GlobalKey();
  final GlobalKey _stationKey = GlobalKey();
  bool _busy = false;
  bool _forPrint = false;

  String get _pngName => 'settlement-${widget.settlement.receiptNo}.png';

  String get _caption {
    final CustomerSettlement row = widget.settlement;
    return <String>[
      ReceiptCopy.stationNameUrdu,
      'Udhaar Recovery  ${row.receiptNo}',
      'Date ${formatDateOnly(row.timestamp)}  ${formatClock(row.timestamp)}',
      'Customer ${row.customerId}  ${row.customerName}',
      'Previous  ${formatPkrStatement(row.previousBalance)}',
      'Paid now  ${formatPkrStatement(row.amountPkr)}',
      'Remaining  ${formatPkrStatement(row.remainingBalance)}',
      'Payment  ${row.paymentMode.label}',
      'Cashier  ${row.cashierId} · ${row.cashierName}',
    ].join('\n');
  }

  Future<void> _print() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _forPrint = true;
    });
    try {
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
      final Uint8List customerCopy = await ReceiptGenerator.instance
          .capturePreview(_customerKey);
      final Uint8List stationCopy = await ReceiptGenerator.instance
          .capturePreview(_stationKey);
      final String base = widget.settlement.receiptNo;
      await ReceiptGenerator.instance.printPngJobs(
        <Uint8List>[customerCopy, stationCopy],
        fileNames: <String>[
          'settlement-$base-customer.pdf',
          'settlement-$base-station.pdf',
        ],
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Receipt ${widget.settlement.receiptNo} — 2 copies sent to printer',
          ),
        ),
      );
    } catch (error, stack) {
      debugPrint('Settlement receipt print failed: $error\n$stack');
      if (!mounted) {
        return;
      }
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

  Future<void> _share() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
    });
    try {
      final Uint8List png = await ReceiptGenerator.instance.capturePreview(
        _customerKey,
      );
      await ReceiptGenerator.instance.sharePng(
        png: png,
        fileName: _pngName,
        caption: _caption,
        subject: 'Recovery ${widget.settlement.receiptNo}',
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Receipt shared')));
    } catch (error, stack) {
      debugPrint('Settlement receipt share failed: $error\n$stack');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not share receipt. $error')),
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
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    'Recovery ${widget.settlement.receiptNo}',
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: tokens.ink,
                    ),
                  ),
                  const Spacer(),
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
                  child: Column(
                    children: <Widget>[
                      Text(
                        'Two slips will print: customer copy, then station record.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 11,
                          color: tokens.inkMuted,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ThermalReceiptCapture(
                        captureKey: _customerKey,
                        child: settlementThermalReceipt(
                          widget.settlement,
                          copyBanner: kSettlementCustomerCopy,
                          forPrint: _forPrint,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ThermalReceiptCapture(
                        captureKey: _stationKey,
                        child: settlementThermalReceipt(
                          widget.settlement,
                          copyBanner: kSettlementStationCopy,
                          forPrint: _forPrint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: DsPillButton(
                      label: 'WhatsApp',
                      icon: Icons.chat_outlined,
                      variant: DsPillVariant.outline,
                      onPressed: _busy
                          ? null
                          : () {
                              unawaited(_share());
                            },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DsPillButton(
                      label: _busy ? 'Printing…' : 'Print',
                      icon: Icons.print_outlined,
                      onPressed: _busy
                          ? null
                          : () {
                              unawaited(_print());
                            },
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
