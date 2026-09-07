import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/dispensr_theme.dart';

String _formatDateOnly(DateTime time) {
  final String day = time.day.toString().padLeft(2, '0');
  final String month = time.month.toString().padLeft(2, '0');
  return '$day-$month-${time.year}';
}

String _formatRange(DateTime start, DateTime end) {
  return '${_formatDateOnly(start)} → ${_formatDateOnly(end)}';
}

/// Result of the shared date-range popup. `null` from [DateRangeSelector.show]
/// means the user dismissed without changing anything.
class DateRangeSelection {
  const DateRangeSelection.apply(this.range) : cleared = false;

  const DateRangeSelection.clear() : range = null, cleared = true;

  final DateTimeRange? range;
  final bool cleared;

  DateTimeRange? get value => cleared ? null : range;
}

/// Shared date-range popup used by ledger filters and any other workspace.
class DateRangeSelector {
  DateRangeSelector._();

  static Future<DateRangeSelection?> show(
    BuildContext context, {
    DateTimeRange? initial,
    DateTime? firstDate,
    DateTime? lastDate,
    String title = 'Date Range',
  }) {
    final DateTime now = DateTime.now();
    return showDialog<DateRangeSelection>(
      context: context,
      builder: (BuildContext context) {
        return _DateRangeDialog(
          title: title,
          initial: initial,
          firstDate: firstDate ?? DateTime(2024),
          lastDate: lastDate ?? now.add(const Duration(days: 1)),
        );
      },
    );
  }
}

/// Compact trigger that opens [DateRangeSelector] and reports Apply / Clear.
class DateRangeFilterButton extends StatelessWidget {
  const DateRangeFilterButton({
    super.key,
    required this.range,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.emptyLabel = 'All dates',
  });

  final DateTimeRange? range;
  final ValueChanged<DateTimeRange?> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final String emptyLabel;

  Future<void> _open(BuildContext context) async {
    final DateRangeSelection? picked = await DateRangeSelector.show(
      context,
      initial: range,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (!context.mounted || picked == null) {
      return;
    }
    onChanged(picked.value);
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final DateTimeRange? current = range;
    final bool active = current != null;
    return Material(
      color: active ? tokens.coral.withValues(alpha: 0.12) : tokens.canvas,
      shape: StadiumBorder(
        side: BorderSide(color: active ? tokens.coral : tokens.line),
      ),
      child: InkWell(
        onTap: () {
          unawaited(_open(context));
        },
        customBorder: const StadiumBorder(),
        hoverColor: tokens.ink.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.date_range_outlined,
                size: 15,
                color: active ? tokens.coralPressed : tokens.inkMuted,
              ),
              const SizedBox(width: 8),
              Text(
                active ? _formatRange(current.start, current.end) : emptyLabel,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: active ? tokens.coralPressed : tokens.ink,
                ),
              ),
              if (active)
                InkWell(
                  onTap: () => onChanged(null),
                  customBorder: const CircleBorder(),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(Icons.close, size: 14, color: tokens.inkMuted),
                  ),
                )
              else
                const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateRangeDialog extends StatefulWidget {
  const _DateRangeDialog({
    required this.title,
    required this.initial,
    required this.firstDate,
    required this.lastDate,
  });

  final String title;
  final DateTimeRange? initial;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<_DateRangeDialog> createState() => _DateRangeDialogState();
}

class _DateRangeDialogState extends State<_DateRangeDialog> {
  late DateTime _from;
  late DateTime _to;

  @override
  void initState() {
    super.initState();
    final DateTime now = DateTime.now();
    _from = _dateOnly(
      widget.initial?.start ?? DateTime(now.year, now.month, 1),
    );
    _to = _dateOnly(widget.initial?.end ?? now);
  }

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  Future<void> _pick({required bool isStart}) async {
    final DateTime initial = isStart ? _from : _to;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: widget.firstDate,
      lastDate: widget.lastDate,
      helpText: isStart ? 'From date' : 'To date',
    );
    if (picked == null) {
      return;
    }
    setState(() {
      if (isStart) {
        _from = _dateOnly(picked);
        if (_from.isAfter(_to)) {
          _to = _from;
        }
      } else {
        _to = _dateOnly(picked);
        if (_to.isBefore(_from)) {
          _from = _to;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Dialog(
      backgroundColor: tokens.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius20),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    widget.title,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: tokens.ink,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _DateField(
                label: 'From',
                value: _formatDateOnly(_from),
                onTap: () {
                  unawaited(_pick(isStart: true));
                },
              ),
              const SizedBox(height: 10),
              _DateField(
                label: 'To',
                value: _formatDateOnly(_to),
                onTap: () {
                  unawaited(_pick(isStart: false));
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: DsPillButton(
                      label: 'Clear',
                      variant: DsPillVariant.outline,
                      onPressed: () {
                        Navigator.of(
                          context,
                        ).pop(const DateRangeSelection.clear());
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DsPillButton(
                      label: 'Apply',
                      onPressed: () {
                        Navigator.of(context).pop(
                          DateRangeSelection.apply(
                            DateTimeRange(start: _from, end: _to),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w700,
            fontSize: 9,
            letterSpacing: 0.8,
            color: tokens.inkMuted,
          ),
        ),
        const SizedBox(height: 6),
        Material(
          color: tokens.canvas,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radius12),
            side: BorderSide(color: tokens.line),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(tokens.radius12),
            hoverColor: tokens.ink.withValues(alpha: 0.05),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: <Widget>[
                  Text(
                    value,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: tokens.ink,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 16,
                    color: tokens.inkMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
