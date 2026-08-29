import 'package:flutter/material.dart';

class LogView extends StatefulWidget {
  const LogView({
    super.key,
    required this.text,
    required this.emptyHint,
    this.minHeight = 180,
  });

  final String text;
  final String emptyHint;
  final double minHeight;

  @override
  State<LogView> createState() => _LogViewState();
}

class _LogViewState extends State<LogView> {
  final ScrollController _controller = ScrollController();

  @override
  void didUpdateWidget(covariant LogView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_controller.hasClients) {
          return;
        }
        _controller.jumpTo(_controller.position.maxScrollExtent);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String body = widget.text.isEmpty ? widget.emptyHint : widget.text;

    final double minH = widget.minHeight;
    final double maxH = minH > 280 ? minH : 280;

    return Container(
      constraints: BoxConstraints(minHeight: minH, maxHeight: maxH),
      color: colors.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Scrollbar(
        controller: _controller,
        child: SingleChildScrollView(
          controller: _controller,
          child: SelectableText(
            body,
            style: TextStyle(
              fontFamily: 'Consolas',
              fontFamilyFallback: const <String>['Courier New', 'monospace'],
              fontSize: 12,
              height: 1.4,
              color: widget.text.isEmpty
                  ? colors.onSurfaceVariant
                  : colors.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
