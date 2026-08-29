import '../domain/telemetry_models.dart';
import 'java_mid.dart';

/// Transaction start. First character must be "4".
SaleEvent? decodeType29(String payload) {
  if (payload.length != 29) {
    return null;
  }
  try {
    if (javaMid(payload, 1, 1) != '4') {
      return null;
    }
    final double total = javaMoney(payload, 5, 8);
    final double rate = javaMoney(payload, 24, 5);
    final String year = javaMid(payload, 18, 2);
    final String month = javaMid(payload, 20, 2);
    final String day = javaMid(payload, 22, 2);
    final String hrs = javaMid(payload, 24, 2);
    final String min = javaMid(payload, 26, 2);
    final String sec = javaMid(payload, 28, 2);
    final String dateLabel = formatDate(day, month, year);
    final String timeLabel = '$hrs:$min:$sec';
    return SaleEvent(
      kind: SaleEventKind.saleStarted,
      message:
          'Sale started: Rt ${rate.toStringAsFixed(2)} · meter ${total.toStringAsFixed(2)} at $timeLabel Hrs $dateLabel',
      logLine:
          '> Sale Started: Rt $rate Tm $total at $timeLabel Hrs $dateLabel',
    );
  } catch (_) {
    return null;
  }
}
