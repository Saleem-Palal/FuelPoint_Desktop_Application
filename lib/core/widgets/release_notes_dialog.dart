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

class ReleaseNotesList extends StatelessWidget {
  const ReleaseNotesList({super.key, this.dense = false});

  final bool dense;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return ListView.separated(
      shrinkWrap: true,
      itemCount: AppBrand.releaseNotes.length,
      separatorBuilder: (_, _) => SizedBox(height: dense ? 6 : 8),
      itemBuilder: (BuildContext context, int index) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 22,
              child: Text(
                '${index + 1}.',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w700,
                  fontSize: dense ? 12 : 13,
                  color: tokens.inkMuted,
                ),
              ),
            ),
            Expanded(
              child: Text(
                AppBrand.releaseNotes[index],
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w500,
                  fontSize: dense ? 12 : 13,
                  height: 1.35,
                  color: tokens.ink,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
