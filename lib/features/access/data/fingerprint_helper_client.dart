import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../domain/fingerprint_protocol.dart';

/// Spawns the x64 U.are.U helper, talks HTTP on 127.0.0.1, then kills it.
class FingerprintHelperSession {
  FingerprintHelperSession();

  Process? _process;
  HttpClient? _http;
  int? _port;
  String? _token;
  Future<void>? _starting;
  final StringBuffer _stderr = StringBuffer();

  bool get isRunning => _process != null;

  static File? resolveExecutable() {
    if (kIsWeb || !Platform.isWindows) {
      return null;
    }
    final String besideApp = p.join(
      File(Platform.resolvedExecutable).parent.path,
      FingerprintProtocol.exeName,
    );
    final List<String> candidates = <String>[];
    Directory dir = Directory.current;
    for (int i = 0; i < 8; i++) {
      candidates.add(
        p.join(
          dir.path,
          'tools',
          'fingerprint_helper',
          'bin',
          'Release',
          'net48',
          FingerprintProtocol.exeName,
        ),
      );
      final Directory parent = dir.parent;
      if (parent.path == dir.path) {
        break;
      }
      dir = parent;
    }
    // During flutter run the copy next to the app goes stale. Prefer the
    // helper just built under tools/ when it is present.
    if (kDebugMode) {
      candidates.add(besideApp);
    } else {
      candidates.insert(0, besideApp);
    }
    for (final String path in candidates) {
      final File file = File(path);
      if (file.existsSync()) {
        return file;
      }
    }
    return null;
  }

  static bool get isSupported {
    return resolveExecutable() != null;
  }

  Future<void> start() {
    if (_port != null && _process != null) {
      return Future<void>.value();
    }
    return _starting ??= _start().whenComplete(() {
      _starting = null;
    });
  }

  Future<void> _start() async {
    if (_process != null) {
      return;
    }
    final File? exe = resolveExecutable();
    if (exe == null) {
      throw const FingerprintHelperException(
        code: 'NO_HELPER',
        message: 'Fingerprint helper is not installed on this PC.',
      );
    }

    await _killStrayHelpers();
    final String token = _randomToken();
    final Map<String, String> environment = Map<String, String>.from(
      Platform.environment,
    );
    final String helperDir = exe.parent.path;
    environment['PATH'] = '$helperDir;${environment['PATH'] ?? ''}';

    final Completer<void> ready = Completer<void>();
    _token = token;
    _stderr.clear();

    final Process process = await Process.start(
      exe.path,
      <String>['--token', token, '--port', '0'],
      workingDirectory: helperDir,
      environment: environment,
      runInShell: false,
    );
    _process = process;
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((String line) {
          final int? port = FingerprintProtocol.parseReadyPort(line);
          if (port != null && !ready.isCompleted) {
            _port = port;
            ready.complete();
          }
        });
    process.stderr.transform(utf8.decoder).listen((String chunk) {
      _stderr.write(chunk);
    });
    unawaited(
      process.exitCode.then((int code) {
        if (!ready.isCompleted) {
          final String err = _stderr.toString().trim();
          ready.completeError(
            FingerprintHelperException(
              code: err.contains(FingerprintProtocol.helperBusy)
                  ? FingerprintProtocol.helperBusy
                  : 'HELPER_EXIT',
              message: FingerprintProtocol.userMessage(
                code: err.contains(FingerprintProtocol.helperBusy)
                    ? FingerprintProtocol.helperBusy
                    : 'HELPER_EXIT',
                message: err.isEmpty
                    ? 'Fingerprint helper exited (code $code).'
                    : err,
              ),
            ),
          );
        }
      }),
    );

    try {
      await ready.future.timeout(const Duration(seconds: 8));
    } catch (error) {
      await stop();
      if (error is FingerprintHelperException) {
        rethrow;
      }
      throw const FingerprintHelperException(
        code: 'HELPER_TIMEOUT',
        message: 'Fingerprint helper did not start.',
      );
    }
    _http = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  }

  Future<void> stop() async {
    final Process? process = _process;
    _process = null;
    _port = null;
    _token = null;
    _starting = null;
    _http?.close(force: true);
    _http = null;
    if (process == null) {
      return;
    }
    process.kill(ProcessSignal.sigkill);
    try {
      await process.exitCode.timeout(const Duration(seconds: 2));
    } catch (_) {
      try {
        process.kill(ProcessSignal.sigkill);
      } catch (_) {}
    }
  }

  Future<FingerprintHealth> health() async {
    final Map<String, Object?> json = await _get('/health');
    _throwIfFailed(json);
    return FingerprintHealth(
      readerCount: (json['readerCount'] as num?)?.toInt() ?? 0,
      readerName: '${json['readerName'] ?? ''}',
      vendorId: (json['vendorId'] as num?)?.toInt() ?? 0,
      productId: (json['productId'] as num?)?.toInt() ?? 0,
    );
  }

  Future<String> capture({
    int timeoutMs = FingerprintProtocol.defaultCaptureTimeoutMs,
  }) async {
    final Map<String, Object?> json = await _post('/capture', <String, Object?>{
      'timeoutMs': timeoutMs,
    }, timeout: Duration(milliseconds: timeoutMs + 12000));
    _throwIfFailed(json);
    final String fmd = '${json['protectedFmd'] ?? ''}'.trim();
    if (fmd.isEmpty) {
      throw const FingerprintHelperException(
        code: 'NO_DATA',
        message: 'No fingerprint template was returned.',
      );
    }
    return fmd;
  }

  Future<String> enroll(List<String> protectedFmds) async {
    final Map<String, Object?> json = await _post('/enroll', <String, Object?>{
      'protectedFmds': protectedFmds,
    });
    _throwIfFailed(json);
    final String fmd = '${json['protectedFmd'] ?? ''}'.trim();
    if (fmd.isEmpty) {
      throw const FingerprintHelperException(
        code: 'NO_DATA',
        message: 'Enrollment did not return a template.',
      );
    }
    return fmd;
  }

  Future<FingerprintVerifyResult> verify(
    List<String> protectedFmds, {
    int timeoutMs = FingerprintProtocol.defaultCaptureTimeoutMs,
  }) async {
    final Map<String, Object?> json = await _post('/verify', <String, Object?>{
      'protectedFmds': protectedFmds,
      'timeoutMs': timeoutMs,
    }, timeout: Duration(milliseconds: timeoutMs + 12000));
    _throwIfFailed(json);
    return FingerprintVerifyResult(
      match: json['match'] == true,
      score: (json['score'] as num?)?.toInt() ?? 0x7fffffff,
      message: '${json['message'] ?? ''}'.trim(),
    );
  }

  Future<Map<String, Object?>> _get(String path) async {
    final Uri uri = _uri(path);
    final HttpClient client = _requireHttp();
    final HttpClientRequest request = await client.getUrl(uri);
    _authorize(request);
    return _read(request);
  }

  Future<Map<String, Object?>> _post(
    String path,
    Map<String, Object?> body, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final Uri uri = _uri(path);
    final HttpClient client = _requireHttp();
    final HttpClientRequest request = await client
        .postUrl(uri)
        .timeout(timeout);
    _authorize(request);
    request.headers.contentType = ContentType.json;
    final List<int> bytes = utf8.encode(jsonEncode(body));
    request.contentLength = bytes.length;
    request.add(bytes);
    return _read(request, timeout: timeout);
  }

  Future<Map<String, Object?>> _read(
    HttpClientRequest request, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final HttpClientResponse response = await request.close().timeout(timeout);
    final String raw = await utf8.decodeStream(response).timeout(timeout);
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FingerprintHelperException(
        code: 'BAD_RESPONSE',
        message: 'Fingerprint helper returned invalid JSON.',
      );
    }
    return decoded.cast<String, Object?>();
  }

  Uri _uri(String path) {
    final int? port = _port;
    final String? token = _token;
    if (port == null || token == null) {
      throw const FingerprintHelperException(
        code: 'NOT_STARTED',
        message: 'Fingerprint helper is not running.',
      );
    }
    return Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: port,
      path: path,
      queryParameters: <String, String>{'token': token},
    );
  }

  HttpClient _requireHttp() {
    final HttpClient? http = _http;
    if (http == null) {
      throw const FingerprintHelperException(
        code: 'NOT_STARTED',
        message: 'Fingerprint helper is not running.',
      );
    }
    return http;
  }

  void _authorize(HttpClientRequest request) {
    final String? token = _token;
    if (token != null) {
      request.headers.set('X-FuelPoint-Token', token);
    }
  }

  void _throwIfFailed(Map<String, Object?> json) {
    if (json['ok'] == true) {
      return;
    }
    final String code = '${json['code'] ?? 'FAILURE'}';
    throw FingerprintHelperException(
      code: code,
      message: FingerprintProtocol.userMessage(
        code: code,
        message: json['message'] as String?,
      ),
    );
  }

  static Future<void> _killStrayHelpers() async {
    try {
      await Process.run('taskkill', <String>[
        '/F',
        '/IM',
        FingerprintProtocol.exeName,
        '/T',
      ]);
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }

  static String _randomToken() {
    final Random random = Random.secure();
    final List<int> bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
