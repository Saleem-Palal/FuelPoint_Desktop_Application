import 'package:flutter_test/flutter_test.dart';

import 'package:fuel_dispenser/features/customer/domain/customer_models.dart';

void main() {
  test('settlement proof survives a Windows receipt_proofs path', () {
    const String path =
        r'C:\FuelPointData\receipt_proofs\proof_100001_20261024_231000.jpg';
    final String encoded = encodeSettlementDescription(
      receiptNo: 'REC-0012',
      paymentMode: SettlementPaymentMode.bankTransfer,
      cashAmountPkr: 200,
      accountAmountPkr: 800,
      notes: 'slip 44',
      cashierName: 'Amir',
      proofImagePath: path,
    );
    final SettlementTender parsed = parseSettlementDescription(
      encoded,
      paidPkr: 1000,
    );
    expect(parsed.receiptNo, 'REC-0012');
    expect(parsed.paymentMode, SettlementPaymentMode.bankTransfer);
    expect(parsed.cashAmountPkr, 200);
    expect(parsed.accountAmountPkr, 800);
    expect(parsed.cashierName, 'Amir');
    expect(parsed.notes, 'slip 44');
    expect(parsed.proofImagePath, path);
  });

  test('settlement proof is the last field when notes are empty', () {
    const String path =
        r'C:\FuelPointData\receipt_proofs\proof_100002_20261024_231100.jpg';
    final String encoded = encodeSettlementDescription(
      receiptNo: 'REC-0013',
      paymentMode: SettlementPaymentMode.easyPaisa,
      cashAmountPkr: 0,
      accountAmountPkr: 500,
      proofImagePath: path,
    );
    final SettlementTender parsed = parseSettlementDescription(
      encoded,
      paidPkr: 500,
    );
    expect(parsed.proofImagePath, path);
    expect(parsed.notes, isEmpty);
  });

  test('settlementFromLedgerRow prefers the proof column', () {
    final UnifiedUdhaarRow row = UnifiedUdhaarRow(
      primaryKey: '0100/01-02',
      type: UnifiedUdhaarType.settlement,
      at: DateTime(2026, 10, 24, 12),
      customerName: 'Ahmad',
      customerId: '01',
      amountPkr: 500,
      remainingPkr: 0,
      description: encodeSettlementDescription(
        receiptNo: 'REC-0001',
        paymentMode: SettlementPaymentMode.cash,
        cashAmountPkr: 500,
        accountAmountPkr: 0,
        proofImagePath: r'D:\old.jpg',
      ),
      proofImagePath: r'C:\FuelPointData\receipt_proofs\new.jpg',
    );
    final CustomerSettlement settlement = settlementFromLedgerRow(row);
    expect(
      settlement.proofImagePath,
      r'C:\FuelPointData\receipt_proofs\new.jpg',
    );
    expect(settlement.ledgerId, '0100/01-02');
  });
}
