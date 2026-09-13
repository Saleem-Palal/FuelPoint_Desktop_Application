import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants.dart';
import '../../station/domain/dispenser_models.dart';
import '../../station/domain/money_format.dart';
import '../domain/shift_models.dart';

class ShiftPdfShareResult {
  const ShiftPdfShareResult({required this.file, required this.shared});

  final File file;
  final bool shared;
}

class ShiftSummaryExport {
  ShiftSummaryExport._();

  static final ShiftSummaryExport instance = ShiftSummaryExport._();

  static const String _stationTitle = '${AppBrand.name} ${AppBrand.tagline}';

  Future<void> printPdf(ShiftSummary summary) async {
    final Uint8List bytes = await buildPdf(summary);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => bytes,
      name: '${summary.shift.shiftId}-summary.pdf',
    );
  }

  Future<File> savePdf(ShiftSummary summary) async {
    final Uint8List bytes = await buildPdf(summary);
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory dir = Directory(
      p.join(docs.path, 'Exported_Reports', 'Shifts'),
    );
    await dir.create(recursive: true);
    final String stamp = _fileStamp(summary.shift.endTime ?? DateTime.now());
    final File file = File(
      p.join(dir.path, '${summary.shift.shiftId}-handover-$stamp.pdf'),
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Saves the PDF under `Exported_Reports/Shifts/` and shares the file.
  /// WhatsApp URL schemes are a fallback only — never a text-only summary.
  Future<ShiftPdfShareResult> sharePdfViaWhatsApp(ShiftSummary summary) async {
    final File file = await savePdf(summary);
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

  Future<bool> shareWhatsApp(ShiftSummary summary) async {
    final ShiftPdfShareResult result = await sharePdfViaWhatsApp(summary);
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

  Future<Uint8List> buildPdf(ShiftSummary summary) async {
    final ManagerShiftRecord shift = summary.shift;
    final ShiftWindowMetrics metrics = summary.metrics;
    final pw.Document doc = pw.Document();
    final PdfColor ink = PdfColor.fromInt(0xFF211C1A);
    final PdfColor muted = PdfColor.fromInt(0xFF6F6560);
    final PdfColor coral = PdfColor.fromInt(0xFFF0785C);
    final PdfColor line = PdfColor.fromInt(0xFFEAD9D0);
    final PdfColor canvas = PdfColor.fromInt(0xFFFBEDE6);
    final double? actual = shift.actualCash;
    final String varianceText = actual == null
        ? '—'
        : _varianceCopy(actual - shift.expectedCash);
    final List<List<String>> tableRows = metrics.sales.map((
      HelperSaleRecord row,
    ) {
      return <String>[
        formatLedgerToken(row.tokenNo),
        formatDateTime(row.timestamp),
        formatUnitLabel(row.unitId),
        row.fuelType.toUpperCase(),
        formatLiters(row.volumeLiters),
        formatRate(row.rate),
        formatPkr(row.amountPkr),
        row.payment.label,
      ];
    }).toList();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 32),
        footer: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.only(top: 8),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: <pw.Widget>[
                pw.Text(
                  'Expected cash = Cash sales + Udhaar recovery (cash). '
                  'Total sale = Cash sales + Account + Udhaar issued. '
                  '${AppBrand.developer}',
                  style: pw.TextStyle(color: muted, fontSize: 8),
                ),
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: pw.TextStyle(color: muted, fontSize: 8),
                ),
              ],
            ),
          );
        },
        build: (pw.Context context) {
          return <pw.Widget>[
            pw.Container(
              padding: const pw.EdgeInsets.all(14),
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
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Wrap(
                    spacing: 24,
                    runSpacing: 6,
                    children: <pw.Widget>[
                      _headerChip(
                        ink,
                        muted,
                        'Outgoing manager',
                        shift.managerName,
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
                            ? '—'
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
            pw.SizedBox(height: 14),
            pw.Text(
              'FINANCIAL SUMMARY',
              style: pw.TextStyle(
                color: muted,
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Table(
              columnWidths: <int, pw.TableColumnWidth>{
                0: const pw.FlexColumnWidth(),
                1: const pw.FlexColumnWidth(),
                2: const pw.FlexColumnWidth(),
                3: const pw.FlexColumnWidth(),
              },
              children: <pw.TableRow>[
                pw.TableRow(
                  children: <pw.Widget>[
                    _moneyCell(
                      ink,
                      muted,
                      line,
                      canvas,
                      'Direct cash sales',
                      formatPkr(metrics.fuelCashSales),
                    ),
                    _moneyCell(
                      ink,
                      muted,
                      line,
                      canvas,
                      'Udhaar issued',
                      formatPkr(metrics.udhaarSales),
                    ),
                    _moneyCell(
                      ink,
                      muted,
                      line,
                      canvas,
                      'Bank / account sales',
                      formatPkr(metrics.accountSales),
                    ),
                    _moneyCell(
                      ink,
                      muted,
                      line,
                      canvas,
                      'Udhaar recovery',
                      formatPkr(metrics.udhaarRecoveryTotal),
                    ),
                  ],
                ),
                pw.TableRow(
                  children: <pw.Widget>[
                    _moneyCell(
                      ink,
                      muted,
                      line,
                      canvas,
                      'Expected cash',
                      formatPkr(shift.expectedCash),
                    ),
                    _moneyCell(
                      ink,
                      muted,
                      line,
                      canvas,
                      'Actual cash',
                      actual == null ? '—' : formatPkr(actual),
                    ),
                    _moneyCell(
                      ink,
                      muted,
                      line,
                      canvas,
                      'Variance (over / short)',
                      varianceText,
                    ),
                    pw.SizedBox(),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              'ITEMIZED SALES  ·  ${shift.shiftId}  ·  ${shift.managerName}',
              style: pw.TextStyle(
                color: muted,
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              border: pw.TableBorder.all(color: line, width: 0.6),
              headerDecoration: pw.BoxDecoration(color: canvas),
              headerStyle: pw.TextStyle(
                color: muted,
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: pw.TextStyle(color: ink, fontSize: 8),
              cellAlignments: <int, pw.Alignment>{
                4: pw.Alignment.centerRight,
                5: pw.Alignment.centerRight,
                6: pw.Alignment.centerRight,
              },
              headers: const <String>[
                'Token #',
                'Date & Time',
                'Dispenser Unit',
                'Fuel Type',
                'Volume (L)',
                'Rate (PKR)',
                'Total Amount (PKR)',
                'Payment Method',
              ],
              data: tableRows.isEmpty
                  ? const <List<String>>[
                      <String>[
                        '—',
                        'No sales on this shift',
                        '',
                        '',
                        '',
                        '',
                        '',
                        '',
                      ],
                    ]
                  : tableRows,
            ),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: <pw.Widget>[
                pw.Text(
                  '${metrics.sales.length} transaction'
                  '${metrics.sales.length == 1 ? '' : 's'}',
                  style: pw.TextStyle(
                    color: ink,
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'Total liters dispensed  ${formatLiters(metrics.totalLiters)}',
                  style: pw.TextStyle(
                    color: ink,
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (shift.notes.isNotEmpty) ...<pw.Widget>[
              pw.SizedBox(height: 12),
              _kv(ink, muted, 'Handover notes', shift.notes),
            ],
          ];
        },
      ),
    );
    return doc.save();
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
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 0.6,
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            color: ink,
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }

  pw.Widget _moneyCell(
    PdfColor ink,
    PdfColor muted,
    PdfColor line,
    PdfColor canvas,
    String label,
    String value,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.fromLTRB(0, 0, 8, 8),
      child: pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          color: canvas,
          border: pw.Border.all(color: line),
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
                letterSpacing: 0.5,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              value,
              style: pw.TextStyle(
                color: ink,
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _kv(PdfColor ink, PdfColor muted, String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.SizedBox(
            width: 140,
            child: pw.Text(
              label.toUpperCase(),
              style: pw.TextStyle(
                color: muted,
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 0.6,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                color: ink,
                fontSize: 11,
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
      return 'Over  ${formatSignedPkr(variance)}';
    }
    if (variance < 0) {
      return 'Short  ${formatSignedPkr(variance)}';
    }
    return 'Matched  ${formatPkr(0)}';
  }
}

String shiftTokenRangeLabel(ShiftWindowMetrics metrics) {
  final int? first = metrics.firstToken;
  final int? last = metrics.lastToken;
  if (first == null || last == null) {
    return '—';
  }
  return '${formatLedgerToken(first)} → ${formatLedgerToken(last)}';
}
