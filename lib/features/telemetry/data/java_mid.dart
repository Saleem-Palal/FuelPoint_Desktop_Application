/// B4A StringFunctions Mid is 1-based: Mid(text, start, length).
String javaMid(String text, int start1Based, int length) {
  final int start = start1Based - 1;
  return text.substring(start, start + length);
}

double javaMoney(String text, int start1Based, int length) {
  return double.parse(javaMid(text, start1Based, length)) / 100.0;
}

String formatClock(String hhmmss) {
  if (hhmmss.length != 6) {
    return hhmmss;
  }
  return '${hhmmss.substring(0, 2)}:${hhmmss.substring(2, 4)}:${hhmmss.substring(4, 6)}';
}

String formatDate(String day, String month, String year) {
  return '$day/$month/$year';
}
