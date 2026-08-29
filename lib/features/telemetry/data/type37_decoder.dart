import '../domain/telemetry_models.dart';
import 'java_mid.dart';

/// Transaction complete / stopped. Flag at first character (Java Mid 1,1).
Type37Result? decodeType37(String payload) {
  if (payload.length != 37) {
    return null;
  }
  try {
    final String flag = javaMid(payload, 1, 1);
    if (flag != '6' && flag != '7') {
      return null;
    }

    final double amount = javaMoney(payload, 5, 8);
    final double volume = javaMoney(payload, 13, 8);
    final double rate = javaMoney(payload, 21, 5);
    final String year = javaMid(payload, 26, 2);
    final String month = javaMid(payload, 28, 2);
    final String day = javaMid(payload, 30, 2);
    final String hrs = javaMid(payload, 32, 2);
    final String min = javaMid(payload, 34, 2);
    final String sec = javaMid(payload, 36, 2);
    final String dateLabel = formatDate(day, month, year);
    final String timeLabel = '$hrs:$min:$sec';

    if (flag == '6') {
      return Type37Result(
        noSale: true,
        amount: amount,
        volumeLiters: volume,
        unitRate: rate,
        timeLabel: timeLabel,
        dateLabel: dateLabel,
        event: SaleEvent(
          kind: SaleEventKind.noSale,
          message:
              'No sale at $timeLabel Hrs $dateLabel (nozzle replaced, no fuel).',
          logLine: '> Stopped With Out Sale: at $timeLabel Hrs $dateLabel',
        ),
      );
    }

    return Type37Result(
      noSale: false,
      amount: amount,
      volumeLiters: volume,
      unitRate: rate,
      timeLabel: timeLabel,
      dateLabel: dateLabel,
      event: SaleEvent(
        kind: SaleEventKind.saleClosed,
        message:
            'Sale closed: Rs ${amount.toStringAsFixed(2)} · ${volume.toStringAsFixed(2)} L · Rt ${rate.toStringAsFixed(2)} at $timeLabel Hrs $dateLabel',
        logLine:
            '> Sale Closed: Rs $amount Ltr $volume Rt $rate at $timeLabel Hrs $dateLabel',
      ),
    );
  } catch (_) {
    return null;
  }
}
