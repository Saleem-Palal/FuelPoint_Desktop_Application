import 'package:flutter/material.dart';

import '../../../../core/theme/dispensr_theme.dart';
import '../../../../core/widgets/segment_lcd.dart';
import '../../../../features/station/domain/dispenser_models.dart';
import 'confirm_payment_dialog.dart';
import 'fuel_nozzle_graphic.dart';
import 'unit_link_dialog.dart';

class DispenserUnitData {
  const DispenserUnitData({
    required this.unitId,
    required this.unitNumber,
    required this.name,
    required this.fuelType,
    required this.online,
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

  factory DispenserUnitData.fromBay(DispenserBay bay) {
    return DispenserUnitData(
      unitId: bay.unitId,
      unitNumber: bay.unitId.toString().padLeft(2, '0'),
      name: bay.name,
      fuelType: bay.fuelType,
      online: bay.isOnline,
      runState: bay.status,
      rupees: bay.amountPkr.toStringAsFixed(2),
      liters: bay.volumeLiters.toStringAsFixed(2),
      ratePerLitre: bay.rate.toStringAsFixed(2),
      lastRupees: bay.lastRupees,
      lastLiters: bay.lastLiters,
      lastTime: bay.lastTime,
      lastCashier: bay.lastCashier,
      totalMeter: _totalMeterFor(bay.unitId),
      volumeLiters: bay.volumeLiters,
    );
  }

  static String _totalMeterFor(int unitId) {
    const List<String> meters = <String>[
      '13452342.143',
      '13454719.863',
      '13450108.004',
      '13449880.550',
      '13451200.210',
    ];
    if (unitId >= 1 && unitId <= meters.length) {
      return meters[unitId - 1];
    }
    return '0.000';
  }

  final int unitId;
  final String unitNumber;
  final String name;
  final String fuelType;
  final bool online;
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
  bool get isOffline => runState == DispenserRunState.offline || !online;
  bool get isCycleComplete => runState == DispenserRunState.cycleComplete;
  bool get canConfirmPayment =>
      !isOffline &&
      isCycleComplete &&
      volumeLiters >= DispenserBay.zeroVolumeEpsilon;
}

/// One dispenser card. Instantiate once per unit with different [data].
class DispenserUnitsWidget extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool offline = data.isOffline;
    final bool dispensing = data.isDispensing;
    final String? notice = abortNotice;

    final String runLabel;
    final Color runFg;
    final Color runBg;
    final Color runBorder;
    if (offline) {
      runLabel = 'Offline';
      runFg = tokens.inkMuted;
      runBg = tokens.line.withValues(alpha: 0.55);
      runBorder = tokens.line;
    } else if (dispensing) {
      runLabel = 'Dispensing';
      runFg = tokens.coralPressed;
      runBg = tokens.coral.withValues(alpha: 0.12);
      runBorder = tokens.coral.withValues(alpha: 0.35);
    } else if (data.isCycleComplete) {
      runLabel = 'Complete';
      runFg = tokens.good;
      runBg = tokens.good.withValues(alpha: 0.12);
      runBorder = tokens.good.withValues(alpha: 0.35);
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
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
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
          opacity: offline ? 0.9 : 1,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              InkWell(
                onTap: onSelect,
                borderRadius: BorderRadius.circular(tokens.radius12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _Header(data: data, tokens: tokens),
                    const SizedBox(height: 10),
                    _LcdWithNozzle(
                      data: data,
                      runLabel: runLabel,
                      runFg: runFg,
                      runBg: runBg,
                      runBorder: runBorder,
                    ),
                    Divider(color: colors.outline, height: 1),
                    const SizedBox(height: 10),
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
              ConfirmPaymentSheet(unitId: data.unitId),
            ],
          ),
        ),
      ),
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

class _Header extends StatelessWidget {
  const _Header({required this.data, required this.tokens});

  final DispenserUnitData data;
  final DispensrTokens tokens;

  @override
  Widget build(BuildContext context) {
    final bool offline = data.isOffline;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
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
        DsStatusPill(
          label: offline ? 'Offline' : 'Online',
          foreground: offline ? tokens.inkMuted : tokens.good,
          background: offline
              ? tokens.line.withValues(alpha: 0.7)
              : tokens.good.withValues(alpha: 0.12),
          border: offline ? tokens.line : tokens.good.withValues(alpha: 0.3),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Unit link',
          onPressed: () {
            showUnitLinkDialog(context: context, unitId: data.unitId);
          },
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          icon: Icon(Icons.settings_outlined, size: 18, color: tokens.inkMuted),
        ),
      ],
    );
  }
}

class _LcdWithNozzle extends StatelessWidget {
  const _LcdWithNozzle({
    required this.data,
    required this.runLabel,
    required this.runFg,
    required this.runBg,
    required this.runBorder,
  });

  final DispenserUnitData data;
  final String runLabel;
  final Color runFg;
  final Color runBg;
  final Color runBorder;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        SizedBox(
          height: FuelNozzleGraphic.slotHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.only(right: 22),
                  child: SegmentLcd.dispenser(
                    offline: data.isOffline,
                    lines: <SegmentLcdLine>[
                      SegmentLcdLine(label: 'AMOUNT', value: data.rupees),
                      SegmentLcdLine(label: 'LITERS', value: data.liters),
                      SegmentLcdLine(label: 'RATE', value: data.ratePerLitre),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: -15,
                top: 0,
                bottom: 15,
                width: FuelNozzleGraphic.slotWidth,
                child: FuelNozzleGraphic(
                  isDispensing: data.isDispensing,
                  isOffline: data.isOffline,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(right: 22),
          child: SizedBox(
            height: 36,
            child: SegmentLcd.meter(
              offline: data.isOffline,
              lines: <SegmentLcdLine>[
                SegmentLcdLine(label: 'METER', value: data.totalMeter),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        DsStatusPill(
          label: runLabel,
          foreground: runFg,
          background: runBg,
          border: runBorder,
          dot: true,
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
                text: data.lastRupees,
                tokens: tokens,
              ),
            ),
            Expanded(
              child: _Meta(
                icon: Icons.water_drop_outlined,
                text: data.lastLiters,
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
                text: data.lastTime,
                tokens: tokens,
              ),
            ),
            Expanded(
              child: _Meta(
                icon: Icons.person_outline,
                text: data.lastCashier,
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
