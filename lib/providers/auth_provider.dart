import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/security/pin_hasher.dart';
import '../services/database_helper.dart';
import 'onboarding_provider.dart';

/// Flip to `true` to force the PIN screen during `flutter run`.
///
/// Debug default is `false` so developers land on the dashboard.
/// Release builds always enforce PIN because [kDebugMode] is false
/// (`enableLoginInDebug` is treated as on in production).
const bool enableLoginInDebug = false;

/// Skip PIN when debugging and [enableLoginInDebug] is off.
bool get shouldBypassLogin => kDebugMode && !enableLoginInDebug;

@immutable
class AuthManager {
  const AuthManager({required this.id, required this.name});

  final String id;
  final String name;

  String get initials {
    final List<String> parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((String part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return id.isEmpty ? '?' : id.substring(0, 1).toUpperCase();
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  static AuthManager fromRow(Map<String, dynamic> row) {
    final String id = '${row['manager_ID'] ?? ''}'.trim();
    final String name = '${row['Manager_name'] ?? ''}'.trim();
    return AuthManager(id: id, name: name.isEmpty ? id : name);
  }
}

@immutable
class AuthState {
  const AuthState({
    required this.loading,
    required this.busy,
    required this.isAuthenticated,
    required this.managers,
    this.selectedManagerId,
    this.activeManagerId,
    this.activeManagerName = '',
    this.stationName = '',
    this.contactNo = '',
    this.openShift,
    this.errorMessage,
    this.failedAttempts = 0,
    this.isOwnerElevated = false,
  });

  final bool loading;
  final bool busy;
  final bool isAuthenticated;
  final List<AuthManager> managers;
  final String? selectedManagerId;
  final String? activeManagerId;
  final String activeManagerName;
  final String stationName;
  final String contactNo;
  final Map<String, dynamic>? openShift;
  final String? errorMessage;
  final int failedAttempts;

  /// In-memory owner elevation. Default locked; never persisted across restart.
  final bool isOwnerElevated;

  AuthManager? get selectedManager {
    final String? id = selectedManagerId;
    if (id == null) {
      return null;
    }
    for (final AuthManager manager in managers) {
      if (manager.id == id) {
        return manager;
      }
    }
    return null;
  }

  bool get hasOpenShift => openShift != null;

  AuthState copyWith({
    bool? loading,
    bool? busy,
    bool? isAuthenticated,
    List<AuthManager>? managers,
    String? selectedManagerId,
    bool clearSelected = false,
    String? activeManagerId,
    bool clearActiveManager = false,
    String? activeManagerName,
    String? stationName,
    String? contactNo,
    Map<String, dynamic>? openShift,
    bool clearOpenShift = false,
    String? errorMessage,
    bool clearError = false,
    int? failedAttempts,
    bool? isOwnerElevated,
  }) {
    return AuthState(
      loading: loading ?? this.loading,
      busy: busy ?? this.busy,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      managers: managers ?? this.managers,
      selectedManagerId: clearSelected
          ? null
          : (selectedManagerId ?? this.selectedManagerId),
      activeManagerId: clearActiveManager
          ? null
          : (activeManagerId ?? this.activeManagerId),
      activeManagerName: clearActiveManager
          ? ''
          : (activeManagerName ?? this.activeManagerName),
      stationName: stationName ?? this.stationName,
      contactNo: contactNo ?? this.contactNo,
      openShift: clearOpenShift ? null : (openShift ?? this.openShift),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      failedAttempts: failedAttempts ?? this.failedAttempts,
      isOwnerElevated: isOwnerElevated ?? this.isOwnerElevated,
    );
  }

  static AuthState empty() {
    return const AuthState(
      loading: true,
      busy: false,
      isAuthenticated: false,
      managers: <AuthManager>[],
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  final DatabaseHelper _db = DatabaseHelper.instance;
  Future<void>? _bootstrapFuture;

  @override
  AuthState build() {
    Future<void>(() => bootstrap());
    return AuthState.empty();
  }

  Future<void> bootstrap() {
    return _bootstrapFuture ??= _runBootstrap();
  }

  Future<void> _runBootstrap() async {
    try {
      await _loadStationIdentity();
      await loadManagers();
      if (shouldBypassLogin && !state.isAuthenticated) {
        await _establishDebugSession();
      } else {
        state = state.copyWith(loading: false);
      }
    } catch (error, stack) {
      debugPrint('AuthNotifier.bootstrap failed: $error\n$stack');
      state = state.copyWith(
        loading: false,
        errorMessage: 'Could not load station login. $error',
      );
    }
  }

  Future<void> _loadStationIdentity() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      state = state.copyWith(
        stationName: (prefs.getString(OnboardingPrefs.stationName) ?? '')
            .trim(),
        contactNo: (prefs.getString(OnboardingPrefs.contactNo) ?? '').trim(),
      );
    } catch (error, stack) {
      debugPrint('AuthNotifier._loadStationIdentity failed: $error\n$stack');
    }
  }

  /// Queries available station managers from SQLite.
  Future<List<Map<String, dynamic>>> loadManagers() async {
    try {
      final List<Map<String, Object?>> rows = await _db.queryManagers();
      final List<Map<String, dynamic>> mapped = rows
          .map(
            (Map<String, Object?> row) => <String, dynamic>{
              'manager_ID': '${row['manager_ID'] ?? ''}'.trim(),
              'Manager_name': '${row['Manager_name'] ?? ''}'.trim(),
            },
          )
          .where(
            (Map<String, dynamic> row) =>
                '${row['manager_ID']}'.trim().isNotEmpty,
          )
          .toList();
      final List<AuthManager> managers = mapped
          .map(AuthManager.fromRow)
          .toList();
      String? selected = state.selectedManagerId;
      if (selected != null &&
          !managers.any((AuthManager manager) => manager.id == selected)) {
        selected = null;
      }
      selected ??= managers.isEmpty ? null : managers.first.id;
      state = state.copyWith(
        managers: managers,
        selectedManagerId: selected,
        clearSelected: selected == null,
      );
      debugPrint('Auth: loaded ${managers.length} manager(s)');
      return mapped;
    } catch (error, stack) {
      debugPrint('AuthNotifier.loadManagers failed: $error\n$stack');
      state = state.copyWith(
        errorMessage: 'Could not load managers. $error',
        managers: const <AuthManager>[],
      );
      return const <Map<String, dynamic>>[];
    }
  }

  void selectManager(String managerId) {
    state = state.copyWith(
      selectedManagerId: managerId.trim(),
      clearError: true,
      failedAttempts: 0,
    );
  }

  /// Hashes [rawPin] with SHA-256 and validates against `managers.pin`.
  Future<bool> authenticateManager(String managerId, String rawPin) async {
    final String id = managerId.trim();
    final String pin = rawPin.trim();
    if (id.isEmpty) {
      state = state.copyWith(
        errorMessage: 'Select a manager before unlocking.',
      );
      return false;
    }
    if (!PinHasher.isValidPlainPin(pin)) {
      state = state.copyWith(
        errorMessage:
            'PIN must be ${PinHasher.minPinLength}–${PinHasher.maxPinLength} digits.',
      );
      return false;
    }

    state = state.copyWith(busy: true, clearError: true);
    try {
      final Map<String, Object?>? row = await _db.queryManagerById(id);
      if (row == null) {
        debugPrint('Auth: no manager row for $id');
        state = state.copyWith(
          busy: false,
          failedAttempts: state.failedAttempts + 1,
          errorMessage: 'Manager $id was not found.',
        );
        return false;
      }

      final String stored = (row['pin'] as String?)?.trim() ?? '';
      final String storedDigest = PinHasher.looksHashed(stored)
          ? stored
          : PinHasher.hash(stored);
      final bool ok = PinHasher.matches(entered: pin, stored: storedDigest);
      if (!ok) {
        debugPrint('Auth: SHA-256 PIN mismatch for $id');
        state = state.copyWith(
          busy: false,
          failedAttempts: state.failedAttempts + 1,
          errorMessage: 'Incorrect PIN. Try again.',
        );
        return false;
      }

      final String rawName = '${row['Manager_name'] ?? ''}'.trim();
      final String name = rawName.isEmpty ? id : rawName;
      final Map<String, dynamic>? open = await checkOpenShift();

      state = state.copyWith(
        busy: false,
        loading: false,
        isAuthenticated: true,
        selectedManagerId: id,
        activeManagerId: id,
        activeManagerName: name,
        openShift: open,
        clearOpenShift: open == null,
        failedAttempts: 0,
      );
      debugPrint(
        'Auth: unlocked $id ($name); '
        'openShift=${open == null ? 'none' : open['SHIFT_ID']}',
      );
      return true;
    } catch (error, stack) {
      debugPrint('AuthNotifier.authenticateManager failed: $error\n$stack');
      state = state.copyWith(
        busy: false,
        errorMessage: 'Could not verify PIN. $error',
      );
      return false;
    }
  }

  /// Queries unclosed `OPEN` rows in `shifts`.
  Future<Map<String, dynamic>?> checkOpenShift() async {
    try {
      final List<Map<String, Object?>> rows = await _db.queryOpenShifts();
      if (rows.isEmpty) {
        debugPrint('Auth: no OPEN shift');
        return null;
      }
      final Map<String, dynamic> shift = Map<String, dynamic>.from(rows.first);
      debugPrint(
        'Auth: OPEN shift ${shift['SHIFT_ID']} manager=${shift['MANAGER']}',
      );
      return shift;
    } catch (error, stack) {
      debugPrint('AuthNotifier.checkOpenShift failed: $error\n$stack');
      return null;
    }
  }

  Future<void> signOut() async {
    debugPrint('Auth: signed out ${state.activeManagerId}');
    state = state.copyWith(
      busy: false,
      loading: false,
      isAuthenticated: false,
      clearActiveManager: true,
      clearOpenShift: true,
      clearError: true,
      failedAttempts: 0,
      isOwnerElevated: false,
    );
  }

  void setOwnerElevated(bool elevated) {
    state = state.copyWith(isOwnerElevated: elevated);
  }

  void lockOwnerAccess() {
    setOwnerElevated(false);
  }

  Future<void> _establishDebugSession() async {
    try {
      debugPrint(
        'Auth: debug bypass (enableLoginInDebug=$enableLoginInDebug) — '
        'skipping PIN',
      );
      await loadManagers();
      final Map<String, dynamic>? open = await checkOpenShift();
      final String openId = '${open?['MANAGER'] ?? ''}'.trim();
      AuthManager? chosen;
      if (openId.isNotEmpty) {
        for (final AuthManager manager in state.managers) {
          if (manager.id == openId) {
            chosen = manager;
            break;
          }
        }
      }
      chosen ??= state.managers.isEmpty ? null : state.managers.first;
      chosen ??= const AuthManager(id: 'mgr-dev', name: 'Debug Manager');

      state = state.copyWith(
        loading: false,
        busy: false,
        isAuthenticated: true,
        selectedManagerId: chosen.id,
        activeManagerId: chosen.id,
        activeManagerName: chosen.name,
        openShift: open,
        clearOpenShift: open == null,
      );
      debugPrint('Auth: debug session as ${chosen.id} (${chosen.name})');
    } catch (error, stack) {
      debugPrint('AuthNotifier._establishDebugSession failed: $error\n$stack');
      state = state.copyWith(
        loading: false,
        isAuthenticated: true,
        activeManagerId: 'mgr-dev',
        activeManagerName: 'Debug Manager',
        selectedManagerId: 'mgr-dev',
      );
    }
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

/// Startup route after SharedPreferences onboarding check.
String resolveLaunchRoute({required bool onboarded}) {
  if (!onboarded) {
    return '/onboarding';
  }
  if (shouldBypassLogin) {
    debugPrint('FuelPoint: kDebugMode bypass → /sale');
    return '/sale';
  }
  return '/login';
}
