import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../../core/constants.dart';

typedef SocketBytesCallback = void Function(Uint8List data);
typedef SocketErrorCallback = void Function(Object error);
typedef SocketDoneCallback = void Function();

class DispenserSocketClient {
  Socket? _socket;
  StreamSubscription<Uint8List>? _subscription;
  bool _closing = false;

  bool get isConnected => _socket != null;

  Future<void> connect({
    required String host,
    required int port,
    required SocketBytesCallback onData,
    required SocketErrorCallback onError,
    required SocketDoneCallback onDone,
    Duration timeout = FdxDefaults.connectTimeout,
  }) async {
    await disconnect();
    final Socket socket = await Socket.connect(host, port, timeout: timeout);
    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}
    _socket = socket;
    _subscription = socket.listen(
      onData,
      onError: (Object error, StackTrace _) {
        onError(error);
        unawaited(disconnect());
      },
      onDone: () {
        onDone();
        unawaited(disconnect());
      },
      cancelOnError: true,
    );
  }

  void send(List<int> bytes) {
    final Socket? socket = _socket;
    if (socket == null) {
      throw const SocketException('Not connected');
    }
    socket.add(bytes);
  }

  Future<void> disconnect() async {
    if (_closing) {
      return;
    }
    _closing = true;
    try {
      await _subscription?.cancel();
      _subscription = null;
      final Socket? socket = _socket;
      _socket = null;
      if (socket != null) {
        try {
          await socket.close();
        } catch (_) {}
        try {
          socket.destroy();
        } catch (_) {}
      }
    } finally {
      _closing = false;
    }
  }
}
