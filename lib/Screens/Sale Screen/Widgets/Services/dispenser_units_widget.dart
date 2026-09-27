import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/dispensr_theme.dart';
import '../../../../core/widgets/segment_lcd.dart';
import '../../../../features/shift/domain/shift_models.dart';
import '../../../../features/shift/presentation/shift_providers.dart';
import '../../../../features/access/domain/access_policy.dart';
import '../../../../features/station/domain/dispenser_models.dart';
import '../../../../features/station/presentation/station_providers.dart';
import '../../../../utils/fuel_formatter.dart';
import 'confirm_payment_dialog.dart';
import 'fuel_nozzle_graphic.dart';
import 'helper_duty_dialog.dart';

class DispenserUnitData {
  const DispenserUnitData({
    required this.unitId,
    required this.unitNumber,
    required this.name,
    required this.fuelType,
    required this.online,
    required this.espConnected,
    required this.fdxBoardLinked,
    required this.runState,
    required this.rupees,
    required this.liters,
    required this.ratePerLitre,
    required this.lastRupees,
    required this.lastLiters,
    required this.lastTime,
    required this.lastCashier,
    required this.totalMeter,
    required this.volumeLiters,
  });

  factory DispenserUnitData.fromBay(
    DispenserBay bay, {
    required bool espConnected,
    required bool fdxBoardLinked,
  }) {
    return DispenserUnitData(
      unitId: bay.unitId,
      unitNumber: bay.unitId.toString().padLeft(2, '0'),
      name: bay.name,
      fuelType: bay.fuelType,
      online: espConnected && fdxBoardLinked,
      espConnected: espConnected,
      fdxBoardLinked: fdxBoardLinked,
      runState: bay.status,
      rupees: bay.status == DispenserRunState.litersPreset
          ? ''
          : bay.status == DispenserRunState.rupeesPreset
          ? '${bay.amountPkr.truncate()}'
          : FuelFormatter.lcdDispenserAmount(bay.amountPkr),
      liters: bay.status == DispenserRunState.rupeesPreset
          ? ''
          : bay.status == DispenserRunState.litersPreset
          ? '${bay.volumeLiters.truncate()}'
          : FuelFormatter.lcdVolume(bay.volumeLiters),
      ratePerLitre: FuelFormatter.lcdAverageRate(bay.rate),
      lastRupees: bay.lastRupees,
      lastLiters: bay.lastLiters,
      lastTime: bay.lastTime,
      lastCashier: bay.lastCashier,
      totalMeter: FuelFormatter.lcdVolume(bay.meterCount),
      volumeLiters: bay.volumeLiters,
    );
  }

  final int unitId;
  final String unitNumber;
  final String name;
  final String fuelType;
  final bool online;
  final bool espConnected;
  final bool fdxBoardLinked;
  final DispenserRunState runState;
  final String rupees;
  final String liters;
  final String ratePerLitre;
  final String lastRupees;
  final String lastLiters;
  final String lastTime;
  final String lastCashier;
  final String totalMeter;
  final double volumeLiters;

  bool get isDispensing => runState == DispenserRunState.dispensing;
  bool get isOffline => !online;
  bool get isEspDisconnected => !espConnected;
  bool get isFdxDisconnected => espConnected && !fdxBoardLinked;
  bool get isCycleComplete => runState == DispenserRunState.cycleComplete;
  bool get canConfirmPayment =>
      isCycleComplete && volumeLiters >= DispenserBay.zeroVolumeEpsilon;
}

/// One dispenser card. Instantiate once per unit with different [data].
class DispenserUnitsWidget extends ConsumerWidget {
  const DispenserUnitsWidget({
    super.key,
    required this.data,
    required this.isSelected,
    this.abortNotice,
    this.onSelect,
  });

  final DispenserUnitData data;
  final bool isSelected;
  final String? abortNotice;
  final VoidCallback? onSelect;

  static const Color _selectedBorder = Color(0xFF4CA771);
  static const Color _idleBorder = Color(0xFFE0E0E0);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool espDown = data.isEspDisconnected;
    final bool dispensing = data.isDispensing;
    final String? notice = abortNotice;

    final String runLabel;
    final Color runFg;
    final Color runBg;
    final Color runBorder;
    if (dispensing) {
      runLabel = 'Dispensing';
      runFg = tokens.coralPressed;
      runBg = tokens.coral.withValues(alpha: 0.12);
      runBorder = tokens.coral.withValues(alpha: 0.35);
    } else if (data.runState == DispenserRunState.rupeesPreset) {
      runLabel = 'P  Amount';
      runFg = tokens.ink;
      runBg = tokens.good.withValues(alpha: 0.12);
      runBorder = tokens.good.withValues(alpha: 0.35);
    } else if (data.runState == DispenserRunState.litersPreset) {
      runLabel = 'L  Liters';
      runFg = tokens.ink;
      runBg = tokens.good.withValues(alpha: 0.12);
      runBorder = tokens.good.withValues(alpha: 0.35);
    } else if (data.isCycleComplete) {
      runLabel = 'Complete';
      runFg = tokens.good;
      runBg = tokens.good.withValues(alpha: 0.12);
      runBorder = tokens.good.withValues(alpha: 0.35);
    } else if (espDown) {
      runLabel = 'Offline';
      runFg = tokens.inkMuted;
      runBg = tokens.line.withValues(alpha: 0.55);
      runBorder = tokens.line;
    } else {
      runLabel = 'Idle';
      runFg = tokens.inkMuted;
      runBg = tokens.line.withValues(alpha: 0.55);
      runBorder = tokens.line;
    }

    return Material(
      color: Colors.transparent,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        clipBehavior: Clip.none,
        padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
        decoration: BoxDecoration(
          color: tokens.card,
          borderRadius: BorderRadius.circular(tokens.radius20),
          border: Border.all(
            color: isSelected ? _selectedBorder : _idleBorder,
            width: isSelected ? 2.5 : 1,
          ),
          boxShadow: isSelected
              ? <BoxShadow>[
                  ...tokens.cardShadow,
                  BoxShadow(
                    color: _selectedBorder.withValues(alpha: 0.28),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                    spreadRadius: -6,
                  ),
                ]
              : tokens.cardShadow,
        ),
        child: Opacity(
          opacity: espDown ? 0.9 : 1,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _Header(data: data, tokens: tokens, onSelect: onSelect),
              InkWell(
                onTap: onSelect,
                borderRadius: BorderRadius.circular(tokens.radius12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const SizedBox(height: 10),
                    _LcdWithNozzle(
                      unitId: data.unitId,
                      runLabel: runLabel,
                      runFg: runFg,
                      runBg: runBg,
                      runBorder: runBorder,
                    ),
                    Divider(color: colors.outline, height: 1),
                    const SizedBox(height: 8),
                    _LastTransaction(data: data, tokens: tokens),
                  ],
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: notice == null
                    ? const SizedBox.shrink()
                    : Padding(
                        key: const ValueKey<String>('abort'),
                        padding: const EdgeInsets.only(top: 8),
                        child: _AbortBanner(message: notice, tokens: tokens),
                      ),
              ),
              const SizedBox(height: 8),
              IgnorePointer(
                ignoring:
                    shouldEnforceStationGuards &&
                    espDown &&
                    !data.isCycleComplete,
                child: ConfirmPaymentSheet(
                  key: ValueKey<int>(data.unitId),
                  unitId: data.unitId,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BayHelperAssigner extends ConsumerWidget {
  const BayHelperAssigner({super.key, required this.unitId});

  final int unitId;

  String _menuLabel(HelperProfile helper) {
    if (helper.assignedUnitIds.isEmpty) {
      return helper.name;
    }
    final String tags = helper.assignedUnitIds
        .map((int id) => 'U$id')
        .join(' · ');
    return '${helper.name} · $tags';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final ColorScheme colors = Theme.of(context).colorScheme;
    final List<HelperProfile> helpers = ref.watch(assignableHelpersProvider);
    final HelperProfile? assigned = helperOnUnit(
      ref.watch(helperRosterProvider),
      unitId,
    );
    final String selectedId = assigned?.id ?? '';
    final String selectedLabel = assigned == null
        ? 'Unassigned'
        : _menuLabel(assigned);

    return Container(
      height: 28,
      padding: const EdgeInsets.only(left: 8, right: 4),
      decoration: BoxDecoration(
        color: tokens.canvas,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tokens.line),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          key: ValueKey<String>('bay-helper-$unitId-$selectedId'),
          value: selectedId,
          isDense: true,
          isExpanded: true,
          padding: EdgeInsets.zero,
          alignment: AlignmentDirectional.centerStart,
          borderRadius: BorderRadius.circular(tokens.radius12),
          dropdownColor: tokens.card,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 16,
            color: colors.onSurfaceVariant,
          ),
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w600,
            fontSize: 11,
            color: colors.onSurface,
          ),
          selectedItemBuilder: (BuildContext context) {
            return <Widget>[
              _HelperMenuRow(
                label: selectedLabel,
                color: colors.onSurface,
                compact: true,
              ),
              for (final HelperProfile _ in helpers)
                _HelperMenuRow(
                  label: selectedLabel,
                  color: colors.onSurface,
                  compact: true,
                ),
            ];
          },
          items: <DropdownMenuItem<String>>[
            DropdownMenuItem<String>(
              value: '',
              child: _HelperMenuRow(
                label: 'Unassigned',
                color: colors.onSurface,
              ),
            ),
            for (final HelperProfile helper in helpers)
              DropdownMenuItem<String>(
                value: helper.id,
                child: _HelperMenuRow(
                  label: _menuLabel(helper),
                  color: colors.onSurface,
                ),
              ),
          ],
          onChanged: (String? value) {
            unawaited(_confirmAndAssign(context, ref, assigned, value));
          },
        ),
      ),
    );
  }

  Future<void> _confirmAndAssign(
    BuildContext context,
    WidgetRef ref,
    HelperProfile? assigned,
    String? value,
  ) async {
    final String? helperId = (value == null || value.isEmpty) ? null : value;
    if (helperId == assigned?.id) {
      return;
    }

    final HelperDutyPromptKind kind;
    final String helperName;
    String? currentUnitsLabel;
    bool remainingOnOtherUnits = false;
    if (helperId == null) {
      if (assigned == null) {
        return;
      }
      kind = HelperDutyPromptKind.endSession;
      helperName = assigned.name;
      remainingOnOtherUnits = assigned.assignedUnitIds.length > 1;
    } else {
      final HelperProfile? incoming = helperById(
        ref.read(helperRosterProvider),
        helperId,
      );
      if (incoming == null) {
        return;
      }
      helperName = incoming.name;
      if (incoming.assignedUnitIds.isNotEmpty &&
          !incoming.isAssignedTo(unitId)) {
        kind = HelperDutyPromptKind.addUnit;
        currentUnitsLabel = incoming.assignedUnitIds
            .map((int id) => 'Unit $id')
            .join(', ');
      } else {
        kind = HelperDutyPromptKind.startDuty;
      }
    }

    final bool confirmed = await showHelperDutyConfirmDialog(
      context: context,
      kind: kind,
      helperName: helperName,
      targetUnitId: unitId,
      currentUnitsLabel: currentUnitsLabel,
      remainingOnOtherUnits: remainingOnOtherUnits,
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    ref
        .read(shiftWorkspaceProvider.notifier)
        .assignHelperToUnit(unitId: unitId, helperId: helperId);
  }
}

class _HelperMenuRow extends StatelessWidget {
  const _HelperMenuRow({
    required this.label,
    required this.color,
    this.compact = false,
  });

  final String label;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(Icons.person_outline, size: compact ? 13 : 16, color: color),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w600,
              fontSize: compact ? 11 : 12,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _AbortBanner extends StatelessWidget {
  const _AbortBanner({required this.message, required this.tokens});

  final String message;
  final DispensrTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: tokens.warn.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(tokens.radius12),
        border: Border.all(color: tokens.warn.withValues(alpha: 0.4)),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Roboto',
          fontWeight: FontWeight.w600,
          fontSize: 11,
          color: tokens.warn,
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.data, required this.tokens, this.onSelect});

  final DispenserUnitData data;
  final DispensrTokens tokens;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool offline = data.isOffline;
    final int nextToken = tokenIdFor(
      unitId: data.unitId,
      sequence: ref.watch(
        stationControllerProvider.select(
          (StationState station) => station.sequences[data.unitId] ?? 1,
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: InkWell(
                onTap: onSelect,
                borderRadius: BorderRadius.circular(tokens.radius12),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: offline ? tokens.inkMuted : tokens.ink,
                        borderRadius: BorderRadius.circular(tokens.radius12),
                      ),
                      child: Text(
                        data.unitNumber,
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: tokens.card,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            data.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Roboto',
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: tokens.ink,
                            ),
                          ),
                          Text(
                            data.fuelType,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Roboto',
                              fontWeight: FontWeight.w500,
                              fontSize: 11,
                              color: tokens.inkMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _BayLinkIcons(unitId: data.unitId),
                    const SizedBox(width: 6),
                    DsStatusPill(
                      label: offline ? 'Offline' : 'Online',
                      foreground: offline ? tokens.inkMuted : tokens.good,
                      background: offline
                          ? tokens.line.withValues(alpha: 0.7)
                          : tokens.good.withValues(alpha: 0.12),
                      border: offline
                          ? tokens.line
                          : tokens.good.withValues(alpha: 0.3),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                DsStatusPill(
                  label: 'Token#${formatTokenNo(nextToken)}',
                  foreground: tokens.good,
                  background: tokens.good.withValues(alpha: 0.18),
                  border: tokens.good.withValues(alpha: 0.35),
                  dot: false,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        BayHelperAssigner(unitId: data.unitId),
      ],
    );
  }
}

class _BayLinkIcons extends ConsumerWidget {
  const _BayLinkIcons({required this.unitId});

  final int unitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _LinkIconButton(
          tooltip: 'Rescan Wi-Fi',
          icon: Icons.wifi_find_outlined,
          tokens: tokens,
          onPressed: () {
            ref.read(stationControllerProvider.notifier).rescanBayWifi(unitId);
          },
        ),
        const SizedBox(width: 2),
        _LinkIconButton(
          tooltip: 'Connect',
          icon: Icons.link,
          tokens: tokens,
          onPressed: () {
            ref.read(stationControllerProvider.notifier).connectUnit(unitId);
          },
        ),
      ],
    );
  }
}

class _LinkIconButton extends StatelessWidget {
  const _LinkIconButton({
    required this.tooltip,
    required this.icon,
    required this.tokens,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final DispensrTokens tokens;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: tokens.canvas,
        shape: CircleBorder(side: BorderSide(color: tokens.line)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 26,
            height: 26,
            child: Icon(icon, size: 14, color: tokens.inkMuted),
          ),
        ),
      ),
    );
  }
}

class _TestModeSwitch extends ConsumerWidget {
  const _TestModeSwitch({required this.unitId, required this.tokens});

  final int unitId;
  final DispensrTokens tokens;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DispenserBay bay = ref.watch(
      stationControllerProvider.select(
        (StationState station) => station.bay(unitId),
      ),
    );
    final bool on = bay.isTestRun;
    final bool locked = bay.isDispensing;

    return Tooltip(
      message: on
          ? 'Test fill: meters saved, stock and KPIs unchanged'
          : 'Arm a test fill (not a sale)',
      child: InkWell(
        onTap: locked && on
            ? null
            : () {
                ref
                    .read(stationControllerProvider.notifier)
                    .setUnitTestMode(unitId, enabled: !on);
              },
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: on ? tokens.warn.withValues(alpha: 0.16) : tokens.canvas,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: on ? tokens.warn.withValues(alpha: 0.45) : tokens.line,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'Test',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w700,
                  fontSize: 9,
                  color: on ? tokens.warn : tokens.inkMuted,
                ),
              ),
              const SizedBox(width: 2),
              SizedBox(
                width: 28,
                height: 16,
                child: FittedBox(
                  child: Switch(
                    value: on,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    activeThumbColor: tokens.warn,
                    onChanged: locked && on
                        ? null
                        : (bool enabled) {
                            ref
                                .read(stationControllerProvider.notifier)
                                .setUnitTestMode(unitId, enabled: enabled);
                          },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LcdWithNozzle extends ConsumerStatefulWidget {
  const _LcdWithNozzle({
    required this.unitId,
    required this.runLabel,
    required this.runFg,
    required this.runBg,
    required this.runBorder,
  });

  final int unitId;
  final String runLabel;
  final Color runFg;
  final Color runBg;
  final Color runBorder;

  @override
  ConsumerState<_LcdWithNozzle> createState() => _LcdWithNozzleState();
}

class _LcdWithNozzleState extends ConsumerState<_LcdWithNozzle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _roll;
  double _fromAmount = 0;
  double _toAmount = 0;
  double _fromLiters = 0;
  double _toLiters = 0;
  DateTime _lastSampleAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _roll = AnimationController(vsync: this);
    final LiveBayLcd live = ref.read(liveBayLcdProvider(widget.unitId));
    _fromAmount = _toAmount = live.amountPkr;
    _fromLiters = _toLiters = live.volumeLiters;
  }

  @override
  void dispose() {
    _roll.dispose();
    super.dispose();
  }

  double _shown(double from, double to) {
    if (!_roll.isAnimating) {
      return to;
    }
    return from + (to - from) * _roll.value;
  }

  void _retarget(LiveBayLcd next) {
    if (next.status == DispenserRunState.rupeesPreset ||
        next.status == DispenserRunState.litersPreset) {
      _fromAmount = _toAmount = next.amountPkr;
      _fromLiters = _toLiters = next.volumeLiters;
      _roll.stop();
      return;
    }
    final double nowAmount = _shown(_fromAmount, _toAmount);
    final double nowLiters = _shown(_fromLiters, _toLiters);
    if (nowAmount == next.amountPkr && nowLiters == next.volumeLiters) {
      return;
    }
    final DateTime now = DateTime.now();
    int ms = now.difference(_lastSampleAt).inMilliseconds;
    if (ms < 80) {
      ms = 80;
    } else if (ms > 150) {
      ms = 150;
    }
    _lastSampleAt = now;
    _fromAmount = nowAmount;
    _toAmount = next.amountPkr;
    _fromLiters = nowLiters;
    _toLiters = next.volumeLiters;
    _roll
      ..duration = Duration(milliseconds: ms)
      ..forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final LiveBayLcd live = ref.watch(liveBayLcdProvider(widget.unitId));
    ref.listen<LiveBayLcd>(liveBayLcdProvider(widget.unitId), (
      LiveBayLcd? previous,
      LiveBayLcd next,
    ) {
      if (previous == null ||
          previous.amountPkr != next.amountPkr ||
          previous.volumeLiters != next.volumeLiters) {
        _retarget(next);
      }
    });
    final String rateText = FuelFormatter.lcdAverageRate(live.rate);
    final String meterText = FuelFormatter.lcdVolume(live.meterCount);
    final bool lcdOffline = live.offline;
    final bool dispensing = live.status == DispenserRunState.dispensing;

    return AnimatedBuilder(
      animation: _roll,
      builder: (BuildContext context, Widget? child) {
        final double amountNow = _shown(_fromAmount, _toAmount);
        final double litersNow = _shown(_fromLiters, _toLiters);
        final String rupeesNow = live.status == DispenserRunState.litersPreset
            ? ''
            : live.status == DispenserRunState.rupeesPreset
            ? '${live.amountPkr.truncate()}'
            : FuelFormatter.lcdDispenserAmount(amountNow);
        final String litersNowText =
            live.status == DispenserRunState.rupeesPreset
            ? ''
            : live.status == DispenserRunState.litersPreset
            ? '${live.volumeLiters.truncate()}'
            : FuelFormatter.lcdVolume(litersNow);
        return _lcdBody(
          rupees: rupeesNow,
          liters: litersNowText,
          rate: rateText,
          meter: meterText,
          lcdOffline: lcdOffline,
          dispensing: dispensing,
        );
      },
    );
  }

  Widget _lcdBody({
    required String rupees,
    required String liters,
    required String rate,
    required String meter,
    required bool lcdOffline,
    required bool dispensing,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          height: 210,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.only(
                    right: FuelNozzleGraphic.width - 10,
                  ),
                  child: SegmentLcd.dispenser(
                    offline: lcdOffline,
                    lines: <SegmentLcdLine>[
                      SegmentLcdLine(label: 'AMOUNT', value: rupees),
                      SegmentLcdLine(label: 'LITERS', value: liters),
                      SegmentLcdLine(label: 'RATE', value: rate),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: FuelNozzleGraphic.nozzleOffset.dx,
                top: FuelNozzleGraphic.down - FuelNozzleGraphic.up,
                height: FuelNozzleGraphic.height,
                width: FuelNozzleGraphic.width,
                child: FuelNozzleGraphic(
                  isDispensing: dispensing,
                  isOffline: lcdOffline,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(right: FuelNozzleGraphic.width - 10),
          child: SizedBox(
            height: 42,
            child: SegmentLcd.meter(
              offline: lcdOffline,
              lines: <SegmentLcdLine>[
                SegmentLcdLine(label: 'METER', value: meter),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(right: FuelNozzleGraphic.width - 10),
          child: Row(
            children: <Widget>[
              DsStatusPill(
                label: widget.runLabel,
                foreground: widget.runFg,
                background: widget.runBg,
                border: widget.runBorder,
                dot: true,
              ),
              const Spacer(),
              _TestModeSwitch(
                unitId: widget.unitId,
                tokens: DispensrTokens.of(context),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LastTransaction extends StatelessWidget {
  const _LastTransaction({required this.data, required this.tokens});

  final DispenserUnitData data;
  final DispensrTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Last Transaction',
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w700,
            fontSize: 9,
            letterSpacing: 1.2,
            color: tokens.inkMuted.withValues(alpha: 0.85),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: <Widget>[
            Expanded(
              child: _Meta(
                icon: Icons.receipt_long_outlined,
                text: data.lastRupees.isEmpty ? '—' : data.lastRupees,
                tokens: tokens,
              ),
            ),
            Expanded(
              child: _Meta(
                icon: Icons.water_drop_outlined,
                text: data.lastLiters.isEmpty ? '—' : data.lastLiters,
                tokens: tokens,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: <Widget>[
            Expanded(
              child: _Meta(
                icon: Icons.schedule_outlined,
                text: data.lastTime.isEmpty ? '—' : data.lastTime,
                tokens: tokens,
              ),
            ),
            Expanded(
              child: _Meta(
                icon: Icons.person_outline,
                text: data.lastCashier.isEmpty ? '—' : data.lastCashier,
                tokens: tokens,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text, required this.tokens});

  final IconData icon;
  final String text;
  final DispensrTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 11, color: tokens.inkMuted),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w500,
              fontSize: 11,
              color: tokens.inkMuted,
            ),
          ),
        ),
      ],
    );
  }
}
