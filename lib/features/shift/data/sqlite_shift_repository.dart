import '../../../core/security/pin_hasher.dart';
import '../../../services/database_helper.dart';
import '../../station/domain/dispenser_models.dart';
import '../../station/domain/fuel_precision.dart';
import '../domain/shift_lifecycle.dart';
import '../domain/shift_models.dart';

class ShiftStoreSnapshot {
  const ShiftStoreSnapshot({
    required this.operators,
    required this.helpers,
    required this.shifts,
    required this.sales,
  });

  final List<OperatorProfile> operators;
  final List<HelperProfile> helpers;
  final List<OperatorShiftRecord> shifts;
  final List<HelperSaleRecord> sales;
}

/// SQLite-backed shift / operator / helper store (`shifts`, `operators`, `helpers`).
class SqliteShiftRepository {
  SqliteShiftRepository({DatabaseHelper? db})
    : _db = db ?? DatabaseHelper.instance;

  static const String _statusLive = ShiftStatusStorage.live;
  static const String _statusPending = ShiftStatusStorage.pending;

  final DatabaseHelper _db;

  Future<ShiftStoreSnapshot> load() async {
    final List<OperatorProfile> operators = await listOperators();
    final List<HelperProfile> helpers = await listHelpers();
    final List<OperatorShiftRecord> shifts = await listShifts(operators);
    final List<HelperSaleRecord> sales = (await listSales())
        .map((HelperSaleRecord sale) => _attachShift(sale, shifts))
        .toList();
    return ShiftStoreSnapshot(
      operators: operators,
      helpers: helpers,
      shifts: shifts,
      sales: sales,
    );
  }

  Future<List<OperatorProfile>> listOperators() async {
    final List<Map<String, Object?>> rows = await _db.queryOperators();
    return rows.map(_operatorFromRow).toList();
  }

  Future<List<HelperProfile>> listHelpers() async {
    final List<Map<String, Object?>> rows = await _db.queryHelpers();
    return rows.map(_helperFromRow).toList();
  }

  Future<List<OperatorShiftRecord>> listShifts(
    List<OperatorProfile> operators,
  ) async {
    final List<Map<String, Object?>> rows = await _db.queryShifts();
    return rows.map((Map<String, Object?> row) {
      return _shiftFromRow(row, operators);
    }).toList();
  }

  Future<List<HelperSaleRecord>> listSales() async {
    final List<Map<String, Object?>> rows = await _db.queryAllSales(
      includeTest: true,
    );
    return rows.map(_saleFromRow).toList();
  }

  Future<List<HelperSaleRecord>> listHelperSales({
    required String helperId,
    required DateTime fromInclusive,
    required DateTime toInclusive,
  }) async {
    final List<Map<String, Object?>> rows = await _db.querySalesForHelper(
      helperId: helperId,
      fromInclusive: fromInclusive,
      toInclusive: toInclusive,
      includeTest: true,
    );
    return rows.map(_saleFromRow).toList();
  }

  Future<OperatorProfile> insertOperator({
    required String id,
    required String name,
    required OperatorRole role,
    required String pin,
  }) async {
    final String trimmed = name.trim();
    final String storedPin = PinHasher.hashIfPlain(pin);
    await _db.upsertOperator(
      operatorId: id,
      operatorName: trimmed,
      pin: storedPin,
    );
    return OperatorProfile(
      id: id,
      name: trimmed,
      role: role,
      status: OperatorProfileStatus.inactive,
      pin: storedPin,
    );
  }

  Future<HelperProfile> insertHelper({
    required String id,
    required String name,
  }) async {
    final String trimmed = name.trim();
    await _db.upsertHelper(helperId: id, helperName: trimmed);
    return HelperProfile(id: id, name: trimmed);
  }

  Future<void> persistHelperAssignments(List<HelperProfile> helpers) async {
    await _db.persistHelperUnitAssignments(
      helperIdToUnitsJson: <String, String>{
        for (final HelperProfile helper in helpers)
          helper.id: HelperUnitAssignmentSnapshot.encode(
            helper.assignedUnitIds,
          ),
      },
    );
  }

  Future<OperatorShiftRecord> insertOpenShift({
    required OperatorProfile operator,
    required DateTime startTime,
    String? helperId,
    Map<int, double> openingMeters = const <int, double>{},
  }) async {
    await _db.upsertOperator(
      operatorId: operator.id,
      operatorName: operator.name,
      pin: operator.pin,
    );
    final int pk = await _db.insertShift(
      operatorId: operator.id,
      helperId: helperId,
      startTimeIso: startTime.toIso8601String(),
      status: _statusLive,
      openingMeters: ShiftMeterSnapshot.encode(openingMeters),
    );
    return OperatorShiftRecord(
      shiftId: formatShiftId(pk),
      operatorId: operator.id,
      operatorName: operator.name,
      role: operator.role,
      startTime: startTime,
      expectedCash: 0,
      status: OperatorShiftStatus.open,
      openingMeters: openingMeters,
    );
  }

  Future<void> persistShift(OperatorShiftRecord shift) async {
    final int? pk = parseShiftPk(shift.shiftId);
    if (pk == null) {
      throw StateError('Cannot persist shift ${shift.shiftId}');
    }
    await _db.updateShift(
      shiftId: pk,
      endTimeIso: shift.endTime?.toIso8601String(),
      expectedCash: shift.expectedCash,
      actualCash: shift.actualCash ?? 0,
      discrepancy: shift.discrepancy,
      status: _statusToStorage(shift.status),
      notes: shift.notes,
      openingMeters: ShiftMeterSnapshot.encode(shift.openingMeters),
      closingMeters: ShiftMeterSnapshot.encode(shift.closingMeters),
    );
  }

  /// Freezes the outgoing shift for cash tally and opens the incoming LIVE shift.
  Future<({OperatorShiftRecord pending, OperatorShiftRecord opened})>
  handoverWithPendingTally({
    required OperatorShiftRecord outgoing,
    required OperatorProfile incoming,
    required DateTime handoffAt,
    Map<int, double> closingMeters = const <int, double>{},
    Map<int, double> openingMeters = const <int, double>{},
  }) async {
    final int? outgoingPk = parseShiftPk(outgoing.shiftId);
    if (outgoingPk == null) {
      throw StateError('Cannot freeze shift ${outgoing.shiftId}');
    }
    await _db.upsertOperator(
      operatorId: incoming.id,
      operatorName: incoming.name,
      pin: incoming.pin,
    );
    final OperatorShiftRecord pending = outgoing.copyWith(
      endTime: handoffAt,
      status: OperatorShiftStatus.pendingReconciliation,
      closingMeters: closingMeters,
    );
    return _db.runInTransaction((txn) async {
      await _db.updateShift(
        shiftId: outgoingPk,
        endTimeIso: handoffAt.toIso8601String(),
        expectedCash: pending.expectedCash,
        actualCash: pending.actualCash ?? 0,
        discrepancy: pending.discrepancy,
        status: _statusPending,
        notes: pending.notes,
        openingMeters: ShiftMeterSnapshot.encode(pending.openingMeters),
        closingMeters: ShiftMeterSnapshot.encode(closingMeters),
        executor: txn,
      );
      final int pk = await _db.insertShift(
        operatorId: incoming.id,
        startTimeIso: handoffAt.toIso8601String(),
        status: _statusLive,
        openingMeters: ShiftMeterSnapshot.encode(openingMeters),
        executor: txn,
      );
      final OperatorShiftRecord opened = OperatorShiftRecord(
        shiftId: formatShiftId(pk),
        operatorId: incoming.id,
        operatorName: incoming.name,
        role: incoming.role,
        startTime: handoffAt,
        expectedCash: 0,
        status: OperatorShiftStatus.open,
        openingMeters: openingMeters,
      );
      return (pending: pending, opened: opened);
    });
  }

  static ShiftWindowMetrics metricsForShift(
    List<HelperSaleRecord> sales,
    OperatorShiftRecord shift, {
    double udhaarRecoveryTotal = 0,
  }) {
    return _metricsForShift(
      sales,
      shift,
      udhaarRecoveryTotal: udhaarRecoveryTotal,
    );
  }

  static ShiftWindowMetrics _metricsForShift(
    List<HelperSaleRecord> sales,
    OperatorShiftRecord shift, {
    double udhaarRecoveryTotal = 0,
  }) {
    final ShiftWindowMetrics fromSales = metricsForSales(
      salesForOutgoingOperator(sales, shift),
      udhaarRecoveryTotal: udhaarRecoveryTotal,
    );
    if (udhaarRecoveryTotal > 0) {
      return fromSales;
    }
    final double inferred = shift.expectedCash - fromSales.fuelCashSales;
    if (inferred <= 0) {
      return fromSales;
    }
    return metricsForSales(fromSales.sales, udhaarRecoveryTotal: inferred);
  }

  static OperatorProfile _operatorFromRow(Map<String, Object?> row) {
    return OperatorProfile(
      id: '${row['manager_ID'] ?? ''}',
      name: (row['Manager_name'] as String?)?.trim() ?? '',
      role: OperatorRole.operator,
      status: OperatorProfileStatus.inactive,
      pin: (row['pin'] as String?)?.trim().isNotEmpty == true
          ? (row['pin'] as String).trim()
          : kDefaultOperatorPin,
    );
  }

  static HelperProfile _helperFromRow(Map<String, Object?> row) {
    return HelperProfile(
      id: '${row['Helper_ID'] ?? ''}',
      name: (row['Helper_name'] as String?)?.trim() ?? '',
      assignedUnitIds: HelperUnitAssignmentSnapshot.decode(
        row['ASSIGNED_UNITS'] as String?,
      ),
    );
  }

  static OperatorShiftRecord _shiftFromRow(
    Map<String, Object?> row,
    List<OperatorProfile> operators,
  ) {
    final int pk = _asInt(row['SHIFT_ID']);
    final String operatorId = '${row['MANAGER'] ?? ''}';
    OperatorRole role = OperatorRole.operator;
    for (final OperatorProfile operator in operators) {
      if (operator.id == operatorId) {
        role = operator.role;
        break;
      }
    }
    final OperatorShiftStatus status = _statusFromStorage(
      '${row['STATUS'] ?? _statusLive}',
    );
    final double actualStored = _asDouble(row['ACTUAL_CASH']);
    return OperatorShiftRecord(
      shiftId: formatShiftId(pk),
      operatorId: operatorId,
      operatorName: (row['manager_name'] as String?)?.trim() ?? operatorId,
      role: role,
      startTime:
          DateTime.tryParse('${row['START_TIME'] ?? ''}') ?? DateTime.now(),
      endTime: DateTime.tryParse('${row['END_TIME'] ?? ''}'),
      expectedCash: _asDouble(row['EXPECTED_CASH']),
      actualCash:
          status == OperatorShiftStatus.closed ||
              status == OperatorShiftStatus.forceClosed
          ? actualStored
          : null,
      notes: '${row['NOTES'] ?? ''}',
      status: status,
      openingMeters: ShiftMeterSnapshot.decode(
        row['OPENING_METERS'] as String?,
      ),
      closingMeters: ShiftMeterSnapshot.decode(
        row['CLOSING_METERS'] as String?,
      ),
    );
  }

  static HelperSaleRecord _saleFromRow(Map<String, Object?> row) {
    final String helperId = '${row['HELPER'] ?? ''}'.trim();
    final String helperName = (row['helper_name'] as String?)?.trim() ?? '';
    final String operatorId = '${row['Manager'] ?? ''}'.trim();
    final String operatorName = (row['manager_name'] as String?)?.trim() ?? '';
    return HelperSaleRecord(
      tokenNo: parseLedgerToken('${row['TOKEN'] ?? ''}'),
      timestamp:
          DateTime.tryParse('${row['DATE_TIME'] ?? ''}') ?? DateTime.now(),
      helperId: helperId,
      helperName: helperName,
      unitId: _asInt(row['UNIT_NO']),
      fuelType: kDieselFuelType,
      volumeLiters: _asDouble(row['LITERS']),
      rate: _asDouble(row['RATE']),
      amountPkr: _asDouble(row['AMOUNT']),
      payment: paymentMethodFromStorage(row['PAYMENT_METHOD'] as String?),
      cashierName: operatorName,
      operatorId: operatorId,
      shiftId: _shiftIdFromRow(row['SHIFT_ID']),
      cashAmount: _asDouble(row['CASH_AMOUNT']),
      accountAmount: _asDouble(row['ACCOUNT_AMOUNT']),
      pendingAccountAmount: _asDouble(row['PENDING_ACCOUNT']),
      openingMeter: _asDouble(row['OPENING_READING']),
      closingMeter: _asDouble(row['CLOSING_READING']),
      customerName: (row['CUSTOMER_NAME'] as String?)?.trim() ?? '',
      vehicleNo: (row['VEHICLE_NO'] as String?)?.trim() ?? '',
      operatorStaffId: '${row['MANAGER_ID'] ?? ''}'.trim(),
      helperStaffId: '${row['HELPER_ID'] ?? ''}'.trim(),
      actions: '${row['ACTIONS'] ?? ''}'.trim(),
      espTxId: '${row['ESP_TX_ID'] ?? ''}'.trim(),
      edited: _asInt(row['EDITED']) != 0,
      isTest: _asInt(row['IS_TEST']) != 0,
      drumQty: _asInt(row['DRUM_QTY']),
    );
  }

  static HelperSaleRecord _attachShift(
    HelperSaleRecord sale,
    List<OperatorShiftRecord> shifts,
  ) {
    if (sale.shiftId.isNotEmpty) {
      return sale;
    }
    for (final OperatorShiftRecord shift in shifts) {
      if (sale.operatorId.isNotEmpty && sale.operatorId != shift.operatorId) {
        continue;
      }
      if (!isInShiftWindow(
        sale.timestamp,
        shift.startTime,
        end: shift.endTime,
      )) {
        continue;
      }
      return sale.copyWith(
        shiftId: shift.shiftId,
        cashierName: sale.cashierName.isEmpty
            ? shift.operatorName
            : sale.cashierName,
        operatorId: sale.operatorId.isEmpty
            ? shift.operatorId
            : sale.operatorId,
      );
    }
    return sale;
  }

  static String _statusToStorage(OperatorShiftStatus status) {
    return ShiftStatusStorage.toStorage(status);
  }

  static OperatorShiftStatus _statusFromStorage(String raw) {
    return ShiftStatusStorage.fromStorage(raw);
  }

  static double _asDouble(Object? value) {
    return storedNumberToDouble(value);
  }

  static int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    return 0;
  }

  static String _shiftIdFromRow(Object? raw) {
    if (raw is int && raw > 0) {
      return formatShiftId(raw);
    }
    if (raw is num) {
      final int pk = raw.round();
      if (pk > 0) {
        return formatShiftId(pk);
      }
    }
    return '';
  }
}
