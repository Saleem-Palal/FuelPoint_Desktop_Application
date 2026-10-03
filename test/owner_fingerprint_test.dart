import 'package:flutter_test/flutter_test.dart';

import 'package:fuel_dispenser/features/access/domain/fingerprint_protocol.dart';

void main() {
  test('unlock allows a shifted finger press', () {
    expect(FingerprintProtocol.matchThreshold, 1073741);
    expect(FingerprintProtocol.enrollScanCount, 4);
    expect(FingerprintProtocol.operatorPinFallbackAfterMisses, 3);
    expect(
      FingerprintProtocol.incorrectFingerprint(
        match: false,
        score: 0,
        message: '',
      ),
      isFalse,
    );
    expect(
      FingerprintProtocol.incorrectFingerprint(
        match: false,
        score: 12,
        message: '',
      ),
      isTrue,
    );
    expect(
      FingerprintProtocol.fingerprintMismatchNote('miss 2 of 3'),
      'Fingerprint did not match. Try again.',
    );
  });

  test('parses helper READY line', () {
    expect(
      FingerprintProtocol.parseReadyPort('READY 127.0.0.1:58311'),
      58311,
    );
    expect(FingerprintProtocol.parseReadyPort('HELPER_BUSY'), isNull);
    expect(FingerprintProtocol.parseReadyPort('READY 10.0.0.1:80'), isNull);
  });

  test('busy codes keep Master PIN as the fallback message', () {
    expect(
      FingerprintProtocol.userMessage(code: 'DP_DEVICE_BUSY'),
      contains('Master PIN'),
    );
    expect(
      FingerprintProtocol.userMessage(code: FingerprintProtocol.helperBusy),
      contains('Settings > Cameras'),
    );
    expect(
      FingerprintProtocol.userMessage(
        code: 'DEVICE_BUSY',
        message: 'Close Settings > Cameras and try again.',
      ),
      'Close Settings > Cameras and try again.',
    );
  });
}
