import '../../../services/database_helper.dart';
import '../domain/customer_models.dart';
import '../domain/customer_repository.dart';

class SqliteUnifiedUdhaarRepository implements UnifiedUdhaarRepository {
  SqliteUnifiedUdhaarRepository({DatabaseHelper? db})
    : _db = db ?? DatabaseHelper.instance;

  final DatabaseHelper _db;

  @override
  Future<List<UnifiedUdhaarRow>> list() async {
    final List<Map<String, Object?>> rows = await _db.queryUnifiedUdhaarLedger();
    return rows.map(fromRow).toList();
  }

  @override
  Future<List<UnifiedUdhaarRow>> forCustomerId(String customerId) async {
    final List<Map<String, Object?>> rows = await _db.queryUnifiedUdhaarLedger(
      customerId: customerId,
    );
    return rows.map(fromRow).toList();
  }

  @override
  Future<double> remainingFor(String customerId) {
    return _db.latestUdhaarRemaining(customerId);
  }

  @override
  Future<int> nextReceiptSeq() {
    return _db.nextSettlementReceiptSeq();
  }

  @override
  Future<UnifiedUdhaarRow> insertSettlement({
    required String customerId,
    required String customerName,
    required double amountPkr,
    required SettlementPaymentMode paymentMode,
    required String shiftId,
    String notes = '',
    DateTime? timestamp,
  }) async {
    final int receiptSeq = await nextReceiptSeq();
    final Map<String, Object?> row = await _db.insertUnifiedUdhaarEntry(
      type: UnifiedUdhaarType.settlement.storage,
      shiftId: shiftId,
      customerId: customerId,
      customerName: customerName,
      at: timestamp ?? DateTime.now(),
      amount: amountPkr,
      description: encodeSettlementDescription(
        receiptNo: formatSettlementReceiptNo(receiptSeq),
        paymentMode: paymentMode,
        notes: notes,
      ),
    );
    return fromRow(row);
  }

  static UnifiedUdhaarRow fromRow(Map<String, Object?> row) {
    return UnifiedUdhaarRow(
      primaryKey: '${row['PRIMARY_KEY'] ?? ''}',
      type: UnifiedUdhaarTypeX.parse(row['TYPE'] as String?),
      at: DateTime.tryParse('${row['DATE_TIME'] ?? ''}') ?? DateTime.now(),
      customerName: '${row['Customer_name'] ?? ''}'.trim(),
      customerId: '${row['Customer_ID'] ?? ''}'.trim(),
      amountPkr: _asDouble(row['AMOUNT']),
      remainingPkr: _asDouble(row['REMAINING']),
      tokenLabel: (row['TKN'] as String?)?.trim(),
      liters: _asDouble(row['LITERS']),
      rate: _asDouble(row['RATE']),
      description: '${row['DESCRIPTION'] ?? ''}'.trim(),
      vehicle: '${row['VEHICLE'] ?? ''}'.trim(),
      udhaarPkr: _asDouble(row['UDHAAR']),
      paidPkr: _asDouble(row['PAID']),
      status: '${row['Status'] ?? 'Unpaid'}',
    );
  }

  static double _asDouble(Object? value) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    return 0.0;
  }
}
