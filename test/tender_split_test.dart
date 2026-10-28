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

    test('udhaar keeps the cash and account slices', () {
      final split = resolveAccountSplit(
        payment: PaymentMethod.udhaar,
        saleAmount: 3945,
        cashNow: 1000,
        accountNow: 1500,
      );
      expect(split.payment, PaymentMethod.udhaar);
      expect(split.cashAmount, 1000);
      expect(split.accountAmount, 1500);
      expect(
        udhaarCreditRupees(
          saleAmount: 3945,
          cashAmount: split.cashAmount,
          accountAmount: split.accountAmount,
        ),
        1445,
      );
    });

    test('udhaar keeps typed Cash and Account slices', () {
      final split = resolveAccountSplit(
        payment: PaymentMethod.udhaar,
        saleAmount: 5000,
        cashNow: 200,
        accountNow: 300,
      );
      expect(split.payment, PaymentMethod.udhaar);
      expect(split.cashAmount, 200);
      expect(split.accountAmount, 300);
    });

    test('udhaar with empty slices still credits the whole ticket', () {
      expect(
        udhaarCreditRupees(saleAmount: 5000, cashAmount: 0, accountAmount: 0),
        5000,
      );
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

    test('account above the ticket stores the received Account amount', () {
      final split = resolveAccountSplit(
        payment: PaymentMethod.bankAccount,
        saleAmount: 8000,
        cashNow: 0,
        accountNow: 10000,
      );
      expect(split.payment, PaymentMethod.bankAccount);
      expect(split.cashAmount, 0);
      expect(split.accountAmount, 10000);
      expect(accountOverpayBaqaya(saleAmount: 8000, accountNow: 10000), 2000);
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

    test('udhaar account slice waits in pending until proof confirm', () {
      final held = accountPersistSplit(
        payment: PaymentMethod.udhaar,
        cashAmount: 200,
        accountAmount: 300,
      );
      expect(held.cashAmount, 200);
      expect(held.accountAmount, 0);
      expect(held.pendingAccountAmount, 300);
      final SaleTransaction txn = SaleTransaction(
        tokenNo: 300001,
        unitId: 1,
        fuelType: kDieselFuelType,
        amountPkr: 1000,
        volumeLiters: 4,
        rate: 250,
        meterCount: 1,
        timestamp: DateTime(2026, 10, 23),
        payment: PaymentMethod.udhaar,
        cashAmount: 200,
        pendingAccountAmount: 300,
      );
      expect(txn.isAccountPending, isTrue);
      expect(txn.needsAccountProof, isTrue);
    });

    test('edit that changes Account holds the slice in pending', () {
      final SaleTransaction saved = SaleTransaction(
        tokenNo: 400001,
        unitId: 1,
        fuelType: kDieselFuelType,
        amountPkr: 1000,
        volumeLiters: 4,
        rate: 250,
        meterCount: 1,
        timestamp: DateTime(2026, 10, 24),
        payment: PaymentMethod.easyPaisa,
        cashAmount: 0,
        accountAmount: 1000,
        proofImagePath: r'C:\FuelPointData\receipt_proofs\a.jpg',
      );
      final held = editedAccountPersistSplit(
        saved: saved,
        payment: PaymentMethod.easyPaisa,
        cashAmount: 200,
        accountAmount: 800,
      );
      expect(held.cashAmount, 200);
      expect(held.accountAmount, 0);
      expect(held.pendingAccountAmount, 800);
      expect(held.clearProof, isTrue);
    });

    test('edit that only changes vehicle keeps credited Account', () {
      final SaleTransaction saved = SaleTransaction(
        tokenNo: 400002,
        unitId: 1,
        fuelType: kDieselFuelType,
        amountPkr: 1000,
        volumeLiters: 4,
        rate: 250,
        meterCount: 1,
        timestamp: DateTime(2026, 10, 24),
        payment: PaymentMethod.bankAccount,
        cashAmount: 400,
        accountAmount: 600,
        proofImagePath: r'C:\FuelPointData\receipt_proofs\a.jpg',
      );
      final held = editedAccountPersistSplit(
        saved: saved,
        payment: PaymentMethod.bankAccount,
        cashAmount: 400,
        accountAmount: 600,
      );
      expect(held.cashAmount, 400);
      expect(held.accountAmount, 600);
      expect(held.pendingAccountAmount, 0);
      expect(held.clearProof, isFalse);
    });

    test('edit cash to Udhaar with Account sends that slice to pending', () {
      final SaleTransaction saved = SaleTransaction(
        tokenNo: 400003,
        unitId: 1,
        fuelType: kDieselFuelType,
        amountPkr: 5000,
        volumeLiters: 20,
        rate: 250,
        meterCount: 1,
        timestamp: DateTime(2026, 10, 24),
        payment: PaymentMethod.cash,
        cashAmount: 5000,
      );
      final held = editedAccountPersistSplit(
        saved: saved,
        payment: PaymentMethod.udhaar,
        cashAmount: 200,
        accountAmount: 300,
      );
      expect(held.cashAmount, 200);
      expect(held.accountAmount, 0);
      expect(held.pendingAccountAmount, 300);
      expect(held.clearProof, isTrue);
    });

    test('last-10 Udhaar recover holds Account as pending for proof', () {
      final split = resolveAccountSplit(
        payment: PaymentMethod.udhaar,
        saleAmount: 5000,
        cashNow: 200,
        accountNow: 300,
      );
      final held = accountPersistSplit(
        payment: split.payment,
        cashAmount: split.cashAmount,
        accountAmount: split.accountAmount,
      );
      expect(split.payment, PaymentMethod.udhaar);
      expect(held.cashAmount, 200);
      expect(held.accountAmount, 0);
      expect(held.pendingAccountAmount, 300);
      expect(
        udhaarCreditRupees(
          saleAmount: 5000,
          cashAmount: held.cashAmount,
          accountAmount: held.accountAmount + held.pendingAccountAmount,
        ),
        4500,
      );
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

    test('account received above the ticket stays credited on confirm', () {
      final confirmed = resolvePendingAccountConfirm(
        payment: PaymentMethod.bankAccount,
        saleAmount: 8000,
        cashAmount: 0,
        pendingAccountAmount: 10000,
      );
      expect(confirmed.payment, PaymentMethod.bankAccount);
      expect(confirmed.cashAmount, 0);
      expect(confirmed.accountAmount, 10000);
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
