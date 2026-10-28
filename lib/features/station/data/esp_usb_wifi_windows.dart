import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'wifi_status.dart';

/// Talks to a FuelPoint board on a Windows COM port.
/// Opening the port restarts the board, then the network line is sent.
class EspUsbWifi {
  static Future<List<String>> listPorts() {
    return Isolate.run(_listPorts);
  }

  static Future<DispenserWifiStatus> send({
    required String portName,
    required String ssid,
    required String password,
  }) {
    return Isolate.run(
      () => _send(portName: portName, ssid: ssid, password: password),
    );
  }
}

List<String> _listPorts() {
  final _Kernel32 kernel = _Kernel32.load();
  final List<String> found = <String>[];
  for (int number = 1; number <= 40; number++) {
    if (kernel.portExists('COM$number')) {
      found.add('COM$number');
    }
  }
  return found;
}

DispenserWifiStatus _send({
  required String portName,
  required String ssid,
  required String password,
}) {
  final _Kernel32 kernel = _Kernel32.load();
  final int handle = kernel.open(portName);
  if (handle == -1) {
    throw EspUsbWifiException(
      'Could not open $portName. Close the Arduino serial monitor and try again.',
    );
  }
  try {
    kernel.configure(handle);
    kernel.purge(handle);
    // The ESP32 restarts when the port opens. Wait until it is listening.
    sleep(const Duration(milliseconds: 2500));
    kernel.purge(handle);
    final String line =
        '{"cmd":"SET_WIFI","ssid":${_quoted(ssid)},"pass":${_quoted(password)}}\n';
    kernel.writeText(handle, line);
    final String reply = kernel.readUntil(
      handle,
      marker: '"cmd":"WIFI_STATUS"',
      wantAddress: true,
      timeout: const Duration(seconds: 20),
    );
    final int start = reply.lastIndexOf('{');
    final int end = reply.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const EspUsbWifiException(
        'The board did not join that network. Check the name and password.',
      );
    }
    final DispenserWifiStatus? status = tryParseWifiStatus(
      reply.substring(start, end + 1),
    );
    if (status == null || !status.hasAddress) {
      throw const EspUsbWifiException(
        'The board did not join that network. Check the name and password.',
      );
    }
    return status;
  } finally {
    kernel.close(handle);
  }
}

String _quoted(String value) {
  final String escaped = value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
  return '"$escaped"';
}

class EspUsbWifiException implements Exception {
  const EspUsbWifiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _Kernel32 {
  _Kernel32(this._lib);

  final DynamicLibrary _lib;

  static _Kernel32 load() {
    return _Kernel32(DynamicLibrary.open('kernel32.dll'));
  }

  late final int Function(Pointer<Utf16>, Pointer<Utf16>, int)
  _queryDosDevice = _lib
      .lookup<
        NativeFunction<Uint32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32)>
      >('QueryDosDeviceW')
      .asFunction();

  late final int Function(
    Pointer<Utf16>,
    int,
    int,
    Pointer<Void>,
    int,
    int,
    int,
  )
  _createFile = _lib
      .lookup<
        NativeFunction<
          IntPtr Function(
            Pointer<Utf16>,
            Uint32,
            Uint32,
            Pointer<Void>,
            Uint32,
            Uint32,
            IntPtr,
          )
        >
      >('CreateFileW')
      .asFunction();

  late final int Function(int) _closeHandle = _lib
      .lookup<NativeFunction<Int32 Function(IntPtr)>>('CloseHandle')
      .asFunction();

  late final int Function(int, Pointer<Uint8>) _getCommState = _lib
      .lookup<NativeFunction<Int32 Function(IntPtr, Pointer<Uint8>)>>(
        'GetCommState',
      )
      .asFunction();

  late final int Function(int, Pointer<Uint8>) _setCommState = _lib
      .lookup<NativeFunction<Int32 Function(IntPtr, Pointer<Uint8>)>>(
        'SetCommState',
      )
      .asFunction();

  late final int Function(int, Pointer<Uint32>) _setTimeouts = _lib
      .lookup<NativeFunction<Int32 Function(IntPtr, Pointer<Uint32>)>>(
        'SetCommTimeouts',
      )
      .asFunction();

  late final int Function(int, int) _purge = _lib
      .lookup<NativeFunction<Int32 Function(IntPtr, Uint32)>>('PurgeComm')
      .asFunction();

  late final int Function(int, int) _escape = _lib
      .lookup<NativeFunction<Int32 Function(IntPtr, Uint32)>>(
        'EscapeCommFunction',
      )
      .asFunction();

  late final int Function(
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint32>,
    Pointer<Void>,
  )
  _writeFile = _lib
      .lookup<
        NativeFunction<
          Int32 Function(
            IntPtr,
            Pointer<Uint8>,
            Uint32,
            Pointer<Uint32>,
            Pointer<Void>,
          )
        >
      >('WriteFile')
      .asFunction();

  late final int Function(
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint32>,
    Pointer<Void>,
  )
  _readFile = _lib
      .lookup<
        NativeFunction<
          Int32 Function(
            IntPtr,
            Pointer<Uint8>,
            Uint32,
            Pointer<Uint32>,
            Pointer<Void>,
          )
        >
      >('ReadFile')
      .asFunction();

  bool portExists(String portName) {
    final Pointer<Utf16> name = portName.toNativeUtf16();
    final Pointer<Utf16> path = malloc<Uint16>(256).cast<Utf16>();
    try {
      return _queryDosDevice(name, path, 256) > 0;
    } finally {
      malloc.free(name);
      malloc.free(path);
    }
  }

  int open(String portName) {
    final Pointer<Utf16> name = '\\.\\$portName'.toNativeUtf16();
    try {
      return _createFile(name, 0xC0000000, 0, nullptr, 3, 0, 0);
    } finally {
      malloc.free(name);
    }
  }

  void close(int handle) {
    _closeHandle(handle);
  }

  void configure(int handle) {
    final Pointer<Uint8> dcb = malloc<Uint8>(28);
    final Pointer<Uint32> timeouts = malloc<Uint32>(5);
    try {
      for (int i = 0; i < 28; i++) {
        dcb[i] = 0;
      }
      dcb[0] = 28;
      if (_getCommState(handle, dcb) == 0) {
        throw const EspUsbWifiException('Could not read the serial port.');
      }
      dcb[4] = 115200 & 0xFF;
      dcb[5] = (115200 >> 8) & 0xFF;
      dcb[6] = (115200 >> 16) & 0xFF;
      dcb[7] = 0;
      dcb[18] = 8;
      dcb[19] = 0;
      dcb[20] = 0;
      if (_setCommState(handle, dcb) == 0) {
        throw const EspUsbWifiException('Could not set 115200 baud.');
      }
      timeouts[0] = 50;
      timeouts[1] = 0;
      timeouts[2] = 200;
      timeouts[3] = 0;
      timeouts[4] = 1000;
      _setTimeouts(handle, timeouts);
      _escape(handle, 6);
      _escape(handle, 4);
    } finally {
      malloc.free(dcb);
      malloc.free(timeouts);
    }
  }

  void purge(int handle) {
    _purge(handle, 0x000F);
  }

  void writeText(int handle, String text) {
    final List<int> bytes = text.codeUnits;
    final Pointer<Uint8> buffer = malloc<Uint8>(bytes.length);
    final Pointer<Uint32> written = malloc<Uint32>();
    try {
      for (int i = 0; i < bytes.length; i++) {
        buffer[i] = bytes[i];
      }
      final int ok = _writeFile(handle, buffer, bytes.length, written, nullptr);
      if (ok == 0 || written.value != bytes.length) {
        throw const EspUsbWifiException(
          'Could not send the network to the board.',
        );
      }
    } finally {
      malloc.free(buffer);
      malloc.free(written);
    }
  }

  String readUntil(
    int handle, {
    required String marker,
    required bool wantAddress,
    required Duration timeout,
  }) {
    final Pointer<Uint8> buffer = malloc<Uint8>(256);
    final Pointer<Uint32> read = malloc<Uint32>();
    final StringBuffer all = StringBuffer();
    final DateTime deadline = DateTime.now().add(timeout);
    try {
      while (DateTime.now().isBefore(deadline)) {
        read.value = 0;
        final int ok = _readFile(handle, buffer, 256, read, nullptr);
        if (ok == 0) {
          break;
        }
        if (read.value == 0) {
          continue;
        }
        for (int i = 0; i < read.value; i++) {
          all.writeCharCode(buffer[i]);
        }
        final String text = all.toString();
        if (!text.contains(marker)) {
          continue;
        }
        if (!wantAddress) {
          return text;
        }
        final int start = text.lastIndexOf(marker);
        final int brace = text.lastIndexOf('{', start);
        final int end = text.indexOf('}', start);
        if (brace < 0 || end < 0) {
          continue;
        }
        final DispenserWifiStatus? status = tryParseWifiStatus(
          text.substring(brace, end + 1),
        );
        if (status != null && status.hasAddress) {
          return text.substring(brace, end + 1);
        }
      }
      return all.toString();
    } finally {
      malloc.free(buffer);
      malloc.free(read);
    }
  }
}
