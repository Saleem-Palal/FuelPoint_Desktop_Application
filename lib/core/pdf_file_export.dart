import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

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
    final Uri uri = Uri.file(file.path);
    try {
      final bool launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (launched) {
        return;
      }
    } catch (error) {
      debugPrint('PdfFileExport.open launchUrl failed: $error');
    }
    if (Platform.isWindows) {
      await Process.start('cmd', <String>[
        '/c',
        'start',
        '',
        file.path,
      ], runInShell: true);
    }
  }
}
