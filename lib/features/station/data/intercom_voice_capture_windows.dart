import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'intercom_boxcar.dart';

typedef IntercomPcmCallback = void Function(Uint8List pcm);

/// Windows voice capture, matching the walkie-talkie page.
///
/// The page calls getUserMedia with echo cancellation, noise suppression, and
/// automatic gain. Those switches are not available on raw waveIn. This opens
/// the default microphone through the Windows voice pipeline, then averages
/// it down to 16 kHz the same way the page does.
class IntercomVoiceCaptureWindows {
  final IntercomBoxcar _boxcar = IntercomBoxcar();
  _Ole? _ole;
  Pointer<Void>? _enumerator;
  Pointer<Void>? _device;
  Pointer<Void>? _client;
  Pointer<Void>? _capture;
  Pointer<Pointer<Uint8>>? _dataOut;
  Pointer<Uint32>? _framesOut;
  Pointer<Uint32>? _flagsOut;
  Timer? _timer;
  IntercomPcmCallback? _onPcm;
  bool _comStarted = false;
  String? lastError;
  int _channels = 0;
  int _rate = 0;
  int _blockAlign = 0;
  int _bytesPerSample = 0;
  bool _isFloat = false;

  bool start(IntercomPcmCallback onPcm) {
    stop();
    lastError = null;
    if (!Platform.isWindows) {
      lastError = 'Voice capture only runs on Windows.';
      return false;
    }
    if (sizeOf<Guid>() != 16 || sizeOf<AudioClientProperties>() != 16) {
      debugPrint('Voice capture layout is wrong for this build.');
      return false;
    }
    final _Ole? ole = _Ole.open();
    if (ole == null) {
      return false;
    }
    _ole = ole;
    final int apartment = ole.coInitializeEx(nullptr, _apartmentThreaded);
    if (apartment < 0 && !_isChangedMode(apartment)) {
      _fail('CoInitializeEx', apartment);
      return false;
    }
    _comStarted = apartment >= 0;

    final Pointer<Guid> clsid = _guid(_mmDeviceEnumerator);
    final Pointer<Guid> enumIid = _guid(_immDeviceEnumerator);
    final Pointer<Pointer<Void>> enumeratorOut = calloc<Pointer<Void>>();
    final int created = ole.coCreateInstance(
      clsid,
      nullptr,
      _clsctxAll,
      enumIid,
      enumeratorOut,
    );
    calloc.free(clsid);
    calloc.free(enumIid);
    if (created < 0 || enumeratorOut.value == nullptr) {
      calloc.free(enumeratorOut);
      _fail('CoCreateInstance', created);
      return false;
    }
    _enumerator = enumeratorOut.value;
    calloc.free(enumeratorOut);

    final Pointer<Pointer<Void>> deviceOut = calloc<Pointer<Void>>();
    final int deviceHr = _getDefaultEndpoint(_enumerator!, deviceOut);
    if (deviceHr < 0 || deviceOut.value == nullptr) {
      calloc.free(deviceOut);
      _fail('GetDefaultAudioEndpoint', deviceHr);
      return false;
    }
    _device = deviceOut.value;
    calloc.free(deviceOut);

    final Pointer<Guid> clientIid = _guid(_audioClient2);
    final Pointer<Pointer<Void>> clientOut = calloc<Pointer<Void>>();
    final int activated = _activate(_device!, clientIid, clientOut);
    calloc.free(clientIid);
    if (activated < 0 || clientOut.value == nullptr) {
      calloc.free(clientOut);
      _fail('Activate', activated);
      return false;
    }
    _client = clientOut.value;
    calloc.free(clientOut);

    final Pointer<AudioClientProperties> props =
        calloc<AudioClientProperties>();
    props.ref
      ..cbSize = sizeOf<AudioClientProperties>()
      ..isOffload = 0
      ..category = _categoryCommunications
      ..options = 0;
    final int propsHr = _setClientProperties(_client!, props);
    calloc.free(props);
    if (propsHr < 0) {
      debugPrint(
        'Voice processing was not enabled (${propsHr.toRadixString(16)}).',
      );
    }

    final Pointer<Pointer<Uint8>> mixOut = calloc<Pointer<Uint8>>();
    final int mixHr = _getMixFormat(_client!, mixOut);
    final Pointer<Uint8> mix = mixOut.value;
    calloc.free(mixOut);
    if (mixHr < 0 || mix == nullptr) {
      if (mix != nullptr) {
        ole.coTaskMemFree(mix.cast<Void>());
      }
      _fail('GetMixFormat', mixHr);
      return false;
    }
    final _MixFormat? format = _MixFormat.read(mix);
    if (format == null) {
      ole.coTaskMemFree(mix.cast<Void>());
      _fail('GetMixFormat', -1);
      return false;
    }
    final int initHr = _initialize(_client!, mix, 2000000);
    ole.coTaskMemFree(mix.cast<Void>());
    if (initHr < 0) {
      _fail('Initialize', initHr);
      return false;
    }
    _channels = format.channels;
    _rate = format.rate;
    _blockAlign = format.blockAlign;
    _bytesPerSample = format.bytesPerSample;
    _isFloat = format.isFloat;

    final Pointer<Guid> captureIid = _guid(_audioCaptureClient);
    final Pointer<Pointer<Void>> captureOut = calloc<Pointer<Void>>();
    final int serviceHr = _getService(_client!, captureIid, captureOut);
    calloc.free(captureIid);
    if (serviceHr < 0 || captureOut.value == nullptr) {
      calloc.free(captureOut);
      _fail('GetService', serviceHr);
      return false;
    }
    _capture = captureOut.value;
    calloc.free(captureOut);

    _dataOut = calloc<Pointer<Uint8>>();
    _framesOut = calloc<Uint32>();
    _flagsOut = calloc<Uint32>();
    final int started = _start(_client!);
    if (started < 0) {
      _fail('Start', started);
      return false;
    }
    _onPcm = onPcm;
    _timer = Timer.periodic(const Duration(milliseconds: 10), (_) => _poll());
    return true;
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _onPcm = null;
    _boxcar.reset();
    final Pointer<Void>? client = _client;
    if (client != null) {
      _stopClient(client);
    }
    _release(_capture);
    _capture = null;
    _release(_client);
    _client = null;
    _release(_device);
    _device = null;
    _release(_enumerator);
    _enumerator = null;
    final Pointer<Pointer<Uint8>>? dataOut = _dataOut;
    _dataOut = null;
    if (dataOut != null) {
      calloc.free(dataOut);
    }
    final Pointer<Uint32>? framesOut = _framesOut;
    _framesOut = null;
    if (framesOut != null) {
      calloc.free(framesOut);
    }
    final Pointer<Uint32>? flagsOut = _flagsOut;
    _flagsOut = null;
    if (flagsOut != null) {
      calloc.free(flagsOut);
    }
    if (_comStarted) {
      _ole?.coUninitialize();
      _comStarted = false;
    }
    _channels = 0;
    _rate = 0;
    _blockAlign = 0;
    _bytesPerSample = 0;
    _isFloat = false;
  }

  void _poll() {
    final IntercomPcmCallback? onPcm = _onPcm;
    final Pointer<Void>? capture = _capture;
    final Pointer<Pointer<Uint8>>? dataOut = _dataOut;
    final Pointer<Uint32>? framesOut = _framesOut;
    final Pointer<Uint32>? flagsOut = _flagsOut;
    if (onPcm == null ||
        capture == null ||
        dataOut == null ||
        framesOut == null ||
        flagsOut == null ||
        _rate <= 0) {
      return;
    }
    for (int packet = 0; packet < 32; packet++) {
      final int sizeHr = _nextPacketSize(capture, framesOut);
      if (sizeHr < 0 || framesOut.value == 0) {
        break;
      }
      final int readHr = _getBuffer(capture, dataOut, framesOut, flagsOut);
      final int frames = framesOut.value;
      if (readHr < 0 || frames == 0) {
        if (frames > 0) {
          _releaseBuffer(capture, frames);
        }
        break;
      }
      final bool silent = (flagsOut.value & _bufferSilent) != 0;
      final Float64List mono = _toMono(
        silent ? nullptr : dataOut.value,
        frames,
      );
      _releaseBuffer(capture, frames);
      _boxcar.add(mono, _rate);
      Uint8List? chunk = _boxcar.takeChunk(320);
      while (chunk != null) {
        onPcm(chunk);
        chunk = _boxcar.takeChunk(320);
      }
    }
  }

  Float64List _toMono(Pointer<Uint8> data, int frames) {
    final Float64List mono = Float64List(frames);
    if (data == nullptr || _channels <= 0 || _bytesPerSample <= 0) {
      return mono;
    }
    final int bytes = frames * _blockAlign;
    final ByteData view = ByteData.sublistView(data.asTypedList(bytes));
    for (int frame = 0; frame < frames; frame++) {
      double sum = 0;
      for (int channel = 0; channel < _channels; channel++) {
        final int offset = frame * _blockAlign + channel * _bytesPerSample;
        if (_isFloat && _bytesPerSample == 4) {
          sum += view.getFloat32(offset, Endian.little);
        } else if (_bytesPerSample == 2) {
          sum += view.getInt16(offset, Endian.little) / 32768.0;
        } else if (_bytesPerSample == 4) {
          sum += view.getInt32(offset, Endian.little) / 2147483648.0;
        }
      }
      mono[frame] = sum / _channels;
    }
    return mono;
  }

  void _fail(String step, int hr) {
    lastError = '$step failed (${hr.toRadixString(16)}).';
    debugPrint('Voice capture $lastError');
    stop();
  }

  static bool _isChangedMode(int hr) => (hr & 0xFFFFFFFF) == 0x80010106;
}

class _MixFormat {
  const _MixFormat({
    required this.channels,
    required this.rate,
    required this.blockAlign,
    required this.bytesPerSample,
    required this.isFloat,
  });

  final int channels;
  final int rate;
  final int blockAlign;
  final int bytesPerSample;
  final bool isFloat;

  static _MixFormat? read(Pointer<Uint8> mix) {
    final ByteData head = ByteData.sublistView(mix.asTypedList(18));
    final int tag = head.getUint16(0, Endian.little);
    final int channels = head.getUint16(2, Endian.little);
    final int rate = head.getUint32(4, Endian.little);
    final int blockAlign = head.getUint16(12, Endian.little);
    final int bits = head.getUint16(14, Endian.little);
    final int extra = head.getUint16(16, Endian.little);
    final int tail = extra > 64 ? 64 : extra;
    if (channels < 1 || channels > 8 || rate < 8000 || blockAlign < channels) {
      return null;
    }
    final int bytes = blockAlign ~/ channels;
    if (bytes != 2 && bytes != 4) {
      return null;
    }
    bool isFloat = tag == 3;
    if (tag == 0xFFFE && tail >= 22) {
      final ByteData full = ByteData.sublistView(mix.asTypedList(18 + tail));
      final int subtype = full.getUint32(24, Endian.little);
      isFloat = subtype == 3;
      if (subtype != 1 && subtype != 3) {
        return null;
      }
    } else if (tag != 1 && tag != 3) {
      return null;
    }
    if ((isFloat && bits != 32) || (!isFloat && bits != 16 && bits != 32)) {
      return null;
    }
    return _MixFormat(
      channels: channels,
      rate: rate,
      blockAlign: blockAlign,
      bytesPerSample: bytes,
      isFloat: isFloat,
    );
  }
}

final class Guid extends Struct {
  @Uint32()
  external int data1;

  @Uint16()
  external int data2;

  @Uint16()
  external int data3;

  @Array(8)
  external Array<Uint8> data4;
}

final class AudioClientProperties extends Struct {
  @Uint32()
  external int cbSize;

  @Int32()
  external int isOffload;

  @Int32()
  external int category;

  @Int32()
  external int options;
}

Pointer<Guid> _guid(List<int> bytes) {
  final Pointer<Guid> guid = calloc<Guid>();
  guid.ref.data1 =
      bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24);
  guid.ref.data2 = bytes[4] | (bytes[5] << 8);
  guid.ref.data3 = bytes[6] | (bytes[7] << 8);
  for (int i = 0; i < 8; i++) {
    guid.ref.data4[i] = bytes[8 + i];
  }
  return guid;
}

const int _apartmentThreaded = 2;
const int _clsctxAll = 23;
const int _categoryCommunications = 3;
const int _bufferSilent = 2;

const List<int> _mmDeviceEnumerator = <int>[
  0x95, 0x03, 0xDE, 0xBC, 0x2F, 0xE5, 0x7C, 0x46, //
  0x8E, 0x3D, 0xC4, 0x57, 0x92, 0x91, 0x69, 0x2E,
];
const List<int> _immDeviceEnumerator = <int>[
  0xD2, 0x64, 0x56, 0xA9, 0x14, 0x96, 0x35, 0x4F, //
  0xA7, 0x46, 0xDE, 0x8D, 0xB6, 0x36, 0x17, 0xE6,
];
const List<int> _audioClient2 = <int>[
  0xCD, 0x78, 0x67, 0x72, 0x0A, 0xF6, 0xDA, 0x4E, //
  0x82, 0xDE, 0xE4, 0x76, 0x10, 0xCD, 0x78, 0xAA,
];
const List<int> _audioCaptureClient = <int>[
  0x64, 0xBD, 0xAD, 0xC8, 0x1E, 0xE7, 0xA0, 0x48, //
  0xA4, 0xDE, 0x18, 0x5C, 0x39, 0x5C, 0xD3, 0x17,
];

class _Ole {
  _Ole(DynamicLibrary library)
    : coInitializeEx = library
          .lookupFunction<
            Int32 Function(Pointer<Void>, Uint32),
            int Function(Pointer<Void>, int)
          >('CoInitializeEx'),
      coUninitialize = library.lookupFunction<Void Function(), void Function()>(
        'CoUninitialize',
      ),
      coCreateInstance = library
          .lookupFunction<
            Int32 Function(
              Pointer<Guid>,
              Pointer<Void>,
              Uint32,
              Pointer<Guid>,
              Pointer<Pointer<Void>>,
            ),
            int Function(
              Pointer<Guid>,
              Pointer<Void>,
              int,
              Pointer<Guid>,
              Pointer<Pointer<Void>>,
            )
          >('CoCreateInstance'),
      coTaskMemFree = library
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('CoTaskMemFree');

  final int Function(Pointer<Void>, int) coInitializeEx;
  final void Function() coUninitialize;
  final int Function(
    Pointer<Guid>,
    Pointer<Void>,
    int,
    Pointer<Guid>,
    Pointer<Pointer<Void>>,
  )
  coCreateInstance;
  final void Function(Pointer<Void>) coTaskMemFree;

  static _Ole? open() {
    try {
      return _Ole(DynamicLibrary.open('ole32.dll'));
    } catch (error) {
      debugPrint('ole32.dll did not open. $error');
      return null;
    }
  }
}

Pointer<Void> _slot(Pointer<Void> object, int index) {
  final Pointer<Pointer<Void>> table = object
      .cast<Pointer<Pointer<Void>>>()
      .value;
  return table[index];
}

void _release(Pointer<Void>? object) {
  if (object == null || object == nullptr) {
    return;
  }
  _slot(object, 2)
      .cast<NativeFunction<Uint32 Function(Pointer<Void>)>>()
      .asFunction<int Function(Pointer<Void>)>()(object);
}

int _getDefaultEndpoint(Pointer<Void> enumerator, Pointer<Pointer<Void>> out) {
  return _slot(enumerator, 4)
      .cast<
        NativeFunction<
          Int32 Function(Pointer<Void>, Int32, Int32, Pointer<Pointer<Void>>)
        >
      >()
      .asFunction<
        int Function(Pointer<Void>, int, int, Pointer<Pointer<Void>>)
      >()(enumerator, 1, 0, out);
}

int _activate(
  Pointer<Void> device,
  Pointer<Guid> iid,
  Pointer<Pointer<Void>> out,
) {
  return _slot(device, 3)
      .cast<
        NativeFunction<
          Int32 Function(
            Pointer<Void>,
            Pointer<Guid>,
            Uint32,
            Pointer<Void>,
            Pointer<Pointer<Void>>,
          )
        >
      >()
      .asFunction<
        int Function(
          Pointer<Void>,
          Pointer<Guid>,
          int,
          Pointer<Void>,
          Pointer<Pointer<Void>>,
        )
      >()(device, iid, _clsctxAll, nullptr, out);
}

int _setClientProperties(
  Pointer<Void> client,
  Pointer<AudioClientProperties> props,
) {
  return _slot(client, 16)
      .cast<
        NativeFunction<
          Int32 Function(Pointer<Void>, Pointer<AudioClientProperties>)
        >
      >()
      .asFunction<
        int Function(Pointer<Void>, Pointer<AudioClientProperties>)
      >()(client, props);
}

int _getMixFormat(Pointer<Void> client, Pointer<Pointer<Uint8>> out) {
  return _slot(client, 8)
      .cast<
        NativeFunction<Int32 Function(Pointer<Void>, Pointer<Pointer<Uint8>>)>
      >()
      .asFunction<int Function(Pointer<Void>, Pointer<Pointer<Uint8>>)>()(
    client,
    out,
  );
}

int _initialize(Pointer<Void> client, Pointer<Uint8> format, int bufferHns) {
  return _slot(client, 3)
      .cast<
        NativeFunction<
          Int32 Function(
            Pointer<Void>,
            Int32,
            Uint32,
            Int64,
            Int64,
            Pointer<Uint8>,
            Pointer<Uint8>,
          )
        >
      >()
      .asFunction<
        int Function(
          Pointer<Void>,
          int,
          int,
          int,
          int,
          Pointer<Uint8>,
          Pointer<Uint8>,
        )
      >()(client, 0, 0, bufferHns, 0, format, nullptr);
}

int _getService(
  Pointer<Void> client,
  Pointer<Guid> iid,
  Pointer<Pointer<Void>> out,
) {
  return _slot(client, 14)
      .cast<
        NativeFunction<
          Int32 Function(Pointer<Void>, Pointer<Guid>, Pointer<Pointer<Void>>)
        >
      >()
      .asFunction<
        int Function(Pointer<Void>, Pointer<Guid>, Pointer<Pointer<Void>>)
      >()(client, iid, out);
}

int _start(Pointer<Void> client) {
  return _slot(client, 10)
      .cast<NativeFunction<Int32 Function(Pointer<Void>)>>()
      .asFunction<int Function(Pointer<Void>)>()(client);
}

void _stopClient(Pointer<Void> client) {
  _slot(client, 11)
      .cast<NativeFunction<Int32 Function(Pointer<Void>)>>()
      .asFunction<int Function(Pointer<Void>)>()(client);
}

int _nextPacketSize(Pointer<Void> capture, Pointer<Uint32> frames) {
  return _slot(capture, 5)
      .cast<NativeFunction<Int32 Function(Pointer<Void>, Pointer<Uint32>)>>()
      .asFunction<int Function(Pointer<Void>, Pointer<Uint32>)>()(
    capture,
    frames,
  );
}

int _getBuffer(
  Pointer<Void> capture,
  Pointer<Pointer<Uint8>> data,
  Pointer<Uint32> frames,
  Pointer<Uint32> flags,
) {
  return _slot(capture, 3)
      .cast<
        NativeFunction<
          Int32 Function(
            Pointer<Void>,
            Pointer<Pointer<Uint8>>,
            Pointer<Uint32>,
            Pointer<Uint32>,
            Pointer<Uint64>,
            Pointer<Uint64>,
          )
        >
      >()
      .asFunction<
        int Function(
          Pointer<Void>,
          Pointer<Pointer<Uint8>>,
          Pointer<Uint32>,
          Pointer<Uint32>,
          Pointer<Uint64>,
          Pointer<Uint64>,
        )
      >()(capture, data, frames, flags, nullptr, nullptr);
}

void _releaseBuffer(Pointer<Void> capture, int frames) {
  _slot(capture, 4)
      .cast<NativeFunction<Int32 Function(Pointer<Void>, Uint32)>>()
      .asFunction<int Function(Pointer<Void>, int)>()(capture, frames);
}
