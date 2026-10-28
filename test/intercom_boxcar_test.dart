import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_dispenser/features/station/data/intercom_boxcar.dart';

void main() {
  test('48 kHz audio averages down to 16 kHz', () {
    final IntercomBoxcar boxcar = IntercomBoxcar();
    final Float64List input = Float64List(48);
    for (int i = 0; i < input.length; i++) {
      input[i] = 0.5;
    }
    boxcar.add(input, 48000);
    final Uint8List? chunk = boxcar.takeChunk(16);
    expect(chunk, isNotNull);
    final ByteData view = ByteData.sublistView(chunk!);
    for (int i = 0; i < 16; i++) {
      expect(view.getInt16(i * 2, Endian.little), 16383);
    }
    expect(boxcar.takeChunk(1), isNull);
  });

  test('three input samples become one averaged sample', () {
    final IntercomBoxcar boxcar = IntercomBoxcar();
    boxcar.add(const <double>[0, 0, 1], 48000);
    final Uint8List? chunk = boxcar.takeChunk(1);
    expect(chunk, isNotNull);
    expect(ByteData.sublistView(chunk!).getInt16(0, Endian.little), 10922);
  });

  test('a short tail is kept until the next block arrives', () {
    final IntercomBoxcar boxcar = IntercomBoxcar();
    boxcar.add(const <double>[1, 1], 48000);
    expect(boxcar.takeChunk(1), isNull);
    boxcar.add(const <double>[1], 48000);
    final Uint8List? chunk = boxcar.takeChunk(1);
    expect(chunk, isNotNull);
    expect(ByteData.sublistView(chunk!).getInt16(0, Endian.little), 32767);
  });
}
