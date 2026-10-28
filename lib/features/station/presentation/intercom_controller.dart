import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/intercom_audio_windows.dart';
import '../data/intercom_codec.dart';
import '../data/intercom_voice_capture_windows.dart';
import '../domain/intercom_audio_settings.dart';
import 'intercom_audio_settings_provider.dart';

enum IntercomPhase { idle, talk, listen }

class IntercomState {
  const IntercomState({
    this.phase = IntercomPhase.idle,
    this.unitId,
    this.startedAt,
  });

  final IntercomPhase phase;
  final int? unitId;
  final DateTime? startedAt;

  @override
  bool operator ==(Object other) {
    return other is IntercomState &&
        other.phase == phase &&
        other.unitId == unitId &&
        other.startedAt == startedAt;
  }

  @override
  int get hashCode => Object.hash(phase, unitId, startedAt);
}

final intercomControllerProvider =
    NotifierProvider<IntercomController, IntercomState>(IntercomController.new);

class IntercomController extends Notifier<IntercomState> {
  late final IntercomAudioWindows _audio;
  final IntercomVoiceCaptureWindows _voice = IntercomVoiceCaptureWindows();
  bool Function(int unitId)? _isOnline;
  void Function(int unitId, bool down)? _sendPtt;
  void Function(int unitId, Uint8List frame)? _sendPcm;
  int _generation = 0;

  @override
  IntercomState build() {
    _audio = IntercomAudioWindows();
    ref.onDispose(() {
      _generation++;
      _voice.stop();
      _audio.dispose();
    });
    return const IntercomState();
  }

  void bind({
    required bool Function(int unitId) isOnline,
    required void Function(int unitId, bool down) sendPtt,
    required void Function(int unitId, Uint8List frame) sendPcm,
  }) {
    _isOnline = isOnline;
    _sendPtt = sendPtt;
    _sendPcm = sendPcm;
  }

  void beginTalk(int unitId) {
    if (!(_isOnline?.call(unitId) ?? false)) {
      return;
    }
    if (state.phase == IntercomPhase.listen && state.unitId == unitId) {
      return;
    }
    if (state.phase == IntercomPhase.talk && state.unitId == unitId) {
      return;
    }
    final int generation = ++_generation;
    _stopHardware(sendPttUp: state.phase == IntercomPhase.talk);
    state = IntercomState(
      phase: IntercomPhase.talk,
      unitId: unitId,
      startedAt: DateTime.now(),
    );
    _sendPtt?.call(unitId, true);
    final bool started = _startTalkCapture(generation, unitId);
    if (generation != _generation) {
      return;
    }
    if (!started) {
      _stopTalkCapture();
      state = const IntercomState();
      _sendPtt?.call(unitId, false);
    }
  }

  /// Windows uses the same voice capture as the walkie-talkie page.
  /// The pump Speaker slider is the only gain on the way to the unit.
  bool _startTalkCapture(int generation, int unitId) {
    void send(Uint8List pcm) {
      if (generation != _generation) {
        return;
      }
      if (state.phase != IntercomPhase.talk || state.unitId != unitId) {
        return;
      }
      _sendPcm?.call(unitId, IntercomCodec.operatorFrame(pcm));
    }

    if (Platform.isWindows && _voice.start(send)) {
      return true;
    }
    return _audio.startCapture(send);
  }

  void _stopTalkCapture() {
    _voice.stop();
    _audio.stopCapture();
  }

  void endTalk(int unitId) {
    if (state.phase != IntercomPhase.talk || state.unitId != unitId) {
      return;
    }
    _generation++;
    _stopTalkCapture();
    state = const IntercomState();
    _sendPtt?.call(unitId, false);
  }

  void onHelperSignal(IntercomNotice notice) {
    if (notice.unitId < 1 || notice.unitId > 5) {
      return;
    }
    if (notice.helperDown) {
      final int? talkingUnit = state.unitId;
      if (state.phase == IntercomPhase.talk && talkingUnit != null) {
        _sendPtt?.call(talkingUnit, false);
      }
      _generation++;
      _stopTalkCapture();
      _audio.setPlaybackVolume(_audioSettings.stationVolume);
      _audio.startPlayback();
      state = IntercomState(
        phase: IntercomPhase.listen,
        unitId: notice.unitId,
        startedAt: DateTime.now(),
      );
      return;
    }
    if (state.phase == IntercomPhase.listen && state.unitId == notice.unitId) {
      _audio.stopPlayback();
      state = const IntercomState();
    }
  }

  void onHelperAudio(int unitId, Uint8List pcm) {
    if (state.phase != IntercomPhase.listen || state.unitId != unitId) {
      return;
    }
    final IntercomAudioSettings settings = _audioSettings;
    _audio.enqueuePlayback(
      IntercomVoiceCleaner.scale(pcm, settings.pumpMicLevel),
    );
  }

  void onUnitOffline(int unitId) {
    if (state.unitId != unitId || state.phase == IntercomPhase.idle) {
      return;
    }
    _generation++;
    _stopTalkCapture();
    _audio.stopPlayback();
    state = const IntercomState();
  }

  IntercomAudioSettings get _audioSettings =>
      ref.read(intercomAudioSettingsProvider);

  void applyStationVolume(int percent) {
    _audio.setPlaybackVolume(percent);
  }

  void _stopHardware({required bool sendPttUp}) {
    final int? unitId = state.unitId;
    final bool talking = state.phase == IntercomPhase.talk;
    _stopTalkCapture();
    _audio.stopPlayback();
    if (sendPttUp && talking && unitId != null) {
      _sendPtt?.call(unitId, false);
    }
  }
}
