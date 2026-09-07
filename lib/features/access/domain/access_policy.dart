import '../../../Shell/shell_navigation.dart';

/// Manager-first, owner-elevated destination policy.
///
/// Only Sales and Customers stay unlocked for the on-duty manager. Every
/// other shell destination requires [isOwnerElevated].
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
