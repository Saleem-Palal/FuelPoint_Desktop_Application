import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

/// Bundled Roboto, parsed once and reused. Nastaliq is not loaded here:
/// its tables are large enough to stall PDF startup.
class PdfTypeface {
  const PdfTypeface({required this.regular, required this.bold});

  final pw.Font regular;
  final pw.Font bold;

  pw.ThemeData get theme {
    return pw.ThemeData.withFont(base: regular, bold: bold);
  }

  static Future<PdfTypeface>? _pending;

  static Future<PdfTypeface> load() {
    final Future<PdfTypeface>? pending = _pending;
    if (pending != null) {
      return pending;
    }
    final Future<PdfTypeface> next = _read();
    _pending = next;
    next.then(
      (PdfTypeface _) {},
      onError: (Object _) {
        if (identical(_pending, next)) {
          _pending = null;
        }
      },
    );
    return next;
  }

  static Future<PdfTypeface> _read() async {
    final pw.Font regular = await _ttf('assets/fonts/Roboto-Regular.ttf');
    final pw.Font bold = await _ttf('assets/fonts/Roboto-Bold.ttf');
    return PdfTypeface(regular: regular, bold: bold);
  }

  static Future<pw.Font> _ttf(String asset) async {
    final ByteData data = await rootBundle.load(asset);
    final Uint8List bytes = Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    await Future<void>.delayed(Duration.zero);
    return pw.Font.ttf(ByteData.sublistView(bytes));
  }
}
