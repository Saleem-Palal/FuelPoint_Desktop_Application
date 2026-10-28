import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:decimal/decimal.dart';

import '../../../core/constants.dart';
import '../../../core/pdf_file_export.dart';
import '../../../core/pdf_sheet.dart';
import '../../../core/pdf_typeface.dart';
import '../../../services/database_helper.dart';
import '../../customer/data/sqlite_unified_udhaar_repository.dart';
import '../../customer/domain/customer_models.dart';
import '../../station/domain/dispenser_models.dart';
import '../../station/domain/fuel_precision.dart';
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

  static const List<String> _udhaarHeaders = <String>[
    'PK / TKN',
    'DateTime',
    'Customer / ID',
    'Liters',
    'Rate',
    'Amount',
    'Cash',
    'Account',
    'Udhaar',
    'Paid',
    'Remaining',
    'Vehicle No',
  ];

  static const Set<int> _udhaarNumeric = <int>{3, 4, 5, 6, 7, 8, 9, 10};

  static const List<String> _accountHeaders = <String>[
    'TKN',
    'DateTime',
    'Liters',
    'Rate',
    'Amount',
    'Cash',
    'Account',
    'Vehicle No',
  ];

  static const Set<int> _accountNumeric = <int>{2, 3, 4, 5, 6};

  Future<File> printPdf(
    ShiftSummary summary, {
    bool showUnit5 = false,
    int? unitId,
  }) async {
    return savePdf(summary, open: true, showUnit5: showUnit5, unitId: unitId);
  }

  Future<File> savePdf(
    ShiftSummary summary, {
    bool open = false,
    bool showUnit5 = false,
    int? unitId,
  }) async {
    final Uint8List bytes = await buildPdf(
      summary,
      showUnit5: showUnit5,
      unitId: unitId,
      udhaarLedger: await _udhaarLedgerFor(summary.shift.shiftId),
    );
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
    int? unitId,
  }) async {
    final File file = await savePdf(
      summary,
      showUnit5: showUnit5,
      unitId: unitId,
    );
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
    int? unitId,
  }) async {
    final ShiftPdfShareResult result = await sharePdfViaWhatsApp(
      summary,
      showUnit5: showUnit5,
      unitId: unitId,
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
    int? unitId,
    List<UnifiedUdhaarRow> udhaarLedger = const <UnifiedUdhaarRow>[],
  }) async {
    await Future<void>.delayed(Duration.zero);
    final PdfTypeface fonts = await PdfTypeface.load();
    final OperatorShiftRecord shift = summary.shift;
    final ShiftWindowMetrics metrics = summary.metrics;
    final pw.Document doc = pw.Document(theme: fonts.theme);
    final double? actual = shift.actualCash;
    final List<HelperSaleRecord> reportSales = shiftReportSalesChronological(
      metrics.sales,
      showUnit5: showUnit5,
      unitId: unitId,
    );
    final List<ShiftUnitReading> readings = buildShiftReportReadings(
      shift: shift,
      sales: metrics.sales,
      showUnit5: showUnit5,
      unitId: unitId,
    );
    final _ReadingsTotals readingTotals = _ReadingsTotals.of(readings);
    final List<ShiftUnitSaleGroup> unitGroups = groupShiftReportSalesByUnit(
      metrics.sales,
      showUnit5: showUnit5,
      unitId: unitId,
    );
    final bool showDirectSales = includeShiftReportDirectSales(unitId: unitId);
    final bool showDispenserSections =
        unitId == null || !isDirectSaleUnit(unitId);
    final double reportTotalSale = showDispenserSections
        ? readingTotals.amountPkr.toDouble()
        : metrics.totalSale;
    final double cashOnlySales = metrics.cashOnlySalesFromReadings(
      reportTotalSale,
    );
    final double expectedCash = metrics.expectedCashInHandFrom(reportTotalSale);
    final String varianceText = actual == null
        ? '-'
        : _varianceCopy(actual - expectedCash);
    final List<HelperSaleRecord> directSales = shiftReportDirectSales(
      metrics.directSales,
      unitId: unitId,
    );
    double reportLiters = 0;
    for (final HelperSaleRecord row in reportSales) {
      reportLiters += row.volumeLiters;
    }

    final PdfSheet flow = PdfSheet(
      pageFormat: _sheetFormat,
      theme: fonts.theme,
      regular: fonts.regular,
      bold: fonts.bold,
      margin: const pw.EdgeInsets.all(20),
    );
    flow.banner(
      kicker: _stationTitle,
      title: 'Shift Report',
      chips: <List<String>>[
        <String>['Outgoing operator', shift.operatorName],
        <String>['Shift ID', shift.shiftId],
        <String>['Start', formatDateTime(shift.startTime)],
        <String>[
          'End',
          shift.endTime == null ? '-' : formatDateTime(shift.endTime!),
        ],
        <String>['Duration', formatShiftDuration(summary.duration)],
        if (unitId != null) <String>['Units', formatUnitLabel(unitId)],
      ],
    );
    flow.section('FINANCIAL SUMMARY');
    flow.kpis(<List<String>>[
      <String>['Total Sale', formatTablePkr(reportTotalSale)],
      <String>['Cash only Sales', formatTablePkr(cashOnlySales)],
      <String>[
        'Udhaar Issued',
        '${formatTablePkr(metrics.udhaarSales)}\n'
            'Cash Now Udhaar: ${formatPkr(metrics.cashNowUdhaar)}',
      ],
      <String>[
        'Udhaar Recovery',
        '${formatTablePkr(metrics.udhaarRecoveryCombined)}\n'
            'Cash: ${formatPkr(metrics.udhaarRecoveryTotal)}  |  '
            'Account: ${formatPkr(metrics.udhaarRecoveryAccountTotal)}',
      ],
      <String>[
        'Account Payments',
        '${formatTablePkr(metrics.accountTicketTotal)}\n'
            'Account: ${formatPkr(metrics.accountSales)}  |  '
            'Cash Now Account: ${formatPkr(metrics.cashNow)}',
      ],
      <String>['Expected cash in Hand', formatTablePkr(expectedCash)],
      <String>[
        'Actual Cash Collected',
        actual == null ? '-' : formatTablePkr(actual),
      ],
      <String>['Variance', varianceText],
    ]);
    if (showDispenserSections) {
      flow.section('READINGS');
      final List<List<String>> readingRows = <List<String>>[
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
      if (readingRows.isNotEmpty) {
        readingRows.add(<String>[
          'Total',
          ' ',
          ' ',
          ' ',
          readingTotals.hasDispensed
              ? formatTableLiters(readingTotals.dispensed)
              : '-',
          formatTableLiters(readingTotals.testLiters),
          readingTotals.hasNetVolume
              ? formatTableLiters(readingTotals.netVolume)
              : '-',
          formatTablePkr(readingTotals.amountPkr.toDouble()),
        ]);
      }
      if (readingRows.isEmpty) {
        flow.note('No dispenser readings for this shift');
      } else {
        flow.table(
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
          rows: readingRows,
          numeric: const <int>{1, 2, 3, 4, 5, 6, 7},
          flex: const <int, double>{
            0: 0.9,
            1: 1,
            2: 1.05,
            3: 1.05,
            4: 1.05,
            5: 0.9,
            6: 1.15,
            7: 1.05,
          },
        );
      }
      _writeUdhaarSection(
        flow,
        ledger: udhaarLedger,
        sales: <HelperSaleRecord>[...metrics.sales, ...metrics.directSales],
      );
      _writeAccountSection(
        flow,
        sales: <HelperSaleRecord>[...metrics.sales, ...metrics.directSales],
        showUnit5: showUnit5,
        unitId: unitId,
      );
      flow.section(
        'ITEMIZED SALES  ·  ${shift.shiftId}  ·  ${shift.operatorName}',
      );
      if (unitGroups.isEmpty) {
        flow.note('No sales on this shift');
      } else {
        for (final ShiftUnitSaleGroup group in unitGroups) {
          flow.table(
            caption: unitGroups.length > 1 ? 'UNIT ${group.unitId}' : null,
            headers: _saleHeaders,
            fontSize: 8,
            numeric: const <int>{2, 3, 4, 5, 6, 8, 9},
            contentDriven: true,
            padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3),
            rows: <List<String>>[
              for (final HelperSaleRecord row in group.sales)
                _itemizedSaleRow(row),
              _itemizedTotalRow(group.sales),
            ],
          );
        }
      }
    } else {
      _writeUdhaarSection(
        flow,
        ledger: udhaarLedger,
        sales: <HelperSaleRecord>[...metrics.sales, ...metrics.directSales],
      );
      _writeAccountSection(
        flow,
        sales: <HelperSaleRecord>[...metrics.sales, ...metrics.directSales],
        showUnit5: showUnit5,
        unitId: unitId,
      );
    }
    if (showDirectSales) {
      flow.section('DIRECT SALES');
      if (directSales.isEmpty) {
        flow.note('No direct sales this shift');
      } else {
        flow.table(
          headers: const <String>[
            'TKN',
            'DateTime',
            'Liters',
            'Rate',
            'Amount',
            'Customer',
          ],
          numeric: const <int>{2, 3, 4},
          contentDriven: true,
          rows: <List<String>>[
            for (final HelperSaleRecord row in directSales)
              <String>[
                formatLedgerToken(row.tokenNo),
                formatShiftTableTime(row.timestamp),
                formatTableLiters(row.volumeLiters),
                formatTableRate(row.rate),
                formatTablePkr(row.amountPkr),
                _pdfCustomerName(row.customerName),
              ],
          ],
        );
      }
    }
    flow.gap(8);
    flow.totals(
      showDispenserSections
          ? '${reportSales.length} dispenser transaction${reportSales.length == 1 ? '' : 's'}'
          : '${directSales.length} direct sale${directSales.length == 1 ? '' : 's'}',
      'Total liters dispensed  ${formatTableLiters(showDispenserSections ? reportLiters : _directSaleLiters(directSales))}',
    );
    if (shift.notes.isNotEmpty) {
      flow.gap(10);
      flow.kv('Handover notes', shift.notes);
    }
    await flow.write(doc);
    return doc.save(enableEventLoopBalancing: true);
  }

  void _writeAccountSection(
    PdfSheet flow, {
    required List<HelperSaleRecord> sales,
    required bool showUnit5,
    int? unitId,
  }) {
    flow.section('ACCOUNT');
    final List<HelperSaleRecord> rows = shiftReportAccountSales(
      sales,
      showUnit5: showUnit5,
      unitId: unitId,
    );
    if (rows.isEmpty) {
      flow.note('ACCOUNT TRANSACTIONS  ·  No account sales this shift');
      return;
    }
    flow.table(
      caption: 'ACCOUNT TRANSACTIONS',
      headers: _accountHeaders,
      fontSize: 8,
      numeric: _accountNumeric,
      contentDriven: true,
      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3),
      rows: <List<String>>[
        for (final HelperSaleRecord row in rows) _accountDataRow(row),
        _accountTotalRow(rows),
      ],
    );
  }

  List<String> _accountDataRow(HelperSaleRecord row) {
    return <String>[
      formatLedgerToken(row.tokenNo),
      formatShiftTableTime(row.timestamp),
      formatTableLiters(row.volumeLiters),
      formatTableRate(row.rate),
      formatTablePkr(row.amountPkr),
      _tender(row.cashTender),
      _tender(shiftSaleAccountColumn(row, tenderFallback: true)),
      _pdfVehicle(row.vehicleNo),
    ];
  }

  List<String> _accountTotalRow(List<HelperSaleRecord> rows) {
    final ShiftItemizedSaleTotals totals = ShiftItemizedSaleTotals.of(rows);
    return <String>[
      'Total',
      ' ',
      formatTableLiters(totals.liters),
      ' ',
      formatTablePkr(totals.amountPkr.toDouble()),
      formatTablePkr(totals.cashPkr.toDouble()),
      formatTablePkr(totals.accountPkr.toDouble()),
      ' ',
    ];
  }

  void _writeUdhaarSection(
    PdfSheet flow, {
    required List<UnifiedUdhaarRow> ledger,
    required List<HelperSaleRecord> sales,
  }) {
    flow.section('UDHAAR');
    final List<ShiftUdhaarLine> recovery = <ShiftUdhaarLine>[
      for (final UnifiedUdhaarRow row in shiftUdhaarRecoveryRows(ledger))
        ShiftUdhaarLine.of(
          row,
          sale: shiftSaleForUdhaarToken(row.tokenLabel, sales),
        ),
    ];
    final List<ShiftUdhaarLine> issued = <ShiftUdhaarLine>[
      for (final UnifiedUdhaarRow row in shiftUdhaarIssuedRows(ledger))
        ShiftUdhaarLine.of(
          row,
          sale: shiftSaleForUdhaarToken(row.tokenLabel, sales),
        ),
    ];
    _writeUdhaarTable(
      flow,
      caption: 'UDHAAR RECOVERY',
      emptyNote: 'No udhaar recoveries this shift',
      lines: recovery,
    );
    _writeUdhaarTable(
      flow,
      caption: 'UDHAAR ISSUED',
      emptyNote: 'No udhaar issued this shift',
      lines: issued,
    );
  }

  void _writeUdhaarTable(
    PdfSheet flow, {
    required String caption,
    required String emptyNote,
    required List<ShiftUdhaarLine> lines,
  }) {
    if (lines.isEmpty) {
      flow.note('$caption  ·  $emptyNote');
      return;
    }
    flow.table(
      caption: caption,
      headers: _udhaarHeaders,
      fontSize: 7,
      numeric: _udhaarNumeric,
      contentDriven: true,
      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3),
      rows: <List<String>>[
        for (final ShiftUdhaarLine line in lines) _udhaarDataRow(line),
        _udhaarTotalRow(lines),
      ],
    );
  }

  List<String> _udhaarDataRow(ShiftUdhaarLine line) {
    final UnifiedUdhaarRow row = line.row;
    return <String>[
      _udhaarKeyCell(row),
      formatShiftTableTime(row.at),
      _udhaarCustomerCell(row),
      line.hasFuel ? formatTableLiters(row.liters) : '-',
      line.hasFuel ? formatTableRate(row.rate) : '-',
      formatTablePkr(line.amountPkr),
      _tender(line.cashPkr),
      _tender(line.accountPkr),
      _tender(row.udhaarPkr),
      _tender(row.paidPkr),
      formatTablePkr(row.remainingPkr),
      _pdfVehicle(row.vehicle),
    ];
  }

  List<String> _udhaarTotalRow(List<ShiftUdhaarLine> lines) {
    final ShiftUdhaarTableTotals totals = ShiftUdhaarTableTotals.of(lines);
    return <String>[
      'Total',
      ' ',
      ' ',
      formatTableLiters(totals.liters),
      ' ',
      formatTablePkr(totals.amountPkr.toDouble()),
      formatTablePkr(totals.cashPkr.toDouble()),
      formatTablePkr(totals.accountPkr.toDouble()),
      formatTablePkr(totals.udhaarPkr.toDouble()),
      formatTablePkr(totals.paidPkr.toDouble()),
      ' ',
      ' ',
    ];
  }

  String _udhaarKeyCell(UnifiedUdhaarRow row) {
    final String token = (row.tokenLabel ?? '').trim();
    if (token.isEmpty) {
      return row.primaryKey;
    }
    return '${row.primaryKey} / $token';
  }

  String _udhaarCustomerCell(UnifiedUdhaarRow row) {
    final String name = row.customerName.trim().isEmpty
        ? '-'
        : row.customerName.trim();
    final String id = row.customerId.trim();
    if (id.isEmpty) {
      return name;
    }
    return '$name / $id';
  }

  String _pdfVehicle(String vehicle) {
    final String text = displayVehicleNo(vehicle);
    return text == '—' ? '-' : text;
  }

  Future<List<UnifiedUdhaarRow>> _udhaarLedgerFor(String shiftId) async {
    try {
      final List<Map<String, Object?>> rows = await DatabaseHelper.instance
          .queryUnifiedUdhaarLedger(shiftId: shiftId);
      return rows.map(SqliteUnifiedUdhaarRepository.fromRow).toList();
    } catch (error) {
      debugPrint('Shift PDF udhaar ledger failed: $error');
      return const <UnifiedUdhaarRow>[];
    }
  }

  List<String> _itemizedSaleRow(HelperSaleRecord row) {
    return <String>[
      formatLedgerToken(row.tokenNo),
      formatShiftTableTime(row.timestamp),
      formatTableLiters(row.volumeLiters),
      formatTableRate(row.rate),
      formatTablePkr(row.amountPkr),
      formatMeterReading(row.openingMeter),
      formatMeterReading(row.closingMeter),
      shiftSalePaymentLabel(row, short: true),
      _tender(row.cashTender),
      _tender(shiftSaleAccountColumn(row, tenderFallback: true)),
      _saleParty(row),
    ];
  }

  List<String> _itemizedTotalRow(List<HelperSaleRecord> sales) {
    final ShiftItemizedSaleTotals totals = ShiftItemizedSaleTotals.of(sales);
    return <String>[
      'Total',
      ' ',
      formatTableLiters(totals.liters),
      ' ',
      formatTablePkr(totals.amountPkr.toDouble()),
      ' ',
      ' ',
      ' ',
      formatTablePkr(totals.cashPkr.toDouble()),
      formatTablePkr(totals.accountPkr.toDouble()),
      ' ',
    ];
  }

  String _saleParty(HelperSaleRecord row) {
    final String customer = _pdfCustomerName(row.customerName);
    final String vehicle = displayVehicleNo(row.vehicleNo);
    if (vehicle == '-' || vehicle == '—') {
      return customer;
    }
    return '$customer / $vehicle';
  }

  String _pdfCustomerName(String name) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty ||
        trimmed == '-' ||
        trimmed == '—' ||
        trimmed.toLowerCase() == 'walk-in') {
      return 'Walk-in';
    }
    return trimmed;
  }

  String _tender(double value) {
    final String text = formatTableTenderPkr(value);
    return text == '—' ? '-' : text;
  }

  double _directSaleLiters(List<HelperSaleRecord> sales) {
    double liters = 0;
    for (final HelperSaleRecord row in sales) {
      liters += row.volumeLiters;
    }
    return liters;
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

class _ReadingsTotals {
  const _ReadingsTotals({
    required this.dispensed,
    required this.testLiters,
    required this.netVolume,
    required this.amountPkr,
    required this.hasDispensed,
    required this.hasNetVolume,
  });

  final double dispensed;
  final double testLiters;
  final double netVolume;
  final int amountPkr;
  final bool hasDispensed;
  final bool hasNetVolume;

  static _ReadingsTotals of(List<ShiftUnitReading> readings) {
    Decimal dispensed = Decimal.zero;
    Decimal testLiters = Decimal.zero;
    Decimal netVolume = Decimal.zero;
    int amountPkr = 0;
    bool hasDispensed = false;
    bool hasNetVolume = false;
    for (final ShiftUnitReading unit in readings) {
      for (final ShiftRateReadingRow row in unit.rows) {
        final double? dispensedLiters = row.dispensed;
        if (dispensedLiters != null) {
          dispensed = truncateFuel(dispensed + parseDecimal(dispensedLiters));
          hasDispensed = true;
        }
        testLiters = truncateFuel(testLiters + parseDecimal(row.testLiters));
        final double? net = row.netVolume;
        if (net != null) {
          netVolume = truncateFuel(netVolume + parseDecimal(net));
          hasNetVolume = true;
        }
        final int? amount = row.amountPkr;
        if (amount != null) {
          amountPkr += amount;
        }
      }
    }
    return _ReadingsTotals(
      dispensed: dispensed.toDouble(),
      testLiters: testLiters.toDouble(),
      netVolume: netVolume.toDouble(),
      amountPkr: amountPkr,
      hasDispensed: hasDispensed,
      hasNetVolume: hasNetVolume,
    );
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
