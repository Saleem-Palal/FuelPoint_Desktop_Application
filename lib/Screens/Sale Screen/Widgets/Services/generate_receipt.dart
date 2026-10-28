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

enum ReceiptPrintKind { live, secondCopy, editedCopy }

/// Station copy, PDF layout, print, and share for the sale receipt.
class ReceiptCopy {
  static const String stationNameUrdu = 'شہید نذیر عمرانی پیٹرولیم سروس';
  static const String addressUrdu =
      'انڈسٹریل ایریا مین کوئٹہ روڈ ڈیرہ مراد جمالی';
  static const String staffLineUrdu =
      'پروپرائیٹر: حاجی عبدالحلیم عمرانی — مینیجر: لطیف عمرانی';
  static const String stationPhone = '0334 3706655';
  static const String complaintUrdu = 'کسی بھی قسم کی شکایت کے لیے رابطہ کریں';
  static const String thankYouUrdu =
      'آپ کا شکریہ — آپ کا بھروسہ ہماری اولین ترجیح۔';

  static const List<String> accountHandwritingLines = <String>[
    'Txn ID # ____________________',
    'Bank _______________________',
    'Account Title _______________',
  ];

  static List<String> handwritingLinesFor({
    required PaymentMethod payment,
    required bool stationCopy,
    ReceiptPrintKind kind = ReceiptPrintKind.live,
  }) {
    switch (payment) {
      case PaymentMethod.bankAccount:
      case PaymentMethod.easyPaisa:
        break;
      case PaymentMethod.cash:
      case PaymentMethod.udhaar:
        return const <String>[];
    }
    switch (kind) {
      case ReceiptPrintKind.live:
        return stationCopy ? accountHandwritingLines : const <String>[];
      case ReceiptPrintKind.secondCopy:
        return accountHandwritingLines;
      case ReceiptPrintKind.editedCopy:
        return const <String>[];
    }
  }

  static const String customerCopyBanner = 'COPY 1: CUSTOMER RECEIPT';
  static const String stationCopyBanner = 'COPY 2: STATION RECORD';
  static const String screenshotCopyBanner = 'COPY 3: TRANSFER SCREENSHOT';

  /// Station record slips for Account and Udhaar print without the footer.
  static bool showFooterFor({
    required PaymentMethod payment,
    required bool stationCopy,
  }) {
    if (!stationCopy) {
      return true;
    }
    switch (payment) {
      case PaymentMethod.bankAccount:
      case PaymentMethod.easyPaisa:
      case PaymentMethod.udhaar:
        return false;
      case PaymentMethod.cash:
        return true;
    }
  }

  static String printedSlipsMessage(SaleTransaction txn) {
    switch (txn.thermalSlipCount) {
      case 3:
        return '3 copies sent: customer, station, screenshot';
      case 2:
        return '2 copies sent to printer';
      default:
        return 'Receipt sent to printer';
    }
  }
  static const String secondCopyBanner = 'SECOND COPY';
  static const String editedCopyBanner = 'EDITED COPY';
  static const String recoveredBanner = 'RECOVERED TRANSACTION';

  static String? bannerFor({
    required PaymentMethod payment,
    required bool stationCopy,
    ReceiptPrintKind kind = ReceiptPrintKind.live,
    bool recovered = false,
  }) {
    if (recovered) {
      return recoveredBanner;
    }
    switch (kind) {
      case ReceiptPrintKind.secondCopy:
        return secondCopyBanner;
      case ReceiptPrintKind.editedCopy:
        return editedCopyBanner;
      case ReceiptPrintKind.live:
        if (!payment.printsTwoCopies) {
          return null;
        }
        return stationCopy ? stationCopyBanner : customerCopyBanner;
    }
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
    this.cashAmount = 0,
    this.accountAmount = 0,
  });

  factory ReceiptTicket.fromUnit({
    required DispenserUnit unit,
    required int tokenNo,
    required DateTime issuedAt,
  }) {
    return ReceiptTicket(
      issuedAt: issuedAt,
      unitId: unit.unitId,
      fuelType: unit.fuelType,
      tokenNo: tokenNo,
      liters: _lcdDigits(unit.lastLiters),
      rate: FuelFormatter.lcdAverageRate(unit.rate),
      amount: _lcdDigits(unit.lastRupees),
      cashierName: unit.lastCashier,
      customerName: unit.lastCustomer,
      vehicleNo: unit.lastVehicleNo,
      payment: unit.lastPayment,
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
      cashAmount: txn.cashAmount,
      accountAmount: txn.accountAmount,
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
  final double cashAmount;
  final double accountAmount;

  String get unitPad => unitId.toString().padLeft(2, '0');

  String get unitBadge => isDirectSaleUnit(unitId)
      ? 'Direct · $fuelType'
      : 'Unit $unitPad · $fuelType';

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

  String get tokenLabel => isDirectSaleToken(tokenNo)
      ? formatLedgerToken(tokenNo)
      : formatTokenNo(tokenNo);

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
    Object? lastError;
    for (int attempt = 0; attempt < 5; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      final BuildContext? context = previewKey.currentContext;
      if (context == null || !context.mounted) {
        lastError = StateError('Receipt preview is not on screen');
        continue;
      }
      final RenderObject? box;
      try {
        box = context.findRenderObject();
      } on FlutterError catch (error) {
        lastError = error;
        continue;
      }
      if (box is! RenderRepaintBoundary ||
          !box.attached ||
          !box.hasSize ||
          box.size.isEmpty) {
        lastError = StateError('Receipt preview cannot be captured');
        continue;
      }
      try {
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
      } on FlutterError catch (error) {
        lastError = error;
      }
    }
    final Object? error = lastError;
    if (error is FlutterError) {
      throw error;
    }
    throw error is StateError
        ? error
        : StateError('Receipt preview cannot be captured');
  }

  Future<Uint8List?> _pngFromImageFile(String path) async {
    try {
      final File file = File(path);
      if (!await file.exists()) {
        return null;
      }
      final Uint8List bytes = await file.readAsBytes();
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frame = await codec.getNextFrame();
      try {
        final ByteData? png = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (png == null) {
          return null;
        }
        return png.buffer.asUint8List();
      } finally {
        frame.image.dispose();
      }
    } catch (error, stack) {
      debugPrint('Screenshot page skipped: $error\n$stack');
      return null;
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

  Future<void> printPng(
    Uint8List png, {
    required String fileName,
    String? proofImagePath,
    Uint8List? screenshotPng,
  }) async {
    await printPngs(
      <Uint8List>[png],
      fileName: fileName,
      proofImagePath: proofImagePath,
      screenshotPng: screenshotPng,
    );
  }

  /// Sends each slip as its own print job.
  /// When [parallel] is true, jobs are submitted together.
  Future<void> printPngJobs(
    List<Uint8List> pngs, {
    required List<String> fileNames,
    Duration pause = const Duration(milliseconds: 250),
    bool parallel = false,
    String? proofImagePath,
    Uint8List? screenshotPng,
  }) async {
    if (pngs.length != fileNames.length) {
      throw ArgumentError('Each print job needs a file name');
    }
    if (parallel) {
      await Future.wait(<Future<void>>[
        for (int i = 0; i < pngs.length; i++)
          printPng(
            pngs[i],
            fileName: fileNames[i],
            proofImagePath: i == pngs.length - 1 ? proofImagePath : null,
            screenshotPng: i == pngs.length - 1 ? screenshotPng : null,
          ),
      ]);
      return;
    }
    for (int i = 0; i < pngs.length; i++) {
      await printPng(
        pngs[i],
        fileName: fileNames[i],
        proofImagePath: i == pngs.length - 1 ? proofImagePath : null,
        screenshotPng: i == pngs.length - 1 ? screenshotPng : null,
      );
      if (i < pngs.length - 1) {
        await Future<void>.delayed(pause);
      }
    }
  }

  Future<void> printCapturedPng(
    Uint8List png,
    ReceiptTicket ticket, {
    String? proofImagePath,
    Uint8List? screenshotPng,
  }) async {
    if (ticket.payment.printsTwoCopies) {
      await printDualCopies(
        customerPng: png,
        stationPng: png,
        ticket: ticket,
        proofImagePath: proofImagePath,
        screenshotPng: screenshotPng,
      );
      return;
    }
    await printPng(
      png,
      fileName: ticket.fileName,
      proofImagePath: ticket.payment.printsScreenshotCopy
          ? proofImagePath
          : null,
      screenshotPng: screenshotPng,
    );
  }

  Future<void> printDualCopies({
    required Uint8List customerPng,
    required Uint8List stationPng,
    required ReceiptTicket ticket,
    String? proofImagePath,
    Uint8List? screenshotPng,
  }) async {
    await printPngs(
      <Uint8List>[customerPng, stationPng],
      fileName: ticket.dualCopyFileNames.last,
      proofImagePath: ticket.payment.printsScreenshotCopy
          ? proofImagePath
          : null,
      screenshotPng: screenshotPng,
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
    String? proofImagePath,
    Uint8List? screenshotPng,
  }) async {
    if (!kIsWeb && Platform.isWindows) {
      try {
        await WindowsEscPosSpooler.instance.printPngs(
          pngs,
          proofImagePath: proofImagePath,
          screenshotPng: screenshotPng,
        );
        return;
      } catch (error, stack) {
        debugPrint('ESC/POS spool failed: $error\n$stack');
      }
    }
    final List<Uint8List> pages = List<Uint8List>.from(pngs);
    if (screenshotPng != null && screenshotPng.isNotEmpty) {
      pages.add(screenshotPng);
    } else {
      final String proof = proofImagePath?.trim() ?? '';
      if (proof.isNotEmpty) {
        final Uint8List? shot = await _pngFromImageFile(proof);
        if (shot != null) {
          pages.add(shot);
        }
      }
    }
    final Uint8List pdfBytes = await _pdfFromPngs(pages);
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
}
