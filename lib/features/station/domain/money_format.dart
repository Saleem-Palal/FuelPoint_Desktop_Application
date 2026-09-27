import '../../../core/decimal_display.dart';
import 'fuel_precision.dart';

String formatSignedPkr(double value) {
  if (value == 0) {
    return formatPkr(0);
  }
  final String formatted = formatPkr(value.abs());
  return value > 0 ? '+$formatted' : '-$formatted';
}

String _groupThousands(String whole) {
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

/// Blank when the tender column is unused (Udhaar, or Account-only Cash).
String formatTenderPkr(double value) {
  if (roundRupees(value) == 0) {
    return '—';
  }
  return formatPkr(value);
}

/// Table amount: grouped whole rupees, no `Rs.` prefix.
String formatTablePkr(double value) {
  final int rounded = value.round();
  final String grouped = _groupThousands(rounded.abs().toString());
  if (rounded < 0) {
    return '-$grouped';
  }
  return grouped;
}

String formatTableSignedPkr(double value) {
  if (value == 0) {
    return formatTablePkr(0);
  }
  final String formatted = formatTablePkr(value.abs());
  return value > 0 ? '+$formatted' : '-$formatted';
}

/// Table volume: truncated decimals, no `Ltr` suffix.
String formatTableLiters(double value) {
  return groupTruncatedDecimal(value);
}

/// Table rate: truncated decimals, no `Rs.` or `/ L`.
String formatTableRate(double value) {
  return groupTruncatedDecimal(value);
}

/// Table tender column: em dash when unused, otherwise [formatTablePkr].
String formatTableTenderPkr(double value) {
  if (roundRupees(value) == 0) {
    return '—';
  }
  return formatTablePkr(value);
}

String formatPkr(double value) {
  return formatPkrWhole(value);
}

/// Live dispenser PKR (`Rs. 6,618.50`). Truncates, never rounds.
String formatDispenserPkr(double value) {
  return 'Rs. ${groupTruncatedDecimal(value)}';
}

/// Whole-rupee PKR label (`Rs. 1,235`).
String formatPkrWhole(double value) {
  final int rounded = value.round();
  final String grouped = _groupThousands(rounded.abs().toString());
  if (rounded < 0) {
    return 'Rs. -$grouped';
  }
  return 'Rs. $grouped';
}

/// Render-time PKR label used on credit balances (`Rs. 1,234.56 PKR`).
String formatPkrStatement(double value) {
  return '${formatPkr(value)} PKR';
}

String formatPkrStatementWhole(double value) {
  return '${formatPkrWhole(value)} PKR';
}

String formatLiters(double value) {
  return '${groupTruncatedDecimal(value)} Ltr';
}

/// Two decimal digits, truncated, no unit. For table cells and tickets.
String formatTruncatedDecimal(double value) {
  return groupTruncatedDecimal(value);
}

/// Average rate / WAC for UI: two decimals, truncated, never rounded.
String formatAverageRateValue(double value) {
  return 'Rs. ${groupTruncatedDecimal(value)}';
}

String formatAverageRate(double value) {
  return '${formatAverageRateValue(value)} / L';
}

String formatRate(double value) {
  return formatAverageRate(value);
}

String formatClock(DateTime time) {
  final int hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final String minute = time.minute.toString().padLeft(2, '0');
  final String period = time.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $period';
}

String formatClockWithSeconds(DateTime time) {
  final int hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final String minute = time.minute.toString().padLeft(2, '0');
  final String second = time.second.toString().padLeft(2, '0');
  final String period = time.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute:$second $period';
}

String formatDateTime(DateTime time) {
  final String day = time.day.toString().padLeft(2, '0');
  final String month = time.month.toString().padLeft(2, '0');
  return '$day-$month-${time.year} ${formatClock(time)}';
}

String formatDateOnly(DateTime time) {
  final String day = time.day.toString().padLeft(2, '0');
  final String month = time.month.toString().padLeft(2, '0');
  return '$day-$month-${time.year}';
}

String formatDateRangeLabel(DateTime start, DateTime end) {
  return '${formatDateOnly(start)} → ${formatDateOnly(end)}';
}

String formatMeterReading(double value) {
  return groupTruncatedDecimal(value);
}

String formatInvoiceNo(int invoiceNo) {
  return 'Inv-$invoiceNo';
}

int parseInvoiceNo(String invNo) {
  final Match? match = RegExp(r'(\d+)$').firstMatch(invNo.trim());
  if (match == null) {
    return 0;
  }
  return int.tryParse(match.group(1) ?? '') ?? 0;
}

String formatKg(double value) {
  return '${value.toStringAsFixed(2)} Kg';
}

String formatSharah(double value) {
  return value.toStringAsFixed(3);
}

DateTime startOfMonth(DateTime value) {
  return DateTime(value.year, value.month);
}

DateTime addCalendarMonths(DateTime month, int delta) {
  return DateTime(month.year, month.month + delta);
}

String formatMonthTitle(DateTime month) {
  const List<String> names = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${names[month.month - 1]} ${month.year}';
}
