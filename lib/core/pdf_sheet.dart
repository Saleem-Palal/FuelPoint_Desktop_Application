import 'dart:math' as math;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_text.dart';

/// Original FuelPoint report colors.
class PdfPalette {
  const PdfPalette._();

  static final PdfColor ink = PdfColor.fromInt(0xFF211C1A);
  static final PdfColor muted = PdfColor.fromInt(0xFF6F6560);
  static final PdfColor coral = PdfColor.fromInt(0xFFF0785C);
  static final PdfColor line = PdfColor.fromInt(0xFFEAD9D0);
  static final PdfColor canvas = PdfColor.fromInt(0xFFFBEDE6);
  static final PdfColor bad = PdfColor.fromInt(0xFFB42318);
}

/// Colored report pages. Each page is a normal [pw.Page], so a long table
/// cannot fall into the pdf package's multi-page loop.
class PdfSheet {
  PdfSheet({
    required this.pageFormat,
    required this.theme,
    required this.regular,
    required this.bold,
    this.margin = const pw.EdgeInsets.all(20),
    this.brand,
    this.title,
    this.subtitle,
    this.footerText,
    this.repeatTitle = true,
  });

  final PdfPageFormat pageFormat;
  final pw.ThemeData theme;
  final pw.Font regular;
  final pw.Font bold;
  final pw.EdgeInsets margin;
  final String? brand;
  final String? title;
  final String? subtitle;
  final String? footerText;

  /// FuelPoint, the report title, and the date line. Later pages stay clear
  /// when this is false, and only the table header repeats.
  final bool repeatTitle;

  static const double _footerReserve = 28;
  static const double _headerReserve = 86;

  final List<_Block> _blocks = <_Block>[];

  bool get _hasHeader => title != null && title!.trim().isNotEmpty;

  double _budgetFor(int pageIndex) {
    final double inner = pageFormat.height - margin.top - margin.bottom;
    final bool titleOnPage = _hasHeader && (repeatTitle || pageIndex == 0);
    final double header = titleOnPage ? _headerReserve : 0;
    return math.max(80, inner - header - _footerReserve - 10);
  }

  void gap(double height) {
    _blocks.add(_Block(pw.SizedBox(height: height), height, gap: true));
  }

  void banner({
    required String kicker,
    required String title,
    required List<List<String>> chips,
  }) {
    _blocks.add(
      _Block(
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: PdfPalette.canvas,
            border: pw.Border.all(color: PdfPalette.line),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Text(
                _safe(kicker).toUpperCase(),
                style: pw.TextStyle(
                  color: PdfPalette.coral,
                  font: bold,
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                _safe(title),
                style: pw.TextStyle(
                  color: PdfPalette.ink,
                  font: bold,
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Wrap(
                spacing: 20,
                runSpacing: 4,
                children: <pw.Widget>[
                  for (final List<String> chip in chips)
                    _chip(chip[0], chip.length > 1 ? chip[1] : ''),
                ],
              ),
            ],
          ),
        ),
        158,
      ),
    );
  }

  void section(String label) {
    gap(12);
    _blocks.add(
      _Block(
        pw.Text(
          _safe(label),
          style: pw.TextStyle(
            color: PdfPalette.muted,
            font: bold,
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 0.7,
          ),
        ),
        12,
      ),
    );
    gap(6);
  }

  void kpis(List<List<String>> items, {bool rounded = true}) {
    if (items.isEmpty) {
      return;
    }
    final bool detailed = items.any(
      (List<String> item) => item.length > 1 && item[1].contains('\n'),
    );
    final double band = detailed ? 72 : 54;
    final List<pw.Widget> rows = <pw.Widget>[];
    int bands = 0;
    for (int i = 0; i < items.length; i += 3) {
      if (bands > 0) {
        rows.add(pw.SizedBox(height: 6));
      }
      final int end = math.min(i + 3, items.length);
      rows.add(_kpiRow(items.sublist(i, end), rounded: rounded));
      bands++;
    }
    _blocks.add(
      _Block(
        pw.Column(children: rows),
        bands * band + math.max(0, bands - 1) * 6,
      ),
    );
  }

  void note(String text, {PdfColor? color, bool boldText = false}) {
    final String safe = _safe(text);
    if (safe.isEmpty) {
      return;
    }
    _blocks.add(
      _Block(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Text(
            safe,
            maxLines: 2,
            style: pw.TextStyle(
              color: color ?? PdfPalette.ink,
              font: boldText ? bold : regular,
              fontSize: 8,
              fontWeight: boldText ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ),
        22,
      ),
    );
  }

  void kv(String label, String value) {
    final String safe = _safe(value);
    final List<String> lines = <String>[];
    for (final String raw in safe.split('\n')) {
      String rest = raw.trim();
      if (rest.isEmpty) {
        continue;
      }
      while (rest.length > 90) {
        lines.add(rest.substring(0, 90));
        rest = rest.substring(90).trimLeft();
      }
      if (rest.isNotEmpty) {
        lines.add(rest);
      }
    }
    if (lines.isEmpty) {
      lines.add('-');
    }
    const int per = 18;
    for (int i = 0; i < lines.length; i += per) {
      final List<String> slice = lines.sublist(
        i,
        math.min(i + per, lines.length),
      );
      _blocks.add(
        _Block(
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.SizedBox(
                  width: 120,
                  child: pw.Text(
                    i == 0 ? _safe(label).toUpperCase() : '',
                    style: pw.TextStyle(
                      color: PdfPalette.muted,
                      font: bold,
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: <pw.Widget>[
                      for (final String line in slice)
                        pw.Text(
                          line,
                          style: pw.TextStyle(
                            color: PdfPalette.ink,
                            font: bold,
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          10 + slice.length * 14,
        ),
      );
    }
  }

  void totals(String left, String right) {
    _blocks.add(
      _Block(
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: <pw.Widget>[
            pw.Text(
              _safe(left),
              style: pw.TextStyle(
                color: PdfPalette.ink,
                font: bold,
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              _safe(right),
              style: pw.TextStyle(
                color: PdfPalette.ink,
                font: bold,
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
        16,
      ),
    );
  }

  void table({
    required List<String> headers,
    required List<List<String>> rows,
    Map<int, double>? flex,
    Set<int>? numeric,
    double fontSize = 7,
    String? caption,
    bool grid = true,
    bool contentDriven = false,
    pw.EdgeInsets padding = const pw.EdgeInsets.symmetric(
      horizontal: 3,
      vertical: 3,
    ),
    PdfColor? headerInk,
  }) {
    if (rows.isEmpty) {
      note('No rows');
      return;
    }
    _blocks.add(
      _Block.table(
        _TableSpec(
          headers: headers,
          rows: rows,
          flex: contentDriven
              ? pdfContentColumnFlex(
                  headers: headers,
                  rows: rows,
                  fontSize: fontSize,
                  horizontalPadding: padding.left + padding.right,
                )
              : flex,
          numeric: numeric ?? const <int>{},
          fontSize: fontSize,
          rowHeight: fontSize * 1.15 + padding.top + padding.bottom + 1,
          caption: caption,
          grid: grid,
          padding: padding,
          headerInk: headerInk ?? PdfPalette.muted,
        ),
      ),
    );
  }

  Future<void> write(pw.Document doc) async {
    final List<List<_Block>> pages = _pack();
    for (int index = 0; index < pages.length; index++) {
      final int pageNumber = index + 1;
      final List<_Block> blocks = pages[index];
      doc.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: margin,
          theme: theme,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: <pw.Widget>[
                if (_hasHeader && (repeatTitle || pageNumber == 1))
                  _pageHeader(pageNumber, pages.length),
                for (final _Block block in blocks)
                  if (block.widget != null) block.widget!,
                pw.Spacer(),
                _pageFooter(pageNumber, pages.length),
              ],
            );
          },
        ),
      );
      if (index % 2 == 1) {
        await Future<void>.delayed(Duration.zero);
      }
    }
  }

  List<List<_Block>> _pack() {
    final List<List<_Block>> pages = <List<_Block>>[];
    final _PageCursor cursor = _PageCursor();

    void push() {
      if (cursor.blocks.isEmpty) {
        return;
      }
      pages.add(cursor.blocks);
      cursor.blocks = <_Block>[];
      cursor.used = 0;
    }

    for (final _Block block in _blocks) {
      final _TableSpec? table = block.table;
      if (table != null) {
        _placeTable(table, pages, cursor, push);
        continue;
      }
      final pw.Widget? widget = block.widget;
      if (widget == null) {
        continue;
      }
      final double budget = _budgetFor(pages.length);
      if (cursor.blocks.isEmpty && block.gap) {
        continue;
      }
      if (cursor.used > 0 && cursor.used + block.height > budget) {
        push();
        if (block.gap) {
          continue;
        }
      }
      cursor.blocks.add(block);
      cursor.used += block.height;
    }
    if (cursor.blocks.isNotEmpty) {
      pages.add(cursor.blocks);
    }
    if (pages.isEmpty) {
      pages.add(<_Block>[_Block(pw.SizedBox(), 1)]);
    }
    return pages;
  }

  void _placeTable(
    _TableSpec spec,
    List<List<_Block>> pages,
    _PageCursor cursor,
    void Function() push,
  ) {
    int index = 0;
    bool captionShown = spec.caption == null || spec.caption!.trim().isEmpty;
    int guard = 0;
    while (index < spec.rows.length && guard < spec.rows.length + 8) {
      guard++;
      final double budget = _budgetFor(pages.length);
      final double space = budget - cursor.used;
      final bool showCaption = !captionShown;
      final double captionHeight = showCaption ? 18 : 0;
      final int fit =
          ((space - captionHeight - spec.rowHeight - 4) / spec.rowHeight)
              .floor();
      if (fit < 1) {
        if (cursor.blocks.isEmpty) {
          final int forced = math.min(1, spec.rows.length - index);
          _appendSlice(
            spec,
            cursor.blocks,
            index,
            forced,
            showCaption: showCaption,
          );
          index += forced;
          captionShown = true;
          push();
          continue;
        }
        push();
        continue;
      }
      final int take = math.min(fit, spec.rows.length - index);
      _appendSlice(spec, cursor.blocks, index, take, showCaption: showCaption);
      cursor.used += _sliceHeight(spec, take, showCaption: showCaption);
      index += take;
      captionShown = true;
    }
  }

  double _sliceHeight(_TableSpec spec, int rows, {required bool showCaption}) {
    return (showCaption ? 18 : 0) + spec.rowHeight * (rows + 1) + 2;
  }

  void _appendSlice(
    _TableSpec spec,
    List<_Block> current,
    int start,
    int count, {
    required bool showCaption,
  }) {
    final List<pw.Widget> children = <pw.Widget>[];
    if (showCaption && spec.caption != null) {
      children.add(
        pw.Text(
          _safe(spec.caption!),
          style: pw.TextStyle(
            color: PdfPalette.ink,
            font: bold,
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      );
      children.add(pw.SizedBox(height: 3));
    }
    children.add(
      _table(
        headers: spec.headers,
        rows: spec.rows.sublist(start, start + count),
        flex: spec.flex,
        numeric: spec.numeric,
        fontSize: spec.fontSize,
        padding: spec.padding,
        grid: spec.grid,
        headerInk: spec.headerInk,
      ),
    );
    current.add(
      _Block(
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: children,
        ),
        _sliceHeight(spec, count, showCaption: showCaption),
      ),
    );
  }

  pw.Widget _pageHeader(int page, int pages) {
    return pw.Container(
      height: _headerReserve - 8,
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfPalette.line)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: <pw.Widget>[
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisSize: pw.MainAxisSize.min,
              children: <pw.Widget>[
                if (brand != null && brand!.trim().isNotEmpty)
                  pw.Text(
                    _safe(brand!).toUpperCase(),
                    style: pw.TextStyle(
                      color: PdfPalette.coral,
                      font: bold,
                      fontSize: 9,
                      letterSpacing: 1.2,
                    ),
                  ),
                pw.Text(
                  _safe(title!),
                  style: pw.TextStyle(
                    color: PdfPalette.ink,
                    font: bold,
                    fontSize: 16,
                  ),
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty)
                  pw.Text(
                    _safe(subtitle!),
                    maxLines: 2,
                    style: pw.TextStyle(
                      color: PdfPalette.muted,
                      font: regular,
                      fontSize: 9,
                    ),
                  ),
              ],
            ),
          ),
          pw.Text(
            'Page $page / $pages',
            style: pw.TextStyle(
              color: PdfPalette.muted,
              font: regular,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pageFooter(int page, int pages) {
    return pw.SizedBox(
      height: 18,
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          pw.Expanded(
            child: pw.Text(
              footerText == null ? '' : _safe(footerText!),
              maxLines: 1,
              style: pw.TextStyle(
                color: PdfPalette.muted,
                font: regular,
                fontSize: 8,
              ),
            ),
          ),
          pw.Text(
            'Page $page of $pages',
            style: pw.TextStyle(
              color: PdfPalette.muted,
              font: regular,
              fontSize: 8,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _chip(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text(
          _safe(label).toUpperCase(),
          style: pw.TextStyle(
            color: PdfPalette.muted,
            font: bold,
            fontSize: 7,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        pw.Text(
          _safe(value).isEmpty ? '-' : _safe(value),
          style: pw.TextStyle(
            color: PdfPalette.ink,
            font: bold,
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }

  pw.Widget _kpiRow(List<List<String>> cells, {required bool rounded}) {
    return pw.Row(
      children: <pw.Widget>[
        for (int i = 0; i < 3; i++) ...<pw.Widget>[
          if (i > 0) pw.SizedBox(width: 6),
          pw.Expanded(
            child: i < cells.length
                ? _kpiPill(
                    cells[i][0],
                    cells[i].length > 1 ? cells[i][1] : '',
                    rounded: rounded,
                  )
                : pw.SizedBox(),
          ),
        ],
      ],
    );
  }

  pw.Widget _kpiPill(String label, String value, {required bool rounded}) {
    final List<String> parts = value.split('\n');
    final String main = parts.first;
    final String? detail = parts.length > 1 ? parts.sublist(1).join(' ') : null;
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: pw.BoxDecoration(
        color: PdfPalette.canvas,
        border: pw.Border.all(color: PdfPalette.line),
        borderRadius: rounded
            ? const pw.BorderRadius.all(pw.Radius.circular(8))
            : null,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisSize: pw.MainAxisSize.min,
        children: <pw.Widget>[
          pw.Text(
            _safe(label).toUpperCase(),
            maxLines: 1,
            style: pw.TextStyle(
              color: PdfPalette.muted,
              font: bold,
              fontSize: 7,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 0.4,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            _safe(main).isEmpty ? '-' : _safe(main),
            maxLines: 2,
            style: pw.TextStyle(
              color: PdfPalette.ink,
              font: bold,
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          if (detail != null && detail.trim().isNotEmpty)
            pw.Text(
              _safe(detail),
              maxLines: 2,
              style: pw.TextStyle(
                color: PdfPalette.muted,
                font: regular,
                fontSize: 7,
              ),
            ),
        ],
      ),
    );
  }

  pw.Widget _table({
    required List<String> headers,
    required List<List<String>> rows,
    required Map<int, double>? flex,
    required Set<int> numeric,
    required double fontSize,
    required pw.EdgeInsets padding,
    required bool grid,
    required PdfColor headerInk,
  }) {
    return pw.Table(
      border: grid
          ? pw.TableBorder.all(color: PdfPalette.line, width: 1.25)
          : pw.TableBorder(
              horizontalInside: pw.BorderSide(
                color: PdfPalette.line,
                width: 1,
              ),
              bottom: pw.BorderSide(color: PdfPalette.line, width: 1.25),
            ),
      columnWidths: <int, pw.TableColumnWidth>{
        for (int i = 0; i < headers.length; i++)
          i: pw.FlexColumnWidth(
            flex != null && flex.containsKey(i) ? flex[i]! : 1,
          ),
      },
      defaultColumnWidth: const pw.FlexColumnWidth(),
      children: <pw.TableRow>[
        pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfPalette.canvas),
          children: <pw.Widget>[
            for (final String header in headers)
              pw.Padding(
                padding: padding,
                child: pw.Text(
                  _safe(header),
                  maxLines: 1,
                  softWrap: false,
                  overflow: pw.TextOverflow.clip,
                  style: pw.TextStyle(
                    color: headerInk,
                    font: bold,
                    fontSize: fontSize,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        for (final List<String> row in rows)
          pw.TableRow(
            children: <pw.Widget>[
              for (int i = 0; i < headers.length; i++)
                pw.Padding(
                  padding: padding,
                  child: pw.Text(
                    _cell(i < row.length ? row[i] : ''),
                    maxLines: 1,
                    softWrap: false,
                    overflow: pw.TextOverflow.clip,
                    textAlign: numeric.contains(i)
                        ? pw.TextAlign.right
                        : pw.TextAlign.left,
                    style: pw.TextStyle(
                      color: PdfPalette.ink,
                      font: regular,
                      fontSize: fontSize,
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  String _cell(String value) {
    final String safe = _safe(value);
    return safe.isEmpty ? '-' : safe;
  }

  String _safe(String value) => pdfSafeText(value);
}

/// Flex weights from the longest cell in each column. [pw.FlexColumnWidth]
/// then stretches the table to the printable width and shares leftover
/// space in the same proportions, so wide names keep room and short
/// columns do not sit idle.
Map<int, double> pdfContentColumnFlex({
  required List<String> headers,
  required List<List<String>> rows,
  double fontSize = 8,
  double horizontalPadding = 4,
}) {
  final int cols = headers.length;
  if (cols == 0) {
    return const <int, double>{};
  }
  final List<double> widths = List<double>.filled(cols, 0);
  for (int i = 0; i < cols; i++) {
    widths[i] = _pdfCellEmWidth(headers[i], bold: true);
  }
  for (final List<String> row in rows) {
    for (int i = 0; i < cols; i++) {
      final String text = i < row.length ? row[i] : '';
      final double width = _pdfCellEmWidth(text, bold: false);
      if (width > widths[i]) {
        widths[i] = width;
      }
    }
  }
  return <int, double>{
    for (int i = 0; i < cols; i++)
      i: math.max(1, widths[i] * fontSize + horizontalPadding),
  };
}

double _pdfCellEmWidth(String text, {required bool bold}) {
  final String safe = pdfSafeText(text);
  if (safe.isEmpty) {
    return bold ? 0.7 : 0.55;
  }
  double em = 0;
  for (final int rune in safe.runes) {
    em += _pdfGlyphEm(rune);
  }
  return em * (bold ? 1.08 : 1);
}

double _pdfGlyphEm(int rune) {
  if (rune == 0x20) {
    return 0.25;
  }
  if (rune >= 0x30 && rune <= 0x39) {
    return 0.56;
  }
  if (rune >= 0x41 && rune <= 0x5A) {
    return 0.66;
  }
  if (rune >= 0x61 && rune <= 0x7A) {
    return 0.52;
  }
  if (rune == 0x2C || rune == 0x2E || rune == 0x3A) {
    return 0.28;
  }
  if (rune == 0x2D || rune == 0x2F) {
    return 0.32;
  }
  return 0.55;
}

class _PageCursor {
  List<_Block> blocks = <_Block>[];
  double used = 0;
}

class _Block {
  const _Block(this.widget, this.height, {this.gap = false}) : table = null;

  const _Block.table(this.table) : widget = null, height = 0, gap = false;

  final pw.Widget? widget;
  final double height;
  final bool gap;
  final _TableSpec? table;
}

class _TableSpec {
  const _TableSpec({
    required this.headers,
    required this.rows,
    required this.flex,
    required this.numeric,
    required this.fontSize,
    required this.rowHeight,
    required this.caption,
    required this.grid,
    required this.padding,
    required this.headerInk,
  });

  final List<String> headers;
  final List<List<String>> rows;
  final Map<int, double>? flex;
  final Set<int> numeric;
  final double fontSize;
  final double rowHeight;
  final String? caption;
  final bool grid;
  final pw.EdgeInsets padding;
  final PdfColor headerInk;
}
