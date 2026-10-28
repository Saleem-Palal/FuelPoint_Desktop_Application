import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/constants.dart';
import '../../../core/pdf_file_export.dart';
import '../../../core/pdf_sheet.dart';
import '../../../core/pdf_text.dart';
import '../../../core/pdf_typeface.dart';
import '../domain/dispenser_models.dart';
import '../domain/money_format.dart';
import 'transaction_store.dart';

class LedgerPdfExport {
  LedgerPdfExport._();

  static final LedgerPdfExport instance = LedgerPdfExport._();

  Future<File> exportSales({
    required SalesLedgerSnapshot slice,
    int? unitId,
    DateTimeRange? range,
    String search = '',
    String? shiftLabel,
  }) async {
    final Uint8List bytes = await buildSalesPdf(
      slice: slice,
      unitId: unitId,
      range: range,
      search: search,
      shiftLabel: shiftLabel,
      pageFormat: PdfPageFormat.a4.landscape,
    );
    final String name = shiftLabel == null || shiftLabel.trim().isEmpty
        ? 'sales-ledger.pdf'
        : 'sales-ledger-${shiftLabel.split(' · ').first}.pdf';
    return PdfFileExport.saveAndOpen(
      bytes: bytes,
      folder: 'Ledgers',
      fileName: name,
    );
  }

  Future<File> exportPurchases({
    required PurchaseLedgerSnapshot slice,
    DateTimeRange? range,
  }) async {
    final Uint8List bytes = await buildPurchasesPdf(
      slice: slice,
      range: range,
      pageFormat: PdfPageFormat.a4.landscape,
    );
    return PdfFileExport.saveAndOpen(
      bytes: bytes,
      folder: 'Ledgers',
      fileName: 'purchase-ledger.pdf',
    );
  }

  Future<Uint8List> buildSalesPdf({
    required SalesLedgerSnapshot slice,
    required int? unitId,
    required DateTimeRange? range,
    required String search,
    required String? shiftLabel,
    required PdfPageFormat pageFormat,
  }) async {
    await Future<void>.delayed(Duration.zero);
    final PdfTypeface faces = await PdfTypeface.load();
    final pw.Document doc = pw.Document(theme: faces.theme);
    final PdfSheet sheet = _sheet(
      faces: faces,
      pageFormat: pageFormat,
      title: 'Sales Ledger',
      subtitle: <String>[
        unitId == null ? 'All Units' : formatUnitLabel(unitId),
        if (shiftLabel != null && shiftLabel.trim().isNotEmpty)
          shiftLabel.trim(),
        _rangeLabel(range),
        if (search.trim().isNotEmpty) 'Search: ${search.trim()}',
      ].join('  ·  '),
      repeatTitle: false,
    );
    sheet.kpis(<List<String>>[
      <String>['Total Sales', formatTablePkr(slice.totalAmountPkr)],
      <String>[
        'Volume',
        '${formatTableLiters(slice.physicalVolumeLiters)}\n'
            'Real volume: ${formatTableLiters(slice.totalVolumeLiters)} | '
            'Test volume: ${formatTableLiters(slice.testVolumeLiters)}',
      ],
      <String>['Udhaar Amount', formatTablePkr(slice.udhaarAmountPkr)],
      <String>['Udhaar Txns', '${slice.udhaarCount}'],
    ], rounded: false);
    sheet.gap(6);
    sheet.table(
      headers: const <String>[
        'Token',
        'Date & Time',
        'Unit',
        'Amount',
        'Liters',
        'Rate',
        'Opening',
        'Closing',
        'Payment',
        'Cash',
        'Account',
        'Customer',
        'Vehicle',
        'Helper',
        'Operator',
      ],
      rows: <List<String>>[
        for (final SaleTransaction row in slice.rows)
          <String>[
            formatLedgerToken(row.tokenNo),
            formatDateTime(row.timestamp),
            formatUnitLabel(row.unitId),
            formatTablePkr(row.amountPkr),
            formatTableLiters(row.volumeLiters),
            formatTableRate(row.rate),
            formatMeterReading(row.openingMeter),
            formatMeterReading(row.closingMeter),
            row.isTest
                ? 'Test'
                : row.isAccountPending
                ? '${row.payment.ledgerPill} · PENDING'
                : (row.udhaarSettled
                      ? 'UDHAAR · SETTLED'
                      : row.payment.ledgerPill),
            formatTableTenderPkr(row.cashAmount),
            formatTableTenderPkr(row.receiptAccountAmount),
            displayCustomerName(row.customerName),
            displayVehicleNo(row.vehicleNo),
            row.helperName.trim().isEmpty ? '-' : row.helperName,
            row.cashierName,
          ],
      ],
      flex: const <int, double>{
        0: 1.25,
        1: 1.15,
        2: 0.75,
        3: 1.05,
        4: 0.85,
        5: 1.05,
        6: 1.1,
        7: 1.1,
        8: 1.05,
        9: 1.2,
        10: 1.05,
        11: 0.95,
        12: 0.95,
        13: 0.95,
        14: 0.95,
      },
      numeric: const <int>{3, 4, 5, 6, 7, 9, 10},
      fontSize: 6.5,
      grid: false,
      headerInk: PdfPalette.ink,
    );
    await sheet.write(doc);
    return doc.save(enableEventLoopBalancing: true);
  }

  Future<Uint8List> buildPurchasesPdf({
    required PurchaseLedgerSnapshot slice,
    required DateTimeRange? range,
    required PdfPageFormat pageFormat,
  }) async {
    await Future<void>.delayed(Duration.zero);
    final PdfTypeface faces = await PdfTypeface.load();
    final pw.Document doc = pw.Document(theme: faces.theme);
    final PdfSheet sheet = _sheet(
      faces: faces,
      pageFormat: pageFormat,
      title: 'Purchase Ledger',
      subtitle: _rangeLabel(range),
    );
    sheet.kpis(<List<String>>[
      <String>['Total Amount', formatTablePkr(slice.totalAmountPkr)],
      <String>['Net Volume', formatTableLiters(slice.totalVolumeLiters)],
      <String>['Avg Rate', formatTableRate(slice.averageRate)],
      <String>[
        'Largest Delivery',
        formatTableLiters(slice.largestDeliveryLiters),
      ],
    ], rounded: false);
    sheet.gap(12);
    sheet.table(
      headers: const <String>[
        'Inv-No',
        'Date & Time',
        'Quantity',
        'Rate',
        'Amount',
        'Tafseel',
        'Users',
      ],
      rows: <List<String>>[
        for (final PurchaseTransaction row in slice.rows)
          <String>[
            formatInvoiceNo(row.refNo),
            formatDateTime(row.timestamp),
            formatTableLiters(row.netLiters),
            formatTableRate(row.ratePerLiter),
            formatTablePkr(row.totalAmount),
            row.tafseelDisplay,
            row.user,
          ],
      ],
      numeric: const <int>{2, 3, 4},
      fontSize: 8,
      grid: false,
      headerInk: PdfPalette.ink,
    );
    await sheet.write(doc);
    return doc.save(enableEventLoopBalancing: true);
  }

  PdfSheet _sheet({
    required PdfTypeface faces,
    required PdfPageFormat pageFormat,
    required String title,
    required String subtitle,
    bool repeatTitle = true,
  }) {
    return PdfSheet(
      pageFormat: pageFormat,
      theme: faces.theme,
      regular: faces.regular,
      bold: faces.bold,
      margin: const pw.EdgeInsets.fromLTRB(18, 22, 18, 26),
      brand: AppBrand.name,
      title: title,
      subtitle: subtitle,
      footerText:
          'Exported ${formatDateTime(DateTime.now())}  ·  ${AppBrand.developer}',
      repeatTitle: repeatTitle,
    );
  }

  String _rangeLabel(DateTimeRange? range) {
    if (range == null) {
      return 'All dates';
    }
    return pdfSafeText(formatDateRangeLabel(range.start, range.end));
  }
}
