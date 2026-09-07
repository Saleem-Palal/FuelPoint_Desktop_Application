import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/google_drive_oauth_config.dart';
import '../services/database_helper.dart';
import '../services/google_drive_backup_service.dart';

export '../services/google_drive_backup_service.dart' show GoogleDriveAccount;

/// Audit action names stored in `audit_logs.action_type`.
class AuditActionType {
  static const String rateUpdate = 'RATE_UPDATE';
  static const String keypadOverride = 'KEYPAD_OVERRIDE';
  static const String backupCreated = 'BACKUP_CREATED';
  static const String shiftForceClose = 'SHIFT_FORCE_CLOSE';
  static const String walCheckpoint = 'WAL_CHECKPOINT';
  static const String dbOptimize = 'DB_OPTIMIZE';
  static const String driveSync = 'DRIVE_SYNC';
  static const String restoreCompleted = 'RESTORE_COMPLETED';
  static const String accountConnect = 'ACCOUNT_CONNECT';
  static const String accountSwitch = 'ACCOUNT_SWITCH';
  static const String shiftClosedBackup = 'SHIFT_CLOSE_BACKUP';
  static const String tablesTruncated = 'TABLES_TRUNCATED';
  static const String oauthCredentialsSaved = 'OAUTH_CREDENTIALS_SAVED';
  static const String accountDisconnect = 'ACCOUNT_DISCONNECT';
  static const String periodicBackup = 'PERIODIC_BACKUP';

  static const List<String> filterOptions = <String>[
    rateUpdate,
    keypadOverride,
    backupCreated,
    shiftForceClose,
    walCheckpoint,
    dbOptimize,
    driveSync,
    restoreCompleted,
    accountConnect,
    accountSwitch,
    shiftClosedBackup,
    tablesTruncated,
    oauthCredentialsSaved,
    accountDisconnect,
    periodicBackup,
  ];
}

/// Periodic Drive backup cadence shown in Settings.
class BackupIntervalHours {
  static const int off = 0;
  static const List<int> choices = <int>[off, 6, 12, 24];

  static String label(int hours) {
    if (hours <= 0) {
      return 'Off';
    }
    return 'Every $hours Hours';
  }
}

class CloudBackupTrigger {
  static const String manual = 'MANUAL';
  static const String shiftClose = 'SHIFT_CLOSE';
  static const String periodic = 'PERIODIC';
}

@immutable
class DatabaseMetrics {
  const DatabaseMetrics({
    required this.dbPath,
    required this.dbBytes,
    required this.walBytes,
  });

  final String dbPath;
  final int dbBytes;
  final int walBytes;

  /// Display-layer MB labels (2 decimal places). Storage stays in bytes.
  String get dbSizeMbLabel => formatBytesAsMb(dbBytes);

  String get walSizeMbLabel => formatBytesAsMb(walBytes);

  static String formatBytesAsMb(int bytes) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

@immutable
class StationTableInfo {
  const StationTableInfo({required this.name, required this.rowCount});

  final String name;
  final int rowCount;

  String get label {
    switch (name) {
      case DatabaseHelper.tableManagers:
        return 'Managers';
      case DatabaseHelper.tableHelpers:
        return 'Helpers';
      case DatabaseHelper.tableCustomers:
        return 'Customers';
      case DatabaseHelper.tableDieselStock:
        return 'Diesel stock';
      case DatabaseHelper.tableShifts:
        return 'Shifts';
      case DatabaseHelper.tableSalesTransactions:
        return 'Sales transactions';
      case DatabaseHelper.tablePurchases:
        return 'Purchases';
      case DatabaseHelper.tableUnifiedUdhaarLedger:
        return 'Udhaar ledger';
      case DatabaseHelper.tableAuditLogs:
        return 'Audit logs';
      case DatabaseHelper.tableCloudBackupLogs:
        return 'Cloud backup logs';
      case DatabaseHelper.tableStationSettings:
        return 'Station settings';
      default:
        return name;
    }
  }
}

@immutable
class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    required this.timestamp,
    required this.managerId,
    required this.actionType,
    required this.details,
  });

  final int id;
  final DateTime timestamp;
  final String managerId;
  final String actionType;
  final String details;

  static AuditLogEntry fromRow(Map<String, Object?> row) {
    final Object? idRaw = row['id'];
    int id = 0;
    if (idRaw is int) {
      id = idRaw;
    } else if (idRaw is num) {
      id = idRaw.toInt();
    } else {
      id = int.tryParse('$idRaw') ?? 0;
    }
    final DateTime? parsed = DateTime.tryParse('${row['timestamp'] ?? ''}');
    return AuditLogEntry(
      id: id,
      timestamp: parsed ?? DateTime.fromMillisecondsSinceEpoch(0),
      managerId: '${row['manager_ID'] ?? 'SYSTEM'}'.trim(),
      actionType: '${row['action_type'] ?? ''}'.trim(),
      details: '${row['details'] ?? ''}',
    );
  }
}

@immutable
class SettingsState {
  const SettingsState({
    required this.loading,
    required this.busy,
    required this.backingUp,
    required this.autoBackupOnShiftClose,
    required this.autoBackupIntervalHours,
    required this.oauthClientId,
    required this.hasOauthSecret,
    required this.auditLogs,
    required this.auditTotal,
    required this.auditPage,
    required this.auditPageSize,
    this.metrics,
    this.account,
    this.lastBackupAt,
    this.lastBackupFileName,
    this.lastBackupDriveFileId,
    this.actionFilter,
    this.errorMessage,
    this.statusMessage,
  });

  final bool loading;
  final bool busy;
  final bool backingUp;
  final DatabaseMetrics? metrics;
  final GoogleDriveAccount? account;
  final bool autoBackupOnShiftClose;
  final int autoBackupIntervalHours;
  final String oauthClientId;
  final bool hasOauthSecret;
  final DateTime? lastBackupAt;
  final String? lastBackupFileName;
  final String? lastBackupDriveFileId;
  final List<AuditLogEntry> auditLogs;
  final int auditTotal;
  final int auditPage;
  final int auditPageSize;
  final String? actionFilter;
  final String? errorMessage;
  final String? statusMessage;

  bool get isDriveConnected => account != null;

  bool get oauthConfigured => oauthClientId.trim().isNotEmpty && hasOauthSecret;

  int get auditPageCount {
    if (auditTotal <= 0) {
      return 1;
    }
    return ((auditTotal + auditPageSize - 1) / auditPageSize).floor();
  }

  bool get canGoPrevAudit => auditPage > 0;

  bool get canGoNextAudit => auditPage + 1 < auditPageCount;

  SettingsState copyWith({
    bool? loading,
    bool? busy,
    bool? backingUp,
    DatabaseMetrics? metrics,
    GoogleDriveAccount? account,
    bool clearAccount = false,
    bool? autoBackupOnShiftClose,
    int? autoBackupIntervalHours,
    String? oauthClientId,
    bool? hasOauthSecret,
    DateTime? lastBackupAt,
    String? lastBackupFileName,
    String? lastBackupDriveFileId,
    bool clearLastBackup = false,
    List<AuditLogEntry>? auditLogs,
    int? auditTotal,
    int? auditPage,
    int? auditPageSize,
    String? actionFilter,
    bool clearActionFilter = false,
    String? errorMessage,
    bool clearError = false,
    String? statusMessage,
    bool clearStatus = false,
  }) {
    return SettingsState(
      loading: loading ?? this.loading,
      busy: busy ?? this.busy,
      backingUp: backingUp ?? this.backingUp,
      metrics: metrics ?? this.metrics,
      account: clearAccount ? null : (account ?? this.account),
      autoBackupOnShiftClose:
          autoBackupOnShiftClose ?? this.autoBackupOnShiftClose,
      autoBackupIntervalHours:
          autoBackupIntervalHours ?? this.autoBackupIntervalHours,
      oauthClientId: oauthClientId ?? this.oauthClientId,
      hasOauthSecret: hasOauthSecret ?? this.hasOauthSecret,
      lastBackupAt: clearLastBackup
          ? null
          : (lastBackupAt ?? this.lastBackupAt),
      lastBackupFileName: clearLastBackup
          ? null
          : (lastBackupFileName ?? this.lastBackupFileName),
      lastBackupDriveFileId: clearLastBackup
          ? null
          : (lastBackupDriveFileId ?? this.lastBackupDriveFileId),
      auditLogs: auditLogs ?? this.auditLogs,
      auditTotal: auditTotal ?? this.auditTotal,
      auditPage: auditPage ?? this.auditPage,
      auditPageSize: auditPageSize ?? this.auditPageSize,
      actionFilter: clearActionFilter
          ? null
          : (actionFilter ?? this.actionFilter),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      statusMessage: clearStatus ? null : (statusMessage ?? this.statusMessage),
    );
  }

  static SettingsState empty() {
    return const SettingsState(
      loading: true,
      busy: false,
      backingUp: false,
      autoBackupOnShiftClose: false,
      autoBackupIntervalHours: BackupIntervalHours.off,
      oauthClientId: '',
      hasOauthSecret: false,
      auditLogs: <AuditLogEntry>[],
      auditTotal: 0,
      auditPage: 0,
      auditPageSize: 12,
    );
  }
}

class SettingsNotifier extends Notifier<SettingsState> {
  final DatabaseHelper _db = DatabaseHelper.instance;
  late final GoogleDriveBackupService _drive;
  Timer? _periodicBackupTimer;
  bool _periodicBackupInFlight = false;

  @override
  SettingsState build() {
    _drive = GoogleDriveBackupService(_db);
    ref.onDispose(() {
      _periodicBackupTimer?.cancel();
      _periodicBackupTimer = null;
      unawaited(_drive.dispose());
    });
    Future<void>.microtask(bootstrap);
    return SettingsState.empty();
  }

  Future<void> bootstrap() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      await fetchDatabaseMetrics();
      final GoogleDriveOAuthConfig oauth =
          await GoogleDriveOAuthConfig.loadPreferringDatabase(_db);
      final String? auto = await _db.readSetting(
        DatabaseHelper.settingAutoBackupOnShiftClose,
      );
      final String? intervalRaw = await _db.readSetting(
        DatabaseHelper.settingAutoBackupIntervalHours,
      );
      final int interval =
          int.tryParse(intervalRaw ?? '') ?? BackupIntervalHours.off;
      final String? lastAtRaw = await _db.readSetting(
        DatabaseHelper.settingLastBackupAt,
      );
      final DateTime? lastAt = DateTime.tryParse(lastAtRaw ?? '');
      final String? lastFile = await _db.readSetting(
        DatabaseHelper.settingLastBackupFileName,
      );
      final String? lastId = await _db.readSetting(
        DatabaseHelper.settingLastBackupDriveFileId,
      );
      final GoogleDriveAccount? account = await _drive.restoreSession();
      state = state.copyWith(
        loading: false,
        autoBackupOnShiftClose: auto == '1',
        autoBackupIntervalHours: BackupIntervalHours.choices.contains(interval)
            ? interval
            : BackupIntervalHours.off,
        oauthClientId: oauth.clientId,
        hasOauthSecret: (oauth.clientSecret ?? '').trim().isNotEmpty,
        lastBackupAt: lastAt,
        lastBackupFileName: lastFile,
        lastBackupDriveFileId: lastId,
        clearLastBackup:
            lastAt == null && (lastFile == null || lastFile.isEmpty),
        account: account,
        clearAccount: account == null,
      );
      _restartPeriodicBackupWatch();
      await fetchAuditLogs(actionFilter: state.actionFilter);
    } catch (error, stack) {
      debugPrint('SettingsNotifier.bootstrap failed: $error\n$stack');
      state = state.copyWith(
        loading: false,
        errorMessage: 'Could not load station settings. $error',
      );
    }
  }

  Future<void> fetchDatabaseMetrics() async {
    try {
      final ({int dbBytes, int walBytes, String dbPath}) raw = await _db
          .databaseFileMetrics();
      state = state.copyWith(
        metrics: DatabaseMetrics(
          dbPath: raw.dbPath,
          dbBytes: raw.dbBytes,
          walBytes: raw.walBytes,
        ),
      );
    } catch (error, stack) {
      debugPrint(
        'SettingsNotifier.fetchDatabaseMetrics failed: $error\n$stack',
      );
      state = state.copyWith(
        errorMessage: 'Could not read database file sizes. $error',
      );
    }
  }

  Future<bool> executeWalCheckpoint() async {
    state = state.copyWith(busy: true, clearError: true, clearStatus: true);
    try {
      final bool ok = await _db.walCheckpointTruncate();
      await _db.insertAuditLog(
        actionType: AuditActionType.walCheckpoint,
        details: ok
            ? 'PRAGMA wal_checkpoint(TRUNCATE) completed.'
            : 'PRAGMA wal_checkpoint(TRUNCATE) reported a busy database.',
      );
      await fetchDatabaseMetrics();
      await fetchAuditLogs(actionFilter: state.actionFilter);
      state = state.copyWith(
        busy: false,
        statusMessage: ok
            ? 'WAL checkpoint completed. Log merged into the primary .db file.'
            : 'WAL checkpoint could not finish because SQLite was busy.',
      );
      return ok;
    } catch (error, stack) {
      debugPrint(
        'SettingsNotifier.executeWalCheckpoint failed: $error\n$stack',
      );
      state = state.copyWith(
        busy: false,
        errorMessage: 'WAL checkpoint failed. $error',
      );
      return false;
    }
  }

  Future<bool> optimizeDatabase() async {
    state = state.copyWith(busy: true, clearError: true, clearStatus: true);
    try {
      await _db.walCheckpointTruncate();
      final bool ok = await _db.optimizeAndVacuum();
      await _db.insertAuditLog(
        actionType: AuditActionType.dbOptimize,
        details: ok
            ? 'PRAGMA optimize and VACUUM completed.'
            : 'Database optimize/VACUUM did not complete.',
      );
      await fetchDatabaseMetrics();
      await fetchAuditLogs(actionFilter: state.actionFilter);
      state = state.copyWith(
        busy: false,
        statusMessage: ok
            ? 'Database optimized and vacuumed.'
            : 'Optimize/VACUUM could not complete. Try again when the station is idle.',
      );
      return ok;
    } catch (error, stack) {
      debugPrint('SettingsNotifier.optimizeDatabase failed: $error\n$stack');
      state = state.copyWith(
        busy: false,
        errorMessage: 'Database optimize failed. $error',
      );
      return false;
    }
  }

  Future<String?> createLocalBackup(String destinationPath) async {
    state = state.copyWith(busy: true, clearError: true, clearStatus: true);
    try {
      final Directory destDir = Directory(destinationPath);
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }
      final String fileName = _backupFileName(DateTime.now());
      final String destFile = p.join(destDir.path, fileName);
      await _db.createConsistentDatabaseCopy(destFile);
      await _db.insertAuditLog(
        actionType: AuditActionType.backupCreated,
        details: 'Local snapshot written to $destFile',
      );
      await fetchAuditLogs(actionFilter: state.actionFilter);
      await fetchDatabaseMetrics();
      state = state.copyWith(
        busy: false,
        statusMessage: 'Backup saved as $fileName',
      );
      debugPrint('SettingsNotifier: local backup -> $destFile');
      return destFile;
    } catch (error, stack) {
      debugPrint('SettingsNotifier.createLocalBackup failed: $error\n$stack');
      state = state.copyWith(
        busy: false,
        errorMessage: 'Could not create local backup. $error',
      );
      return null;
    }
  }

  Future<bool> restoreDatabase(String sourcePath) async {
    state = state.copyWith(busy: true, clearError: true, clearStatus: true);
    try {
      await _db.restoreFromBackupFile(sourcePath);
      await _db.insertAuditLog(
        actionType: AuditActionType.restoreCompleted,
        details: 'Database restored from $sourcePath',
      );
      await fetchDatabaseMetrics();
      await fetchAuditLogs(actionFilter: state.actionFilter);
      state = state.copyWith(
        busy: false,
        statusMessage:
            'Database restored. Restart any open workspace screens if figures look stale.',
      );
      return true;
    } catch (error, stack) {
      debugPrint('SettingsNotifier.restoreDatabase failed: $error\n$stack');
      state = state.copyWith(
        busy: false,
        errorMessage: 'Restore blocked. $error',
      );
      return false;
    }
  }

  Future<List<StationTableInfo>> listDatabaseTables() async {
    try {
      final List<({String name, int rowCount})> rows = await _db
          .listUserTables();
      return rows
          .map(
            (row) => StationTableInfo(name: row.name, rowCount: row.rowCount),
          )
          .toList();
    } catch (error, stack) {
      debugPrint('SettingsNotifier.listDatabaseTables failed: $error\n$stack');
      state = state.copyWith(
        errorMessage: 'Could not list database tables. $error',
      );
      return const <StationTableInfo>[];
    }
  }

  Future<bool> truncateSelectedTables(Set<String> tableNames) async {
    state = state.copyWith(busy: true, clearError: true, clearStatus: true);
    try {
      final List<String> erased = await _db.truncateTables(tableNames);
      await _db.insertAuditLog(
        actionType: AuditActionType.tablesTruncated,
        details: 'Erased tables: ${erased.join(', ')}',
      );
      await fetchDatabaseMetrics();
      await fetchAuditLogs(actionFilter: state.actionFilter);
      final bool clearedSettings = erased.contains(
        DatabaseHelper.tableStationSettings,
      );
      if (clearedSettings) {
        try {
          await _drive.signOut();
        } catch (error, stack) {
          debugPrint(
            'SettingsNotifier: sign-out after settings erase: $error\n$stack',
          );
        }
        _periodicBackupTimer?.cancel();
        _periodicBackupTimer = null;
      }
      state = state.copyWith(
        busy: false,
        autoBackupOnShiftClose: clearedSettings
            ? false
            : state.autoBackupOnShiftClose,
        autoBackupIntervalHours: clearedSettings
            ? BackupIntervalHours.off
            : state.autoBackupIntervalHours,
        oauthClientId: clearedSettings ? '' : state.oauthClientId,
        hasOauthSecret: clearedSettings ? false : state.hasOauthSecret,
        clearAccount: clearedSettings,
        clearLastBackup: clearedSettings,
        statusMessage:
            'Erased ${erased.length} table${erased.length == 1 ? '' : 's'}: '
            '${erased.join(', ')}',
      );
      return true;
    } catch (error, stack) {
      debugPrint(
        'SettingsNotifier.truncateSelectedTables failed: $error\n$stack',
      );
      state = state.copyWith(
        busy: false,
        errorMessage: 'Could not erase the selected tables. $error',
      );
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> fetchAuditLogs({
    String? actionFilter,
  }) async {
    try {
      final String? filter = actionFilter?.trim();
      final String? resolved = (filter == null || filter.isEmpty)
          ? null
          : filter;
      final int page = resolved == state.actionFilter ? state.auditPage : 0;
      final int total = await _db.countAuditLogs(actionFilter: resolved);
      final int pageSize = state.auditPageSize;
      final int maxPage = total <= 0
          ? 0
          : ((total + pageSize - 1) / pageSize).floor() - 1;
      final int safePage = page > maxPage ? maxPage : page;
      final List<Map<String, Object?>> rows = await _db.queryAuditLogs(
        actionFilter: resolved,
        limit: pageSize,
        offset: safePage * pageSize,
      );
      final List<AuditLogEntry> entries = rows
          .map(AuditLogEntry.fromRow)
          .toList();
      state = state.copyWith(
        auditLogs: entries,
        auditTotal: total,
        auditPage: safePage < 0 ? 0 : safePage,
        actionFilter: resolved,
        clearActionFilter: resolved == null,
      );
      return rows
          .map((Map<String, Object?> row) => Map<String, dynamic>.from(row))
          .toList();
    } catch (error, stack) {
      debugPrint('SettingsNotifier.fetchAuditLogs failed: $error\n$stack');
      state = state.copyWith(errorMessage: 'Could not load audit logs. $error');
      return const <Map<String, dynamic>>[];
    }
  }

  Future<void> setAuditFilter(String? actionFilter) async {
    state = state.copyWith(
      auditPage: 0,
      actionFilter: actionFilter,
      clearActionFilter: actionFilter == null || actionFilter.trim().isEmpty,
    );
    await fetchAuditLogs(actionFilter: actionFilter);
  }

  Future<void> goToAuditPage(int page) async {
    if (page < 0 || page >= state.auditPageCount) {
      return;
    }
    state = state.copyWith(auditPage: page);
    await fetchAuditLogs(actionFilter: state.actionFilter);
  }

  Future<void> saveOauthCredentials({
    required String clientId,
    required String clientSecret,
  }) async {
    state = state.copyWith(busy: true, clearError: true, clearStatus: true);
    try {
      final String id = clientId.trim();
      final String secret = clientSecret.trim();
      if (id.isEmpty) {
        throw StateError('Client ID is required.');
      }
      final String resolvedSecret = secret.isEmpty
          ? ((await _db.readSetting(
                  DatabaseHelper.settingGoogleOauthClientSecret,
                )) ??
                '')
          : secret;
      if (resolvedSecret.trim().isEmpty) {
        throw StateError('Client Secret is required.');
      }
      if (state.account != null) {
        await _drive.signOut();
        await _db.deleteSetting(DatabaseHelper.settingDriveBackupFolderId);
      }
      await GoogleDriveOAuthConfig.persistToDatabase(
        _db,
        GoogleDriveOAuthConfig(clientId: id, clientSecret: resolvedSecret),
      );
      await _db.insertAuditLog(
        actionType: AuditActionType.oauthCredentialsSaved,
        details: 'Google OAuth Desktop client credentials saved locally.',
      );
      await fetchAuditLogs(actionFilter: state.actionFilter);
      state = state.copyWith(
        busy: false,
        oauthClientId: id,
        hasOauthSecret: true,
        clearAccount: true,
        statusMessage:
            'OAuth credentials saved on this station. You can sign in now.',
      );
    } catch (error, stack) {
      debugPrint(
        'SettingsNotifier.saveOauthCredentials failed: $error\n$stack',
      );
      state = state.copyWith(
        busy: false,
        errorMessage: 'Could not save OAuth credentials. $error',
      );
    }
  }

  Future<void> authenticateGoogleDrive() async {
    state = state.copyWith(busy: true, clearError: true, clearStatus: true);
    try {
      if (!await _drive.hasConfiguredCredentials()) {
        throw StateError(
          'Save a Desktop Client ID and Client Secret before signing in.',
        );
      }
      final GoogleDriveAccount account = await _drive.authenticate();
      await _db.insertAuditLog(
        actionType: AuditActionType.accountConnect,
        details: 'Google Drive connected as ${account.email}',
      );
      await fetchAuditLogs(actionFilter: state.actionFilter);
      state = state.copyWith(
        busy: false,
        account: account,
        statusMessage: 'Connected as ${account.email}',
      );
    } catch (error, stack) {
      debugPrint(
        'SettingsNotifier.authenticateGoogleDrive failed: $error\n$stack',
      );
      state = state.copyWith(
        busy: false,
        errorMessage: 'Google sign-in failed. $error',
      );
    }
  }

  Future<void> signOutGoogleDrive() async {
    state = state.copyWith(busy: true, clearError: true, clearStatus: true);
    try {
      await _drive.signOut();
      await _db.deleteSetting(DatabaseHelper.settingDriveBackupFolderId);
      await _db.insertAuditLog(
        actionType: AuditActionType.accountDisconnect,
        details: 'Google Drive account disconnected.',
      );
      await fetchAuditLogs(actionFilter: state.actionFilter);
      state = state.copyWith(
        busy: false,
        clearAccount: true,
        statusMessage: 'Google Drive disconnected.',
      );
    } catch (error, stack) {
      debugPrint('SettingsNotifier.signOutGoogleDrive failed: $error\n$stack');
      state = state.copyWith(
        busy: false,
        clearAccount: _drive.account == null,
        account: _drive.account,
        errorMessage: 'Could not disconnect Google Drive. $error',
      );
    }
  }

  Future<void> switchGoogleAccount() async {
    state = state.copyWith(busy: true, clearError: true, clearStatus: true);
    try {
      await _drive.signOut();
      await _db.deleteSetting(DatabaseHelper.settingDriveBackupFolderId);
      final GoogleDriveAccount account = await _drive.authenticate();
      await _db.insertAuditLog(
        actionType: AuditActionType.accountSwitch,
        details: 'Google Drive account switched to ${account.email}',
      );
      await fetchAuditLogs(actionFilter: state.actionFilter);
      state = state.copyWith(
        busy: false,
        account: account,
        statusMessage: 'Switched Google account to ${account.email}',
      );
    } catch (error, stack) {
      debugPrint('SettingsNotifier.switchGoogleAccount failed: $error\n$stack');
      state = state.copyWith(
        busy: false,
        clearAccount: _drive.account == null,
        account: _drive.account,
        errorMessage: 'Could not switch Google account. $error',
      );
    }
  }

  Future<bool> uploadBackupToGoogleDrive({
    String trigger = CloudBackupTrigger.manual,
    bool silent = false,
  }) async {
    if (state.backingUp) {
      return false;
    }
    state = state.copyWith(
      backingUp: true,
      busy: silent ? state.busy : true,
      clearError: true,
      clearStatus: true,
    );
    File? snapshot;
    String attemptedName = 'fuel_station_backup.db';
    try {
      if (_drive.account == null) {
        await _drive.restoreSession();
      }
      if (_drive.account == null) {
        if (!await _drive.hasConfiguredCredentials()) {
          throw StateError(
            'Save Google OAuth credentials and sign in before backing up.',
          );
        }
        final GoogleDriveAccount account = await _drive.authenticate();
        state = state.copyWith(account: account);
        await _db.insertAuditLog(
          actionType: AuditActionType.accountConnect,
          details: 'Google Drive connected as ${account.email}',
        );
      }
      final DateTime at = DateTime.now();
      final String remoteName = _backupFileName(at);
      attemptedName = remoteName;
      final String stagingDir = p.join(
        await _db.dataDirectoryPath,
        'backup_staging',
      );
      snapshot = await _db.createConsistentDatabaseCopy(
        p.join(stagingDir, remoteName),
      );
      final String? knownFolder = await _db.readSetting(
        DatabaseHelper.settingDriveBackupFolderId,
      );
      final String folderId = await _drive.ensureBackupFolder(
        knownFolderId: knownFolder,
      );
      await _db.writeSetting(
        DatabaseHelper.settingDriveBackupFolderId,
        folderId,
      );
      final String driveFileId = await _drive.uploadDatabaseFile(
        dbFile: snapshot,
        remoteName: remoteName,
        knownFolderId: folderId,
      );
      await _recordSuccessfulBackup(
        at: at,
        remoteName: remoteName,
        driveFileId: driveFileId,
        trigger: trigger,
      );
      final int reports = await _uploadRecentShiftReports(
        folderId: folderId,
        trigger: trigger,
      );
      final String auditType = trigger == CloudBackupTrigger.periodic
          ? AuditActionType.periodicBackup
          : trigger == CloudBackupTrigger.shiftClose
          ? AuditActionType.shiftClosedBackup
          : AuditActionType.driveSync;
      await _db.insertAuditLog(
        actionType: auditType,
        details:
            'Uploaded $remoteName (Drive file $driveFileId) to '
            '${GoogleDriveBackupService.backupFolderName}'
            '${reports > 0 ? ' plus $reports shift report(s)' : ''}.',
      );
      await fetchAuditLogs(actionFilter: state.actionFilter);
      await fetchDatabaseMetrics();
      state = state.copyWith(
        busy: silent ? state.busy : false,
        backingUp: false,
        lastBackupAt: at,
        lastBackupFileName: remoteName,
        lastBackupDriveFileId: driveFileId,
        statusMessage:
            'Backup complete: $remoteName'
            '${reports > 0 ? ' · $reports shift report(s)' : ''}',
      );
      return true;
    } catch (error, stack) {
      debugPrint(
        'SettingsNotifier.uploadBackupToGoogleDrive failed: $error\n$stack',
      );
      try {
        await _db.insertCloudBackupLog(
          fileName: attemptedName,
          status: 'FAILED',
          triggerSource: trigger,
          details: '$error',
        );
      } catch (logError, logStack) {
        debugPrint(
          'SettingsNotifier: failed to write cloud_backup_logs: '
          '$logError\n$logStack',
        );
      }
      state = state.copyWith(
        busy: silent ? state.busy : false,
        backingUp: false,
        errorMessage: 'Google Drive upload failed. $error',
      );
      return false;
    } finally {
      if (snapshot != null) {
        try {
          if (await snapshot.exists()) {
            await snapshot.delete();
          }
        } catch (error, stack) {
          debugPrint(
            'SettingsNotifier: could not delete staging snapshot: '
            '$error\n$stack',
          );
        }
      }
    }
  }

  Future<void> maybeUploadOnShiftClose() async {
    try {
      final String? auto = await _db.readSetting(
        DatabaseHelper.settingAutoBackupOnShiftClose,
      );
      if (auto != '1') {
        return;
      }
      if (_drive.account == null) {
        await _drive.restoreSession();
      }
      if (_drive.account == null) {
        debugPrint(
          'SettingsNotifier: auto Drive backup skipped (no Google account).',
        );
        return;
      }
      await uploadBackupToGoogleDrive(
        trigger: CloudBackupTrigger.shiftClose,
        silent: true,
      );
    } catch (error, stack) {
      debugPrint(
        'SettingsNotifier.maybeUploadOnShiftClose failed: $error\n$stack',
      );
    }
  }

  Future<void> setAutoBackupOnShiftClose(bool enabled) async {
    try {
      await _db.writeSetting(
        DatabaseHelper.settingAutoBackupOnShiftClose,
        enabled ? '1' : '0',
      );
      state = state.copyWith(autoBackupOnShiftClose: enabled);
    } catch (error, stack) {
      debugPrint(
        'SettingsNotifier.setAutoBackupOnShiftClose failed: $error\n$stack',
      );
      state = state.copyWith(
        errorMessage: 'Could not save the auto-backup preference. $error',
      );
    }
  }

  Future<void> setAutoBackupIntervalHours(int hours) async {
    try {
      final int resolved = BackupIntervalHours.choices.contains(hours)
          ? hours
          : BackupIntervalHours.off;
      await _db.writeSetting(
        DatabaseHelper.settingAutoBackupIntervalHours,
        '$resolved',
      );
      state = state.copyWith(autoBackupIntervalHours: resolved);
      _restartPeriodicBackupWatch();
    } catch (error, stack) {
      debugPrint(
        'SettingsNotifier.setAutoBackupIntervalHours failed: $error\n$stack',
      );
      state = state.copyWith(
        errorMessage: 'Could not save the backup interval. $error',
      );
    }
  }

  void _restartPeriodicBackupWatch() {
    _periodicBackupTimer?.cancel();
    _periodicBackupTimer = null;
    if (state.autoBackupIntervalHours <= 0) {
      return;
    }
    _periodicBackupTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      unawaited(_maybeRunPeriodicBackup());
    });
  }

  Future<void> _maybeRunPeriodicBackup() async {
    if (_periodicBackupInFlight || state.backingUp) {
      return;
    }
    final int hours = state.autoBackupIntervalHours;
    if (hours <= 0) {
      return;
    }
    final DateTime? last = state.lastBackupAt;
    if (last != null &&
        DateTime.now().difference(last) < Duration(hours: hours)) {
      return;
    }
    if (_drive.account == null) {
      await _drive.restoreSession();
    }
    if (_drive.account == null) {
      debugPrint(
        'SettingsNotifier: periodic Drive backup skipped (no Google account).',
      );
      return;
    }
    _periodicBackupInFlight = true;
    try {
      await uploadBackupToGoogleDrive(
        trigger: CloudBackupTrigger.periodic,
        silent: true,
      );
    } finally {
      _periodicBackupInFlight = false;
    }
  }

  Future<void> _recordSuccessfulBackup({
    required DateTime at,
    required String remoteName,
    required String driveFileId,
    required String trigger,
  }) async {
    await _db.writeSetting(
      DatabaseHelper.settingLastBackupAt,
      at.toIso8601String(),
    );
    await _db.writeSetting(
      DatabaseHelper.settingLastBackupFileName,
      remoteName,
    );
    await _db.writeSetting(
      DatabaseHelper.settingLastBackupDriveFileId,
      driveFileId,
    );
    await _db.insertCloudBackupLog(
      fileName: remoteName,
      driveFileId: driveFileId,
      status: 'SUCCESS',
      triggerSource: trigger,
      details:
          'Uploaded to ${GoogleDriveBackupService.backupFolderName} '
          '(Drive file $driveFileId).',
    );
  }

  Future<int> _uploadRecentShiftReports({
    required String folderId,
    required String trigger,
  }) async {
    try {
      final List<File> reports = await _recentShiftReportPdfs();
      int uploaded = 0;
      for (final File pdf in reports) {
        final String name = p.basename(pdf.path);
        try {
          final String id = await _drive.uploadFile(
            file: pdf,
            remoteName: name,
            mimeType: 'application/pdf',
            knownFolderId: folderId,
          );
          await _db.insertCloudBackupLog(
            fileName: name,
            driveFileId: id,
            status: 'SUCCESS',
            triggerSource: trigger,
            details: 'Shift report uploaded to FuelPoint_Backups.',
          );
          uploaded += 1;
        } catch (error, stack) {
          debugPrint(
            'SettingsNotifier: shift report upload failed for $name: '
            '$error\n$stack',
          );
          await _db.insertCloudBackupLog(
            fileName: name,
            status: 'FAILED',
            triggerSource: trigger,
            details: 'Shift report upload failed. $error',
          );
        }
      }
      return uploaded;
    } catch (error, stack) {
      debugPrint(
        'SettingsNotifier._uploadRecentShiftReports failed: $error\n$stack',
      );
      return 0;
    }
  }

  Future<List<File>> _recentShiftReportPdfs() async {
    try {
      final Directory docs = await getApplicationDocumentsDirectory();
      final Directory dir = Directory(
        p.join(docs.path, 'Exported_Reports', 'Shifts'),
      );
      if (!await dir.exists()) {
        return const <File>[];
      }
      final DateTime cutoff = DateTime.now().subtract(
        const Duration(hours: 36),
      );
      final List<File> files = <File>[];
      await for (final FileSystemEntity entity in dir.list()) {
        if (entity is! File) {
          continue;
        }
        if (!entity.path.toLowerCase().endsWith('.pdf')) {
          continue;
        }
        final DateTime modified = await entity.lastModified();
        if (!modified.isBefore(cutoff)) {
          files.add(entity);
        }
      }
      files.sort(
        (File a, File b) => p.basename(b.path).compareTo(p.basename(a.path)),
      );
      return files;
    } catch (error, stack) {
      debugPrint(
        'SettingsNotifier._recentShiftReportPdfs failed: $error\n$stack',
      );
      return const <File>[];
    }
  }

  static String _backupFileName(DateTime at) {
    final String y = at.year.toString().padLeft(4, '0');
    final String m = at.month.toString().padLeft(2, '0');
    final String d = at.day.toString().padLeft(2, '0');
    final String h = at.hour.toString().padLeft(2, '0');
    final String min = at.minute.toString().padLeft(2, '0');
    final String sec = at.second.toString().padLeft(2, '0');
    return 'fuel_station_backup_$y$m${d}_$h$min$sec.db';
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(
  SettingsNotifier.new,
);
