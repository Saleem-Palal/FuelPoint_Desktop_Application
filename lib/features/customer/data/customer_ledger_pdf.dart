import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/constants.dart';
import '../../../core/pdf_file_export.dart';
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
    final ByteData regularData = await rootBundle.load(
      'assets/fonts/Roboto-Regular.ttf',
    );
    final ByteData boldData = await rootBundle.load(
      'assets/fonts/Roboto-Bold.ttf',
    );
    final pw.Font regular = pw.Font.ttf(regularData);
    final pw.Font bold = pw.Font.ttf(boldData);
    final PdfColor ink = PdfColor.fromInt(0xFF211C1A);
    final PdfColor muted = PdfColor.fromInt(0xFF6F6560);
    final PdfColor coral = PdfColor.fromInt(0xFFF0785C);
    final PdfColor line = PdfColor.fromInt(0xFFEAD9D0);
    final PdfColor canvas = PdfColor.fromInt(0xFFFBEDE6);

    final CustomerProfile profile = account.profile;
    final List<List<String>> data = <List<String>>[
      for (final CustomerLedgerLine line in account.ledger)
        <String>[
          line.ledgerId,
          line.isSale ? 'SALE' : 'SETTLEMENT',
          line.tokenLabel,
          formatDateTime(line.at),
          line.volumeLiters == null
              ? '—'
              : formatTruncatedDecimal(line.volumeLiters!),
          line.rate == null ? '—' : formatTableRate(line.rate!),
          formatTablePkr(line.amountPkr),
          line.description,
          line.vehicleLabel,
          line.debitPkr > 0 ? formatTablePkr(line.debitPkr) : '—',
          line.creditPkr > 0 ? formatTablePkr(line.creditPkr) : '—',
          formatTablePkr(line.runningBalance),
        ],
    ];

    final pw.Document doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.fromLTRB(16, 16, 16, 20),
        header: (pw.Context context) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 12),
            padding: const pw.EdgeInsets.only(bottom: 8),
            decoration: pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: line)),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: <pw.Widget>[
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: <pw.Widget>[
                      pw.Text(
                        AppBrand.name.toUpperCase(),
                        style: pw.TextStyle(
                          color: coral,
                          font: bold,
                          fontSize: 8,
                          letterSpacing: 1.2,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Unified Udhaar Ledger',
                        style: pw.TextStyle(
                          color: ink,
                          font: bold,
                          fontSize: 14,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        '${profile.id}  ·  ${profile.name}  ·  Outstanding ${formatPkrStatement(account.outstanding)}  ·  ${account.ledger.length} rows',
                        style: pw.TextStyle(
                          color: muted,
                          font: regular,
                          fontSize: 8,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Text(
                  'Page ${context.pageNumber} / ${context.pagesCount}',
                  style: pw.TextStyle(color: muted, font: regular, fontSize: 8),
                ),
              ],
            ),
          );
        },
        footer: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.only(top: 8),
            child: pw.Text(
              'Exported ${formatDateTime(DateTime.now())}  ·  ${AppBrand.developer}',
              style: pw.TextStyle(color: muted, font: regular, fontSize: 8),
            ),
          );
        },
        build: (pw.Context context) {
          return <pw.Widget>[
            pw.TableHelper.fromTextArray(
              headers: const <String>[
                'Primary Key',
                'Type',
                'TKN',
                'Date & Time',
                'Liters',
                'Rate',
                'Amount',
                'Description',
                'Vehicle',
                'Udhaar',
                'Paid',
                'Remaining',
              ],
              data: data,
              headerStyle: pw.TextStyle(
                color: ink,
                font: bold,
                fontSize: 7,
                letterSpacing: 0.2,
              ),
              cellStyle: pw.TextStyle(color: ink, font: regular, fontSize: 7),
              headerDecoration: pw.BoxDecoration(color: canvas),
              headerAlignment: pw.Alignment.centerLeft,
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 4,
              ),
              border: pw.TableBorder(
                horizontalInside: pw.BorderSide(color: line, width: 0.4),
                bottom: pw.BorderSide(color: line, width: 0.6),
              ),
            ),
          ];
        },
      ),
    );
    return doc.save();
  }

  static String _fileSlug(String raw) {
    final String cleaned = raw.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-');
    final String collapsed = cleaned.replaceAll(RegExp(r'-{2,}'), '-');
    final String trimmed = collapsed.replaceAll(RegExp(r'^-+|-+$'), '');
    return trimmed.isEmpty ? 'customer' : trimmed;
  }
}
