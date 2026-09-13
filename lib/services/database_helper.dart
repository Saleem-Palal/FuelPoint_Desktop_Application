import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:decimal/decimal.dart';

import '../core/security/pin_hasher.dart';
import '../features/shift/domain/shift_lifecycle.dart';
import '../features/station/domain/average_rate.dart';
import '../features/station/domain/fuel_precision.dart';

/// Singleton SQLite access for FuelPoint (`fuel_point_system.db`).
///
/// Uses `sqflite_common_ffi` + WAL so high-frequency ESP telemetry writes do
/// not lock the file. Liters and rate are TEXT at 13 fractional digits.
/// PKR amounts are whole rupees.
class DatabaseHelper {
  DatabaseHelper._init();

  static final DatabaseHelper instance = DatabaseHelper._init();

  static const String dbName = 'fuel_point_system.db';
  static const int dbVersion = 2;

  static const String tableManagers = 'managers';
  static const String tableHelpers = 'helpers';
  static const String tableCustomers = 'customers';
  static const String tableDieselStock = 'diesel_stock';
  static const String tableShifts = 'shifts';
  static const String tableSalesTransactions = 'sales_transactions';
  static const String tablePurchases = 'purchases';
  static const String tableUnifiedUdhaarLedger = 'unified_udhaar_ledger';
  static const String tableAuditLogs = 'audit_logs';
  static const String tableCloudBackupLogs = 'cloud_backup_logs';
  static const String tableStationSettings = 'station_settings';
  static const String tableAppSettings = 'app_settings';
  static const String tableAppSessionState = 'app_session_state';

  /// Preferred Windows data root. Falls back to app-support if unwritable.
  static const String windowsDataDirectory = r'C:\FuelPointData';

  static const String settingAutoBackupOnShiftClose =
      'auto_backup_drive_on_shift_close';
  static const String settingDriveBackupFolderId = 'drive_backup_folder_id';
  static const String settingGoogleOauthClientId = 'google_oauth_client_id';
  static const String settingGoogleOauthClientSecret =
      'google_oauth_client_secret';
  static const String settingAutoBackupIntervalHours =
      'auto_backup_interval_hours';
  static const String settingLastBackupAt = 'last_backup_at';
  static const String settingLastBackupFileName = 'last_backup_file_name';
  static const String settingLastBackupDriveFileId =
      'last_backup_drive_file_id';
  static const String settingOwnerMasterPinHash = 'owner_master_pin_hash';
  static const String defaultOwnerMasterPin = '1234';
  static const String settingOwnerAutoLockMinutes = 'owner_auto_lock_minutes';
  static const int defaultOwnerAutoLockMinutes = 5;
  static const String settingShowUnit5 = 'show_unit_5';
  static const String settingLowStockThresholdLiters =
      'low_stock_threshold_liters';

  /// Keys kept when `station_settings` is truncated so Drive OAuth survives.
  static const List<String> googleIdentitySettingKeys = <String>[
    settingGoogleOauthClientId,
    settingGoogleOauthClientSecret,
    settingDriveBackupFolderId,
  ];

  Database? _database;
  Future<Database>? _opening;
  bool _ffiReady = false;
  String? _resolvedDbPath;

  Future<Database> get database async {
    final Database? open = _database;
    if (open != null && open.isOpen) {
      return open;
    }
    return _opening ??= _openDatabase();
  }

  /// Opens `fuel_point_system.db`, creates core tables, and seeds the
  /// singleton `diesel_stock` row (`id = 1`, `Stock_amount = 0.0`).
  Future<Database> initializeStationDatabase() async {
    final Database db = await database;
    await db.insert(tableDieselStock, <String, Object?>{
      'id': 1,
      'stock_quantity': zeroFuelText,
      'Average_rate': zeroFuelText,
      'Stock_amount': 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    debugPrint(
      'DatabaseHelper: schema ready; diesel_stock singleton seeded (id=1)',
    );
    return db;
  }

  Future<Database> _openDatabase() async {
    try {
      _ensureFfi();
      final String dbPath = await databasePath;
      final Database db = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: dbVersion,
          onConfigure: _onConfigure,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
          onOpen: _onOpen,
        ),
      );
      _database = db;
      return db;
    } catch (error, stack) {
      _opening = null;
      debugPrint('DatabaseHelper: failed to open $dbName: $error\n$stack');
      rethrow;
    }
  }

  void _ensureFfi() {
    if (_ffiReady) {
      return;
    }
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _ffiReady = true;
  }

  /// Absolute path of `fuel_point_system.db` (and sibling WAL/credential files).
  Future<String> get databasePath async {
    return _resolvedDbPath ??= await _resolveDbPath();
  }

  Future<String> get dataDirectoryPath async {
    return p.dirname(await databasePath);
  }

  Future<String> _resolveDbPath() async {
    Future<String> supportPath() async {
      final Directory dir = await getApplicationSupportDirectory();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return p.join(dir.path, dbName);
    }

    if (!Platform.isWindows) {
      return supportPath();
    }

    try {
      final Directory preferred = Directory(windowsDataDirectory);
      if (!await preferred.exists()) {
        await preferred.create(recursive: true);
      }
      final String preferredPath = p.join(preferred.path, dbName);
      final String legacyPath = await supportPath();
      if (preferredPath != legacyPath) {
        await _migrateDbSidecars(
          fromDbPath: legacyPath,
          toDbPath: preferredPath,
        );
      }
      return preferredPath;
    } catch (error, stack) {
      debugPrint(
        'DatabaseHelper: could not use $windowsDataDirectory: $error\n$stack',
      );
      return supportPath();
    }
  }

  Future<void> _migrateDbSidecars({
    required String fromDbPath,
    required String toDbPath,
  }) async {
    final File fromDb = File(fromDbPath);
    final File toDb = File(toDbPath);
    if (!await fromDb.exists() || await toDb.exists()) {
      return;
    }
    await fromDb.copy(toDbPath);
    for (final String suffix in const <String>['-wal', '-shm']) {
      final File fromSide = File('$fromDbPath$suffix');
      if (await fromSide.exists()) {
        await fromSide.copy('$toDbPath$suffix');
      }
    }
    debugPrint('DatabaseHelper: migrated $fromDbPath -> $toDbPath');
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON;');
  }

  Future<void> _onOpen(Database db) async {
    await db.execute('PRAGMA journal_mode = WAL;');
    await db.execute('PRAGMA synchronous = NORMAL;');
    await db.execute('PRAGMA busy_timeout = 5000;');
    await _createSchema(db);
    await _ensureDieselStockSchema(db);
    await _ensureFuelPrecisionSchema(db);
    await _ensureSalesTransactionDutyIds(db);
    await _ensureShiftWorkflowSchema(db);
    await _seedOwnerAccessSettings(db);
    await _purgeLegacyDemoHelpers(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    await _ensureShiftWorkflowSchema(db);
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createSchema(db);
    await _ensureShiftWorkflowSchema(db);
    await _seedOwnerAccessSettings(db);
  }

  Future<void> _createSchema(Database db) async {
    final Batch batch = db.batch();

    batch.execute('''
CREATE TABLE IF NOT EXISTS $tableManagers (
  manager_ID TEXT PRIMARY KEY,
  Manager_name TEXT NOT NULL,
  pin TEXT NOT NULL
);
''');

    batch.execute('''
CREATE TABLE IF NOT EXISTS $tableHelpers (
  Helper_ID TEXT PRIMARY KEY,
  Helper_name TEXT NOT NULL
);
''');

    batch.execute('''
CREATE TABLE IF NOT EXISTS $tableCustomers (
  customer_ID TEXT PRIMARY KEY,
  Customer_Name TEXT NOT NULL
);
''');

    batch.execute('''
CREATE TABLE IF NOT EXISTS $tableDieselStock (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  stock_quantity TEXT NOT NULL DEFAULT '0.0000000000000',
  Average_rate TEXT NOT NULL DEFAULT '0.0000000000000',
  Stock_amount REAL NOT NULL DEFAULT 0
);
''');

    batch.execute('''
CREATE TABLE IF NOT EXISTS $tableShifts (
  SHIFT_ID INTEGER PRIMARY KEY AUTOINCREMENT,
  MANAGER TEXT NOT NULL,
  Helper TEXT,
  START_TIME TEXT NOT NULL,
  END_TIME TEXT,
  EXPECTED_CASH REAL DEFAULT 0.0,
  ACTUAL_CASH REAL DEFAULT 0.0,
  DISCREPANCY REAL DEFAULT 0.0,
  STATUS TEXT NOT NULL DEFAULT 'LIVE',
  NOTES TEXT NOT NULL DEFAULT '',
  OPENING_METERS TEXT NOT NULL DEFAULT '{}',
  CLOSING_METERS TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (MANAGER) REFERENCES $tableManagers (manager_ID),
  FOREIGN KEY (Helper) REFERENCES $tableHelpers (Helper_ID)
);
''');

    batch.execute('''
CREATE TABLE IF NOT EXISTS $tableSalesTransactions (
  TOKEN TEXT PRIMARY KEY,
  DATE_TIME TEXT NOT NULL,
  UNIT_NO INTEGER NOT NULL,
  AMOUNT REAL NOT NULL,
  LITERS TEXT NOT NULL,
  RATE TEXT NOT NULL,
  OPENING_READING REAL NOT NULL,
  CLOSING_READING REAL NOT NULL,
  PAYMENT_METHOD TEXT NOT NULL,
  CUSTOMER_NAME TEXT,
  VEHICLE_NO TEXT,
  HELPER TEXT,
  Manager TEXT NOT NULL,
  SHIFT_ID INTEGER,
  MANAGER_ID TEXT,
  HELPER_ID TEXT,
  ACTIONS TEXT,
  ESP_TX_ID TEXT,
  FOREIGN KEY (HELPER) REFERENCES $tableHelpers (Helper_ID),
  FOREIGN KEY (Manager) REFERENCES $tableManagers (manager_ID),
  FOREIGN KEY (SHIFT_ID) REFERENCES $tableShifts (SHIFT_ID),
  FOREIGN KEY (MANAGER_ID) REFERENCES $tableManagers (manager_ID),
  FOREIGN KEY (HELPER_ID) REFERENCES $tableHelpers (Helper_ID)
);
''');

    batch.execute('''
CREATE TABLE IF NOT EXISTS $tablePurchases (
  INV_NO TEXT PRIMARY KEY,
  DATETIME TEXT NOT NULL,
  QUANTITY TEXT NOT NULL,
  RATE TEXT NOT NULL,
  AMOUNT REAL NOT NULL,
  TAFSEEL TEXT,
  Manager TEXT NOT NULL,
  FOREIGN KEY (Manager) REFERENCES $tableManagers (manager_ID)
);
''');

    batch.execute('''
CREATE TABLE IF NOT EXISTS $tableUnifiedUdhaarLedger (
  PRIMARY_KEY TEXT PRIMARY KEY,
  TYPE TEXT NOT NULL CHECK (TYPE IN ('SALE', 'SETTLEMENT')),
  TKN TEXT,
  DATE_TIME TEXT NOT NULL,
  Customer_name TEXT NOT NULL,
  Customer_ID TEXT NOT NULL,
  LITERS TEXT DEFAULT '0.0000000000000',
  RATE TEXT DEFAULT '0.0000000000000',
  AMOUNT REAL NOT NULL,
  DESCRIPTION TEXT,
  VEHICLE TEXT,
  UDHAAR REAL DEFAULT 0.0,
  PAID REAL DEFAULT 0.0,
  REMAINING REAL NOT NULL,
  Status TEXT NOT NULL DEFAULT 'Unpaid'
    CHECK (Status IN ('Unpaid', 'Partially Paid', 'Paid')),
  FOREIGN KEY (TKN) REFERENCES $tableSalesTransactions (TOKEN),
  FOREIGN KEY (Customer_ID) REFERENCES $tableCustomers (customer_ID)
);
''');

    batch.execute('''
CREATE TABLE IF NOT EXISTS $tableAuditLogs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  timestamp TEXT NOT NULL,
  manager_ID TEXT,
  action_type TEXT NOT NULL,
  details TEXT,
  elevated_by_owner INTEGER NOT NULL DEFAULT 0
);
''');

    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_audit_logs_action '
      'ON $tableAuditLogs (action_type);',
    );
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_audit_logs_timestamp '
      'ON $tableAuditLogs (timestamp);',
    );

    batch.execute('''
CREATE TABLE IF NOT EXISTS $tableCloudBackupLogs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  timestamp TEXT NOT NULL,
  file_name TEXT NOT NULL,
  drive_file_id TEXT,
  status TEXT NOT NULL,
  trigger_source TEXT,
  details TEXT,
  manager_ID TEXT
);
''');
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_cloud_backup_logs_timestamp '
      'ON $tableCloudBackupLogs (timestamp);',
    );

    batch.execute('''
CREATE TABLE IF NOT EXISTS $tableStationSettings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
''');

    batch.execute('''
CREATE TABLE IF NOT EXISTS $tableAppSettings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
''');

    batch.execute('''
CREATE TABLE IF NOT EXISTS $tableAppSessionState (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  is_clean_shutdown INTEGER NOT NULL DEFAULT 1,
  last_heartbeat_at TEXT,
  unclean_exit_at TEXT
);
''');

    await batch.commit(noResult: true);
  }

  /// Adds SHIFT_ID / MANAGER_ID / HELPER_ID on existing `sales_transactions`.
  Future<void> _ensureSalesTransactionDutyIds(Database db) async {
    try {
      final List<Map<String, Object?>> cols = await db.rawQuery(
        'PRAGMA table_info($tableSalesTransactions)',
      );
      final Set<String> names = <String>{
        for (final Map<String, Object?> col in cols) '${col['name']}',
      };
      if (!names.contains('SHIFT_ID')) {
        await db.execute(
          'ALTER TABLE $tableSalesTransactions ADD COLUMN SHIFT_ID INTEGER',
        );
      }
      if (!names.contains('MANAGER_ID')) {
        await db.execute(
          'ALTER TABLE $tableSalesTransactions ADD COLUMN MANAGER_ID TEXT',
        );
        await db.execute('''
UPDATE $tableSalesTransactions
SET MANAGER_ID = Manager
WHERE MANAGER_ID IS NULL OR TRIM(MANAGER_ID) = ''
''');
      }
      if (!names.contains('HELPER_ID')) {
        await db.execute(
          'ALTER TABLE $tableSalesTransactions ADD COLUMN HELPER_ID TEXT',
        );
        await db.execute('''
UPDATE $tableSalesTransactions
SET HELPER_ID = HELPER
WHERE HELPER_ID IS NULL OR TRIM(HELPER_ID) = ''
''');
      }
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sales_transactions_shift_id '
        'ON $tableSalesTransactions (SHIFT_ID)',
      );
      if (!names.contains('ESP_TX_ID')) {
        await db.execute(
          'ALTER TABLE $tableSalesTransactions ADD COLUMN ESP_TX_ID TEXT',
        );
      }
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_sales_transactions_esp_tx_id '
        'ON $tableSalesTransactions (ESP_TX_ID) '
        "WHERE ESP_TX_ID IS NOT NULL AND TRIM(ESP_TX_ID) != ''",
      );
    } catch (error, stack) {
      debugPrint(
        'DatabaseHelper._ensureSalesTransactionDutyIds failed: $error\n$stack',
      );
    }
  }

  /// LIVE status, session heartbeat, shift notes/meters, owner-elevation audit.
  Future<void> _ensureShiftWorkflowSchema(Database db) async {
    try {
      await db.execute('''
CREATE TABLE IF NOT EXISTS $tableAppSessionState (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  is_clean_shutdown INTEGER NOT NULL DEFAULT 1,
  last_heartbeat_at TEXT,
  unclean_exit_at TEXT
);
''');
      await db.insert(tableAppSessionState, <String, Object?>{
        'id': 1,
        'is_clean_shutdown': 1,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

      final List<Map<String, Object?>> shiftCols = await db.rawQuery(
        'PRAGMA table_info($tableShifts)',
      );
      final Set<String> shiftNames = <String>{
        for (final Map<String, Object?> col in shiftCols) '${col['name']}',
      };
      if (!shiftNames.contains('NOTES')) {
        await db.execute(
          "ALTER TABLE $tableShifts ADD COLUMN NOTES TEXT NOT NULL DEFAULT ''",
        );
      }
      if (!shiftNames.contains('OPENING_METERS')) {
        await db.execute(
          "ALTER TABLE $tableShifts ADD COLUMN OPENING_METERS TEXT NOT NULL DEFAULT '{}'",
        );
      }
      if (!shiftNames.contains('CLOSING_METERS')) {
        await db.execute(
          "ALTER TABLE $tableShifts ADD COLUMN CLOSING_METERS TEXT NOT NULL DEFAULT '{}'",
        );
      }
      await db.execute(
        "UPDATE $tableShifts SET STATUS = 'LIVE' "
        "WHERE UPPER(TRIM(STATUS)) = 'OPEN'",
      );

      final List<Map<String, Object?>> auditCols = await db.rawQuery(
        'PRAGMA table_info($tableAuditLogs)',
      );
      final Set<String> auditNames = <String>{
        for (final Map<String, Object?> col in auditCols) '${col['name']}',
      };
      if (!auditNames.contains('elevated_by_owner')) {
        await db.execute(
          'ALTER TABLE $tableAuditLogs ADD COLUMN elevated_by_owner '
          'INTEGER NOT NULL DEFAULT 0',
        );
      }
    } catch (error, stack) {
      debugPrint(
        'DatabaseHelper._ensureShiftWorkflowSchema failed: $error\n$stack',
      );
    }
  }

  /// Ensures the singleton `diesel_stock` row (`id = 1`) has
  /// `stock_quantity`, `Average_rate`, and `Stock_amount`.
  ///
  /// Existing DBs stored liters in `Stock_amount`. That volume is copied into
  /// `stock_quantity`, then `Stock_amount` becomes quantity × average rate.
  Future<void> _ensureDieselStockSchema(Database db) async {
    try {
      final List<Map<String, Object?>> cols = await db.rawQuery(
        'PRAGMA table_info($tableDieselStock)',
      );
      final Set<String> names = <String>{
        for (final Map<String, Object?> col in cols) '${col['name']}',
      };
      if (!names.contains('Average_rate')) {
        await db.execute(
          'ALTER TABLE $tableDieselStock '
          'ADD COLUMN Average_rate REAL NOT NULL DEFAULT 0.0',
        );
        names.add('Average_rate');
        await db.execute('''
UPDATE $tableDieselStock
SET Average_rate = (
  SELECT CASE
    WHEN COALESCE(SUM(QUANTITY), 0) = 0 THEN 0
    ELSE SUM(AMOUNT) / SUM(QUANTITY)
  END
  FROM $tablePurchases
  WHERE UPPER(TRIM(COALESCE(TAFSEEL, ''))) NOT LIKE 'DIP%'
)
WHERE id = 1
''');
      }
      if (!names.contains('stock_quantity')) {
        await db.execute(
          'ALTER TABLE $tableDieselStock '
          'ADD COLUMN stock_quantity REAL NOT NULL DEFAULT 0.0',
        );
        names.add('stock_quantity');
        await db.execute(
          'UPDATE $tableDieselStock SET stock_quantity = Stock_amount WHERE id = 1',
        );
        await db.execute(
          'UPDATE $tableDieselStock '
          'SET Stock_amount = stock_quantity * Average_rate WHERE id = 1',
        );
      }
      await db.insert(tableDieselStock, <String, Object?>{
        'id': 1,
        'stock_quantity': zeroFuelText,
        'Average_rate': zeroFuelText,
        'Stock_amount': 0,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    } catch (error, stack) {
      debugPrint(
        'DatabaseHelper._ensureDieselStockSchema failed: $error\n$stack',
      );
    }
  }

  /// Rebuilds liters/rate columns to TEXT (13-place) when an older REAL
  /// schema is still on disk. SQLite will not change affinity in place.
  Future<void> _ensureFuelPrecisionSchema(Database db) async {
    try {
      await db.execute('PRAGMA foreign_keys = OFF');
      if (!await _columnIsText(db, tableDieselStock, 'stock_quantity')) {
        await _rebuildTable(
          db,
          table: tableDieselStock,
          createSql:
              '''
CREATE TABLE ${tableDieselStock}__precision (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  stock_quantity TEXT NOT NULL DEFAULT '0.0000000000000',
  Average_rate TEXT NOT NULL DEFAULT '0.0000000000000',
  Stock_amount REAL NOT NULL DEFAULT 0
)
''',
          transform: (Map<String, Object?> row) {
            final Decimal qty = parseFuel(row['stock_quantity']);
            final Decimal rate = parseFuel(row['Average_rate']);
            return <String, Object?>{
              'id': row['id'] ?? 1,
              'stock_quantity': fuelToText(qty),
              'Average_rate': fuelToText(rate),
              'Stock_amount': roundRupees(qty * rate),
            };
          },
        );
      }
      if (!await _columnIsText(db, tablePurchases, 'QUANTITY')) {
        await _rebuildTable(
          db,
          table: tablePurchases,
          createSql:
              '''
CREATE TABLE ${tablePurchases}__precision (
  INV_NO TEXT PRIMARY KEY,
  DATETIME TEXT NOT NULL,
  QUANTITY TEXT NOT NULL,
  RATE TEXT NOT NULL,
  AMOUNT REAL NOT NULL,
  TAFSEEL TEXT,
  Manager TEXT NOT NULL,
  FOREIGN KEY (Manager) REFERENCES $tableManagers (manager_ID)
)
''',
          transform: (Map<String, Object?> row) {
            return <String, Object?>{
              'INV_NO': row['INV_NO'],
              'DATETIME': row['DATETIME'],
              'QUANTITY': fuelToText(row['QUANTITY']),
              'RATE': fuelToText(row['RATE']),
              'AMOUNT': roundRupees(row['AMOUNT']),
              'TAFSEEL': row['TAFSEEL'],
              'Manager': row['Manager'],
            };
          },
        );
      }
      if (!await _columnIsText(db, tableSalesTransactions, 'LITERS')) {
        await _rebuildTable(
          db,
          table: tableSalesTransactions,
          createSql:
              '''
CREATE TABLE ${tableSalesTransactions}__precision (
  TOKEN TEXT PRIMARY KEY,
  DATE_TIME TEXT NOT NULL,
  UNIT_NO INTEGER NOT NULL,
  AMOUNT REAL NOT NULL,
  LITERS TEXT NOT NULL,
  RATE TEXT NOT NULL,
  OPENING_READING REAL NOT NULL,
  CLOSING_READING REAL NOT NULL,
  PAYMENT_METHOD TEXT NOT NULL,
  CUSTOMER_NAME TEXT,
  VEHICLE_NO TEXT,
  HELPER TEXT,
  Manager TEXT NOT NULL,
  SHIFT_ID INTEGER,
  MANAGER_ID TEXT,
  HELPER_ID TEXT,
  ACTIONS TEXT,
  FOREIGN KEY (HELPER) REFERENCES $tableHelpers (Helper_ID),
  FOREIGN KEY (Manager) REFERENCES $tableManagers (manager_ID),
  FOREIGN KEY (SHIFT_ID) REFERENCES $tableShifts (SHIFT_ID),
  FOREIGN KEY (MANAGER_ID) REFERENCES $tableManagers (manager_ID),
  FOREIGN KEY (HELPER_ID) REFERENCES $tableHelpers (Helper_ID)
)
''',
          transform: (Map<String, Object?> row) {
            return <String, Object?>{
              'TOKEN': row['TOKEN'],
              'DATE_TIME': row['DATE_TIME'],
              'UNIT_NO': row['UNIT_NO'],
              'AMOUNT': roundRupees(row['AMOUNT']),
              'LITERS': fuelToText(row['LITERS']),
              'RATE': fuelToText(row['RATE']),
              'OPENING_READING': row['OPENING_READING'],
              'CLOSING_READING': row['CLOSING_READING'],
              'PAYMENT_METHOD': row['PAYMENT_METHOD'],
              'CUSTOMER_NAME': row['CUSTOMER_NAME'],
              'VEHICLE_NO': row['VEHICLE_NO'],
              'HELPER': row['HELPER'],
              'Manager': row['Manager'],
              'SHIFT_ID': row['SHIFT_ID'],
              'MANAGER_ID': row['MANAGER_ID'],
              'HELPER_ID': row['HELPER_ID'],
              'ACTIONS': row['ACTIONS'],
            };
          },
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_sales_transactions_shift_id '
          'ON $tableSalesTransactions (SHIFT_ID)',
        );
      }
      if (!await _columnIsText(db, tableUnifiedUdhaarLedger, 'LITERS')) {
        await _rebuildTable(
          db,
          table: tableUnifiedUdhaarLedger,
          createSql:
              '''
CREATE TABLE ${tableUnifiedUdhaarLedger}__precision (
  PRIMARY_KEY TEXT PRIMARY KEY,
  TYPE TEXT NOT NULL CHECK (TYPE IN ('SALE', 'SETTLEMENT')),
  TKN TEXT,
  DATE_TIME TEXT NOT NULL,
  Customer_name TEXT NOT NULL,
  Customer_ID TEXT NOT NULL,
  LITERS TEXT DEFAULT '0.0000000000000',
  RATE TEXT DEFAULT '0.0000000000000',
  AMOUNT REAL NOT NULL,
  DESCRIPTION TEXT,
  VEHICLE TEXT,
  UDHAAR REAL DEFAULT 0.0,
  PAID REAL DEFAULT 0.0,
  REMAINING REAL NOT NULL,
  Status TEXT NOT NULL DEFAULT 'Unpaid'
    CHECK (Status IN ('Unpaid', 'Partially Paid', 'Paid')),
  FOREIGN KEY (TKN) REFERENCES $tableSalesTransactions (TOKEN),
  FOREIGN KEY (Customer_ID) REFERENCES $tableCustomers (customer_ID)
)
''',
          transform: (Map<String, Object?> row) {
            return <String, Object?>{
              'PRIMARY_KEY': row['PRIMARY_KEY'],
              'TYPE': row['TYPE'],
              'TKN': row['TKN'],
              'DATE_TIME': row['DATE_TIME'],
              'Customer_name': row['Customer_name'],
              'Customer_ID': row['Customer_ID'],
              'LITERS': fuelToText(row['LITERS']),
              'RATE': fuelToText(row['RATE']),
              'AMOUNT': roundRupees(row['AMOUNT']),
              'DESCRIPTION': row['DESCRIPTION'],
              'VEHICLE': row['VEHICLE'],
              'UDHAAR': roundRupees(row['UDHAAR']),
              'PAID': roundRupees(row['PAID']),
              'REMAINING': roundRupees(row['REMAINING']),
              'Status': row['Status'],
            };
          },
        );
      }
    } catch (error, stack) {
      debugPrint(
        'DatabaseHelper._ensureFuelPrecisionSchema failed: $error\n$stack',
      );
    } finally {
      await db.execute('PRAGMA foreign_keys = ON');
    }
  }

  Future<bool> _columnIsText(Database db, String table, String column) async {
    final List<Map<String, Object?>> cols = await db.rawQuery(
      'PRAGMA table_info($table)',
    );
    for (final Map<String, Object?> col in cols) {
      if ('${col['name']}' == column) {
        return '${col['type']}'.toUpperCase() == 'TEXT';
      }
    }
    return false;
  }

  Future<void> _rebuildTable(
    Database db, {
    required String table,
    required String createSql,
    required Map<String, Object?> Function(Map<String, Object?> row) transform,
  }) async {
    final String tmp = '${table}__precision';
    await db.execute('DROP TABLE IF EXISTS $tmp');
    await db.execute(createSql);
    final List<Map<String, Object?>> rows = await db.query(table);
    if (rows.isNotEmpty) {
      final Batch batch = db.batch();
      for (final Map<String, Object?> row in rows) {
        batch.insert(tmp, transform(row));
      }
      await batch.commit(noResult: true);
    }
    await db.execute('DROP TABLE $table');
    await db.execute('ALTER TABLE $tmp RENAME TO $table');
  }

  /// Seeds SHA-256(`1234`) when `owner_master_pin_hash` is missing.
  Future<void> _seedOwnerMasterPin(Database db) async {
    try {
      final List<Map<String, Object?>> rows = await db.query(
        tableAppSettings,
        columns: const <String>['value'],
        where: 'key = ?',
        whereArgs: const <Object>[settingOwnerMasterPinHash],
        limit: 1,
      );
      final String stored = rows.isEmpty
          ? ''
          : '${rows.first['value'] ?? ''}'.trim();
      if (stored.isNotEmpty) {
        return;
      }
      await db.insert(tableAppSettings, <String, Object?>{
        'key': settingOwnerMasterPinHash,
        'value': PinHasher.hash(defaultOwnerMasterPin),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      debugPrint(
        'DatabaseHelper: seeded default owner Master PIN hash in $tableAppSettings',
      );
    } catch (error, stack) {
      debugPrint('DatabaseHelper._seedOwnerMasterPin failed: $error\n$stack');
    }
  }

  Future<void> _seedOwnerAutoLockMinutes(Database db) async {
    try {
      final List<Map<String, Object?>> rows = await db.query(
        tableAppSettings,
        columns: const <String>['value'],
        where: 'key = ?',
        whereArgs: const <Object>[settingOwnerAutoLockMinutes],
        limit: 1,
      );
      final String stored = rows.isEmpty
          ? ''
          : '${rows.first['value'] ?? ''}'.trim();
      if (stored.isNotEmpty) {
        return;
      }
      await db.insert(tableAppSettings, <String, Object?>{
        'key': settingOwnerAutoLockMinutes,
        'value': '$defaultOwnerAutoLockMinutes',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      debugPrint(
        'DatabaseHelper: seeded owner auto-lock minutes='
        '$defaultOwnerAutoLockMinutes',
      );
    } catch (error, stack) {
      debugPrint(
        'DatabaseHelper._seedOwnerAutoLockMinutes failed: $error\n$stack',
      );
    }
  }

  Future<void> _seedOwnerAccessSettings(Database db) async {
    await _seedOwnerMasterPin(db);
    await _seedOwnerAutoLockMinutes(db);
  }

  /// Old in-memory seed (Sajjad / Babar / Tariq / Rashid) was written into
  /// `helpers` when those IDs were assigned on a bay and a sale was committed.
  /// Strip only that exact ID+name pair so a later real helper can reuse `hlp-1`.
  Future<void> _purgeLegacyDemoHelpers(Database db) async {
    const List<({String id, String name})> demo = <({String id, String name})>[
      (id: 'hlp-1', name: 'Sajjad Ali'),
      (id: 'hlp-2', name: 'Babar Azam'),
      (id: 'hlp-3', name: 'Tariq M.'),
      (id: 'hlp-4', name: 'Rashid K.'),
    ];
    for (final ({String id, String name}) row in demo) {
      final List<Map<String, Object?>> match = await db.query(
        tableHelpers,
        columns: const <String>['Helper_ID'],
        where: 'Helper_ID = ? AND Helper_name = ?',
        whereArgs: <Object>[row.id, row.name],
        limit: 1,
      );
      if (match.isEmpty) {
        continue;
      }
      await db.update(
        tableSalesTransactions,
        const <String, Object?>{'HELPER': null},
        where: 'HELPER = ?',
        whereArgs: <Object>[row.id],
      );
      await db.update(
        tableShifts,
        const <String, Object?>{'Helper': null},
        where: 'Helper = ?',
        whereArgs: <Object>[row.id],
      );
      await db.delete(
        tableHelpers,
        where: 'Helper_ID = ? AND Helper_name = ?',
        whereArgs: <Object>[row.id, row.name],
      );
    }
  }

  /// Inserts a committed sale, upserts FK parents, and decrements stock.
  Future<void> commitSaleTransaction({
    required Map<String, Object?> sale,
    required String managerId,
    required String managerName,
    required String managerPin,
    String? helperId,
    String? helperName,
    required double volumeLiters,
    String? creditCustomerId,
    String? creditCustomerName,
    String? creditShiftId,
    String? creditDescription,
    String? creditVehicle,
  }) async {
    try {
      final Database db = await database;
      await db.transaction((Transaction txn) async {
        await txn.insert(tableManagers, <String, Object?>{
          'manager_ID': managerId,
          'Manager_name': managerName,
          'pin': PinHasher.hashIfPlain(managerPin),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        final String? resolvedHelperId = helperId?.trim();
        if (resolvedHelperId != null && resolvedHelperId.isNotEmpty) {
          await txn.insert(tableHelpers, <String, Object?>{
            'Helper_ID': resolvedHelperId,
            'Helper_name': helperName?.trim().isNotEmpty == true
                ? helperName!.trim()
                : resolvedHelperId,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        final Map<String, Object?> saleRow = Map<String, Object?>.from(sale)
          ..removeWhere((String _, Object? value) => value == null);
        saleRow['LITERS'] = fuelToText(saleRow['LITERS']);
        saleRow['RATE'] = fuelToText(saleRow['RATE']);
        final String espTxId = '${saleRow['ESP_TX_ID'] ?? ''}'.trim();
        if (espTxId.isNotEmpty) {
          saleRow['AMOUNT'] = parseDecimal(saleRow['AMOUNT'])
              .truncate(scale: 2)
              .toDouble();
        } else {
          saleRow['AMOUNT'] = roundRupees(saleRow['AMOUNT']);
        }
        if (espTxId.isNotEmpty) {
          final List<Map<String, Object?>> existing = await txn.query(
            tableSalesTransactions,
            columns: <String>['TOKEN'],
            where: 'ESP_TX_ID = ?',
            whereArgs: <Object>[espTxId],
            limit: 1,
          );
          if (existing.isNotEmpty) {
            return;
          }
        }
        await txn.insert(tableSalesTransactions, saleRow);
        final String? creditId = creditCustomerId?.trim();
        if (creditId != null && creditId.isNotEmpty) {
          final String creditName =
              (creditCustomerName ?? sale['CUSTOMER_NAME'] as String? ?? '')
                  .trim();
          await _upsertCustomerTxn(
            txn,
            id: creditId,
            name: creditName.isEmpty ? creditId : creditName,
          );
          await _insertUnifiedUdhaarTxn(
            txn,
            type: 'SALE',
            shiftId: creditShiftId ?? '',
            customerId: creditId,
            customerName: creditName.isEmpty ? creditId : creditName,
            at:
                DateTime.tryParse('${sale['DATE_TIME'] ?? ''}') ??
                DateTime.now(),
            amount: parseDecimal(saleRow['AMOUNT']).toDouble(),
            token: sale['TOKEN'] as String?,
            liters: parseFuel(saleRow['LITERS']).toDouble(),
            rate: parseFuel(saleRow['RATE']).toDouble(),
            description: creditDescription ?? '',
            vehicle: creditVehicle ?? sale['VEHICLE_NO'] as String?,
          );
        }
        await _applyStockDelta(txn, parseFuel(-volumeLiters));
      });
    } catch (error, stack) {
      debugPrint('DatabaseHelper.commitSaleTransaction failed: $error\n$stack');
      rethrow;
    }
  }

  static const String _salesSelectSql =
      '''
SELECT
  s.TOKEN,
  s.DATE_TIME,
  s.UNIT_NO,
  s.AMOUNT,
  s.LITERS,
  s.RATE,
  s.OPENING_READING,
  s.CLOSING_READING,
  s.PAYMENT_METHOD,
  s.CUSTOMER_NAME,
  s.VEHICLE_NO,
  s.HELPER,
  s.Manager,
  s.SHIFT_ID,
  s.MANAGER_ID,
  s.HELPER_ID,
  s.ACTIONS,
  m.Manager_name AS manager_name,
  h.Helper_name AS helper_name
FROM $tableSalesTransactions s
LEFT JOIN $tableManagers m ON m.manager_ID = COALESCE(s.MANAGER_ID, s.Manager)
LEFT JOIN $tableHelpers h ON h.Helper_ID = COALESCE(s.HELPER_ID, s.HELPER)
''';

  Future<List<Map<String, Object?>>> queryRecentSales({int limit = 20}) async {
    return _querySales(limit: limit);
  }

  Future<List<Map<String, Object?>>> queryAllSales() async {
    return _querySales();
  }

  /// Itemized `sales_transactions` for one shift, including untagged rows
  /// whose `DATE_TIME` falls inside that shift window.
  Future<List<Map<String, Object?>>> querySalesByShiftId(int shiftId) async {
    if (shiftId <= 0) {
      return const <Map<String, Object?>>[];
    }
    try {
      final Database db = await database;
      final List<Map<String, Object?>> shifts = await db.query(
        tableShifts,
        columns: const <String>['START_TIME', 'END_TIME'],
        where: 'SHIFT_ID = ?',
        whereArgs: <Object>[shiftId],
        limit: 1,
      );
      if (shifts.isEmpty) {
        return const <Map<String, Object?>>[];
      }
      final String start = '${shifts.first['START_TIME'] ?? ''}';
      final String end = '${shifts.first['END_TIME'] ?? ''}'.trim();
      return db.rawQuery(
        '''
$_salesSelectSql
WHERE (
  s.SHIFT_ID = ?
  OR (
    s.SHIFT_ID IS NULL
    AND datetime(s.DATE_TIME) >= datetime(?)
    AND (? = '' OR datetime(s.DATE_TIME) <= datetime(?))
  )
)
ORDER BY datetime(s.DATE_TIME) DESC, s.TOKEN DESC
''',
        <Object>[shiftId, start, end, end],
      );
    } catch (error, stack) {
      debugPrint('DatabaseHelper.querySalesByShiftId failed: $error\n$stack');
      rethrow;
    }
  }

  /// Helper-tab ledger: `sales_transactions` rows for one `helpers.Helper_ID`
  /// whose `DATE_TIME` falls on an inclusive calendar range.
  Future<List<Map<String, Object?>>> querySalesForHelper({
    required String helperId,
    required DateTime fromInclusive,
    required DateTime toInclusive,
  }) async {
    final String id = helperId.trim();
    if (id.isEmpty) {
      return const <Map<String, Object?>>[];
    }
    return _querySales(
      helperId: id,
      fromInclusive: fromInclusive,
      toInclusive: toInclusive,
    );
  }

  Future<Map<String, Object?>?> querySaleByToken(String token) async {
    try {
      final Database db = await database;
      final List<Map<String, Object?>> rows = await db.rawQuery(
        '$_salesSelectSql WHERE s.TOKEN = ? LIMIT 1',
        <Object>[token],
      );
      if (rows.isEmpty) {
        return null;
      }
      return rows.first;
    } catch (error, stack) {
      debugPrint('DatabaseHelper.querySaleByToken failed: $error\n$stack');
      rethrow;
    }
  }

  Future<List<Map<String, Object?>>> _querySales({
    String? helperId,
    DateTime? fromInclusive,
    DateTime? toInclusive,
    int? shiftId,
    int? limit,
  }) async {
    try {
      final Database db = await database;
      final StringBuffer sql = StringBuffer(_salesSelectSql);
      final List<Object> args = <Object>[];
      final List<String> where = <String>[];
      final String? resolvedHelper = helperId?.trim();
      if (resolvedHelper != null && resolvedHelper.isNotEmpty) {
        where.add('(s.HELPER_ID = ? OR s.HELPER = ?)');
        args.add(resolvedHelper);
        args.add(resolvedHelper);
      }
      if (shiftId != null && shiftId > 0) {
        where.add('s.SHIFT_ID = ?');
        args.add(shiftId);
      }
      if (fromInclusive != null) {
        final DateTime start = DateTime(
          fromInclusive.year,
          fromInclusive.month,
          fromInclusive.day,
        );
        where.add('datetime(s.DATE_TIME) >= datetime(?)');
        args.add(start.toIso8601String());
      }
      if (toInclusive != null) {
        final DateTime endExclusive = DateTime(
          toInclusive.year,
          toInclusive.month,
          toInclusive.day,
        ).add(const Duration(days: 1));
        where.add('datetime(s.DATE_TIME) < datetime(?)');
        args.add(endExclusive.toIso8601String());
      }
      if (where.isNotEmpty) {
        sql.write(' WHERE ');
        sql.write(where.join(' AND '));
      }
      sql.write(' ORDER BY datetime(s.DATE_TIME) DESC, s.TOKEN DESC');
      if (limit != null) {
        sql.write(' LIMIT ?');
        args.add(limit);
      }
      return db.rawQuery(sql.toString(), args);
    } catch (error, stack) {
      debugPrint('DatabaseHelper.querySales failed: $error\n$stack');
      rethrow;
    }
  }

  Future<void> markSaleSettled({
    required String token,
    required String actions,
  }) async {
    try {
      final Database db = await database;
      final int changed = await db.update(
        tableSalesTransactions,
        <String, Object?>{'ACTIONS': actions},
        where: 'TOKEN = ?',
        whereArgs: <Object>[token],
      );
      if (changed == 0) {
        throw StateError('No sale found for token $token');
      }
    } catch (error, stack) {
      debugPrint('DatabaseHelper.markSaleSettled failed: $error\n$stack');
      rethrow;
    }
  }

  Future<void> updateSalesTransaction({
    required String token,
    required String? customerName,
    required String? vehicleNo,
    required String paymentMethod,
  }) async {
    try {
      final Database db = await database;
      await db.update(
        tableSalesTransactions,
        <String, Object?>{
          'CUSTOMER_NAME': customerName,
          'VEHICLE_NO': vehicleNo,
          'PAYMENT_METHOD': paymentMethod,
        },
        where: 'TOKEN = ?',
        whereArgs: <Object>[token],
      );
    } catch (error, stack) {
      debugPrint(
        'DatabaseHelper.updateSalesTransaction failed: $error\n$stack',
      );
      rethrow;
    }
  }

  /// Current tank liters from `diesel_stock.stock_quantity`.
  Future<double> getStockAmount() async {
    try {
      final ({double quantity, double averageRate, double amount}) stock =
          await getDieselStock();
      return stock.quantity;
    } catch (error, stack) {
      debugPrint('DatabaseHelper.getStockAmount failed: $error\n$stack');
      rethrow;
    }
  }

  /// Singleton tank row: liters and WAC at 13-place TEXT; PKR is whole rupees.
  Future<({double quantity, double averageRate, double amount})>
  getDieselStock() async {
    try {
      final Database db = await database;
      final List<Map<String, Object?>> rows = await db.query(
        tableDieselStock,
        columns: const <String>[
          'stock_quantity',
          'Average_rate',
          'Stock_amount',
        ],
        where: 'id = ?',
        whereArgs: const <Object>[1],
        limit: 1,
      );
      if (rows.isEmpty) {
        await db.insert(tableDieselStock, <String, Object?>{
          'id': 1,
          'stock_quantity': zeroFuelText,
          'Average_rate': zeroFuelText,
          'Stock_amount': 0,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        return (quantity: 0.0, averageRate: 0.0, amount: 0.0);
      }
      return (
        quantity: _asDouble(rows.first['stock_quantity']),
        averageRate: _asDouble(rows.first['Average_rate']),
        amount: _asDouble(rows.first['Stock_amount']),
      );
    } catch (error, stack) {
      debugPrint('DatabaseHelper.getDieselStock failed: $error\n$stack');
      rethrow;
    }
  }

  /// Atomically add or subtract [deltaVolume] on `diesel_stock.id = 1`.
  ///
  /// [deltaVolume] is applied as stored — no rounding. Pass [isAddition] true
  /// for inbound purchases; false (default) for outbound sales.
  Future<void> updateStockAmount(
    double deltaVolume, {
    bool isAddition = false,
  }) async {
    try {
      final Database db = await database;
      final double signedDelta = isAddition ? deltaVolume : -deltaVolume;
      await db.transaction((Transaction txn) async {
        await _applyStockDelta(txn, parseFuel(signedDelta));
      });
    } catch (error, stack) {
      debugPrint('DatabaseHelper.updateStockAmount failed: $error\n$stack');
      rethrow;
    }
  }

  /// Replace the singleton stock row. Used by Initial Dip calibration.
  Future<void> setStockAmount(double volume) async {
    try {
      final Database db = await database;
      await db.transaction((Transaction txn) async {
        await _setStockAmount(txn, volume);
      });
    } catch (error, stack) {
      debugPrint('DatabaseHelper.setStockAmount failed: $error\n$stack');
      rethrow;
    }
  }

  /// Inserts a purchase, upserts the manager FK, and updates `diesel_stock`.
  ///
  /// WAC uses stored whole-rupee amounts:
  /// `(Stock_amount + this AMOUNT) / (stock_quantity + this QUANTITY)`.
  Future<void> commitPurchase({
    required String invNo,
    required String datetimeIso,
    required double quantity,
    required double rate,
    required double amount,
    required String managerId,
    required String managerName,
    required String managerPin,
    String tafseel = '',
  }) async {
    try {
      final Decimal liters = parseFuel(quantity);
      final Decimal unitRate = parseFuel(rate);
      final int rupees = roundRupees(amount);
      final Database db = await database;
      await db.transaction((Transaction txn) async {
        await txn.insert(tableManagers, <String, Object?>{
          'manager_ID': managerId,
          'Manager_name': managerName,
          'pin': PinHasher.hashIfPlain(managerPin),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        await txn.insert(tablePurchases, <String, Object?>{
          'INV_NO': invNo,
          'DATETIME': datetimeIso,
          'QUANTITY': fuelToText(liters),
          'RATE': fuelToText(unitRate),
          'AMOUNT': rupees,
          'TAFSEEL': tafseel.trim().isEmpty ? null : tafseel.trim(),
          'Manager': managerId,
        });
        await _applyPurchaseToStock(
          txn,
          purchaseLiters: liters,
          purchaseAmount: Decimal.fromInt(rupees),
        );
      });
    } catch (error, stack) {
      debugPrint('DatabaseHelper.commitPurchase failed: $error\n$stack');
      rethrow;
    }
  }

  /// Corrects an existing purchase in place. [invNo] is never rewritten.
  ///
  /// Stock is delta-adjusted from the current tank (not a history replay) so
  /// later invoices and sales keep their own running WAC.
  Future<void> updatePurchase({
    required String invNo,
    required double quantity,
    required double rate,
    required double amount,
    String tafseel = '',
  }) async {
    try {
      final Decimal newLiters = parseFuel(quantity);
      final Decimal newRate = parseFuel(rate);
      final int newRupees = roundRupees(amount);
      final Database db = await database;
      await db.transaction((Transaction txn) async {
        final List<Map<String, Object?>> rows = await txn.query(
          tablePurchases,
          columns: const <String>['QUANTITY', 'AMOUNT'],
          where: 'INV_NO = ?',
          whereArgs: <Object>[invNo],
          limit: 1,
        );
        if (rows.isEmpty) {
          throw StateError('Purchase $invNo was not found');
        }
        final Decimal oldLiters = parseFuel(rows.first['QUANTITY']);
        final Decimal oldAmount = rupeesDecimal(rows.first['AMOUNT']);
        final Decimal deltaLiters = truncateFuel(newLiters - oldLiters);
        final Decimal deltaAmount = Decimal.fromInt(newRupees) - oldAmount;
        if (deltaLiters != Decimal.zero || deltaAmount != Decimal.zero) {
          final ({Decimal quantity, Decimal averageRate, Decimal amount})
          current = await _readDieselStock(txn);
          if (truncateFuel(current.quantity + deltaLiters) < Decimal.zero) {
            throw const PurchaseStockOverdrawException();
          }
          await _applyPurchaseToStock(
            txn,
            purchaseLiters: deltaLiters,
            purchaseAmount: deltaAmount,
          );
        }
        await txn.update(
          tablePurchases,
          <String, Object?>{
            'QUANTITY': fuelToText(newLiters),
            'RATE': fuelToText(newRate),
            'AMOUNT': newRupees,
            'TAFSEEL': tafseel.trim().isEmpty ? null : tafseel.trim(),
          },
          where: 'INV_NO = ?',
          whereArgs: <Object>[invNo],
        );
      });
    } catch (error, stack) {
      debugPrint('DatabaseHelper.updatePurchase failed: $error\n$stack');
      rethrow;
    }
  }

  Future<List<Map<String, Object?>>> queryPurchases({int? limit}) async {
    try {
      final Database db = await database;
      final StringBuffer sql = StringBuffer('''
SELECT
  p.INV_NO,
  p.DATETIME,
  p.QUANTITY,
  p.RATE,
  p.AMOUNT,
  p.TAFSEEL,
  p.Manager,
  m.Manager_name AS manager_name
FROM $tablePurchases p
LEFT JOIN $tableManagers m ON m.manager_ID = p.Manager
ORDER BY datetime(p.DATETIME) DESC, p.INV_NO DESC
''');
      if (limit == null) {
        return db.rawQuery(sql.toString());
      }
      sql.write(' LIMIT ?');
      return db.rawQuery(sql.toString(), <Object>[limit]);
    } catch (error, stack) {
      debugPrint('DatabaseHelper.queryPurchases failed: $error\n$stack');
      rethrow;
    }
  }

  Future<int> nextPurchaseInvoiceNo() async {
    try {
      final Database db = await database;
      final List<Map<String, Object?>> rows = await db.query(
        tablePurchases,
        columns: const <String>['INV_NO'],
      );
      int highest = 999;
      for (final Map<String, Object?> row in rows) {
        final int parsed = _invoiceNumberOf('${row['INV_NO'] ?? ''}');
        if (parsed > highest) {
          highest = parsed;
        }
      }
      return highest + 1;
    } catch (error, stack) {
      debugPrint('DatabaseHelper.nextPurchaseInvoiceNo failed: $error\n$stack');
      rethrow;
    }
  }

  Future<List<Map<String, Object?>>> queryManagers() async {
    try {
      final Database db = await database;
      return db.query(
        tableManagers,
        orderBy: 'Manager_name COLLATE NOCASE ASC',
      );
    } catch (error, stack) {
      debugPrint('DatabaseHelper.queryManagers failed: $error\n$stack');
      rethrow;
    }
  }

  Future<void> upsertManager({
    required String managerId,
    required String managerName,
    required String pin,
  }) async {
    try {
      final String id = managerId.trim();
      final String name = managerName.trim();
      if (id.isEmpty || name.isEmpty) {
        throw ArgumentError('Manager ID and name are required');
      }
      final Database db = await database;
      await db.insert(tableManagers, <String, Object?>{
        'manager_ID': id,
        'Manager_name': name,
        'pin': PinHasher.hashIfPlain(pin),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (error, stack) {
      debugPrint('DatabaseHelper.upsertManager failed: $error\n$stack');
      rethrow;
    }
  }

  /// Managers joined with the latest `OPEN` shift, if any.
  Future<List<Map<String, Object?>>> queryManagersWithOpenShifts() async {
    try {
      final Database db = await database;
      return db.rawQuery('''
SELECT
  m.manager_ID,
  m.Manager_name,
  m.pin,
  (
    SELECT s.SHIFT_ID
    FROM $tableShifts s
    WHERE s.MANAGER = m.manager_ID
      AND ${ShiftStatusStorage.liveAliasSql}
    ORDER BY s.SHIFT_ID DESC
    LIMIT 1
  ) AS open_shift_id
FROM $tableManagers m
ORDER BY m.Manager_name COLLATE NOCASE ASC
''');
    } catch (error, stack) {
      debugPrint(
        'DatabaseHelper.queryManagersWithOpenShifts failed: $error\n$stack',
      );
      rethrow;
    }
  }

  Future<Map<String, Object?>?> queryManagerById(String managerId) async {
    try {
      final Database db = await database;
      final List<Map<String, Object?>> rows = await db.query(
        tableManagers,
        where: 'manager_ID = ?',
        whereArgs: <Object>[managerId.trim()],
        limit: 1,
      );
      return rows.isEmpty ? null : rows.first;
    } catch (error, stack) {
      debugPrint('DatabaseHelper.queryManagerById failed: $error\n$stack');
      rethrow;
    }
  }

  /// Verifies [pin] against `managers.pin` (hashed or leftover plaintext).
  Future<bool> verifyManagerPin({
    required String managerId,
    required String pin,
  }) async {
    try {
      final Map<String, Object?>? row = await queryManagerById(managerId);
      if (row == null) {
        return false;
      }
      final String stored = (row['pin'] as String?)?.trim() ?? '';
      return PinHasher.matches(entered: pin, stored: stored);
    } catch (error, stack) {
      debugPrint('DatabaseHelper.verifyManagerPin failed: $error\n$stack');
      return false;
    }
  }

  Future<double> sumPurchasesInWindow({
    required DateTime start,
    DateTime? end,
    String? managerId,
  }) async {
    try {
      final Database db = await database;
      final List<String> where = <String>['datetime(DATETIME) >= datetime(?)'];
      final List<Object> args = <Object>[start.toIso8601String()];
      if (end != null) {
        where.add('datetime(DATETIME) <= datetime(?)');
        args.add(end.toIso8601String());
      }
      final String? manager = managerId?.trim();
      if (manager != null && manager.isNotEmpty) {
        where.add('Manager = ?');
        args.add(manager);
      }
      final List<Map<String, Object?>> rows = await db.rawQuery(
        'SELECT COALESCE(SUM(AMOUNT), 0) AS total FROM $tablePurchases '
        'WHERE ${where.join(' AND ')}',
        args,
      );
      return _asDouble(rows.isEmpty ? 0 : rows.first['total']);
    } catch (error, stack) {
      debugPrint('DatabaseHelper.sumPurchasesInWindow failed: $error\n$stack');
      rethrow;
    }
  }

  Future<double> sumSettlementsForShift(String shiftId) async {
    try {
      final Database db = await database;
      final String prefix = '${_shiftToken(shiftId)}/';
      final List<Map<String, Object?>> rows = await db.rawQuery(
        'SELECT COALESCE(SUM(PAID), 0) AS total FROM $tableUnifiedUdhaarLedger '
        "WHERE TYPE = 'SETTLEMENT' AND PRIMARY_KEY LIKE ?",
        <Object>['$prefix%'],
      );
      return _asDouble(rows.isEmpty ? 0 : rows.first['total']);
    } catch (error, stack) {
      debugPrint(
        'DatabaseHelper.sumSettlementsForShift failed: $error\n$stack',
      );
      rethrow;
    }
  }

  Future<Map<String, Object?>?> queryOpenShiftForManager(
    String managerId,
  ) async {
    try {
      final Database db = await database;
      final List<Map<String, Object?>> rows = await db.query(
        tableShifts,
        columns: const <String>['SHIFT_ID', 'MANAGER', 'STATUS'],
        where: 'MANAGER = ? AND ${ShiftStatusStorage.liveSql}',
        whereArgs: <Object>[managerId.trim()],
        orderBy: 'SHIFT_ID DESC',
        limit: 1,
      );
      return rows.isEmpty ? null : rows.first;
    } catch (error, stack) {
      debugPrint(
        'DatabaseHelper.queryOpenShiftForManager failed: $error\n$stack',
      );
      rethrow;
    }
  }

  Future<String> nextManagerId() async {
    try {
      final List<Map<String, Object?>> rows = await queryManagers();
      int max = 0;
      for (final Map<String, Object?> row in rows) {
        final String id = '${row['manager_ID'] ?? ''}';
        if (!id.startsWith('mgr-')) {
          continue;
        }
        final int? parsed = int.tryParse(id.substring(4));
        if (parsed != null && parsed > max) {
          max = parsed;
        }
      }
      return 'mgr-${max + 1}';
    } catch (error, stack) {
      debugPrint('DatabaseHelper.nextManagerId failed: $error\n$stack');
      rethrow;
    }
  }

  /// Updates name always. Replaces the PIN only when [pin] is non-empty.
  Future<void> updateManager({
    required String managerId,
    required String managerName,
    String? pin,
  }) async {
    try {
      final String id = managerId.trim();
      final String name = managerName.trim();
      if (id.isEmpty || name.isEmpty) {
        throw ArgumentError('Manager ID and name are required');
      }
      final Database db = await database;
      final Map<String, Object?> values = <String, Object?>{
        'Manager_name': name,
      };
      final String? nextPin = pin?.trim();
      if (nextPin != null && nextPin.isNotEmpty) {
        values['pin'] = PinHasher.hashIfPlain(nextPin);
      }
      final int changed = await db.update(
        tableManagers,
        values,
        where: 'manager_ID = ?',
        whereArgs: <Object>[id],
      );
      if (changed == 0) {
        throw StateError('No manager found for $id');
      }
    } catch (error, stack) {
      debugPrint('DatabaseHelper.updateManager failed: $error\n$stack');
      rethrow;
    }
  }

  /// Hard-deletes a manager. Refuses if they hold an `OPEN` shift.
  Future<void> deleteManager(String managerId) async {
    final String id = managerId.trim();
    if (id.isEmpty) {
      throw ArgumentError('Manager ID is required');
    }
    try {
      final Database db = await database;
      final Map<String, Object?>? row = await queryManagerById(id);
      if (row == null) {
        throw StateError('No manager found for $id');
      }
      final Map<String, Object?>? open = await queryOpenShiftForManager(id);
      if (open != null) {
        throw ManagerHasOpenShiftException(
          managerId: id,
          managerName: (row['Manager_name'] as String?)?.trim() ?? id,
          shiftId: _asInt(open['SHIFT_ID']),
        );
      }
      final int changed = await db.delete(
        tableManagers,
        where: 'manager_ID = ?',
        whereArgs: <Object>[id],
      );
      if (changed == 0) {
        throw StateError('No manager found for $id');
      }
    } on ManagerHasOpenShiftException {
      rethrow;
    } catch (error, stack) {
      debugPrint('DatabaseHelper.deleteManager failed: $error\n$stack');
      if (_isForeignKeyError(error)) {
        throw ManagerInUseException(managerId: id);
      }
      rethrow;
    }
  }

  static bool _isForeignKeyError(Object error) {
    final String text = error.toString().toLowerCase();
    return text.contains('foreign key') || text.contains('constraint');
  }

  static int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    return int.tryParse('$value') ?? 0;
  }

  Future<List<Map<String, Object?>>> queryHelpers() async {
    try {
      final Database db = await database;
      return db.query(tableHelpers, orderBy: 'Helper_name COLLATE NOCASE ASC');
    } catch (error, stack) {
      debugPrint('DatabaseHelper.queryHelpers failed: $error\n$stack');
      rethrow;
    }
  }

  Future<void> upsertHelper({
    required String helperId,
    required String helperName,
  }) async {
    try {
      final Database db = await database;
      await db.insert(tableHelpers, <String, Object?>{
        'Helper_ID': helperId,
        'Helper_name': helperName,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (error, stack) {
      debugPrint('DatabaseHelper.upsertHelper failed: $error\n$stack');
      rethrow;
    }
  }

  static const String _shiftsSelectSql =
      '''
SELECT
  s.SHIFT_ID,
  s.MANAGER,
  s.Helper,
  s.START_TIME,
  s.END_TIME,
  s.EXPECTED_CASH,
  s.ACTUAL_CASH,
  s.DISCREPANCY,
  s.STATUS,
  s.NOTES,
  s.OPENING_METERS,
  s.CLOSING_METERS,
  m.Manager_name AS manager_name,
  h.Helper_name AS helper_name
FROM $tableShifts s
LEFT JOIN $tableManagers m ON m.manager_ID = s.MANAGER
LEFT JOIN $tableHelpers h ON h.Helper_ID = s.Helper
''';

  Future<List<Map<String, Object?>>> queryShifts() async {
    try {
      final Database db = await database;
      return db.rawQuery('$_shiftsSelectSql ORDER BY s.SHIFT_ID DESC');
    } catch (error, stack) {
      debugPrint('DatabaseHelper.queryShifts failed: $error\n$stack');
      rethrow;
    }
  }

  static const String _shiftLedgerSelectSql =
      '''
SELECT
  s.SHIFT_ID AS shift_id,
  s.MANAGER AS manager_id,
  m.Manager_name AS manager_name,
  s.START_TIME AS start_timestamp,
  s.END_TIME AS end_timestamp,
  s.STATUS AS shift_status,
  COUNT(t.TOKEN) AS total_transactions,
  COALESCE(SUM(t.AMOUNT), 0.0) AS total_shift_pkr,
  COALESCE(SUM(t.LITERS), 0.0) AS total_shift_liters
FROM $tableShifts s
LEFT JOIN $tableManagers m ON m.manager_ID = s.MANAGER
LEFT JOIN $tableSalesTransactions t ON (
  t.SHIFT_ID = s.SHIFT_ID
  OR (
    t.SHIFT_ID IS NULL
    AND datetime(t.DATE_TIME) >= datetime(s.START_TIME)
    AND (
      s.END_TIME IS NULL
      OR TRIM(s.END_TIME) = ''
      OR datetime(t.DATE_TIME) <= datetime(s.END_TIME)
    )
  )
)
GROUP BY s.SHIFT_ID, s.MANAGER, m.Manager_name, s.START_TIME, s.END_TIME, s.STATUS
ORDER BY datetime(s.START_TIME) DESC
''';

  /// Shift sessions with nested sales totals (`COUNT` / `SUM` over LEFT JOIN).
  Future<List<Map<String, Object?>>> queryShiftLedgerSummaries() async {
    try {
      final Database db = await database;
      return db.rawQuery(_shiftLedgerSelectSql);
    } catch (error, stack) {
      debugPrint(
        'DatabaseHelper.queryShiftLedgerSummaries failed: $error\n$stack',
      );
      rethrow;
    }
  }

  Future<int> insertShift({
    required String managerId,
    String? helperId,
    required String startTimeIso,
    String status = ShiftStatusStorage.live,
    double expectedCash = 0,
    double actualCash = 0,
    double discrepancy = 0,
    String? endTimeIso,
    String notes = '',
    String openingMeters = '{}',
    String closingMeters = '{}',
    DatabaseExecutor? executor,
  }) async {
    try {
      final DatabaseExecutor db = executor ?? await database;
      return db.insert(tableShifts, <String, Object?>{
        'MANAGER': managerId,
        'Helper': helperId,
        'START_TIME': startTimeIso,
        'END_TIME': endTimeIso,
        'EXPECTED_CASH': expectedCash,
        'ACTUAL_CASH': actualCash,
        'DISCREPANCY': discrepancy,
        'STATUS': status,
        'NOTES': notes,
        'OPENING_METERS': openingMeters,
        'CLOSING_METERS': closingMeters,
      });
    } catch (error, stack) {
      debugPrint('DatabaseHelper.insertShift failed: $error\n$stack');
      rethrow;
    }
  }

  Future<void> updateShift({
    required int shiftId,
    String? helperId,
    String? endTimeIso,
    double? expectedCash,
    double? actualCash,
    double? discrepancy,
    String? status,
    String? notes,
    String? openingMeters,
    String? closingMeters,
    DatabaseExecutor? executor,
  }) async {
    try {
      final DatabaseExecutor db = executor ?? await database;
      final Map<String, Object?> values = <String, Object?>{};
      if (helperId != null) {
        values['Helper'] = helperId;
      }
      if (endTimeIso != null) {
        values['END_TIME'] = endTimeIso;
      }
      if (expectedCash != null) {
        values['EXPECTED_CASH'] = expectedCash;
      }
      if (actualCash != null) {
        values['ACTUAL_CASH'] = actualCash;
      }
      if (discrepancy != null) {
        values['DISCREPANCY'] = discrepancy;
      }
      if (status != null) {
        values['STATUS'] = status;
      }
      if (notes != null) {
        values['NOTES'] = notes;
      }
      if (openingMeters != null) {
        values['OPENING_METERS'] = openingMeters;
      }
      if (closingMeters != null) {
        values['CLOSING_METERS'] = closingMeters;
      }
      if (values.isEmpty) {
        return;
      }
      final int changed = await db.update(
        tableShifts,
        values,
        where: 'SHIFT_ID = ?',
        whereArgs: <Object>[shiftId],
      );
      if (changed == 0) {
        throw StateError('No shift found for SHIFT_ID $shiftId');
      }
    } catch (error, stack) {
      debugPrint('DatabaseHelper.updateShift failed: $error\n$stack');
      rethrow;
    }
  }

  Future<T> runInTransaction<T>(
    Future<T> Function(Transaction txn) action,
  ) async {
    final Database db = await database;
    return db.transaction(action);
  }

  Future<List<Map<String, Object?>>> queryCustomers() async {
    try {
      final Database db = await database;
      return db.query(
        tableCustomers,
        orderBy: 'customer_ID COLLATE NOCASE ASC',
      );
    } catch (error, stack) {
      debugPrint('DatabaseHelper.queryCustomers failed: $error\n$stack');
      rethrow;
    }
  }

  Future<Map<String, Object?>?> queryCustomerById(String customerId) async {
    try {
      final Database db = await database;
      final List<Map<String, Object?>> rows = await db.query(
        tableCustomers,
        where: 'customer_ID = ?',
        whereArgs: <Object>[customerId],
        limit: 1,
      );
      return rows.isEmpty ? null : rows.first;
    } catch (error, stack) {
      debugPrint('DatabaseHelper.queryCustomerById failed: $error\n$stack');
      rethrow;
    }
  }

  Future<Map<String, Object?>?> queryCustomerByName(String name) async {
    try {
      final Database db = await database;
      final List<Map<String, Object?>> rows = await db.query(
        tableCustomers,
        where: 'UPPER(TRIM(Customer_Name)) = UPPER(TRIM(?))',
        whereArgs: <Object>[name],
        limit: 1,
      );
      return rows.isEmpty ? null : rows.first;
    } catch (error, stack) {
      debugPrint('DatabaseHelper.queryCustomerByName failed: $error\n$stack');
      rethrow;
    }
  }

  Future<int> nextCustomerSequence() async {
    try {
      final List<Map<String, Object?>> rows = await queryCustomers();
      int max = 0;
      for (final Map<String, Object?> row in rows) {
        final int? parsed = int.tryParse('${row['customer_ID'] ?? ''}');
        if (parsed != null && parsed > max) {
          max = parsed;
        }
      }
      return max + 1;
    } catch (error, stack) {
      debugPrint('DatabaseHelper.nextCustomerSequence failed: $error\n$stack');
      rethrow;
    }
  }

  Future<void> upsertCustomer({
    required String id,
    required String name,
  }) async {
    try {
      final Database db = await database;
      await db.transaction((Transaction txn) async {
        await _upsertCustomerTxn(txn, id: id, name: name);
      });
    } catch (error, stack) {
      debugPrint('DatabaseHelper.upsertCustomer failed: $error\n$stack');
      rethrow;
    }
  }

  Future<List<Map<String, Object?>>> queryUnifiedUdhaarLedger({
    String? customerId,
  }) async {
    try {
      final Database db = await database;
      final String? id = customerId?.trim();
      if (id == null || id.isEmpty) {
        return db.query(
          tableUnifiedUdhaarLedger,
          orderBy: 'datetime(DATE_TIME) ASC, PRIMARY_KEY ASC',
        );
      }
      return db.query(
        tableUnifiedUdhaarLedger,
        where: 'Customer_ID = ?',
        whereArgs: <Object>[id],
        orderBy: 'datetime(DATE_TIME) ASC, PRIMARY_KEY ASC',
      );
    } catch (error, stack) {
      debugPrint(
        'DatabaseHelper.queryUnifiedUdhaarLedger failed: $error\n$stack',
      );
      rethrow;
    }
  }

  Future<double> latestUdhaarRemaining(String customerId) async {
    try {
      final Database db = await database;
      return _latestRemainingOn(db, customerId);
    } catch (error, stack) {
      debugPrint('DatabaseHelper.latestUdhaarRemaining failed: $error\n$stack');
      rethrow;
    }
  }

  Future<int> nextSettlementReceiptSeq() async {
    try {
      final Database db = await database;
      final List<Map<String, Object?>> rows = await db.rawQuery(
        'SELECT COUNT(*) AS qty FROM $tableUnifiedUdhaarLedger WHERE TYPE = ?',
        const <Object>['SETTLEMENT'],
      );
      final Object? qty = rows.isEmpty ? 0 : rows.first['qty'];
      final int count = qty is int ? qty : (qty is num ? qty.round() : 0);
      return count + 1;
    } catch (error, stack) {
      debugPrint(
        'DatabaseHelper.nextSettlementReceiptSeq failed: $error\n$stack',
      );
      rethrow;
    }
  }

  Future<Map<String, Object?>> insertUnifiedUdhaarEntry({
    required String type,
    required String shiftId,
    required String customerId,
    required String customerName,
    required DateTime at,
    required double amount,
    String? token,
    double liters = 0,
    double rate = 0,
    String description = '',
    String? vehicle,
  }) async {
    try {
      final Database db = await database;
      return db.transaction((Transaction txn) async {
        await _upsertCustomerTxn(txn, id: customerId, name: customerName);
        return _insertUnifiedUdhaarTxn(
          txn,
          type: type,
          shiftId: shiftId,
          customerId: customerId,
          customerName: customerName,
          at: at,
          amount: amount,
          token: token,
          liters: liters,
          rate: rate,
          description: description,
          vehicle: vehicle,
        );
      });
    } catch (error, stack) {
      debugPrint(
        'DatabaseHelper.insertUnifiedUdhaarEntry failed: $error\n$stack',
      );
      rethrow;
    }
  }

  Future<void> close() async {
    try {
      final Database? db = _database;
      _database = null;
      _opening = null;
      if (db != null && db.isOpen) {
        await db.close();
      }
    } catch (error, stack) {
      debugPrint('DatabaseHelper.close failed: $error\n$stack');
      rethrow;
    }
  }

  Future<Database> reopen() async {
    await close();
    return database;
  }

  Future<({int dbBytes, int walBytes, String dbPath})>
  databaseFileMetrics() async {
    try {
      final String path = await databasePath;
      return (
        dbBytes: await _fileByteLength(path),
        walBytes: await _fileByteLength('$path-wal'),
        dbPath: path,
      );
    } catch (error, stack) {
      debugPrint('DatabaseHelper.databaseFileMetrics failed: $error\n$stack');
      rethrow;
    }
  }

  /// Writes a consistent SQLite snapshot to [destPath] without holding a
  /// long exclusive lock on the live WAL database.
  ///
  /// Prefers `VACUUM INTO` (crash-safe copy). Falls back to checkpoint +
  /// file copy when the SQLite build cannot vacuum into a new file.
  Future<File> createConsistentDatabaseCopy(String destPath) async {
    try {
      final File dest = File(destPath);
      final Directory parent = dest.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
      if (await dest.exists()) {
        await dest.delete();
      }
      await walCheckpointTruncate();
      try {
        final Database db = await database;
        final String sqlPath = destPath
            .replaceAll('\\', '/')
            .replaceAll("'", "''");
        await db.execute("VACUUM INTO '$sqlPath'");
        if (await dest.exists() && await dest.length() > 0) {
          debugPrint('DatabaseHelper: VACUUM INTO snapshot -> $destPath');
          return dest;
        }
        throw StateError('VACUUM INTO produced an empty file.');
      } catch (vacuumError, vacuumStack) {
        debugPrint(
          'DatabaseHelper: VACUUM INTO unavailable, copying after '
          'checkpoint: $vacuumError\n$vacuumStack',
        );
        if (await dest.exists()) {
          await dest.delete();
        }
        final File source = File(await databasePath);
        await source.copy(destPath);
        return dest;
      }
    } catch (error, stack) {
      debugPrint(
        'DatabaseHelper.createConsistentDatabaseCopy failed: $error\n$stack',
      );
      rethrow;
    }
  }

  /// Merges the WAL into the main file and truncates `-wal`.
  Future<bool> walCheckpointTruncate() async {
    try {
      final Database db = await database;
      final List<Map<String, Object?>> rows = await db.rawQuery(
        'PRAGMA wal_checkpoint(TRUNCATE);',
      );
      debugPrint('DatabaseHelper: wal_checkpoint(TRUNCATE) => $rows');
      if (rows.isEmpty) {
        return true;
      }
      final Object? busy = rows.first['busy'];
      if (busy is int) {
        return busy == 0;
      }
      if (busy is num) {
        return busy.toInt() == 0;
      }
      return true;
    } catch (error, stack) {
      debugPrint('DatabaseHelper.walCheckpointTruncate failed: $error\n$stack');
      return false;
    }
  }

  /// User tables only (excludes `sqlite_*` internals).
  Future<List<({String name, int rowCount})>> listUserTables() async {
    try {
      final Database db = await database;
      final List<Map<String, Object?>> rows = await db.rawQuery(
        "SELECT name FROM sqlite_master "
        "WHERE type = 'table' AND name NOT LIKE 'sqlite_%' "
        'ORDER BY name COLLATE NOCASE ASC',
      );
      final List<({String name, int rowCount})> tables =
          <({String name, int rowCount})>[];
      for (final Map<String, Object?> row in rows) {
        final String name = '${row['name'] ?? ''}'.trim();
        if (name.isEmpty || !_isSafeSqliteIdent(name)) {
          continue;
        }
        final List<Map<String, Object?>> counted = await db.rawQuery(
          'SELECT COUNT(*) AS n FROM $name',
        );
        tables.add((name: name, rowCount: _countOf(counted)));
      }
      return tables;
    } catch (error, stack) {
      debugPrint('DatabaseHelper.listUserTables failed: $error\n$stack');
      rethrow;
    }
  }

  /// Deletes every row in [tableNames]. SQLite has no TRUNCATE; this is the
  /// equivalent (`DELETE FROM` + `sqlite_sequence` reset). Foreign keys are
  /// lifted for the wipe so selected tables can be cleared independently.
  Future<List<String>> truncateTables(Iterable<String> tableNames) async {
    try {
      final List<({String name, int rowCount})> known = await listUserTables();
      final Set<String> allowed = <String>{
        for (final ({String name, int rowCount}) table in known) table.name,
      };
      final Set<String> requested = <String>{};
      for (final String raw in tableNames) {
        final String name = raw.trim();
        if (name.isNotEmpty && allowed.contains(name)) {
          requested.add(name);
        }
      }
      if (requested.isEmpty) {
        debugPrint(
          'DatabaseHelper.truncateTables: nothing matched. '
          'requested=$tableNames allowed=$allowed',
        );
        throw ArgumentError('No valid tables were selected to erase.');
      }

      final List<String> selected = _orderedTruncateTargets(requested);
      final Database db = await database;
      await _setForeignKeys(db, enabled: false);
      try {
        await db.transaction((Transaction txn) async {
          Map<String, String> preservedGoogle = const <String, String>{};
          if (selected.contains(tableStationSettings)) {
            preservedGoogle = await _readGoogleIdentitySettingsOn(txn);
          }
          for (final String table in selected) {
            final int deleted = await txn.delete(table, where: '1');
            debugPrint('DatabaseHelper: DELETE FROM $table WHERE 1 → $deleted');
          }
          final List<Map<String, Object?>> seq = await txn.rawQuery(
            "SELECT 1 AS n FROM sqlite_master "
            "WHERE type = 'table' AND name = 'sqlite_sequence' LIMIT 1",
          );
          if (seq.isNotEmpty) {
            for (final String table in selected) {
              await txn.delete(
                'sqlite_sequence',
                where: 'name = ?',
                whereArgs: <Object>[table],
              );
            }
          }
          if (selected.contains(tableDieselStock)) {
            await txn.insert(tableDieselStock, <String, Object?>{
              'id': 1,
              'stock_quantity': zeroFuelText,
              'Average_rate': zeroFuelText,
              'Stock_amount': 0,
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
          if (selected.contains(tableAppSettings)) {
            await txn.insert(tableAppSettings, <String, Object?>{
              'key': settingOwnerMasterPinHash,
              'value': PinHasher.hash(defaultOwnerMasterPin),
            }, conflictAlgorithm: ConflictAlgorithm.replace);
            await txn.insert(tableAppSettings, <String, Object?>{
              'key': settingOwnerAutoLockMinutes,
              'value': '$defaultOwnerAutoLockMinutes',
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
          if (preservedGoogle.isNotEmpty) {
            await _writeGoogleIdentitySettingsOn(txn, preservedGoogle);
          }
        });
      } finally {
        await _setForeignKeys(db, enabled: true);
      }
      await walCheckpointTruncate();
      debugPrint('DatabaseHelper: truncated ${selected.join(', ')}');
      return selected;
    } catch (error, stack) {
      debugPrint('DatabaseHelper.truncateTables failed: $error\n$stack');
      rethrow;
    }
  }

  Future<void> _setForeignKeys(Database db, {required bool enabled}) async {
    await db.rawQuery('PRAGMA foreign_keys = ${enabled ? 'ON' : 'OFF'}');
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'PRAGMA foreign_keys',
    );
    debugPrint(
      'DatabaseHelper: PRAGMA foreign_keys => $rows (wanted ${enabled ? 1 : 0})',
    );
  }

  List<String> _orderedTruncateTargets(Set<String> requested) {
    const List<String> childFirst = <String>[
      tableUnifiedUdhaarLedger,
      tableSalesTransactions,
      tablePurchases,
      tableShifts,
      tableHelpers,
      tableCustomers,
      tableManagers,
      tableDieselStock,
      tableStationSettings,
      tableAppSettings,
      tableAppSessionState,
      tableAuditLogs,
      tableCloudBackupLogs,
    ];
    final List<String> ordered = <String>[];
    for (final String table in childFirst) {
      if (requested.contains(table)) {
        ordered.add(table);
      }
    }
    for (final String table in requested) {
      if (!ordered.contains(table)) {
        ordered.add(table);
      }
    }
    return ordered;
  }

  static final RegExp _sqliteIdent = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  static bool _isSafeSqliteIdent(String name) => _sqliteIdent.hasMatch(name);

  Future<bool> optimizeAndVacuum() async {
    try {
      final Database db = await database;
      await db.execute('PRAGMA optimize;');
      await db.execute('VACUUM;');
      debugPrint('DatabaseHelper: PRAGMA optimize + VACUUM completed');
      return true;
    } catch (error, stack) {
      debugPrint('DatabaseHelper.optimizeAndVacuum failed: $error\n$stack');
      return false;
    }
  }

  Future<int> countOpenShifts() async {
    try {
      final Database db = await database;
      final List<Map<String, Object?>> rows = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM $tableShifts '
        'WHERE ${ShiftStatusStorage.blockingSql}',
      );
      if (rows.isEmpty) {
        return 0;
      }
      final Object? value = rows.first['n'];
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      return int.tryParse('$value') ?? 0;
    } catch (error, stack) {
      debugPrint('DatabaseHelper.countOpenShifts failed: $error\n$stack');
      rethrow;
    }
  }

  Future<List<Map<String, Object?>>> queryOpenShifts() async {
    try {
      final Database db = await database;
      return db.rawQuery(
        '$_shiftsSelectSql WHERE ${ShiftStatusStorage.liveAliasSql} '
        'ORDER BY s.SHIFT_ID DESC',
      );
    } catch (error, stack) {
      debugPrint('DatabaseHelper.queryOpenShifts failed: $error\n$stack');
      rethrow;
    }
  }

  Future<AppSessionSnapshot> readAppSessionState() async {
    try {
      final Database db = await database;
      final List<Map<String, Object?>> rows = await db.query(
        tableAppSessionState,
        where: 'id = 1',
        limit: 1,
      );
      if (rows.isEmpty) {
        return AppSessionSnapshot.clean;
      }
      final Map<String, Object?> row = rows.first;
      return AppSessionSnapshot(
        isCleanShutdown: _asInt(row['is_clean_shutdown']) != 0,
        lastHeartbeatAt: DateTime.tryParse('${row['last_heartbeat_at'] ?? ''}'),
        uncleanExitAt: DateTime.tryParse('${row['unclean_exit_at'] ?? ''}'),
      );
    } catch (error, stack) {
      debugPrint('DatabaseHelper.readAppSessionState failed: $error\n$stack');
      return AppSessionSnapshot.clean;
    }
  }

  Future<void> markRuntimeUnclean() async {
    try {
      final Database db = await database;
      await db.update(tableAppSessionState, <String, Object?>{
        'is_clean_shutdown': 0,
        'last_heartbeat_at': DateTime.now().toIso8601String(),
      }, where: 'id = 1');
    } catch (error, stack) {
      debugPrint('DatabaseHelper.markRuntimeUnclean failed: $error\n$stack');
    }
  }

  Future<void> markCleanShutdown() async {
    try {
      final Database db = await database;
      await db.update(tableAppSessionState, <String, Object?>{
        'is_clean_shutdown': 1,
        'last_heartbeat_at': DateTime.now().toIso8601String(),
      }, where: 'id = 1');
    } catch (error, stack) {
      debugPrint('DatabaseHelper.markCleanShutdown failed: $error\n$stack');
    }
  }

  Future<void> touchSessionHeartbeat() async {
    try {
      final Database db = await database;
      await db.update(tableAppSessionState, <String, Object?>{
        'last_heartbeat_at': DateTime.now().toIso8601String(),
      }, where: 'id = 1');
    } catch (error, stack) {
      debugPrint('DatabaseHelper.touchSessionHeartbeat failed: $error\n$stack');
    }
  }

  /// On crash boot, stamp [unclean_exit_at] from the last heartbeat if empty.
  Future<AppSessionSnapshot> captureUncleanExitIfNeeded() async {
    try {
      final AppSessionSnapshot current = await readAppSessionState();
      if (current.isCleanShutdown) {
        return current;
      }
      if (current.uncleanExitAt != null) {
        return current;
      }
      final DateTime stamp = current.lastHeartbeatAt ?? DateTime.now();
      final Database db = await database;
      await db.update(tableAppSessionState, <String, Object?>{
        'unclean_exit_at': stamp.toIso8601String(),
      }, where: 'id = 1');
      return AppSessionSnapshot(
        isCleanShutdown: false,
        lastHeartbeatAt: current.lastHeartbeatAt,
        uncleanExitAt: stamp,
      );
    } catch (error, stack) {
      debugPrint(
        'DatabaseHelper.captureUncleanExitIfNeeded failed: $error\n$stack',
      );
      return readAppSessionState();
    }
  }

  Future<void> clearUncleanExitStamp() async {
    try {
      final Database db = await database;
      await db.update(tableAppSessionState, <String, Object?>{
        'unclean_exit_at': null,
      }, where: 'id = 1');
    } catch (error, stack) {
      debugPrint('DatabaseHelper.clearUncleanExitStamp failed: $error\n$stack');
    }
  }

  /// Manager on the live OPEN shift, or `SYSTEM` when the station is idle.
  Future<String> auditOperatorId() async {
    try {
      final List<Map<String, Object?>> open = await queryOpenShifts();
      if (open.isEmpty) {
        return 'SYSTEM';
      }
      final String id = '${open.first['MANAGER'] ?? ''}'.trim();
      return id.isEmpty ? 'SYSTEM' : id;
    } catch (error, stack) {
      debugPrint('DatabaseHelper.auditOperatorId failed: $error\n$stack');
      return 'SYSTEM';
    }
  }

  Future<int> insertCloudBackupLog({
    required String fileName,
    required String status,
    String? driveFileId,
    String triggerSource = 'MANUAL',
    String details = '',
    String? managerId,
    DateTime? at,
  }) async {
    try {
      final Database db = await database;
      final String operator = (managerId ?? await auditOperatorId()).trim();
      return db.insert(tableCloudBackupLogs, <String, Object?>{
        'timestamp': (at ?? DateTime.now()).toIso8601String(),
        'file_name': fileName.trim(),
        'drive_file_id': driveFileId?.trim(),
        'status': status.trim().toUpperCase(),
        'trigger_source': triggerSource.trim(),
        'details': details,
        'manager_ID': operator.isEmpty ? 'SYSTEM' : operator,
      });
    } catch (error, stack) {
      debugPrint('DatabaseHelper.insertCloudBackupLog failed: $error\n$stack');
      rethrow;
    }
  }

  Future<int> insertAuditLog({
    required String actionType,
    required String details,
    String? managerId,
    DateTime? at,
    bool elevatedByOwner = false,
  }) async {
    try {
      final Database db = await database;
      final String operator = (managerId ?? await auditOperatorId()).trim();
      return db.insert(tableAuditLogs, <String, Object?>{
        'timestamp': (at ?? DateTime.now()).toIso8601String(),
        'manager_ID': operator.isEmpty ? 'SYSTEM' : operator,
        'action_type': actionType.trim(),
        'details': details,
        'elevated_by_owner': elevatedByOwnerFlag(elevatedByOwner),
      });
    } catch (error, stack) {
      debugPrint('DatabaseHelper.insertAuditLog failed: $error\n$stack');
      rethrow;
    }
  }

  Future<int> countAuditLogs({String? actionFilter}) async {
    try {
      final Database db = await database;
      final String? filter = actionFilter?.trim();
      if (filter == null || filter.isEmpty) {
        final List<Map<String, Object?>> rows = await db.rawQuery(
          'SELECT COUNT(*) AS n FROM $tableAuditLogs',
        );
        return _countOf(rows);
      }
      final List<Map<String, Object?>> rows = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM $tableAuditLogs WHERE action_type = ?',
        <Object>[filter],
      );
      return _countOf(rows);
    } catch (error, stack) {
      debugPrint('DatabaseHelper.countAuditLogs failed: $error\n$stack');
      rethrow;
    }
  }

  Future<List<Map<String, Object?>>> queryAuditLogs({
    String? actionFilter,
    int limit = 25,
    int offset = 0,
  }) async {
    try {
      final Database db = await database;
      final String? filter = actionFilter?.trim();
      final int safeLimit = limit < 1 ? 25 : limit;
      final int safeOffset = offset < 0 ? 0 : offset;
      if (filter == null || filter.isEmpty) {
        return db.query(
          tableAuditLogs,
          orderBy: 'datetime(timestamp) DESC, id DESC',
          limit: safeLimit,
          offset: safeOffset,
        );
      }
      return db.query(
        tableAuditLogs,
        where: 'action_type = ?',
        whereArgs: <Object>[filter],
        orderBy: 'datetime(timestamp) DESC, id DESC',
        limit: safeLimit,
        offset: safeOffset,
      );
    } catch (error, stack) {
      debugPrint('DatabaseHelper.queryAuditLogs failed: $error\n$stack');
      rethrow;
    }
  }

  Future<String?> readAppSetting(String key) async {
    try {
      final Database db = await database;
      final List<Map<String, Object?>> rows = await db.query(
        tableAppSettings,
        columns: const <String>['value'],
        where: 'key = ?',
        whereArgs: <Object>[key],
        limit: 1,
      );
      if (rows.isEmpty) {
        return null;
      }
      return '${rows.first['value'] ?? ''}';
    } catch (error, stack) {
      debugPrint('DatabaseHelper.readAppSetting failed: $error\n$stack');
      rethrow;
    }
  }

  Future<void> writeAppSetting(String key, String value) async {
    try {
      final Database db = await database;
      await db.insert(tableAppSettings, <String, Object?>{
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (error, stack) {
      debugPrint('DatabaseHelper.writeAppSetting failed: $error\n$stack');
      rethrow;
    }
  }

  Future<String> readOwnerMasterPinHash() async {
    final Database db = await database;
    await _seedOwnerMasterPin(db);
    final String? stored = await readAppSetting(settingOwnerMasterPinHash);
    final String trimmed = stored?.trim() ?? '';
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
    final String fallback = PinHasher.hash(defaultOwnerMasterPin);
    await writeAppSetting(settingOwnerMasterPinHash, fallback);
    return fallback;
  }

  Future<void> writeOwnerMasterPinHash(String hash) async {
    await writeAppSetting(settingOwnerMasterPinHash, hash.trim());
  }

  Future<int> readOwnerAutoLockMinutes() async {
    final Database db = await database;
    await _seedOwnerAutoLockMinutes(db);
    final String? stored = await readAppSetting(settingOwnerAutoLockMinutes);
    final int? parsed = int.tryParse(stored?.trim() ?? '');
    if (parsed != null && parsed >= 0) {
      return parsed;
    }
    await writeAppSetting(
      settingOwnerAutoLockMinutes,
      '$defaultOwnerAutoLockMinutes',
    );
    return defaultOwnerAutoLockMinutes;
  }

  Future<void> writeOwnerAutoLockMinutes(int minutes) async {
    final int safe = minutes < 0 ? defaultOwnerAutoLockMinutes : minutes;
    await writeAppSetting(settingOwnerAutoLockMinutes, '$safe');
  }

  Future<String?> readSetting(String key) async {
    try {
      final Database db = await database;
      final List<Map<String, Object?>> rows = await db.query(
        tableStationSettings,
        columns: const <String>['value'],
        where: 'key = ?',
        whereArgs: <Object>[key],
        limit: 1,
      );
      if (rows.isEmpty) {
        return null;
      }
      return '${rows.first['value'] ?? ''}';
    } catch (error, stack) {
      debugPrint('DatabaseHelper.readSetting failed: $error\n$stack');
      rethrow;
    }
  }

  Future<void> writeSetting(String key, String value) async {
    try {
      final Database db = await database;
      await db.insert(tableStationSettings, <String, Object?>{
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (error, stack) {
      debugPrint('DatabaseHelper.writeSetting failed: $error\n$stack');
      rethrow;
    }
  }

  Future<void> deleteSetting(String key) async {
    try {
      final Database db = await database;
      await db.delete(
        tableStationSettings,
        where: 'key = ?',
        whereArgs: <Object>[key],
      );
    } catch (error, stack) {
      debugPrint('DatabaseHelper.deleteSetting failed: $error\n$stack');
      rethrow;
    }
  }

  Future<Map<String, String>> snapshotGoogleIdentitySettings() async {
    try {
      final Database db = await database;
      return _readGoogleIdentitySettingsOn(db);
    } catch (error, stack) {
      debugPrint(
        'DatabaseHelper.snapshotGoogleIdentitySettings failed: $error\n$stack',
      );
      rethrow;
    }
  }

  Future<void> restoreGoogleIdentitySettings(Map<String, String> values) async {
    try {
      if (values.isEmpty) {
        return;
      }
      final Database db = await database;
      await _writeGoogleIdentitySettingsOn(db, values);
    } catch (error, stack) {
      debugPrint(
        'DatabaseHelper.restoreGoogleIdentitySettings failed: $error\n$stack',
      );
      rethrow;
    }
  }

  Future<Map<String, String>> _readGoogleIdentitySettingsOn(
    DatabaseExecutor executor,
  ) async {
    final List<String> keys = googleIdentitySettingKeys;
    if (keys.isEmpty) {
      return const <String, String>{};
    }
    final String placeholders = List<String>.filled(keys.length, '?').join(',');
    final List<Map<String, Object?>> rows = await executor.query(
      tableStationSettings,
      columns: const <String>['key', 'value'],
      where: 'key IN ($placeholders)',
      whereArgs: keys,
    );
    final Map<String, String> out = <String, String>{};
    for (final Map<String, Object?> row in rows) {
      final String key = '${row['key'] ?? ''}'.trim();
      final String value = '${row['value'] ?? ''}';
      if (key.isNotEmpty && value.trim().isNotEmpty) {
        out[key] = value;
      }
    }
    return out;
  }

  Future<void> _writeGoogleIdentitySettingsOn(
    DatabaseExecutor executor,
    Map<String, String> values,
  ) async {
    for (final MapEntry<String, String> entry in values.entries) {
      final String key = entry.key.trim();
      if (key.isEmpty) {
        continue;
      }
      await executor.insert(tableStationSettings, <String, Object?>{
        'key': key,
        'value': entry.value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<bool> isSqliteDatabaseFile(String path) async {
    try {
      final File file = File(path);
      if (!await file.exists()) {
        return false;
      }
      final RandomAccessFile raf = await file.open();
      try {
        final List<int> header = await raf.read(16);
        if (header.length < 16) {
          return false;
        }
        return String.fromCharCodes(header.sublist(0, 15)) == 'SQLite format 3';
      } finally {
        await raf.close();
      }
    } catch (error, stack) {
      debugPrint('DatabaseHelper.isSqliteDatabaseFile failed: $error\n$stack');
      return false;
    }
  }

  /// Closes SQLite, swaps in [backupFilePath], and reopens. Refuses when any
  /// shift is still `OPEN`.
  Future<void> restoreFromBackupFile(String backupFilePath) async {
    try {
      final bool valid = await isSqliteDatabaseFile(backupFilePath);
      if (!valid) {
        throw const FormatException(
          'Selected file is not a valid SQLite database.',
        );
      }
      final int openCount = await countOpenShifts();
      if (openCount > 0) {
        throw StateError(
          'Cannot restore while $openCount OPEN shift(s) exist. '
          'Close every live shift first.',
        );
      }
      final String dest = await databasePath;
      await close();
      await File(backupFilePath).copy(dest);
      await _deleteSidecars(dest);
      await database;
      debugPrint('DatabaseHelper: restored database from $backupFilePath');
    } catch (error, stack) {
      debugPrint('DatabaseHelper.restoreFromBackupFile failed: $error\n$stack');
      try {
        await database;
      } catch (reopenError, reopenStack) {
        debugPrint(
          'DatabaseHelper: reopen after failed restore: '
          '$reopenError\n$reopenStack',
        );
      }
      rethrow;
    }
  }

  Future<void> _deleteSidecars(String dbPath) async {
    for (final String suffix in const <String>['-wal', '-shm']) {
      final File side = File('$dbPath$suffix');
      if (await side.exists()) {
        await side.delete();
      }
    }
  }

  static Future<int> _fileByteLength(String path) async {
    final File file = File(path);
    if (!await file.exists()) {
      return 0;
    }
    return file.length();
  }

  static int _countOf(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) {
      return 0;
    }
    final Object? value = rows.first['n'];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('$value') ?? 0;
  }

  Future<void> _upsertCustomerTxn(
    Transaction txn, {
    required String id,
    required String name,
  }) async {
    final String resolvedId = id.trim();
    final String resolvedName = name.trim();
    if (resolvedId.isEmpty || resolvedName.isEmpty) {
      throw ArgumentError('Customer id and name are required');
    }
    await txn.insert(tableCustomers, <String, Object?>{
      'customer_ID': resolvedId,
      'Customer_Name': resolvedName,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await txn.update(
      tableCustomers,
      <String, Object?>{'Customer_Name': resolvedName},
      where: 'customer_ID = ?',
      whereArgs: <Object>[resolvedId],
    );
  }

  Future<Map<String, Object?>> _insertUnifiedUdhaarTxn(
    Transaction txn, {
    required String type,
    required String shiftId,
    required String customerId,
    required String customerName,
    required DateTime at,
    required double amount,
    String? token,
    double liters = 0,
    double rate = 0,
    String description = '',
    String? vehicle,
  }) async {
    final String resolvedType = type.trim().toUpperCase();
    final bool isSale = resolvedType == 'SALE';
    final String resolvedCustomerId = customerId.trim().padLeft(2, '0');
    final int rupees = roundRupees(amount);
    final int previous = roundRupees(
      await _latestRemainingOn(txn, resolvedCustomerId),
    );
    final int remaining = isSale ? previous + rupees : previous - rupees;
    final List<Map<String, Object?>> paidRows = await txn.rawQuery(
      'SELECT COALESCE(SUM(PAID), 0) AS paid FROM $tableUnifiedUdhaarLedger WHERE Customer_ID = ?',
      <Object>[resolvedCustomerId],
    );
    final int priorPaid = roundRupees(
      paidRows.isEmpty ? 0 : paidRows.first['paid'],
    );
    final int thisPaid = isSale ? 0 : rupees;
    final String status = remaining <= 0
        ? 'Paid'
        : (priorPaid + thisPaid > 0 ? 'Partially Paid' : 'Unpaid');
    final int serial = await _nextLedgerSerial(
      txn,
      shiftId: shiftId,
      customerId: resolvedCustomerId,
    );
    final String primaryKey =
        '${_shiftToken(shiftId)}/$resolvedCustomerId-${serial.toString().padLeft(2, '0')}';
    final String? tokenValue = token?.trim();
    final String? vehicleValue = vehicle?.trim();
    final Map<String, Object?> row = <String, Object?>{
      'PRIMARY_KEY': primaryKey,
      'TYPE': isSale ? 'SALE' : 'SETTLEMENT',
      'TKN': tokenValue == null || tokenValue.isEmpty ? null : tokenValue,
      'DATE_TIME': at.toIso8601String(),
      'Customer_name': customerName.trim(),
      'Customer_ID': resolvedCustomerId,
      'LITERS': isSale ? fuelToText(liters) : zeroFuelText,
      'RATE': isSale ? fuelToText(rate) : zeroFuelText,
      'AMOUNT': rupees,
      'DESCRIPTION': description.trim(),
      'VEHICLE': vehicleValue == null || vehicleValue.isEmpty
          ? null
          : vehicleValue,
      'UDHAAR': isSale ? rupees : 0,
      'PAID': thisPaid,
      'REMAINING': remaining,
      'Status': status,
    };
    await txn.insert(tableUnifiedUdhaarLedger, row);
    return row;
  }

  Future<int> _nextLedgerSerial(
    Transaction txn, {
    required String shiftId,
    required String customerId,
  }) async {
    final String prefix = '${_shiftToken(shiftId)}/$customerId-';
    final List<Map<String, Object?>> rows = await txn.query(
      tableUnifiedUdhaarLedger,
      columns: const <String>['PRIMARY_KEY'],
      where: 'PRIMARY_KEY LIKE ?',
      whereArgs: <Object>['$prefix%'],
    );
    int max = 0;
    for (final Map<String, Object?> row in rows) {
      final String key = '${row['PRIMARY_KEY'] ?? ''}';
      if (!key.startsWith(prefix)) {
        continue;
      }
      final int? parsed = int.tryParse(key.substring(prefix.length));
      if (parsed != null && parsed > max) {
        max = parsed;
      }
    }
    return max + 1;
  }

  Future<double> _latestRemainingOn(
    DatabaseExecutor executor,
    String customerId,
  ) async {
    final List<Map<String, Object?>> rows = await executor.query(
      tableUnifiedUdhaarLedger,
      columns: const <String>['REMAINING'],
      where: 'Customer_ID = ?',
      whereArgs: <Object>[customerId],
      orderBy: 'datetime(DATE_TIME) DESC, PRIMARY_KEY DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return 0;
    }
    return _asDouble(rows.first['REMAINING']);
  }

  static String _shiftToken(String shiftId) {
    final String trimmed = shiftId.trim();
    if (trimmed.isEmpty) {
      return '0000';
    }
    return trimmed.replaceFirst(RegExp(r'^SHF-', caseSensitive: false), '');
  }

  Future<void> _applyPurchaseToStock(
    Transaction txn, {
    required Decimal purchaseLiters,
    required Decimal purchaseAmount,
  }) async {
    final ({Decimal quantity, Decimal averageRate, Decimal amount}) current =
        await _readDieselStock(txn);
    final Decimal nextQuantity = truncateFuel(
      current.quantity + purchaseLiters,
    );
    final Decimal nextRate = nextAverageRate(
      currentLiters: current.quantity,
      currentStockAmount: current.amount,
      purchaseLiters: purchaseLiters,
      purchaseAmount: purchaseAmount,
    );
    await _writeDieselStock(txn, quantity: nextQuantity, averageRate: nextRate);
  }

  Future<void> _applyStockDelta(Transaction txn, Decimal signedDelta) async {
    final ({Decimal quantity, Decimal averageRate, Decimal amount}) current =
        await _readDieselStock(txn);
    await _writeDieselStock(
      txn,
      quantity: truncateFuel(current.quantity + signedDelta),
      averageRate: current.averageRate,
    );
  }

  Future<void> _setStockAmount(Transaction txn, double volume) async {
    final ({Decimal quantity, Decimal averageRate, Decimal amount}) current =
        await _readDieselStock(txn);
    await _writeDieselStock(
      txn,
      quantity: parseFuel(volume),
      averageRate: current.averageRate,
    );
  }

  Future<({Decimal quantity, Decimal averageRate, Decimal amount})>
  _readDieselStock(Transaction txn) async {
    final List<Map<String, Object?>> rows = await txn.query(
      tableDieselStock,
      columns: const <String>['stock_quantity', 'Average_rate', 'Stock_amount'],
      where: 'id = ?',
      whereArgs: const <Object>[1],
      limit: 1,
    );
    if (rows.isEmpty) {
      return (
        quantity: Decimal.zero,
        averageRate: Decimal.zero,
        amount: Decimal.zero,
      );
    }
    return (
      quantity: parseFuel(rows.first['stock_quantity']),
      averageRate: parseFuel(rows.first['Average_rate']),
      amount: rupeesDecimal(rows.first['Stock_amount']),
    );
  }

  /// Writes the singleton row. `Stock_amount` is round(quantity × rate).
  Future<void> _writeDieselStock(
    Transaction txn, {
    required Decimal quantity,
    required Decimal averageRate,
  }) async {
    final Decimal qty = truncateFuel(quantity);
    final Decimal rate = truncateFuel(averageRate);
    final Map<String, Object?> values = <String, Object?>{
      'stock_quantity': fuelToText(qty),
      'Average_rate': fuelToText(rate),
      'Stock_amount': roundRupees(qty * rate),
    };
    final int changed = await txn.update(
      tableDieselStock,
      values,
      where: 'id = ?',
      whereArgs: const <Object>[1],
    );
    if (changed == 0) {
      await txn.insert(tableDieselStock, <String, Object?>{
        'id': 1,
        ...values,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  static int _invoiceNumberOf(String invNo) {
    final Match? match = RegExp(r'(\d+)$').firstMatch(invNo.trim());
    if (match == null) {
      return 0;
    }
    return int.tryParse(match.group(1) ?? '') ?? 0;
  }

  static double _asDouble(Object? value) {
    return storedNumberToDouble(value);
  }
}

/// Thrown when a purchase edit would push `diesel_stock` below zero.
class PurchaseStockOverdrawException implements Exception {
  const PurchaseStockOverdrawException();

  @override
  String toString() {
    return 'PurchaseStockOverdrawException';
  }
}

/// Thrown when a manager still holds an `OPEN` row in `shifts`.
class ManagerHasOpenShiftException implements Exception {
  const ManagerHasOpenShiftException({
    required this.managerId,
    required this.managerName,
    required this.shiftId,
  });

  final String managerId;
  final String managerName;
  final int shiftId;

  @override
  String toString() {
    return '$managerName currently holds Shift #$shiftId. '
        'Close that shift before removing or inactivating this manager.';
  }
}

/// Thrown when SQLite FK rows (sales, purchases, closed shifts) still reference
/// the manager.
class ManagerInUseException implements Exception {
  const ManagerInUseException({required this.managerId});

  final String managerId;

  @override
  String toString() {
    return 'Manager $managerId is referenced by historical station records '
        'and cannot be deleted.';
  }
}
