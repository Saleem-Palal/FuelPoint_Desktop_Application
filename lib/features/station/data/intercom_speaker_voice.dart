import 'dart:math' as math;
import 'dart:typed_data';

/// Cleans the PC microphone before it is played on the ESP speaker.
///
/// A raw Windows mic is quieter than the walkie-talkie phone page, which
/// already ran noise suppression. Raising that raw signal turned the hiss up
/// with the voice. Voice-band frames are lifted a limited amount. Anything
/// that looks like hiss, including the gaps between words, is sent as silence.
class IntercomSpeakerVoice {
  static const int fftSize = 256;
  static const int hop = 128;

  final Float64List _window = _hann(fftSize);
  final List<double> _pending = <double>[];
  final Float64List _overlap = Float64List(hop);
  final Float64List _noise = Float64List((fftSize ~/ 2) + 1);
  final Float64List _re = Float64List(fftSize);
  final Float64List _im = Float64List(fftSize);
  final Float64List _mag = Float64List((fftSize ~/ 2) + 1);
  final Float64List _phaseRe = Float64List((fftSize ~/ 2) + 1);
  final Float64List _phaseIm = Float64List((fftSize ~/ 2) + 1);
  double _gain = 0;

  void reset() {
    _pending.clear();
    _overlap.fillRange(0, hop, 0);
    _noise.fillRange(0, _noise.length, 0);
    _gain = 0;
  }

  Uint8List shape(Uint8List pcm, int micPercent) {
    final int sampleCount = pcm.length ~/ 2;
    if (sampleCount == 0 || micPercent <= 0) {
      if (micPercent <= 0) {
        reset();
      }
      return Uint8List(sampleCount * 2);
    }
    final ByteData input = ByteData.sublistView(pcm, 0, sampleCount * 2);
    for (int i = 0; i < sampleCount; i++) {
      _pending.add(input.getInt16(i * 2, Endian.little) / 32768.0);
    }
    final List<double> produced = <double>[];
    final int mic = micPercent > 100 ? 100 : micPercent;
    while (_pending.length >= fftSize) {
      produced.addAll(_processFrame(mic));
      _pending.removeRange(0, hop);
    }
    return _toPcm(produced);
  }

  List<double> _processFrame(int micPercent) {
    double inputPeak = 0;
    for (int i = 0; i < fftSize; i++) {
      final double sample = _pending[i];
      final double absSample = sample < 0 ? -sample : sample;
      if (absSample > inputPeak) {
        inputPeak = absSample;
      }
      _re[i] = sample * _window[i];
      _im[i] = 0;
    }
    _fft(_re, _im, false);

    final int bins = fftSize ~/ 2;
    double voice = 0;
    double hiss = 0;
    for (int bin = 0; bin <= bins; bin++) {
      final double mag = math.sqrt(
        _re[bin] * _re[bin] + _im[bin] * _im[bin],
      );
      _mag[bin] = mag;
      if (mag > 1e-8) {
        _phaseRe[bin] = _re[bin] / mag;
        _phaseIm[bin] = _im[bin] / mag;
      } else {
        _phaseRe[bin] = 1;
        _phaseIm[bin] = 0;
      }
      if (bin >= 3 && bin <= 54) {
        voice += mag;
      } else if (bin >= 64 && bin <= 120) {
        hiss += mag;
      }
    }

    final bool speech = inputPeak > 0.025 && voice > hiss * 1.8;
    if (!speech) {
      for (int bin = 0; bin <= bins; bin++) {
        _noise[bin] = _noise[bin] * 0.85 + _mag[bin] * 0.15;
      }
    }

    for (int bin = 0; bin <= bins; bin++) {
      final double power = _mag[bin] * _mag[bin];
      final double noisePower = _noise[bin] * _noise[bin];
      double binGain = power / (power + (2.4 * noisePower) + 1e-12);
      if (bin <= 2 || bin >= 58) {
        binGain *= 0.05;
      }
      if (!speech) {
        binGain = 0;
      }
      final double mag = _mag[bin] * binGain;
      _re[bin] = mag * _phaseRe[bin];
      _im[bin] = mag * _phaseIm[bin];
    }
    for (int bin = 1; bin < bins; bin++) {
      _re[fftSize - bin] = _re[bin];
      _im[fftSize - bin] = -_im[bin];
    }
    _im[0] = 0;
    _im[bins] = 0;
    _fft(_re, _im, true);

    double cleanedPeak = 0;
    for (int i = 0; i < fftSize; i++) {
      final double absSample = _re[i] < 0 ? -_re[i] : _re[i];
      if (absSample > cleanedPeak) {
        cleanedPeak = absSample;
      }
    }
    double desired = 0;
    if (speech && cleanedPeak > 0.008) {
      desired = (0.58 * micPercent / 100) / cleanedPeak;
      if (desired > 3) {
        desired = 3;
      }
    }
    if (desired > _gain) {
      _gain = desired;
    } else {
      _gain = (_gain + desired) * 0.5;
    }
    for (int i = 0; i < fftSize; i++) {
      _re[i] *= _gain;
    }

    final List<double> hopOut = List<double>.filled(hop, 0);
    for (int i = 0; i < hop; i++) {
      hopOut[i] = _overlap[i] + _re[i];
      _overlap[i] = _re[i + hop];
    }
    return hopOut;
  }

  Uint8List _toPcm(List<double> samples) {
    final Uint8List out = Uint8List(samples.length * 2);
    final ByteData output = ByteData.sublistView(out);
    for (int i = 0; i < samples.length; i++) {
      int sample = (samples[i] * 32767.0).round();
      if (sample > 32767) {
        sample = 32767;
      } else if (sample < -32768) {
        sample = -32768;
      }
      output.setInt16(i * 2, sample, Endian.little);
    }
    return out;
  }
}

Float64List _hann(int size) {
  final Float64List window = Float64List(size);
  for (int i = 0; i < size; i++) {
    window[i] = 0.5 * (1 - math.cos((2 * math.pi * i) / size));
  }
  return window;
}

void _fft(Float64List re, Float64List im, bool invert) {
  final int n = re.length;
  for (int i = 1, j = 0; i < n; i++) {
    int bit = n >> 1;
    for (; j & bit != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final double swapRe = re[i];
      re[i] = re[j];
      re[j] = swapRe;
      final double swapIm = im[i];
      im[i] = im[j];
      im[j] = swapIm;
    }
  }
  for (int length = 2; length <= n; length <<= 1) {
    final double angle = (invert ? 2 : -2) * math.pi / length;
    final double stepRe = math.cos(angle);
    final double stepIm = math.sin(angle);
    for (int i = 0; i < n; i += length) {
      double turnRe = 1;
      double turnIm = 0;
      final int half = length >> 1;
      for (int j = 0; j < half; j++) {
        final int even = i + j;
        final int odd = even + half;
        final double oddRe = re[odd] * turnRe - im[odd] * turnIm;
        final double oddIm = re[odd] * turnIm + im[odd] * turnRe;
        re[odd] = re[even] - oddRe;
        im[odd] = im[even] - oddIm;
        re[even] += oddRe;
        im[even] += oddIm;
        final double nextRe = turnRe * stepRe - turnIm * stepIm;
        turnIm = turnRe * stepIm + turnIm * stepRe;
        turnRe = nextRe;
      }
    }
  }
  if (invert) {
    for (int i = 0; i < n; i++) {
      re[i] /= n;
      im[i] /= n;
    }
  }
}
