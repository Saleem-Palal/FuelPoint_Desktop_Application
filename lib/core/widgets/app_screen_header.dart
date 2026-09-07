import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/dispensr_theme.dart';

/// Dark status bar used at the top of every workspace screen.
class AppScreenHeader extends StatefulWidget {
  const AppScreenHeader({
    super.key,
    required this.title,
    required this.icon,
    this.invoiceLabel,
    this.trailingAction,
  });

  final String title;
  final IconData icon;

  /// Optional invoice pill (e.g. Inv-1021) shown after the clock.
  final String? invoiceLabel;

  /// Optional action shown after the invoice / Online pill (same 36px height).
  final Widget? trailingAction;

  @override
  State<AppScreenHeader> createState() => _AppScreenHeaderState();
}

class _AppScreenHeaderState extends State<AppScreenHeader> {
  late DateTime _now;
  Timer? _clock;

  static const List<String> _months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static const double _pillHeight = 36;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _now = DateTime.now();
      });
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final String date = '${_now.day} ${_months[_now.month - 1]} ${_now.year}';
    final String time =
        '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}:${_now.second.toString().padLeft(2, '0')}';
    final String? invoiceLabel = widget.invoiceLabel;
    final Widget? trailingAction = widget.trailingAction;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.ink,
        borderRadius: BorderRadius.circular(tokens.radius20),
        boxShadow: tokens.cardShadow,
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tokens.card.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(tokens.radius12),
            ),
            child: Icon(widget.icon, color: tokens.card, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.title,
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: tokens.card,
                    height: 1.15,
                  ),
                ),
              ),
            ),
          ),
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _HeaderMetaPill(
                      height: _pillHeight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 13,
                            color: tokens.canvas,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            date,
                            style: TextStyle(
                              fontFamily: 'Roboto',
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                              color: tokens.canvas,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              '|',
                              style: TextStyle(color: tokens.inkMuted),
                            ),
                          ),
                          Text(
                            time,
                            style: TextStyle(
                              fontFamily: 'Roboto',
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                              color: tokens.canvas,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (invoiceLabel != null) ...<Widget>[
                      const SizedBox(width: 10),
                      _HeaderMetaPill(
                        height: _pillHeight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(Icons.tag, size: 13, color: tokens.canvas),
                            const SizedBox(width: 8),
                            Text(
                              invoiceLabel,
                              style: TextStyle(
                                fontFamily: 'Roboto',
                                fontWeight: FontWeight.w500,
                                fontSize: 12,
                                color: tokens.canvas,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (trailingAction != null) ...<Widget>[
                      const SizedBox(width: 10),
                      trailingAction,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderMetaPill extends StatelessWidget {
  const _HeaderMetaPill({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tokens.card.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tokens.inkMuted.withValues(alpha: 0.35)),
      ),
      child: child,
    );
  }
}

/// Outlined header chip matching DateTime / Inv-No. pill height.
class AppHeaderActionButton extends StatelessWidget {
  const AppHeaderActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  static const double _height = 36;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final bool enabled = onPressed != null && !busy;
    return SizedBox(
      height: _height,
      child: Material(
        color: Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(color: tokens.canvas.withValues(alpha: 0.55)),
        ),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          customBorder: const StadiumBorder(),
          hoverColor: tokens.card.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (busy) ...<Widget>[
                  SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: tokens.canvas,
                    ),
                  ),
                  const SizedBox(width: 8),
                ] else if (icon != null) ...<Widget>[
                  Icon(icon, size: 13, color: tokens.canvas),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                    color: tokens.canvas,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
