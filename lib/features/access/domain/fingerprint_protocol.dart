/// Wire protocol shared by the U.are.U helper and Flutter (no raw images).
class FingerprintProtocol {
  FingerprintProtocol._();

  /// Owner unlock dissimilarity limit. Looser than 1 in 100,000 so a finger
  /// that is a little shifted from the enrollment press still matches.
  static const int matchThreshold = 0x7fffffff ~/ 2000;
  static const int enrollScanCount = 4;

  /// Operator PIN field stays hidden until this many real mismatches.
  static const int operatorPinFallbackAfterMisses = 3;
  static const int defaultCaptureTimeoutMs = 15000;
  static const String readyPrefix = 'READY 127.0.0.1:';
  static const String helperBusy = 'HELPER_BUSY';
  static const String exeName = 'fingerprint_helper.exe';

  /// A timeout with no finger is not a miss. A scored or messaged reject is.
  static bool incorrectFingerprint({
    required bool match,
    required int score,
    String? message,
  }) {
    if (match) {
      return false;
    }
    if ((message ?? '').trim().isNotEmpty) {
      return true;
    }
    return score > 0;
  }

  /// Failure copy only. Attempt totals stay off the screen.
  static String fingerprintMismatchNote(String? helper) {
    final String hint = (helper ?? '').trim();
    if (hint.isEmpty || RegExp(r'\d').hasMatch(hint)) {
      return 'Fingerprint did not match. Try again.';
    }
    return hint;
  }

  static int? parseReadyPort(String line) {
    final String trimmed = line.trim();
    if (!trimmed.startsWith(readyPrefix)) {
      return null;
    }
    return int.tryParse(trimmed.substring(readyPrefix.length));
  }

  static String userMessage({required String code, String? message}) {
    final String trimmed = (message ?? '').trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
    switch (code) {
      case 'DEVICE_BUSY':
      case 'DP_DEVICE_BUSY':
      case helperBusy:
        return 'Reader is in use. Close Settings > Cameras and try again, '
            'or use the Master PIN.';
      case 'NO_READER':
      case 'DP_INVALID_DEVICE':
        return 'Fingerprint reader is not connected.';
      case 'DP_QUALITY_TIMED_OUT':
      case 'FINGER_PRESENT':
        return 'Lift your finger completely, then place it flat and hold still.';
      case 'NO_TEMPLATE':
        return 'No owner fingerprint is enrolled.';
      default:
        return 'Fingerprint reader error.';
    }
  }
}

class FingerprintHealth {
  const FingerprintHealth({
    required this.readerCount,
    required this.readerName,
    required this.vendorId,
    required this.productId,
  });

  final int readerCount;
  final String readerName;
  final int vendorId;
  final int productId;

  bool get hasReader => readerCount > 0;
}

class FingerprintVerifyResult {
  const FingerprintVerifyResult({
    required this.match,
    required this.score,
    this.message,
  });

  final bool match;
  final int score;
  final String? message;
}

class FingerprintHelperException implements Exception {
  const FingerprintHelperException({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String toString() => message;
}
