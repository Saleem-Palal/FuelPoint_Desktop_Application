import 'package:flutter/material.dart';

/// Scales industrial metric text down instead of wrapping or overflowing.
class ScaleDownMetric extends StatelessWidget {
  const ScaleDownMetric({
    super.key,
    required this.text,
    required this.style,
    this.alignment = Alignment.centerLeft,
    this.maxLines = 1,
  });

  final String text;
  final TextStyle style;
  final Alignment alignment;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: alignment,
      child: Text(
        text,
        maxLines: maxLines,
        softWrap: false,
        overflow: TextOverflow.visible,
        style: style,
      ),
    );
  }
}

/// Scrolls a form / card / dialog when vertical space is compressed, while
/// still filling the viewport when content is short.
class ScrollableConstrainedBody extends StatelessWidget {
  const ScrollableConstrainedBody({
    super.key,
    required this.child,
    this.padding,
    this.controller,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double minHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 0;
        final double minWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 0;
        return SingleChildScrollView(
          controller: controller,
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: minWidth,
              minHeight: minHeight,
            ),
            child: IntrinsicHeight(child: child),
          ),
        );
      },
    );
  }
}

/// Computes wrap/grid columns the same way [SliverGridDelegateWithMaxCrossAxisExtent] does.
int extentCrossAxisCount({
  required double width,
  double maxCrossAxisExtent = 320,
  double spacing = 8,
}) {
  if (!width.isFinite || width <= 0) {
    return 1;
  }
  final int count = (width / (maxCrossAxisExtent + spacing)).ceil();
  return count < 1 ? 1 : count;
}

double extentTileWidth({
  required double width,
  required int columns,
  double spacing = 8,
}) {
  if (!width.isFinite || width <= 0 || columns <= 0) {
    return width.isFinite ? width : 0;
  }
  return (width - spacing * (columns - 1)) / columns;
}

/// Reflows cards as width shrinks. Prefer this over a fixed-column [Row].
class ExtentWrap extends StatelessWidget {
  const ExtentWrap({
    super.key,
    required this.children,
    this.maxCrossAxisExtent = 320,
    this.spacing = 8,
    this.runSpacing = 8,
  });

  final List<Widget> children;
  final double maxCrossAxisExtent;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final int columns = extentCrossAxisCount(
          width: width,
          maxCrossAxisExtent: maxCrossAxisExtent,
          spacing: spacing,
        );
        final double tileWidth = extentTileWidth(
          width: width,
          columns: columns,
          spacing: spacing,
        );
        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: <Widget>[
            for (final Widget child in children)
              SizedBox(width: tileWidth, child: child),
          ],
        );
      },
    );
  }
}
