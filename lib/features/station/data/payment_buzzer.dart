import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Plays a looping piezo-style WAV through the Windows sound card.
///
/// `kernel32 Beep()` is silent on most modern PCs (no motherboard speaker).
/// `winmm PlaySound` uses the default playback device instead.
class PaymentBuzzer {
  static const int _sndAsync = 0x0001;
  static const int _sndNoDefault = 0x0002;
  static const int _sndLoop = 0x0008;
  static const int _sndFilename = 0x00020000;

  int Function(Pointer<Utf16> sound, Pointer<Void> module, int flags)? _play;
  Pointer<Utf16>? _pathPtr;
  String? _wavPath;
  bool _wanted = false;

  Future<void> start() async {
    _wanted = true;
    if (!Platform.isWindows || _pathPtr != null) {
      return;
    }
    _play ??= _loadPlaySound();
    final int Function(Pointer<Utf16>, Pointer<Void>, int)? play = _play;
    if (play == null) {
      return;
    }
    final String path = await _ensureWavFile();
    if (!_wanted) {
      return;
    }
    final Pointer<Utf16> pathPtr = path.toNativeUtf16();
    _pathPtr = pathPtr;
    final int ok = play(
      pathPtr,
      nullptr,
      _sndAsync | _sndLoop | _sndFilename | _sndNoDefault,
    );
    if (ok == 0) {
      calloc.free(pathPtr);
      _pathPtr = null;
    }
  }

  void stop() {
    _wanted = false;
    final int Function(Pointer<Utf16>, Pointer<Void>, int)? play = _play;
    if (play != null) {
      play(nullptr.cast<Utf16>(), nullptr, 0);
    }
    final Pointer<Utf16>? pathPtr = _pathPtr;
    if (pathPtr != null) {
      calloc.free(pathPtr);
      _pathPtr = null;
    }
  }

  void dispose() {
    stop();
  }

  static int Function(Pointer<Utf16>, Pointer<Void>, int)? _loadPlaySound() {
    try {
      return DynamicLibrary.open('winmm.dll').lookupFunction<
        Int32 Function(Pointer<Utf16>, Pointer<Void>, Uint32),
        int Function(Pointer<Utf16>, Pointer<Void>, int)
      >('PlaySoundW');
    } catch (_) {
      return null;
    }
  }

  Future<String> _ensureWavFile() async {
    final String? existing = _wavPath;
    if (existing != null && File(existing).existsSync()) {
      return existing;
    }
    final File file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}dispensr_bay_buzzer_v012.wav',
    );
    await file.writeAsBytes(_buildBuzzerWav(), flush: true);
    _wavPath = file.path;
    return file.path;
  }

  /// Double chirp + pause, sized to loop as an attendant-call piezo.
  static Uint8List _buildBuzzerWav() {
    const int sampleRate = 22050;
    const int freqHz = 2200;
    const double volume = 0.12;
    final int peak = (32767 * volume).round();
    final List<int> pcm = <int>[];

    void appendTone({required int milliseconds, required bool audible}) {
      final int count = (sampleRate * milliseconds / 1000).round();
      final int period = (sampleRate / freqHz).round().clamp(2, sampleRate);
      final int half = period ~/ 2;
      for (int i = 0; i < count; i++) {
        if (!audible) {
          pcm.add(0);
          continue;
        }
        pcm.add((i % period) < half ? peak : -peak);
      }
    }

    appendTone(milliseconds: 140, audible: true);
    appendTone(milliseconds: 90, audible: false);
    appendTone(milliseconds: 140, audible: true);
    appendTone(milliseconds: 480, audible: false);

    final int dataBytes = pcm.length * 2;
    final BytesBuilder out = BytesBuilder(copy: false);
    void u16(int value) {
      out.addByte(value & 0xFF);
      out.addByte((value >> 8) & 0xFF);
    }

    void u32(int value) {
      out.addByte(value & 0xFF);
      out.addByte((value >> 8) & 0xFF);
      out.addByte((value >> 16) & 0xFF);
      out.addByte((value >> 24) & 0xFF);
    }

    out.add('RIFF'.codeUnits);
    u32(36 + dataBytes);
    out.add('WAVE'.codeUnits);
    out.add('fmt '.codeUnits);
    u32(16);
    u16(1);
    u16(1);
    u32(sampleRate);
    u32(sampleRate * 2);
    u16(2);
    u16(16);
    out.add('data'.codeUnits);
    u32(dataBytes);
    for (final int sample in pcm) {
      u16(sample & 0xFFFF);
    }
    return Uint8List.fromList(out.takeBytes());
  }
}
