import '../../../core/security/pin_hasher.dart';
import '../../../services/database_helper.dart';
import '../../station/domain/dispenser_models.dart';
import '../domain/shift_models.dart';

class ShiftStoreSnapshot {
  const ShiftStoreSnapshot({
    required this.managers,
    required this.helpers,
    required this.shifts,
    required this.sales,
  });

  final List<ManagerProfile> managers;
  final List<HelperProfile> helpers;
  final List<ManagerShiftRecord> shifts;
  final List<HelperSaleRecord> sales;
}

/// SQLite-backed shift / manager / helper store (`shifts`, `managers`, `helpers`).
class SqliteShiftRepository {
  SqliteShiftRepository({DatabaseHelper? db})
    : _db = db ?? DatabaseHelper.instance;

  static const String _statusOpen = 'OPEN';
  static const String _statusPending = 'PENDING_RECONCILIATION';
  static const String _statusClosed = 'CLOSED';
  static const String _statusForceClosed = 'FORCE_CLOSED';

  final DatabaseHelper _db;

  Future<ShiftStoreSnapshot> load() async {
    final List<ManagerProfile> managers = await listManagers();
    final List<HelperProfile> helpers = await listHelpers();
    final List<ManagerShiftRecord> shifts = await listShifts(managers);
    final List<HelperSaleRecord> sales = (await listSales())
        .map((HelperSaleRecord sale) => _attachShift(sale, shifts))
        .toList();
    return ShiftStoreSnapshot(
      managers: managers,
      helpers: helpers,
      shifts: shifts,
      sales: sales,
    );
  }

  Future<List<ManagerProfile>> listManagers() async {
    final List<Map<String, Object?>> rows = await _db.queryManagers();
    return rows.map(_managerFromRow).toList();
  }

  Future<List<HelperProfile>> listHelpers() async {
    final List<Map<String, Object?>> rows = await _db.queryHelpers();
    return rows.map(_helperFromRow).toList();
  }

  Future<List<ManagerShiftRecord>> listShifts(
    List<ManagerProfile> managers,
  ) async {
    final List<Map<String, Object?>> rows = await _db.queryShifts();
    return rows.map((Map<String, Object?> row) {
      return _shiftFromRow(row, managers);
    }).toList();
  }

  Future<List<HelperSaleRecord>> listSales() async {
    final List<Map<String, Object?>> rows = await _db.queryAllSales();
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
    );
    return rows.map(_saleFromRow).toList();
  }

  Future<ManagerProfile> insertManager({
    required String id,
    required String name,
    required ManagerRole role,
    required String pin,
  }) async {
    final String trimmed = name.trim();
    final String storedPin = PinHasher.hashIfPlain(pin);
    await _db.upsertManager(
      managerId: id,
      managerName: trimmed,
      pin: storedPin,
    );
    return ManagerProfile(
      id: id,
      name: trimmed,
      role: role,
      status: ManagerProfileStatus.inactive,
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

  Future<ManagerShiftRecord> insertOpenShift({
    required ManagerProfile manager,
    required DateTime startTime,
    String? helperId,
  }) async {
    await _db.upsertManager(
      managerId: manager.id,
      managerName: manager.name,
      pin: manager.pin,
    );
    final int pk = await _db.insertShift(
      managerId: manager.id,
      helperId: helperId,
      startTimeIso: startTime.toIso8601String(),
      status: _statusOpen,
    );
    return ManagerShiftRecord(
      shiftId: formatShiftId(pk),
      managerId: manager.id,
      managerName: manager.name,
      role: manager.role,
      startTime: startTime,
      expectedCash: 0,
      status: ManagerShiftStatus.open,
    );
  }

  Future<void> persistShift(ManagerShiftRecord shift) async {
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
    );
  }

  static ShiftWindowMetrics metricsForShift(
    List<HelperSaleRecord> sales,
    ManagerShiftRecord shift, {
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
    ManagerShiftRecord shift, {
    double udhaarRecoveryTotal = 0,
  }) {
    final ShiftWindowMetrics fromSales = metricsForSales(
      salesForOutgoingManager(sales, shift),
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

  static ManagerProfile _managerFromRow(Map<String, Object?> row) {
    return ManagerProfile(
      id: '${row['manager_ID'] ?? ''}',
      name: (row['Manager_name'] as String?)?.trim() ?? '',
      role: ManagerRole.manager,
      status: ManagerProfileStatus.inactive,
      pin: (row['pin'] as String?)?.trim().isNotEmpty == true
          ? (row['pin'] as String).trim()
          : kDefaultManagerPin,
    );
  }

  static HelperProfile _helperFromRow(Map<String, Object?> row) {
    return HelperProfile(
      id: '${row['Helper_ID'] ?? ''}',
      name: (row['Helper_name'] as String?)?.trim() ?? '',
    );
  }

  static ManagerShiftRecord _shiftFromRow(
    Map<String, Object?> row,
    List<ManagerProfile> managers,
  ) {
    final int pk = _asInt(row['SHIFT_ID']);
    final String managerId = '${row['MANAGER'] ?? ''}';
    ManagerRole role = ManagerRole.manager;
    for (final ManagerProfile manager in managers) {
      if (manager.id == managerId) {
        role = manager.role;
        break;
      }
    }
    final ManagerShiftStatus status = _statusFromStorage(
      '${row['STATUS'] ?? _statusOpen}',
    );
    final double actualStored = _asDouble(row['ACTUAL_CASH']);
    return ManagerShiftRecord(
      shiftId: formatShiftId(pk),
      managerId: managerId,
      managerName: (row['manager_name'] as String?)?.trim() ?? managerId,
      role: role,
      startTime:
          DateTime.tryParse('${row['START_TIME'] ?? ''}') ?? DateTime.now(),
      endTime: DateTime.tryParse('${row['END_TIME'] ?? ''}'),
      expectedCash: _asDouble(row['EXPECTED_CASH']),
      actualCash:
          status == ManagerShiftStatus.closed ||
              status == ManagerShiftStatus.forceClosed
          ? actualStored
          : null,
      status: status,
    );
  }

  static HelperSaleRecord _saleFromRow(Map<String, Object?> row) {
    final String helperId = '${row['HELPER'] ?? ''}'.trim();
    final String helperName = (row['helper_name'] as String?)?.trim() ?? '';
    final String managerId = '${row['Manager'] ?? ''}'.trim();
    final String managerName = (row['manager_name'] as String?)?.trim() ?? '';
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
      cashierName: managerName,
      managerId: managerId,
    );
  }

  static HelperSaleRecord _attachShift(
    HelperSaleRecord sale,
    List<ManagerShiftRecord> shifts,
  ) {
    if (sale.shiftId.isNotEmpty) {
      return sale;
    }
    for (final ManagerShiftRecord shift in shifts) {
      if (sale.managerId.isNotEmpty && sale.managerId != shift.managerId) {
        continue;
      }
      if (!isInShiftWindow(
        sale.timestamp,
        shift.startTime,
        end: shift.endTime,
      )) {
        continue;
      }
      return HelperSaleRecord(
        tokenNo: sale.tokenNo,
        timestamp: sale.timestamp,
        helperId: sale.helperId,
        helperName: sale.helperName,
        unitId: sale.unitId,
        fuelType: sale.fuelType,
        volumeLiters: sale.volumeLiters,
        rate: sale.rate,
        amountPkr: sale.amountPkr,
        payment: sale.payment,
        shiftId: shift.shiftId,
        cashierName: sale.cashierName.isEmpty
            ? shift.managerName
            : sale.cashierName,
        managerId: sale.managerId.isEmpty ? shift.managerId : sale.managerId,
      );
    }
    return sale;
  }

  static String _statusToStorage(ManagerShiftStatus status) {
    switch (status) {
      case ManagerShiftStatus.open:
        return _statusOpen;
      case ManagerShiftStatus.pendingReconciliation:
        return _statusPending;
      case ManagerShiftStatus.closed:
        return _statusClosed;
      case ManagerShiftStatus.forceClosed:
        return _statusForceClosed;
    }
  }

  static ManagerShiftStatus _statusFromStorage(String raw) {
    switch (raw.trim().toUpperCase()) {
      case _statusPending:
        return ManagerShiftStatus.pendingReconciliation;
      case _statusClosed:
        return ManagerShiftStatus.closed;
      case _statusForceClosed:
        return ManagerShiftStatus.forceClosed;
      default:
        return ManagerShiftStatus.open;
    }
  }

  static double _asDouble(Object? value) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    return 0;
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
}
