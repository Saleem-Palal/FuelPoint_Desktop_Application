import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/pin_hasher.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/database_helper.dart';
import '../domain/access_policy.dart';

@immutable
class AccessState {
  const AccessState({
    required this.isOwnerElevated,
    required this.busy,
    this.errorMessage,
  });

  /// In-memory owner elevation. Never persisted; defaults to locked.
  final bool isOwnerElevated;
  final bool busy;
  final String? errorMessage;

  AccessState copyWith({
    bool? isOwnerElevated,
    bool? busy,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AccessState(
      isOwnerElevated: isOwnerElevated ?? this.isOwnerElevated,
      busy: busy ?? this.busy,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  static AccessState locked() {
    return const AccessState(isOwnerElevated: false, busy: false);
  }
}

/// Owner Master PIN verification and elevation. Manager session stays active.
class AccessController extends Notifier<AccessState> {
  final DatabaseHelper _db = DatabaseHelper.instance;

  @override
  AccessState build() {
    return AccessState.locked();
  }

  void _syncAuthElevation(bool elevated) {
    ref.read(authProvider.notifier).setOwnerElevated(elevated);
  }

  /// Sets [isOwnerElevated] to false. Caller navigates back to Sales.
  void lockOwnerAccess() {
    state = state.copyWith(
      isOwnerElevated: false,
      busy: false,
      clearError: true,
    );
    _syncAuthElevation(false);
    debugPrint('Access: owner access locked');
  }

  /// Verifies [rawPin] against SHA-256 `app_settings.owner_master_pin_hash`.
  Future<bool> verifyOwnerMasterPin(String rawPin) async {
    final String pin = rawPin.trim();
    if (!PinHasher.isValidPlainPin(pin)) {
      state = state.copyWith(
        errorMessage:
            'Master PIN must be ${PinHasher.minPinLength}–${PinHasher.maxPinLength} digits.',
      );
      return false;
    }

    state = state.copyWith(busy: true, clearError: true);
    try {
      final String stored = await _db.readOwnerMasterPinHash();
      final bool ok = PinHasher.matches(entered: pin, stored: stored);
      if (!ok) {
        state = state.copyWith(
          busy: false,
          errorMessage: 'Incorrect Master PIN. Try again.',
        );
        return false;
      }
      state = state.copyWith(
        busy: false,
        isOwnerElevated: true,
        clearError: true,
      );
      _syncAuthElevation(true);
      debugPrint('Access: owner elevated');
      return true;
    } catch (error, stack) {
      debugPrint(
        'AccessController.verifyOwnerMasterPin failed: $error\n$stack',
      );
      state = state.copyWith(
        busy: false,
        errorMessage: 'Could not verify Master PIN. $error',
      );
      return false;
    }
  }

  /// Hashes [newPin] with SHA-256 and writes `owner_master_pin_hash`.
  Future<MasterPinChangeResult> changeMasterPin({
    required String currentPin,
    required String newPin,
    required String confirmPin,
  }) async {
    final String? inputError = MasterPinChangeInput.validate(
      currentPin: currentPin,
      newPin: newPin,
      confirmPin: confirmPin,
      isValidPlainPin: PinHasher.isValidPlainPin,
      minPinLength: PinHasher.minPinLength,
      maxPinLength: PinHasher.maxPinLength,
    );
    if (inputError != null) {
      final MasterPinChangeOutcome outcome;
      if (inputError.contains('Current')) {
        outcome = MasterPinChangeOutcome.invalidCurrent;
      } else if (inputError.contains('confirmation')) {
        outcome = MasterPinChangeOutcome.mismatch;
      } else {
        outcome = MasterPinChangeOutcome.invalidNew;
      }
      return MasterPinChangeResult(outcome: outcome, message: inputError);
    }

    state = state.copyWith(busy: true, clearError: true);
    try {
      final String stored = await _db.readOwnerMasterPinHash();
      final bool currentOk = PinHasher.matches(
        entered: currentPin.trim(),
        stored: stored,
      );
      if (!currentOk) {
        state = state.copyWith(busy: false);
        return const MasterPinChangeResult(
          outcome: MasterPinChangeOutcome.invalidCurrent,
          message: 'Current Master PIN is incorrect.',
        );
      }

      await _db.writeOwnerMasterPinHash(PinHasher.hash(newPin.trim()));
      state = state.copyWith(busy: false, clearError: true);
      debugPrint('Access: owner Master PIN updated');
      return const MasterPinChangeResult(
        outcome: MasterPinChangeOutcome.success,
        message: 'Master PIN updated.',
      );
    } catch (error, stack) {
      debugPrint('AccessController.changeMasterPin failed: $error\n$stack');
      state = state.copyWith(busy: false);
      return MasterPinChangeResult(
        outcome: MasterPinChangeOutcome.failed,
        message: 'Could not update Master PIN. $error',
      );
    }
  }
}

final accessControllerProvider =
    NotifierProvider<AccessController, AccessState>(AccessController.new);
