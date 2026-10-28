/// Separate pump and office levels. Sliders are 0–100, except the pump
/// speaker, which goes to 150. 100 on that speaker is full level.
class IntercomAudioSettings {
  const IntercomAudioSettings({
    this.pumpVolume = defaultPumpVolume,
    this.pumpMicLevel = defaultPumpMicLevel,
    this.pumpNoiseCut = defaultNoiseCut,
    this.stationVolume = defaultStationVolume,
    this.micLevel = defaultMicLevel,
    this.officeNoiseCut = defaultNoiseCut,
  });

  static const int defaultPumpVolume = 80;
  static const int defaultPumpMicLevel = 100;
  static const int defaultStationVolume = 85;
  static const int defaultMicLevel = 80;
  static const int defaultNoiseCut = 20;

  /// Pump speaker level. 100 is full, the same as the walkie-talkie page.
  /// The slider can go to 150.
  final int pumpVolume;

  /// Digital gain of the pump microphone, before it is sent to the office.
  final int pumpMicLevel;

  /// Quiet-floor cut on the pump microphone and pump speaker.
  final int pumpNoiseCut;

  /// Windows playback level while the helper is talking.
  final int stationVolume;

  /// How loud the office microphone is sent to the pump.
  final int micLevel;

  /// Quiet-floor cut on the office microphone and office speaker.
  final int officeNoiseCut;

  static int clampPercent(int value) {
    return _clamp(value, 100);
  }

  /// Walkie-talkie speaker range. 100 is the file or voice at full level.
  static int clampSpeaker(int value) {
    return _clamp(value, 150);
  }

  static int _clamp(int value, int high) {
    if (value < 0) {
      return 0;
    }
    if (value > high) {
      return high;
    }
    return value;
  }

  IntercomAudioSettings copyWith({
    int? pumpVolume,
    int? pumpMicLevel,
    int? pumpNoiseCut,
    int? stationVolume,
    int? micLevel,
    int? officeNoiseCut,
  }) {
    return IntercomAudioSettings(
      pumpVolume: pumpVolume ?? this.pumpVolume,
      pumpMicLevel: pumpMicLevel ?? this.pumpMicLevel,
      pumpNoiseCut: pumpNoiseCut ?? this.pumpNoiseCut,
      stationVolume: stationVolume ?? this.stationVolume,
      micLevel: micLevel ?? this.micLevel,
      officeNoiseCut: officeNoiseCut ?? this.officeNoiseCut,
    );
  }
}
