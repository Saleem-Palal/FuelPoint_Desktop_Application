import 'package:flutter_test/flutter_test.dart';

import 'package:fuel_dispenser/features/station/domain/dispenser_models.dart';

void main() {
  group('resolveAccountSplit tender columns', () {
    test('cash-only fills Cash and leaves Account empty', () {
      final split = resolveAccountSplit(
        payment: PaymentMethod.cash,
        saleAmount: 2989,
        cashNow: 0,
      );
      expect(split.payment, PaymentMethod.cash);
      expect(split.cashAmount, 2989);
      expect(split.accountAmount, 0);
    });

    test('udhaar leaves Cash and Account empty', () {
      final split = resolveAccountSplit(
        payment: PaymentMethod.udhaar,
        saleAmount: 5000,
        cashNow: 200,
      );
      expect(split.payment, PaymentMethod.udhaar);
      expect(split.cashAmount, 0);
      expect(split.accountAmount, 0);
    });

    test('partial account puts Cash Now in Cash and remainder in Account', () {
      final split = resolveAccountSplit(
        payment: PaymentMethod.bankAccount,
        saleAmount: 2989,
        cashNow: 2000,
      );
      expect(split.payment, PaymentMethod.bankAccount);
      expect(split.cashAmount, 2000);
      expect(split.accountAmount, 989);
    });

    test('full cash-now on account becomes a cash ticket', () {
      final split = resolveAccountSplit(
        payment: PaymentMethod.easyPaisa,
        saleAmount: 1000,
        cashNow: 1000,
      );
      expect(split.payment, PaymentMethod.cash);
      expect(split.cashAmount, 1000);
      expect(split.accountAmount, 0);
    });

    test('pending bank remainder is not credited until confirm', () {
      final held = accountPersistSplit(
        payment: PaymentMethod.bankAccount,
        cashAmount: 2000,
        accountAmount: 989,
      );
      expect(held.cashAmount, 2000);
      expect(held.accountAmount, 0);
      expect(held.pendingAccountAmount, 989);
    });
  });

  group('resolvePendingAccountConfirm', () {
    test('a zero account remainder becomes a cash ticket', () {
      final confirmed = resolvePendingAccountConfirm(
        payment: PaymentMethod.bankAccount,
        saleAmount: 2989,
        cashAmount: 2989,
      );
      expect(confirmed.payment, PaymentMethod.cash);
      expect(confirmed.cashAmount, 2989);
      expect(confirmed.accountAmount, 0);
    });

    test('a partial account keeps the original bank method', () {
      final confirmed = resolvePendingAccountConfirm(
        payment: PaymentMethod.easyPaisa,
        saleAmount: 2989,
        cashAmount: 2000,
      );
      expect(confirmed.payment, PaymentMethod.easyPaisa);
      expect(confirmed.cashAmount, 2000);
      expect(confirmed.accountAmount, 989);
    });

    test('cash above the ticket is cut down to the sale', () {
      final confirmed = resolvePendingAccountConfirm(
        payment: PaymentMethod.bankAccount,
        saleAmount: 1000,
        cashAmount: 5000,
      );
      expect(confirmed.payment, PaymentMethod.cash);
      expect(confirmed.cashAmount, 1000);
      expect(confirmed.accountAmount, 0);
    });
  });

  group('saleTenderNeedsUpdate', () {
    SaleTransaction cashHangup() {
      return SaleTransaction(
        tokenNo: 100001,
        unitId: 1,
        fuelType: kDieselFuelType,
        amountPkr: 2989,
        volumeLiters: 10,
        rate: 298.9,
        meterCount: 1,
        timestamp: DateTime(2026, 9, 15),
        payment: PaymentMethod.cash,
        customerName: 'Walk-in',
        cashAmount: 2989,
      );
    }

    test('cash hang-up row is unchanged when Confirm stays cash Walk-in', () {
      expect(
        saleTenderNeedsUpdate(
          saved: cashHangup(),
          payment: PaymentMethod.cash,
          customerName: '',
          vehicleNo: '',
          cashAmount: 2989,
          accountAmount: 0,
        ),
        isFalse,
      );
    });

    test('Confirm rewrites the saved row when payment method changes', () {
      expect(
        saleTenderNeedsUpdate(
          saved: cashHangup(),
          payment: PaymentMethod.udhaar,
          customerName: 'Ali',
          vehicleNo: 'ABC-1',
          cashAmount: 0,
          accountAmount: 0,
        ),
        isTrue,
      );
      expect(
        saleTenderNeedsUpdate(
          saved: cashHangup(),
          payment: PaymentMethod.bankAccount,
          customerName: '',
          vehicleNo: '',
          cashAmount: 2000,
          accountAmount: 989,
        ),
        isTrue,
      );
    });
  });
}
