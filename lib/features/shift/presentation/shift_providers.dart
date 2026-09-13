import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/settings_provider.dart';
import '../../../services/database_helper.dart';
import '../../access/domain/access_policy.dart';
import '../../station/domain/dispenser_models.dart';
import '../data/sqlite_shift_repository.dart';
import '../domain/shift_lifecycle.dart';
import '../domain/shift_models.dart';

@immutable
class ShiftWorkspaceState {
  const ShiftWorkspaceState({
    required this.managers,
    required this.helpers,
    required this.closedShifts,
    required this.sales,
    required this.dutySessions,
    required this.tab,
    required this.tallyPane,
    required this.helperPreset,
    this.activeShift,
    this.pendingReconciliation,
    this.selectedHelperId,
    this.customRange,
    this.globalHelperRewardPerTx = kDefaultHelperRewardPerTx,
    this.nextManagerSeq = 1,
    this.nextHelperSeq = 1,
    this.nextShiftSeq = 1,
    this.nextDutySeq = 1,
    this.udhaarRecoveryTotal = 0,
    this.sessionVerified = true,
    this.uncleanExitAt,
  });

  final List<ManagerProfile> managers;
  final List<HelperProfile> helpers;
  final ManagerShiftRecord? activeShift;
  final ReconciliationSnapshot? pendingReconciliation;
  final List<ManagerShiftRecord> closedShifts;
  final List<HelperSaleRecord> sales;
  final List<HelperDutySession> dutySessions;
  final ShiftWorkspaceTab tab;
  final ManagerTallyPane tallyPane;
  final String? selectedHelperId;
  final HelperRangePreset helperPreset;
  final DateTimeRange? customRange;
  final double globalHelperRewardPerTx;
  final int nextManagerSeq;
  final int nextHelperSeq;
  final int nextShiftSeq;
  final int nextDutySeq;
  final double udhaarRecoveryTotal;
  final bool sessionVerified;
  final DateTime? uncleanExitAt;

  HelperProfile? get selectedHelper => helperById(helpers, selectedHelperId);

  List<HelperProfile> get assignableHelpers {
    return helpers.where((HelperProfile helper) => helper.isActive).toList();
  }

  DateTimeRange get helperRange {
    if (helperPreset == HelperRangePreset.custom && customRange != null) {
      return customRange!;
    }
    return rangeForPreset(helperPreset);
  }

  ShiftWindowMetrics get activeMetrics {
    final ManagerShiftRecord? open = activeShift;
    if (open == null) {
      return ShiftWindowMetrics.empty;
    }
    return metricsForSales(
      salesForOutgoingManager(sales, open),
      udhaarRecoveryTotal: udhaarRecoveryTotal,
    );
  }

  List<ManagerProfile> get incomingHandoverCandidates {
    final String? outgoingId = activeShift?.managerId;
    return managers
        .where((ManagerProfile manager) => manager.id != outgoingId)
        .toList();
  }

  bool get canEndShift => activeShift != null && pendingReconciliation == null;

  /// OPEN shift or unfinished tally — blocks native window close.
  bool get hasActiveShift {
    return (activeShift != null && activeShift!.isOpen) ||
        pendingReconciliation != null;
  }

  bool get isUnverifiedSession {
    return activeShift != null && activeShift!.isOpen && !sessionVerified;
  }

  bool get needsCrashRecovery => isUnverifiedSession;

  List<ManagerShiftRecord> get knownShifts {
    return <ManagerShiftRecord>[
      if (activeShift != null) activeShift!,
      if (pendingReconciliation != null) pendingReconciliation!.shift,
      ...closedShifts,
    ];
  }

  ShiftWorkspaceState copyWith({
    List<ManagerProfile>? managers,
    List<HelperProfile>? helpers,
    ManagerShiftRecord? activeShift,
    bool clearActiveShift = false,
    ReconciliationSnapshot? pendingReconciliation,
    bool clearPendingReconciliation = false,
    List<ManagerShiftRecord>? closedShifts,
    List<HelperSaleRecord>? sales,
    List<HelperDutySession>? dutySessions,
    ShiftWorkspaceTab? tab,
    ManagerTallyPane? tallyPane,
    String? selectedHelperId,
    bool clearSelectedHelper = false,
    HelperRangePreset? helperPreset,
    DateTimeRange? customRange,
    bool clearCustomRange = false,
    double? globalHelperRewardPerTx,
    int? nextManagerSeq,
    int? nextHelperSeq,
    int? nextShiftSeq,
    int? nextDutySeq,
    double? udhaarRecoveryTotal,
    bool? sessionVerified,
    DateTime? uncleanExitAt,
    bool clearUncleanExitAt = false,
  }) {
    return ShiftWorkspaceState(
      managers: managers ?? this.managers,
      helpers: helpers ?? this.helpers,
      activeShift: clearActiveShift ? null : (activeShift ?? this.activeShift),
      pendingReconciliation: clearPendingReconciliation
          ? null
          : (pendingReconciliation ?? this.pendingReconciliation),
      closedShifts: closedShifts ?? this.closedShifts,
      sales: sales ?? this.sales,
      dutySessions: dutySessions ?? this.dutySessions,
      tab: tab ?? this.tab,
      tallyPane: tallyPane ?? this.tallyPane,
      selectedHelperId: clearSelectedHelper
          ? null
          : (selectedHelperId ?? this.selectedHelperId),
      helperPreset: helperPreset ?? this.helperPreset,
      customRange: clearCustomRange ? null : (customRange ?? this.customRange),
      globalHelperRewardPerTx:
          globalHelperRewardPerTx ?? this.globalHelperRewardPerTx,
      nextManagerSeq: nextManagerSeq ?? this.nextManagerSeq,
      nextHelperSeq: nextHelperSeq ?? this.nextHelperSeq,
      nextShiftSeq: nextShiftSeq ?? this.nextShiftSeq,
      nextDutySeq: nextDutySeq ?? this.nextDutySeq,
      udhaarRecoveryTotal: udhaarRecoveryTotal ?? this.udhaarRecoveryTotal,
      sessionVerified: sessionVerified ?? this.sessionVerified,
      uncleanExitAt: clearUncleanExitAt
          ? null
          : (uncleanExitAt ?? this.uncleanExitAt),
    );
  }

  static ShiftWorkspaceState empty() {
    return const ShiftWorkspaceState(
      managers: <ManagerProfile>[],
      helpers: <HelperProfile>[],
      closedShifts: <ManagerShiftRecord>[],
      sales: <HelperSaleRecord>[],
      dutySessions: <HelperDutySession>[],
      tab: ShiftWorkspaceTab.managers,
      tallyPane: ManagerTallyPane.todaySales,
      helperPreset: HelperRangePreset.today,
    );
  }
}

class ShiftWorkspaceNotifier extends Notifier<ShiftWorkspaceState> {
  final SqliteShiftRepository _repo = SqliteShiftRepository();
  Future<void>? _hydrateFuture;
  bool _alive = true;
  Timer? _sessionHeartbeat;

  @override
  ShiftWorkspaceState build() {
    _alive = true;
    ref.onDispose(() {
      _alive = false;
      _sessionHeartbeat?.cancel();
      _sessionHeartbeat = null;
    });
    _hydrateFuture = _hydrate();
    return ShiftWorkspaceState.empty();
  }

  Future<void> ensureReady() => _ensureHydrated();

  Future<void> _ensureHydrated() async {
    await (_hydrateFuture ??= _hydrate());
  }

  Future<void> _hydrate() async {
    try {
      final ShiftStoreSnapshot snapshot = await _repo.load();
      if (!_alive) {
        return;
      }
      ManagerShiftRecord? live;
      for (final ManagerShiftRecord shift in snapshot.shifts) {
        if (shift.isOpen) {
          live = shift;
          break;
        }
      }
      final AppSessionSnapshot session = await _loadBootSession(live);
      if (!_alive) {
        return;
      }
      state = _stateFromStore(snapshot, preserve: state, session: session);
      await _refreshExpectedCashComponents();
      _syncSessionHeartbeat();
    } catch (error, stack) {
      debugPrint('ShiftWorkspaceNotifier.hydrate failed: $error\n$stack');
    }
  }

  Future<AppSessionSnapshot> _loadBootSession(ManagerShiftRecord? live) async {
    if (live == null || !live.isOpen) {
      return DatabaseHelper.instance.readAppSessionState();
    }
    final AppSessionSnapshot session = await DatabaseHelper.instance
        .readAppSessionState();
    if (session.isCleanShutdown) {
      return session;
    }
    return DatabaseHelper.instance.captureUncleanExitIfNeeded();
  }

  void _syncSessionHeartbeat() {
    _sessionHeartbeat?.cancel();
    _sessionHeartbeat = null;
    final bool live =
        state.activeShift != null &&
        state.activeShift!.isOpen &&
        state.sessionVerified;
    if (!live) {
      return;
    }
    unawaited(DatabaseHelper.instance.markRuntimeUnclean());
    _sessionHeartbeat = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(DatabaseHelper.instance.touchSessionHeartbeat());
    });
  }

  Future<void> reload() async {
    _hydrateFuture = _hydrate();
    await _hydrateFuture;
  }

  ShiftWorkspaceState _stateFromStore(
    ShiftStoreSnapshot snapshot, {
    required ShiftWorkspaceState preserve,
    required AppSessionSnapshot session,
  }) {
    ManagerShiftRecord? open;
    ManagerShiftRecord? pending;
    final List<ManagerShiftRecord> closed = <ManagerShiftRecord>[];
    for (final ManagerShiftRecord shift in snapshot.shifts) {
      switch (shift.status) {
        case ManagerShiftStatus.open:
          open ??= shift;
        case ManagerShiftStatus.pendingReconciliation:
          pending ??= shift;
        case ManagerShiftStatus.closed:
        case ManagerShiftStatus.forceClosed:
          closed.add(shift);
      }
    }

    final List<HelperProfile> helpers = snapshot.helpers.map((
      HelperProfile helper,
    ) {
      final HelperProfile? existing = helperById(preserve.helpers, helper.id);
      if (existing == null) {
        return helper;
      }
      return helper.copyWith(assignedUnitIds: existing.assignedUnitIds);
    }).toList();

    ReconciliationSnapshot? pendingSnapshot;
    if (pending != null) {
      pendingSnapshot = ReconciliationSnapshot(
        shift: pending,
        metrics: SqliteShiftRepository.metricsForShift(snapshot.sales, pending),
      );
    }

    String? selectedHelperId = _resolvedSelectedHelperId(
      helpers,
      preserve.selectedHelperId,
    );

    return preserve.copyWith(
      managers: snapshot.managers.map((ManagerProfile manager) {
        return manager.copyWith(
          status: manager.id == open?.managerId
              ? ManagerProfileStatus.active
              : ManagerProfileStatus.inactive,
        );
      }).toList(),
      helpers: helpers,
      activeShift: open,
      clearActiveShift: open == null,
      pendingReconciliation: pendingSnapshot,
      clearPendingReconciliation: pendingSnapshot == null,
      closedShifts: closed,
      sales: snapshot.sales,
      selectedHelperId: selectedHelperId,
      clearSelectedHelper: selectedHelperId == null,
      nextManagerSeq: _nextIdSeq(
        snapshot.managers.map((ManagerProfile row) => row.id),
        'mgr-',
      ),
      nextHelperSeq: _nextIdSeq(
        snapshot.helpers.map((HelperProfile row) => row.id),
        'hlp-',
      ),
      sessionVerified:
          !shouldEnforceStationGuards ||
          open == null ||
          session.isCleanShutdown,
      uncleanExitAt: open != null && !session.isCleanShutdown
          ? session.uncleanExitAt
          : null,
      clearUncleanExitAt: open == null || session.isCleanShutdown,
    );
  }

  void setTab(ShiftWorkspaceTab tab) {
    if (state.tab == tab) {
      return;
    }
    state = state.copyWith(tab: tab);
  }

  void setTallyPane(ManagerTallyPane pane) {
    if (state.tallyPane == pane) {
      return;
    }
    state = state.copyWith(tallyPane: pane);
  }

  void selectHelper(String? helperId) {
    if (state.selectedHelperId == helperId) {
      return;
    }
    state = state.copyWith(
      selectedHelperId: helperId,
      clearSelectedHelper: helperId == null,
    );
  }

  Future<void> addHelper({required String name}) async {
    await _ensureHydrated();
    final String trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final int seq = state.nextHelperSeq;
    final HelperProfile profile = await _repo.insertHelper(
      id: 'hlp-$seq',
      name: trimmed,
    );
    state = state.copyWith(
      helpers: <HelperProfile>[...state.helpers, profile],
      nextHelperSeq: seq + 1,
      selectedHelperId: profile.id,
    );
  }

  /// Replaces duty on every bay. Null / empty helper ids leave that unit idle.
  void applyUnitAssignments(Map<int, String?> unitHelperIds) {
    for (final int unitId in dispenserUnitIds) {
      final String? raw = unitHelperIds[unitId];
      final String? helperId = (raw == null || raw.isEmpty) ? null : raw;
      assignHelperToUnit(unitId: unitId, helperId: helperId);
    }
  }

  void unassignAllHelpers() {
    applyUnitAssignments(<int, String?>{
      for (final int unitId in dispenserUnitIds) unitId: null,
    });
  }

  /// One helper per bay. A helper may cover multiple bays.
  /// Passing a null [helperId] clears only this unit.
  void assignHelperToUnit({required int unitId, String? helperId}) {
    final DateTime now = DateTime.now();
    final List<HelperDutySession> sessions = state.dutySessions.map((
      HelperDutySession session,
    ) {
      if (!session.isOpen) {
        return session;
      }
      if (session.unitId == unitId) {
        return session.copyWith(endTime: now);
      }
      return session;
    }).toList();

    int seq = state.nextDutySeq;
    if (helperId != null) {
      final HelperProfile? profile = helperById(state.helpers, helperId);
      if (profile != null) {
        sessions.add(
          HelperDutySession(
            id: 'duty-$seq',
            helperId: profile.id,
            helperName: profile.name,
            unitId: unitId,
            startTime: now,
          ),
        );
        seq += 1;
      }
    }

    state = state.copyWith(
      helpers: state.helpers.map((HelperProfile helper) {
        if (!helper.isActive) {
          return helper;
        }
        if (helperId != null && helper.id == helperId) {
          return helper.withUnitAdded(unitId);
        }
        return helper.withUnitRemoved(unitId);
      }).toList(),
      dutySessions: sessions,
      nextDutySeq: seq,
    );
  }

  void recordSale(HelperSaleRecord sale) {
    state = state.copyWith(sales: <HelperSaleRecord>[sale, ...state.sales]);
  }

  void addUdhaarRecovery(double amountPaid) {
    if (state.activeShift == null || amountPaid <= 0) {
      return;
    }
    state = state.copyWith(
      udhaarRecoveryTotal: state.udhaarRecoveryTotal + amountPaid,
    );
  }

  void setHelperPreset(HelperRangePreset preset) {
    state = state.copyWith(
      helperPreset: preset,
      clearCustomRange: preset != HelperRangePreset.custom,
    );
  }

  void setCustomRange(DateTimeRange range) {
    state = state.copyWith(
      helperPreset: HelperRangePreset.custom,
      customRange: range,
    );
  }

  void setGlobalHelperRewardPerTx(double rate) {
    if (rate < 0) {
      return;
    }
    state = state.copyWith(globalHelperRewardPerTx: rate);
  }

  Future<void> addManager({
    required String name,
    required ManagerRole role,
    String pin = kDefaultManagerPin,
  }) async {
    await _ensureHydrated();
    final String trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final String resolvedPin = pin.trim().isEmpty
        ? kDefaultManagerPin
        : pin.trim();
    final int seq = state.nextManagerSeq;
    final ManagerProfile profile = await _repo.insertManager(
      id: 'mgr-$seq',
      name: trimmed,
      role: role,
      pin: resolvedPin,
    );
    state = state.copyWith(
      managers: <ManagerProfile>[...state.managers, profile],
      nextManagerSeq: seq + 1,
    );
  }

  /// Only one open manager shift is allowed. Returns why a start was refused.
  Future<StartShiftOutcome> startShift(
    String managerId, {
    required String pin,
    Map<int, String?>? unitAssignments,
    Map<int, double> openingMeters = const <int, double>{},
  }) async {
    await _ensureHydrated();
    final ManagerShiftRecord? open = state.activeShift;
    if (open != null) {
      if (open.managerId == managerId) {
        return StartShiftOutcome.alreadyOnDuty;
      }
      return StartShiftOutcome.blocked;
    }
    ManagerProfile? profile;
    for (final ManagerProfile manager in state.managers) {
      if (manager.id == managerId) {
        profile = manager;
        break;
      }
    }
    if (profile == null) {
      return StartShiftOutcome.blocked;
    }
    final bool pinOk = await DatabaseHelper.instance.verifyManagerPin(
      managerId: managerId,
      pin: pin,
    );
    if (!pinOk) {
      return StartShiftOutcome.invalidPin;
    }
    final ManagerShiftRecord shift = await _repo.insertOpenShift(
      manager: profile,
      startTime: DateTime.now(),
      openingMeters: openingMeters,
    );
    await DatabaseHelper.instance.markRuntimeUnclean();
    await DatabaseHelper.instance.clearUncleanExitStamp();
    state = state.copyWith(
      activeShift: shift,
      managers: _withSingleActive(profile.id),
      udhaarRecoveryTotal: 0,
      sessionVerified: true,
      clearUncleanExitAt: true,
    );
    applyUnitAssignments(
      unitAssignments ?? unitHelperAssignmentsOf(state.helpers),
    );
    _syncSessionHeartbeat();
    return StartShiftOutcome.started;
  }

  Future<ShiftSummary?> closeActiveShift({
    required double actualCash,
    required String notes,
  }) async {
    await _ensureHydrated();
    final ManagerShiftRecord? open = state.activeShift;
    if (open == null) {
      return null;
    }
    final DateTime ended = DateTime.now();
    final ManagerShiftRecord window = open.copyWith(endTime: ended);
    await _refreshExpectedCashComponents();
    final ShiftWindowMetrics metrics = metricsForSales(
      salesForOutgoingManager(state.sales, window),
      udhaarRecoveryTotal: state.udhaarRecoveryTotal,
    );
    final ManagerShiftRecord closed = open.copyWith(
      endTime: ended,
      expectedCash: metrics.expectedCashInHand,
      actualCash: actualCash,
      notes: notes.trim(),
      status: ManagerShiftStatus.closed,
      udhaarRecoveryTotal: state.udhaarRecoveryTotal,
    );
    await _repo.persistShift(closed);
    state = state.copyWith(
      clearActiveShift: true,
      closedShifts: <ManagerShiftRecord>[closed, ...state.closedShifts],
      managers: _withSingleActive(null),
      udhaarRecoveryTotal: 0,
    );
    unawaited(ref.read(settingsProvider.notifier).maybeUploadOnShiftClose());
    _syncSessionHeartbeat();
    return ShiftSummary(shift: closed, metrics: metrics);
  }

  /// Authenticates the incoming manager, freezes Shift N for tally, and opens N+1 LIVE.
  Future<ShiftHandoverResult> beginHandover({
    required String incomingManagerId,
    required String pin,
    Map<int, String?>? unitAssignments,
    int? blockingDispensingBay,
    double? actualCash,
    String notes = '',
    Map<int, double> closingMeters = const <int, double>{},
    Map<int, double> openingMeters = const <int, double>{},
  }) async {
    await _ensureHydrated();
    if (shouldEnforceStationGuards && blockingDispensingBay != null) {
      return ShiftHandoverResult(
        outcome: HandoverOutcome.baysDispensing,
        blockedBayId: blockingDispensingBay,
      );
    }
    if (state.pendingReconciliation != null) {
      return const ShiftHandoverResult(outcome: HandoverOutcome.alreadyPending);
    }
    final ManagerShiftRecord? open = state.activeShift;
    if (open == null) {
      return const ShiftHandoverResult(outcome: HandoverOutcome.noActiveShift);
    }
    if (incomingManagerId == open.managerId) {
      return const ShiftHandoverResult(outcome: HandoverOutcome.sameManager);
    }
    ManagerProfile? incoming;
    for (final ManagerProfile manager in state.managers) {
      if (manager.id == incomingManagerId) {
        incoming = manager;
        break;
      }
    }
    if (incoming == null) {
      return const ShiftHandoverResult(outcome: HandoverOutcome.unknownManager);
    }
    final bool pinOk = await DatabaseHelper.instance.verifyManagerPin(
      managerId: incomingManagerId,
      pin: pin,
    );
    if (!pinOk) {
      return const ShiftHandoverResult(outcome: HandoverOutcome.invalidPin);
    }

    final DateTime handoffAt = DateTime.now();
    final ManagerShiftRecord window = open.copyWith(endTime: handoffAt);
    await _refreshExpectedCashComponents();
    final ShiftWindowMetrics frozenMetrics = metricsForSales(
      List<HelperSaleRecord>.from(salesForOutgoingManager(state.sales, window)),
      udhaarRecoveryTotal: state.udhaarRecoveryTotal,
    );
    final ManagerShiftRecord outgoing = open.copyWith(
      endTime: handoffAt,
      expectedCash: frozenMetrics.expectedCashInHand,
      actualCash: actualCash,
      notes: notes.trim(),
      status: ManagerShiftStatus.pendingReconciliation,
      udhaarRecoveryTotal: state.udhaarRecoveryTotal,
      closingMeters: closingMeters,
    );
    final ({ManagerShiftRecord pending, ManagerShiftRecord opened}) swapped =
        await _repo.handoverWithPendingTally(
          outgoing: outgoing,
          incoming: incoming,
          handoffAt: handoffAt,
          closingMeters: closingMeters,
          openingMeters: openingMeters,
        );
    final ReconciliationSnapshot pendingSnap = ReconciliationSnapshot(
      shift: swapped.pending,
      metrics: frozenMetrics,
    );
    state = state.copyWith(
      activeShift: swapped.opened,
      pendingReconciliation: pendingSnap,
      managers: _withSingleActive(incoming.id),
      udhaarRecoveryTotal: 0,
      sessionVerified: true,
      clearUncleanExitAt: true,
    );
    applyUnitAssignments(
      unitAssignments ?? unitHelperAssignmentsOf(state.helpers),
    );
    unawaited(ref.read(settingsProvider.notifier).maybeUploadOnShiftClose());
    _syncSessionHeartbeat();
    return ShiftHandoverResult(
      outcome: HandoverOutcome.handedOff,
      opened: swapped.opened,
      pending: pendingSnap,
    );
  }

  /// Locks Shift N after the outgoing manager enters counted cash.
  Future<ShiftSummary?> finalizeReconciliation({
    required double actualCash,
    required String notes,
  }) async {
    await _ensureHydrated();
    final ReconciliationSnapshot? pending = state.pendingReconciliation;
    if (pending == null) {
      return null;
    }
    final ManagerShiftRecord closed = pending.shift.copyWith(
      expectedCash: pending.metrics.expectedCashInHand,
      actualCash: actualCash,
      notes: notes.trim(),
      status: ManagerShiftStatus.closed,
      udhaarRecoveryTotal: pending.metrics.udhaarRecoveryTotal,
    );
    await _repo.persistShift(closed);
    state = state.copyWith(
      clearPendingReconciliation: true,
      closedShifts: <ManagerShiftRecord>[closed, ...state.closedShifts],
    );
    unawaited(ref.read(settingsProvider.notifier).maybeUploadOnShiftClose());
    _syncSessionHeartbeat();
    return ShiftSummary(shift: closed, metrics: pending.metrics);
  }

  Future<bool> verifyActiveManagerPin(String pin) async {
    final ManagerShiftRecord? target =
        state.activeShift ?? state.pendingReconciliation?.shift;
    if (target == null) {
      return false;
    }
    return DatabaseHelper.instance.verifyManagerPin(
      managerId: target.managerId,
      pin: pin,
    );
  }

  Future<bool> resumeUnverifiedSession(String pin) async {
    await _ensureHydrated();
    if (!state.isUnverifiedSession) {
      return true;
    }
    final bool ok = await verifyActiveManagerPin(pin);
    if (!ok) {
      return false;
    }
    state = state.copyWith(sessionVerified: true, clearUncleanExitAt: true);
    unawaited(DatabaseHelper.instance.clearUncleanExitStamp());
    unawaited(DatabaseHelper.instance.markRuntimeUnclean());
    _syncSessionHeartbeat();
    return true;
  }

  /// Marks the live LIVE shift as PIN-verified (after login unlock).
  void markSessionVerified() {
    if (state.sessionVerified) {
      return;
    }
    state = state.copyWith(sessionVerified: true, clearUncleanExitAt: true);
    unawaited(DatabaseHelper.instance.clearUncleanExitStamp());
    unawaited(DatabaseHelper.instance.markRuntimeUnclean());
    _syncSessionHeartbeat();
    debugPrint('ShiftWorkspace: session marked verified after manager login');
  }

  /// Closes the live shift for tally. Does not open a successor.
  Future<ShiftHandoverResult> beginManualEnd({
    required String pin,
    int? blockingDispensingBay,
    Map<int, double> closingMeters = const <int, double>{},
  }) async {
    await _ensureHydrated();
    if (shouldEnforceStationGuards && blockingDispensingBay != null) {
      return ShiftHandoverResult(
        outcome: HandoverOutcome.baysDispensing,
        blockedBayId: blockingDispensingBay,
      );
    }
    if (state.pendingReconciliation != null) {
      return const ShiftHandoverResult(outcome: HandoverOutcome.alreadyPending);
    }
    final ManagerShiftRecord? open = state.activeShift;
    if (open == null) {
      return const ShiftHandoverResult(outcome: HandoverOutcome.noActiveShift);
    }
    final bool ok = await DatabaseHelper.instance.verifyManagerPin(
      managerId: open.managerId,
      pin: pin,
    );
    if (!ok) {
      return const ShiftHandoverResult(outcome: HandoverOutcome.invalidPin);
    }
    unassignAllHelpers();
    await _refreshExpectedCashComponents();
    final DateTime ended = DateTime.now();
    final ManagerShiftRecord window = open.copyWith(endTime: ended);
    final ShiftWindowMetrics metrics = metricsForSales(
      List<HelperSaleRecord>.from(salesForOutgoingManager(state.sales, window)),
      udhaarRecoveryTotal: state.udhaarRecoveryTotal,
    );
    final ManagerShiftRecord pendingShift = open.copyWith(
      endTime: ended,
      expectedCash: metrics.expectedCashInHand,
      status: ManagerShiftStatus.pendingReconciliation,
      udhaarRecoveryTotal: state.udhaarRecoveryTotal,
      closingMeters: closingMeters,
    );
    await _repo.persistShift(pendingShift);
    state = state.copyWith(
      clearActiveShift: true,
      pendingReconciliation: ReconciliationSnapshot(
        shift: pendingShift,
        metrics: metrics,
      ),
      managers: _withSingleActive(null),
      sessionVerified: true,
      udhaarRecoveryTotal: 0,
      clearUncleanExitAt: true,
    );
    _syncSessionHeartbeat();
    return ShiftHandoverResult(
      outcome: HandoverOutcome.handedOff,
      pending: ReconciliationSnapshot(shift: pendingShift, metrics: metrics),
    );
  }

  /// Marks the live or pending shift FORCE_CLOSED. No keypad lock traffic.
  Future<bool> forceCloseActiveShift({required String pin}) async {
    await _ensureHydrated();
    final ManagerShiftRecord? target =
        state.activeShift ?? state.pendingReconciliation?.shift;
    if (target == null) {
      return false;
    }
    final bool ok = await DatabaseHelper.instance.verifyManagerPin(
      managerId: target.managerId,
      pin: pin,
    );
    if (!ok) {
      return false;
    }
    unassignAllHelpers();
    await _refreshExpectedCashComponents();
    final DateTime ended = DateTime.now();
    final ManagerShiftRecord window = target.copyWith(endTime: ended);
    final ShiftWindowMetrics metrics = metricsForSales(
      salesForOutgoingManager(state.sales, window),
      udhaarRecoveryTotal: state.udhaarRecoveryTotal,
    );
    final ManagerShiftRecord closed = target.copyWith(
      endTime: ended,
      expectedCash: metrics.expectedCashInHand,
      actualCash: 0,
      notes: 'FORCE_CLOSED',
      status: ManagerShiftStatus.forceClosed,
      udhaarRecoveryTotal: state.udhaarRecoveryTotal,
    );
    await _repo.persistShift(closed);
    await DatabaseHelper.instance.insertAuditLog(
      actionType: AuditActionType.shiftForceClose,
      details:
          'Force-closed ${closed.shiftId} under ${closed.managerName} '
          '(expected ${closed.expectedCash.toStringAsFixed(2)}).',
      managerId: closed.managerId,
    );
    state = state.copyWith(
      clearActiveShift: true,
      clearPendingReconciliation: true,
      closedShifts: <ManagerShiftRecord>[closed, ...state.closedShifts],
      managers: _withSingleActive(null),
      sessionVerified: true,
      udhaarRecoveryTotal: 0,
    );
    unawaited(ref.read(settingsProvider.notifier).maybeUploadOnShiftClose());
    _syncSessionHeartbeat();
    return true;
  }

  Future<void> markAppCleanShutdown() async {
    if (state.hasActiveShift) {
      return;
    }
    await DatabaseHelper.instance.markCleanShutdown();
  }

  Future<void> refreshExpectedCashComponents() async {
    await _refreshExpectedCashComponents();
  }

  Future<void> _refreshExpectedCashComponents() async {
    final ManagerShiftRecord? shift =
        state.activeShift ?? state.pendingReconciliation?.shift;
    if (shift == null) {
      return;
    }
    try {
      final double settlements = await DatabaseHelper.instance
          .sumSettlementsForShift(shift.shiftId);
      if (settlements > state.udhaarRecoveryTotal) {
        state = state.copyWith(udhaarRecoveryTotal: settlements);
      }
    } catch (error, stack) {
      debugPrint(
        'ShiftWorkspaceNotifier.refreshExpectedCash failed: $error\n$stack',
      );
    }
  }

  List<ManagerProfile> _withSingleActive(String? managerId) {
    return state.managers.map((ManagerProfile manager) {
      final bool onDuty = manager.id == managerId;
      return manager.copyWith(
        status: onDuty
            ? ManagerProfileStatus.active
            : ManagerProfileStatus.inactive,
      );
    }).toList();
  }

  static int _nextIdSeq(Iterable<String> ids, String prefix) {
    int max = 0;
    for (final String id in ids) {
      if (!id.startsWith(prefix)) {
        continue;
      }
      final int? parsed = int.tryParse(id.substring(prefix.length));
      if (parsed != null && parsed > max) {
        max = parsed;
      }
    }
    return max + 1;
  }

  static String? _resolvedSelectedHelperId(
    List<HelperProfile> helpers,
    String? currentId,
  ) {
    if (currentId != null && helperById(helpers, currentId) != null) {
      return currentId;
    }
    if (helpers.isEmpty) {
      return null;
    }
    return helpers.first.id;
  }
}

final shiftWorkspaceProvider =
    NotifierProvider<ShiftWorkspaceNotifier, ShiftWorkspaceState>(
      ShiftWorkspaceNotifier.new,
    );

/// Live open shift. New telemetry and sales tag to this record.
class ActiveShiftNotifier extends Notifier<ManagerShiftRecord?> {
  @override
  ManagerShiftRecord? build() {
    return ref.watch(
      shiftWorkspaceProvider.select(
        (ShiftWorkspaceState state) => state.activeShift,
      ),
    );
  }
}

final activeShiftNotifierProvider =
    NotifierProvider<ActiveShiftNotifier, ManagerShiftRecord?>(
      ActiveShiftNotifier.new,
    );

/// Frozen Shift N while the outgoing manager tallies cash.
class ReconciliationShiftNotifier extends Notifier<ReconciliationSnapshot?> {
  @override
  ReconciliationSnapshot? build() {
    return ref.watch(
      shiftWorkspaceProvider.select(
        (ShiftWorkspaceState state) => state.pendingReconciliation,
      ),
    );
  }
}

final reconciliationShiftNotifierProvider =
    NotifierProvider<ReconciliationShiftNotifier, ReconciliationSnapshot?>(
      ReconciliationShiftNotifier.new,
    );

final activeShiftMetricsProvider = Provider<ShiftWindowMetrics>((Ref ref) {
  return ref.watch(shiftWorkspaceProvider).activeMetrics;
});

final helperRosterProvider = Provider<List<HelperProfile>>((Ref ref) {
  return ref.watch(shiftWorkspaceProvider).helpers;
});

final assignableHelpersProvider = Provider<List<HelperProfile>>((Ref ref) {
  return ref.watch(shiftWorkspaceProvider).assignableHelpers;
});

/// `sales_transactions` rows for the selected helper + date range.
final helperFilteredSalesProvider = FutureProvider<List<HelperSaleRecord>>((
  Ref ref,
) async {
  final String? helperId = ref.watch(
    shiftWorkspaceProvider.select(
      (ShiftWorkspaceState state) => state.selectedHelperId,
    ),
  );
  final HelperRangePreset preset = ref.watch(
    shiftWorkspaceProvider.select(
      (ShiftWorkspaceState state) => state.helperPreset,
    ),
  );
  final DateTimeRange? customRange = ref.watch(
    shiftWorkspaceProvider.select(
      (ShiftWorkspaceState state) => state.customRange,
    ),
  );
  ref.watch(
    shiftWorkspaceProvider.select(
      (ShiftWorkspaceState state) => state.sales.length,
    ),
  );
  if (helperId == null || helperId.isEmpty) {
    return const <HelperSaleRecord>[];
  }
  final DateTimeRange range =
      preset == HelperRangePreset.custom && customRange != null
      ? customRange
      : rangeForPreset(preset);
  return SqliteShiftRepository().listHelperSales(
    helperId: helperId,
    fromInclusive: range.start,
    toInclusive: range.end,
  );
});

final helperPerformanceProvider = Provider<HelperPerformanceSnapshot>((
  Ref ref,
) {
  final double rate = ref.watch(
    shiftWorkspaceProvider.select(
      (ShiftWorkspaceState state) => state.globalHelperRewardPerTx,
    ),
  );
  final List<HelperSaleRecord> rows =
      ref.watch(helperFilteredSalesProvider).asData?.value ??
      const <HelperSaleRecord>[];
  return helperPerformanceSnapshot(rows, rewardRate: rate);
});
