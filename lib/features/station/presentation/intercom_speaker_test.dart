import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/intercom_codec.dart';
import '../data/intercom_wav.dart';
import 'intercom_controller.dart';
import 'station_providers.dart';

class IntercomSpeakerTestState {
  const IntercomSpeakerTestState({
    this.unitId = 1,
    this.files = const <String>[],
    this.playing = false,
    this.status = 'No files chosen. Play sends a 6 second tone.',
  });

  final int unitId;
  final List<String> files;
  final bool playing;
  final String status;

  IntercomSpeakerTestState copyWith({
    int? unitId,
    List<String>? files,
    bool? playing,
    String? status,
  }) {
    return IntercomSpeakerTestState(
      unitId: unitId ?? this.unitId,
      files: files ?? this.files,
      playing: playing ?? this.playing,
      status: status ?? this.status,
    );
  }
}

final intercomSpeakerTestProvider =
    NotifierProvider<IntercomSpeakerTest, IntercomSpeakerTestState>(
      IntercomSpeakerTest.new,
    );

class IntercomSpeakerTest extends Notifier<IntercomSpeakerTestState> {
  int _token = 0;
  bool _alive = true;

  @override
  IntercomSpeakerTestState build() {
    _alive = true;
    ref.onDispose(() {
      _alive = false;
      _token++;
    });
    return const IntercomSpeakerTestState();
  }

  void selectUnit(int unitId) {
    if (unitId < 1 || unitId > 5 || state.playing) {
      return;
    }
    state = state.copyWith(unitId: unitId);
  }

  Future<void> pickFiles() async {
    final List<PlatformFile> picked = await FilePicker.pickFiles(
      dialogTitle: 'Choose WAV files for the pump speaker',
      type: FileType.custom,
      allowedExtensions: const <String>['wav'],
    );
    if (!_alive || picked.isEmpty) {
      return;
    }
    _remember(<String>[
      for (final PlatformFile file in picked)
        if (file.path != null && file.path!.isNotEmpty) file.path!,
    ]);
  }

  Future<void> pickDirectory() async {
    final String? folder = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose a folder of WAV files',
    );
    if (!_alive || folder == null || folder.isEmpty) {
      return;
    }
    final List<String> paths = <String>[];
    try {
      await for (final FileSystemEntity entity in Directory(
        folder,
      ).list(followLinks: false)) {
        if (entity is File && entity.path.toLowerCase().endsWith('.wav')) {
          paths.add(entity.path);
        }
      }
    } catch (_) {
      state = state.copyWith(status: 'Could not read that folder.');
      return;
    }
    paths.sort();
    if (paths.isEmpty) {
      state = state.copyWith(status: 'No WAV files in that folder.');
      return;
    }
    _remember(paths);
  }

  void clearFiles() {
    if (state.playing) {
      return;
    }
    state = state.copyWith(
      files: const <String>[],
      status: 'No files chosen. Play sends a 6 second tone.',
    );
  }

  void stop() {
    if (!state.playing) {
      return;
    }
    final int unitId = state.unitId;
    _token++;
    state = state.copyWith(playing: false, status: 'Stopped.');
    ref.read(stationControllerProvider.notifier).sendIntercomPtt(unitId, false);
  }

  Future<void> play() async {
    if (state.playing) {
      return;
    }
    final int unitId = state.unitId;
    if (!ref.read(stationControllerProvider).endpoint(unitId).connected) {
      state = state.copyWith(status: 'Unit $unitId is offline.');
      return;
    }
    final IntercomPhase phase = ref.read(intercomControllerProvider).phase;
    if (phase != IntercomPhase.idle) {
      state = state.copyWith(
        status: 'End the intercom call, then play the test.',
      );
      return;
    }
    final Uint8List? pcm = await _loadPcm();
    if (!_alive) {
      return;
    }
    if (pcm == null || pcm.isEmpty) {
      state = state.copyWith(
        status: 'Could not read those WAV files. Choose 16-bit WAV audio.',
      );
      return;
    }
    final int token = ++_token;
    final bool tone = state.files.isEmpty;
    state = state.copyWith(
      playing: true,
      status: tone
          ? 'Playing a 6 second tone on unit $unitId.'
          : 'Playing ${state.files.length} file${state.files.length == 1 ? '' : 's'} on unit $unitId.',
    );
    final StationController station = ref.read(
      stationControllerProvider.notifier,
    );
    station.sendIntercomPtt(unitId, true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      const int leadChunks = 8;
      final int chunks =
          (pcm.length + IntercomCodec.pcmBytes - 1) ~/ IntercomCodec.pcmBytes;
      final Stopwatch clock = Stopwatch()..start();
      for (int i = 0; i < chunks; i++) {
        if (!_alive || token != _token) {
          break;
        }
        final int start = i * IntercomCodec.pcmBytes;
        final int end = start + IntercomCodec.pcmBytes > pcm.length
            ? pcm.length
            : start + IntercomCodec.pcmBytes;
        final Uint8List slice = Uint8List(IntercomCodec.pcmBytes);
        slice.setRange(0, end - start, pcm, start);
        station.sendIntercomPcm(unitId, slice);
        if (i + 1 < leadChunks) {
          continue;
        }
        final int dueMs = (i + 1 - leadChunks) * 20;
        final int waitMs = dueMs - clock.elapsedMilliseconds;
        if (waitMs > 0) {
          await Future<void>.delayed(Duration(milliseconds: waitMs));
        }
      }
    } finally {
      if (_alive && token == _token) {
        station.sendIntercomPtt(unitId, false);
        state = state.copyWith(playing: false, status: 'Finished.');
      } else if (!_alive) {
        try {
          station.sendIntercomPtt(unitId, false);
        } catch (_) {}
      }
    }
  }

  void _remember(List<String> paths) {
    if (paths.isEmpty) {
      state = state.copyWith(status: 'Those files have no path.');
      return;
    }
    final List<String> kept = paths.length > 30 ? paths.sublist(0, 30) : paths;
    state = state.copyWith(
      files: kept,
      status: paths.length > 30
          ? '30 WAV files ready. The rest were left out.'
          : '${kept.length} WAV file${kept.length == 1 ? '' : 's'} ready.',
    );
  }

  Future<Uint8List?> _loadPcm() async {
    if (state.files.isEmpty) {
      return intercomTestTone();
    }
    final BytesBuilder all = BytesBuilder(copy: false);
    const int maxBytes = IntercomCodec.sampleRate * 180 * 2;
    var any = false;
    for (final String path in state.files) {
      if (all.length >= maxBytes) {
        break;
      }
      try {
        final Uint8List? pcm = pcm16kFromWav(await File(path).readAsBytes());
        if (pcm == null || pcm.isEmpty) {
          continue;
        }
        if (any) {
          final int gap = IntercomCodec.sampleRate ~/ 5 * 2;
          if (all.length + gap >= maxBytes) {
            break;
          }
          all.add(Uint8List(gap));
        }
        final int room = maxBytes - all.length;
        if (room <= 0) {
          break;
        }
        all.add(pcm.length > room ? Uint8List.sublistView(pcm, 0, room) : pcm);
        any = true;
      } catch (_) {
        continue;
      }
    }
    if (!any) {
      return null;
    }
    return all.toBytes();
  }
}
