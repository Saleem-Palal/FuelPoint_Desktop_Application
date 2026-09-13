/// Display-only decimal chopping. Never use this in stored math.
///
/// [toStringAsFixed] and `NumberFormat` round. These helpers hide extra
/// digits without rounding.
String truncateToDecimalPlaces(double value, int places) {
  if (!value.isFinite || places < 0) {
    return places <= 0 ? '0' : '0.${'0' * places}';
  }
  final bool negative = value.isNegative && value != 0;
  final String raw = value.abs().toStringAsFixed(places + 8);
  final int dot = raw.indexOf('.');
  final String whole = dot < 0 ? raw : raw.substring(0, dot);
  final String fracRaw = dot < 0 ? '' : raw.substring(dot + 1);
  final StringBuffer digits = StringBuffer();
  for (int i = 0; i < fracRaw.length; i++) {
    final int code = fracRaw.codeUnitAt(i);
    if (code >= 48 && code <= 57) {
      digits.writeCharCode(code);
    }
  }
  final String padded = digits.toString().padRight(places, '0');
  final String frac = places == 0 ? '' : padded.substring(0, places);
  final String unsigned = places == 0 ? whole : '$whole.$frac';
  return negative ? '-$unsigned' : unsigned;
}

String groupTruncatedDecimal(double value, {int places = 2}) {
  final String truncated = truncateToDecimalPlaces(value, places);
  final bool negative = truncated.startsWith('-');
  final String unsigned = negative ? truncated.substring(1) : truncated;
  final int dot = unsigned.indexOf('.');
  final String whole = dot < 0 ? unsigned : unsigned.substring(0, dot);
  final String frac = dot < 0 ? '' : unsigned.substring(dot + 1);
  final String grouped = _groupThousands(whole);
  final String withFrac = places == 0 ? grouped : '$grouped.$frac';
  return negative ? '-$withFrac' : withFrac;
}

String _groupThousands(String whole) {
  if (whole.length <= 3) {
    return whole;
  }
  final StringBuffer grouped = StringBuffer();
  for (int i = 0; i < whole.length; i++) {
    final int fromEnd = whole.length - i;
    grouped.write(whole[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) {
      grouped.write(',');
    }
  }
  return grouped.toString();
}
