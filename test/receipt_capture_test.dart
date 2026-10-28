import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fuel_dispenser/Screens/Sale Screen/Widgets/Services/receipt_preview_widget.dart';
import 'package:fuel_dispenser/features/station/data/receipt_widget_capture.dart';
import 'package:fuel_dispenser/features/station/domain/dispenser_models.dart';

void main() {
  testWidgets('off-tree receipt capture produces a png', (
    WidgetTester tester,
  ) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    await tester.pump();
    final Uint8List? bytes = await tester.runAsync(() async {
      final SaleTransaction txn = SaleTransaction(
        tokenNo: 1001,
        unitId: 1,
        fuelType: kDieselFuelType,
        amountPkr: 1500,
        volumeLiters: 5,
        rate: 300,
        meterCount: 10,
        timestamp: DateTime(2026, 10, 25, 12),
        payment: PaymentMethod.easyPaisa,
        accountAmount: 1500,
        customerName: 'Ahmad',
        cashierName: 'Amir',
      );
      return captureReceiptWidget(
        context: ctx,
        child: buildSaleReceiptSlip(txn: txn, stationCopy: true),
      );
    });
    expect(bytes, isNotNull);
    expect(bytes!.length, greaterThan(500));
    expect(bytes.take(8).toList(), <int>[137, 80, 78, 71, 13, 10, 26, 10]);
  });
}
