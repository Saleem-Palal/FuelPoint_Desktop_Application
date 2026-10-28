import 'dart:math' as math;
import 'dart:typed_data';

import 'intercom_codec.dart';

/// Six-second tone used when no speaker file has been chosen.
Uint8List intercomTestTone() {
  const int seconds = 6;
  final int count = IntercomCodec.sampleRate * seconds;
  final Uint8List out = Uint8List(count * 2);
  final ByteData view = ByteData.sublistView(out);
  const int amplitude = 10000;
  for (int i = 0; i < count; i++) {
    final double t = i / IntercomCodec.sampleRate;
    final double hz = t < 2 ? 440 : (t < 4 ? 660 : 880);
    final int sample = (math.sin(2 * math.pi * hz * t) * amplitude).round();
    view.setInt16(i * 2, sample, Endian.little);
  }
  return out;
}

/// 16 kHz mono PCM from a WAV file, or null when the file is not PCM/float WAV.
Uint8List? pcm16kFromWav(Uint8List bytes) {
  if (bytes.length < 44) {
    return null;
  }
  final ByteData data = ByteData.sublistView(bytes);
  if (data.getUint32(0, Endian.little) != 0x46464952 ||
      data.getUint32(8, Endian.little) != 0x45564157) {
    return null;
  }
  int? format;
  int? channels;
  int? rate;
  int? bits;
  Uint8List? pcm;
  int offset = 12;
  while (offset + 8 <= bytes.length) {
    final int id = data.getUint32(offset, Endian.little);
    final int size = data.getUint32(offset + 4, Endian.little);
    final int start = offset + 8;
    if (size < 0 || start > bytes.length) {
      break;
    }
    final int end = start + size > bytes.length ? bytes.length : start + size;
    if (id == 0x20746d66 && end - start >= 16) {
      format = data.getUint16(start, Endian.little);
      channels = data.getUint16(start + 2, Endian.little);
      rate = data.getUint32(start + 4, Endian.little);
      bits = data.getUint16(start + 14, Endian.little);
    } else if (id == 0x61746164) {
      pcm = Uint8List.sublistView(bytes, start, end);
    }
    offset = start + size + (size.isOdd ? 1 : 0);
  }
  if (pcm == null ||
      format == null ||
      channels == null ||
      rate == null ||
      bits == null ||
      channels < 1 ||
      rate < 1000) {
    return null;
  }
  final bool pcmInt =
      format == 1 && (bits == 8 || bits == 16 || bits == 24 || bits == 32);
  final bool pcmFloat = format == 3 && bits == 32;
  if (!pcmInt && !pcmFloat) {
    return null;
  }
  final int width = bits ~/ 8;
  final int frame = width * channels;
  if (frame <= 0 || pcm.length < frame) {
    return null;
  }
  final int frames = pcm.length ~/ frame;
  final Float64List mono = Float64List(frames);
  final ByteData raw = ByteData.sublistView(pcm);
  for (int i = 0; i < frames; i++) {
    double sum = 0;
    for (int channel = 0; channel < channels; channel++) {
      final int at = (i * frame) + (channel * width);
      sum += _sample(raw, at, bits, pcmFloat);
    }
    mono[i] = sum / channels;
  }
  return _resample(mono, rate, IntercomCodec.sampleRate);
}

double _sample(ByteData raw, int at, int bits, bool floating) {
  if (floating) {
    return raw.getFloat32(at, Endian.little).clamp(-1, 1);
  }
  if (bits == 8) {
    return (raw.getUint8(at) - 128) / 128;
  }
  if (bits == 16) {
    return raw.getInt16(at, Endian.little) / 32768;
  }
  if (bits == 24) {
    final int b0 = raw.getUint8(at);
    final int b1 = raw.getUint8(at + 1);
    final int b2 = raw.getUint8(at + 2);
    int value = b0 | (b1 << 8) | (b2 << 16);
    if ((value & 0x800000) != 0) {
      value |= ~0xFFFFFF;
    }
    return value / 8388608;
  }
  return raw.getInt32(at, Endian.little) / 2147483648;
}

Uint8List _resample(Float64List input, int fromRate, int toRate) {
  if (input.isEmpty) {
    return Uint8List(0);
  }
  final int outCount = math.min(
    toRate * 180,
    math.max(1, (input.length * toRate) ~/ fromRate),
  );
  final Uint8List out = Uint8List(outCount * 2);
  final ByteData view = ByteData.sublistView(out);
  for (int i = 0; i < outCount; i++) {
    final double position = i * fromRate / toRate;
    final int index = position.floor();
    final double frac = position - index;
    final double a = input[math.min(index, input.length - 1)];
    final double b = input[math.min(index + 1, input.length - 1)];
    final double mixed = a + ((b - a) * frac);
    int sample = (mixed * 32767).round();
    if (sample > 32767) {
      sample = 32767;
    } else if (sample < -32768) {
      sample = -32768;
    }
    view.setInt16(i * 2, sample, Endian.little);
  }
  return out;
}
