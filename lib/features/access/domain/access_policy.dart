import 'package:flutter/foundation.dart';

import '../../../Shell/shell_navigation.dart';

/// Production interlocks (owner PIN, LIVE-shift sales, ESP, crash recovery).
/// Debug (`flutter run`) stays open so local coding is not blocked.
/// Release / MSIX builds always enforce these guards.
bool get shouldEnforceStationGuards => !kDebugMode;

/// Owner Master PIN gate, Lock Owner Access, and idle auto-lock.
/// Always on in the release MSIX so client demos include the lock workflow.
bool get shouldEnforceOwnerAccessLock => !kDebugMode;

/// Manager-first, owner-elevated destination policy.
///
/// Sale and Customers (Udhaar) stay unlocked for the on-duty manager.
/// Every other shell destination requires [isOwnerElevated].
class AccessPolicy {
  AccessPolicy._();

  static const Set<int> managerUnlockedDestinations = <int>{
    ShellDestinations.sale,
    ShellDestinations.customers,
  };

  static bool isManagerUnlockedDestination(int index) {
    return managerUnlockedDestinations.contains(index);
  }

  static bool destinationRequiresOwner(int index) {
    return !isManagerUnlockedDestination(index);
  }
}

/// Idle timeout for owner elevation. `0` disables auto-lock.
class OwnerAutoLockMinutes {
  OwnerAutoLockMinutes._();

  static const int off = 0;
  static const int defaultMinutes = 5;
  static const List<int> choices = <int>[off, 1, 2, 5, 10, 15, 30];

  static String label(int minutes) {
    if (minutes <= 0) {
      return 'Off';
    }
    if (minutes == 1) {
      return '1 minute';
    }
    return '$minutes minutes';
  }

  static int sanitize(int? minutes) {
    if (minutes != null && choices.contains(minutes)) {
      return minutes;
    }
    return defaultMinutes;
  }

  static int parse(String? raw) {
    return sanitize(int.tryParse(raw?.trim() ?? ''));
  }
}

enum MasterPinChangeOutcome {
  success,
  invalidCurrent,
  invalidNew,
  mismatch,
  failed,
}

class MasterPinChangeResult {
  const MasterPinChangeResult({required this.outcome, this.message});

  final MasterPinChangeOutcome outcome;
  final String? message;

  bool get isSuccess => outcome == MasterPinChangeOutcome.success;
}

/// Pure validation for the Settings Master PIN form.
class MasterPinChangeInput {
  MasterPinChangeInput._();

  static String? validate({
    required String currentPin,
    required String newPin,
    required String confirmPin,
    required bool Function(String pin) isValidPlainPin,
    required int minPinLength,
    required int maxPinLength,
  }) {
    final String current = currentPin.trim();
    final String next = newPin.trim();
    final String confirm = confirmPin.trim();
    if (!isValidPlainPin(current)) {
      return 'Current Master PIN must be $minPinLength–$maxPinLength digits.';
    }
    if (!isValidPlainPin(next)) {
      return 'New Master PIN must be $minPinLength–$maxPinLength digits.';
    }
    if (next != confirm) {
      return 'New Master PIN and confirmation do not match.';
    }
    return null;
  }
}
