/// Calendar days covered by one All Transactions block.
const int kAllTransactionsWindowDays = 30;

/// Inclusive calendar window for the All Transactions ledger.
class SalesLedgerWindow {
  const SalesLedgerWindow({
    required this.from,
    required this.to,
    required this.isDefault,
  });

  /// First calendar day included.
  final DateTime from;

  /// Last calendar day included.
  final DateTime to;

  /// True when the operator has not picked a custom range.
  final bool isDefault;
}

/// Page [pageIndex] 0 is the last 30 days through today.
///
/// Each older page ends the day before the previous page starts, then
/// stretches 30 days back, so blocks share no day. A picked [from] and [to]
/// replaces stepping.
SalesLedgerWindow salesLedgerWindowForPage({
  required int pageIndex,
  DateTime? from,
  DateTime? to,
  DateTime? now,
}) {
  if (from != null && to != null) {
    return SalesLedgerWindow(from: from, to: to, isDefault: false);
  }
  final DateTime clock = now ?? DateTime.now();
  final DateTime today = DateTime(clock.year, clock.month, clock.day);
  final int page = pageIndex < 0 ? 0 : pageIndex;
  final DateTime end = today.subtract(
    Duration(days: page * (kAllTransactionsWindowDays + 1)),
  );
  final DateTime start = end.subtract(
    const Duration(days: kAllTransactionsWindowDays),
  );
  return SalesLedgerWindow(from: start, to: end, isDefault: true);
}

/// How many 30-day blocks reach back to [oldest]. One page when there is
/// no history.
int salesLedgerBlockCount(DateTime? oldest, {DateTime? now}) {
  if (oldest == null) {
    return 1;
  }
  final DateTime clock = now ?? DateTime.now();
  final DateTime today = DateTime(clock.year, clock.month, clock.day);
  final DateTime oldestDay = DateTime(oldest.year, oldest.month, oldest.day);
  if (oldestDay.isAfter(today)) {
    return 1;
  }
  final int spanInclusive = today.difference(oldestDay).inDays + 1;
  final int blockDays = kAllTransactionsWindowDays + 1;
  if (spanInclusive <= blockDays) {
    return 1;
  }
  return (spanInclusive + kAllTransactionsWindowDays) ~/ blockDays;
}
