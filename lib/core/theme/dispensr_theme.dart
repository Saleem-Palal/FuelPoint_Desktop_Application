import 'package:flutter/material.dart';

/// FuelPoint style-guide tokens. Visual source of truth for every screen.
@immutable
class DispensrTokens extends ThemeExtension<DispensrTokens> {
  const DispensrTokens({
    required this.blush,
    required this.canvas,
    required this.coral,
    required this.coralPressed,
    required this.ink,
    required this.inkMuted,
    required this.card,
    required this.line,
    required this.good,
    required this.warn,
    required this.bad,
    required this.radius12,
    required this.radius20,
    required this.radius28,
    required this.cardShadow,
    required this.coralShadow,
  });

  final Color blush;
  final Color canvas;
  final Color coral;
  final Color coralPressed;
  final Color ink;
  final Color inkMuted;
  final Color card;
  final Color line;
  final Color good;
  final Color warn;
  final Color bad;
  final double radius12;
  final double radius20;
  final double radius28;
  final List<BoxShadow> cardShadow;
  final List<BoxShadow> coralShadow;

  static const DispensrTokens standard = DispensrTokens(
    blush: Color(0xFFF7DCD2),
    canvas: Color(0xFFFBEDE6),
    coral: Color(0xFFF0785C),
    coralPressed: Color(0xFFD65E42),
    ink: Color(0xFF211C1A),
    inkMuted: Color(0xFF6F6560),
    card: Color(0xFFFFFFFF),
    line: Color(0xFFEAD9D0),
    good: Color(0xFF3E8E5B),
    warn: Color(0xFFC98A2A),
    bad: Color(0xFFC24A3D),
    radius12: 8,
    radius20: 10,
    radius28: 10,
    cardShadow: <BoxShadow>[
      BoxShadow(color: Color(0x0A211C1A), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(
        color: Color(0x2E211C1A),
        blurRadius: 24,
        offset: Offset(0, 8),
        spreadRadius: -12,
      ),
    ],
    coralShadow: <BoxShadow>[
      BoxShadow(
        color: Color(0x8CF0785C),
        blurRadius: 24,
        offset: Offset(0, 10),
        spreadRadius: -8,
      ),
    ],
  );

  static DispensrTokens of(BuildContext context) {
    final DispensrTokens? tokens = Theme.of(
      context,
    ).extension<DispensrTokens>();
    if (tokens != null) {
      return tokens;
    }
    return DispensrTokens.standard;
  }

  @override
  DispensrTokens copyWith({
    Color? blush,
    Color? canvas,
    Color? coral,
    Color? coralPressed,
    Color? ink,
    Color? inkMuted,
    Color? card,
    Color? line,
    Color? good,
    Color? warn,
    Color? bad,
    double? radius12,
    double? radius20,
    double? radius28,
    List<BoxShadow>? cardShadow,
    List<BoxShadow>? coralShadow,
  }) {
    return DispensrTokens(
      blush: blush ?? this.blush,
      canvas: canvas ?? this.canvas,
      coral: coral ?? this.coral,
      coralPressed: coralPressed ?? this.coralPressed,
      ink: ink ?? this.ink,
      inkMuted: inkMuted ?? this.inkMuted,
      card: card ?? this.card,
      line: line ?? this.line,
      good: good ?? this.good,
      warn: warn ?? this.warn,
      bad: bad ?? this.bad,
      radius12: radius12 ?? this.radius12,
      radius20: radius20 ?? this.radius20,
      radius28: radius28 ?? this.radius28,
      cardShadow: cardShadow ?? this.cardShadow,
      coralShadow: coralShadow ?? this.coralShadow,
    );
  }

  @override
  DispensrTokens lerp(ThemeExtension<DispensrTokens>? other, double t) {
    if (other is! DispensrTokens) {
      return this;
    }
    return DispensrTokens(
      blush: Color.lerp(blush, other.blush, t) ?? blush,
      canvas: Color.lerp(canvas, other.canvas, t) ?? canvas,
      coral: Color.lerp(coral, other.coral, t) ?? coral,
      coralPressed:
          Color.lerp(coralPressed, other.coralPressed, t) ?? coralPressed,
      ink: Color.lerp(ink, other.ink, t) ?? ink,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t) ?? inkMuted,
      card: Color.lerp(card, other.card, t) ?? card,
      line: Color.lerp(line, other.line, t) ?? line,
      good: Color.lerp(good, other.good, t) ?? good,
      warn: Color.lerp(warn, other.warn, t) ?? warn,
      bad: Color.lerp(bad, other.bad, t) ?? bad,
      radius12: lerpDouble(radius12, other.radius12, t),
      radius20: lerpDouble(radius20, other.radius20, t),
      radius28: lerpDouble(radius28, other.radius28, t),
      cardShadow: t < 0.5 ? cardShadow : other.cardShadow,
      coralShadow: t < 0.5 ? coralShadow : other.coralShadow,
    );
  }

  static double lerpDouble(double a, double b, double t) {
    return a + (b - a) * t;
  }
}

ThemeData buildDispensrTheme() {
  const DispensrTokens tokens = DispensrTokens.standard;
  const String fontFamily = 'Roboto';

  final ColorScheme colorScheme = ColorScheme.light(
    primary: tokens.coral,
    onPrimary: tokens.card,
    primaryContainer: const Color(0x1AF0785C),
    onPrimaryContainer: tokens.coralPressed,
    secondary: tokens.ink,
    onSecondary: tokens.card,
    tertiary: tokens.good,
    onTertiary: tokens.card,
    error: tokens.bad,
    onError: tokens.card,
    surface: tokens.card,
    onSurface: tokens.ink,
    onSurfaceVariant: tokens.inkMuted,
    outline: tokens.line,
    outlineVariant: tokens.line,
    surfaceContainerLowest: tokens.canvas,
    surfaceContainerLow: tokens.blush,
    surfaceContainerHighest: tokens.canvas,
  );

  final TextTheme textTheme = ThemeData.light().textTheme.apply(
    fontFamily: fontFamily,
    bodyColor: tokens.ink,
    displayColor: tokens.ink,
  );

  return ThemeData(
    useMaterial3: true,
    fontFamily: fontFamily,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: tokens.canvas,
    textTheme: textTheme,
    splashFactory: InkRipple.splashFactory,
    extensions: const <ThemeExtension<dynamic>>[DispensrTokens.standard],
    dividerColor: tokens.line,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tokens.canvas,
      hintStyle: TextStyle(
        fontFamily: fontFamily,
        color: tokens.inkMuted.withValues(alpha: 0.7),
        fontSize: 14,
      ),
      labelStyle: TextStyle(
        fontFamily: fontFamily,
        color: tokens.inkMuted,
        fontSize: 12,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.radius12),
        borderSide: BorderSide(color: tokens.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.radius12),
        borderSide: BorderSide(color: tokens.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.radius12),
        borderSide: BorderSide(color: tokens.coral, width: 1.4),
      ),
    ),
  );
}

enum DsPillVariant { coral, ink, outline, danger, muted, good }

class DsPillButton extends StatelessWidget {
  const DsPillButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = DsPillVariant.coral,
    this.icon,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final DsPillVariant variant;
  final IconData? icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final bool enabled = onPressed != null;

    late final Color background;
    late final Color foreground;
    late final BorderSide border;
    late final List<BoxShadow> shadows;

    switch (variant) {
      case DsPillVariant.coral:
        background = enabled ? tokens.coral : tokens.line;
        foreground = enabled ? tokens.card : tokens.inkMuted;
        border = BorderSide.none;
        shadows = enabled ? tokens.coralShadow : const <BoxShadow>[];
      case DsPillVariant.ink:
        background = tokens.ink;
        foreground = tokens.card;
        border = BorderSide.none;
        shadows = const <BoxShadow>[];
      case DsPillVariant.outline:
        background = tokens.card;
        foreground = tokens.ink;
        border = BorderSide(color: tokens.ink);
        shadows = const <BoxShadow>[];
      case DsPillVariant.danger:
        background = tokens.bad;
        foreground = tokens.card;
        border = BorderSide.none;
        shadows = const <BoxShadow>[];
      case DsPillVariant.muted:
        background = tokens.line;
        foreground = tokens.inkMuted;
        border = BorderSide.none;
        shadows = const <BoxShadow>[];
      case DsPillVariant.good:
        background = tokens.good;
        foreground = tokens.card;
        border = BorderSide.none;
        shadows = const <BoxShadow>[];
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: shadows,
      ),
      child: Material(
        color: background,
        shape: StadiumBorder(side: border),
        child: InkWell(
          onTap: onPressed,
          customBorder: const StadiumBorder(),
          hoverColor: tokens.ink.withValues(alpha: 0.06),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 14,
              vertical: compact ? 8 : 10,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Icon(icon, size: compact ? 14 : 16, color: foreground),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w600,
                      fontSize: compact ? 12 : 13,
                      letterSpacing: 0.6,
                      color: foreground,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DsStatusPill extends StatelessWidget {
  const DsStatusPill({
    super.key,
    required this.label,
    required this.foreground,
    required this.background,
    this.border,
    this.dot = true,
  });

  final String label;
  final Color foreground;
  final Color background;
  final Color? border;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border ?? foreground.withValues(alpha: 0.3)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (dot) ...<Widget>[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: foreground,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w600,
                fontSize: 10,
                letterSpacing: 0.8,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
