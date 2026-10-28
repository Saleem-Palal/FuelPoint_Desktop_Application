import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_dispenser/features/station/domain/sales_ledger_window.dart';

void main() {
  test('page 0 is the last 30 days through today', () {
    final SalesLedgerWindow window = salesLedgerWindowForPage(
      pageIndex: 0,
      now: DateTime(2026, 10, 8, 15, 30),
    );

    expect(window.isDefault, isTrue);
    expect(window.from, DateTime(2026, 9, 8));
    expect(window.to, DateTime(2026, 10, 8));
  });

  test('older pages step back 30 days without sharing a day', () {
    final SalesLedgerWindow second = salesLedgerWindowForPage(
      pageIndex: 1,
      now: DateTime(2026, 10, 8),
    );
    final SalesLedgerWindow third = salesLedgerWindowForPage(
      pageIndex: 2,
      now: DateTime(2026, 10, 8),
    );

    expect(second.from, DateTime(2026, 8, 8));
    expect(second.to, DateTime(2026, 9, 7));
    expect(third.from, DateTime(2026, 7, 8));
    expect(third.to, DateTime(2026, 8, 7));
  });

  test('a picked range replaces the 30-day window', () {
    final DateTime start = DateTime(2026, 1, 2, 9);
    final DateTime end = DateTime(2026, 1, 20, 18);
    final SalesLedgerWindow window = salesLedgerWindowForPage(
      pageIndex: 4,
      from: start,
      to: end,
      now: DateTime(2026, 10, 8),
    );

    expect(window.isDefault, isFalse);
    expect(window.from, start);
    expect(window.to, end);
  });

  test('block count reaches back to the oldest sale', () {
    expect(salesLedgerBlockCount(null, now: DateTime(2026, 10, 8)), 1);
    expect(
      salesLedgerBlockCount(DateTime(2026, 9, 8), now: DateTime(2026, 10, 8)),
      1,
    );
    expect(
      salesLedgerBlockCount(
        DateTime(2026, 9, 7, 18),
        now: DateTime(2026, 10, 8),
      ),
      2,
    );
    expect(
      salesLedgerBlockCount(DateTime(2026, 7, 8), now: DateTime(2026, 10, 8)),
      3,
    );
  });
}
