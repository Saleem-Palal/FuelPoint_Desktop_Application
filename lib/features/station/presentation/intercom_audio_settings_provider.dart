import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/database_helper.dart';
import '../domain/intercom_audio_settings.dart';

final intercomAudioSettingsProvider =
    NotifierProvider<IntercomAudioSettingsNotifier, IntercomAudioSettings>(
      IntercomAudioSettingsNotifier.new,
    );

class IntercomAudioSettingsNotifier extends Notifier<IntercomAudioSettings> {
  final DatabaseHelper _db = DatabaseHelper.instance;
  Timer? _saveTimer;
  bool _alive = true;

  @override
  IntercomAudioSettings build() {
    _alive = true;
    ref.onDispose(() {
      _alive = false;
      _saveTimer?.cancel();
    });
    Future<void>.microtask(_load);
    return const IntercomAudioSettings();
  }

  void setPumpVolume(int value) {
    _stage(
      state.copyWith(pumpVolume: IntercomAudioSettings.clampSpeaker(value)),
    );
  }

  void setStationVolume(int value) {
    _stage(
      state.copyWith(stationVolume: IntercomAudioSettings.clampPercent(value)),
    );
  }

  void setPumpMicLevel(int value) {
    _stage(
      state.copyWith(pumpMicLevel: IntercomAudioSettings.clampPercent(value)),
    );
  }

  void setPumpNoiseCut(int value) {
    _stage(
      state.copyWith(pumpNoiseCut: IntercomAudioSettings.clampPercent(value)),
    );
  }

  void setMicLevel(int value) {
    _stage(state.copyWith(micLevel: IntercomAudioSettings.clampPercent(value)));
  }

  void setOfficeNoiseCut(int value) {
    _stage(
      state.copyWith(officeNoiseCut: IntercomAudioSettings.clampPercent(value)),
    );
  }

  void _stage(IntercomAudioSettings next) {
    state = next;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 200), () {
      unawaited(_persist(next));
    });
  }

  Future<void> _load() async {
    try {
      final int sharedNoiseCut = await _read(
        DatabaseHelper.settingIntercomNoiseCut,
        IntercomAudioSettings.defaultNoiseCut,
      );
      final IntercomAudioSettings loaded = IntercomAudioSettings(
        pumpVolume: await _read(
          DatabaseHelper.settingIntercomPumpVolume,
          IntercomAudioSettings.defaultPumpVolume,
          max: 150,
        ),
        pumpMicLevel: await _read(
          DatabaseHelper.settingIntercomPumpMic,
          IntercomAudioSettings.defaultPumpMicLevel,
        ),
        pumpNoiseCut: await _read(
          DatabaseHelper.settingIntercomPumpNoiseCut,
          sharedNoiseCut,
        ),
        stationVolume: await _read(
          DatabaseHelper.settingIntercomStationVolume,
          IntercomAudioSettings.defaultStationVolume,
        ),
        micLevel: await _read(
          DatabaseHelper.settingIntercomMicLevel,
          IntercomAudioSettings.defaultMicLevel,
        ),
        officeNoiseCut: await _read(
          DatabaseHelper.settingIntercomOfficeNoiseCut,
          sharedNoiseCut,
        ),
      );
      if (!_alive) {
        return;
      }
      state = loaded;
    } catch (error, stack) {
      debugPrint('IntercomAudioSettingsNotifier._load failed: $error\n$stack');
    }
  }

  Future<void> _persist(IntercomAudioSettings settings) async {
    try {
      await _db.writeSetting(
        DatabaseHelper.settingIntercomPumpVolume,
        '${settings.pumpVolume}',
      );
      await _db.writeSetting(
        DatabaseHelper.settingIntercomPumpMic,
        '${settings.pumpMicLevel}',
      );
      await _db.writeSetting(
        DatabaseHelper.settingIntercomPumpNoiseCut,
        '${settings.pumpNoiseCut}',
      );
      await _db.writeSetting(
        DatabaseHelper.settingIntercomStationVolume,
        '${settings.stationVolume}',
      );
      await _db.writeSetting(
        DatabaseHelper.settingIntercomMicLevel,
        '${settings.micLevel}',
      );
      await _db.writeSetting(
        DatabaseHelper.settingIntercomOfficeNoiseCut,
        '${settings.officeNoiseCut}',
      );
    } catch (error, stack) {
      debugPrint(
        'IntercomAudioSettingsNotifier._persist failed: $error\n$stack',
      );
    }
  }

  Future<int> _read(String key, int fallback, {int max = 100}) async {
    final String? raw = await _db.readSetting(key);
    final int? parsed = int.tryParse(raw ?? '');
    if (parsed == null) {
      return fallback;
    }
    if (parsed < 0) {
      return 0;
    }
    if (parsed > max) {
      return max;
    }
    return parsed;
  }
}
