import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/intercom_audio_windows.dart';
import '../data/intercom_codec.dart';
import '../data/intercom_mp3.dart';
import '../data/intercom_test_wifi.dart';
import '../data/intercom_voice_capture_windows.dart';

enum IntercomTestLink { idle, joining, live, failed }

class IntercomTestState {
  const IntercomTestState({
    this.link = IntercomTestLink.idle,
    this.talking = false,
    this.hearing = false,
    this.micOnSpeaker = false,
    this.mic = 100,
    this.speaker = 80,
    this.noiseCut = 20,
    this.clipPath = '',
    this.status = 'Enter the ESP Wi-Fi and connect.',
  });

  final IntercomTestLink link;
  final bool talking;
  final bool hearing;
  final bool micOnSpeaker;
  final int mic;
  final int speaker;
  final int noiseCut;

  /// Path of the MP3 currently going to the ESP speaker. Empty when idle.
  final String clipPath;
  final String status;

  IntercomTestState copyWith({
    IntercomTestLink? link,
    bool? talking,
    bool? hearing,
    bool? micOnSpeaker,
    int? mic,
    int? speaker,
    int? noiseCut,
    String? clipPath,
    String? status,
  }) {
    return IntercomTestState(
      link: link ?? this.link,
      talking: talking ?? this.talking,
      hearing: hearing ?? this.hearing,
      micOnSpeaker: micOnSpeaker ?? this.micOnSpeaker,
      mic: mic ?? this.mic,
      speaker: speaker ?? this.speaker,
      noiseCut: noiseCut ?? this.noiseCut,
      clipPath: clipPath ?? this.clipPath,
      status: status ?? this.status,
    );
  }
}

final intercomTestControllerProvider =
    NotifierProvider.autoDispose<IntercomTestController, IntercomTestState>(
      IntercomTestController.new,
    );

/// Half-duplex link to [Intercom_test.ino]. The PC is the other radio.
class IntercomTestController extends AutoDisposeNotifier<IntercomTestState> {
  static const int port = 81;

  late final IntercomAudioWindows _audio;
  final IntercomVoiceCaptureWindows _voice = IntercomVoiceCaptureWindows();
  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _hearingTimer;
  int _generation = 0;
  int _clipToken = 0;

  @override
  IntercomTestState build() {
    _audio = IntercomAudioWindows();
    ref.onDispose(_shutdown);
    return const IntercomTestState();
  }

  Future<void> connect({
    required String ssid,
    required String password,
    required String host,
  }) async {
    final int generation = ++_generation;
    _clipToken++;
    _dropSocket();
    _stopMic();
    _audio.stopPlayback();
    final String name = ssid.trim();
    final String address = host.trim();
    state = state.copyWith(
      link: IntercomTestLink.joining,
      talking: false,
      hearing: false,
      micOnSpeaker: false,
      clipPath: '',
      status: 'Joining $name…',
    );

    String? joinError;
    if (!await IntercomTestWifi.hasSubnet(address)) {
      joinError = await IntercomTestWifi.join(ssid: name, password: password);
      if (generation != _generation) {
        return;
      }
      final bool onNet = await _waitForSubnet(address);
      if (generation != _generation) {
        return;
      }
      if (!onNet) {
        state = state.copyWith(
          link: IntercomTestLink.failed,
          status:
              joinError ??
              'This PC did not get an address from the ESP. '
                  'The LED should flash three times at boot, then blink. '
                  'No flashes means the board is still in reset.',
        );
        return;
      }
    }

    if (generation != _generation) {
      return;
    }
    state = state.copyWith(
      link: IntercomTestLink.joining,
      status: 'Opening ws://$address:$port/ …',
    );
    try {
      final WebSocket socket = await WebSocket.connect(
        'ws://$address:$port/',
        compression: CompressionOptions.compressionOff,
      ).timeout(const Duration(seconds: 8));
      if (generation != _generation) {
        await socket.close();
        return;
      }
      _socket = socket;
      _subscription = socket.listen(
        (dynamic data) => _onSocketData(generation, data),
        onError: (Object error) {
          if (generation != _generation) {
            return;
          }
          _fail('The audio link dropped. $error');
        },
        onDone: () {
          if (generation != _generation) {
            return;
          }
          _fail('The ESP closed the audio link.');
        },
      );
      _sendLevels();
      state = state.copyWith(
        link: IntercomTestLink.live,
        status: 'Connected. Hold to talk, or hold the button on the box.',
      );
    } catch (error) {
      if (generation != _generation) {
        return;
      }
      final String extra = joinError == null ? '' : ' $joinError';
      state = state.copyWith(
        link: IntercomTestLink.failed,
        status: 'Could not open the audio link.$extra $error',
      );
    }
  }

  Future<void> disconnect() async {
    _generation++;
    _clipToken++;
    _dropSocket();
    _hearingTimer?.cancel();
    _stopMic();
    _audio.stopPlayback();
    state = state.copyWith(
      link: IntercomTestLink.idle,
      talking: false,
      hearing: false,
      micOnSpeaker: false,
      clipPath: '',
      status: 'Disconnected. This PC may still be on the ESP Wi-Fi.',
    );
  }

  void setMic(int value) {
    final int mic = value.clamp(0, 100);
    state = state.copyWith(mic: mic);
    _send('G${_espGain(mic)}');
  }

  void setSpeaker(int value) {
    final int speaker = value.clamp(0, 150);
    state = state.copyWith(speaker: speaker);
    _audio.setPlaybackVolume(speaker);
    _send('V$speaker');
  }

  void setNoiseCut(int value) {
    final int cut = value.clamp(0, 100);
    state = state.copyWith(noiseCut: cut);
    _send('N$cut');
  }

  void swapMicChannel() {
    _send('C');
    if (state.link == IntercomTestLink.live) {
      state = state.copyWith(
        status: 'Mic channel swapped. Hold the box button to try it.',
      );
    }
  }

  void beginBoxLoop() {
    if (state.link != IntercomTestLink.live || state.micOnSpeaker) {
      return;
    }
    state = state.copyWith(
      micOnSpeaker: true,
      status: 'ESP microphone is playing on the ESP speaker.',
    );
    _send('M1');
  }

  void endBoxLoop() {
    if (!state.micOnSpeaker) {
      return;
    }
    state = state.copyWith(micOnSpeaker: false, status: _idleStatus());
    _send('M0');
  }

  void beginTalk() {
    if (state.link != IntercomTestLink.live || state.talking) {
      return;
    }
    if (state.clipPath.isNotEmpty) {
      stopClip();
    }
    _hearingTimer?.cancel();
    _audio.stopPlayback();
    state = state.copyWith(talking: true, hearing: false, status: 'Talking');
    _send('1');
    final bool started = _voice.start(_onCaptured);
    if (!started) {
      state = state.copyWith(
        talking: false,
        status: 'This PC microphone did not open. ${_voice.lastError ?? ''}',
      );
      _send('0');
    }
  }

  /// Sends [path] to the ESP speaker as raw PCM. Mic processing is not applied.
  Future<void> playClip(String path) async {
    if (state.link != IntercomTestLink.live) {
      state = state.copyWith(status: 'Connect to the ESP, then play the file.');
      return;
    }
    if (state.talking) {
      endTalk();
    }
    if (state.micOnSpeaker) {
      endBoxLoop();
    }
    final int token = ++_clipToken;
    final String name = _fileName(path);
    state = state.copyWith(clipPath: path, status: 'Reading $name…');
    final IntercomFilePcm file;
    try {
      file = await pcm16kFromMp3File(path);
    } catch (error) {
      if (token != _clipToken) {
        return;
      }
      state = state.copyWith(
        clipPath: '',
        status: 'Could not read $name. $error',
      );
      return;
    }
    if (token != _clipToken) {
      return;
    }
    if (file.pcm.isEmpty || state.link != IntercomTestLink.live) {
      state = state.copyWith(
        clipPath: '',
        status: 'Could not read $name. Choose an MP3 file.',
      );
      return;
    }
    final String lead = file.trimmed
        ? 'Playing the first 3 minutes of '
        : 'Playing ';
    state = state.copyWith(
      clipPath: path,
      status:
          '$lead$name on the ESP speaker. Only the Speaker slider changes it.',
    );
    _send('V${state.speaker}');
    _send('1');
    try {
      await _paceClip(file.pcm, token);
    } finally {
      if (token == _clipToken) {
        _send('0');
        state = state.copyWith(clipPath: '', status: 'Finished $name.');
      }
    }
  }

  void stopClip() {
    if (state.clipPath.isEmpty) {
      return;
    }
    _clipToken++;
    _send('0');
    state = state.copyWith(clipPath: '', status: 'Stopped the file.');
  }

  Future<void> _paceClip(Uint8List pcm, int token) async {
    const int leadChunks = 8;
    final int chunkBytes = IntercomCodec.pcmBytes;
    final int chunks = (pcm.length + chunkBytes - 1) ~/ chunkBytes;
    final Stopwatch clock = Stopwatch()..start();
    for (int index = 0; index < chunks; index++) {
      if (!_pushClipChunk(pcm, index, token)) {
        return;
      }
      if (index + 1 < leadChunks) {
        continue;
      }
      final int dueMs = (index + 1 - leadChunks) * 20;
      final int waitMs = dueMs - clock.elapsedMilliseconds;
      if (waitMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: waitMs));
      }
    }
  }

  bool _pushClipChunk(Uint8List pcm, int index, int token) {
    final WebSocket? socket = _socket;
    if (token != _clipToken || socket == null) {
      return false;
    }
    final int start = index * IntercomCodec.pcmBytes;
    if (start >= pcm.length) {
      return false;
    }
    final int end = start + IntercomCodec.pcmBytes > pcm.length
        ? pcm.length
        : start + IntercomCodec.pcmBytes;
    final Uint8List slice = Uint8List(IntercomCodec.pcmBytes);
    slice.setRange(0, end - start, pcm, start);
    try {
      socket.add(slice);
    } catch (_) {
      return false;
    }
    return token == _clipToken;
  }

  void endTalk() {
    if (!state.talking) {
      return;
    }
    _stopMic();
    state = state.copyWith(
      talking: false,
      status: state.hearing ? 'Box is talking' : _idleStatus(),
    );
    _send('0');
  }

  Future<bool> _waitForSubnet(String host) async {
    for (int i = 0; i < 24; i++) {
      if (await IntercomTestWifi.hasSubnet(host)) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return IntercomTestWifi.hasSubnet(host);
  }

  void _onCaptured(Uint8List pcm) {
    if (!state.talking) {
      return;
    }
    final WebSocket? socket = _socket;
    if (socket == null) {
      return;
    }
    try {
      socket.add(pcm);
    } catch (_) {}
  }

  void _onSocketData(int generation, dynamic data) {
    if (generation != _generation) {
      return;
    }
    if (data is String) {
      if (data == '1') {
        _hearBox();
      } else if (data == '0') {
        _stopHearing();
      }
      return;
    }
    if (data is! List<int> || state.talking) {
      return;
    }
    if (!state.hearing) {
      _hearBox();
    }
    _audio.enqueuePlayback(
      IntercomVoiceCleaner.pullDown(Uint8List.fromList(data), state.noiseCut),
    );
    _armHearingTimeout();
  }

  void _hearBox() {
    if (state.talking) {
      _stopMic();
      _send('0');
    }
    if (!state.hearing) {
      _audio.startPlayback();
      _audio.setPlaybackVolume(state.speaker);
    }
    state = state.copyWith(
      talking: false,
      hearing: true,
      status: 'Box is talking',
    );
    _armHearingTimeout();
  }

  void _stopHearing() {
    _hearingTimer?.cancel();
    _audio.stopPlayback();
    if (!state.hearing && !state.talking) {
      return;
    }
    state = state.copyWith(
      hearing: false,
      talking: false,
      status: _idleStatus(),
    );
  }

  void _armHearingTimeout() {
    _hearingTimer?.cancel();
    _hearingTimer = Timer(const Duration(milliseconds: 800), () {
      if (state.hearing && !state.talking) {
        _stopHearing();
      }
    });
  }

  void _sendLevels() {
    _send('V${state.speaker}');
    _send('G${_espGain(state.mic)}');
    _send('N${state.noiseCut}');
    _audio.setPlaybackVolume(state.speaker);
  }

  void _send(String text) {
    final WebSocket? socket = _socket;
    if (socket == null || state.link == IntercomTestLink.failed) {
      return;
    }
    try {
      socket.add(text);
    } catch (_) {}
  }

  /// Slider 60 is the 12x bench level. 100 reaches 20x on the INMP441.
  int _espGain(int mic) {
    return (mic.clamp(0, 100) * 20) ~/ 100;
  }

  String _idleStatus() {
    if (state.clipPath.isNotEmpty) {
      final String name = _fileName(state.clipPath);
      return 'Playing $name on the ESP speaker. Only the Speaker slider changes it.';
    }
    if (state.link == IntercomTestLink.live) {
      return 'Connected. Hold to talk, or hold the button on the box.';
    }
    return state.status;
  }

  String _fileName(String path) {
    final String normalized = path.replaceAll('\\', '/');
    final int slash = normalized.lastIndexOf('/');
    return slash < 0 ? path : normalized.substring(slash + 1);
  }

  void _fail(String status) {
    _generation++;
    _clipToken++;
    _dropSocket();
    _hearingTimer?.cancel();
    _stopMic();
    _audio.stopPlayback();
    state = state.copyWith(
      link: IntercomTestLink.failed,
      talking: false,
      hearing: false,
      micOnSpeaker: false,
      clipPath: '',
      status: status,
    );
  }

  void _dropSocket() {
    final StreamSubscription<dynamic>? subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    final WebSocket? socket = _socket;
    _socket = null;
    if (socket != null) {
      unawaited(() async {
        try {
          await socket.close();
        } catch (_) {}
      }());
    }
  }

  void _shutdown() {
    _generation++;
    _clipToken++;
    _hearingTimer?.cancel();
    _dropSocket();
    _stopMic();
    _audio.dispose();
  }

  void _stopMic() {
    _voice.stop();
    _audio.stopCapture();
  }
}
