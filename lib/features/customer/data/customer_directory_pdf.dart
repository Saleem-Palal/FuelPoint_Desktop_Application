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

class CustomerDirectoryPdf {
  CustomerDirectoryPdf._();

  static final CustomerDirectoryPdf instance = CustomerDirectoryPdf._();

  Future<File> export(List<CustomerProfile> customers) async {
    final Uint8List bytes = await _build(customers, PdfPageFormat.a4);
    return PdfFileExport.saveAndOpen(
      bytes: bytes,
      folder: 'Customers',
      fileName: 'customer-directory.pdf',
    );
  }

  Future<Uint8List> _build(
    List<CustomerProfile> customers,
    PdfPageFormat pageFormat,
  ) async {
    await Future<void>.delayed(Duration.zero);
    final PdfTypeface faces = await PdfTypeface.load();
    final pw.Document doc = pw.Document(theme: faces.theme);
    final PdfSheet sheet = PdfSheet(
      pageFormat: pageFormat,
      theme: faces.theme,
      regular: faces.regular,
      bold: faces.bold,
      margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 28),
      brand: AppBrand.name,
      title: 'Customer Directory',
      subtitle: '${customers.length} accounts  ·  ID and name only',
      footerText:
          'Exported ${formatDateTime(DateTime.now())}  ·  ${AppBrand.developer}',
    );
    sheet.table(
      headers: const <String>['Customer ID', 'Customer Name'],
      rows: <List<String>>[
        for (final CustomerProfile row in customers) <String>[row.id, row.name],
      ],
      flex: const <int, double>{0: 1, 1: 3},
      fontSize: 10,
      grid: false,
      headerInk: PdfPalette.ink,
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    );
    await sheet.write(doc);
    return doc.save(enableEventLoopBalancing: true);
  }
}
