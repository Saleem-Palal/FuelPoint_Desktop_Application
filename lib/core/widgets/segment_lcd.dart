import 'package:flutter/material.dart';

/// One labelled row on a 7/14-segment pump LCD.
class SegmentLcdLine {
  const SegmentLcdLine({required this.label, required this.value});

  final String label;
  final String value;
}

/// Shared pump LCD. Callers pass glass color, sizes, and layout — do not fork
/// a second LCD widget per screen.
class SegmentLcd extends StatelessWidget {
  const SegmentLcd({
    super.key,
    required this.lines,
    this.digitWidth = 0,
    this.labelSize = 13,
    this.valueSize = 22,
    this.labelWeight = FontWeight.w700,
    this.glass = sageGlass,
    this.frame = inkFrame,
    this.active = inkFrame,
    this.ghost = const Color(0x2E1C1A17),
    this.rule = const Color(0x40211C1A),
    this.bezelWidth = 3,
    this.frameRadius = 8,
    this.glassRadius = 3,
    this.glassPadding = const EdgeInsets.fromLTRB(8, 6, 8, 6),
    this.dividerAfterFirst = true,
    this.emphasizeFirst = true,
    this.expand = false,
    this.showSideNub = false,
    this.labelStroke = false,
  });

  /// Purchase stock LCDs — sage glass, compact, AMOUNT rule.
  factory SegmentLcd.purchase({
    Key? key,
    required List<SegmentLcdLine> lines,
    double labelSize = 13,
    double valueSize = 22,
    int digitWidth = 8,
    FontWeight labelWeight = FontWeight.w300,
  }) {
    return SegmentLcd(
      key: key,
      lines: lines,
      digitWidth: digitWidth,
      labelSize: labelSize,
      valueSize: valueSize,
      labelWeight: labelWeight,
      glass: sageGlass,
      bezelWidth: 3,
      dividerAfterFirst: true,
      emphasizeFirst: true,
      labelStroke: true,
    );
  }

  /// Sale dispenser head — amber glass, fills the nozzle slot.
  factory SegmentLcd.dispenser({
    Key? key,
    required List<SegmentLcdLine> lines,
    bool offline = false,
  }) {
    return SegmentLcd(
      key: key,
      lines: lines,
      digitWidth: 0,
      labelSize: 11,
      valueSize: 20,
      labelWeight: FontWeight.w400,
      glass: offlineAmber(offline),
      active: offlineActive(offline),
      ghost: offlineGhost(offline),
      bezelWidth: 6,
      frameRadius: 8,
      glassRadius: 2,
      glassPadding: const EdgeInsets.all(8),
      dividerAfterFirst: true,
      emphasizeFirst: true,
      expand: true,
      showSideNub: true,
    );
  }

  /// Sale total-meter strip under the pump LCD.
  factory SegmentLcd.meter({
    Key? key,
    required List<SegmentLcdLine> lines,
    bool offline = false,
  }) {
    return SegmentLcd(
      key: key,
      lines: lines,
      digitWidth: 0,
      labelSize: 8,
      valueSize: 13,
      labelWeight: FontWeight.w400,
      glass: offlineAmber(offline),
      active: offlineActive(offline),
      ghost: offlineGhost(offline),
      bezelWidth: 4,
      frameRadius: 8,
      glassRadius: 2,
      glassPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      dividerAfterFirst: false,
      emphasizeFirst: false,
      expand: true,
    );
  }

  /// Thermal receipt LCD block.
  factory SegmentLcd.receipt({Key? key, required List<SegmentLcdLine> lines}) {
    return SegmentLcd(
      key: key,
      lines: lines,
      digitWidth: 0,
      labelSize: 9,
      valueSize: 21,
      labelWeight: FontWeight.w400,
      glass: amberGlass,
      ghost: const Color(0x14000000),
      bezelWidth: 5,
      frameRadius: 8,
      glassRadius: 2,
      glassPadding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      dividerAfterFirst: true,
      emphasizeFirst: true,
    );
  }

  static const Color sageGlass = Color(0xFF9EA98A);
  static const Color amberGlass = Color(0xFFFA9500);
  static const Color inkFrame = Color(0xFF1C1A17);

  static Color offlineAmber(bool offline) {
    if (!offline) {
      return amberGlass;
    }
    return Color.lerp(amberGlass, inkFrame, 0.45) ?? amberGlass;
  }

  static Color offlineActive(bool offline) {
    if (!offline) {
      return inkFrame;
    }
    return inkFrame.withValues(alpha: 0.35);
  }

  static Color offlineGhost(bool offline) {
    if (!offline) {
      return const Color(0x14000000);
    }
    return inkFrame.withValues(alpha: 0.06);
  }

  final List<SegmentLcdLine> lines;
  final int digitWidth;
  final double labelSize;
  final double valueSize;
  final FontWeight labelWeight;
  final Color glass;
  final Color frame;
  final Color active;
  final Color ghost;
  final Color rule;
  final double bezelWidth;
  final double frameRadius;
  final double glassRadius;
  final EdgeInsets glassPadding;
  final bool dividerAfterFirst;
  final bool emphasizeFirst;
  final bool expand;
  final bool showSideNub;
  final bool labelStroke;

  @override
  Widget build(BuildContext context) {
    final Widget panel = Container(
      decoration: BoxDecoration(
        color: frame,
        borderRadius: BorderRadius.circular(frameRadius),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x3D000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: EdgeInsets.all(bezelWidth),
      child: Container(
        width: double.infinity,
        height: expand ? double.infinity : null,
        padding: glassPadding,
        decoration: BoxDecoration(
          color: glass,
          borderRadius: BorderRadius.circular(glassRadius),
        ),
        child: Column(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: expand
              ? MainAxisAlignment.spaceEvenly
              : MainAxisAlignment.center,
          children: <Widget>[
            for (int i = 0; i < lines.length; i++) ...<Widget>[
              if (i == 1 && dividerAfterFirst)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Divider(height: 1, thickness: 1, color: rule),
                )
              else if (i > 0 && !expand)
                const SizedBox(height: 2),
              _SegmentLcdRow(
                label: lines[i].label,
                value: lines[i].value,
                digitWidth: digitWidth,
                labelSize: labelSize,
                valueSize: emphasizeFirst && i == 0
                    ? valueSize
                    : (emphasizeFirst ? valueSize * 0.86 : valueSize),
                labelWeight: labelWeight,
                active: active,
                ghost: ghost,
                labelStroke: labelStroke,
              ),
            ],
          ],
        ),
      ),
    );

    final Widget body = expand ? SizedBox.expand(child: panel) : panel;
    if (!showSideNub) {
      return body;
    }
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Positioned.fill(child: body),
        Positioned(
          right: -5,
          top: 18,
          child: Container(
            width: 8,
            height: 36,
            decoration: BoxDecoration(
              color: frame,
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(5),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SegmentLcdRow extends StatelessWidget {
  const _SegmentLcdRow({
    required this.label,
    required this.value,
    required this.digitWidth,
    required this.labelSize,
    required this.valueSize,
    required this.labelWeight,
    required this.active,
    required this.ghost,
    required this.labelStroke,
  });

  final String label;
  final String value;
  final int digitWidth;
  final double labelSize;
  final double valueSize;
  final FontWeight labelWeight;
  final Color active;
  final Color ghost;
  final bool labelStroke;

  @override
  Widget build(BuildContext context) {
    final TextStyle labelStyle = TextStyle(
      fontFamily: 'DSEG14ClassicMini',
      fontWeight: labelWeight,
      fontSize: labelSize,
      height: 1.0,
      color: active,
    );
    final TextStyle valueStyle = TextStyle(
      fontFamily: 'DSEG7Classic',
      fontSize: valueSize,
      height: 1.0,
      color: active,
    );
    final String labelGhost = List<String>.filled(label.length, '~').join();
    final String live = digitWidth > 0 ? value.padLeft(digitWidth) : value;
    final String valueGhost = live.replaceAll(RegExp(r'[0-9 ]'), '8');

    return Row(
      children: <Widget>[
        Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Text(labelGhost, style: labelStyle.copyWith(color: ghost)),
            if (labelStroke)
              Transform.translate(
                offset: const Offset(0.55, 0),
                child: Text(label, style: labelStyle),
              ),
            Text(label, style: labelStyle),
          ],
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            clipBehavior: Clip.none,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerRight,
              children: <Widget>[
                Text(
                  valueGhost,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  style: valueStyle.copyWith(color: ghost),
                ),
                Text(
                  live,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  style: valueStyle,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
