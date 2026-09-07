import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/google_drive_oauth_config.dart';
import '../services/database_helper.dart';

/// SharedPreferences keys for first-run station identity.
class OnboardingPrefs {
  static const String stationName = 'station_name';
  static const String contactNo = 'contact_no';
  static const String ownerEmail = 'owner_email';
  static const String ownerName = 'owner_name';
  static const String ownerGoogleId = 'owner_google_id';
  static const String isOnboardingCompleted = 'isOnboardingCompleted';

  static Future<bool> isCompleted() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getBool(isOnboardingCompleted) ?? false;
    } catch (error, stack) {
      debugPrint('OnboardingPrefs.isCompleted failed: $error\n$stack');
      return false;
    }
  }
}

@immutable
class OnboardingState {
  const OnboardingState({
    required this.busy,
    required this.isGoogleAuthenticated,
    this.ownerEmail = '',
    this.ownerName = '',
    this.ownerGoogleId = '',
    this.errorMessage,
  });

  final bool busy;
  final bool isGoogleAuthenticated;
  final String ownerEmail;
  final String ownerName;
  final String ownerGoogleId;
  final String? errorMessage;

  bool get isGoogleLinkDeferred =>
      isGoogleAuthenticated && ownerGoogleId == pendingGoogleId;

  static const String pendingGoogleId = 'pending';

  OnboardingState copyWith({
    bool? busy,
    bool? isGoogleAuthenticated,
    String? ownerEmail,
    String? ownerName,
    String? ownerGoogleId,
    String? errorMessage,
    bool clearOwner = false,
    bool clearError = false,
  }) {
    return OnboardingState(
      busy: busy ?? this.busy,
      isGoogleAuthenticated: clearOwner
          ? false
          : (isGoogleAuthenticated ?? this.isGoogleAuthenticated),
      ownerEmail: clearOwner ? '' : (ownerEmail ?? this.ownerEmail),
      ownerName: clearOwner ? '' : (ownerName ?? this.ownerName),
      ownerGoogleId: clearOwner ? '' : (ownerGoogleId ?? this.ownerGoogleId),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  static OnboardingState empty() {
    return const OnboardingState(busy: false, isGoogleAuthenticated: false);
  }
}

class OnboardingNotifier extends Notifier<OnboardingState> {
  /// Plugin used on Android / iOS / macOS / web. Windows has no
  /// `google_sign_in` implementation — identity there uses desktop OAuth.
  final GoogleSignIn googleSignIn = GoogleSignIn(
    scopes: const <String>['email', 'profile', 'openid'],
  );

  AutoRefreshingAuthClient? _desktopClient;

  static const List<String> _identityScopes = <String>[
    'openid',
    'https://www.googleapis.com/auth/userinfo.email',
    'https://www.googleapis.com/auth/userinfo.profile',
  ];

  @override
  OnboardingState build() {
    ref.onDispose(() {
      _desktopClient?.close();
      _desktopClient = null;
    });
    return OnboardingState.empty();
  }

  /// Google Drive linking is not wired yet. Marks owner identity as deferred
  /// so station setup can continue.
  void deferGoogleAccountLink() {
    debugPrint('Onboarding: Google account link deferred');
    state = state.copyWith(
      busy: false,
      isGoogleAuthenticated: true,
      ownerEmail: '',
      ownerName: 'Pending Google Link',
      ownerGoogleId: OnboardingState.pendingGoogleId,
      clearError: true,
    );
  }

  /// Invokes Google Sign-In, extracts owner profile, and updates local state.
  ///
  /// Drive API is not requested. This is owner identity only.
  Future<bool> signInWithGoogle() async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final _OwnerIdentity? identity = Platform.isWindows || Platform.isLinux
          ? await _signInDesktopIdentity()
          : await _signInWithPlugin();
      if (identity == null) {
        debugPrint('Onboarding: Google sign-in cancelled by operator');
        state = state.copyWith(busy: false);
        return false;
      }
      state = state.copyWith(
        busy: false,
        isGoogleAuthenticated: true,
        ownerEmail: identity.email,
        ownerName: identity.name,
        ownerGoogleId: identity.googleId,
      );
      debugPrint(
        'Onboarding: owner signed in as ${identity.email} '
        '(google_id=${identity.googleId})',
      );
      return true;
    } catch (error, stack) {
      debugPrint('OnboardingNotifier.signInWithGoogle failed: $error\n$stack');
      state = state.copyWith(
        busy: false,
        errorMessage: 'Google sign-in failed. $error',
      );
      return false;
    }
  }

  /// Clears authenticated owner state if setup is cancelled.
  Future<void> signOutGoogle() async {
    try {
      if (!Platform.isWindows && !Platform.isLinux) {
        await googleSignIn.signOut();
      }
      _desktopClient?.close();
      _desktopClient = null;
      state = state.copyWith(clearOwner: true, busy: false, clearError: true);
      debugPrint('Onboarding: Google owner identity cleared');
    } catch (error, stack) {
      debugPrint('OnboardingNotifier.signOutGoogle failed: $error\n$stack');
      state = state.copyWith(
        clearOwner: true,
        busy: false,
        errorMessage: 'Could not clear Google session. $error',
      );
    }
  }

  /// Validates inputs, persists station + owner identity, initializes SQLite.
  Future<bool> completeOnboarding({
    required String stationName,
    required String contactNo,
  }) async {
    final String name = stationName.trim();
    final String contact = contactNo.trim();
    final String nameError = _validateStationName(name);
    if (nameError.isNotEmpty) {
      state = state.copyWith(errorMessage: nameError);
      debugPrint('Onboarding: rejected — $nameError');
      return false;
    }
    final String contactError = _validateContact(contact);
    if (contactError.isNotEmpty) {
      state = state.copyWith(errorMessage: contactError);
      debugPrint('Onboarding: rejected — $contactError');
      return false;
    }
    if (!state.isGoogleAuthenticated) {
      const String message =
          'Confirm owner Google account (link can be set up later) before launching.';
      state = state.copyWith(errorMessage: message);
      debugPrint('Onboarding: rejected — owner Google step not confirmed');
      return false;
    }

    state = state.copyWith(busy: true, clearError: true);
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(OnboardingPrefs.stationName, name);
      await prefs.setString(OnboardingPrefs.contactNo, contact);
      await prefs.setString(OnboardingPrefs.ownerEmail, state.ownerEmail);
      await prefs.setString(OnboardingPrefs.ownerName, state.ownerName);
      await prefs.setString(OnboardingPrefs.ownerGoogleId, state.ownerGoogleId);
      await prefs.setBool(OnboardingPrefs.isOnboardingCompleted, true);
      debugPrint(
        'Onboarding: persisted station="$name" contact="$contact" '
        'owner=${state.ownerEmail}',
      );

      await DatabaseHelper.instance.initializeStationDatabase();
      debugPrint(
        'Onboarding: fuel_point_system.db initialized '
        '(managers, helpers, customers, diesel_stock, shifts, '
        'sales_transactions, purchases, unified_udhaar_ledger)',
      );

      state = state.copyWith(busy: false);
      return true;
    } catch (error, stack) {
      debugPrint(
        'OnboardingNotifier.completeOnboarding failed: $error\n$stack',
      );
      try {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setBool(OnboardingPrefs.isOnboardingCompleted, false);
      } catch (prefsError, prefsStack) {
        debugPrint(
          'Onboarding: could not roll back completion flag: '
          '$prefsError\n$prefsStack',
        );
      }
      state = state.copyWith(
        busy: false,
        errorMessage: 'Could not finish station setup. $error',
      );
      return false;
    }
  }

  Future<_OwnerIdentity?> _signInWithPlugin() async {
    debugPrint('Onboarding: invoking googleSignIn.signIn()');
    final GoogleSignInAccount? account = await googleSignIn.signIn();
    if (account == null) {
      return null;
    }
    final String email = account.email.trim();
    final String displayName = (account.displayName ?? '').trim();
    final String googleId = account.id.trim();
    if (email.isEmpty || googleId.isEmpty) {
      throw StateError('Google account did not return an email or user id.');
    }
    return _OwnerIdentity(
      email: email,
      name: displayName.isEmpty ? email : displayName,
      googleId: googleId,
    );
  }

  /// Windows / Linux identity via installed-app OAuth (no Drive scopes).
  Future<_OwnerIdentity?> _signInDesktopIdentity() async {
    debugPrint(
      'Onboarding: google_sign_in is not available on this desktop OS; '
      'using identity-only OAuth (userinfo.email / userinfo.profile)',
    );
    final GoogleDriveOAuthConfig config = await _loadOauthConfig();
    if (!config.isConfigured) {
      throw StateError(
        'Google OAuth is not configured. After setup, paste a Desktop '
        'Client ID and Client Secret in Settings, or place '
        '${GoogleDriveOAuthConfig.fileName} in '
        '${DatabaseHelper.windowsDataDirectory}.',
      );
    }

    _desktopClient?.close();
    _desktopClient = null;
    final AutoRefreshingAuthClient client = await clientViaUserConsent(
      config.toClientId(),
      _identityScopes,
      _promptBrowser,
      customPostAuthPage:
          '<html><body style="font-family:Segoe UI,sans-serif;padding:32px;'
          'background:#12181F;color:#FFFFFF">'
          '<h2>FuelPoint Station OS</h2>'
          '<p>Owner account verified. You can close this window and return '
          'to station setup.</p></body></html>',
    );
    _desktopClient = client;
    return _loadUserInfo(client);
  }

  Future<_OwnerIdentity> _loadUserInfo(AuthClient client) async {
    final http.Response response = await client.get(
      Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Google userinfo failed (${response.statusCode}): ${response.body}',
      );
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw StateError('Google userinfo returned an unexpected payload.');
    }
    final Map<String, dynamic> json = Map<String, dynamic>.from(decoded);
    final String email = '${json['email'] ?? ''}'.trim();
    final String name = '${json['name'] ?? ''}'.trim();
    final String googleId = '${json['sub'] ?? json['id'] ?? ''}'.trim();
    if (email.isEmpty || googleId.isEmpty) {
      throw StateError('Google account did not return an email or user id.');
    }
    return _OwnerIdentity(
      email: email,
      name: name.isEmpty ? email : name,
      googleId: googleId,
    );
  }

  Future<GoogleDriveOAuthConfig> _loadOauthConfig() async {
    return GoogleDriveOAuthConfig.load(await _dataDirectory());
  }

  Future<Directory> _dataDirectory() async {
    if (Platform.isWindows) {
      try {
        final Directory preferred = Directory(
          DatabaseHelper.windowsDataDirectory,
        );
        if (!await preferred.exists()) {
          await preferred.create(recursive: true);
        }
        return preferred;
      } catch (error, stack) {
        debugPrint(
          'Onboarding: could not use '
          '${DatabaseHelper.windowsDataDirectory}: $error\n$stack',
        );
      }
    }
    return getApplicationSupportDirectory();
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

  static String _validateStationName(String name) {
    if (name.length < 2) {
      return 'Enter a station name (at least 2 characters).';
    }
    return '';
  }

  static String _validateContact(String contact) {
    if (contact.isEmpty) {
      return 'Enter a station contact number.';
    }
    final String digits = contact.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7) {
      return 'Enter a valid contact number (at least 7 digits).';
    }
    return '';
  }
}

@immutable
class _OwnerIdentity {
  const _OwnerIdentity({
    required this.email,
    required this.name,
    required this.googleId,
  });

  final String email;
  final String name;
  final String googleId;
}

final onboardingProvider =
    NotifierProvider<OnboardingNotifier, OnboardingState>(
      OnboardingNotifier.new,
    );
