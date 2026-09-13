import 'package:flutter/material.dart';

/// One labelled row on a 7/14-segment pump LCD.
class SegmentLcdLine {
  const SegmentLcdLine({
    required this.label,
    required this.value,
    this.placeholder,
    this.valueSize,
  });

  final String label;
  final String value;

  /// Unlit 7-segment mask painted behind [value], e.g. `888888.88`.
  final String? placeholder;

  /// Overrides the panel value size for this row only.
  final double? valueSize;
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
    this.valueUnlit,
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
    this.gapBeforeLast = 0,
  });

  static const String saleAmountMask = '888888.88';
  static const String saleMeterMask = '88888888.888';

  /// Pump-head type. Receipt LCD uses these same sizes.
  static const double dispenserLabelSize = 11;
  static const double dispenserValueSize = 36;
  static const double dispenserAmountSize = 46;
  static const double dispenserLitersSize = 42;
  static const double dispenserRateSize = 20;

  static double? _dispenserValueSize(String label) {
    switch (label.toUpperCase()) {
      case 'AMOUNT':
        return dispenserAmountSize;
      case 'LITERS':
        return dispenserLitersSize;
      case 'RATE':
        return dispenserRateSize;
      default:
        return null;
    }
  }

  static List<SegmentLcdLine> _saleReadoutLines(List<SegmentLcdLine> lines) {
    return <SegmentLcdLine>[
      for (final SegmentLcdLine line in lines)
        SegmentLcdLine(
          label: line.label,
          value: line.value,
          placeholder: line.placeholder ?? saleAmountMask,
          valueSize: line.valueSize ?? _dispenserValueSize(line.label),
        ),
    ];
  }

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
      expand: true,
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
      lines: _saleReadoutLines(lines),
      digitWidth: 0,
      labelSize: dispenserLabelSize,
      valueSize: dispenserValueSize,
      labelWeight: FontWeight.w400,
      glass: offlineAmber(offline),
      active: offlineActive(offline),
      ghost: offlineGhost(offline),
      valueUnlit: offlineUnlitDigits(offline),
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
      lines: <SegmentLcdLine>[
        for (final SegmentLcdLine line in lines)
          SegmentLcdLine(
            label: line.label,
            value: line.value,
            placeholder: line.placeholder ?? saleMeterMask,
            valueSize: line.valueSize,
          ),
      ],
      digitWidth: 0,
      labelSize: 8,
      valueSize: 20,
      labelWeight: FontWeight.w400,
      glass: offlineAmber(offline),
      active: offlineActive(offline),
      ghost: offlineGhost(offline),
      valueUnlit: offlineUnlitDigits(offline),
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
  ///
  /// [forPrint] uses white glass and black digits so a 1-bit thermal
  /// head does not turn the amber panel into a solid black rectangle.
  factory SegmentLcd.receipt({
    Key? key,
    required List<SegmentLcdLine> lines,
    bool forPrint = false,
  }) {
    return SegmentLcd(
      key: key,
      lines: _saleReadoutLines(lines),
      digitWidth: 0,
      labelSize: dispenserLabelSize,
      valueSize: dispenserValueSize,
      labelWeight: FontWeight.w400,
      glass: forPrint ? const Color(0xFFFFFFFF) : amberGlass,
      ghost: forPrint ? const Color(0x1A000000) : const Color(0x14000000),
      bezelWidth: 5,
      frameRadius: 8,
      glassRadius: 2,
      glassPadding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      dividerAfterFirst: true,
      emphasizeFirst: true,
      gapBeforeLast: 8,
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

  static Color offlineUnlitDigits(bool offline) {
    if (!offline) {
      return const Color(0x1A000000);
    }
    return inkFrame.withValues(alpha: 0.08);
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
  final Color? valueUnlit;
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
  final double gapBeforeLast;

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
              if (i == lines.length - 1 && gapBeforeLast > 0)
                SizedBox(height: gapBeforeLast),
              _SegmentLcdRow(
                label: lines[i].label,
                value: lines[i].value,
                placeholder: lines[i].placeholder,
                digitWidth: digitWidth,
                labelSize: labelSize,
                valueSize:
                    lines[i].valueSize ??
                    (emphasizeFirst && i == 0
                        ? valueSize
                        : (emphasizeFirst ? valueSize * 0.86 : valueSize)),
                labelWeight: labelWeight,
                active: active,
                ghost: ghost,
                valueUnlit: valueUnlit ?? ghost,
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
    required this.placeholder,
    required this.digitWidth,
    required this.labelSize,
    required this.valueSize,
    required this.labelWeight,
    required this.active,
    required this.ghost,
    required this.valueUnlit,
    required this.labelStroke,
  });

  final String label;
  final String value;
  final String? placeholder;
  final int digitWidth;
  final double labelSize;
  final double valueSize;
  final FontWeight labelWeight;
  final Color active;
  final Color ghost;
  final Color valueUnlit;
  final bool labelStroke;

  String get _liveDigits {
    if (digitWidth > 0) {
      return value.padLeft(digitWidth);
    }
    return value;
  }

  String get _unlitMask {
    final String? mask = placeholder;
    if (mask != null && mask.isNotEmpty) {
      return mask;
    }
    return _liveDigits.replaceAll(RegExp(r'[0-9 ]'), '8');
  }

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
    final String live = _liveDigits;
    final String unlit = _unlitMask;

    return Row(
      children: <Widget>[
        Flexible(
          flex: 0,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Stack(
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
          ),
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
                  unlit,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  style: valueStyle.copyWith(color: valueUnlit),
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
