import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants.dart';
import '../../../../features/station/domain/dispenser_models.dart';
import '../../../../features/station/domain/money_format.dart';

/// Station copy, PDF layout, print, and share for the sale receipt.
class ReceiptCopy {
  static const String stationNameUrdu = 'شہید نذیر عمرانی پیٹرولیم سروس';
  static const String addressUrdu =
      'انڈسٹریل ایریا مین کوئٹہ روڈ ڈیرہ مراد جمالی';
  static const String staffLineUrdu =
      'پروپرائیٹر: حاجی عبدالحلیم عمرانی — مینیجر: لطیف عمرانی';
  static const String stationPhone = '0334 3706655';
  static const String thankYouUrdu =
      'آپ کا شکریہ — آپ کا بھروسہ ہماری اولین ترجیح۔';

  static const String developerName = AppBrand.developer;
  static const String developerFooter =
      'Developer: ${AppBrand.developer} · WhatsApp Support: 0331 245518';
  static const String developerPitchUrdu =
      'کسی بھی قسم کا سافٹ ویئر بنوانے کے لیے رابطہ کریں';

  static const String urduFontFamily = 'NotoNastaliqUrdu';
  static const String latinFontFamily = 'Roboto';
  static const String lcdFontFamily = 'DSEG7Classic';
  static const String lcdLabelFontFamily = 'DSEG14ClassicMini';
}

/// Plain-int color helpers shared with the on-screen ticket.
class ColorData {
  static const int paper = 0xFFFDF9F6;
  static const int ink = 0xFF211C1A;
  static const int lcdAmber = 0xFFFA9500;
  static const int lcdInset = 0xFF1C1A17;
  static const int steel = 0xFF3D5A80;
  static const int printTerracotta = 0xFFC9603E;
  static const int whatsAppGreen = 0xFF3C8A5C;
}

class ReceiptTicket {
  const ReceiptTicket({
    required this.issuedAt,
    required this.unitId,
    required this.fuelType,
    required this.tokenNo,
    required this.liters,
    required this.rate,
    required this.amount,
    required this.cashierName,
    required this.customerName,
    required this.vehicleNo,
    required this.payment,
  });

  factory ReceiptTicket.fromBay({
    required DispenserBay bay,
    required int tokenNo,
    required DateTime issuedAt,
  }) {
    return ReceiptTicket(
      issuedAt: issuedAt,
      unitId: bay.unitId,
      fuelType: bay.fuelType,
      tokenNo: tokenNo,
      liters: _lcdDigits(bay.lastLiters),
      rate: bay.rate.toStringAsFixed(2),
      amount: _lcdDigits(bay.lastRupees),
      cashierName: bay.lastCashier,
      customerName: bay.lastCustomer,
      vehicleNo: bay.lastVehicleNo,
      payment: bay.lastPayment,
    );
  }

  factory ReceiptTicket.fromTransaction(SaleTransaction txn) {
    return ReceiptTicket(
      issuedAt: txn.timestamp,
      unitId: txn.unitId,
      fuelType: txn.fuelType,
      tokenNo: txn.tokenNo,
      liters: txn.volumeLiters.toStringAsFixed(2),
      rate: txn.rate.toStringAsFixed(2),
      amount: txn.amountPkr.toStringAsFixed(2),
      cashierName: txn.cashierName,
      customerName: txn.customerName,
      vehicleNo: txn.vehicleNo,
      payment: txn.payment,
    );
  }

  final DateTime issuedAt;
  final int unitId;
  final String fuelType;
  final int tokenNo;
  final String liters;
  final String rate;
  final String amount;
  final String cashierName;
  final String customerName;
  final String vehicleNo;
  final PaymentMethod payment;

  String get unitPad => unitId.toString().padLeft(2, '0');

  String get unitBadge => 'Unit $unitPad · $fuelType';

  String get dateLabel {
    final String day = issuedAt.day.toString().padLeft(2, '0');
    final String month = issuedAt.month.toString().padLeft(2, '0');
    return '$day-$month-${issuedAt.year}';
  }

  String get timeLabel => formatClock(issuedAt);

  String get vehicleDisplay {
    final String trimmed = vehicleNo.trim();
    if (trimmed.isEmpty) {
      return '—';
    }
    return trimmed;
  }

  String get paymentLabel => payment.label;

  String get tokenLabel => formatTokenNo(tokenNo);

  String get fileName => 'receipt-$tokenLabel.pdf';

  String get pngFileName => 'receipt-$tokenLabel.png';

  static String _lcdDigits(String raw) {
    return raw
        .replaceFirst('Rs. ', '')
        .replaceFirst(' Ltr', '')
        .replaceAll(',', '');
  }
}

class ReceiptGenerator {
  ReceiptGenerator._();

  static final ReceiptGenerator instance = ReceiptGenerator._();

  /// Snapshot of the on-screen [ThermalReceiptView] — same fonts and layout.
  Future<Uint8List> capturePreview(
    GlobalKey previewKey, {
    double pixelRatio = 3,
  }) async {
    final BuildContext? context = previewKey.currentContext;
    if (context == null) {
      throw StateError('Receipt preview is not on screen');
    }
    await WidgetsBinding.instance.endOfFrame;
    final RenderObject? box = context.findRenderObject();
    if (box is! RenderRepaintBoundary) {
      throw StateError('Receipt preview cannot be captured');
    }
    if (box.debugNeedsPaint) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    final ui.Image image = await box.toImage(pixelRatio: pixelRatio);
    try {
      final ByteData? bytes = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (bytes == null) {
        throw StateError('Receipt snapshot failed');
      }
      return bytes.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  Future<Uint8List> _pdfFromPng(Uint8List png) async {
    final ui.Codec codec = await ui.instantiateImageCodec(png);
    final ui.FrameInfo frame = await codec.getNextFrame();
    final int widthPx = frame.image.width;
    final int heightPx = frame.image.height;
    frame.image.dispose();
    if (widthPx <= 0 || heightPx <= 0) {
      throw StateError('Receipt snapshot is empty');
    }

    final double pageWidth = 80 * PdfPageFormat.mm;
    final double pageHeight = pageWidth * (heightPx / widthPx);
    final pw.MemoryImage image = pw.MemoryImage(png);
    final pw.Document pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(pageWidth, pageHeight, marginAll: 0),
        build: (pw.Context context) {
          return pw.Image(image, fit: pw.BoxFit.fill);
        },
      ),
    );
    return pdf.save();
  }

  String _whatsAppCaption(ReceiptTicket ticket) {
    return <String>[
      ReceiptCopy.stationNameUrdu,
      'Token ${ticket.tokenLabel}',
      ticket.unitBadge,
      'Date ${ticket.dateLabel}  ${ticket.timeLabel}',
      'Amount  Rs. ${ticket.amount}',
      'Liters  ${ticket.liters}',
      'Rate  ${ticket.rate}',
      'Customer  ${ticket.customerName}',
      'Vehicle  ${ticket.vehicleDisplay}',
      'Payment  ${ticket.paymentLabel}',
      'Cashier  ${ticket.cashierName}',
    ].join('\n');
  }

  Future<File> _writeTempFile(String name, Uint8List bytes) async {
    final Directory dir = await getTemporaryDirectory();
    final File file = File(p.join(dir.path, name));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<bool> _openWhatsApp(String text) async {
    final String encoded = Uri.encodeComponent(text);
    final List<Uri> targets = <Uri>[
      Uri.parse('whatsapp://send?text=$encoded'),
      Uri.parse('https://wa.me/?text=$encoded'),
      Uri.parse('https://web.whatsapp.com/send?text=$encoded'),
    ];
    for (final Uri uri in targets) {
      try {
        final bool launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) {
          return true;
        }
      } catch (error) {
        debugPrint('WhatsApp launch failed ($uri): $error');
      }
    }
    return false;
  }

  Future<void> printPreview(
    GlobalKey previewKey,
    ReceiptTicket ticket,
  ) async {
    final Uint8List png = await capturePreview(previewKey);
    final Uint8List pdfBytes = await _pdfFromPng(png);
    try {
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
        name: ticket.fileName,
      );
      return;
    } catch (error, stack) {
      debugPrint('Print layout failed: $error\n$stack');
    }
    final File file = await _writeTempFile(ticket.fileName, pdfBytes);
    final bool opened = await launchUrl(
      Uri.file(file.path),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      throw Exception('Could not open the print dialog');
    }
  }

  Future<void> sharePreview(
    GlobalKey previewKey,
    ReceiptTicket ticket,
  ) async {
    final Uint8List png = await capturePreview(previewKey);
    final File file = await _writeTempFile(ticket.pngFileName, png);
    final String caption = _whatsAppCaption(ticket);
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[
            XFile(
              file.path,
              mimeType: 'image/png',
              name: ticket.pngFileName,
            ),
          ],
          text: caption,
          subject: 'Receipt ${ticket.tokenLabel}',
        ),
      );
      return;
    } catch (error) {
      debugPrint('Share sheet failed: $error');
    }
    final bool whatsAppOpened = await _openWhatsApp(caption);
    if (whatsAppOpened) {
      return;
    }
    final bool openedFile = await launchUrl(
      Uri.file(file.path),
      mode: LaunchMode.externalApplication,
    );
    if (!openedFile) {
      throw Exception('Could not share the receipt');
    }
  }
}
