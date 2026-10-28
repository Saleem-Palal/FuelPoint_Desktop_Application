import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/constants.dart';
import '../../../core/pdf_file_export.dart';
import '../../../core/pdf_sheet.dart';
import '../../../core/pdf_typeface.dart';
import '../../station/domain/money_format.dart';
import '../domain/customer_models.dart';

class CustomerLedgerPdf {
  CustomerLedgerPdf._();

  static final CustomerLedgerPdf instance = CustomerLedgerPdf._();

  Future<File> export(CustomerAccount account) async {
    final Uint8List bytes = await _build(account, PdfPageFormat.a4.landscape);
    final String id = _fileSlug(account.profile.id);
    final String name = _fileSlug(account.profile.name);
    return PdfFileExport.saveAndOpen(
      bytes: bytes,
      folder: 'Customers',
      fileName: 'udhaar-$id-$name.pdf',
    );
  }

  Future<Uint8List> _build(
    CustomerAccount account,
    PdfPageFormat pageFormat,
  ) async {
    await Future<void>.delayed(Duration.zero);
    final PdfTypeface faces = await PdfTypeface.load();
    final CustomerProfile profile = account.profile;
    final pw.Document doc = pw.Document(theme: faces.theme);
    final PdfSheet sheet = PdfSheet(
      pageFormat: pageFormat,
      theme: faces.theme,
      regular: faces.regular,
      bold: faces.bold,
      margin: const pw.EdgeInsets.fromLTRB(16, 16, 16, 20),
      brand: AppBrand.name,
      title: 'Unified Udhaar Ledger',
      subtitle:
          '${profile.id}  ·  ${profile.name}  ·  Outstanding ${formatPkrStatement(account.outstanding)}  ·  ${account.ledger.length} rows',
      footerText:
          'Exported ${formatDateTime(DateTime.now())}  ·  ${AppBrand.developer}',
    );
    sheet.table(
      headers: const <String>[
        'Primary Key',
        'Type',
        'TKN',
        'Date & Time',
        'Liters',
        'Rate',
        'Amount',
        'Cash',
        'Account',
        'Description',
        'Vehicle',
        'Udhaar',
        'Paid',
        'Remaining',
        'Proof',
      ],
      rows: <List<String>>[
        for (final CustomerLedgerLine line in account.ledger)
          <String>[
            line.ledgerId,
            line.isSale ? 'SALE' : 'SETTLEMENT',
            line.tokenLabel,
            formatDateTime(line.at),
            line.volumeLiters == null
                ? '-'
                : formatTruncatedDecimal(line.volumeLiters!),
            line.rate == null ? '-' : formatTableRate(line.rate!),
            formatTablePkr(line.amountPkr),
            line.settlementCashPkr == null
                ? '-'
                : formatTablePkr(line.settlementCashPkr!),
            line.settlementAccountPkr == null
                ? '-'
                : formatTablePkr(line.settlementAccountPkr!),
            line.description,
            line.vehicleLabel,
            line.debitPkr > 0 ? formatTablePkr(line.debitPkr) : '-',
            line.creditPkr > 0 ? formatTablePkr(line.creditPkr) : '-',
            formatTablePkr(line.runningBalance),
            (line.settlement?.proofImagePath.trim().isNotEmpty ?? false)
                ? 'Yes'
                : '-',
          ],
      ],
      numeric: const <int>{4, 5, 6, 7, 8, 11, 12, 13},
      fontSize: 7,
      grid: false,
      headerInk: PdfPalette.ink,
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    );
    await sheet.write(doc);
    return doc.save(enableEventLoopBalancing: true);
  }

  static String _fileSlug(String raw) {
    final String cleaned = raw.trim().replaceAll(
      RegExp(r'[^A-Za-z0-9_-]+'),
      '-',
    );
    final String collapsed = cleaned.replaceAll(RegExp(r'-{2,}'), '-');
    final String trimmed = collapsed.replaceAll(RegExp(r'^-+|-+$'), '');
    return trimmed.isEmpty ? 'customer' : trimmed;
  }
}
