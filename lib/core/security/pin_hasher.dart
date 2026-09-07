import 'dart:convert';

import 'package:crypto/crypto.dart';

/// SHA-256 PIN hashing for SQLite `managers.pin`.
///
/// Legacy plaintext PINs (4–6 digits) still verify until the next write
/// upgrades them. Already-hashed 64-char hex values are never re-hashed.
class PinHasher {
  PinHasher._();

  static const int digestLength = 64;
  static const int minPinLength = 4;
  static const int maxPinLength = 6;

  static final RegExp _hex = RegExp(r'^[0-9a-f]+$');
  static final RegExp _digits = RegExp(r'^\d+$');

  static String hash(String pin) {
    return sha256.convert(utf8.encode(pin.trim())).toString();
  }

  static bool looksHashed(String value) {
    final String trimmed = value.trim();
    return trimmed.length == digestLength && _hex.hasMatch(trimmed);
  }

  /// Hash plaintext; leave an existing SHA-256 digest unchanged.
  static String hashIfPlain(String pin) {
    final String trimmed = pin.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Manager PIN is required');
    }
    if (looksHashed(trimmed)) {
      return trimmed;
    }
    return hash(trimmed);
  }

  static bool isValidPlainPin(String pin) {
    final String trimmed = pin.trim();
    return trimmed.length >= minPinLength &&
        trimmed.length <= maxPinLength &&
        _digits.hasMatch(trimmed);
  }

  /// Verifies [entered] against a stored digest or leftover plaintext PIN.
  static bool matches({required String entered, required String stored}) {
    final String resolvedStored = stored.trim();
    final String resolvedEntered = entered.trim();
    if (resolvedStored.isEmpty || resolvedEntered.isEmpty) {
      return false;
    }
    if (looksHashed(resolvedStored)) {
      return _constantTimeEquals(hash(resolvedEntered), resolvedStored);
    }
    return _constantTimeEquals(resolvedEntered, resolvedStored);
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) {
      return false;
    }
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
