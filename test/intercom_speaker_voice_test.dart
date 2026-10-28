import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_dispenser/features/station/data/intercom_speaker_voice.dart';

void main() {
  test('voice is kept and high hiss is not amplified', () {
    final IntercomSpeakerVoice voice = IntercomSpeakerVoice();
    final Uint8List tone = _pcm(_tone(1000, 0.22, 1600));
    final Uint8List hiss = _pcm(_tone(6200, 0.22, 1600));

    final double toneLevel = _rms(voice.shape(tone, 100));
    voice.reset();
    final double hissLevel = _rms(voice.shape(hiss, 100));

    expect(toneLevel, greaterThan(0.05));
    expect(hissLevel, lessThan(toneLevel * 0.25));
  });

  test('a quiet noise floor is not boosted', () {
    final IntercomSpeakerVoice voice = IntercomSpeakerVoice();
    final math.Random random = math.Random(7);
    final Float64List noise = Float64List(1600);
    for (int i = 0; i < noise.length; i++) {
      noise[i] = (random.nextDouble() * 2 - 1) * 0.03;
    }
    final double level = _rms(voice.shape(_pcm(noise), 100));
    expect(level, lessThan(0.02));
  });
}

Uint8List _pcm(Float64List samples) {
  final Uint8List out = Uint8List(samples.length * 2);
  final ByteData data = ByteData.sublistView(out);
  for (int i = 0; i < samples.length; i++) {
    data.setInt16(i * 2, (samples[i] * 32767).round(), Endian.little);
  }
  return out;
}

Float64List _tone(double hz, double amplitude, int count) {
  final Float64List out = Float64List(count);
  for (int i = 0; i < count; i++) {
    out[i] = amplitude * math.sin(2 * math.pi * hz * i / 16000);
  }
  return out;
}

double _rms(Uint8List pcm) {
  final int samples = pcm.length ~/ 2;
  if (samples == 0) {
    return 0;
  }
  final ByteData data = ByteData.sublistView(pcm);
  double sum = 0;
  for (int i = 0; i < samples; i++) {
    final double sample = data.getInt16(i * 2, Endian.little) / 32768.0;
    sum += sample * sample;
  }
  return math.sqrt(sum / samples);
}
