import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme/dispensr_theme.dart';

/// Writes a PDF under Documents/Exported_Reports and opens it.
class PdfFileExport {
  PdfFileExport._();

  static Future<File> saveAndOpen({
    required Uint8List bytes,
    required String folder,
    required String fileName,
  }) async {
    final File file = await save(
      bytes: bytes,
      folder: folder,
      fileName: fileName,
    );
    await open(file);
    return file;
  }

  static Future<File> save({
    required Uint8List bytes,
    required String folder,
    required String fileName,
  }) async {
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory dir = Directory(
      p.join(docs.path, 'Exported_Reports', folder),
    );
    await dir.create(recursive: true);
    final File file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static Future<void> open(File file) async {
    if (Platform.isWindows) {
      try {
        // `start` treats the first quoted argument as a window title.
        // The title has to be an empty string. A word here is launched as
        // the program, which is the "Windows cannot find 'FuelPoint'" dialog.
        await Process.start(
          'cmd.exe',
          <String>['/c', 'start', '', file.path],
          mode: ProcessStartMode.detached,
        );
        return;
      } catch (error) {
        debugPrint('PdfFileExport.open failed: $error');
      }
    }
    final Uri uri = Uri.file(file.path);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      debugPrint('PdfFileExport.open launchUrl failed: $error');
    }
  }
}

/// Above this many rows, building the PDF on the desktop can stall or close.
const int kLargePdfTransactionCount = 800;

/// Asks before a very large export. Returns true when generation should start.
Future<bool> confirmLargePdfExport(
  BuildContext context, {
  required int transactionCount,
}) async {
  if (transactionCount < kLargePdfTransactionCount) {
    return true;
  }
  if (!context.mounted) {
    return false;
  }
  final DispensrTokens tokens = DispensrTokens.of(context);
  final bool? proceed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        backgroundColor: tokens.card,
        surfaceTintColor: tokens.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radius20),
          side: BorderSide(color: tokens.line),
        ),
        title: Text(
          'This export is very large',
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: tokens.ink,
          ),
        ),
        content: Text(
          'This PDF includes ${_groupedCount(transactionCount)} transactions. '
          'Building it can take a long time, and FuelPoint may freeze or close. '
          'A shorter date range is safer.',
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w500,
            fontSize: 14,
            height: 1.4,
            color: tokens.ink,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Narrow the dates',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w600,
                color: tokens.ink,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Generate anyway',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w700,
                color: tokens.coral,
              ),
            ),
          ),
        ],
      );
    },
  );
  return proceed ?? false;
}

String _groupedCount(int value) {
  final String raw = value.abs().toString();
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < raw.length; i++) {
    if (i > 0 && (raw.length - i) % 3 == 0) {
      out.write(',');
    }
    out.write(raw[i]);
  }
  return out.toString();
}

/// Paints a busy dialog, then builds the PDF so the window stays responsive.
Future<void> runPdfExport(
  BuildContext context, {
  required Future<File> Function() export,
  String Function(File file)? success,
  int transactionCount = 0,
}) async {
  final bool allowed = await confirmLargePdfExport(
    context,
    transactionCount: transactionCount,
  );
  if (!allowed || !context.mounted) {
    return;
  }
  final DispensrTokens tokens = DispensrTokens.of(context);
  final Completer<void> shown = Completer<void>();
  BuildContext? dialogContext;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      dialogContext = context;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!shown.isCompleted) {
          shown.complete();
        }
      });
      return AlertDialog(
        backgroundColor: tokens.card,
        surfaceTintColor: tokens.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radius20),
          side: BorderSide(color: tokens.line),
        ),
        content: Row(
          children: <Widget>[
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: tokens.coral,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Generating PDF…',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: tokens.ink,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
  await shown.future;
  try {
    final File file = await export();
    _closePdfDialog(dialogContext);
    if (!context.mounted) {
      return;
    }
    final String message = success == null
        ? 'PDF saved: ${file.path}'
        : success(file);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  } catch (error) {
    _closePdfDialog(dialogContext);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Could not generate PDF: $error')));
  }
}

void _closePdfDialog(BuildContext? dialogContext) {
  if (dialogContext != null && dialogContext.mounted) {
    Navigator.of(dialogContext).pop();
  }
}
