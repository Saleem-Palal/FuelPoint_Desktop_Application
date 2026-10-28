import 'dart:typed_data';

/// Averages a microphone stream down to 16 kHz 16-bit mono.
///
/// This is the same mix the walkie-talkie page does in the browser: each
/// output sample is the average of the input samples that belong to it.
class IntercomBoxcar {
  final List<double> _carry = <double>[];
  final List<int> _ready = <int>[];

  void reset() {
    _carry.clear();
    _ready.clear();
  }

  void add(List<double> samples, int inputRate) {
    if (samples.isEmpty || inputRate <= 0) {
      return;
    }
    _carry.addAll(samples);
    final double ratio = inputRate / 16000;
    int offset = 0;
    while (true) {
      final int next = (offset + ratio).round();
      if (next <= offset || next > _carry.length) {
        break;
      }
      double sum = 0;
      for (int i = offset; i < next; i++) {
        sum += _carry[i];
      }
      final int count = next - offset;
      double mixed = count == 0 ? 0 : sum / count;
      if (mixed > 1) {
        mixed = 1;
      } else if (mixed < -1) {
        mixed = -1;
      }
      final int sample = mixed < 0
          ? (mixed * 32768).truncate()
          : (mixed * 32767).truncate();
      _ready.add(sample);
      offset = next;
    }
    if (offset > 0) {
      _carry.removeRange(0, offset);
    }
  }

  /// Next [sampleCount] samples as little-endian PCM, when that many are ready.
  Uint8List? takeChunk(int sampleCount) {
    if (sampleCount <= 0 || _ready.length < sampleCount) {
      return null;
    }
    final Uint8List out = Uint8List(sampleCount * 2);
    final ByteData view = ByteData.sublistView(out);
    for (int i = 0; i < sampleCount; i++) {
      view.setInt16(i * 2, _ready[i], Endian.little);
    }
    _ready.removeRange(0, sampleCount);
    return out;
  }
}
