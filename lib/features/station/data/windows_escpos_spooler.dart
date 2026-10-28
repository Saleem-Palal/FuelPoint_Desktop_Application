import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';

import 'receipt_proof_raster.dart';

/// Sends a receipt bitmap to a Windows thermal printer as RAW ESC/POS.
///
/// GDI/PDF jobs are clipped to the driver's ~80mm page. RAW raster prints
/// the full slip height and cuts once at the end.
class WindowsEscPosSpooler {
  WindowsEscPosSpooler._();

  static final WindowsEscPosSpooler instance = WindowsEscPosSpooler._();

  static const int _dots80mm = 576;
  static const int _dots58mm = 384;
  static const int _maxRasterRows = 1200;

  /// 80mm until a paper-width setting exists.
  static int paperWidthDots({bool mm58 = false}) {
    return mm58 ? _dots58mm : _dots80mm;
  }

  static int get thermalWidthDots => paperWidthDots();

  _Winspool? _api;

  /// Each PNG is its own cut job. [proofImagePath] prints as a separate screenshot slip.
  Future<void> printPngs(
    List<Uint8List> pngs, {
    String? proofImagePath,
    Uint8List? screenshotPng,
  }) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('ESC/POS spooler is Windows-only');
    }
    if (pngs.isEmpty) {
      throw StateError('Receipt snapshot is empty');
    }
    final String printer = await _resolvePrinterName();
    final _Winspool api = _api ??= _Winspool.open();
    for (int i = 0; i < pngs.length; i++) {
      final Uint8List payload = await _escPosFromPng(pngs[i]);
      api.writeRaw(printer, payload, jobName: 'FuelPoint receipt');
      if (i < pngs.length - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
    try {
      final Uint8List? composed = screenshotPng;
      if (composed != null && composed.isNotEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        api.writeRaw(
          printer,
          await _escPosFromPng(composed, mode: ThermalBitMode.photo),
          jobName: 'FuelPoint screenshot',
        );
        return;
      }
      final String proof = proofImagePath?.trim() ?? '';
      if (proof.isEmpty) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
      api.writeRaw(
        printer,
        await _escPosFromProofJpeg(proof),
        jobName: 'FuelPoint screenshot',
      );
    } catch (error, stack) {
      debugPrint('Screenshot copy skipped: $error\n$stack');
    }
  }

  Future<String> _resolvePrinterName() async {
    try {
      final List<Printer> printers = await Printing.listPrinters();
      final List<Printer> ready = printers
          .where((Printer p) => p.isAvailable)
          .toList();
      for (final Printer p in ready) {
        final String n = p.name.toLowerCase();
        if (n.contains('pos') ||
            n.contains('thermal') ||
            n.contains('receipt') ||
            n.contains('80c')) {
          return p.name;
        }
      }
      for (final Printer p in ready) {
        if (p.isDefault) {
          return p.name;
        }
      }
      if (ready.isNotEmpty) {
        return ready.first.name;
      }
    } catch (error, stack) {
      debugPrint('listPrinters failed: $error\n$stack');
    }
    return _Winspool.defaultPrinterName();
  }

  Future<Uint8List> _escPosFromPng(
    Uint8List png, {
    ThermalBitMode mode = ThermalBitMode.text,
  }) async {
    return mergeEscPosSlip(
      receiptBody: await _rasterFromPng(png, mode: mode),
    );
  }

  Future<Uint8List> _escPosFromProofJpeg(String path) async {
    final File file = File(path);
    if (!await file.exists()) {
      throw StateError('Transfer screenshot missing on disk: $path');
    }
    final Uint8List jpeg = await file.readAsBytes();
    final int maxWidth = thermalWidthDots;
    final Uint8List body = await Isolate.run(() {
      return packProofJpegRaster(jpeg, maxWidth: maxWidth);
    });
    return mergeEscPosSlip(receiptBody: body);
  }

  Future<Uint8List> _rasterFromPng(
    Uint8List png, {
    ThermalBitMode mode = ThermalBitMode.text,
  }) async {
    final ui.Codec codec = await ui.instantiateImageCodec(png);
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image src = frame.image;
    try {
      if (src.width <= 0 || src.height <= 0) {
        throw StateError('Receipt snapshot is empty');
      }
      final int destW = thermalWidthDots;
      final int destH = (src.height * destW / src.width).round().clamp(1, 8000);
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final ui.Canvas canvas = ui.Canvas(recorder);
      canvas.drawImageRect(
        src,
        ui.Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
        ui.Rect.fromLTWH(0, 0, destW.toDouble(), destH.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      final ui.Picture picture = recorder.endRecording();
      final ui.Image scaled = await picture.toImage(destW, destH);
      picture.dispose();
      try {
        final ByteData? rgba = await scaled.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        if (rgba == null) {
          throw StateError('Receipt raster failed');
        }
        return packEscPosRaster(
          rgba.buffer.asUint8List(),
          destW,
          destH,
          mode: mode,
        );
      } finally {
        scaled.dispose();
      }
    } finally {
      src.dispose();
    }
  }
}

Uint8List mergeEscPosSlip({
  required Uint8List receiptBody,
  Uint8List? proofBody,
  int feedLines = 3,
}) {
  final BytesBuilder out = BytesBuilder(copy: false);
  out.add(const <int>[0x1B, 0x40]);
  out.add(const <int>[0x1B, 0x61, 0x01]);
  out.add(receiptBody);
  if (proofBody != null && proofBody.isNotEmpty) {
    out.add(const <int>[0x1B, 0x64, 0x01]);
    out.add(proofBody);
  }
  out.add(<int>[0x1B, 0x64, feedLines.clamp(0, 255)]);
  out.add(const <int>[0x1D, 0x56, 0x41, 0x10]);
  return out.toBytes();
}

/// Proof photo already rastered at save time — resize and pack, no second dither.
Uint8List packProofJpegRaster(Uint8List jpeg, {int maxWidth = 576}) {
  final ({int width, int height, Uint8List rgba}) prepared =
      ReceiptProofRaster.preparePhotoThermal(jpeg, maxWidth: maxWidth);
  return packEscPosRaster(
    prepared.rgba,
    prepared.width,
    prepared.height,
    mode: ThermalBitMode.photo,
  );
}

Uint8List packEscPosRaster(
  Uint8List rgba,
  int width,
  int height, {
  ThermalBitMode mode = ThermalBitMode.text,
}) {
  final List<int> bits = rgbaToThermalBits(rgba, width, height, mode: mode);
  final int widthBytes = (width + 7) ~/ 8;
  final BytesBuilder out = BytesBuilder(copy: false);
  int row = 0;
  while (row < height) {
    final int chunk = math.min(
      WindowsEscPosSpooler._maxRasterRows,
      height - row,
    );
    out.add(const <int>[0x1D, 0x76, 0x30, 0x00]);
    out.addByte(widthBytes & 0xFF);
    out.addByte((widthBytes >> 8) & 0xFF);
    out.addByte(chunk & 0xFF);
    out.addByte((chunk >> 8) & 0xFF);
    final Uint8List band = Uint8List(widthBytes * chunk);
    for (int y = 0; y < chunk; y++) {
      for (int x = 0; x < width; x++) {
        if (bits[(row + y) * width + x] == 0) {
          continue;
        }
        band[y * widthBytes + (x >> 3)] |= 0x80 >> (x & 7);
      }
    }
    out.add(band);
    row += chunk;
  }
  return out.toBytes();
}

final class _DocInfo1 extends Struct {
  external Pointer<Utf16> pDocName;
  external Pointer<Utf16> pOutputFile;
  external Pointer<Utf16> pDatatype;
}

class _Winspool {
  _Winspool({
    required this.openPrinter,
    required this.closePrinter,
    required this.startDocPrinter,
    required this.endDocPrinter,
    required this.startPagePrinter,
    required this.endPagePrinter,
    required this.writePrinter,
    required this.getLastError,
  });

  final int Function(Pointer<Utf16>, Pointer<IntPtr>, Pointer<Void>)
  openPrinter;
  final int Function(int) closePrinter;
  final int Function(int, int, Pointer<Uint8>) startDocPrinter;
  final int Function(int) endDocPrinter;
  final int Function(int) startPagePrinter;
  final int Function(int) endPagePrinter;
  final int Function(int, Pointer<Void>, int, Pointer<Uint32>) writePrinter;
  final int Function() getLastError;

  static _Winspool open() {
    final DynamicLibrary spool = DynamicLibrary.open('winspool.drv');
    final DynamicLibrary kernel = DynamicLibrary.open('kernel32.dll');
    return _Winspool(
      openPrinter: spool
          .lookupFunction<
            Int32 Function(Pointer<Utf16>, Pointer<IntPtr>, Pointer<Void>),
            int Function(Pointer<Utf16>, Pointer<IntPtr>, Pointer<Void>)
          >('OpenPrinterW'),
      closePrinter: spool
          .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
            'ClosePrinter',
          ),
      startDocPrinter: spool
          .lookupFunction<
            Uint32 Function(IntPtr, Uint32, Pointer<Uint8>),
            int Function(int, int, Pointer<Uint8>)
          >('StartDocPrinterW'),
      endDocPrinter: spool
          .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
            'EndDocPrinter',
          ),
      startPagePrinter: spool
          .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
            'StartPagePrinter',
          ),
      endPagePrinter: spool
          .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
            'EndPagePrinter',
          ),
      writePrinter: spool
          .lookupFunction<
            Int32 Function(IntPtr, Pointer<Void>, Uint32, Pointer<Uint32>),
            int Function(int, Pointer<Void>, int, Pointer<Uint32>)
          >('WritePrinter'),
      getLastError: kernel.lookupFunction<Uint32 Function(), int Function()>(
        'GetLastError',
      ),
    );
  }

  static String defaultPrinterName() {
    final DynamicLibrary spool = DynamicLibrary.open('winspool.drv');
    final int Function(Pointer<Utf16>, Pointer<Uint32>) getDefault = spool
        .lookupFunction<
          Int32 Function(Pointer<Utf16>, Pointer<Uint32>),
          int Function(Pointer<Utf16>, Pointer<Uint32>)
        >('GetDefaultPrinterW');
    final Pointer<Uint32> size = calloc<Uint32>();
    try {
      size.value = 0;
      getDefault(nullptr, size);
      if (size.value == 0) {
        throw Exception('No default printer is set in Windows');
      }
      final Pointer<Utf16> name = calloc<Uint16>(size.value).cast<Utf16>();
      try {
        if (getDefault(name, size) == 0) {
          throw Exception('Could not read the Windows default printer');
        }
        return name.toDartString();
      } finally {
        calloc.free(name);
      }
    } finally {
      calloc.free(size);
    }
  }

  void writeRaw(String printerName, Uint8List data, {required String jobName}) {
    final Pointer<Utf16> namePtr = printerName.toNativeUtf16();
    final Pointer<IntPtr> handle = calloc<IntPtr>();
    final Pointer<Utf16> docName = jobName.toNativeUtf16();
    final Pointer<Utf16> datatype = 'RAW'.toNativeUtf16();
    final Pointer<_DocInfo1> doc = calloc<_DocInfo1>();
    final Pointer<Uint8> buf = calloc<Uint8>(data.length);
    final Pointer<Uint32> written = calloc<Uint32>();
    int printer = 0;
    bool started = false;
    try {
      buf.asTypedList(data.length).setAll(0, data);
      doc.ref.pDocName = docName;
      doc.ref.pOutputFile = nullptr;
      doc.ref.pDatatype = datatype;
      if (openPrinter(namePtr, handle, nullptr) == 0) {
        throw Exception(
          'Could not open printer "$printerName" (Win32 ${getLastError()})',
        );
      }
      printer = handle.value;
      if (startDocPrinter(printer, 1, doc.cast<Uint8>()) == 0) {
        throw Exception(
          'Could not start print job on "$printerName" (Win32 ${getLastError()})',
        );
      }
      started = true;
      if (startPagePrinter(printer) == 0) {
        throw Exception(
          'Could not start the print page (Win32 ${getLastError()})',
        );
      }
      if (writePrinter(printer, buf.cast(), data.length, written) == 0) {
        throw Exception(
          'Could not send data to "$printerName" (Win32 ${getLastError()})',
        );
      }
      endPagePrinter(printer);
    } finally {
      if (started) {
        endDocPrinter(printer);
      }
      if (printer != 0) {
        closePrinter(printer);
      }
      calloc.free(written);
      calloc.free(buf);
      calloc.free(doc);
      calloc.free(datatype);
      calloc.free(docName);
      calloc.free(handle);
      calloc.free(namePtr);
    }
  }
}
