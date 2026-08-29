import 'dart:io';

import 'package:path_provider/path_provider.dart';

class AlphaLogStore {
  File? _file;
  String? path;

  Future<void> append(String line) async {
    try {
      final File file = await _ensureFile();
      await file.writeAsString('$line\r\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  Future<File> _ensureFile() async {
    final File? existing = _file;
    if (existing != null) {
      return existing;
    }
    final Directory dir = await getApplicationDocumentsDirectory();
    final File file = File('${dir.path}${Platform.pathSeparator}AlphaLog.txt');
    path = file.path;
    _file = file;
    return file;
  }
}
