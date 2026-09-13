// import 'dart:typed_data';
// import 'dart:ui' as ui;

// import 'package:flutter/painting.dart';

// import '../../../Screens/Sale Screen/Widgets/Services/generate_receipt.dart';
// import '../../../Screens/Sale Screen/Widgets/Services/receipt_preview_widget.dart';

// /// Structured slip for the 3-layer ESC/POS engine.
// class EscPosSlip {
//   const EscPosSlip({
//     required this.dateLabel,
//     required this.timeLabel,
//     required this.badge,
//     required this.referenceLabel,
//     required this.referenceValue,
//     required this.details,
//     this.copyBanner,
//     this.showLcd = false,
//     this.amount = '',
//     this.liters = '',
//     this.rate = '',
//   });

//   factory EscPosSlip.fromTicket(ReceiptTicket ticket, {String? copyBanner}) {
//     return EscPosSlip(
//       dateLabel: ticket.dateLabel,
//       timeLabel: ticket.timeLabel,
//       badge: ticket.unitBadge,
//       referenceLabel: 'Token',
//       referenceValue: ticket.tokenLabel,
//       copyBanner: copyBanner,
//       showLcd: true,
//       amount: ticket.amount,
//       liters: ticket.liters,
//       rate: ticket.rate,
//       details: <ThermalReceiptDetail>[
//         ThermalReceiptDetail(label: 'Customer', value: ticket.customerName),
//         ThermalReceiptDetail(
//           label: 'Vehicle No.',
//           value: ticket.vehicleDisplay,
//         ),
//         ThermalReceiptDetail(label: 'Payment', value: ticket.paymentLabel),
//         ThermalReceiptDetail(label: 'Manager', value: ticket.cashierName),
//         ThermalReceiptDetail(label: 'Helper', value: ticket.helperDisplay),
//       ],
//     );
//   }

//   final String dateLabel;
//   final String timeLabel;
//   final String badge;
//   final String referenceLabel;
//   final String referenceValue;
//   final String? copyBanner;
//   final bool showLcd;
//   final String amount;
//   final String liters;
//   final String rate;
//   final List<ThermalReceiptDetail> details;
// }

// /// Builds a hybrid ESC/POS byte stream: hardware QR, native ASCII, rasters.
// class EscPosReceiptEngine {
//   EscPosReceiptEngine._();

//   static const int dots80mm = 576;
//   static const int cols = 48;
//   static const int _threshold = 128;
//   static const int _maxRasterRows = 1200;

//   /// WhatsApp contact encoded in [ReceiptCopy.developerContactQrAsset].
//   static const String developerWhatsAppUrl = 'https://wa.me/qr/VNZ6VGRUHJ6DJ1';

//   /// Module size 3 ≈ 40×40px on an 80mm slip (29–33 modules × 3 dots).
//   static const int qrModuleDots = 3;

//   static Future<Uint8List> build(EscPosSlip slip) async {
//     final BytesBuilder out = BytesBuilder(copy: false);
//     out.add(const <int>[0x1B, 0x40]);
//     out.add(const <int>[0x1B, 0x74, 0x00]);
//     out.add(const <int>[0x1B, 0x32]);

//     out.add(
//       await _urduRaster(
//         <_UrduLine>[
//           _UrduLine(ReceiptCopy.stationNameUrdu, size: 34, bold: true),
//         ],
//         padTop: 8,
//         padBottom: 10,
//       ),
//     );

//     _align(out, 0);
//     _fontA(out);
//     _line(out, _pair('Date  ${slip.dateLabel}', _ascii(slip.badge)));
//     _line(
//       out,
//       _pair(
//         'Time  ${slip.timeLabel}',
//         '${slip.referenceLabel}  ${slip.referenceValue}',
//       ),
//     );
//     final String? banner = slip.copyBanner?.trim();
//     if (banner != null && banner.isNotEmpty) {
//       _align(out, 1);
//       _bold(out, true);
//       _line(out, _ascii(banner));
//       _bold(out, false);
//       _align(out, 0);
//     }

//     if (slip.showLcd) {
//       out.add(await _lcdRaster(slip));
//     }

//     out.addByte(0x0A);
//     for (final ThermalReceiptDetail row in slip.details) {
//       if (_isAscii(row.label) && _isAscii(row.value)) {
//         _line(out, _pair(row.label, _ascii(row.value)));
//       } else {
//         out.add(
//           await _urduRaster(
//             <_UrduLine>[_UrduLine('${row.label}  ${row.value}', size: 20)],
//             padTop: 2,
//             padBottom: 2,
//           ),
//         );
//       }
//     }
//     _line(out, '-' * cols);

//     out.add(
//       await _urduRaster(
//         <_UrduLine>[
//           _UrduLine(ReceiptCopy.addressUrdu, size: 20),
//           _UrduLine(ReceiptCopy.staffLineUrdu, size: 18),
//         ],
//         padTop: 8,
//         padBottom: 4,
//       ),
//     );

//     _align(out, 1);
//     _bold(out, true);
//     _line(out, ReceiptCopy.stationPhone);
//     _bold(out, false);

//     out.add(
//       await _urduRaster(
//         <_UrduLine>[_UrduLine(ReceiptCopy.thankYouUrdu, size: 22, bold: true)],
//         padTop: 4,
//         padBottom: 6,
//       ),
//     );

//     _align(out, 1);
//     _hardwareQr(out, developerWhatsAppUrl);

//     out.add(
//       await _urduRaster(
//         <_UrduLine>[_UrduLine(ReceiptCopy.developerPitchUrdu, size: 16)],
//         padTop: 4,
//         padBottom: 8,
//       ),
//     );

//     out.add(const <int>[0x1B, 0x64, 0x04]);
//     out.add(const <int>[0x1D, 0x56, 0x41, 0x10]);
//     return out.toBytes();
//   }

//   static void _align(BytesBuilder out, int n) {
//     out.add(<int>[0x1B, 0x61, n]);
//   }

//   static void _fontA(BytesBuilder out) {
//     out.add(const <int>[0x1B, 0x21, 0x00]);
//   }

//   static void _bold(BytesBuilder out, bool on) {
//     out.add(<int>[0x1B, 0x45, on ? 0x01 : 0x00]);
//   }

//   static void _line(BytesBuilder out, String text) {
//     out.add(_latin(text));
//     out.addByte(0x0A);
//   }

//   static Uint8List _latin(String text) {
//     return Uint8List.fromList(
//       text.codeUnits.map((int c) {
//         if (c < 32 || c > 126) {
//           return 0x20;
//         }
//         return c;
//       }).toList(),
//     );
//   }

//   static bool _isAscii(String text) {
//     for (final int c in text.codeUnits) {
//       if (c > 127) {
//         return false;
//       }
//     }
//     return true;
//   }

//   static String _ascii(String text) {
//     return text
//         .replaceAll('—', '-')
//         .replaceAll('–', '-')
//         .replaceAll('·', '-')
//         .replaceAll('•', '*');
//   }

//   static String _pair(String left, String right) {
//     final String l = _ascii(left);
//     final String r = _ascii(right);
//     final int gap = cols - l.length - r.length;
//     if (gap < 1) {
//       final String joined = '$l $r';
//       if (joined.length <= cols) {
//         return joined;
//       }
//       return joined.substring(0, cols);
//     }
//     return l + (' ' * gap) + r;
//   }

//   static void _hardwareQr(BytesBuilder out, String data) {
//     final List<int> payload = data.codeUnits;
//     out.add(const <int>[0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00]);
//     out.add(const <int>[
//       0x1D,
//       0x28,
//       0x6B,
//       0x03,
//       0x00,
//       0x31,
//       0x43,
//       qrModuleDots,
//     ]);
//     out.add(const <int>[0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x31]);
//     final int store = payload.length + 3;
//     out.add(<int>[
//       0x1D,
//       0x28,
//       0x6B,
//       store & 0xFF,
//       (store >> 8) & 0xFF,
//       0x31,
//       0x50,
//       0x30,
//     ]);
//     out.add(payload);
//     out.add(const <int>[0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30]);
//     out.addByte(0x0A);
//   }

//   static Future<Uint8List> _urduRaster(
//     List<_UrduLine> lines, {
//     required int padTop,
//     required int padBottom,
//   }) async {
//     final List<TextPainter> painters = <TextPainter>[];
//     double height = padTop + padBottom;
//     for (final _UrduLine line in lines) {
//       final Paint ink = Paint()
//         ..color = const Color(0xFF000000)
//         ..isAntiAlias = false;
//       final TextPainter tp = TextPainter(
//         text: TextSpan(
//           text: line.text,
//           style: TextStyle(
//             fontFamily: ReceiptCopy.urduFontFamily,
//             fontFamilyFallback: const <String>[ReceiptCopy.latinFontFamily],
//             fontSize: line.size,
//             fontWeight: line.bold ? FontWeight.w700 : FontWeight.w400,
//             height: 1.55,
//             foreground: ink,
//           ),
//         ),
//         textAlign: TextAlign.center,
//         textDirection: TextDirection.rtl,
//       )..layout(maxWidth: dots80mm.toDouble());
//       painters.add(tp);
//       height += tp.height;
//     }
//     return _pictureToGsRaster(
//       width: dots80mm,
//       height: height.ceil().clamp(8, 2000),
//       paint: (Canvas canvas) {
//         double y = padTop.toDouble();
//         for (final TextPainter tp in painters) {
//           tp.paint(canvas, Offset((dots80mm - tp.width) / 2, y));
//           y += tp.height;
//         }
//       },
//     );
//   }

//   static Future<Uint8List> _lcdRaster(EscPosSlip slip) async {
//     const double boxH = 132;
//     const double inset = 8;
//     return _pictureToGsRaster(
//       width: dots80mm,
//       height: boxH.ceil() + 16,
//       paint: (Canvas canvas) {
//         final Paint stroke = Paint()
//           ..color = const Color(0xFF000000)
//           ..style = PaintingStyle.stroke
//           ..strokeWidth = 5
//           ..isAntiAlias = false;
//         final Paint fill = Paint()
//           ..color = const Color(0xFFFFFFFF)
//           ..style = PaintingStyle.fill
//           ..isAntiAlias = false;
//         final Paint rule = Paint()
//           ..color = const Color(0xFF000000)
//           ..strokeWidth = 1
//           ..isAntiAlias = false;
//         const Rect box = Rect.fromLTWH(24, 8, dots80mm - 48, boxH);
//         canvas.drawRRect(RRect.fromRectXY(box, 4, 4), fill);
//         canvas.drawRRect(RRect.fromRectXY(box, 4, 4), stroke);
//         final List<({String label, String value, double size})> rows =
//             <({String label, String value, double size})>[
//               (label: 'AMOUNT', value: slip.amount, size: 34),
//               (label: 'LITERS', value: slip.liters, size: 30),
//               (label: 'RATE', value: slip.rate, size: 30),
//             ];
//         final double rowH = (boxH - inset * 2) / 3;
//         for (int i = 0; i < rows.length; i++) {
//           final double y = box.top + inset + i * rowH;
//           if (i == 1) {
//             canvas.drawLine(
//               Offset(box.left + 10, y),
//               Offset(box.right - 10, y),
//               rule,
//             );
//           }
//           _paintLcdRow(
//             canvas,
//             label: rows[i].label,
//             value: rows[i].value,
//             valueSize: rows[i].size,
//             origin: Offset(box.left + 12, y + 6),
//             width: box.width - 24,
//           );
//         }
//       },
//     );
//   }

//   static void _paintLcdRow(
//     Canvas canvas, {
//     required String label,
//     required String value,
//     required double valueSize,
//     required Offset origin,
//     required double width,
//   }) {
//     final Paint ink = Paint()
//       ..color = const Color(0xFF000000)
//       ..isAntiAlias = false;
//     final TextPainter left = TextPainter(
//       text: TextSpan(
//         text: label,
//         style: TextStyle(
//           fontFamily: ReceiptCopy.lcdLabelFontFamily,
//           fontSize: 16,
//           height: 1.0,
//           foreground: ink,
//         ),
//       ),
//       textDirection: TextDirection.ltr,
//     )..layout();
//     final TextPainter right = TextPainter(
//       text: TextSpan(
//         text: value,
//         style: TextStyle(
//           fontFamily: ReceiptCopy.lcdFontFamily,
//           fontSize: valueSize,
//           height: 1.0,
//           foreground: ink,
//         ),
//       ),
//       textAlign: TextAlign.right,
//       textDirection: TextDirection.ltr,
//     )..layout(maxWidth: width - left.width - 12);
//     left.paint(canvas, origin);
//     right.paint(canvas, Offset(origin.dx + width - right.width, origin.dy));
//   }

//   static Future<Uint8List> _pictureToGsRaster({
//     required int width,
//     required int height,
//     required void Function(Canvas canvas) paint,
//   }) async {
//     final int w = (width ~/ 8) * 8;
//     final int h = height.clamp(8, 4000);
//     final ui.PictureRecorder recorder = ui.PictureRecorder();
//     final Canvas canvas = Canvas(recorder);
//     canvas.drawRect(
//       Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
//       Paint()
//         ..color = const Color(0xFFFFFFFF)
//         ..isAntiAlias = false,
//     );
//     paint(canvas);
//     final ui.Picture picture = recorder.endRecording();
//     final ui.Image image = await picture.toImage(w, h);
//     picture.dispose();
//     try {
//       final ByteData? rgba = await image.toByteData(
//         format: ui.ImageByteFormat.rawRgba,
//       );
//       if (rgba == null) {
//         throw StateError('Receipt raster failed');
//       }
//       return _packGsRaster(rgba.buffer.asUint8List(), w, h);
//     } finally {
//       image.dispose();
//     }
//   }

//   static Uint8List _packGsRaster(Uint8List rgba, int width, int height) {
//     final int widthBytes = width ~/ 8;
//     final BytesBuilder out = BytesBuilder(copy: false);
//     int row = 0;
//     while (row < height) {
//       final int chunk = height - row < _maxRasterRows
//           ? height - row
//           : _maxRasterRows;
//       out.add(const <int>[0x1D, 0x76, 0x30, 0x00]);
//       out.addByte(widthBytes & 0xFF);
//       out.addByte((widthBytes >> 8) & 0xFF);
//       out.addByte(chunk & 0xFF);
//       out.addByte((chunk >> 8) & 0xFF);
//       final Uint8List band = Uint8List(widthBytes * chunk);
//       for (int y = 0; y < chunk; y++) {
//         for (int x = 0; x < width; x++) {
//           final int p = ((row + y) * width + x) * 4;
//           if (rgba[p + 3] < 32) {
//             continue;
//           }
//           final double luma =
//               rgba[p] * 0.299 + rgba[p + 1] * 0.587 + rgba[p + 2] * 0.114;
//           if (luma > _threshold) {
//             continue;
//           }
//           band[y * widthBytes + (x >> 3)] |= 0x80 >> (x & 7);
//         }
//       }
//       out.add(band);
//       row += chunk;
//     }
//     return out.toBytes();
//   }
// }

// class _UrduLine {
//   const _UrduLine(this.text, {required this.size, this.bold = false});

//   final String text;
//   final double size;
//   final bool bold;
// }
