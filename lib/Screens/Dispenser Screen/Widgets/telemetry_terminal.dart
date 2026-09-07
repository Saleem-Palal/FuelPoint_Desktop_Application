import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/dispensr_theme.dart';
import '../../../features/station/domain/dispenser_models.dart';
import '../../../features/station/domain/dispenser_monitor_models.dart';

class TelemetryTerminal extends StatefulWidget {
  const TelemetryTerminal({
    super.key,
    required this.monitor,
    required this.onUnitFilter,
    required this.onKindFilter,
    required this.onPause,
    required this.onClear,
  });

  final DispenserMonitorState monitor;
  final ValueChanged<int?> onUnitFilter;
  final ValueChanged<DispenserWireKind?> onKindFilter;
  final ValueChanged<bool> onPause;
  final VoidCallback onClear;

  @override
  State<TelemetryTerminal> createState() => _TelemetryTerminalState();
}

class _TelemetryTerminalState extends State<TelemetryTerminal> {
  final ScrollController _scroll = ScrollController();
  static final DateFormat _clock = DateFormat('HH:mm:ss.SSS');

  @override
  void didUpdateWidget(covariant TelemetryTerminal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.monitor.paused) {
      return;
    }
    if (widget.monitor.frames.length == oldWidget.monitor.frames.length) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) {
        return;
      }
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final List<DispenserWireFrame> lines = widget.monitor.visibleFrames;

    return Container(
      decoration: BoxDecoration(
        color: tokens.ink,
        borderRadius: BorderRadius.circular(tokens.radius20),
        boxShadow: tokens.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.terminal,
                      size: 16,
                      color: tokens.card.withValues(alpha: 0.85),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'LIVE TELEMETRY STREAM',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        letterSpacing: 0.8,
                        color: tokens.card,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${lines.length} frames',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 11,
                        color: tokens.canvas.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    _FilterChip(
                      label: 'All Units',
                      selected: widget.monitor.unitFilter == null,
                      onTap: () => widget.onUnitFilter(null),
                    ),
                    for (final int unitId in dispenserUnitIds)
                      _FilterChip(
                        label: 'Unit $unitId',
                        selected: widget.monitor.unitFilter == unitId,
                        onTap: () => widget.onUnitFilter(unitId),
                      ),
                    _FilterChip(
                      label: 'All types',
                      selected: widget.monitor.kindFilter == null,
                      onTap: () => widget.onKindFilter(null),
                    ),
                    for (final DispenserWireKind kind
                        in DispenserWireKind.values)
                      _FilterChip(
                        label: kind.label,
                        selected: widget.monitor.kindFilter == kind,
                        onTap: () => widget.onKindFilter(kind),
                      ),
                    AppHeaderLikeButton(
                      label: widget.monitor.paused
                          ? 'Resume Stream'
                          : 'Pause Stream',
                      icon: widget.monitor.paused
                          ? Icons.play_arrow
                          : Icons.pause,
                      onPressed: () => widget.onPause(!widget.monitor.paused),
                    ),
                    AppHeaderLikeButton(
                      label: 'Clear Log',
                      icon: Icons.delete_outline,
                      onPressed: widget.onClear,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(height: 1, color: tokens.inkMuted.withValues(alpha: 0.35)),
          Expanded(
            child: lines.isEmpty
                ? Center(
                    child: Text(
                      widget.monitor.paused
                          ? 'Stream paused.'
                          : 'Waiting for WebSocket frames…',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 13,
                        color: tokens.canvas.withValues(alpha: 0.55),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    itemCount: lines.length,
                    itemBuilder: (BuildContext context, int index) {
                      return _LogLine(frame: lines[index], clock: _clock);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Material(
      color: selected
          ? tokens.coral.withValues(alpha: 0.22)
          : tokens.card.withValues(alpha: 0.08),
      shape: StadiumBorder(
        side: BorderSide(
          color: selected
              ? tokens.coral.withValues(alpha: 0.7)
              : tokens.inkMuted.withValues(alpha: 0.35),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        hoverColor: tokens.card.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w600,
              fontSize: 11,
              color: tokens.canvas,
            ),
          ),
        ),
      ),
    );
  }
}

class AppHeaderLikeButton extends StatelessWidget {
  const AppHeaderLikeButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Material(
      color: Colors.transparent,
      shape: StadiumBorder(
        side: BorderSide(color: tokens.canvas.withValues(alpha: 0.45)),
      ),
      child: InkWell(
        onTap: onPressed,
        customBorder: const StadiumBorder(),
        hoverColor: tokens.card.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 13, color: tokens.canvas),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w500,
                  fontSize: 11,
                  color: tokens.canvas,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.frame, required this.clock});

  final DispenserWireFrame frame;
  final DateFormat clock;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final Color kindColor = switch (frame.kind) {
      DispenserWireKind.telemetry => const Color(0xFF7DCE9A),
      DispenserWireKind.command => const Color(0xFFF0B35C),
      DispenserWireKind.error => tokens.bad,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SelectionArea(
        child: Text.rich(
          TextSpan(
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 12,
              height: 1.45,
              color: tokens.canvas.withValues(alpha: 0.92),
            ),
            children: <InlineSpan>[
              TextSpan(
                text: clock.format(frame.at),
                style: TextStyle(color: tokens.canvas.withValues(alpha: 0.45)),
              ),
              TextSpan(
                text: '  ${frame.directionTag}  ',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: frame.outbound
                      ? tokens.coral
                      : const Color(0xFF7DCE9A),
                ),
              ),
              TextSpan(
                text: '${frame.unitTag}  ',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              TextSpan(
                text: '[${frame.kind.name.toUpperCase()}]  ',
                style: TextStyle(fontWeight: FontWeight.w700, color: kindColor),
              ),
              TextSpan(text: frame.payload),
            ],
          ),
        ),
      ),
    );
  }
}
