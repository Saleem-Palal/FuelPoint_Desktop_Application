import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:fuel_dispenser/features/dashboard/dashboard_controller.dart';
import 'package:fuel_dispenser/features/telemetry/data/ascii_frame_buffer.dart';
import 'package:fuel_dispenser/features/telemetry/data/telemetry_ingestor.dart';
import 'package:fuel_dispenser/features/telemetry/data/type33_decoder.dart';
import 'package:fuel_dispenser/features/telemetry/data/type37_decoder.dart';
import 'package:fuel_dispenser/features/telemetry/domain/telemetry_models.dart';

Uint8List _bytes(String ascii) => Uint8List.fromList(utf8.encode(ascii));

void _write(List<String> chars, int start, String value) {
  for (int i = 0; i < value.length; i++) {
    chars[start + i] = value[i];
  }
}

/// Java Type-33: status(1) + unit(2) + product(1) + amount(8) + liters(8) + rate(5) + meter(8)
String type33Payload({
  String status = '5',
  String unitId = '01',
  String product = '0',
  String amount8 = '00050000',
  String volume8 = '00000187',
  String rate5 = '26700',
  String meter8 = '56069506',
}) {
  return '$status$unitId$product$amount8$volume8$rate5$meter8';
}

String type37Payload({
  required String flag,
  String amount8 = '00033750',
  String volume8 = '00001250',
  String rate5 = '27050',
  String yymmddhhmmss = '260421060442',
}) {
  final List<String> chars = List<String>.filled(37, '0');
  chars[0] = flag;
  _write(chars, 4, amount8);
  _write(chars, 12, volume8);
  _write(chars, 20, rate5);
  _write(chars, 25, yymmddhhmmss);
  return chars.join();
}

void main() {
  test('type-33 maps amount, liters, rate, and meter without mixing fields', () {
    final String payload = type33Payload();
    expect(payload.length, 33);

    final Type33Frame? frame = decodeType33(payload);
    expect(frame, isNotNull);
    expect(frame!.totalAmount, closeTo(500.00, 0.001));
    expect(frame.volumeLiters, closeTo(1.87, 0.001));
    expect(frame.unitRate, closeTo(267.00, 0.001));
    expect(frame.totalMeter, closeTo(560695.06, 0.001));
    expect(frame.product, ProductType.petrol);
    expect(frame.pumpStatus, PumpStatus.nozzleActive);
  });

  test('type-33 does not format total meter as a clock', () {
    final IngestOutcome outcome = TelemetryIngestor().ingest(
      _bytes('<${type33Payload()}>'),
      TelemetrySnapshot.empty,
    );
    expect(outcome.snapshot.timeLabel, isNot('06:95:06'));
    expect(outcome.snapshot.unitRate, isNot(closeTo(187.26, 0.01)));
    expect(outcome.snapshot.totalMeter, closeTo(560695.06, 0.001));
    expect(outcome.snapshot.timeLabel, matches(RegExp(r'^\d{2}:\d{2}:\d{2}$')));
  });

  test('strips spaces and CRLF from framed payload', () {
    final AsciiFrameBuffer buffer = AsciiFrameBuffer();
    final String payload = type33Payload();
    final List<String> got = buffer.push(_bytes('< $payload \r\n>'));
    expect(got.single, payload);
  });

  test('length router: 33 updates live cards, junk lengths ignored', () {
    final TelemetryIngestor ingestor = TelemetryIngestor();
    IngestOutcome outcome = ingestor.ingest(
      _bytes('<SHORT>'),
      TelemetrySnapshot.empty,
    );
    expect(outcome.snapshot.volumeLiters, isNull);

    outcome = ingestor.ingest(_bytes('<${type33Payload()}>'), outcome.snapshot);
    expect(outcome.snapshot.volumeLiters, closeTo(1.87, 0.001));
    expect(outcome.snapshot.totalAmount, closeTo(500.00, 0.001));
  });

  test('type 37 flag 6 is a no-sale event', () {
    final Type37Result? result = decodeType37(type37Payload(flag: '6'));
    expect(result, isNotNull);
    expect(result!.noSale, isTrue);
    expect(result.event.kind, SaleEventKind.noSale);
    expect(result.event.logLine, contains('Stopped With Out Sale'));
  });

  test('type 37 flag 7 updates sale totals and log line', () {
    final TelemetryIngestor ingestor = TelemetryIngestor();
    final IngestOutcome outcome = ingestor.ingest(
      _bytes('<${type37Payload(flag: '7')}>'),
      TelemetrySnapshot.empty,
    );
    expect(outcome.snapshot.totalAmount, closeTo(337.50, 0.001));
    expect(outcome.snapshot.volumeLiters, closeTo(12.50, 0.001));
    expect(outcome.snapshot.unitRate, closeTo(270.50, 0.001));
    expect(outcome.snapshot.lastEvent?.kind, SaleEventKind.saleClosed);
    expect(outcome.snapshot.timeFromRtc, isTrue);
    expect(outcome.logLines.single, contains('Sale Closed'));
  });

  test('type-33 keeps RTC time from type-37 and does not overwrite the clock', () {
    final TelemetryIngestor ingestor = TelemetryIngestor();
    IngestOutcome outcome = ingestor.ingest(
      _bytes('<${type37Payload(flag: '7')}>'),
      TelemetrySnapshot.empty,
    );
    final String? rtc = outcome.snapshot.timeLabel;
    expect(rtc, isNotNull);

    outcome = ingestor.ingest(_bytes('<${type33Payload()}>'), outcome.snapshot);
    expect(outcome.snapshot.timeLabel, rtc);
    expect(outcome.snapshot.totalMeter, closeTo(560695.06, 0.001));
    expect(outcome.snapshot.volumeLiters, closeTo(1.87, 0.001));
    expect(outcome.snapshot.unitRate, closeTo(267.00, 0.001));
  });

  test('parseHexBytes accepts spaced hex', () {
    final Uint8List? bytes = parseHexBytes('01 0A ff');
    expect(bytes, isNotNull);
    expect(bytes, <int>[0x01, 0x0A, 0xFF]);
  });
}
