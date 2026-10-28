import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_dispenser/core/pdf_sheet.dart';
import 'package:fuel_dispenser/features/customer/domain/customer_models.dart';
import 'package:fuel_dispenser/features/shift/data/shift_summary_export.dart';
import 'package:fuel_dispenser/features/shift/domain/shift_models.dart';
import 'package:fuel_dispenser/features/station/data/ledger_pdf_export.dart';
import 'package:fuel_dispenser/features/station/data/transaction_store.dart';
import 'package:fuel_dispenser/features/station/domain/dispenser_models.dart';
import 'package:pdf/pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('shift summary PDF finishes for a full shift', () async {
    final DateTime start = DateTime(2026, 10, 5, 6);
    final List<HelperSaleRecord> sales = <HelperSaleRecord>[
      for (int i = 0; i < 90; i++)
        HelperSaleRecord(
          tokenNo: 5000 + i,
          timestamp: start.add(Duration(minutes: i)),
          helperId: 'h1',
          helperName: 'Ali',
          unitId: (i % 2) + 1,
          fuelType: 'Petrol',
          volumeLiters: 4.5,
          rate: 267.89,
          amountPkr: 1200,
          payment: i.isEven ? PaymentMethod.cash : PaymentMethod.udhaar,
          cashAmount: i.isEven ? 1200 : 0,
          openingMeter: 10000 + i * 4.5,
          closingMeter: 10004.5 + i * 4.5,
          customerName: i == 3
              ? 'Ahmad Khan'
              : 'Walk-in Customer $i with a long note',
          vehicleNo: 'LEA-${1000 + i}',
          cashierName: 'Latif',
        ),
    ];
    final List<HelperSaleRecord> direct = <HelperSaleRecord>[
      for (int i = 0; i < 8; i++)
        HelperSaleRecord(
          tokenNo: 9000 + i,
          timestamp: start.add(Duration(minutes: i)),
          helperId: 'h1',
          helperName: 'Ali',
          unitId: kDirectSaleUnitId,
          fuelType: 'Petrol',
          volumeLiters: 20,
          rate: 267.89,
          amountPkr: 5000,
          customerName: 'Drum buyer',
        ),
    ];
    final ShiftSummary summary = ShiftSummary(
      shift: OperatorShiftRecord(
        shiftId: 'SH-100',
        operatorId: 'op1',
        operatorName: 'Latif Umrani',
        role: OperatorRole.operator,
        startTime: start,
        endTime: start.add(const Duration(hours: 8)),
        expectedCash: 20000,
        actualCash: 19800,
        status: OperatorShiftStatus.closed,
        notes: 'Handover -> night shift',
        openingMeters: const <int, double>{1: 10000, 2: 20000},
        closingMeters: const <int, double>{1: 10200, 2: 20110},
      ),
      metrics: ShiftWindowMetrics(
        sales: sales,
        directSales: direct,
        fuelCashSales: 28000,
        udhaarSales: 4000,
        accountSales: 0,
        udhaarRecoveryTotal: 500,
        totalLiters: 300,
        firstToken: 5000,
        lastToken: 5047,
      ),
    );

    final bytes = await ShiftSummaryExport.instance
        .buildPdf(
          summary,
          udhaarLedger: <UnifiedUdhaarRow>[
            UnifiedUdhaarRow(
              primaryKey: '0100/01-01',
              type: UnifiedUdhaarType.sale,
              at: start.add(const Duration(minutes: 12)),
              customerName: 'Ahmad Khan',
              customerId: '01',
              amountPkr: 1863,
              remainingPkr: 1863,
              tokenLabel: 'TKN-005003',
              liters: 4.5,
              rate: 267.89,
              vehicle: 'LEA-1003',
              udhaarPkr: 1863,
            ),
            UnifiedUdhaarRow(
              primaryKey: '0100/01-02',
              type: UnifiedUdhaarType.settlement,
              at: start.add(const Duration(hours: 2)),
              customerName: 'Ahmad Khan',
              customerId: '01',
              amountPkr: 500,
              remainingPkr: 1363,
              paidPkr: 500,
              description: encodeSettlementDescription(
                receiptNo: 'REC-0008',
                paymentMode: SettlementPaymentMode.cash,
                cashAmountPkr: 300,
                accountAmountPkr: 200,
              ),
            ),
          ],
        )
        .timeout(const Duration(seconds: 40));

    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('sales ledger PDF finishes for a filtered day of sales', () async {
    final List<SaleTransaction> rows = <SaleTransaction>[
      for (int i = 0; i < 180; i++)
        SaleTransaction(
          tokenNo: 1000 + i,
          unitId: 1,
          fuelType: 'Petrol',
          amountPkr: 500,
          volumeLiters: 2,
          rate: 250,
          meterCount: 1000 + i,
          timestamp: DateTime(2026, 10, 1, 8, i % 60),
          openingMeter: 100,
          closingMeter: 102,
          customerName: i == 1 ? 'Ahmad' : 'Walk-in',
          vehicleNo: 'ABC-$i',
          cashierName: 'Latif',
          helperName: 'Ali',
          cashAmount: 500,
        ),
    ];

    final bytes = await LedgerPdfExport.instance
        .buildSalesPdf(
          slice: SalesLedgerSnapshot(
            rows: rows,
            meterRows: rows,
            totalCount: rows.length,
            totalAmountPkr: 20000,
            totalVolumeLiters: 80,
            udhaarAmountPkr: 0,
            udhaarCount: 0,
            totalAccountAmountPkr: 0,
          ),
          unitId: null,
          range: DateTimeRange(
            start: DateTime(2026, 10, 1),
            end: DateTime(2026, 10, 5),
          ),
          search: '',
          shiftLabel: null,
          pageFormat: PdfPageFormat.a4.landscape,
        )
        .timeout(const Duration(seconds: 40));

    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('content-driven columns size from text and share leftover space', () {
    final Map<int, double> flex = pdfContentColumnFlex(
      headers: const <String>['PM', 'Customer / Vehicle'],
      rows: const <List<String>>[
        <String>['Cash', 'Ahmad Khan / LEA-1001'],
        <String>['Udhr', 'Walk-in'],
      ],
    );
    expect(flex[1]!, greaterThan(flex[0]!));

    final double total = flex[0]! + flex[1]!;
    expect(flex[1]! / total, greaterThan(0.55));
    expect(flex[0]! / total, lessThan(0.45));
  });
}
