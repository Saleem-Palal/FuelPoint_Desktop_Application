import 'package:flutter_test/flutter_test.dart';

import 'package:fuel_dispenser/Shell/shell_navigation.dart';
import 'package:fuel_dispenser/core/security/pin_hasher.dart';
import 'package:fuel_dispenser/features/access/domain/access_policy.dart';

void main() {
  group('AccessPolicy', () {
    test('locks every screen except sales and customers', () {
      expect(
        AccessPolicy.destinationRequiresOwner(ShellDestinations.dashboard),
        isTrue,
      );
      expect(
        AccessPolicy.destinationRequiresOwner(ShellDestinations.purchase),
        isTrue,
      );
      expect(
        AccessPolicy.destinationRequiresOwner(ShellDestinations.ledger),
        isTrue,
      );
      expect(
        AccessPolicy.destinationRequiresOwner(ShellDestinations.reports),
        isTrue,
      );
      expect(
        AccessPolicy.destinationRequiresOwner(ShellDestinations.shifts),
        isTrue,
      );
      expect(
        AccessPolicy.destinationRequiresOwner(
          ShellDestinations.dispenserMonitor,
        ),
        isTrue,
      );
      expect(
        AccessPolicy.destinationRequiresOwner(ShellDestinations.settings),
        isTrue,
      );
      expect(
        AccessPolicy.destinationRequiresOwner(ShellDestinations.managers),
        isTrue,
      );
    });

    test('keeps sales and customers unlocked', () {
      expect(
        AccessPolicy.isManagerUnlockedDestination(ShellDestinations.sale),
        isTrue,
      );
      expect(
        AccessPolicy.isManagerUnlockedDestination(ShellDestinations.customers),
        isTrue,
      );
      expect(
        AccessPolicy.destinationRequiresOwner(ShellDestinations.sale),
        isFalse,
      );
      expect(
        AccessPolicy.destinationRequiresOwner(ShellDestinations.customers),
        isFalse,
      );
    });
  });

  group('MasterPinChangeInput', () {
    test('rejects short current PIN', () {
      expect(
        MasterPinChangeInput.validate(
          currentPin: '12',
          newPin: '5678',
          confirmPin: '5678',
          isValidPlainPin: PinHasher.isValidPlainPin,
          minPinLength: PinHasher.minPinLength,
          maxPinLength: PinHasher.maxPinLength,
        ),
        contains('Current Master PIN'),
      );
    });

    test('rejects mismatched confirmation', () {
      expect(
        MasterPinChangeInput.validate(
          currentPin: '1234',
          newPin: '5678',
          confirmPin: '5679',
          isValidPlainPin: PinHasher.isValidPlainPin,
          minPinLength: PinHasher.minPinLength,
          maxPinLength: PinHasher.maxPinLength,
        ),
        contains('confirmation'),
      );
    });

    test('accepts matching 4–6 digit PINs', () {
      expect(
        MasterPinChangeInput.validate(
          currentPin: '1234',
          newPin: '567890',
          confirmPin: '567890',
          isValidPlainPin: PinHasher.isValidPlainPin,
          minPinLength: PinHasher.minPinLength,
          maxPinLength: PinHasher.maxPinLength,
        ),
        isNull,
      );
    });
  });

  test('default owner PIN hashes with SHA-256', () {
    expect(PinHasher.hash('1234').length, PinHasher.digestLength);
    expect(
      PinHasher.matches(entered: '1234', stored: PinHasher.hash('1234')),
      isTrue,
    );
    expect(
      PinHasher.matches(entered: '0000', stored: PinHasher.hash('1234')),
      isFalse,
    );
  });
}
