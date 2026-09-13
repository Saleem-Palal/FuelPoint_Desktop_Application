import '../domain/average_rate.dart';
import '../domain/dispenser_models.dart';

/// In-memory system logs. Committed sales and purchases live in SQLite.
class TransactionStore {
  final List<SystemLog> _systemLogs = <SystemLog>[];

  List<SystemLog> get logsSnapshot {
    return List<SystemLog>.from(_systemLogs);
  }

  Future<void> init() async {}

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

  static const SalesLedgerSnapshot empty = SalesLedgerSnapshot(
    rows: <SaleTransaction>[],
    totalCount: 0,
    totalAmountPkr: 0,
    totalVolumeLiters: 0,
    udhaarAmountPkr: 0,
    udhaarCount: 0,
  );

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
    double cost = 0;
    double liters = 0;
    for (final PurchaseTransaction row in rows) {
      if (isInitialDipTafseel(row.tafseel)) {
        continue;
      }
      cost += row.totalAmount;
      liters += row.netLiters;
    }
    if (liters <= 0) {
      return 0;
    }
    return cost / liters;
  }
}
