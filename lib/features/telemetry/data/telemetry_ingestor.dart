import 'dart:typed_data';

import '../domain/telemetry_models.dart';
import 'ascii_frame_buffer.dart';
import 'type29_decoder.dart';
import 'type33_decoder.dart';
import 'type36_decoder.dart';
import 'type37_decoder.dart';

class TelemetryIngestor {
  final AsciiFrameBuffer _buffer = AsciiFrameBuffer();

  void reset() {
    _buffer.reset();
  }

  IngestOutcome ingest(Uint8List data, TelemetrySnapshot current) {
    TelemetrySnapshot next = current.copyWith(
      rxBytes: current.rxBytes + data.length,
    );
    final List<String> logLines = <String>[];

    for (final String payload in _buffer.push(data)) {
      switch (payload.length) {
        case 33:
          final Type33Frame? live = decodeType33(payload);
          if (live != null) {
            next = next.mergeType33(live);
          }
          break;
        case 37:
          final Type37Result? stopped = decodeType37(payload);
          if (stopped != null) {
            next = next.mergeType37(stopped);
            logLines.add(stopped.event.logLine);
          }
          break;
        case 29:
          final SaleEvent? started = decodeType29(payload);
          if (started != null) {
            next = next.addEvent(started);
            logLines.add(started.logLine);
          }
          break;
        case 36:
          final SaleEvent? record = decodeType36(payload);
          if (record != null) {
            next = next.addEvent(record);
          }
          break;
        default:
          break;
      }
    }

    return IngestOutcome(snapshot: next, logLines: logLines);
  }
}
