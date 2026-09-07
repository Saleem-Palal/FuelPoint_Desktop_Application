import 'package:flutter_test/flutter_test.dart';

import 'package:fuel_dispenser/features/customer/domain/customer_models.dart';
import 'package:fuel_dispenser/features/station/domain/dashboard_models.dart';
import 'package:fuel_dispenser/features/station/domain/dispenser_models.dart';

SaleTransaction _sale({
  required int unitId,
  required DateTime at,
  required double liters,
  required double pkr,
  PaymentMethod payment = PaymentMethod.cash,
  String customer = 'Walk-in',
  String cashierName = 'Cashier',
  String helperName = '',
}) {
  return SaleTransaction(
    tokenNo: tokenIdFor(unitId: unitId, sequence: 1),
    unitId: unitId,
    fuelType: kDieselFuelType,
    amountPkr: pkr,
    volumeLiters: liters,
    rate: 200,
    meterCount: 1,
    timestamp: at,
    payment: payment,
    customerName: customer,
    cashierName: cashierName,
    helperName: helperName,
  );
}

CustomerAccount _account({
  required String id,
  required String name,
  required double outstanding,
}) {
  return CustomerAccount(
    profile: CustomerProfile(id: id, name: name),
    udhaarSalesTotal: outstanding,
    settlementsTotal: 0,
    outstanding: outstanding,
    ledger: const <CustomerLedgerLine>[],
  );
}

void main() {
  test('dashboard snapshot aggregates SQLite sales windows and peak lane', () {
    final DateTime now = DateTime(2026, 9, 2, 16, 40);
    final List<SaleTransaction> sales = <SaleTransaction>[
      _sale(
        unitId: 1,
        at: now.subtract(const Duration(hours: 2)),
        liters: 10,
        pkr: 2000,
      ),
      _sale(
        unitId: 2,
        at: now.subtract(const Duration(hours: 3)),
        liters: 40,
        pkr: 8000,
      ),
      _sale(
        unitId: 2,
        at: now.subtract(const Duration(hours: 30)),
        liters: 99,
        pkr: 19800,
      ),
      _sale(
        unitId: 3,
        at: DateTime(2026, 9, 2, 8, 15),
        liters: 5,
        pkr: 1000,
        payment: PaymentMethod.udhaar,
        customer: 'Haji Karim',
      ),
      _sale(unitId: 4, at: DateTime(2026, 9, 2, 7, 10), liters: 8, pkr: 1600),
    ];
    final DashboardSnapshot snapshot = assembleDashboardSnapshot(
      sales: sales,
      accounts: <CustomerAccount>[
        _account(id: '01', name: 'Haji Karim', outstanding: 2700),
        _account(id: '02', name: 'Gul Khan', outstanding: 900),
        _account(id: '03', name: 'Paid Up', outstanding: 0),
      ],
      now: now,
    );

    expect(snapshot.kpis.dieselSoldLiters24h, 63);
    expect(snapshot.kpis.cashSalesPkrToday, 11600);
    expect(snapshot.kpis.udhaarExtendedPkrToday, 1000);
    expect(snapshot.kpis.totalOutstandingPkr, 3600);
    expect(snapshot.kpis.activeDebtAccounts, 2);

    final DashboardBayPerformance peak = snapshot.bays.firstWhere(
      (DashboardBayPerformance bay) => bay.isPeakLane,
    );
    expect(peak.unitId, 2);
    expect(peak.volumeLiters, 40);
    expect(
      snapshot.bays.where((DashboardBayPerformance b) => b.isPeakLane).length,
      1,
    );

    expect(snapshot.watchlist.first.customerName, 'Haji Karim');
    expect(snapshot.watchlist.length, 2);
    expect(snapshot.hourly[8].volumeLiters, 5);
    expect(snapshot.morningPeak.startHour, isNonNegative);
  });

  test('last week bay range includes the previous calendar days', () {
    final DateTime now = DateTime(2026, 9, 2, 16, 40);
    final DashboardSnapshot snapshot = assembleDashboardSnapshot(
      sales: <SaleTransaction>[
        _sale(
          unitId: 2,
          at: now.subtract(const Duration(hours: 3)),
          liters: 40,
          pkr: 8000,
        ),
        _sale(
          unitId: 2,
          at: now.subtract(const Duration(hours: 30)),
          liters: 99,
          pkr: 19800,
        ),
      ],
      accounts: const <CustomerAccount>[],
      now: now,
      bayRange: DashboardRangePreset.lastWeek,
    );
    final DashboardBayPerformance bay2 = snapshot.bays.firstWhere(
      (DashboardBayPerformance bay) => bay.unitId == 2,
    );
    expect(bay2.volumeLiters, 139);
    expect(bay2.revenuePkr, 27800);
    expect(bay2.txnCount, 2);
  });

  test('manager and helper cards total amount, volume, and transactions', () {
    final DateTime now = DateTime(2026, 9, 2, 16, 40);
    final DashboardSnapshot snapshot = assembleDashboardSnapshot(
      sales: <SaleTransaction>[
        _sale(
          unitId: 1,
          at: now.subtract(const Duration(hours: 1)),
          liters: 10,
          pkr: 2000,
          cashierName: 'Amir R.',
          helperName: 'Sajjad Ali',
        ),
        _sale(
          unitId: 2,
          at: now.subtract(const Duration(hours: 2)),
          liters: 20,
          pkr: 4000,
          cashierName: 'Amir R.',
          helperName: 'Babar Azam',
        ),
        _sale(
          unitId: 3,
          at: now.subtract(const Duration(days: 8)),
          liters: 50,
          pkr: 10000,
          cashierName: 'Amir R.',
          helperName: 'Sajjad Ali',
        ),
      ],
      accounts: const <CustomerAccount>[],
      now: now,
      managerRange: DashboardRangePreset.today,
      helperRange: DashboardRangePreset.thisMonth,
      managers: const <DashboardStaffMember>[
        DashboardStaffMember(id: 'mgr-1', name: 'Amir R.'),
        DashboardStaffMember(id: 'mgr-2', name: 'Usman'),
      ],
      helpers: const <DashboardStaffMember>[
        DashboardStaffMember(id: 'hlp-1', name: 'Sajjad Ali'),
        DashboardStaffMember(id: 'hlp-2', name: 'Babar Azam'),
      ],
    );

    expect(snapshot.managers.length, 2);
    expect(snapshot.managers.first.revenuePkr, 6000);
    expect(snapshot.managers.first.volumeLiters, 30);
    expect(snapshot.managers.first.txnCount, 2);
    expect(snapshot.managers.last.txnCount, 0);

    expect(snapshot.helpers.first.volumeLiters, 10);
    expect(snapshot.helpers.first.revenuePkr, 2000);
    expect(snapshot.helpers.first.txnCount, 1);
    expect(snapshot.helpers.last.volumeLiters, 20);
  });
}
