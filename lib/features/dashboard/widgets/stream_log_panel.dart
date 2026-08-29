import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/log_view.dart';

class StreamLogPanel extends StatelessWidget {
  const StreamLogPanel({
    super.key,
    required this.title,
    required this.text,
    required this.emptyHint,
    this.minHeight = 180,
  });

  final String title;
  final String text;
  final String emptyHint;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy',
                  onPressed: text.isEmpty
                      ? null
                      : () async {
                          await Clipboard.setData(ClipboardData(text: text));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('$title copied'),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          }
                        },
                  icon: const Icon(Icons.copy, size: 18),
                ),
              ],
            ),
          ),
          LogView(text: text, emptyHint: emptyHint, minHeight: minHeight),
        ],
      ),
    );
  }
}
