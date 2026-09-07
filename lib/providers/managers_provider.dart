import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/pin_hasher.dart';
import '../features/shift/domain/shift_models.dart';
import '../features/shift/presentation/shift_providers.dart';
import '../services/database_helper.dart';

@immutable
class StationManager {
  const StationManager({
    required this.id,
    required this.name,
    required this.pinStored,
    this.openShiftId,
  });

  final String id;
  final String name;
  final String pinStored;
  final int? openShiftId;

  bool get hasOpenShift {
    final int? shiftId = openShiftId;
    return shiftId != null && shiftId > 0;
  }

  String get initials => initialsFromName(name);

  String get maskedPin => '••••';

  String get statusLabel {
    final int? shiftId = openShiftId;
    if (shiftId == null || shiftId <= 0) {
      return 'Idle';
    }
    return 'Shift #$shiftId Active';
  }

  StationManager copyWith({
    String? name,
    String? pinStored,
    int? openShiftId,
    bool clearOpenShift = false,
  }) {
    return StationManager(
      id: id,
      name: name ?? this.name,
      pinStored: pinStored ?? this.pinStored,
      openShiftId: clearOpenShift ? null : (openShiftId ?? this.openShiftId),
    );
  }

  static StationManager fromRow(Map<String, Object?> row) {
    final Object? open = row['open_shift_id'];
    int? shiftId;
    if (open is int) {
      shiftId = open;
    } else if (open is num) {
      shiftId = open.round();
    } else if (open != null) {
      shiftId = int.tryParse('$open');
    }
    return StationManager(
      id: '${row['manager_ID'] ?? ''}'.trim(),
      name: (row['Manager_name'] as String?)?.trim() ?? '',
      pinStored: (row['pin'] as String?)?.trim() ?? '',
      openShiftId: (shiftId != null && shiftId > 0) ? shiftId : null,
    );
  }
}

enum ManagerMutationOutcome {
  created,
  updated,
  deleted,
  duplicateId,
  invalidId,
  invalidName,
  invalidPin,
  openShiftBlocked,
  inUse,
  notFound,
  failed,
}

@immutable
class ManagerMutationResult {
  const ManagerMutationResult({
    required this.outcome,
    this.message = '',
    this.managerName = '',
    this.shiftId,
  });

  final ManagerMutationOutcome outcome;
  final String message;
  final String managerName;
  final int? shiftId;

  bool get isSuccess =>
      outcome == ManagerMutationOutcome.created ||
      outcome == ManagerMutationOutcome.updated ||
      outcome == ManagerMutationOutcome.deleted;

  bool get isOpenShiftBlock =>
      outcome == ManagerMutationOutcome.openShiftBlocked;
}

@immutable
class ManagersState {
  const ManagersState({
    required this.managers,
    this.search = '',
    this.selectedId,
    this.nextId = 'mgr-1',
    this.loading = true,
    this.busy = false,
    this.errorMessage,
  });

  final List<StationManager> managers;
  final String search;
  final String? selectedId;
  final String nextId;
  final bool loading;
  final bool busy;
  final String? errorMessage;

  bool get isCreateMode => selectedId == null;

  StationManager? get selected {
    final String? id = selectedId;
    if (id == null) {
      return null;
    }
    for (final StationManager manager in managers) {
      if (manager.id == id) {
        return manager;
      }
    }
    return null;
  }

  List<StationManager> get filtered {
    final String query = search.trim().toLowerCase();
    if (query.isEmpty) {
      return managers;
    }
    return managers.where((StationManager manager) {
      return manager.name.toLowerCase().contains(query) ||
          manager.id.toLowerCase().contains(query);
    }).toList();
  }

  int get onShiftCount {
    int count = 0;
    for (final StationManager manager in managers) {
      if (manager.hasOpenShift) {
        count += 1;
      }
    }
    return count;
  }

  int get idleCount => managers.length - onShiftCount;

  ManagersState copyWith({
    List<StationManager>? managers,
    String? search,
    String? selectedId,
    bool clearSelected = false,
    String? nextId,
    bool? loading,
    bool? busy,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ManagersState(
      managers: managers ?? this.managers,
      search: search ?? this.search,
      selectedId: clearSelected ? null : (selectedId ?? this.selectedId),
      nextId: nextId ?? this.nextId,
      loading: loading ?? this.loading,
      busy: busy ?? this.busy,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  static ManagersState empty() {
    return const ManagersState(managers: <StationManager>[]);
  }
}

class ManagersNotifier extends Notifier<ManagersState> {
  final DatabaseHelper _db = DatabaseHelper.instance;

  @override
  ManagersState build() {
    Future<void>.microtask(reload);
    return ManagersState.empty();
  }

  void setSearch(String value) {
    state = state.copyWith(search: value);
  }

  void select(String id) {
    state = state.copyWith(selectedId: id, clearError: true);
  }

  void startCreate() {
    state = state.copyWith(clearSelected: true, clearError: true);
  }

  Future<void> reload() async {
    final bool initial = state.managers.isEmpty;
    if (initial) {
      state = state.copyWith(loading: true, clearError: true);
    }
    try {
      final List<Map<String, Object?>> rows = await _db
          .queryManagersWithOpenShifts();
      final List<StationManager> managers = rows
          .map(StationManager.fromRow)
          .where((StationManager row) => row.id.isNotEmpty)
          .toList();
      final String nextId = await _db.nextManagerId();
      String? selectedId = state.selectedId;
      if (selectedId != null) {
        final bool stillExists = managers.any(
          (StationManager row) => row.id == selectedId,
        );
        if (!stillExists) {
          selectedId = null;
        }
      }
      state = state.copyWith(
        managers: managers,
        nextId: nextId,
        selectedId: selectedId,
        clearSelected: selectedId == null,
        loading: false,
        busy: false,
      );
    } catch (error, stack) {
      debugPrint('ManagersNotifier.reload failed: $error\n$stack');
      state = state.copyWith(
        loading: false,
        busy: false,
        errorMessage: 'Could not load managers. $error',
      );
    }
  }

  Future<ManagerMutationResult> save({
    required String managerId,
    required String managerName,
    required String pin,
  }) async {
    final String id = managerId.trim();
    final String name = managerName.trim();
    final String resolvedPin = pin.trim();
    if (id.isEmpty) {
      return const ManagerMutationResult(
        outcome: ManagerMutationOutcome.invalidId,
        message: 'Manager ID is required.',
      );
    }
    if (name.isEmpty) {
      return const ManagerMutationResult(
        outcome: ManagerMutationOutcome.invalidName,
        message: 'Manager name is required.',
      );
    }

    final bool creating = state.isCreateMode;
    if (creating) {
      if (!PinHasher.isValidPlainPin(resolvedPin)) {
        return const ManagerMutationResult(
          outcome: ManagerMutationOutcome.invalidPin,
          message: 'PIN must be 4–6 digits.',
        );
      }
      final Map<String, Object?>? existing = await _db.queryManagerById(id);
      if (existing != null) {
        return ManagerMutationResult(
          outcome: ManagerMutationOutcome.duplicateId,
          message: 'Manager ID $id already exists.',
        );
      }
    } else if (resolvedPin.isNotEmpty &&
        !PinHasher.isValidPlainPin(resolvedPin)) {
      return const ManagerMutationResult(
        outcome: ManagerMutationOutcome.invalidPin,
        message:
            'PIN must be 4–6 digits, or leave blank to keep the current PIN.',
      );
    }

    state = state.copyWith(busy: true, clearError: true);
    try {
      if (creating) {
        await _db.upsertManager(
          managerId: id,
          managerName: name,
          pin: resolvedPin,
        );
      } else {
        await _db.updateManager(
          managerId: id,
          managerName: name,
          pin: resolvedPin.isEmpty ? null : resolvedPin,
        );
      }
      await _syncDownstream();
      state = state.copyWith(busy: false, selectedId: id);
      return ManagerMutationResult(
        outcome: creating
            ? ManagerMutationOutcome.created
            : ManagerMutationOutcome.updated,
        managerName: name,
      );
    } catch (error, stack) {
      debugPrint('ManagersNotifier.save failed: $error\n$stack');
      state = state.copyWith(busy: false, errorMessage: '$error');
      return ManagerMutationResult(
        outcome: ManagerMutationOutcome.failed,
        message: '$error',
      );
    }
  }

  /// Blocks deletion (and inactivation) while the manager holds an OPEN shift.
  Future<ManagerMutationResult> delete(String managerId) async {
    final String id = managerId.trim();
    StationManager? profile;
    for (final StationManager manager in state.managers) {
      if (manager.id == id) {
        profile = manager;
        break;
      }
    }
    if (profile == null) {
      return const ManagerMutationResult(
        outcome: ManagerMutationOutcome.notFound,
        message: 'Manager was not found.',
      );
    }
    if (profile.hasOpenShift) {
      return ManagerMutationResult(
        outcome: ManagerMutationOutcome.openShiftBlocked,
        managerName: profile.name,
        shiftId: profile.openShiftId,
        message:
            '${profile.name} currently holds Shift #${profile.openShiftId}. '
            'Close that OPEN shift before removing or inactivating this manager.',
      );
    }

    state = state.copyWith(busy: true, clearError: true);
    try {
      await _db.deleteManager(id);
      await _syncDownstream();
      state = state.copyWith(busy: false, clearSelected: true);
      return ManagerMutationResult(
        outcome: ManagerMutationOutcome.deleted,
        managerName: profile.name,
      );
    } on ManagerHasOpenShiftException catch (error) {
      state = state.copyWith(busy: false);
      return ManagerMutationResult(
        outcome: ManagerMutationOutcome.openShiftBlocked,
        managerName: error.managerName,
        shiftId: error.shiftId,
        message: error.toString(),
      );
    } on ManagerInUseException catch (error) {
      state = state.copyWith(busy: false);
      return ManagerMutationResult(
        outcome: ManagerMutationOutcome.inUse,
        message: error.toString(),
      );
    } catch (error, stack) {
      debugPrint('ManagersNotifier.delete failed: $error\n$stack');
      state = state.copyWith(busy: false, errorMessage: '$error');
      return ManagerMutationResult(
        outcome: ManagerMutationOutcome.failed,
        message: '$error',
      );
    }
  }

  Future<void> _syncDownstream() async {
    await reload();
    try {
      await ref.read(shiftWorkspaceProvider.notifier).reload();
    } catch (error, stack) {
      debugPrint('ManagersNotifier shift reload failed: $error\n$stack');
    }
  }
}

final managersProvider = NotifierProvider<ManagersNotifier, ManagersState>(
  ManagersNotifier.new,
);
