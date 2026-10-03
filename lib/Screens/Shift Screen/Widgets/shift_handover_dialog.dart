import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/dispensr_theme.dart';
import '../../../features/access/data/fingerprint_helper_client.dart';
import '../../../features/access/presentation/operator_fingerprint_watch.dart';
import '../../../features/shift/data/shift_summary_export.dart';
import '../../../features/shift/domain/shift_lifecycle.dart';
import '../../../features/shift/domain/shift_models.dart';
import '../../../features/shift/presentation/shift_providers.dart';
import '../../../features/station/domain/money_format.dart';
import '../../../providers/settings_provider.dart';
import 'helper_unit_assignment_panel.dart';
import 'shift_ui_kit.dart';

typedef ShiftAuthSubmit =
    Future<ShiftHandoverResult> Function({
      required String incomingOperatorId,
      required String pin,
      required bool fingerprintVerified,
      required Map<int, String?> unitAssignments,
    });

Future<ShiftHandoverResult?> showIncomingOperatorAuthDialog(
  BuildContext context, {
  required OperatorShiftRecord outgoingShift,
  required List<OperatorProfile> incomingOperators,
  required List<HelperProfile> helpers,
  required Map<int, String?> currentAssignments,
  required ShiftAuthSubmit onConfirm,
}) {
  return showDialog<ShiftHandoverResult>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return ShiftIncomingAuthDialog(
        outgoingShift: outgoingShift,
        incomingOperators: incomingOperators,
        helpers: helpers,
        currentAssignments: currentAssignments,
        onConfirm: onConfirm,
      );
    },
  );
}

class ShiftIncomingAuthDialog extends StatefulWidget {
  const ShiftIncomingAuthDialog({
    super.key,
    required this.outgoingShift,
    required this.incomingOperators,
    required this.helpers,
    required this.currentAssignments,
    required this.onConfirm,
  });

  final OperatorShiftRecord outgoingShift;
  final List<OperatorProfile> incomingOperators;
  final List<HelperProfile> helpers;
  final Map<int, String?> currentAssignments;
  final ShiftAuthSubmit onConfirm;

  @override
  State<ShiftIncomingAuthDialog> createState() =>
      _ShiftIncomingAuthDialogState();
}

class _ShiftIncomingAuthDialogState extends State<ShiftIncomingAuthDialog> {
  final TextEditingController _pin = TextEditingController();
  String? _selectedIncomingId;
  String? _pinError;
  late Map<int, String?> _assignments;
  bool _busy = false;
  bool _fingerprintReady = false;
  bool _showPin = !FingerprintHelperSession.isSupported;

  @override
  void initState() {
    super.initState();
    _assignments = Map<int, String?>.from(widget.currentAssignments);
  }

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  bool get _canConfirm {
    return !_busy &&
        _selectedIncomingId != null &&
        (_fingerprintReady || _pin.text.trim().length >= 4);
  }

  OperatorProfile? get _selectedOperator {
    final String? id = _selectedIncomingId;
    if (id == null) {
      return null;
    }
    for (final OperatorProfile operator in widget.incomingOperators) {
      if (operator.id == id) {
        return operator;
      }
    }
    return null;
  }

  void _selectIncoming(String id) {
    setState(() {
      _selectedIncomingId = id;
      _pinError = null;
      _fingerprintReady = false;
      _showPin = !FingerprintHelperSession.isSupported;
      _pin.clear();
    });
  }

  void _clearIncoming() {
    setState(() {
      _selectedIncomingId = null;
      _pinError = null;
      _fingerprintReady = false;
      _showPin = !FingerprintHelperSession.isSupported;
      _pin.clear();
    });
  }

  Future<void> _submit() async {
    final String? incomingId = _selectedIncomingId;
    if (incomingId == null || !_canConfirm) {
      return;
    }
    setState(() {
      _busy = true;
      _pinError = null;
    });
    final ShiftHandoverResult result = await widget.onConfirm(
      incomingOperatorId: incomingId,
      pin: _fingerprintReady ? '' : _pin.text.trim(),
      fingerprintVerified: _fingerprintReady,
      unitAssignments: Map<int, String?>.from(_assignments),
    );
    if (!mounted) {
      return;
    }
    if (result.outcome == HandoverOutcome.invalidPin) {
      setState(() {
        _busy = false;
        _pinError = 'PIN does not match the selected operator.';
      });
      return;
    }
    if (result.outcome == HandoverOutcome.unitsDispensing) {
      setState(() {
        _busy = false;
        _pinError =
            'Handover Blocked: Unit #${result.blockedUnitId ?? 0} is actively dispensing. Wait for nozzle stowage.';
      });
      return;
    }
    if (result.outcome == HandoverOutcome.pendingAccount) {
      setState(() {
        _busy = false;
        _pinError = ShiftLifecycleGuard.pendingAccountBlockedMessage();
      });
      return;
    }
    if (!result.isSuccess) {
      setState(() {
        _busy = false;
        _pinError = 'Could not start the incoming shift. Try again.';
      });
      return;
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return AlertDialog(
      backgroundColor: tokens.card,
      surfaceTintColor: tokens.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius20),
        side: BorderSide(color: tokens.line),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Row(
        children: <Widget>[
          Icon(Icons.verified_user_outlined, size: 20, color: tokens.coral),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Incoming Operator Authentication',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: tokens.ink,
                  ),
                ),
                Text(
                  'Start the next shift now · freeze ${widget.outgoingShift.shiftId}',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                    color: tokens.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        height: 580,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              _selectedIncomingId == null
                  ? 'Select the incoming operator. Fuel sales will tag to the '
                        'new shift immediately. ${widget.outgoingShift.operatorName} '
                        'can tally cash afterwards.'
                  : 'Enter ${_selectedOperator?.name ?? 'the incoming operator'}\'s '
                        'PIN and review helper duty. Keep or reassign who is on each unit.',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w500,
                fontSize: 13,
                color: tokens.inkMuted,
              ),
            ),
            const SizedBox(height: 14),
            if (_selectedIncomingId == null)
              Expanded(
                child: widget.incomingOperators.isEmpty
                    ? const ShiftEmptyHint(
                        message:
                            'Add another operator on the Shifts screen before handing off.',
                      )
                    : GridView.builder(
                        itemCount: widget.incomingOperators.length,
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 260,
                              mainAxisExtent: 88,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                        itemBuilder: (BuildContext context, int index) {
                          final OperatorProfile operator =
                              widget.incomingOperators[index];
                          return _IncomingOperatorCard(
                            operator: operator,
                            selected: operator.id == _selectedIncomingId,
                            onTap: () => _selectIncoming(operator.id),
                          );
                        },
                      ),
              )
            else ...<Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _busy ? null : _clearIncoming,
                  icon: const Icon(Icons.arrow_back, size: 16),
                  label: Text(
                    'Change operator · ${_selectedOperator?.name ?? ''}',
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: tokens.ink,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              OperatorFingerprintWatch(
                operatorId: _selectedIncomingId,
                showScanMark: true,
                onMatched: () {
                  if (!mounted) {
                    return;
                  }
                  setState(() {
                    _fingerprintReady = true;
                    _pinError = null;
                  });
                },
                onShowPin: (bool show) {
                  if (!mounted || _showPin == show) {
                    return;
                  }
                  setState(() {
                    _showPin = show;
                  });
                },
              ),
              if (_showPin) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  'Incoming operator PIN',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: tokens.inkMuted,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _pin,
                  enabled: !_busy,
                  obscureText: true,
                  maxLength: 6,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  onChanged: (_) {
                    setState(() {
                      _pinError = null;
                    });
                  },
                  onSubmitted: (_) => _submit(),
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    letterSpacing: 4,
                    color: tokens.ink,
                  ),
                  decoration: InputDecoration(
                    hintText: '••••',
                    counterText: '',
                    errorText: _pinError,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Helper assignment',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: tokens.inkMuted,
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: HelperUnitAssignmentPanel(
                  helpers: widget.helpers,
                  assignments: _assignments,
                  originalAssignments: widget.currentAssignments,
                  onChanged: (Map<int, String?> next) {
                    setState(() {
                      _assignments = next;
                    });
                  },
                ),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: DsPillButton(
                label: 'Cancel',
                variant: DsPillVariant.outline,
                compact: true,
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DsPillButton(
                label: _busy ? 'Handing over…' : 'Start Incoming Shift',
                compact: true,
                icon: Icons.swap_horiz,
                onPressed: _canConfirm ? _submit : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Non-blocking right drawer. Sale / dashboard stay interactable underneath.
class ShiftReconciliationOverlay extends ConsumerStatefulWidget {
  const ShiftReconciliationOverlay({super.key});

  @override
  ConsumerState<ShiftReconciliationOverlay> createState() =>
      _ShiftReconciliationOverlayState();
}

class _ShiftReconciliationOverlayState
    extends ConsumerState<ShiftReconciliationOverlay> {
  static final FilteringTextInputFormatter _decimalFormatter =
      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'));

  final TextEditingController _actual = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  bool _collapsed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _actual.addListener(_onChanged);
  }

  @override
  void dispose() {
    _actual
      ..removeListener(_onChanged)
      ..dispose();
    _notes.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  double? _actualCashOf() {
    final String raw = _actual.text.trim();
    if (raw.isEmpty) {
      return null;
    }
    return double.tryParse(raw);
  }

  ShiftSummary _preview(ReconciliationSnapshot snapshot) {
    return ShiftSummary(
      shift: snapshot.shift.copyWith(
        actualCash: _actualCashOf(),
        notes: _notes.text.trim(),
      ),
      metrics: snapshot.metrics,
    );
  }

  Future<void> _export(ReconciliationSnapshot snapshot) async {
    setState(() {
      _busy = true;
    });
    try {
      final File file = await ShiftSummaryExport.instance.printPdf(
        _preview(snapshot),
        showUnit5: ref.read(settingsProvider).showUnit5,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('PDF saved: ${file.path}')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not generate PDF: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _finalize() async {
    final double? actual = _actualCashOf();
    if (actual == null || actual < 0) {
      return;
    }
    try {
      final ShiftSummary? closed = await ref
          .read(shiftWorkspaceProvider.notifier)
          .finalizeReconciliation(
            actualCash: actual,
            notes: _notes.text.trim(),
          );
      if (!mounted) {
        return;
      }
      _actual.clear();
      _notes.clear();
      if (closed != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${closed.shift.shiftId} saved as closed. Variance ${formatSignedPkr(closed.shift.discrepancy)}.',
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save shift data: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ReconciliationSnapshot?>(reconciliationShiftNotifierProvider, (
      ReconciliationSnapshot? previous,
      ReconciliationSnapshot? next,
    ) {
      if (previous == null && next != null && _collapsed) {
        setState(() {
          _collapsed = false;
        });
      }
    });
    final ReconciliationSnapshot? snapshot = ref.watch(
      reconciliationShiftNotifierProvider,
    );
    if (snapshot == null) {
      return const SizedBox.shrink();
    }
    final OperatorShiftRecord? live = ref.watch(activeShiftNotifierProvider);
    final DispensrTokens tokens = DispensrTokens.of(context);
    final double? actual = _actualCashOf();
    final double? variance = actual == null
        ? null
        : actual - snapshot.metrics.expectedCashInHand;
    final Color varianceColor = variance == null
        ? tokens.inkMuted
        : variance < 0
        ? tokens.bad
        : tokens.good;

    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double panelHeight = constraints.maxHeight;
            return Material(
              color: tokens.card,
              elevation: 16,
              shadowColor: tokens.ink.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(tokens.radius20),
              clipBehavior: Clip.antiAlias,
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                tween: Tween<double>(end: _collapsed ? 52 : 400),
                builder: (BuildContext context, double width, Widget? child) {
                  return SizedBox(
                    width: width,
                    height: panelHeight,
                    child: child,
                  );
                },
                child: _collapsed
                    ? _CollapsedRail(
                        tokens: tokens,
                        shift: snapshot.shift,
                        onExpand: () {
                          setState(() {
                            _collapsed = false;
                          });
                        },
                      )
                    : OverflowBox(
                        alignment: Alignment.topLeft,
                        minWidth: 400,
                        maxWidth: 400,
                        minHeight: panelHeight,
                        maxHeight: panelHeight,
                        child: SizedBox(
                          width: 400,
                          height: panelHeight,
                          child: _ReconciliationBody(
                            tokens: tokens,
                            snapshot: snapshot,
                            live: live,
                            variance: variance,
                            varianceColor: varianceColor,
                            actualController: _actual,
                            notesController: _notes,
                            decimalFormatter: _decimalFormatter,
                            busy: _busy,
                            canFinalize:
                                actual != null && actual >= 0 && !_busy,
                            onCollapse: () {
                              setState(() {
                                _collapsed = true;
                              });
                            },
                            onExport: () {
                              unawaited(_export(snapshot));
                            },
                            onFinalize: _finalize,
                          ),
                        ),
                      ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CollapsedRail extends StatelessWidget {
  const _CollapsedRail({
    required this.tokens,
    required this.shift,
    required this.onExpand,
  });

  final DispensrTokens tokens;
  final OperatorShiftRecord shift;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onExpand,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: <Widget>[
            Icon(Icons.account_balance_wallet_outlined, color: tokens.coral),
            const SizedBox(height: 10),
            Expanded(
              child: Center(
                child: RotatedBox(
                  quarterTurns: 1,
                  child: Text(
                    'Pending tally · ${shift.shiftId}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: tokens.ink,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReconciliationBody extends StatelessWidget {
  const _ReconciliationBody({
    required this.tokens,
    required this.snapshot,
    required this.live,
    required this.variance,
    required this.varianceColor,
    required this.actualController,
    required this.notesController,
    required this.decimalFormatter,
    required this.busy,
    required this.canFinalize,
    required this.onCollapse,
    required this.onExport,
    required this.onFinalize,
  });

  final DispensrTokens tokens;
  final ReconciliationSnapshot snapshot;
  final OperatorShiftRecord? live;
  final double? variance;
  final Color varianceColor;
  final TextEditingController actualController;
  final TextEditingController notesController;
  final TextInputFormatter decimalFormatter;
  final bool busy;
  final bool canFinalize;
  final VoidCallback onCollapse;
  final VoidCallback onExport;
  final VoidCallback onFinalize;

  @override
  Widget build(BuildContext context) {
    final OperatorShiftRecord shift = snapshot.shift;
    final ShiftWindowMetrics metrics = snapshot.metrics;
    final OperatorShiftRecord? liveShift = live;
    final double? varianceAmount = variance;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tokens.coral.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(tokens.radius12),
                ),
                child: Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 16,
                  color: tokens.coral,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Deferred cash tally',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: tokens.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${shift.shiftId} · ${shift.operatorName} · frozen',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.w400,
                        fontSize: 12,
                        color: tokens.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Collapse — station stays live',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: onCollapse,
                icon: Icon(Icons.chevron_right, color: tokens.inkMuted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            decoration: BoxDecoration(
              color: tokens.good.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(tokens.radius12),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.info_outline, size: 14, color: tokens.good),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    liveShift == null
                        ? 'This table is frozen. New sales will not appear here.'
                        : 'Live ops: ${liveShift.shiftId} · ${liveShift.operatorName}. This tally will not receive those sales.',
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w500,
                      fontSize: 11.5,
                      color: tokens.good,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Expanded(
                child: _MiniKpi(
                  label: 'Total sale',
                  value: formatPkr(metrics.totalSale),
                  icon: Icons.payments_outlined,
                  tint: tokens.good,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _MiniKpi(
                  label: 'Udhaar issued',
                  value: formatPkr(metrics.udhaarSales),
                  icon: Icons.credit_card_off_outlined,
                  tint: tokens.coral,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _MiniKpi(
            label: 'Account payments',
            value: formatPkr(metrics.accountSales),
            icon: Icons.account_balance_outlined,
            tint: tokens.inkMuted,
          ),
          const SizedBox(height: 6),
          _UdhaarRecoveryMini(metrics: metrics),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: tokens.coral.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(tokens.radius12),
              border: Border.all(color: tokens.coral, width: 1.5),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Expected cash in hand',
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontWeight: FontWeight.w500,
                          fontSize: 10,
                          color: tokens.coralPressed,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        formatPkr(metrics.expectedCashInHand),
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          height: 1.1,
                          color: tokens.coralPressed,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        ShiftWindowMetrics.expectedCashFormula,
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontWeight: FontWeight.w400,
                          fontSize: 10,
                          color: tokens.coralPressed.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 19,
                  color: tokens.coral,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Actual physical cash collected (PKR)',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w500,
              fontSize: 12.5,
              color: tokens.ink,
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: actualController,
            enabled: !busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: <TextInputFormatter>[decimalFormatter],
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
              color: tokens.ink,
            ),
            decoration: const InputDecoration(
              hintText: '0.00',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: tokens.canvas,
              borderRadius: BorderRadius.circular(tokens.radius12),
              border: Border.all(color: tokens.line),
            ),
            child: Row(
              children: <Widget>[
                Text(
                  varianceAmount == null
                      ? 'Enter counted cash'
                      : varianceAmount < 0
                      ? 'SHORT'
                      : varianceAmount > 0
                      ? 'OVER'
                      : 'MATCHED',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                    color: varianceAmount == null
                        ? tokens.inkMuted
                        : varianceColor,
                  ),
                ),
                const Spacer(),
                if (varianceAmount == null)
                  Icon(Icons.expand_more, size: 16, color: tokens.inkMuted)
                else
                  Text(
                    formatSignedPkr(varianceAmount),
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: varianceColor,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: notesController,
            enabled: !busy,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w500,
              fontSize: 13.5,
              color: tokens.ink,
            ),
            decoration: const InputDecoration(
              hintText: 'Handover remarks…',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Frozen sales · ${shift.shiftId}',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
              color: tokens.ink,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(tokens.radius12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(tokens.radius12),
                  border: Border.all(color: tokens.line),
                ),
                child: metrics.sales.isEmpty
                    ? const ShiftEmptyHint(
                        message: 'No fuel sales tagged to this operator shift.',
                      )
                    : ShiftSalesTable(
                        rows: metrics.sales,
                        showFooter: true,
                        compact: true,
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: DsPillButton(
                  label: busy ? 'Generating…' : 'Generate PDF',
                  compact: true,
                  icon: Icons.picture_as_pdf_outlined,
                  onPressed: busy ? null : onExport,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DsPillButton(
                  label: 'Finalize',
                  compact: true,
                  icon: Icons.lock_outline,
                  onPressed: canFinalize ? onFinalize : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UdhaarRecoveryMini extends StatelessWidget {
  const _UdhaarRecoveryMini({required this.metrics});

  final ShiftWindowMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: tokens.canvas,
        borderRadius: BorderRadius.circular(tokens.radius12),
        border: Border.all(color: tokens.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Udhaar recovery',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w500,
              fontSize: 10,
              color: tokens.inkMuted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            formatPkr(metrics.udhaarRecoveryCombined),
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w700,
              fontSize: 16,
              height: 1.1,
              color: tokens.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            formatUdhaarRecoverySplit(metrics),
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w600,
              fontSize: 11,
              color: tokens.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniKpi extends StatelessWidget {
  const _MiniKpi({
    required this.label,
    required this.value,
    required this.icon,
    required this.tint,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: tokens.canvas,
        borderRadius: BorderRadius.circular(tokens.radius12),
        border: Border.all(color: tokens.line),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 13, color: tint),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w500,
                    fontSize: 10,
                    color: tokens.inkMuted,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    height: 1.15,
                    color: tokens.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IncomingOperatorCard extends StatelessWidget {
  const _IncomingOperatorCard({
    required this.operator,
    required this.selected,
    required this.onTap,
  });

  final OperatorProfile operator;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Material(
      color: selected ? tokens.coral.withValues(alpha: 0.10) : tokens.canvas,
      borderRadius: BorderRadius.circular(tokens.radius12),
      child: InkWell(
        onTap: onTap,
        hoverColor: tokens.ink.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(tokens.radius12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(tokens.radius12),
            border: Border.all(
              color: selected ? tokens.coral : tokens.line,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 18,
                backgroundColor: selected
                    ? tokens.coral.withValues(alpha: 0.22)
                    : tokens.line,
                child: Text(
                  operator.initials,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: selected ? tokens.coralPressed : tokens.inkMuted,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      operator.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: tokens.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    DsStatusPill(
                      label: operatorRoleLabel(operator.role),
                      foreground: tokens.coralPressed,
                      background: tokens.coral.withValues(alpha: 0.12),
                      border: tokens.coral.withValues(alpha: 0.35),
                      dot: false,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
