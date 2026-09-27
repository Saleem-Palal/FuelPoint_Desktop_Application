import 'package:flutter/material.dart';

import '../constants.dart';
import '../theme/dispensr_theme.dart';

Future<void> showReleaseNotesDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return const ReleaseNotesDialog();
    },
  );
}

class ReleaseNotesDialog extends StatelessWidget {
  const ReleaseNotesDialog({super.key});

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
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      title: Row(
        children: <Widget>[
          Icon(Icons.new_releases_outlined, size: 20, color: tokens.coral),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'What\'s new in ${AppBrand.versionLabel}',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: tokens.ink,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: const ReleaseNotesList(),
        ),
      ),
      actions: <Widget>[
        DsPillButton(
          label: 'Close',
          variant: DsPillVariant.outline,
          compact: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class ReleaseNotesList extends StatefulWidget {
  const ReleaseNotesList({
    super.key,
    this.dense = false,
    this.visibleLineCount,
  });

  final bool dense;

  /// When set, the list is clipped to this many note-lines and scrolls.
  final int? visibleLineCount;

  static const int settingsVisibleLines = 5;

  @override
  State<ReleaseNotesList> createState() => _ReleaseNotesListState();
}

class _ReleaseNotesListState extends State<ReleaseNotesList> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  double get _fontSize => widget.dense ? 12 : 13;

  double get _lineHeight => 1.35;

  double get _gap => widget.dense ? 6 : 8;

  double get _viewportHeight {
    final int lines = widget.visibleLineCount ?? 0;
    if (lines <= 0) {
      return 0;
    }
    return lines * _fontSize * _lineHeight + (lines - 1) * _gap;
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final List<_ReleaseNotesRow> rows = _flatten(AppBrand.releaseNoteUpdates);
    final Widget list = Scrollbar(
      controller: _scroll,
      thumbVisibility: widget.visibleLineCount != null,
      child: ListView.builder(
        controller: _scroll,
        primary: false,
        shrinkWrap: widget.visibleLineCount == null,
        padding: EdgeInsets.zero,
        itemCount: rows.length,
        itemBuilder: (BuildContext context, int index) {
          return _buildRow(tokens, rows[index], index == rows.length - 1);
        },
      ),
    );

    if (widget.visibleLineCount == null) {
      return list;
    }
    return SizedBox(height: _viewportHeight, child: list);
  }

  Widget _buildRow(
    DispensrTokens tokens,
    _ReleaseNotesRow row,
    bool isLast,
  ) {
    final double bottom = isLast ? 0 : _gap;
    switch (row) {
      case _ReleaseNotesHeader(:final String version):
        return Padding(
          padding: EdgeInsets.only(
            top: row.isFirst ? 0 : _gap + 4,
            bottom: bottom,
          ),
          child: Text(
            'Update $version',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w700,
              fontSize: _fontSize,
              height: _lineHeight,
              letterSpacing: 0.2,
              color: tokens.coral,
            ),
          ),
        );
      case _ReleaseNotesItem(:final int number, :final String text):
        return Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: widget.dense ? 22 : 26,
                child: Text(
                  '$number.',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: _fontSize,
                    height: _lineHeight,
                    color: tokens.inkMuted,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w500,
                    fontSize: _fontSize,
                    height: _lineHeight,
                    color: tokens.ink,
                  ),
                ),
              ),
            ],
          ),
        );
    }
  }
}

List<_ReleaseNotesRow> _flatten(List<ReleaseNoteUpdate> updates) {
  final List<_ReleaseNotesRow> rows = <_ReleaseNotesRow>[];
  for (int i = 0; i < updates.length; i++) {
    final ReleaseNoteUpdate update = updates[i];
    rows.add(_ReleaseNotesHeader(version: update.version, isFirst: i == 0));
    for (int n = 0; n < update.notes.length; n++) {
      rows.add(_ReleaseNotesItem(number: n + 1, text: update.notes[n]));
    }
  }
  return rows;
}

sealed class _ReleaseNotesRow {
  const _ReleaseNotesRow();
}

class _ReleaseNotesHeader extends _ReleaseNotesRow {
  const _ReleaseNotesHeader({required this.version, required this.isFirst});

  final String version;
  final bool isFirst;
}

class _ReleaseNotesItem extends _ReleaseNotesRow {
  const _ReleaseNotesItem({required this.number, required this.text});

  final int number;
  final String text;
}
