import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants.dart';
import '../../../core/pdf_file_export.dart';
import '../../station/domain/dispenser_models.dart';
import '../../station/domain/money_format.dart';
import '../domain/shift_models.dart';
import '../domain/shift_report_layout.dart';

class ShiftPdfShareResult {
  const ShiftPdfShareResult({required this.file, required this.shared});

  final File file;
  final bool shared;
}

class ShiftSummaryExport {
  ShiftSummaryExport._();

  static final ShiftSummaryExport instance = ShiftSummaryExport._();

  static const String _stationTitle = '${AppBrand.name} ${AppBrand.tagline}';

  static const PdfPageFormat _sheetFormat = PdfPageFormat.a4;

  static const List<String> _saleHeaders = <String>[
    'Token',
    'DateTime',
    'Liters',
    'Rate',
    'Amount',
    'Opening',
    'Closing',
    'PM',
    'Ch Amount',
    'Ac Amount',
    'Customer / Vehicle',
  ];

  static const double _saleFontSize = 8;

  static const Map<int, pw.TableColumnWidth> _saleColumnWidths =
      <int, pw.TableColumnWidth>{
        0: pw.FlexColumnWidth(),
        1: pw.FlexColumnWidth(),
        2: pw.FlexColumnWidth(),
        3: pw.FlexColumnWidth(),
        4: pw.FlexColumnWidth(),
        5: pw.FlexColumnWidth(),
        6: pw.FlexColumnWidth(),
        7: pw.FlexColumnWidth(),
        8: pw.FlexColumnWidth(),
        9: pw.FlexColumnWidth(),
        10: pw.FlexColumnWidth(),
      };

  static const pw.EdgeInsets _cellPad = pw.EdgeInsets.symmetric(
    horizontal: 2,
    vertical: 3,
  );

  Future<File> printPdf(ShiftSummary summary, {bool showUnit5 = false}) async {
    return savePdf(summary, open: true, showUnit5: showUnit5);
  }

  Future<File> savePdf(
    ShiftSummary summary, {
    bool open = false,
    bool showUnit5 = false,
  }) async {
    final Uint8List bytes = await buildPdf(summary, showUnit5: showUnit5);
    final String stamp = _fileStamp(summary.shift.endTime ?? DateTime.now());
    final File file = await PdfFileExport.save(
      bytes: bytes,
      folder: 'Shifts',
      fileName: '${summary.shift.shiftId}-handover-$stamp.pdf',
    );
    if (open) {
      await PdfFileExport.open(file);
    }
    return file;
  }

  /// Saves the PDF under `Exported_Reports/Shifts/` and shares the file.
  /// WhatsApp URL schemes are a fallback only - never a text-only summary.
  Future<ShiftPdfShareResult> sharePdfViaWhatsApp(
    ShiftSummary summary, {
    bool showUnit5 = false,
  }) async {
    final File file = await savePdf(summary, showUnit5: showUnit5);
    final String name = p.basename(file.path);
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[
            XFile(file.path, mimeType: 'application/pdf', name: name),
          ],
          subject: '$_stationTitle · ${summary.shift.shiftId}',
        ),
      );
      return ShiftPdfShareResult(file: file, shared: true);
    } catch (error) {
      debugPrint('Shift PDF share sheet failed: $error');
    }
    final bool opened = await _openWhatsApp();
    return ShiftPdfShareResult(file: file, shared: opened);
  }

  Future<bool> shareWhatsApp(
    ShiftSummary summary, {
    bool showUnit5 = false,
  }) async {
    final ShiftPdfShareResult result = await sharePdfViaWhatsApp(
      summary,
      showUnit5: showUnit5,
    );
    return result.shared;
  }

  Future<bool> _openWhatsApp() async {
    final List<Uri> targets = <Uri>[
      Uri.parse('whatsapp://send'),
      Uri.parse('https://wa.me/'),
      Uri.parse('https://web.whatsapp.com/'),
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

  Future<Uint8List> buildPdf(
    ShiftSummary summary, {
    bool showUnit5 = false,
  }) async {
    final _ShiftPdfFonts fonts = await _ShiftPdfFonts.load();
    final OperatorShiftRecord shift = summary.shift;
    final ShiftWindowMetrics metrics = summary.metrics;
    final pw.Document doc = pw.Document(
      theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
    );
    final PdfColor ink = PdfColor.fromInt(0xFF211C1A);
    final PdfColor muted = PdfColor.fromInt(0xFF6F6560);
    final PdfColor coral = PdfColor.fromInt(0xFFF0785C);
    final PdfColor line = PdfColor.fromInt(0xFFEAD9D0);
    final PdfColor canvas = PdfColor.fromInt(0xFFFBEDE6);
    final PdfColor bad = PdfColor.fromInt(0xFFB42318);
    final double? actual = shift.actualCash;
    final String varianceText = actual == null
        ? '-'
        : _varianceCopy(actual - metrics.expectedCashInHand);
    final List<HelperSaleRecord> reportSales = shiftReportSalesChronological(
      metrics.sales,
      showUnit5: showUnit5,
    );
    final List<ShiftUnitReading> readings = buildShiftReportReadings(
      shift: shift,
      sales: metrics.sales,
      showUnit5: showUnit5,
    );
    final List<String> auditLines = shiftReportAuditLines(
      shift: shift,
      sales: metrics.sales,
      showUnit5: showUnit5,
    );
    final List<ShiftUnitSaleGroup> unitGroups = groupShiftReportSalesByUnit(
      metrics.sales,
      showUnit5: showUnit5,
    );
    final List<HelperSaleRecord> directSales = shiftReportDirectSales(
      metrics.directSales,
    );
    double reportLiters = 0;
    for (final HelperSaleRecord row in reportSales) {
      reportLiters += row.volumeLiters;
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: _sheetFormat,
        margin: const pw.EdgeInsets.all(20),
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
        footer: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.only(top: 8),
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: pw.TextStyle(color: muted, fontSize: 8),
              ),
            ),
          );
        },
        build: (pw.Context context) {
          return <pw.Widget>[
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: canvas,
                border: pw.Border.all(color: line),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  pw.Text(
                    _stationTitle.toUpperCase(),
                    style: pw.TextStyle(
                      color: coral,
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Shift Report',
                    style: pw.TextStyle(
                      color: ink,
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Wrap(
                    spacing: 20,
                    runSpacing: 4,
                    children: <pw.Widget>[
                      _headerChip(
                        ink,
                        muted,
                        'Outgoing operator',
                        shift.operatorName,
                      ),
                      _headerChip(ink, muted, 'Shift ID', shift.shiftId),
                      _headerChip(
                        ink,
                        muted,
                        'Start',
                        formatDateTime(shift.startTime),
                      ),
                      _headerChip(
                        ink,
                        muted,
                        'End',
                        shift.endTime == null
                            ? '-'
                            : formatDateTime(shift.endTime!),
                      ),
                      _headerChip(
                        ink,
                        muted,
                        'Duration',
                        formatShiftDuration(summary.duration),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),
            _sectionLabel(muted, 'FINANCIAL SUMMARY'),
            pw.SizedBox(height: 6),
            _kpiPills(
              ink: ink,
              muted: muted,
              line: line,
              canvas: canvas,
              items: <List<String>>[
                <String>['Total Sale', formatTablePkr(metrics.totalSale)],
                <String>['Udhaar Issued', formatTablePkr(metrics.udhaarSales)],
                <String>[
                  'Udhaar Recovery',
                  formatTablePkr(metrics.udhaarRecoveryCombined),
                ],
                <String>[
                  'Cash / Account',
                  'Cash: ${formatPkr(metrics.udhaarRecoveryTotal)}  |  Account: ${formatPkr(metrics.udhaarRecoveryAccountTotal)}',
                ],
                <String>[
                  'Account Payments',
                  formatTablePkr(metrics.accountSales),
                ],
                <String>[
                  'Expected cash in Hand',
                  formatTablePkr(metrics.expectedCashInHand),
                ],
                <String>[
                  'Actual Cash Collected',
                  actual == null ? '-' : formatTablePkr(actual),
                ],
                <String>['Variance', varianceText],
              ],
            ),
            pw.SizedBox(height: 12),
            _sectionLabel(muted, 'READINGS'),
            pw.SizedBox(height: 6),
            _readingsTable(
              ink: ink,
              muted: muted,
              line: line,
              canvas: canvas,
              readings: readings,
            ),
            pw.SizedBox(height: 12),
            _sectionLabel(muted, 'AUDIT REPORT'),
            pw.SizedBox(height: 6),
            if (auditLines.isEmpty)
              pw.Text(
                'No dispenser units to audit.',
                style: pw.TextStyle(color: muted, fontSize: 8),
              )
            else
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  for (final String line in auditLines)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 3),
                      child: pw.Text(
                        pdfSafeText(line),
                        style: pw.TextStyle(
                          color: line.contains('MISMATCH') ? bad : ink,
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          lineSpacing: 1.2,
                        ),
                      ),
                    ),
                ],
              ),
            pw.SizedBox(height: 12),
            _sectionLabel(
              muted,
              'ITEMIZED SALES  ·  ${shift.shiftId}  ·  ${shift.operatorName}',
            ),
            pw.SizedBox(height: 6),
            if (unitGroups.isEmpty)
              pw.Text(
                'No sales on this shift',
                style: pw.TextStyle(color: muted, fontSize: 8),
              )
            else ...<pw.Widget>[
              for (int i = 0; i < unitGroups.length; i++) ...<pw.Widget>[
                if (i > 0) pw.SizedBox(height: 10),
                _unitSalesTable(
                  ink: ink,
                  muted: muted,
                  line: line,
                  canvas: canvas,
                  group: unitGroups[i],
                ),
              ],
            ],
            pw.SizedBox(height: 12),
            _sectionLabel(muted, 'DIRECT SALES'),
            pw.SizedBox(height: 6),
            _directSalesTable(
              ink: ink,
              muted: muted,
              line: line,
              canvas: canvas,
              sales: directSales,
            ),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: <pw.Widget>[
                pw.Text(
                  '${reportSales.length} dispenser transaction'
                  '${reportSales.length == 1 ? '' : 's'}',
                  style: pw.TextStyle(
                    color: ink,
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'Total liters dispensed  ${formatTableLiters(reportLiters)}',
                  style: pw.TextStyle(
                    color: ink,
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (shift.notes.isNotEmpty) ...<pw.Widget>[
              pw.SizedBox(height: 10),
              _kv(ink, muted, 'Handover notes', shift.notes),
            ],
          ];
        },
      ),
    );
    return doc.save();
  }

  pw.Widget _sectionLabel(PdfColor muted, String label) {
    return pw.Text(
      label,
      style: pw.TextStyle(
        color: muted,
        fontSize: 8,
        fontWeight: pw.FontWeight.bold,
        letterSpacing: 0.7,
      ),
    );
  }

  pw.Widget _kpiPills({
    required PdfColor ink,
    required PdfColor muted,
    required PdfColor line,
    required PdfColor canvas,
    required List<List<String>> items,
  }) {
    pw.Widget rowOf(List<List<String>> cells, {int slots = 3}) {
      return pw.Row(
        children: <pw.Widget>[
          for (int i = 0; i < slots; i++) ...<pw.Widget>[
            if (i > 0) pw.SizedBox(width: 6),
            pw.Expanded(
              child: i < cells.length
                  ? _kpiPill(
                      ink: ink,
                      muted: muted,
                      line: line,
                      canvas: canvas,
                      label: cells[i][0],
                      value: cells[i][1],
                    )
                  : pw.SizedBox(),
            ),
          ],
        ],
      );
    }

    return pw.Column(
      children: <pw.Widget>[
        rowOf(items.sublist(0, 3)),
        pw.SizedBox(height: 6),
        rowOf(items.sublist(3, 6)),
        pw.SizedBox(height: 6),
        rowOf(items.sublist(6)),
      ],
    );
  }

  pw.Widget _kpiPill({
    required PdfColor ink,
    required PdfColor muted,
    required PdfColor line,
    required PdfColor canvas,
    required String label,
    required String value,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: pw.BoxDecoration(
        color: canvas,
        border: pw.Border.all(color: line),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(
            label.toUpperCase(),
            style: pw.TextStyle(
              color: muted,
              fontSize: 7,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 0.4,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            pdfSafeText(value),
            style: pw.TextStyle(
              color: ink,
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _readingsTable({
    required PdfColor ink,
    required PdfColor muted,
    required PdfColor line,
    required PdfColor canvas,
    required List<ShiftUnitReading> readings,
  }) {
    if (readings.isEmpty) {
      return pw.Text(
        'No dispenser readings for this shift',
        style: pw.TextStyle(color: muted, fontSize: 8),
      );
    }
    final List<List<String>> rows = <List<String>>[
      for (final ShiftUnitReading unit in readings)
        for (final ShiftRateReadingRow row in unit.rows)
          <String>[
            'Unit ${row.unitId}',
            row.rateLabel,
            row.opening == null ? '-' : formatMeterReading(row.opening!),
            row.closing == null ? '-' : formatMeterReading(row.closing!),
            row.dispensed == null ? '-' : formatTableLiters(row.dispensed!),
            formatTableLiters(row.testLiters),
            row.netVolume == null ? '-' : formatTableLiters(row.netVolume!),
            row.amountPkr == null
                ? '-'
                : formatTablePkr(row.amountPkr!.toDouble()),
          ],
    ];
    return _textTable(
      ink: ink,
      muted: muted,
      line: line,
      canvas: canvas,
      headers: const <String>[
        'Unit',
        'Rate',
        'Opening',
        'Closing',
        'Dispensed',
        'Test',
        'Net Volume',
        'Amount',
      ],
      rows: rows,
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FlexColumnWidth(0.9),
        1: pw.FlexColumnWidth(1.0),
        2: pw.FlexColumnWidth(1.05),
        3: pw.FlexColumnWidth(1.05),
        4: pw.FlexColumnWidth(1.05),
        5: pw.FlexColumnWidth(0.9),
        6: pw.FlexColumnWidth(1.15),
        7: pw.FlexColumnWidth(1.05),
      },
      numeric: const <int>{1, 2, 3, 4, 5, 6, 7},
    );
  }

  pw.Widget _unitSalesTable({
    required PdfColor ink,
    required PdfColor muted,
    required PdfColor line,
    required PdfColor canvas,
    required ShiftUnitSaleGroup group,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text(
          'UNIT ${group.unitId}',
          style: pw.TextStyle(
            color: ink,
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.SizedBox(
          width: double.infinity,
          child: pw.Table(
            border: pw.TableBorder.all(color: line, width: 0.5),
            tableWidth: pw.TableWidth.max,
            columnWidths: _saleColumnWidths,
            children: <pw.TableRow>[
              _headerRow(
                muted,
                canvas,
                _saleHeaders,
                fontSize: _saleFontSize,
              ),
              for (final HelperSaleRecord row in group.sales)
                pw.TableRow(
                  children: <pw.Widget>[
                    _cell(
                      ink,
                      formatLedgerToken(row.tokenNo),
                      fontSize: _saleFontSize,
                    ),
                    _cell(
                      ink,
                      formatShiftTableTime(row.timestamp),
                      fontSize: _saleFontSize,
                    ),
                    _cell(
                      ink,
                      formatTableLiters(row.volumeLiters),
                      numeric: true,
                      fontSize: _saleFontSize,
                    ),
                    _cell(
                      ink,
                      formatTableRate(row.rate),
                      numeric: true,
                      fontSize: _saleFontSize,
                    ),
                    _cell(
                      ink,
                      formatTablePkr(row.amountPkr),
                      numeric: true,
                      fontSize: _saleFontSize,
                    ),
                    _cell(
                      ink,
                      formatMeterReading(row.openingMeter),
                      numeric: true,
                      fontSize: _saleFontSize,
                    ),
                    _cell(
                      ink,
                      formatMeterReading(row.closingMeter),
                      numeric: true,
                      fontSize: _saleFontSize,
                    ),
                    _cell(
                      ink,
                      shiftSalePaymentLabel(row, short: true),
                      fontSize: _saleFontSize,
                    ),
                    _cell(
                      ink,
                      _tender(row.cashTender),
                      numeric: true,
                      fontSize: _saleFontSize,
                    ),
                    _cell(
                      ink,
                      _tender(shiftSaleAccountColumn(row, tenderFallback: true)),
                      numeric: true,
                      fontSize: _saleFontSize,
                    ),
                    _customerVehicleCell(ink, muted, row),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _directSalesTable({
    required PdfColor ink,
    required PdfColor muted,
    required PdfColor line,
    required PdfColor canvas,
    required List<HelperSaleRecord> sales,
  }) {
    if (sales.isEmpty) {
      return pw.Text(
        'No direct sales this shift',
        style: pw.TextStyle(color: muted, fontSize: 8),
      );
    }
    return _textTable(
      ink: ink,
      muted: muted,
      line: line,
      canvas: canvas,
      headers: const <String>[
        'TKN',
        'DateTime',
        'Liters',
        'Rate',
        'Amount',
        'Customer',
      ],
      rows: <List<String>>[
        for (final HelperSaleRecord row in sales)
          <String>[
            formatLedgerToken(row.tokenNo),
            formatShiftTableTime(row.timestamp),
            formatTableLiters(row.volumeLiters),
            formatTableRate(row.rate),
            formatTablePkr(row.amountPkr),
            _pdfCustomerName(row.customerName),
          ],
      ],
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FlexColumnWidth(1.4),
        1: pw.FlexColumnWidth(1.0),
        2: pw.FlexColumnWidth(1.0),
        3: pw.FlexColumnWidth(1.0),
        4: pw.FlexColumnWidth(1.2),
        5: pw.FlexColumnWidth(1.6),
      },
      numeric: const <int>{2, 3, 4},
    );
  }

  pw.Widget _textTable({
    required PdfColor ink,
    required PdfColor muted,
    required PdfColor line,
    required PdfColor canvas,
    required List<String> headers,
    required List<List<String>> rows,
    required Map<int, pw.TableColumnWidth> columnWidths,
    required Set<int> numeric,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(color: line, width: 0.5),
      columnWidths: columnWidths,
      children: <pw.TableRow>[
        _headerRow(muted, canvas, headers),
        for (final List<String> row in rows)
          pw.TableRow(
            children: <pw.Widget>[
              for (int i = 0; i < row.length; i++)
                _cell(ink, row[i], numeric: numeric.contains(i)),
            ],
          ),
      ],
    );
  }

  pw.TableRow _headerRow(
    PdfColor muted,
    PdfColor canvas,
    List<String> headers, {
    double fontSize = 7,
  }) {
    return pw.TableRow(
      decoration: pw.BoxDecoration(color: canvas),
      children: <pw.Widget>[
        for (final String header in headers)
          pw.Padding(
            padding: _cellPad,
            child: pw.Text(
              header,
              style: pw.TextStyle(
                color: muted,
                fontSize: fontSize,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  pw.Widget _cell(
    PdfColor ink,
    String text, {
    bool numeric = false,
    double fontSize = 7,
  }) {
    return pw.Padding(
      padding: _cellPad,
      child: pw.Text(
        pdfSafeText(text == '—' ? '-' : text),
        textAlign: numeric ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(color: ink, fontSize: fontSize),
      ),
    );
  }

  pw.Widget _customerVehicleCell(
    PdfColor ink,
    PdfColor muted,
    HelperSaleRecord row,
  ) {
    final String customer = _pdfCustomerName(row.customerName);
    final String vehicle = pdfSafeText(displayVehicleNo(row.vehicleNo));
    final bool hasVehicle = vehicle != '-' && vehicle != '—';
    return pw.Padding(
      padding: _cellPad,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(
            customer,
            style: pw.TextStyle(color: ink, fontSize: _saleFontSize),
          ),
          if (hasVehicle)
            pw.Text(
              vehicle,
              style: pw.TextStyle(color: muted, fontSize: _saleFontSize - 1),
            ),
        ],
      ),
    );
  }

  String _pdfCustomerName(String name) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty ||
        trimmed == '-' ||
        trimmed == '—' ||
        trimmed.toLowerCase() == 'walk-in') {
      return 'Walk-in';
    }
    return pdfSafeText(trimmed);
  }

  String _tender(double value) {
    final String text = formatTableTenderPkr(value);
    return text == '—' ? '-' : text;
  }

  pw.Widget _headerChip(
    PdfColor ink,
    PdfColor muted,
    String label,
    String value,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text(
          label.toUpperCase(),
          style: pw.TextStyle(
            color: muted,
            fontSize: 7,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        pw.Text(
          pdfSafeText(value),
          style: pw.TextStyle(
            color: ink,
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }

  pw.Widget _kv(PdfColor ink, PdfColor muted, String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.SizedBox(
            width: 120,
            child: pw.Text(
              label.toUpperCase(),
              style: pw.TextStyle(
                color: muted,
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              pdfSafeText(value),
              style: pw.TextStyle(
                color: ink,
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fileStamp(DateTime time) {
    final String y = time.year.toString().padLeft(4, '0');
    final String m = time.month.toString().padLeft(2, '0');
    final String d = time.day.toString().padLeft(2, '0');
    final String h = time.hour.toString().padLeft(2, '0');
    final String min = time.minute.toString().padLeft(2, '0');
    return '$y$m$d-$h$min';
  }

  String _varianceCopy(double variance) {
    if (variance > 0) {
      return 'Over  ${formatTableSignedPkr(variance)}';
    }
    if (variance < 0) {
      return 'Short  ${formatTableSignedPkr(variance)}';
    }
    return 'Matched  ${formatTablePkr(0)}';
  }
}

class _ShiftPdfFonts {
  const _ShiftPdfFonts({required this.regular, required this.bold});

  final pw.Font regular;
  final pw.Font bold;

  static Future<_ShiftPdfFonts> load() async {
    try {
      return _ShiftPdfFonts(
        regular: await PdfGoogleFonts.robotoRegular(),
        bold: await PdfGoogleFonts.robotoBold(),
      );
    } catch (error) {
      debugPrint('PdfGoogleFonts unavailable, using bundled Roboto: $error');
      final ByteData regularData = await rootBundle.load(
        'assets/fonts/Roboto-Regular.ttf',
      );
      final ByteData boldData = await rootBundle.load(
        'assets/fonts/Roboto-Bold.ttf',
      );
      return _ShiftPdfFonts(
        regular: pw.Font.ttf(regularData),
        bold: pw.Font.ttf(boldData),
      );
    }
  }
}

String shiftTokenRangeLabel(ShiftWindowMetrics metrics) {
  final int? first = metrics.firstToken;
  final int? last = metrics.lastToken;
  if (first == null || last == null) {
    return '-';
  }
  return '${formatLedgerToken(first)} -> ${formatLedgerToken(last)}';
}
