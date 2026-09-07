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
