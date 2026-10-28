/// Keep only glyphs Roboto can draw. Anything else is dropped so layout
/// cannot abort on a missing character.
String pdfSafeText(String value) {
  final String normalized = value
      .replaceAll(RegExp(r'[\u2010-\u2015\u2212\uFE58\uFE63\uFF0D]'), '-')
      .replaceAll('\u2192', ' - ')
      .replaceAll('\u2190', ' - ')
      .replaceAll('\u2026', '...')
      .replaceAll('\u00A0', ' ');
  final StringBuffer out = StringBuffer();
  for (final int rune in normalized.runes) {
    final bool latin =
        (rune >= 0x20 && rune <= 0x7E) ||
        (rune >= 0xA1 && rune <= 0xFF) ||
        (rune >= 0x100 && rune <= 0x17F);
    if (latin) {
      out.writeCharCode(rune);
    }
  }
  return out.toString();
}

/// One table cell, single line, clipped so a row cannot grow.
String pdfCell(String value, {int maxChars = 32}) {
  final String flat = pdfSafeText(value).replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.isEmpty) {
    return '-';
  }
  final List<int> runes = flat.runes.toList(growable: false);
  if (runes.length <= maxChars) {
    return flat;
  }
  return '${String.fromCharCodes(runes.take(maxChars - 3))}...';
}
