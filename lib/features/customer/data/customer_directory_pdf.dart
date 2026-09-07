import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/constants.dart';
import '../../station/domain/money_format.dart';
import '../domain/customer_models.dart';

class CustomerDirectoryPdf {
  CustomerDirectoryPdf._();

  static final CustomerDirectoryPdf instance = CustomerDirectoryPdf._();

  Future<void> export(List<CustomerProfile> customers) async {
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) {
        return _build(customers, format);
      },
      format: PdfPageFormat.a4,
      name: 'customer-directory.pdf',
    );
  }

  Future<Uint8List> _build(
    List<CustomerProfile> customers,
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

    final pw.Document doc = pw.Document();
    final List<List<String>> data = <List<String>>[
      for (final CustomerProfile row in customers) <String>[row.id, row.name],
    ];

    doc.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 28),
        header: (pw.Context context) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 14),
            padding: const pw.EdgeInsets.only(bottom: 10),
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
                          fontSize: 9,
                          letterSpacing: 1.2,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Customer Directory',
                        style: pw.TextStyle(
                          color: ink,
                          font: bold,
                          fontSize: 16,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        '${customers.length} accounts  ·  ID and name only',
                        style: pw.TextStyle(
                          color: muted,
                          font: regular,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Text(
                  'Page ${context.pageNumber} / ${context.pagesCount}',
                  style: pw.TextStyle(color: muted, font: regular, fontSize: 9),
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
              headers: <String>['Customer ID', 'Customer Name'],
              data: data,
              headerStyle: pw.TextStyle(
                color: ink,
                font: bold,
                fontSize: 10,
                letterSpacing: 0.3,
              ),
              cellStyle: pw.TextStyle(color: ink, font: regular, fontSize: 10),
              headerDecoration: pw.BoxDecoration(color: canvas),
              headerAlignment: pw.Alignment.centerLeft,
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              columnWidths: <int, pw.TableColumnWidth>{
                0: const pw.FlexColumnWidth(1),
                1: const pw.FlexColumnWidth(3),
              },
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
}
