import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:googleapis_auth/googleapis_auth.dart';

import '../services/database_helper.dart';

/// Desktop OAuth client for Drive API v3 (`drive.file` scope).
///
/// Credentials are stored in `station_settings` (local SQLite), never in
/// repository source. Resolve order:
/// 1. `station_settings` keys written from Settings
/// 2. Legacy `google_oauth_client.json` beside the database (migrated into SQLite)
/// 3. Optional `--dart-define` values for a developer workstation
///
/// Create an OAuth **Desktop** client in Google Cloud Console, enable the
/// Drive API, then paste Client ID and Client Secret in Settings.
class GoogleDriveOAuthConfig {
  const GoogleDriveOAuthConfig({required this.clientId, this.clientSecret});

  final String clientId;
  final String? clientSecret;

  bool get isConfigured {
    return clientId.trim().isNotEmpty && (clientSecret ?? '').trim().isNotEmpty;
  }

  ClientId toClientId() {
    final String secret = clientSecret?.trim() ?? '';
    if (secret.isEmpty) {
      return ClientId(clientId.trim());
    }
    return ClientId(clientId.trim(), secret);
  }

  static const String fileName = 'google_oauth_client.json';

  static const String _defineId = String.fromEnvironment(
    'GOOGLE_OAUTH_CLIENT_ID',
  );
  static const String _defineSecret = String.fromEnvironment(
    'GOOGLE_OAUTH_CLIENT_SECRET',
  );

  /// Settings-first load used by Drive backup. Migrates a leftover JSON file
  /// into `station_settings` so secrets are not read from disk on later runs.
  static Future<GoogleDriveOAuthConfig> loadPreferringDatabase(
    DatabaseHelper db,
  ) async {
    try {
      final String? storedId = (await db.readSetting(
        DatabaseHelper.settingGoogleOauthClientId,
      ))?.trim();
      final String? storedSecret = (await db.readSetting(
        DatabaseHelper.settingGoogleOauthClientSecret,
      ))?.trim();
      if (storedId != null && storedId.isNotEmpty) {
        return GoogleDriveOAuthConfig(
          clientId: storedId,
          clientSecret: (storedSecret == null || storedSecret.isEmpty)
              ? null
              : storedSecret,
        );
      }

      final GoogleDriveOAuthConfig fromFile = await load(
        Directory(await db.dataDirectoryPath),
      );
      if (fromFile.clientId.trim().isNotEmpty) {
        await persistToDatabase(db, fromFile);
        return fromFile;
      }
      return const GoogleDriveOAuthConfig(clientId: '');
    } catch (error, stack) {
      debugPrint(
        'GoogleDriveOAuthConfig.loadPreferringDatabase failed: $error\n$stack',
      );
      return const GoogleDriveOAuthConfig(clientId: '');
    }
  }

  static Future<void> persistToDatabase(
    DatabaseHelper db,
    GoogleDriveOAuthConfig config,
  ) async {
    await db.writeSetting(
      DatabaseHelper.settingGoogleOauthClientId,
      config.clientId.trim(),
    );
    final String secret = config.clientSecret?.trim() ?? '';
    if (secret.isEmpty) {
      await db.deleteSetting(DatabaseHelper.settingGoogleOauthClientSecret);
    } else {
      await db.writeSetting(
        DatabaseHelper.settingGoogleOauthClientSecret,
        secret,
      );
    }
  }

  /// File / dart-define lookup used by onboarding (database may not exist yet).
  static Future<GoogleDriveOAuthConfig> load(Directory dataDir) async {
    if (_defineId.trim().isNotEmpty) {
      return GoogleDriveOAuthConfig(
        clientId: _defineId.trim(),
        clientSecret: _defineSecret.trim().isEmpty
            ? null
            : _defineSecret.trim(),
      );
    }

    final File file = File('${dataDir.path}${Platform.pathSeparator}$fileName');
    if (!await file.exists()) {
      return const GoogleDriveOAuthConfig(clientId: '');
    }

    try {
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return const GoogleDriveOAuthConfig(clientId: '');
      }
      final Map<String, dynamic> root = Map<String, dynamic>.from(decoded);
      final Map<String, dynamic> installed = root.containsKey('installed')
          ? Map<String, dynamic>.from(root['installed'] as Map)
          : root.containsKey('web')
          ? Map<String, dynamic>.from(root['web'] as Map)
          : root;
      final String id =
          '${installed['client_id'] ?? installed['clientId'] ?? ''}'.trim();
      final String secret =
          '${installed['client_secret'] ?? installed['clientSecret'] ?? ''}'
              .trim();
      return GoogleDriveOAuthConfig(
        clientId: id,
        clientSecret: secret.isEmpty ? null : secret,
      );
    } catch (error, stack) {
      debugPrint('GoogleDriveOAuthConfig.load failed: $error\n$stack');
      return const GoogleDriveOAuthConfig(clientId: '');
    }
  }
}
