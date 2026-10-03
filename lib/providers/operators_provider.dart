import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/pin_hasher.dart';
import '../features/shift/domain/shift_models.dart';
import '../features/shift/presentation/shift_providers.dart';
import '../services/database_helper.dart';

@immutable
class StationOperator {
  const StationOperator({
    required this.id,
    required this.name,
    required this.pinStored,
    this.openShiftId,
    this.fingerprintEnrolled = false,
  });

  final String id;
  final String name;
  final String pinStored;
  final int? openShiftId;
  final bool fingerprintEnrolled;

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

  StationOperator copyWith({
    String? name,
    String? pinStored,
    int? openShiftId,
    bool clearOpenShift = false,
    bool? fingerprintEnrolled,
  }) {
    return StationOperator(
      id: id,
      name: name ?? this.name,
      pinStored: pinStored ?? this.pinStored,
      openShiftId: clearOpenShift ? null : (openShiftId ?? this.openShiftId),
      fingerprintEnrolled: fingerprintEnrolled ?? this.fingerprintEnrolled,
    );
  }

  static StationOperator fromRow(Map<String, Object?> row) {
    final Object? open = row['open_shift_id'];
    int? shiftId;
    if (open is int) {
      shiftId = open;
    } else if (open is num) {
      shiftId = open.round();
    } else if (open != null) {
      shiftId = int.tryParse('$open');
    }
    return StationOperator(
      id: '${row['manager_ID'] ?? ''}'.trim(),
      name: (row['Manager_name'] as String?)?.trim() ?? '',
      pinStored: (row['pin'] as String?)?.trim() ?? '',
      openShiftId: (shiftId != null && shiftId > 0) ? shiftId : null,
      fingerprintEnrolled: _fingerprintFlag(row['fingerprint_enrolled']),
    );
  }

  static bool _fingerprintFlag(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    final String text = '${value ?? ''}'.trim().toLowerCase();
    return text == '1' || text == 'true';
  }
}

enum OperatorMutationOutcome {
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
class OperatorMutationResult {
  const OperatorMutationResult({
    required this.outcome,
    this.message = '',
    this.operatorName = '',
    this.shiftId,
  });

  final OperatorMutationOutcome outcome;
  final String message;
  final String operatorName;
  final int? shiftId;

  bool get isSuccess =>
      outcome == OperatorMutationOutcome.created ||
      outcome == OperatorMutationOutcome.updated ||
      outcome == OperatorMutationOutcome.deleted;

  bool get isOpenShiftBlock =>
      outcome == OperatorMutationOutcome.openShiftBlocked;
}

@immutable
class OperatorsState {
  const OperatorsState({
    required this.operators,
    this.search = '',
    this.selectedId,
    this.nextId = 'mgr-1',
    this.loading = true,
    this.busy = false,
    this.errorMessage,
  });

  final List<StationOperator> operators;
  final String search;
  final String? selectedId;
  final String nextId;
  final bool loading;
  final bool busy;
  final String? errorMessage;

  bool get isCreateMode => selectedId == null;

  StationOperator? get selected {
    final String? id = selectedId;
    if (id == null) {
      return null;
    }
    for (final StationOperator operator in operators) {
      if (operator.id == id) {
        return operator;
      }
    }
    return null;
  }

  List<StationOperator> get filtered {
    final String query = search.trim().toLowerCase();
    if (query.isEmpty) {
      return operators;
    }
    return operators.where((StationOperator operator) {
      return operator.name.toLowerCase().contains(query) ||
          operator.id.toLowerCase().contains(query);
    }).toList();
  }

  int get onShiftCount {
    int count = 0;
    for (final StationOperator operator in operators) {
      if (operator.hasOpenShift) {
        count += 1;
      }
    }
    return count;
  }

  int get idleCount => operators.length - onShiftCount;

  OperatorsState copyWith({
    List<StationOperator>? operators,
    String? search,
    String? selectedId,
    bool clearSelected = false,
    String? nextId,
    bool? loading,
    bool? busy,
    String? errorMessage,
    bool clearError = false,
  }) {
    return OperatorsState(
      operators: operators ?? this.operators,
      search: search ?? this.search,
      selectedId: clearSelected ? null : (selectedId ?? this.selectedId),
      nextId: nextId ?? this.nextId,
      loading: loading ?? this.loading,
      busy: busy ?? this.busy,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  static OperatorsState empty() {
    return const OperatorsState(operators: <StationOperator>[]);
  }
}

class OperatorsNotifier extends Notifier<OperatorsState> {
  final DatabaseHelper _db = DatabaseHelper.instance;

  @override
  OperatorsState build() {
    Future<void>.microtask(reload);
    return OperatorsState.empty();
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
    final bool initial = state.operators.isEmpty;
    if (initial) {
      state = state.copyWith(loading: true, clearError: true);
    }
    try {
      final List<Map<String, Object?>> rows = await _db
          .queryOperatorsWithOpenShifts();
      final List<StationOperator> operators = rows
          .map(StationOperator.fromRow)
          .where((StationOperator row) => row.id.isNotEmpty)
          .toList();
      final String nextId = await _db.nextOperatorId();
      String? selectedId = state.selectedId;
      if (selectedId != null) {
        final bool stillExists = operators.any(
          (StationOperator row) => row.id == selectedId,
        );
        if (!stillExists) {
          selectedId = null;
        }
      }
      state = state.copyWith(
        operators: operators,
        nextId: nextId,
        selectedId: selectedId,
        clearSelected: selectedId == null,
        loading: false,
        busy: false,
      );
    } catch (error, stack) {
      debugPrint('OperatorsNotifier.reload failed: $error\n$stack');
      state = state.copyWith(
        loading: false,
        busy: false,
        errorMessage: 'Could not load operators. $error',
      );
    }
  }

  Future<OperatorMutationResult> save({
    required String operatorId,
    required String operatorName,
    required String pin,
  }) async {
    final String id = operatorId.trim();
    final String name = operatorName.trim();
    final String resolvedPin = pin.trim();
    if (id.isEmpty) {
      return const OperatorMutationResult(
        outcome: OperatorMutationOutcome.invalidId,
        message: 'Operator ID is required.',
      );
    }
    if (name.isEmpty) {
      return const OperatorMutationResult(
        outcome: OperatorMutationOutcome.invalidName,
        message: 'Operator name is required.',
      );
    }

    final bool creating = state.isCreateMode;
    if (creating) {
      if (!PinHasher.isValidPlainPin(resolvedPin)) {
        return const OperatorMutationResult(
          outcome: OperatorMutationOutcome.invalidPin,
          message: 'PIN must be 4–6 digits.',
        );
      }
      final Map<String, Object?>? existing = await _db.queryOperatorById(id);
      if (existing != null) {
        return OperatorMutationResult(
          outcome: OperatorMutationOutcome.duplicateId,
          message: 'Operator ID $id already exists.',
        );
      }
    } else if (resolvedPin.isNotEmpty &&
        !PinHasher.isValidPlainPin(resolvedPin)) {
      return const OperatorMutationResult(
        outcome: OperatorMutationOutcome.invalidPin,
        message:
            'PIN must be 4–6 digits, or leave blank to keep the current PIN.',
      );
    }

    state = state.copyWith(busy: true, clearError: true);
    try {
      if (creating) {
        await _db.upsertOperator(
          operatorId: id,
          operatorName: name,
          pin: resolvedPin,
        );
      } else {
        await _db.updateOperator(
          operatorId: id,
          operatorName: name,
          pin: resolvedPin.isEmpty ? null : resolvedPin,
        );
      }
      await _syncDownstream();
      state = state.copyWith(busy: false, selectedId: id);
      return OperatorMutationResult(
        outcome: creating
            ? OperatorMutationOutcome.created
            : OperatorMutationOutcome.updated,
        operatorName: name,
      );
    } catch (error, stack) {
      debugPrint('OperatorsNotifier.save failed: $error\n$stack');
      state = state.copyWith(busy: false, errorMessage: '$error');
      return OperatorMutationResult(
        outcome: OperatorMutationOutcome.failed,
        message: '$error',
      );
    }
  }

  /// Blocks deletion (and inactivation) while the operator holds an OPEN shift.
  Future<OperatorMutationResult> delete(String operatorId) async {
    final String id = operatorId.trim();
    StationOperator? profile;
    for (final StationOperator operator in state.operators) {
      if (operator.id == id) {
        profile = operator;
        break;
      }
    }
    if (profile == null) {
      return const OperatorMutationResult(
        outcome: OperatorMutationOutcome.notFound,
        message: 'Operator was not found.',
      );
    }
    if (profile.hasOpenShift) {
      return OperatorMutationResult(
        outcome: OperatorMutationOutcome.openShiftBlocked,
        operatorName: profile.name,
        shiftId: profile.openShiftId,
        message:
            '${profile.name} currently holds Shift #${profile.openShiftId}. '
            'Close that OPEN shift before removing or inactivating this operator.',
      );
    }

    state = state.copyWith(busy: true, clearError: true);
    try {
      await _db.deleteOperator(id);
      await _syncDownstream();
      state = state.copyWith(busy: false, clearSelected: true);
      return OperatorMutationResult(
        outcome: OperatorMutationOutcome.deleted,
        operatorName: profile.name,
      );
    } on OperatorHasOpenShiftException catch (error) {
      state = state.copyWith(busy: false);
      return OperatorMutationResult(
        outcome: OperatorMutationOutcome.openShiftBlocked,
        operatorName: error.operatorName,
        shiftId: error.shiftId,
        message: error.toString(),
      );
    } on OperatorInUseException catch (error) {
      state = state.copyWith(busy: false);
      return OperatorMutationResult(
        outcome: OperatorMutationOutcome.inUse,
        message: error.toString(),
      );
    } catch (error, stack) {
      debugPrint('OperatorsNotifier.delete failed: $error\n$stack');
      state = state.copyWith(busy: false, errorMessage: '$error');
      return OperatorMutationResult(
        outcome: OperatorMutationOutcome.failed,
        message: '$error',
      );
    }
  }

  Future<void> _syncDownstream() async {
    await reload();
    try {
      await ref.read(shiftWorkspaceProvider.notifier).reload();
    } catch (error, stack) {
      debugPrint('OperatorsNotifier shift reload failed: $error\n$stack');
    }
  }
}

final operatorsProvider = NotifierProvider<OperatorsNotifier, OperatorsState>(
  OperatorsNotifier.new,
);
