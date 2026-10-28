import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

typedef IntercomPcmCallback = void Function(Uint8List pcm);

/// 16 kHz 16-bit mono capture and playback through winmm.
///
/// Polls buffer-done flags so the audio driver never calls back into Dart.
class IntercomAudioWindows {
  static const int _pcmBytes = 640;
  static const int _waveMapper = 0xFFFFFFFF;
  static const int _whdrDone = 0x00000001;
  static const int _bufferCount = 8;

  final _Winmm? _winmm = _Winmm.load();
  final List<_PcmBuf> _capture = <_PcmBuf>[];
  final List<_PcmBuf> _playback = <_PcmBuf>[];

  Pointer<Void>? _inHandle;
  Pointer<Void>? _outHandle;
  Pointer<WaveFormatEx>? _format;
  Timer? _poll;
  IntercomPcmCallback? _onPcm;
  int _epoch = 0;
  int _playbackPercent = 85;

  bool startCapture(IntercomPcmCallback onPcm) {
    stopPlayback();
    stopCapture();
    if (!Platform.isWindows) {
      return false;
    }
    final _Winmm? winmm = _winmm;
    if (winmm == null || sizeOf<WaveHdr>() != 48) {
      debugPrint('intercom capture unavailable');
      return false;
    }
    final int epoch = ++_epoch;
    final Pointer<WaveFormatEx> format = _monoFormat();
    final Pointer<Pointer<Void>> opened = calloc<Pointer<Void>>();
    final int result = winmm.waveInOpen(opened, _waveMapper, format, 0, 0, 0);
    final Pointer<Void> handle = opened.value;
    calloc.free(opened);
    if (result != 0 || handle == nullptr) {
      calloc.free(format);
      debugPrint('waveInOpen failed ($result)');
      return false;
    }
    _format = format;
    _inHandle = handle;
    _onPcm = onPcm;
    for (int i = 0; i < _bufferCount; i++) {
      final _PcmBuf buf = _PcmBuf.allocate(winmm, handle, capture: true);
      if (!buf.prepared) {
        stopCapture();
        return false;
      }
      _capture.add(buf);
      winmm.waveInAddBuffer(handle, buf.header, sizeOf<WaveHdr>());
    }
    if (winmm.waveInStart(handle) != 0) {
      stopCapture();
      return false;
    }
    _poll = Timer.periodic(const Duration(milliseconds: 10), (_) {
      if (epoch != _epoch) {
        return;
      }
      _pollCapture();
    });
    return true;
  }

  void stopCapture() {
    _epoch++;
    _poll?.cancel();
    _poll = null;
    _onPcm = null;
    final _Winmm? winmm = _winmm;
    final Pointer<Void>? handle = _inHandle;
    _inHandle = null;
    if (winmm != null && handle != null) {
      winmm.waveInStop(handle);
      winmm.waveInReset(handle);
    }
    for (final _PcmBuf buf in _capture) {
      if (winmm != null && handle != null) {
        winmm.waveInUnprepare(handle, buf.header, sizeOf<WaveHdr>());
      }
      buf.free();
    }
    _capture.clear();
    if (winmm != null && handle != null) {
      winmm.waveInClose(handle);
    }
    final Pointer<WaveFormatEx>? format = _format;
    _format = null;
    if (format != null) {
      calloc.free(format);
    }
  }

  void startPlayback() {
    stopCapture();
    if (_outHandle != null || !Platform.isWindows) {
      return;
    }
    final _Winmm? winmm = _winmm;
    if (winmm == null || sizeOf<WaveHdr>() != 48) {
      return;
    }
    final Pointer<WaveFormatEx> format = _monoFormat();
    final Pointer<Pointer<Void>> opened = calloc<Pointer<Void>>();
    final int result = winmm.waveOutOpen(opened, _waveMapper, format, 0, 0, 0);
    final Pointer<Void> handle = opened.value;
    calloc.free(opened);
    if (result != 0 || handle == nullptr) {
      calloc.free(format);
      debugPrint('waveOutOpen failed ($result)');
      return;
    }
    _format = format;
    _outHandle = handle;
    for (int i = 0; i < _bufferCount; i++) {
      final _PcmBuf buf = _PcmBuf.allocate(winmm, handle, capture: false);
      if (!buf.prepared) {
        stopPlayback();
        return;
      }
      _playback.add(buf);
    }
    _applyPlaybackVolume();
  }

  /// 0–100. Applies immediately when helper playback is open.
  void setPlaybackVolume(int percent) {
    if (percent < 0) {
      _playbackPercent = 0;
    } else if (percent > 100) {
      _playbackPercent = 100;
    } else {
      _playbackPercent = percent;
    }
    _applyPlaybackVolume();
  }

  void _applyPlaybackVolume() {
    final _Winmm? winmm = _winmm;
    final Pointer<Void>? handle = _outHandle;
    if (winmm == null || handle == null) {
      return;
    }
    final int channel = (_playbackPercent * 0xFFFF) ~/ 100;
    final int packed = channel | (channel << 16);
    winmm.waveOutSetVolume(handle, packed);
  }

  void enqueuePlayback(Uint8List pcm) {
    final _Winmm? winmm = _winmm;
    final Pointer<Void>? handle = _outHandle;
    if (winmm == null || handle == null || pcm.isEmpty) {
      return;
    }
    _PcmBuf? free;
    for (final _PcmBuf buf in _playback) {
      if (!buf.inFlight || (buf.header.ref.dwFlags & _whdrDone) != 0) {
        buf.inFlight = false;
        free = buf;
        break;
      }
    }
    if (free == null) {
      return;
    }
    final Uint8List view = free.data.asTypedList(_pcmBytes);
    view.fillRange(0, _pcmBytes, 0);
    final int count = pcm.length < _pcmBytes ? pcm.length : _pcmBytes;
    view.setRange(0, count, pcm);
    free.header.ref.dwBufferLength = _pcmBytes;
    free.inFlight = true;
    winmm.waveOutWrite(handle, free.header, sizeOf<WaveHdr>());
  }

  void stopPlayback() {
    final _Winmm? winmm = _winmm;
    final Pointer<Void>? handle = _outHandle;
    _outHandle = null;
    if (winmm != null && handle != null) {
      winmm.waveOutReset(handle);
    }
    for (final _PcmBuf buf in _playback) {
      if (winmm != null && handle != null) {
        winmm.waveOutUnprepare(handle, buf.header, sizeOf<WaveHdr>());
      }
      buf.free();
    }
    _playback.clear();
    if (winmm != null && handle != null) {
      winmm.waveOutClose(handle);
    }
    if (_inHandle == null) {
      final Pointer<WaveFormatEx>? format = _format;
      _format = null;
      if (format != null) {
        calloc.free(format);
      }
    }
  }

  void dispose() {
    stopCapture();
    stopPlayback();
  }

  void _pollCapture() {
    final IntercomPcmCallback? onPcm = _onPcm;
    final _Winmm? winmm = _winmm;
    final Pointer<Void>? handle = _inHandle;
    if (onPcm == null || winmm == null || handle == null) {
      return;
    }
    for (final _PcmBuf buf in _capture) {
      if ((buf.header.ref.dwFlags & _whdrDone) == 0) {
        continue;
      }
      final int recorded = buf.header.ref.dwBytesRecorded;
      if (recorded > 0) {
        final int count = recorded < _pcmBytes ? recorded : _pcmBytes;
        final Uint8List pcm = Uint8List.fromList(buf.data.asTypedList(count));
        onPcm(pcm);
      }
      buf.header.ref.dwFlags = buf.header.ref.dwFlags & ~_whdrDone;
      winmm.waveInAddBuffer(handle, buf.header, sizeOf<WaveHdr>());
    }
  }

  Pointer<WaveFormatEx> _monoFormat() {
    final Pointer<WaveFormatEx> format = calloc<WaveFormatEx>();
    format.ref
      ..wFormatTag = 1
      ..nChannels = 1
      ..nSamplesPerSec = 16000
      ..nAvgBytesPerSec = 32000
      ..nBlockAlign = 2
      ..wBitsPerSample = 16
      ..cbSize = 0;
    return format;
  }
}

final class WaveFormatEx extends Struct {
  @Uint16()
  external int wFormatTag;

  @Uint16()
  external int nChannels;

  @Uint32()
  external int nSamplesPerSec;

  @Uint32()
  external int nAvgBytesPerSec;

  @Uint16()
  external int nBlockAlign;

  @Uint16()
  external int wBitsPerSample;

  @Uint16()
  external int cbSize;
}

final class WaveHdr extends Struct {
  external Pointer<Uint8> lpData;

  @Uint32()
  external int dwBufferLength;

  @Uint32()
  external int dwBytesRecorded;

  @Uint64()
  external int dwUser;

  @Uint32()
  external int dwFlags;

  @Uint32()
  external int dwLoops;

  external Pointer<Uint8> lpNext;

  @Uint64()
  external int reserved;
}

class _PcmBuf {
  _PcmBuf(this.data, this.header, {required this.prepared});

  final Pointer<Uint8> data;
  final Pointer<WaveHdr> header;
  final bool prepared;
  bool inFlight = false;

  static _PcmBuf allocate(
    _Winmm winmm,
    Pointer<Void> handle, {
    required bool capture,
  }) {
    final Pointer<Uint8> data = calloc<Uint8>(IntercomAudioWindows._pcmBytes);
    final Pointer<WaveHdr> header = calloc<WaveHdr>();
    header.ref
      ..lpData = data
      ..dwBufferLength = IntercomAudioWindows._pcmBytes
      ..dwBytesRecorded = 0
      ..dwUser = 0
      ..dwFlags = 0
      ..dwLoops = 0
      ..lpNext = nullptr
      ..reserved = 0;
    final int prepared = capture
        ? winmm.waveInPrepare(handle, header, sizeOf<WaveHdr>())
        : winmm.waveOutPrepare(handle, header, sizeOf<WaveHdr>());
    return _PcmBuf(data, header, prepared: prepared == 0);
  }

  void free() {
    calloc.free(header);
    calloc.free(data);
  }
}

class _Winmm {
  _Winmm(DynamicLibrary library)
    : waveInOpen = library
          .lookup<
            NativeFunction<
              Int32 Function(
                Pointer<Pointer<Void>>,
                Uint32,
                Pointer<WaveFormatEx>,
                Uint64,
                Uint64,
                Uint32,
              )
            >
          >('waveInOpen')
          .asFunction(),
      waveInPrepare = library
          .lookup<
            NativeFunction<
              Int32 Function(Pointer<Void>, Pointer<WaveHdr>, Uint32)
            >
          >('waveInPrepareHeader')
          .asFunction(),
      waveInUnprepare = library
          .lookup<
            NativeFunction<
              Int32 Function(Pointer<Void>, Pointer<WaveHdr>, Uint32)
            >
          >('waveInUnprepareHeader')
          .asFunction(),
      waveInAddBuffer = library
          .lookup<
            NativeFunction<
              Int32 Function(Pointer<Void>, Pointer<WaveHdr>, Uint32)
            >
          >('waveInAddBuffer')
          .asFunction(),
      waveInStart = library
          .lookup<NativeFunction<Int32 Function(Pointer<Void>)>>('waveInStart')
          .asFunction(),
      waveInStop = library
          .lookup<NativeFunction<Int32 Function(Pointer<Void>)>>('waveInStop')
          .asFunction(),
      waveInReset = library
          .lookup<NativeFunction<Int32 Function(Pointer<Void>)>>('waveInReset')
          .asFunction(),
      waveInClose = library
          .lookup<NativeFunction<Int32 Function(Pointer<Void>)>>('waveInClose')
          .asFunction(),
      waveOutOpen = library
          .lookup<
            NativeFunction<
              Int32 Function(
                Pointer<Pointer<Void>>,
                Uint32,
                Pointer<WaveFormatEx>,
                Uint64,
                Uint64,
                Uint32,
              )
            >
          >('waveOutOpen')
          .asFunction(),
      waveOutPrepare = library
          .lookup<
            NativeFunction<
              Int32 Function(Pointer<Void>, Pointer<WaveHdr>, Uint32)
            >
          >('waveOutPrepareHeader')
          .asFunction(),
      waveOutUnprepare = library
          .lookup<
            NativeFunction<
              Int32 Function(Pointer<Void>, Pointer<WaveHdr>, Uint32)
            >
          >('waveOutUnprepareHeader')
          .asFunction(),
      waveOutWrite = library
          .lookup<
            NativeFunction<
              Int32 Function(Pointer<Void>, Pointer<WaveHdr>, Uint32)
            >
          >('waveOutWrite')
          .asFunction(),
      waveOutReset = library
          .lookup<NativeFunction<Int32 Function(Pointer<Void>)>>('waveOutReset')
          .asFunction(),
      waveOutClose = library
          .lookup<NativeFunction<Int32 Function(Pointer<Void>)>>('waveOutClose')
          .asFunction(),
      waveOutSetVolume = library
          .lookup<NativeFunction<Int32 Function(Pointer<Void>, Uint32)>>(
            'waveOutSetVolume',
          )
          .asFunction();

  final int Function(
    Pointer<Pointer<Void>>,
    int,
    Pointer<WaveFormatEx>,
    int,
    int,
    int,
  )
  waveInOpen;
  final int Function(Pointer<Void>, Pointer<WaveHdr>, int) waveInPrepare;
  final int Function(Pointer<Void>, Pointer<WaveHdr>, int) waveInUnprepare;
  final int Function(Pointer<Void>, Pointer<WaveHdr>, int) waveInAddBuffer;
  final int Function(Pointer<Void>) waveInStart;
  final int Function(Pointer<Void>) waveInStop;
  final int Function(Pointer<Void>) waveInReset;
  final int Function(Pointer<Void>) waveInClose;
  final int Function(
    Pointer<Pointer<Void>>,
    int,
    Pointer<WaveFormatEx>,
    int,
    int,
    int,
  )
  waveOutOpen;
  final int Function(Pointer<Void>, Pointer<WaveHdr>, int) waveOutPrepare;
  final int Function(Pointer<Void>, Pointer<WaveHdr>, int) waveOutUnprepare;
  final int Function(Pointer<Void>, Pointer<WaveHdr>, int) waveOutWrite;
  final int Function(Pointer<Void>) waveOutReset;
  final int Function(Pointer<Void>) waveOutClose;
  final int Function(Pointer<Void>, int) waveOutSetVolume;

  static _Winmm? load() {
    if (!Platform.isWindows) {
      return null;
    }
    try {
      return _Winmm(DynamicLibrary.open('winmm.dll'));
    } catch (error) {
      debugPrint('winmm load failed: $error');
      return null;
    }
  }
}

