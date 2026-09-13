import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/constants.dart';
import '../domain/dispenser_models.dart';
import '../domain/money_format.dart';
import 'transaction_store.dart';

class LedgerPdfExport {
  LedgerPdfExport._();

  static final LedgerPdfExport instance = LedgerPdfExport._();

  Future<void> exportSales({
    required SalesLedgerSnapshot slice,
    int? unitId,
    DateTimeRange? range,
    String search = '',
    String? shiftLabel,
  }) async {
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) {
        return _buildSalesPdf(
          slice: slice,
          unitId: unitId,
          range: range,
          search: search,
          shiftLabel: shiftLabel,
          pageFormat: format.landscape,
        );
      },
      format: PdfPageFormat.a4.landscape,
      name: shiftLabel == null || shiftLabel.trim().isEmpty
          ? 'sales-ledger.pdf'
          : 'sales-ledger-${shiftLabel.split(' · ').first}.pdf',
    );
  }

  Future<void> exportPurchases({
    required PurchaseLedgerSnapshot slice,
    DateTimeRange? range,
  }) async {
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) {
        return _buildPurchasesPdf(
          slice: slice,
          range: range,
          pageFormat: format.landscape,
        );
      },
      format: PdfPageFormat.a4.landscape,
      name: 'purchase-ledger.pdf',
    );
  }

  Future<Uint8List> _buildSalesPdf({
    required SalesLedgerSnapshot slice,
    required int? unitId,
    required DateTimeRange? range,
    required String search,
    required String? shiftLabel,
    required PdfPageFormat pageFormat,
  }) async {
    final _PdfTheme theme = await _PdfTheme.load();
    final pw.Document doc = pw.Document();
    final List<String> headers = <String>[
      'Token',
      'Date & Time',
      'Unit',
      'Amount',
      'Liters',
      'Rate',
      'Opening',
      'Closing',
      'Payment',
      'Customer',
      'Vehicle',
      'Helper',
      'Cashier',
    ];
    final List<List<String>> data = <List<String>>[
      for (final SaleTransaction row in slice.rows)
        <String>[
          formatLedgerToken(row.tokenNo),
          formatDateTime(row.timestamp),
          formatUnitLabel(row.unitId),
          formatPkr(row.amountPkr),
          formatLiters(row.volumeLiters),
          formatRate(row.rate),
          formatMeterReading(row.openingMeter),
          formatMeterReading(row.closingMeter),
          row.udhaarSettled ? 'UDHAAR · SETTLED' : row.payment.ledgerPill,
          displayCustomerName(row.customerName),
          displayVehicleNo(row.vehicleNo),
          row.helperName.trim().isEmpty ? '—' : row.helperName,
          row.cashierName,
        ],
    ];

    doc.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.fromLTRB(16, 16, 16, 20),
        header: (pw.Context context) {
          return _header(
            theme: theme,
            title: 'Sales Ledger',
            filters: <String>[
              unitId == null ? 'All Units' : formatUnitLabel(unitId),
              if (shiftLabel != null && shiftLabel.trim().isNotEmpty)
                shiftLabel.trim(),
              _rangeLabel(range),
              if (search.trim().isNotEmpty) 'Search: ${search.trim()}',
            ],
            page: context.pageNumber,
            pages: context.pagesCount,
          );
        },
        footer: (pw.Context context) => _footer(theme),
        build: (pw.Context context) {
          return <pw.Widget>[
            _kpiRow(theme, <_KpiLine>[
              _KpiLine('Total Sales', formatPkr(slice.totalAmountPkr)),
              _KpiLine('Volume', formatLiters(slice.totalVolumeLiters)),
              _KpiLine('Udhaar Amount', formatPkr(slice.udhaarAmountPkr)),
              _KpiLine('Udhaar Txns', '${slice.udhaarCount}'),
            ]),
            pw.SizedBox(height: 12),
            _table(
              theme,
              headers,
              data,
              columnWidths: <int, pw.TableColumnWidth>{
                0: const pw.FlexColumnWidth(1.25),
                1: const pw.FlexColumnWidth(1.15),
                2: const pw.FlexColumnWidth(0.75),
                3: const pw.FlexColumnWidth(1.05),
                4: const pw.FlexColumnWidth(0.85),
                5: const pw.FlexColumnWidth(1.05),
                6: const pw.FlexColumnWidth(1.1),
                7: const pw.FlexColumnWidth(1.1),
                8: const pw.FlexColumnWidth(1.05),
                9: const pw.FlexColumnWidth(1.2),
                10: const pw.FlexColumnWidth(1.05),
                11: const pw.FlexColumnWidth(0.95),
                12: const pw.FlexColumnWidth(0.95),
              },
            ),
          ];
        },
      ),
    );
    return doc.save();
  }

  Future<Uint8List> _buildPurchasesPdf({
    required PurchaseLedgerSnapshot slice,
    required DateTimeRange? range,
    required PdfPageFormat pageFormat,
  }) async {
    final _PdfTheme theme = await _PdfTheme.load();
    final pw.Document doc = pw.Document();
    final List<String> headers = <String>[
      'Inv-No',
      'Date & Time',
      'Quantity',
      'Rate',
      'Amount',
      'Tafseel',
      'Users',
    ];
    final List<List<String>> data = <List<String>>[
      for (final PurchaseTransaction row in slice.rows)
        <String>[
          formatInvoiceNo(row.refNo),
          formatDateTime(row.timestamp),
          formatLiters(row.netLiters),
          formatTruncatedDecimal(row.ratePerLiter),
          formatPkr(row.totalAmount),
          row.tafseelDisplay,
          row.user,
        ],
    ];

    doc.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.fromLTRB(16, 16, 16, 20),
        header: (pw.Context context) {
          return _header(
            theme: theme,
            title: 'Purchase Ledger',
            filters: <String>[_rangeLabel(range)],
            page: context.pageNumber,
            pages: context.pagesCount,
          );
        },
        footer: (pw.Context context) => _footer(theme),
        build: (pw.Context context) {
          return <pw.Widget>[
            _kpiRow(theme, <_KpiLine>[
              _KpiLine('Total Amount', formatPkr(slice.totalAmountPkr)),
              _KpiLine('Net Volume', formatLiters(slice.totalVolumeLiters)),
              _KpiLine('Avg Rate', formatAverageRateValue(slice.averageRate)),
              _KpiLine(
                'Largest Delivery',
                formatLiters(slice.largestDeliveryLiters),
              ),
            ]),
            pw.SizedBox(height: 12),
            _table(theme, headers, data),
          ];
        },
      ),
    );
    return doc.save();
  }

  String _rangeLabel(DateTimeRange? range) {
    if (range == null) {
      return 'All dates';
    }
    return formatDateRangeLabel(range.start, range.end);
  }

  pw.Widget _header({
    required _PdfTheme theme,
    required String title,
    required List<String> filters,
    required int page,
    required int pages,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      padding: const pw.EdgeInsets.only(bottom: 10),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: theme.line)),
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
                    color: theme.coral,
                    font: theme.bold,
                    fontSize: 9,
                    letterSpacing: 1.2,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    color: theme.ink,
                    font: theme.bold,
                    fontSize: 16,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  filters.join('  ·  '),
                  style: pw.TextStyle(
                    color: theme.muted,
                    font: theme.regular,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
          pw.Text(
            'Page $page / $pages',
            style: pw.TextStyle(
              color: theme.muted,
              font: theme.regular,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _footer(_PdfTheme theme) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 8),
      child: pw.Text(
        'Exported ${formatDateTime(DateTime.now())}  ·  ${AppBrand.developer}',
        style: pw.TextStyle(
          color: theme.muted,
          font: theme.regular,
          fontSize: 8,
        ),
      ),
    );
  }

  pw.Widget _kpiRow(_PdfTheme theme, List<_KpiLine> items) {
    return pw.Row(
      children: <pw.Widget>[
        for (int i = 0; i < items.length; i++) ...<pw.Widget>[
          if (i > 0) pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              decoration: pw.BoxDecoration(
                color: theme.canvas,
                border: pw.Border.all(color: theme.line),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  pw.Text(
                    items[i].label.toUpperCase(),
                    style: pw.TextStyle(
                      color: theme.muted,
                      font: theme.bold,
                      fontSize: 7,
                      letterSpacing: 0.6,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    items[i].value,
                    style: pw.TextStyle(
                      color: theme.ink,
                      font: theme.bold,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  pw.Widget _table(
    _PdfTheme theme,
    List<String> headers,
    List<List<String>> data, {
    Map<int, pw.TableColumnWidth>? columnWidths,
  }) {
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      headerStyle: pw.TextStyle(
        color: theme.ink,
        font: theme.bold,
        fontSize: 6.5,
        letterSpacing: 0.3,
      ),
      cellStyle: pw.TextStyle(
        color: theme.ink,
        font: theme.regular,
        fontSize: 6.5,
      ),
      headerDecoration: pw.BoxDecoration(color: theme.canvas),
      headerAlignment: pw.Alignment.centerLeft,
      cellAlignment: pw.Alignment.centerLeft,
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      columnWidths: columnWidths,
      defaultColumnWidth: const pw.FlexColumnWidth(),
      tableWidth: pw.TableWidth.max,
      border: pw.TableBorder(
        horizontalInside: pw.BorderSide(color: theme.line, width: 0.4),
        bottom: pw.BorderSide(color: theme.line, width: 0.6),
      ),
    );
  }
}

class _KpiLine {
  const _KpiLine(this.label, this.value);

  final String label;
  final String value;
}

class _PdfTheme {
  const _PdfTheme({
    required this.regular,
    required this.bold,
    required this.ink,
    required this.muted,
    required this.coral,
    required this.line,
    required this.canvas,
  });

  final pw.Font regular;
  final pw.Font bold;
  final PdfColor ink;
  final PdfColor muted;
  final PdfColor coral;
  final PdfColor line;
  final PdfColor canvas;

  static Future<_PdfTheme> load() async {
    final ByteData regularData = await rootBundle.load(
      'assets/fonts/Roboto-Regular.ttf',
    );
    final ByteData boldData = await rootBundle.load(
      'assets/fonts/Roboto-Bold.ttf',
    );
    return _PdfTheme(
      regular: pw.Font.ttf(regularData),
      bold: pw.Font.ttf(boldData),
      ink: PdfColor.fromInt(0xFF211C1A),
      muted: PdfColor.fromInt(0xFF6F6560),
      coral: PdfColor.fromInt(0xFFF0785C),
      line: PdfColor.fromInt(0xFFEAD9D0),
      canvas: PdfColor.fromInt(0xFFFBEDE6),
    );
  }
}
