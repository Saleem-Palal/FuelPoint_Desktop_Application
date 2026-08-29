import '../domain/telemetry_models.dart';
import 'java_mid.dart';

/// Historical log record. First character must be "2".
SaleEvent? decodeType36(String payload) {
  if (payload.length != 36) {
    return null;
  }
  try {
    if (javaMid(payload, 1, 1) != '2') {
      return null;
    }
    final String number = javaMid(payload, 2, 2);
    final double amount = javaMoney(payload, 4, 8);
    final double volume = javaMoney(payload, 12, 8);
    final double rate = javaMoney(payload, 20, 5);
    final String hrs = javaMid(payload, 31, 2);
    final String min = javaMid(payload, 33, 2);
    final String sec = javaMid(payload, 35, 2);
    final String day = javaMid(payload, 29, 2);
    final String month = javaMid(payload, 27, 2);
    final String year = javaMid(payload, 25, 2);
    final String line =
        '#$number $amount Rs. $volume Ltr. $rate Rs/Ltr at $hrs:$min:$sec $day/$month/$year';
    return SaleEvent(
      kind: SaleEventKind.logRecord,
      message: line,
      logLine: '> Log: $line',
    );
  } catch (_) {
    return null;
  }
}
