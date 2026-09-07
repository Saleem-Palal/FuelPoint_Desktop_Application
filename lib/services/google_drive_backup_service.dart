import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as gdrive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../core/google_drive_oauth_config.dart';
import 'database_helper.dart';

/// Connected Google identity shown on the Settings account card.
@immutable
class GoogleDriveAccount {
  const GoogleDriveAccount({
    required this.displayName,
    required this.email,
    this.photoUrl,
  });

  final String displayName;
  final String email;
  final String? photoUrl;

  String get initials {
    final String source = displayName.trim().isEmpty ? email : displayName;
    final List<String> parts = source
        .split(RegExp(r'\s+'))
        .where((String part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return 'G';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }
}

/// Windows desktop Google Sign-In + Drive API v3 (`drive.file`).
///
/// Official `google_sign_in` is not supported on Windows, and
/// `google_sign_in_all_platforms` 2.x conflicts with the onboarding plugin
/// (`google_sign_in` 6.3.0). This service uses the installed-app OAuth
/// loopback flow (`googleapis_auth`) with Client ID / Secret stored in
/// `station_settings`. Refresh tokens live beside the station database.
class GoogleDriveBackupService {
  GoogleDriveBackupService(this._db);

  static const String credentialsFileName = 'google_drive_credentials.json';
  static const String backupFolderName = 'FuelPoint_Backups';
  static const Duration networkTimeout = Duration(minutes: 3);
  static const List<String> scopes = <String>[
    gdrive.DriveApi.driveFileScope,
    'https://www.googleapis.com/auth/userinfo.email',
    'https://www.googleapis.com/auth/userinfo.profile',
  ];

  final DatabaseHelper _db;

  AutoRefreshingAuthClient? _client;
  GoogleDriveAccount? _account;

  GoogleDriveAccount? get account => _account;

  bool get isSignedIn => _account != null && _client != null;

  Future<void> dispose() async {
    _client?.close();
    _client = null;
  }

  Future<GoogleDriveOAuthConfig> loadConfig() {
    return GoogleDriveOAuthConfig.loadPreferringDatabase(_db);
  }

  Future<bool> hasConfiguredCredentials() async {
    final GoogleDriveOAuthConfig config = await loadConfig();
    return config.isConfigured;
  }

  Future<GoogleDriveAccount?> restoreSession() async {
    try {
      final AutoRefreshingAuthClient? client = await _clientFromDisk();
      if (client == null) {
        return null;
      }
      _client = client;
      _account = await _guardNetwork(() => _loadProfile(client));
      await _persistSession(client.credentials, _account);
      debugPrint(
        'GoogleDriveBackupService: restored session for ${_account?.email}',
      );
      return _account;
    } catch (error, stack) {
      debugPrint(
        'GoogleDriveBackupService.restoreSession failed: $error\n$stack',
      );
      await signOut();
      return null;
    }
  }

  /// Opens the system browser for OAuth2 consent (`drive.file`).
  Future<GoogleDriveAccount> authenticate() async {
    try {
      final GoogleDriveOAuthConfig config = await loadConfig();
      if (!config.isConfigured) {
        throw StateError(
          'Google OAuth is not configured. Open Settings, paste a Desktop '
          'Client ID and Client Secret, then tap Save Credentials.',
        );
      }

      await _closeClient();
      final AutoRefreshingAuthClient client = await _guardNetwork(() {
        return clientViaUserConsent(
          config.toClientId(),
          scopes,
          _promptBrowser,
          customPostAuthPage:
              '<html><body style="font-family:Segoe UI,sans-serif;padding:32px">'
              '<h2>FuelPoint</h2><p>Google account connected. '
              'You can close this window and return to the station terminal.</p>'
              '</body></html>',
        );
      });
      final GoogleDriveAccount profile = await _guardNetwork(
        () => _loadProfile(client),
      );
      _client = client;
      _account = profile;
      await _persistSession(client.credentials, profile);
      debugPrint('GoogleDriveBackupService: signed in as ${profile.email}');
      return profile;
    } catch (error, stack) {
      debugPrint(
        'GoogleDriveBackupService.authenticate failed: $error\n$stack',
      );
      rethrow;
    }
  }

  /// Signs out the current Google account (clears the local refresh token).
  Future<void> signOut() async {
    try {
      final String? token = _client?.credentials.accessToken.data;
      _client?.close();
      _client = null;
      _account = null;
      if (token != null && token.isNotEmpty) {
        try {
          await http
              .post(
                Uri.parse('https://oauth2.googleapis.com/revoke?token=$token'),
              )
              .timeout(const Duration(seconds: 12));
        } catch (error, stack) {
          debugPrint(
            'GoogleDriveBackupService: token revoke failed: $error\n$stack',
          );
        }
      }
      final File file = await _credentialsFile();
      if (await file.exists()) {
        await file.delete();
      }
      debugPrint('GoogleDriveBackupService: signed out');
    } catch (error, stack) {
      debugPrint('GoogleDriveBackupService.signOut failed: $error\n$stack');
      rethrow;
    }
  }

  /// Uploads a local file into Drive folder `FuelPoint_Backups`.
  Future<String> uploadFile({
    required File file,
    required String remoteName,
    String mimeType = 'application/octet-stream',
    String? knownFolderId,
  }) async {
    try {
      if (!await file.exists()) {
        throw StateError('Backup file was not found at ${file.path}');
      }
      final AutoRefreshingAuthClient client = await _requireClient();
      final gdrive.DriveApi api = gdrive.DriveApi(client);
      final String folderId = await _ensureBackupFolder(
        api,
        knownFolderId: knownFolderId,
      );
      final int length = await file.length();
      final gdrive.File meta = gdrive.File()
        ..name = remoteName
        ..mimeType = mimeType
        ..parents = <String>[folderId];
      final gdrive.File created = await _guardNetwork(() {
        return api.files.create(
          meta,
          uploadMedia: gdrive.Media(file.openRead(), length),
          $fields: 'id,name',
        );
      });
      final String id = created.id ?? '';
      debugPrint(
        'GoogleDriveBackupService: uploaded $remoteName '
        '(${created.id}) to $backupFolderName',
      );
      return id;
    } catch (error, stack) {
      debugPrint('GoogleDriveBackupService.uploadFile failed: $error\n$stack');
      rethrow;
    }
  }

  /// Uploads a SQLite snapshot into Drive folder `FuelPoint_Backups`.
  Future<String> uploadDatabaseFile({
    required File dbFile,
    required String remoteName,
    String? knownFolderId,
  }) {
    return uploadFile(
      file: dbFile,
      remoteName: remoteName,
      mimeType: 'application/x-sqlite3',
      knownFolderId: knownFolderId,
    );
  }

  Future<String> ensureBackupFolder({String? knownFolderId}) async {
    final AutoRefreshingAuthClient client = await _requireClient();
    return _ensureBackupFolder(
      gdrive.DriveApi(client),
      knownFolderId: knownFolderId,
    );
  }

  Future<void> _promptBrowser(String url) async {
    final Uri uri = Uri.parse(url);
    final bool launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      throw StateError('Could not open the Google sign-in browser at $url');
    }
  }

  Future<AutoRefreshingAuthClient> _requireClient() async {
    final AutoRefreshingAuthClient? open = _client;
    if (open != null) {
      return open;
    }
    final AutoRefreshingAuthClient? restored = await _clientFromDisk();
    if (restored == null) {
      throw StateError('No Google account is connected.');
    }
    _client = restored;
    _account ??= await _loadProfile(restored);
    return restored;
  }

  Future<AutoRefreshingAuthClient?> _clientFromDisk() async {
    final File file = await _credentialsFile();
    if (!await file.exists()) {
      return null;
    }
    final GoogleDriveOAuthConfig config = await loadConfig();
    if (!config.isConfigured) {
      return null;
    }
    final Object? decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      return null;
    }
    final Map<String, dynamic> root = Map<String, dynamic>.from(decoded);
    final Object? credRaw = root['credentials'];
    if (credRaw is! Map) {
      return null;
    }
    final Map<String, dynamic> credMap = Map<String, dynamic>.from(credRaw);
    final Object? tokenRaw = credMap['accessToken'];
    if (tokenRaw is! Map) {
      return null;
    }
    final AccessCredentials credentials =
        AccessCredentials.fromJson(<String, dynamic>{
          'accessToken': Map<String, dynamic>.from(tokenRaw),
          'refreshToken': credMap['refreshToken'],
          'idToken': credMap['idToken'],
          'scopes': credMap['scopes'],
        });
    if (credentials.refreshToken == null || credentials.refreshToken!.isEmpty) {
      return null;
    }
    final Object? profileRaw = root['profile'];
    if (profileRaw is Map) {
      final Map<String, dynamic> profile = Map<String, dynamic>.from(
        profileRaw,
      );
      final String email = '${profile['email'] ?? ''}'.trim();
      if (email.isNotEmpty) {
        _account = GoogleDriveAccount(
          displayName: '${profile['displayName'] ?? ''}'.trim(),
          email: email,
          photoUrl: '${profile['photoUrl'] ?? ''}'.trim().isEmpty
              ? null
              : '${profile['photoUrl']}'.trim(),
        );
      }
    }
    return autoRefreshingClient(
      config.toClientId(),
      credentials,
      http.Client(),
    );
  }

  Future<GoogleDriveAccount> _loadProfile(AuthClient client) async {
    final gdrive.DriveApi api = gdrive.DriveApi(client);
    final gdrive.About about = await api.about.get(
      $fields: 'user(displayName,emailAddress,photoLink)',
    );
    final gdrive.User? user = about.user;
    final String email = user?.emailAddress?.trim() ?? '';
    final String name = user?.displayName?.trim() ?? '';
    return GoogleDriveAccount(
      displayName: name.isEmpty ? email : name,
      email: email.isEmpty ? 'Google Account' : email,
      photoUrl: user?.photoLink,
    );
  }

  Future<String> _ensureBackupFolder(
    gdrive.DriveApi api, {
    String? knownFolderId,
  }) async {
    final String? known = knownFolderId?.trim();
    if (known != null && known.isNotEmpty) {
      try {
        final Object existing = await _guardNetwork(() {
          return api.files.get(known, $fields: 'id,trashed');
        });
        final String existingId = existing is gdrive.File
            ? (existing.id ?? '').trim()
            : '';
        if (existing is gdrive.File &&
            existing.trashed != true &&
            existingId.isNotEmpty) {
          return existingId;
        }
      } catch (error, stack) {
        debugPrint(
          'GoogleDriveBackupService: stored folder $known missing: '
          '$error\n$stack',
        );
      }
    }

    final gdrive.FileList listed = await _guardNetwork(() {
      return api.files.list(
        q:
            "mimeType='application/vnd.google-apps.folder' and "
            "name='$backupFolderName' and trashed=false",
        spaces: 'drive',
        pageSize: 1,
        $fields: 'files(id,name)',
      );
    });
    final List<gdrive.File> files = listed.files ?? const <gdrive.File>[];
    if (files.isNotEmpty && (files.first.id ?? '').isNotEmpty) {
      return files.first.id!;
    }

    final gdrive.File created = await _guardNetwork(() {
      return api.files.create(
        gdrive.File()
          ..name = backupFolderName
          ..mimeType = 'application/vnd.google-apps.folder',
        $fields: 'id',
      );
    });
    final String id = created.id ?? '';
    if (id.isEmpty) {
      throw StateError('Google Drive did not return a folder id.');
    }
    return id;
  }

  Future<void> _persistSession(
    AccessCredentials credentials,
    GoogleDriveAccount? profile,
  ) async {
    final File file = await _credentialsFile();
    final Map<String, dynamic> payload = <String, dynamic>{
      'credentials': <String, dynamic>{
        'accessToken': credentials.accessToken.toJson(),
        'refreshToken': credentials.refreshToken,
        'idToken': credentials.idToken,
        'scopes': credentials.scopes,
      },
      if (profile != null)
        'profile': <String, dynamic>{
          'displayName': profile.displayName,
          'email': profile.email,
          'photoUrl': profile.photoUrl,
        },
    };
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  Future<File> _credentialsFile() async {
    final String dir = await _db.dataDirectoryPath;
    return File('$dir${Platform.pathSeparator}$credentialsFileName');
  }

  Future<void> _closeClient() async {
    _client?.close();
    _client = null;
  }

  Future<T> _guardNetwork<T>(Future<T> Function() action) async {
    try {
      return await action().timeout(networkTimeout);
    } on TimeoutException {
      throw StateError(
        'Google Drive timed out. Check the station internet connection and try again.',
      );
    } on SocketException {
      throw StateError(
        'No internet connection. Google Drive could not be reached.',
      );
    } on HandshakeException {
      throw StateError(
        'Secure connection to Google Drive failed. Check the network and try again.',
      );
    } on http.ClientException catch (error) {
      throw StateError('Google Drive network error. $error');
    }
  }
}
