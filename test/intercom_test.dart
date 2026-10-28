import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_dispenser/features/station/data/dispenser_socket_manager.dart';
import 'package:fuel_dispenser/features/station/data/intercom_codec.dart';
import 'package:fuel_dispenser/features/station/data/intercom_wav.dart';
import 'package:fuel_dispenser/features/station/data/telemetry_parser.dart';
import 'package:fuel_dispenser/features/station/data/wifi_status.dart';
import 'package:fuel_dispenser/features/station/domain/dispenser_models.dart';

void main() {
  test('helper frame is 0xA2 plus 640 PCM bytes', () {
    final Uint8List pcm = Uint8List(IntercomCodec.pcmBytes);
    for (int i = 0; i < pcm.length; i++) {
      pcm[i] = i & 0xFF;
    }

    final Uint8List frame = IntercomCodec.helperFrame(pcm);

    expect(frame.length, IntercomCodec.frameBytes);
    expect(frame[0], IntercomCodec.helperMagic);
    expect(frame.sublist(1), pcm);

    final Uint8List? decoded = IntercomCodec.pcmFromFrame(
      frame,
      magic: IntercomCodec.helperMagic,
    );
    expect(decoded, pcm);
  });

  test('operator frame uses 0xA1 and pads a short chunk to 640 bytes', () {
    final Uint8List frame = IntercomCodec.operatorFrame(
      Uint8List.fromList(<int>[1, 2, 3, 4]),
    );

    expect(frame.length, 641);
    expect(frame[0], 0xA1);
    expect(frame.sublist(1, 5), <int>[1, 2, 3, 4]);
    expect(frame.sublist(5).every((int byte) => byte == 0), isTrue);
  });

  test('straight gain keeps a quiet sample and does not filter it', () {
    final ByteData data = ByteData(4);
    data.setInt16(0, 40, Endian.little);
    data.setInt16(2, 4000, Endian.little);
    final Uint8List pcm = data.buffer.asUint8List();

    final Uint8List full = IntercomVoiceCleaner.scale(pcm, 100);
    final ByteData fullData = ByteData.sublistView(full);
    expect(fullData.getInt16(0, Endian.little), 40);
    expect(fullData.getInt16(2, Endian.little), 4000);

    final Uint8List half = IntercomVoiceCleaner.scale(pcm, 50);
    final ByteData halfData = ByteData.sublistView(half);
    expect(halfData.getInt16(0, Endian.little), 20);
    expect(halfData.getInt16(2, Endian.little), 2000);
  });

  test('short and wrong-magic audio frames are rejected', () {
    expect(
      IntercomCodec.pcmFromFrame(
        Uint8List.fromList(<int>[IntercomCodec.helperMagic, 1, 2]),
        magic: IntercomCodec.helperMagic,
      ),
      isNull,
    );
    final Uint8List wrong = IntercomCodec.operatorFrame(Uint8List(640));
    expect(
      IntercomCodec.pcmFromFrame(wrong, magic: IntercomCodec.helperMagic),
      isNull,
    );
  });

  test('voice cleaner drops hiss and tames peaks headed for the pump', () {
    final IntercomVoiceCleaner cleaner = IntercomVoiceCleaner();
    final Uint8List quiet = Uint8List(80);
    final ByteData quietData = ByteData.sublistView(quiet);
    for (int i = 0; i < 40; i++) {
      quietData.setInt16(i * 2, 40, Endian.little);
    }
    final Uint8List gated = cleaner.apply(quiet, softenPeaks: false);
    final ByteData gatedData = ByteData.sublistView(gated);
    expect(gatedData.getInt16(78, Endian.little), 0);

    cleaner.reset();
    final Uint8List loud = Uint8List(2);
    ByteData.sublistView(loud).setInt16(0, 32000, Endian.little);
    final int softened = ByteData.sublistView(
      cleaner.apply(loud, softenPeaks: true),
    ).getInt16(0, Endian.little);
    expect(softened, lessThan(25000));
    expect(softened, greaterThan(18000));

    cleaner.reset();
    final Uint8List mid = Uint8List(2);
    ByteData.sublistView(mid).setInt16(0, 4000, Endian.little);
    final int halved = ByteData.sublistView(
      cleaner.apply(mid, softenPeaks: false, gain: 50),
    ).getInt16(0, Endian.little);
    expect(halved, 2000);

    cleaner.reset();
    final Uint8List quietVoice = Uint8List(2);
    ByteData.sublistView(quietVoice).setInt16(0, 4000, Endian.little);
    final int kept = ByteData.sublistView(
      cleaner.apply(quietVoice, softenPeaks: true, noiseCut: 100),
    ).getInt16(0, Endian.little);
    expect(kept, greaterThan(3000));
  });

  test('office noise cut turns PC hiss down and keeps a loud word', () {
    final IntercomVoiceCleaner cleaner = IntercomVoiceCleaner(
      stationSpeaker: true,
    );
    final Uint8List hiss = Uint8List(128);
    final ByteData hissData = ByteData.sublistView(hiss);
    for (int i = 0; i < 64; i++) {
      hissData.setInt16(i * 2, i.isEven ? 2500 : -2500, Endian.little);
    }
    final int open = ByteData.sublistView(
      cleaner.apply(hiss, softenPeaks: false, noiseCut: 0),
    ).getInt16(64, Endian.little).abs();
    cleaner.reset();
    final int shut = ByteData.sublistView(
      cleaner.apply(hiss, softenPeaks: false, noiseCut: 100),
    ).getInt16(64, Endian.little).abs();
    expect(open, greaterThan(1500));
    expect(shut, lessThan(400));

    cleaner.reset();
    final Uint8List word = Uint8List(128);
    final ByteData wordData = ByteData.sublistView(word);
    for (int i = 0; i < 64; i++) {
      wordData.setInt16(i * 2, i.isEven ? 14000 : -14000, Endian.little);
    }
    final int kept = ByteData.sublistView(
      cleaner.apply(word, softenPeaks: false, noiseCut: 80),
    ).getInt16(64, Endian.little).abs();
    expect(kept, greaterThan(10000));
  });

  test('noise cut pull-down only reduces a hiss and never boosts it', () {
    final Uint8List hiss = Uint8List(128);
    final ByteData raw = ByteData.sublistView(hiss);
    for (int i = 0; i < 64; i++) {
      raw.setInt16(i * 2, i.isEven ? 2500 : -2500, Endian.little);
    }
    final int open = ByteData.sublistView(
      IntercomVoiceCleaner.pullDown(hiss, 0),
    ).getInt16(0, Endian.little).abs();
    final int shut = ByteData.sublistView(
      IntercomVoiceCleaner.pullDown(hiss, 100),
    ).getInt16(32, Endian.little).abs();
    expect(open, 2500);
    expect(shut, lessThan(400));
  });

  test('INTERCOM json is not applied as telemetry', () {
    final List<DispenserTelemetry> live = <DispenserTelemetry>[];
    final List<IntercomNotice> notices = <IntercomNotice>[];
    final DispenserSocketManager sockets = DispenserSocketManager(
      onTelemetry: live.add,
      onOffline: (_) {},
      onIntercomSignal: notices.add,
    );
    const String raw = '{"cmd":"INTERCOM","unit":2,"who":"helper","down":true}';

    expect(TelemetryParser().tryParse(raw), isNotNull);
    sockets.acceptTextForTest(raw, fallbackUnit: 2);

    expect(live, isEmpty);
    expect(notices, hasLength(1));
    expect(notices.single.unitId, 2);
    expect(notices.single.helperDown, isTrue);

    sockets.acceptTextForTest(
      '{"cmd":"HEARTBEAT","unit":2,"telemetry":{"amount":10,"liters":1,"rate":2,"meter":3,"status":"IDLE"}}',
      fallbackUnit: 2,
    );
    expect(live, hasLength(1));
    expect(live.single.unitId, 2);
    expect(live.single.amountPkr, 10);
  });

  test('WIFI_STATUS is not applied as telemetry', () {
    final List<DispenserTelemetry> live = <DispenserTelemetry>[];
    final List<DispenserWifiStatus> wifi = <DispenserWifiStatus>[];
    final DispenserSocketManager sockets = DispenserSocketManager(
      onTelemetry: live.add,
      onOffline: (_) {},
      onWifiStatus: wifi.add,
    );
    const String raw =
        '{"cmd":"WIFI_STATUS","unit":5,"ssid":"Home","ip":"192.168.1.40","dhcp":true}';

    sockets.acceptTextForTest(raw, fallbackUnit: 5);

    expect(live, isEmpty);
    expect(wifi, hasLength(1));
    expect(wifi.single.unitId, 5);
    expect(wifi.single.ip, '192.168.1.40');
    expect(wifi.single.dhcp, isTrue);
  });

  test('speaker test tone lasts at least 5 seconds', () {
    final Uint8List tone = intercomTestTone();

    expect(tone.length, greaterThanOrEqualTo(IntercomCodec.sampleRate * 5 * 2));
    expect(tone.length.isEven, isTrue);
    final ByteData view = ByteData.sublistView(tone);
    expect(view.getInt16(0, Endian.little).abs(), lessThan(500));
    expect(view.getInt16(18, Endian.little).abs(), greaterThan(1000));
  });

  test('16-bit stereo WAV becomes 16 kHz mono PCM', () {
    final Uint8List wav = _wav16(
      sampleRate: 8000,
      channels: 2,
      frames: <List<int>>[
        <int>[1000, -1000],
        <int>[3000, 1000],
      ],
    );

    final Uint8List? pcm = pcm16kFromWav(wav);

    expect(pcm, isNotNull);
    expect(pcm!.length, 8);
    final ByteData view = ByteData.sublistView(pcm);
    expect(view.getInt16(0, Endian.little), 0);
    expect(view.getInt16(4, Endian.little), closeTo(2000, 50));
  });
}

Uint8List _wav16({
  required int sampleRate,
  required int channels,
  required List<List<int>> frames,
}) {
  final int dataBytes = frames.length * channels * 2;
  final Uint8List bytes = Uint8List(44 + dataBytes);
  final ByteData view = ByteData.sublistView(bytes);
  view.setUint32(0, 0x46464952, Endian.little);
  view.setUint32(4, 36 + dataBytes, Endian.little);
  view.setUint32(8, 0x45564157, Endian.little);
  view.setUint32(12, 0x20746d66, Endian.little);
  view.setUint32(16, 16, Endian.little);
  view.setUint16(20, 1, Endian.little);
  view.setUint16(22, channels, Endian.little);
  view.setUint32(24, sampleRate, Endian.little);
  view.setUint32(28, sampleRate * channels * 2, Endian.little);
  view.setUint16(32, channels * 2, Endian.little);
  view.setUint16(34, 16, Endian.little);
  view.setUint32(36, 0x61746164, Endian.little);
  view.setUint32(40, dataBytes, Endian.little);
  int at = 44;
  for (final List<int> frame in frames) {
    for (final int sample in frame) {
      view.setInt16(at, sample, Endian.little);
      at += 2;
    }
  }
  return bytes;
}
