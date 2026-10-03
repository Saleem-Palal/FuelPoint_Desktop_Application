import 'package:flutter_test/flutter_test.dart';

import 'package:fuel_dispenser/features/station/domain/sale_fulfillment.dart';

void main() {
  group('isVehicleRegistrationValid', () {
    test('requires both letters and digits in any order', () {
      expect(isVehicleRegistrationValid('123ABC'), isTrue);
      expect(isVehicleRegistrationValid('123-ABC'), isTrue);
      expect(isVehicleRegistrationValid('123 ABC'), isTrue);
      expect(isVehicleRegistrationValid('1234 abcde 23'), isTrue);
      expect(isVehicleRegistrationValid('1 Drum'), isTrue);
      expect(isVehicleRegistrationValid('1 Jharikan'), isTrue);
      expect(isVehicleRegistrationValid('2 Cans.'), isTrue);
    });

    test('rejects letters-only, digits-only, and empty', () {
      expect(isVehicleRegistrationValid(''), isFalse);
      expect(isVehicleRegistrationValid('   '), isFalse);
      expect(isVehicleRegistrationValid('12'), isFalse);
      expect(isVehicleRegistrationValid('ABC'), isFalse);
      expect(isVehicleRegistrationValid('0000'), isFalse);
    });

    test('persistVehicleNo uppercases and strips other punctuation', () {
      expect(persistVehicleNo('123 abc'), '123 ABC');
      expect(persistVehicleNo('2 Cans.'), '2 CANS');
      expect(persistVehicleNo('12'), '');
    });
  });
}
