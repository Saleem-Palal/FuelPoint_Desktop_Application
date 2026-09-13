import 'package:flutter_test/flutter_test.dart';

import 'package:fuel_dispenser/Shell/shell_navigation.dart';
import 'package:fuel_dispenser/core/security/pin_hasher.dart';
import 'package:fuel_dispenser/features/access/domain/access_policy.dart';

void main() {
  group('AccessPolicy', () {
    test(
      'locks owner-only screens and keeps sale and customers open',
      () {
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
        expect(
          AccessPolicy.destinationRequiresOwner(ShellDestinations.shifts),
          isTrue,
        );
      },
    );

    test('keeps sale and customers unlocked; shifts requires owner', () {
      expect(
        AccessPolicy.isManagerUnlockedDestination(ShellDestinations.sale),
        isTrue,
      );
      expect(
        AccessPolicy.isManagerUnlockedDestination(ShellDestinations.customers),
        isTrue,
      );
      expect(
        AccessPolicy.isManagerUnlockedDestination(ShellDestinations.shifts),
        isFalse,
      );
      expect(
        AccessPolicy.destinationRequiresOwner(ShellDestinations.sale),
        isFalse,
      );
      expect(
        AccessPolicy.destinationRequiresOwner(ShellDestinations.customers),
        isFalse,
      );
      expect(
        AccessPolicy.destinationRequiresOwner(ShellDestinations.shifts),
        isTrue,
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

  test('default owner auto-lock is 5 minutes', () {
    expect(OwnerAutoLockMinutes.defaultMinutes, 5);
    expect(OwnerAutoLockMinutes.sanitize(null), 5);
    expect(OwnerAutoLockMinutes.sanitize(7), 5);
    expect(OwnerAutoLockMinutes.parse('5'), 5);
    expect(OwnerAutoLockMinutes.parse('0'), OwnerAutoLockMinutes.off);
    expect(OwnerAutoLockMinutes.label(5), '5 minutes');
    expect(OwnerAutoLockMinutes.label(0), 'Off');
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
