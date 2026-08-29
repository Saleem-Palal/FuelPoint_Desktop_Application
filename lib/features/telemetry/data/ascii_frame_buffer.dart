import 'dart:convert';
import 'dart:typed_data';

/// Persistent TCP ASCII buffer. Frames are taken from `<` to `>`, then
/// `<`, `>`, spaces, CR, and LF are stripped to get a clean payload.
class AsciiFrameBuffer {
  static const String startMark = '<';
  static const String endMark = '>';
  static const int maxChars = 8192;

  final StringBuffer _rx = StringBuffer();

  void reset() {
    _rx.clear();
  }

  List<String> push(Uint8List data) {
    _rx.write(utf8.decode(data, allowMalformed: true));
    String text = _rx.toString();
    final List<String> payloads = <String>[];

    while (true) {
      final int end = text.indexOf(endMark);
      if (end < 0) {
        if (text.length > maxChars) {
          final int start = text.lastIndexOf(startMark);
          text = start >= 0 ? text.substring(start) : '';
        }
        break;
      }

      final String beforeEnd = text.substring(0, end);
      text = text.substring(end + 1);

      final int start = beforeEnd.lastIndexOf(startMark);
      if (start < 0) {
        continue;
      }

      payloads.add(_sanitize(beforeEnd.substring(start + 1)));
    }

    _rx
      ..clear()
      ..write(text);
    return payloads;
  }

  String _sanitize(String inner) {
    return inner.replaceAll(RegExp(r'[<>\s]'), '');
  }
}
