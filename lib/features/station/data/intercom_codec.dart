import 'dart:convert';
import 'dart:typed_data';

/// One helper-button edge from the unit ESP32.
class IntercomNotice {
  const IntercomNotice({required this.unitId, required this.helperDown});

  final int unitId;
  final bool helperDown;
}

/// 16 kHz mono PCM frames shared by the app and the unit ESP32.
class IntercomCodec {
  const IntercomCodec._();

  static const int operatorMagic = 0xA1;
  static const int helperMagic = 0xA2;
  static const int sampleRate = 16000;
  static const int samplesPerChunk = 320;
  static const int pcmBytes = samplesPerChunk * 2;
  static const int frameBytes = 1 + pcmBytes;

  static Uint8List operatorFrame(Uint8List pcm) {
    return _frame(operatorMagic, pcm);
  }

  static Uint8List helperFrame(Uint8List pcm) {
    return _frame(helperMagic, pcm);
  }

  static Uint8List _frame(int magic, Uint8List pcm) {
    final Uint8List out = Uint8List(frameBytes);
    out[0] = magic;
    final int count = pcm.length < pcmBytes ? pcm.length : pcmBytes;
    out.setRange(1, 1 + count, pcm);
    return out;
  }

  /// PCM payload of a full chunk, or null when the magic or length is wrong.
  static Uint8List? pcmFromFrame(List<int> frame, {required int magic}) {
    if (frame.length != frameBytes || frame.isEmpty || frame[0] != magic) {
      return null;
    }
    return Uint8List.fromList(frame.sublist(1));
  }
}

/// High-pass, noise gate, and optional peak soften for one voice direction.
class IntercomVoiceCleaner {
  IntercomVoiceCleaner({this.stationSpeaker = false});

  /// Helper audio played on this computer. Flat hiss is pulled down harder
  /// than the pump path, and a recent word is left alone.
  final bool stationSpeaker;
  int _prevX = 0;
  int _prevY = 0;
  int _speechHold = 0;

  void reset() {
    _prevX = 0;
    _prevY = 0;
    _speechHold = 0;
  }

  /// Straight gain from 0 to 100. No filter and no noise gate.
  static Uint8List scale(Uint8List pcm, int gain) {
    final int samples = pcm.length ~/ 2;
    final Uint8List out = Uint8List(samples * 2);
    if (samples == 0) {
      return out;
    }
    final int g = gain.clamp(0, 100);
    final ByteData input = ByteData.sublistView(pcm, 0, samples * 2);
    final ByteData output = ByteData.sublistView(out);
    for (int i = 0; i < samples; i++) {
      int y = (input.getInt16(i * 2, Endian.little) * g) ~/ 100;
      if (y > 32767) {
        y = 32767;
      } else if (y < -32768) {
        y = -32768;
      }
      output.setInt16(i * 2, y, Endian.little);
    }
    return out;
  }

  Uint8List apply(
    Uint8List pcm, {
    required bool softenPeaks,
    int gain = 100,
    int noiseCut = 0,
  }) {
    final int samples = pcm.length ~/ 2;
    final Uint8List out = Uint8List(samples * 2);
    if (samples == 0) {
      return out;
    }
    final ByteData input = ByteData.sublistView(pcm, 0, samples * 2);
    final ByteData output = ByteData.sublistView(out);
    int levelSum = 0;
    int levelPeak = 0;
    for (int i = 0; i < samples; i++) {
      final int x = input.getInt16(i * 2, Endian.little);
      int y = x - _prevX + ((_prevY * 31) >> 5);
      _prevX = x;
      _prevY = y;
      if (y > 32767) {
        y = 32767;
      } else if (y < -32768) {
        y = -32768;
      }
      final int boundedGain = gain < 0 ? 0 : (gain > 100 ? 100 : gain);
      y = (y * boundedGain) ~/ 100;
      if (y > 32767) {
        y = 32767;
      } else if (y < -32768) {
        y = -32768;
      }
      if (softenPeaks) {
        if (y > 18000) {
          y = 18000 + ((y - 18000) >> 2);
        } else if (y < -18000) {
          y = -18000 + ((y + 18000) >> 2);
        }
        if (y < 480 && y > -480) {
          y = y >> 3;
        }
      } else {
        y = _softenStation(y, noiseCut);
      }
      if (softenPeaks) {
        y = _softenFloor(y, noiseCut);
      }
      final int mag = y < 0 ? -y : y;
      levelSum += mag;
      if (mag > levelPeak) {
        levelPeak = mag;
      }
      output.setInt16(i * 2, y, Endian.little);
    }
    if (stationSpeaker) {
      _duckFlatHiss(
        output,
        samples: samples,
        levelSum: levelSum,
        levelPeak: levelPeak,
        noiseCut: noiseCut,
      );
    }
    return out;
  }

  /// Turns a noise-cut slider into a downward gate. It never filters again,
  /// so it cannot make hiss louder.
  static Uint8List pullDown(Uint8List pcm, int noiseCut) {
    final int cut = noiseCut < 0 ? 0 : (noiseCut > 100 ? 100 : noiseCut);
    if (cut <= 0 || pcm.length < 2) {
      return pcm;
    }
    final int samples = pcm.length ~/ 2;
    final ByteData input = ByteData.sublistView(pcm, 0, samples * 2);
    final Uint8List out = Uint8List(samples * 2);
    final ByteData output = ByteData.sublistView(out);
    int levelSum = 0;
    int levelPeak = 0;
    for (int i = 0; i < samples; i++) {
      final int y = _softenStation(
        input.getInt16(i * 2, Endian.little),
        cut,
      );
      final int mag = y < 0 ? -y : y;
      levelSum += mag;
      if (mag > levelPeak) {
        levelPeak = mag;
      }
      output.setInt16(i * 2, y, Endian.little);
    }
    final int mean = levelSum ~/ samples;
    if (mean >= 8000 && levelPeak >= 12000) {
      return out;
    }
    final int keep = 100 - ((cut * 92) ~/ 100);
    final int bounded = keep < 8 ? 8 : keep;
    if (bounded >= 100) {
      return out;
    }
    for (int i = 0; i < samples; i++) {
      final int y = output.getInt16(i * 2, Endian.little);
      output.setInt16(i * 2, (y * bounded) ~/ 100, Endian.little);
    }
    return out;
  }

  /// PC speaker. 0 leaves the level alone. 100 pulls a loud hiss down.
  static int _softenStation(int sample, int noiseCut) {
    final int mag = sample < 0 ? -sample : sample;
    if (mag < 180) {
      return 0;
    }
    final int cut = noiseCut < 0 ? 0 : (noiseCut > 100 ? 100 : noiseCut);
    if (cut <= 0) {
      return sample;
    }
    final int thresh = 400 + (cut * 176);
    if (mag >= thresh) {
      return sample;
    }
    final int pulled = (sample * mag) ~/ thresh;
    final int pulledMag = pulled < 0 ? -pulled : pulled;
    return (pulled * pulledMag) ~/ thresh;
  }

  void _duckFlatHiss(
    ByteData output, {
    required int samples,
    required int levelSum,
    required int levelPeak,
    required int noiseCut,
  }) {
    if (samples == 0 || noiseCut <= 0) {
      return;
    }
    final int cut = noiseCut > 100 ? 100 : noiseCut;
    final int mean = levelSum ~/ samples;
    final bool speech = mean >= 8000 && levelPeak >= 12000;
    if (speech) {
      _speechHold = 8;
      return;
    }
    if (_speechHold > 0) {
      _speechHold--;
      return;
    }
    final int keep = 100 - ((cut * 92) ~/ 100);
    final int bounded = keep < 8 ? 8 : keep;
    for (int i = 0; i < samples; i++) {
      final int y = output.getInt16(i * 2, Endian.little);
      output.setInt16(i * 2, (y * bounded) ~/ 100, Endian.little);
    }
  }

  /// Pulls the quiet floor down. Speech above the floor is left alone.
  static int _softenFloor(int sample, int noiseCut) {
    final int cut = noiseCut < 0 ? 0 : (noiseCut > 100 ? 100 : noiseCut);
    final int thresh = cut * 8;
    if (thresh <= 0) {
      return sample;
    }
    final int mag = sample < 0 ? -sample : sample;
    if (mag >= thresh) {
      return sample;
    }
    return (sample * mag) ~/ thresh;
  }
}

/// Control JSON for the helper button. Null when [text] is not an intercom
/// message, so telemetry can keep parsing everything else.
IntercomNotice? tryParseIntercomNotice(String text, {int fallbackUnit = 0}) {
  try {
    final Object? decoded = jsonDecode(text);
    if (decoded is! Map) {
      return null;
    }
    if (decoded['cmd'] != 'INTERCOM') {
      return null;
    }
    int unitId = int.tryParse('${decoded['unit'] ?? ''}') ?? fallbackUnit;
    if (unitId < 1 || unitId > 5) {
      unitId = fallbackUnit;
    }
    if (unitId < 1 || unitId > 5) {
      unitId = 0;
    }
    return IntercomNotice(unitId: unitId, helperDown: decoded['down'] == true);
  } catch (_) {
    return null;
  }
}
