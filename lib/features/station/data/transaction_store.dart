import '../domain/dispenser_models.dart';

/// Persistence boundary for `sales_history`, `purchase_history`, and `system_logs`.
///
/// In-memory for the hardware-less client demo. Callers treat this as SQLite:
/// swap the engine for `sqflite_common_ffi` without changing insert signatures.
class TransactionStore {
  TransactionStore() {
    _salesHistory.addAll(_demoSales());
    _purchaseHistory.addAll(_demoPurchases());
  }

  final List<SaleTransaction> _salesHistory = <SaleTransaction>[];
  final List<PurchaseTransaction> _purchaseHistory = <PurchaseTransaction>[];
  final List<SystemLog> _systemLogs = <SystemLog>[];

  List<SaleTransaction> get snapshot {
    return List<SaleTransaction>.from(_salesHistory);
  }

  List<PurchaseTransaction> get purchaseSnapshot {
    return List<PurchaseTransaction>.from(_purchaseHistory);
  }

  List<SystemLog> get logsSnapshot {
    return List<SystemLog>.from(_systemLogs);
  }

  Future<void> init() async {}

  Future<void> insert(SaleTransaction txn) async {
    await insertSalesHistory(txn);
  }

  Future<void> insertSalesHistory(SaleTransaction txn) async {
    _salesHistory.insert(0, txn);
  }

  Future<SaleTransaction?> updateSalesHistory({
    required int tokenNo,
    required String customerName,
    required String vehicleNo,
    required PaymentMethod payment,
  }) async {
    final int index = _salesHistory.indexWhere(
      (SaleTransaction row) => row.tokenNo == tokenNo,
    );
    if (index < 0) {
      return null;
    }
    final String resolvedCustomer = customerName.trim().isEmpty
        ? 'Walk-in'
        : customerName.trim();
    final SaleTransaction next = _salesHistory[index].copyWith(
      customerName: resolvedCustomer,
      vehicleNo: vehicleNo.trim(),
      payment: payment,
    );
    _salesHistory[index] = next;
    return next;
  }

  Future<SaleTransaction?> settleUdhaar({
    required int tokenNo,
    required double settledAmount,
    required String description,
  }) async {
    final int index = _salesHistory.indexWhere(
      (SaleTransaction row) => row.tokenNo == tokenNo,
    );
    if (index < 0) {
      return null;
    }
    final SaleTransaction current = _salesHistory[index];
    if (current.payment != PaymentMethod.udhaar || current.udhaarSettled) {
      return null;
    }
    final String incoming = description.trim();
    final String existing = current.notes.trim();
    final String merged;
    if (existing.isEmpty) {
      merged = incoming;
    } else if (incoming.isEmpty) {
      merged = existing;
    } else {
      merged = '$existing · $incoming';
    }
    final SaleTransaction next = current.copyWith(
      notes: merged,
      udhaarSettled: true,
      settledAmount: settledAmount,
      settledAt: DateTime.now(),
    );
    _salesHistory[index] = next;
    return next;
  }

  Future<void> insertPurchaseHistory(PurchaseTransaction txn) async {
    _purchaseHistory.insert(0, txn);
  }

  Future<void> insertSystemLog({
    required String eventType,
    required int unitId,
    String details = '',
  }) async {
    _systemLogs.insert(
      0,
      SystemLog(
        eventType: eventType,
        unitId: unitId,
        timestamp: DateTime.now(),
        details: details,
      ),
    );
  }

  Future<List<SaleTransaction>> recent({int limit = 20}) async {
    if (_salesHistory.length <= limit) {
      return List<SaleTransaction>.from(_salesHistory);
    }
    return _salesHistory.take(limit).toList();
  }

  Future<Map<int, int>> sequencesFromHistory() async {
    final Map<int, int> nextSequence = <int, int>{
      for (final int unitId in dispenserUnitIds) unitId: 1,
    };
    for (final SaleTransaction txn in _salesHistory) {
      final int issued = sequenceFromToken(txn.tokenNo, txn.unitId);
      final int current = nextSequence[txn.unitId] ?? 1;
      if (issued + 1 > current) {
        nextSequence[txn.unitId] = issued + 1;
      }
    }
    return nextSequence;
  }

  SalesLedgerSnapshot querySales({
    int? unitId,
    String search = '',
    required DateTime month,
  }) {
    final DateTime from = DateTime(month.year, month.month);
    final DateTime to = DateTime(
      month.year,
      month.month + 1,
    ).subtract(const Duration(milliseconds: 1));
    final List<SaleTransaction> matched = _salesHistory.where((
      SaleTransaction row,
    ) {
      if (unitId != null && row.unitId != unitId) {
        return false;
      }
      if (!_inRange(row.timestamp, from, to)) {
        return false;
      }
      return _saleMatchesSearch(row, search);
    }).toList();

    double totalAmount = 0;
    double totalVolume = 0;
    double udhaarAmount = 0;
    int udhaarCount = 0;
    for (final SaleTransaction row in matched) {
      totalAmount += row.amountPkr;
      totalVolume += row.volumeLiters;
      if (row.payment == PaymentMethod.udhaar) {
        udhaarAmount += row.amountPkr;
        udhaarCount += 1;
      }
    }

    return SalesLedgerSnapshot(
      rows: matched,
      totalCount: matched.length,
      totalAmountPkr: totalAmount,
      totalVolumeLiters: totalVolume,
      udhaarAmountPkr: udhaarAmount,
      udhaarCount: udhaarCount,
    );
  }

  PurchaseLedgerSnapshot queryPurchases({required DateTime month}) {
    final DateTime from = DateTime(month.year, month.month);
    final DateTime to = DateTime(
      month.year,
      month.month + 1,
    ).subtract(const Duration(milliseconds: 1));
    final List<PurchaseTransaction> matched = _purchaseHistory.where((
      PurchaseTransaction row,
    ) {
      return _inRange(row.timestamp, from, to);
    }).toList();

    double totalAmount = 0;
    double totalVolume = 0;
    double largestDelivery = 0;
    for (final PurchaseTransaction row in matched) {
      totalAmount += row.totalAmount;
      totalVolume += row.netLiters;
      if (row.netLiters > largestDelivery) {
        largestDelivery = row.netLiters;
      }
    }

    return PurchaseLedgerSnapshot(
      rows: matched,
      totalCount: matched.length,
      totalAmountPkr: totalAmount,
      totalVolumeLiters: totalVolume,
      largestDeliveryLiters: largestDelivery,
    );
  }

  List<DateTime> availableSalesMonths() {
    return _monthsFrom(
      _salesHistory.map((SaleTransaction row) => row.timestamp),
    );
  }

  List<DateTime> availablePurchaseMonths() {
    return _monthsFrom(
      _purchaseHistory.map((PurchaseTransaction row) => row.timestamp),
    );
  }

  static List<DateTime> _monthsFrom(Iterable<DateTime> timestamps) {
    final Map<int, DateTime> unique = <int, DateTime>{};
    for (final DateTime timestamp in timestamps) {
      final DateTime month = DateTime(timestamp.year, timestamp.month);
      unique[month.year * 12 + month.month] = month;
    }
    final List<DateTime> months = unique.values.toList()
      ..sort((DateTime a, DateTime b) => a.compareTo(b));
    return months;
  }

  static bool _inRange(DateTime timestamp, DateTime? from, DateTime? to) {
    if (from != null) {
      final DateTime start = DateTime(from.year, from.month, from.day);
      if (timestamp.isBefore(start)) {
        return false;
      }
    }
    if (to != null) {
      final DateTime end = DateTime(to.year, to.month, to.day, 23, 59, 59, 999);
      if (timestamp.isAfter(end)) {
        return false;
      }
    }
    return true;
  }

  static bool _saleMatchesSearch(SaleTransaction row, String raw) {
    final String query = raw.trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }
    final String tokenLabel = formatLedgerToken(row.tokenNo).toLowerCase();
    final String tokenDigits = formatTokenNo(row.tokenNo);
    if (tokenLabel.contains(query) ||
        tokenDigits.contains(query) ||
        row.tokenNo.toString().contains(query)) {
      return true;
    }
    if (row.customerName.toLowerCase().contains(query)) {
      return true;
    }
    if (row.vehicleNo.toLowerCase().contains(query)) {
      return true;
    }
    return false;
  }

  static SaleTransaction _row({
    required int id,
    required int tokenNo,
    required int unitId,
    required double amountPkr,
    required double volumeLiters,
    required double rate,
    required double openingMeter,
    required DateTime timestamp,
    required PaymentMethod payment,
    required String cashierName,
    String shiftName = 'Morning',
    String fuelType = 'Diesel',
    String customerName = 'Walk-in',
    String vehicleNo = '',
  }) {
    final double closingMeter = openingMeter + volumeLiters;
    return SaleTransaction(
      id: id,
      tokenNo: tokenNo,
      unitId: unitId,
      fuelType: fuelType,
      amountPkr: amountPkr,
      volumeLiters: volumeLiters,
      rate: rate,
      meterCount: closingMeter.round(),
      timestamp: timestamp,
      openingMeter: openingMeter,
      closingMeter: closingMeter,
      payment: payment,
      cashierName: cashierName,
      shiftName: shiftName,
      customerName: customerName,
      vehicleNo: vehicleNo,
    );
  }

  static List<SaleTransaction> _demoSales() {
    final DateTime now = DateTime(2026, 8, 28, 12, 40);
    int id = 0;
    SaleTransaction next({
      required int unitId,
      required int sequence,
      required double amountPkr,
      required double volumeLiters,
      required double rate,
      required double openingMeter,
      required DateTime timestamp,
      required PaymentMethod payment,
      required String cashierName,
      String shiftName = 'Morning',
      String customerName = 'Walk-in',
      String vehicleNo = '',
    }) {
      id += 1;
      return _row(
        id: id,
        tokenNo: tokenIdFor(unitId: unitId, sequence: sequence),
        unitId: unitId,
        amountPkr: amountPkr,
        volumeLiters: volumeLiters,
        rate: rate,
        openingMeter: openingMeter,
        timestamp: timestamp,
        payment: payment,
        cashierName: cashierName,
        shiftName: shiftName,
        customerName: customerName,
        vehicleNo: vehicleNo,
      );
    }

    return <SaleTransaction>[
      next(
        unitId: 2,
        sequence: 14,
        amountPkr: 1200,
        volumeLiters: 8,
        rate: 150,
        openingMeter: 13454711.863,
        timestamp: now,
        payment: PaymentMethod.cash,
        cashierName: 'Ali',
        customerName: 'Malik Zahid',
        vehicleNo: 'QTA-4412',
      ),
      next(
        unitId: 1,
        sequence: 25,
        amountPkr: 2000,
        volumeLiters: 10,
        rate: 200,
        openingMeter: 13452332.143,
        timestamp: now.subtract(const Duration(minutes: 8)),
        payment: PaymentMethod.bankAccount,
        cashierName: 'Amir R.',
        customerName: 'Quetta Transport',
        vehicleNo: 'BRP-2211',
      ),
      next(
        unitId: 3,
        sequence: 8,
        amountPkr: 800,
        volumeLiters: 4,
        rate: 200,
        openingMeter: 13450104.004,
        timestamp: DateTime(2026, 8, 28, 12, 18),
        payment: PaymentMethod.easyPaisa,
        cashierName: 'Cashier',
      ),
      next(
        unitId: 1,
        sequence: 24,
        amountPkr: 1500,
        volumeLiters: 7.5,
        rate: 200,
        openingMeter: 13452324.643,
        timestamp: DateTime(2026, 8, 28, 11, 55),
        payment: PaymentMethod.udhaar,
        cashierName: 'Amir R.',
        customerName: 'Haji Karim',
        vehicleNo: 'LEA-9088',
      ),
      next(
        unitId: 4,
        sequence: 2,
        amountPkr: 600,
        volumeLiters: 4,
        rate: 150,
        openingMeter: 13449876.550,
        timestamp: DateTime(2026, 8, 28, 11, 30),
        payment: PaymentMethod.cash,
        cashierName: 'Usman',
      ),
      next(
        unitId: 2,
        sequence: 13,
        amountPkr: 2250,
        volumeLiters: 15,
        rate: 150,
        openingMeter: 13454696.863,
        timestamp: DateTime(2026, 8, 28, 11, 05),
        payment: PaymentMethod.bankAccount,
        cashierName: 'Ali',
        customerName: 'PSO Fleet',
        vehicleNo: 'QTA-1107',
      ),
      next(
        unitId: 3,
        sequence: 7,
        amountPkr: 400,
        volumeLiters: 2,
        rate: 200,
        openingMeter: 13450102.004,
        timestamp: DateTime(2026, 8, 28, 10, 42),
        payment: PaymentMethod.cash,
        cashierName: 'Cashier',
      ),
      next(
        unitId: 1,
        sequence: 23,
        amountPkr: 3000,
        volumeLiters: 15,
        rate: 200,
        openingMeter: 13452309.643,
        timestamp: DateTime(2026, 8, 28, 10, 15),
        payment: PaymentMethod.easyPaisa,
        cashierName: 'Amir R.',
        customerName: 'Naseer Traders',
        vehicleNo: 'ABC-3344',
      ),
      next(
        unitId: 5,
        sequence: 2,
        amountPkr: 1800,
        volumeLiters: 9,
        rate: 200,
        openingMeter: 13451191.000,
        timestamp: DateTime(2026, 8, 28, 9, 40),
        payment: PaymentMethod.cash,
        cashierName: 'Usman',
        shiftName: 'Morning',
        customerName: 'Walk-in',
        vehicleNo: 'QTA-7781',
      ),
      next(
        unitId: 5,
        sequence: 1,
        amountPkr: 900,
        volumeLiters: 4.5,
        rate: 200,
        openingMeter: 13451186.500,
        timestamp: DateTime(2026, 8, 28, 8, 12),
        payment: PaymentMethod.udhaar,
        cashierName: 'Ali',
        customerName: 'Gul Khan',
        vehicleNo: 'DMA-5520',
      ),
      next(
        unitId: 4,
        sequence: 1,
        amountPkr: 2250,
        volumeLiters: 15,
        rate: 150,
        openingMeter: 13449861.550,
        timestamp: DateTime(2026, 8, 27, 21, 18),
        payment: PaymentMethod.bankAccount,
        cashierName: 'Usman',
        shiftName: 'Night',
        customerName: 'City Logistics',
        vehicleNo: 'QTA-0901',
      ),
      next(
        unitId: 2,
        sequence: 12,
        amountPkr: 750,
        volumeLiters: 5,
        rate: 150,
        openingMeter: 13454691.863,
        timestamp: DateTime(2026, 8, 27, 19, 05),
        payment: PaymentMethod.cash,
        cashierName: 'Ali',
        shiftName: 'Evening',
      ),
      next(
        unitId: 1,
        sequence: 22,
        amountPkr: 4000,
        volumeLiters: 20,
        rate: 200,
        openingMeter: 13452289.643,
        timestamp: DateTime(2026, 8, 27, 16, 44),
        payment: PaymentMethod.udhaar,
        cashierName: 'Amir R.',
        shiftName: 'Evening',
        customerName: 'Malik Zahid',
        vehicleNo: 'QTA-4412',
      ),
      next(
        unitId: 3,
        sequence: 6,
        amountPkr: 1600,
        volumeLiters: 8,
        rate: 200,
        openingMeter: 13450094.004,
        timestamp: DateTime(2026, 8, 27, 14, 22),
        payment: PaymentMethod.easyPaisa,
        cashierName: 'Cashier',
        shiftName: 'Evening',
        vehicleNo: 'LEA-1200',
      ),
      next(
        unitId: 1,
        sequence: 21,
        amountPkr: 1000,
        volumeLiters: 5,
        rate: 200,
        openingMeter: 13452284.643,
        timestamp: DateTime(2026, 8, 26, 18, 10),
        payment: PaymentMethod.cash,
        cashierName: 'Amir R.',
        shiftName: 'Evening',
      ),
      next(
        unitId: 2,
        sequence: 11,
        amountPkr: 3000,
        volumeLiters: 20,
        rate: 150,
        openingMeter: 13454671.863,
        timestamp: DateTime(2026, 8, 26, 11, 30),
        payment: PaymentMethod.bankAccount,
        cashierName: 'Ali',
        customerName: 'Hascol Contractor',
        vehicleNo: 'BRP-8802',
      ),
      next(
        unitId: 3,
        sequence: 5,
        amountPkr: 2400,
        volumeLiters: 12,
        rate: 200,
        openingMeter: 13450082.004,
        timestamp: DateTime(2026, 8, 25, 20, 48),
        payment: PaymentMethod.cash,
        cashierName: 'Cashier',
        shiftName: 'Night',
        customerName: 'Walk-in',
      ),
      next(
        unitId: 4,
        sequence: 3,
        amountPkr: 450,
        volumeLiters: 3,
        rate: 150,
        openingMeter: 13449858.550,
        timestamp: DateTime(2026, 8, 25, 9, 15),
        payment: PaymentMethod.udhaar,
        cashierName: 'Usman',
        customerName: 'Saeed Ahmed',
        vehicleNo: 'QTA-3340',
      ),
      next(
        unitId: 1,
        sequence: 20,
        amountPkr: 5000,
        volumeLiters: 25,
        rate: 200,
        openingMeter: 13452259.643,
        timestamp: DateTime(2026, 8, 24, 13, 02),
        payment: PaymentMethod.bankAccount,
        cashierName: 'Amir R.',
        customerName: 'Quetta Transport',
        vehicleNo: 'BRP-2211',
      ),
      next(
        unitId: 5,
        sequence: 3,
        amountPkr: 600,
        volumeLiters: 3,
        rate: 200,
        openingMeter: 13451183.500,
        timestamp: DateTime(2026, 8, 24, 8, 40),
        payment: PaymentMethod.cash,
        cashierName: 'Ali',
      ),
      next(
        unitId: 2,
        sequence: 10,
        amountPkr: 1350,
        volumeLiters: 9,
        rate: 150,
        openingMeter: 13454662.863,
        timestamp: DateTime(2026, 8, 23, 17, 28),
        payment: PaymentMethod.easyPaisa,
        cashierName: 'Ali',
        shiftName: 'Evening',
        customerName: 'Naseer Traders',
        vehicleNo: 'ABC-3344',
      ),
      next(
        unitId: 3,
        sequence: 4,
        amountPkr: 800,
        volumeLiters: 4,
        rate: 200,
        openingMeter: 13450078.004,
        timestamp: DateTime(2026, 8, 22, 12, 11),
        payment: PaymentMethod.cash,
        cashierName: 'Cashier',
      ),
      next(
        unitId: 1,
        sequence: 19,
        amountPkr: 2200,
        volumeLiters: 11,
        rate: 200,
        openingMeter: 13452248.643,
        timestamp: DateTime(2026, 8, 21, 19, 55),
        payment: PaymentMethod.udhaar,
        cashierName: 'Amir R.',
        shiftName: 'Evening',
        customerName: 'Haji Karim',
        vehicleNo: 'LEA-9088',
      ),
      next(
        unitId: 4,
        sequence: 4,
        amountPkr: 1500,
        volumeLiters: 10,
        rate: 150,
        openingMeter: 13449848.550,
        timestamp: DateTime(2026, 8, 20, 10, 06),
        payment: PaymentMethod.cash,
        cashierName: 'Usman',
        customerName: 'City Logistics',
        vehicleNo: 'QTA-0901',
      ),
      next(
        unitId: 2,
        sequence: 9,
        amountPkr: 1800,
        volumeLiters: 12,
        rate: 150,
        openingMeter: 13454650.863,
        timestamp: DateTime(2026, 7, 22, 16, 40),
        payment: PaymentMethod.cash,
        cashierName: 'Ali',
        shiftName: 'Evening',
        customerName: 'Malik Zahid',
        vehicleNo: 'QTA-4412',
      ),
      next(
        unitId: 1,
        sequence: 18,
        amountPkr: 2600,
        volumeLiters: 13,
        rate: 200,
        openingMeter: 13452235.643,
        timestamp: DateTime(2026, 7, 9, 11, 20),
        payment: PaymentMethod.udhaar,
        cashierName: 'Amir R.',
        customerName: 'Gul Khan',
        vehicleNo: 'DMA-5520',
      ),
      next(
        unitId: 3,
        sequence: 3,
        amountPkr: 1200,
        volumeLiters: 6,
        rate: 200,
        openingMeter: 13450072.004,
        timestamp: DateTime(2026, 6, 18, 14, 05),
        payment: PaymentMethod.bankAccount,
        cashierName: 'Cashier',
        customerName: 'Quetta Transport',
        vehicleNo: 'BRP-2211',
      ),
      next(
        unitId: 5,
        sequence: 4,
        amountPkr: 900,
        volumeLiters: 4.5,
        rate: 200,
        openingMeter: 13451179.000,
        timestamp: DateTime(2026, 6, 4, 9, 30),
        payment: PaymentMethod.cash,
        cashierName: 'Usman',
      ),
    ];
  }

  static PurchaseTransaction _purchase({
    required int id,
    required int refNo,
    required DateTime timestamp,
    required String supplierName,
    required double netLiters,
    required double ratePerLiter,
    required double paidAmount,
    double sharahRatio = 0.840,
    double deductions = 0,
    String fuelType = 'Diesel',
  }) {
    final double weightKg = netLiters * sharahRatio;
    final double totalAmount = netLiters * ratePerLiter;
    final double remaining = (totalAmount - deductions - paidAmount)
        .clamp(0, double.infinity)
        .toDouble();
    return PurchaseTransaction(
      id: id,
      refNo: refNo,
      timestamp: timestamp,
      supplierName: supplierName,
      fuelType: fuelType,
      weightKg: weightKg,
      sharahRatio: sharahRatio,
      netLiters: netLiters,
      ratePerLiter: ratePerLiter,
      totalAmount: totalAmount,
      deductions: deductions,
      paidAmount: paidAmount,
      remainingBalance: remaining,
    );
  }

  static List<PurchaseTransaction> _demoPurchases() {
    return <PurchaseTransaction>[
      _purchase(
        id: 1,
        refNo: 999,
        timestamp: DateTime(2026, 8, 29, 11, 42),
        supplierName: 'Haji Abdul Haleem Umrani',
        netLiters: 580.50,
        ratePerLiter: 151.20,
        paidAmount: 87771.60,
      ),
      _purchase(
        id: 2,
        refNo: 998,
        timestamp: DateTime(2026, 8, 29, 8, 15),
        supplierName: 'Attock Petroleum',
        netLiters: 533.26,
        ratePerLiter: 151.20,
        paidAmount: 80628.40,
      ),
      _purchase(
        id: 3,
        refNo: 997,
        timestamp: DateTime(2026, 8, 26, 16, 30),
        supplierName: 'Hascol Depot',
        netLiters: 3200.00,
        ratePerLiter: 149.80,
        paidAmount: 429360.00,
        deductions: 2500,
      ),
      _purchase(
        id: 4,
        refNo: 996,
        timestamp: DateTime(2026, 8, 24, 10, 5),
        supplierName: 'Shell Pakistan',
        netLiters: 2100.00,
        ratePerLiter: 149.50,
        paidAmount: 313950.00,
      ),
      _purchase(
        id: 5,
        refNo: 995,
        timestamp: DateTime(2026, 8, 21, 14, 48),
        supplierName: 'PSO — Evening Load',
        netLiters: 1750.00,
        ratePerLiter: 148.90,
        paidAmount: 0,
      ),
      _purchase(
        id: 6,
        refNo: 994,
        timestamp: DateTime(2026, 8, 18, 9, 20),
        supplierName: 'Local Tanker Contractor',
        netLiters: 980.00,
        ratePerLiter: 148.90,
        paidAmount: 100000.00,
        deductions: 1200,
      ),
      _purchase(
        id: 7,
        refNo: 993,
        timestamp: DateTime(2026, 8, 15, 13, 10),
        supplierName: 'Attock — Full Compartment',
        netLiters: 2400.00,
        ratePerLiter: 147.60,
        paidAmount: 354240.00,
      ),
      _purchase(
        id: 8,
        refNo: 992,
        timestamp: DateTime(2026, 8, 12, 17, 55),
        supplierName: 'Owner Top-up',
        netLiters: 640.00,
        ratePerLiter: 147.60,
        paidAmount: 94464.00,
      ),
      _purchase(
        id: 9,
        refNo: 991,
        timestamp: DateTime(2026, 8, 9, 11, 2),
        supplierName: 'Hascol Morning',
        netLiters: 1500.00,
        ratePerLiter: 146.40,
        paidAmount: 180000.00,
      ),
      _purchase(
        id: 10,
        refNo: 990,
        timestamp: DateTime(2026, 8, 6, 15, 40),
        supplierName: 'PSO Tanker 7',
        netLiters: 1880.00,
        ratePerLiter: 146.40,
        paidAmount: 275232.00,
      ),
      _purchase(
        id: 11,
        refNo: 989,
        timestamp: DateTime(2026, 8, 3, 10, 18),
        supplierName: 'Byco / Cnergyico',
        netLiters: 1100.00,
        ratePerLiter: 145.80,
        paidAmount: 80000.00,
        deductions: 800,
      ),
      _purchase(
        id: 12,
        refNo: 988,
        timestamp: DateTime(2026, 7, 30, 16, 05),
        supplierName: 'Haji Abdul Haleem Umrani',
        netLiters: 2650.00,
        ratePerLiter: 145.20,
        paidAmount: 384780.00,
      ),
      _purchase(
        id: 13,
        refNo: 987,
        timestamp: DateTime(2026, 6, 14, 11, 20),
        supplierName: 'Attock Petroleum',
        netLiters: 1900.00,
        ratePerLiter: 144.80,
        paidAmount: 275120.00,
      ),
    ];
  }
}

class SalesLedgerSnapshot {
  const SalesLedgerSnapshot({
    required this.rows,
    required this.totalCount,
    required this.totalAmountPkr,
    required this.totalVolumeLiters,
    required this.udhaarAmountPkr,
    required this.udhaarCount,
  });

  final List<SaleTransaction> rows;
  final int totalCount;
  final double totalAmountPkr;
  final double totalVolumeLiters;
  final double udhaarAmountPkr;
  final int udhaarCount;
}

class PurchaseLedgerSnapshot {
  const PurchaseLedgerSnapshot({
    required this.rows,
    required this.totalCount,
    required this.totalAmountPkr,
    required this.totalVolumeLiters,
    required this.largestDeliveryLiters,
  });

  final List<PurchaseTransaction> rows;
  final int totalCount;
  final double totalAmountPkr;
  final double totalVolumeLiters;
  final double largestDeliveryLiters;

  double get averageRate {
    if (totalVolumeLiters <= 0) {
      return 0;
    }
    return totalAmountPkr / totalVolumeLiters;
  }
}
