String formatPkr(double value) {
  final String raw = value.toStringAsFixed(2);
  final List<String> parts = raw.split('.');
  final String whole = parts[0];
  final String fraction = parts.length > 1 ? parts[1] : '00';
  final StringBuffer grouped = StringBuffer();
  for (int i = 0; i < whole.length; i++) {
    final int fromEnd = whole.length - i;
    grouped.write(whole[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) {
      grouped.write(',');
    }
  }
  return 'Rs. ${grouped.toString()}.$fraction';
}

String formatLiters(double value) {
  return '${value.toStringAsFixed(2)} Ltr';
}

String formatRate(double value) {
  return '${formatPkr(value)} / L';
}

String formatClock(DateTime time) {
  final int hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final String minute = time.minute.toString().padLeft(2, '0');
  final String period = time.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $period';
}

String formatDateTime(DateTime time) {
  final String day = time.day.toString().padLeft(2, '0');
  final String month = time.month.toString().padLeft(2, '0');
  return '$day-$month-${time.year} ${formatClock(time)}';
}

String formatMeterReading(double value) {
  return value.toStringAsFixed(3);
}

String formatInvoiceNo(int invoiceNo) {
  return 'Inv-$invoiceNo';
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
