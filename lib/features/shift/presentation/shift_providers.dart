import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/settings_provider.dart';
import '../../../services/database_helper.dart';
import '../../access/domain/access_policy.dart';
import '../../customer/data/sqlite_unified_udhaar_repository.dart';
import '../../customer/domain/customer_models.dart';
import '../../station/domain/dispenser_models.dart';
import '../data/sqlite_shift_repository.dart';
import '../domain/shift_lifecycle.dart';
import '../domain/shift_models.dart';

@immutable
class ShiftWorkspaceState {
  const ShiftWorkspaceState({
    required this.operators,
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
    this.nextOperatorSeq = 1,
    this.nextHelperSeq = 1,
    this.nextShiftSeq = 1,
    this.nextDutySeq = 1,
    this.udhaarRecoveryTotal = 0,
    this.udhaarRecoveryAccountTotal = 0,
    this.udhaarRecoveryPartialTotal = 0,
    this.sessionVerified = true,
    this.uncleanExitAt,
  });

  final List<OperatorProfile> operators;
  final List<HelperProfile> helpers;
  final OperatorShiftRecord? activeShift;
  final ReconciliationSnapshot? pendingReconciliation;
  final List<OperatorShiftRecord> closedShifts;
  final List<HelperSaleRecord> sales;
  final List<HelperDutySession> dutySessions;
  final ShiftWorkspaceTab tab;
  final OperatorTallyPane tallyPane;
  final String? selectedHelperId;
  final HelperRangePreset helperPreset;
  final DateTimeRange? customRange;
  final double globalHelperRewardPerTx;
  final int nextOperatorSeq;
  final int nextHelperSeq;
  final int nextShiftSeq;
  final int nextDutySeq;
  final double udhaarRecoveryTotal;
  final double udhaarRecoveryAccountTotal;
  final double udhaarRecoveryPartialTotal;
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
    final OperatorShiftRecord? open = activeShift;
    if (open == null) {
      return ShiftWindowMetrics.empty;
    }
    return metricsForSales(
      salesForOutgoingOperator(sales, open),
      udhaarRecoveryTotal: udhaarRecoveryTotal,
      udhaarRecoveryAccountTotal: udhaarRecoveryAccountTotal,
      udhaarRecoveryPartialTotal: udhaarRecoveryPartialTotal,
    );
  }

  ShiftWindowMetrics metricsForOperatorShift(OperatorShiftRecord shift) {
    return metricsForSales(
      salesForOutgoingOperator(sales, shift),
      udhaarRecoveryTotal: udhaarRecoveryTotal,
      udhaarRecoveryAccountTotal: udhaarRecoveryAccountTotal,
      udhaarRecoveryPartialTotal: udhaarRecoveryPartialTotal,
    );
  }

  List<OperatorProfile> get incomingHandoverCandidates {
    final String? outgoingId = activeShift?.operatorId;
    return operators
        .where((OperatorProfile operator) => operator.id != outgoingId)
        .toList();
  }

  bool get canEndShift => activeShift != null && pendingReconciliation == null;

  bool get hasUnconfirmedAccount => pendingAccountSales.isNotEmpty;

  List<HelperSaleRecord> get pendingAccountSales {
    final OperatorShiftRecord? open = activeShift;
    if (open == null) {
      return const <HelperSaleRecord>[];
    }
    return salesForOutgoingOperator(
      sales,
      open,
    ).where((HelperSaleRecord row) => row.pendingAccountAmount > 0).toList();
  }

  /// OPEN shift or unfinished tally — blocks native window close.
  bool get hasActiveShift {
    return (activeShift != null && activeShift!.isOpen) ||
        pendingReconciliation != null;
  }

  bool get isUnverifiedSession {
    return activeShift != null && activeShift!.isOpen && !sessionVerified;
  }

  bool get needsCrashRecovery => isUnverifiedSession;

  List<OperatorShiftRecord> get knownShifts {
    return <OperatorShiftRecord>[
      if (activeShift != null) activeShift!,
      if (pendingReconciliation != null) pendingReconciliation!.shift,
      ...closedShifts,
    ];
  }

  ShiftWorkspaceState copyWith({
    List<OperatorProfile>? operators,
    List<HelperProfile>? helpers,
    OperatorShiftRecord? activeShift,
    bool clearActiveShift = false,
    ReconciliationSnapshot? pendingReconciliation,
    bool clearPendingReconciliation = false,
    List<OperatorShiftRecord>? closedShifts,
    List<HelperSaleRecord>? sales,
    List<HelperDutySession>? dutySessions,
    ShiftWorkspaceTab? tab,
    OperatorTallyPane? tallyPane,
    String? selectedHelperId,
    bool clearSelectedHelper = false,
    HelperRangePreset? helperPreset,
    DateTimeRange? customRange,
    bool clearCustomRange = false,
    double? globalHelperRewardPerTx,
    int? nextOperatorSeq,
    int? nextHelperSeq,
    int? nextShiftSeq,
    int? nextDutySeq,
    double? udhaarRecoveryTotal,
    double? udhaarRecoveryAccountTotal,
    double? udhaarRecoveryPartialTotal,
    bool? sessionVerified,
    DateTime? uncleanExitAt,
    bool clearUncleanExitAt = false,
  }) {
    return ShiftWorkspaceState(
      operators: operators ?? this.operators,
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
      nextOperatorSeq: nextOperatorSeq ?? this.nextOperatorSeq,
      nextHelperSeq: nextHelperSeq ?? this.nextHelperSeq,
      nextShiftSeq: nextShiftSeq ?? this.nextShiftSeq,
      nextDutySeq: nextDutySeq ?? this.nextDutySeq,
      udhaarRecoveryTotal: udhaarRecoveryTotal ?? this.udhaarRecoveryTotal,
      udhaarRecoveryAccountTotal:
          udhaarRecoveryAccountTotal ?? this.udhaarRecoveryAccountTotal,
      udhaarRecoveryPartialTotal:
          udhaarRecoveryPartialTotal ?? this.udhaarRecoveryPartialTotal,
      sessionVerified: sessionVerified ?? this.sessionVerified,
      uncleanExitAt: clearUncleanExitAt
          ? null
          : (uncleanExitAt ?? this.uncleanExitAt),
    );
  }

  static ShiftWorkspaceState empty() {
    return const ShiftWorkspaceState(
      operators: <OperatorProfile>[],
      helpers: <HelperProfile>[],
      closedShifts: <OperatorShiftRecord>[],
      sales: <HelperSaleRecord>[],
      dutySessions: <HelperDutySession>[],
      tab: ShiftWorkspaceTab.operators,
      tallyPane: OperatorTallyPane.todaySales,
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
      OperatorShiftRecord? live;
      for (final OperatorShiftRecord shift in snapshot.shifts) {
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

  Future<AppSessionSnapshot> _loadBootSession(OperatorShiftRecord? live) async {
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
    OperatorShiftRecord? open;
    OperatorShiftRecord? pending;
    final List<OperatorShiftRecord> closed = <OperatorShiftRecord>[];
    for (final OperatorShiftRecord shift in snapshot.shifts) {
      switch (shift.status) {
        case OperatorShiftStatus.open:
          open ??= shift;
        case OperatorShiftStatus.pendingReconciliation:
          pending ??= shift;
        case OperatorShiftStatus.closed:
        case OperatorShiftStatus.forceClosed:
          closed.add(shift);
      }
    }

    final List<HelperProfile> helpers = snapshot.helpers.map((
      HelperProfile helper,
    ) {
      if (helper.assignedUnitIds.isNotEmpty) {
        return helper;
      }
      final HelperProfile? existing = helperById(preserve.helpers, helper.id);
      if (existing == null || existing.assignedUnitIds.isEmpty) {
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

    final bool hasOpenDuty = preserve.dutySessions.any(
      (HelperDutySession session) => session.isOpen,
    );
    final List<HelperDutySession> dutySessions = hasOpenDuty
        ? preserve.dutySessions
        : _dutySessionsFromAssignments(helpers);

    return preserve.copyWith(
      operators: snapshot.operators.map((OperatorProfile operator) {
        return operator.copyWith(
          status: operator.id == open?.operatorId
              ? OperatorProfileStatus.active
              : OperatorProfileStatus.inactive,
        );
      }).toList(),
      helpers: helpers,
      dutySessions: dutySessions,
      nextDutySeq: _nextIdSeq(
        dutySessions.map((HelperDutySession session) => session.id),
        'duty-',
      ),
      activeShift: open,
      clearActiveShift: open == null,
      pendingReconciliation: pendingSnapshot,
      clearPendingReconciliation: pendingSnapshot == null,
      closedShifts: closed,
      sales: snapshot.sales,
      selectedHelperId: selectedHelperId,
      clearSelectedHelper: selectedHelperId == null,
      nextOperatorSeq: _nextIdSeq(
        snapshot.operators.map((OperatorProfile row) => row.id),
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

  void setTallyPane(OperatorTallyPane pane) {
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

  /// Replaces duty on every unit. Null / empty helper ids leave that unit idle.
  void applyUnitAssignments(Map<int, String?> unitHelperIds) {
    for (final int unitId in dispenserUnitIds) {
      final String? raw = unitHelperIds[unitId];
      final String? helperId = (raw == null || raw.isEmpty) ? null : raw;
      _assignHelperToUnit(unitId: unitId, helperId: helperId, persist: false);
    }
    unawaited(_persistHelperAssignments());
  }

  void unassignAllHelpers() {
    applyUnitAssignments(<int, String?>{
      for (final int unitId in dispenserUnitIds) unitId: null,
    });
  }

  /// One helper per unit. A helper may cover multiple units.
  /// Passing a null [helperId] clears only this unit.
  void assignHelperToUnit({required int unitId, String? helperId}) {
    _assignHelperToUnit(unitId: unitId, helperId: helperId, persist: true);
  }

  void _assignHelperToUnit({
    required int unitId,
    required String? helperId,
    required bool persist,
  }) {
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
    if (persist) {
      unawaited(_persistHelperAssignments());
    }
  }

  Future<void> _persistHelperAssignments() async {
    try {
      await _repo.persistHelperAssignments(state.helpers);
    } catch (error, stack) {
      debugPrint(
        'ShiftWorkspaceNotifier.persistHelperAssignments failed: $error\n$stack',
      );
    }
  }

  static List<HelperDutySession> _dutySessionsFromAssignments(
    List<HelperProfile> helpers,
  ) {
    int seq = 1;
    final DateTime now = DateTime.now();
    final List<HelperDutySession> sessions = <HelperDutySession>[];
    for (final HelperProfile helper in helpers) {
      for (final int unitId in helper.assignedUnitIds) {
        sessions.add(
          HelperDutySession(
            id: 'duty-$seq',
            helperId: helper.id,
            helperName: helper.name,
            unitId: unitId,
            startTime: now,
          ),
        );
        seq += 1;
      }
    }
    return sessions;
  }

  void recordSale(HelperSaleRecord sale) {
    final List<HelperSaleRecord> next = state.sales
        .where((HelperSaleRecord row) => row.tokenNo != sale.tokenNo)
        .toList();
    state = state.copyWith(sales: <HelperSaleRecord>[sale, ...next]);
  }

  /// Updates cash, account, and payment on an existing shift sale.
  /// Helper, operator, and shift stay as they were when the fuel was sold.
  void patchSaleTender({
    required int tokenNo,
    required PaymentMethod payment,
    required double cashAmount,
    required double accountAmount,
    required double pendingAccountAmount,
  }) {
    final int index = state.sales.indexWhere(
      (HelperSaleRecord row) => row.tokenNo == tokenNo,
    );
    if (index < 0) {
      return;
    }
    final List<HelperSaleRecord> next = List<HelperSaleRecord>.from(
      state.sales,
    );
    next[index] = state.sales[index].copyWith(
      payment: payment,
      cashAmount: cashAmount,
      accountAmount: accountAmount,
      pendingAccountAmount: pendingAccountAmount,
    );
    state = state.copyWith(sales: next);
  }

  void addUdhaarRecovery({
    double cashAmount = 0,
    double accountAmount = 0,
    bool partial = false,
  }) {
    if (state.activeShift == null) {
      return;
    }
    final double cash = cashAmount < 0 ? 0 : cashAmount;
    final double account = accountAmount < 0 ? 0 : accountAmount;
    if (cash <= 0 && account <= 0) {
      return;
    }
    state = state.copyWith(
      udhaarRecoveryTotal: state.udhaarRecoveryTotal + cash,
      udhaarRecoveryAccountTotal: state.udhaarRecoveryAccountTotal + account,
      udhaarRecoveryPartialTotal: partial
          ? state.udhaarRecoveryPartialTotal + cash + account
          : state.udhaarRecoveryPartialTotal,
    );
  }

  ShiftWindowMetrics _metricsWithRecoveries(OperatorShiftRecord shift) {
    return metricsForSales(
      List<HelperSaleRecord>.from(
        salesForOutgoingOperator(state.sales, shift),
      ),
      udhaarRecoveryTotal: state.udhaarRecoveryTotal,
      udhaarRecoveryAccountTotal: state.udhaarRecoveryAccountTotal,
      udhaarRecoveryPartialTotal: state.udhaarRecoveryPartialTotal,
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

  Future<void> addOperator({
    required String name,
    required OperatorRole role,
    String pin = kDefaultOperatorPin,
  }) async {
    await _ensureHydrated();
    final String trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final String resolvedPin = pin.trim().isEmpty
        ? kDefaultOperatorPin
        : pin.trim();
    final int seq = state.nextOperatorSeq;
    final OperatorProfile profile = await _repo.insertOperator(
      id: 'mgr-$seq',
      name: trimmed,
      role: role,
      pin: resolvedPin,
    );
    state = state.copyWith(
      operators: <OperatorProfile>[...state.operators, profile],
      nextOperatorSeq: seq + 1,
    );
  }

  /// Only one open operator shift is allowed. Returns why a start was refused.
  Future<StartShiftOutcome> startShift(
    String operatorId, {
    required String pin,
    bool fingerprintVerified = false,
    Map<int, String?>? unitAssignments,
    Map<int, double> openingMeters = const <int, double>{},
  }) async {
    await _ensureHydrated();
    final OperatorShiftRecord? open = state.activeShift;
    if (open != null) {
      if (open.operatorId == operatorId) {
        return StartShiftOutcome.alreadyOnDuty;
      }
      return StartShiftOutcome.blocked;
    }
    OperatorProfile? profile;
    for (final OperatorProfile operator in state.operators) {
      if (operator.id == operatorId) {
        profile = operator;
        break;
      }
    }
    if (profile == null) {
      return StartShiftOutcome.blocked;
    }
    final bool pinOk =
        fingerprintVerified ||
        await DatabaseHelper.instance.verifyOperatorPin(
          operatorId: operatorId,
          pin: pin,
        );
    if (!pinOk) {
      return StartShiftOutcome.invalidPin;
    }
    final OperatorShiftRecord shift = await _repo.insertOpenShift(
      operator: profile,
      startTime: DateTime.now(),
      openingMeters: openingMeters,
    );
    await DatabaseHelper.instance.markRuntimeUnclean();
    await DatabaseHelper.instance.clearUncleanExitStamp();
    state = state.copyWith(
      activeShift: shift,
      operators: _withSingleActive(profile.id),
      udhaarRecoveryTotal: 0,
      udhaarRecoveryAccountTotal: 0,
      udhaarRecoveryPartialTotal: 0,
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
    final OperatorShiftRecord? open = state.activeShift;
    if (open == null) {
      return null;
    }
    final DateTime ended = DateTime.now();
    final OperatorShiftRecord window = open.copyWith(endTime: ended);
    await _refreshExpectedCashComponents();
    final ShiftWindowMetrics metrics = _metricsWithRecoveries(window);
    final OperatorShiftRecord closed = open.copyWith(
      endTime: ended,
      expectedCash: metrics.expectedCashInHand,
      actualCash: actualCash,
      notes: notes.trim(),
      status: OperatorShiftStatus.closed,
      udhaarRecoveryTotal: state.udhaarRecoveryTotal,
    );
    await _repo.persistShift(closed);
    state = state.copyWith(
      clearActiveShift: true,
      closedShifts: <OperatorShiftRecord>[closed, ...state.closedShifts],
      operators: _withSingleActive(null),
      udhaarRecoveryTotal: 0,
      udhaarRecoveryAccountTotal: 0,
      udhaarRecoveryPartialTotal: 0,
    );
    unawaited(ref.read(settingsProvider.notifier).maybeUploadOnShiftClose());
    _syncSessionHeartbeat();
    return ShiftSummary(shift: closed, metrics: metrics);
  }

  /// Authenticates the incoming operator, freezes Shift N for tally, and opens N+1 LIVE.
  Future<ShiftHandoverResult> beginHandover({
    required String incomingOperatorId,
    required String pin,
    bool fingerprintVerified = false,
    Map<int, String?>? unitAssignments,
    int? blockingDispensingUnit,
    double? actualCash,
    String notes = '',
    Map<int, double> closingMeters = const <int, double>{},
    Map<int, double> openingMeters = const <int, double>{},
  }) async {
    await _ensureHydrated();
    if (shouldEnforceStationGuards && blockingDispensingUnit != null) {
      return ShiftHandoverResult(
        outcome: HandoverOutcome.unitsDispensing,
        blockedUnitId: blockingDispensingUnit,
      );
    }
    if (state.pendingReconciliation != null) {
      return const ShiftHandoverResult(outcome: HandoverOutcome.alreadyPending);
    }
    if (state.hasUnconfirmedAccount) {
      return const ShiftHandoverResult(outcome: HandoverOutcome.pendingAccount);
    }
    final OperatorShiftRecord? open = state.activeShift;
    if (open == null) {
      return const ShiftHandoverResult(outcome: HandoverOutcome.noActiveShift);
    }
    if (incomingOperatorId == open.operatorId) {
      return const ShiftHandoverResult(outcome: HandoverOutcome.sameOperator);
    }
    OperatorProfile? incoming;
    for (final OperatorProfile operator in state.operators) {
      if (operator.id == incomingOperatorId) {
        incoming = operator;
        break;
      }
    }
    if (incoming == null) {
      return const ShiftHandoverResult(
        outcome: HandoverOutcome.unknownOperator,
      );
    }
    final bool pinOk =
        fingerprintVerified ||
        await DatabaseHelper.instance.verifyOperatorPin(
          operatorId: incomingOperatorId,
          pin: pin,
        );
    if (!pinOk) {
      return const ShiftHandoverResult(outcome: HandoverOutcome.invalidPin);
    }

    final DateTime handoffAt = DateTime.now();
    final OperatorShiftRecord window = open.copyWith(endTime: handoffAt);
    await _refreshExpectedCashComponents();
    final ShiftWindowMetrics frozenMetrics = _metricsWithRecoveries(window);
    final OperatorShiftRecord outgoing = open.copyWith(
      endTime: handoffAt,
      expectedCash: frozenMetrics.expectedCashInHand,
      actualCash: actualCash,
      notes: notes.trim(),
      status: OperatorShiftStatus.pendingReconciliation,
      udhaarRecoveryTotal: state.udhaarRecoveryTotal,
      closingMeters: closingMeters,
    );
    final ({OperatorShiftRecord pending, OperatorShiftRecord opened}) swapped =
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
      operators: _withSingleActive(incoming.id),
      udhaarRecoveryTotal: 0,
      udhaarRecoveryAccountTotal: 0,
      udhaarRecoveryPartialTotal: 0,
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

  /// Locks Shift N after the outgoing operator enters counted cash.
  Future<ShiftSummary?> finalizeReconciliation({
    required double actualCash,
    required String notes,
  }) async {
    await _ensureHydrated();
    final ReconciliationSnapshot? pending = state.pendingReconciliation;
    if (pending == null) {
      return null;
    }
    final OperatorShiftRecord closed = pending.shift.copyWith(
      expectedCash: pending.metrics.expectedCashInHand,
      actualCash: actualCash,
      notes: notes.trim(),
      status: OperatorShiftStatus.closed,
      udhaarRecoveryTotal: pending.metrics.udhaarRecoveryTotal,
    );
    await _repo.persistShift(closed);
    state = state.copyWith(
      clearPendingReconciliation: true,
      closedShifts: <OperatorShiftRecord>[closed, ...state.closedShifts],
    );
    unawaited(ref.read(settingsProvider.notifier).maybeUploadOnShiftClose());
    _syncSessionHeartbeat();
    return ShiftSummary(shift: closed, metrics: pending.metrics);
  }

  Future<bool> verifyActiveOperatorPin(String pin) async {
    final OperatorShiftRecord? target =
        state.activeShift ?? state.pendingReconciliation?.shift;
    if (target == null) {
      return false;
    }
    return DatabaseHelper.instance.verifyOperatorPin(
      operatorId: target.operatorId,
      pin: pin,
    );
  }

  Future<bool> resumeUnverifiedSession(
    String pin, {
    bool fingerprintVerified = false,
  }) async {
    await _ensureHydrated();
    if (!state.isUnverifiedSession) {
      return true;
    }
    final bool ok =
        fingerprintVerified || await verifyActiveOperatorPin(pin);
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
    debugPrint('ShiftWorkspace: session marked verified after operator login');
  }

  /// Closes the live shift for tally. Does not open a successor.
  Future<ShiftHandoverResult> beginManualEnd({
    required String pin,
    bool fingerprintVerified = false,
    int? blockingDispensingUnit,
    Map<int, double> closingMeters = const <int, double>{},
  }) async {
    await _ensureHydrated();
    if (shouldEnforceStationGuards && blockingDispensingUnit != null) {
      return ShiftHandoverResult(
        outcome: HandoverOutcome.unitsDispensing,
        blockedUnitId: blockingDispensingUnit,
      );
    }
    if (state.pendingReconciliation != null) {
      return const ShiftHandoverResult(outcome: HandoverOutcome.alreadyPending);
    }
    if (state.hasUnconfirmedAccount) {
      return const ShiftHandoverResult(outcome: HandoverOutcome.pendingAccount);
    }
    final OperatorShiftRecord? open = state.activeShift;
    if (open == null) {
      return const ShiftHandoverResult(outcome: HandoverOutcome.noActiveShift);
    }
    final bool ok =
        fingerprintVerified ||
        await DatabaseHelper.instance.verifyOperatorPin(
          operatorId: open.operatorId,
          pin: pin,
        );
    if (!ok) {
      return const ShiftHandoverResult(outcome: HandoverOutcome.invalidPin);
    }
    unassignAllHelpers();
    await _refreshExpectedCashComponents();
    final DateTime ended = DateTime.now();
    final OperatorShiftRecord window = open.copyWith(endTime: ended);
    final ShiftWindowMetrics metrics = _metricsWithRecoveries(window);
    final OperatorShiftRecord pendingShift = open.copyWith(
      endTime: ended,
      expectedCash: metrics.expectedCashInHand,
      status: OperatorShiftStatus.pendingReconciliation,
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
      operators: _withSingleActive(null),
      sessionVerified: true,
      udhaarRecoveryTotal: 0,
      udhaarRecoveryAccountTotal: 0,
      udhaarRecoveryPartialTotal: 0,
      clearUncleanExitAt: true,
    );
    _syncSessionHeartbeat();
    return ShiftHandoverResult(
      outcome: HandoverOutcome.handedOff,
      pending: ReconciliationSnapshot(shift: pendingShift, metrics: metrics),
    );
  }

  /// Marks the live or pending shift FORCE_CLOSED. No keypad lock traffic.
  Future<bool> forceCloseActiveShift({
    required String pin,
    bool fingerprintVerified = false,
  }) async {
    await _ensureHydrated();
    final OperatorShiftRecord? target =
        state.activeShift ?? state.pendingReconciliation?.shift;
    if (target == null) {
      return false;
    }
    final bool ok =
        fingerprintVerified ||
        await DatabaseHelper.instance.verifyOperatorPin(
          operatorId: target.operatorId,
          pin: pin,
        );
    if (!ok) {
      return false;
    }
    unassignAllHelpers();
    await _refreshExpectedCashComponents();
    final DateTime ended = DateTime.now();
    final OperatorShiftRecord window = target.copyWith(endTime: ended);
    final ShiftWindowMetrics metrics = _metricsWithRecoveries(window);
    final OperatorShiftRecord closed = target.copyWith(
      endTime: ended,
      expectedCash: metrics.expectedCashInHand,
      actualCash: 0,
      notes: 'FORCE_CLOSED',
      status: OperatorShiftStatus.forceClosed,
      udhaarRecoveryTotal: state.udhaarRecoveryTotal,
    );
    await _repo.persistShift(closed);
    await DatabaseHelper.instance.insertAuditLog(
      actionType: AuditActionType.shiftForceClose,
      details:
          'Force-closed ${closed.shiftId} under ${closed.operatorName} '
          '(expected ${closed.expectedCash.toStringAsFixed(2)}).',
      operatorId: closed.operatorId,
    );
    state = state.copyWith(
      clearActiveShift: true,
      clearPendingReconciliation: true,
      closedShifts: <OperatorShiftRecord>[closed, ...state.closedShifts],
      operators: _withSingleActive(null),
      sessionVerified: true,
      udhaarRecoveryTotal: 0,
      udhaarRecoveryAccountTotal: 0,
      udhaarRecoveryPartialTotal: 0,
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
    final OperatorShiftRecord? shift =
        state.activeShift ?? state.pendingReconciliation?.shift;
    if (shift == null) {
      return;
    }
    try {
      final List<Map<String, Object?>> rows = await DatabaseHelper.instance
          .queryUnifiedUdhaarLedger(shiftId: shift.shiftId);
      final UdhaarRecoveryShiftTotals totals = udhaarRecoveryTotalsFromRows(
        rows.map(SqliteUnifiedUdhaarRepository.fromRow),
      );
      state = state.copyWith(
        udhaarRecoveryTotal: totals.cash,
        udhaarRecoveryAccountTotal: totals.account,
        udhaarRecoveryPartialTotal: totals.partialPaid,
      );
    } catch (error, stack) {
      debugPrint(
        'ShiftWorkspaceNotifier.refreshExpectedCash failed: $error\n$stack',
      );
    }
  }

  List<OperatorProfile> _withSingleActive(String? operatorId) {
    return state.operators.map((OperatorProfile operator) {
      final bool onDuty = operator.id == operatorId;
      return operator.copyWith(
        status: onDuty
            ? OperatorProfileStatus.active
            : OperatorProfileStatus.inactive,
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
class ActiveShiftNotifier extends Notifier<OperatorShiftRecord?> {
  @override
  OperatorShiftRecord? build() {
    return ref.watch(
      shiftWorkspaceProvider.select(
        (ShiftWorkspaceState state) => state.activeShift,
      ),
    );
  }
}

final activeShiftNotifierProvider =
    NotifierProvider<ActiveShiftNotifier, OperatorShiftRecord?>(
      ActiveShiftNotifier.new,
    );

/// Frozen Shift N while the outgoing operator tallies cash.
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
