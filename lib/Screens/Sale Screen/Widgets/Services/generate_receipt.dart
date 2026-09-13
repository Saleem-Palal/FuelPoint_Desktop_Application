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

import '../../../../features/station/data/windows_escpos_spooler.dart';
import '../../../../features/station/domain/dispenser_models.dart';
import '../../../../features/station/domain/money_format.dart';
import '../../../../utils/fuel_formatter.dart';

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

  static const String customerCopyBanner = 'COPY 1: CUSTOMER RECEIPT';
  static const String stationCopyBanner = 'COPY 2: STATION RECORD';

  static String? bannerFor({
    required PaymentMethod payment,
    required bool stationCopy,
  }) {
    if (!payment.printsTwoCopies) {
      return null;
    }
    return stationCopy ? stationCopyBanner : customerCopyBanner;
  }

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
    this.helperName = '',
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
      rate: FuelFormatter.lcdAverageRate(bay.rate),
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
      liters: FuelFormatter.lcdVolume(txn.volumeLiters),
      rate: FuelFormatter.lcdAverageRate(txn.rate),
      amount: FuelFormatter.lcdDispenserAmount(txn.amountPkr),
      cashierName: txn.cashierName,
      helperName: txn.helperName,
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
  final String helperName;
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

  String get helperDisplay {
    final String trimmed = helperName.trim();
    if (trimmed.isEmpty) {
      return '—';
    }
    return trimmed;
  }

  String get paymentLabel => payment.label;

  String get tokenLabel => formatTokenNo(tokenNo);

  String get fileName => 'receipt-$tokenLabel.pdf';

  String get pngFileName => 'receipt-$tokenLabel.png';

  List<String> get dualCopyFileNames => <String>[
    'receipt-$tokenLabel-customer.pdf',
    'receipt-$tokenLabel-station.pdf',
  ];

  List<String> get udhaarCopyFileNames => dualCopyFileNames;

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

  /// Fallback PDF envelope if RAW ESC/POS is unavailable.
  static const PdfPageFormat thermal80 = PdfPageFormat(
    80 * PdfPageFormat.mm,
    double.infinity,
    marginAll: 3 * PdfPageFormat.mm,
  );

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

  Future<Uint8List> _pdfFromPngs(List<Uint8List> pngs) async {
    if (pngs.isEmpty) {
      throw StateError('Receipt snapshot is empty');
    }
    final pw.Document pdf = pw.Document();
    for (final Uint8List png in pngs) {
      final pw.MemoryImage image = pw.MemoryImage(png);
      pdf.addPage(
        pw.Page(
          pageFormat: thermal80,
          build: (pw.Context context) {
            return pw.Align(
              alignment: pw.Alignment.topCenter,
              child: pw.Image(image, fit: pw.BoxFit.fitWidth),
            );
          },
        ),
      );
    }
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
      'Manager  ${ticket.cashierName}',
      'Helper  ${ticket.helperDisplay}',
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

  Future<void> printPng(Uint8List png, {required String fileName}) async {
    await printPngs(<Uint8List>[png], fileName: fileName);
  }

  /// Sends each slip as its own print job.
  /// When [parallel] is true, jobs are submitted together.
  Future<void> printPngJobs(
    List<Uint8List> pngs, {
    required List<String> fileNames,
    Duration pause = const Duration(milliseconds: 250),
    bool parallel = false,
  }) async {
    if (pngs.length != fileNames.length) {
      throw ArgumentError('Each print job needs a file name');
    }
    if (parallel) {
      await Future.wait(<Future<void>>[
        for (int i = 0; i < pngs.length; i++)
          printPng(pngs[i], fileName: fileNames[i]),
      ]);
      return;
    }
    for (int i = 0; i < pngs.length; i++) {
      await printPng(pngs[i], fileName: fileNames[i]);
      if (i < pngs.length - 1) {
        await Future<void>.delayed(pause);
      }
    }
  }

  Future<void> printCapturedPng(Uint8List png, ReceiptTicket ticket) async {
    if (ticket.payment.printsTwoCopies) {
      await printDualCopies(
        customerPng: png,
        stationPng: png,
        ticket: ticket,
      );
      return;
    }
    await printPng(png, fileName: ticket.fileName);
  }

  Future<void> printDualCopies({
    required Uint8List customerPng,
    required Uint8List stationPng,
    required ReceiptTicket ticket,
  }) async {
    await printPngJobs(
      <Uint8List>[customerPng, stationPng],
      fileNames: ticket.dualCopyFileNames,
      parallel: true,
    );
  }

  Future<void> printUdhaarCopies({
    required Uint8List customerPng,
    required Uint8List stationPng,
    required ReceiptTicket ticket,
  }) async {
    await printDualCopies(
      customerPng: customerPng,
      stationPng: stationPng,
      ticket: ticket,
    );
  }

  Future<void> printPngs(
    List<Uint8List> pngs, {
    required String fileName,
  }) async {
    if (!kIsWeb && Platform.isWindows) {
      try {
        await WindowsEscPosSpooler.instance.printPngs(pngs);
        return;
      } catch (error, stack) {
        debugPrint('ESC/POS spool failed: $error\n$stack');
      }
    }
    final Uint8List pdfBytes = await _pdfFromPngs(pngs);
    final bool printed = await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: fileName,
      format: thermal80,
      dynamicLayout: false,
    );
    if (!printed) {
      throw Exception('Print cancelled or the printer did not accept the job');
    }
  }

  Future<void> printPreview(GlobalKey previewKey, ReceiptTicket ticket) async {
    final Uint8List png = await capturePreview(previewKey);
    await printCapturedPng(png, ticket);
  }

  Future<void> printPreviewPng(
    GlobalKey previewKey, {
    required String fileName,
  }) async {
    final Uint8List png = await capturePreview(previewKey);
    await printPng(png, fileName: fileName);
  }

  Future<void> sharePng({
    required Uint8List png,
    required String fileName,
    required String caption,
    String? subject,
  }) async {
    final File file = await _writeTempFile(fileName, png);
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[
            XFile(file.path, mimeType: 'image/png', name: fileName),
          ],
          text: caption,
          subject: subject,
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

  Future<void> sharePreview(GlobalKey previewKey, ReceiptTicket ticket) async {
    final Uint8List png = await capturePreview(previewKey);
    await sharePng(
      png: png,
      fileName: ticket.pngFileName,
      caption: _whatsAppCaption(ticket),
      subject: 'Receipt ${ticket.tokenLabel}',
    );
  }
}
