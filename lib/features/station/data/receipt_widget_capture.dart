import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/settings_provider.dart';
import '../domain/receipt_footer_settings.dart';

/// Pins the receipt footer for an off-tree print snapshot.
///
/// A second [UncontrolledProviderScope] on the live container crashes Riverpod
/// when another provider (the office-network stream) refreshes mid-capture.
class ReceiptPrintFooter extends InheritedWidget {
  const ReceiptPrintFooter({required this.footer, required super.child});

  final ReceiptFooterSettings footer;

  static ReceiptFooterSettings? maybeOf(BuildContext context) {
    final InheritedElement? element = context
        .getElementForInheritedWidgetOfExactType<ReceiptPrintFooter>();
    if (element == null) {
      return null;
    }
    return (element.widget as ReceiptPrintFooter).footer;
  }

  @override
  bool updateShouldNotify(ReceiptPrintFooter oldWidget) {
    return footer != oldWidget.footer;
  }
}

/// Renders [child] off the live tree so print capture is not culled or shown.
Future<Uint8List> captureReceiptWidget({
  required BuildContext context,
  required Widget child,
  double logicalWidth = 456,
}) async {
  if (!context.mounted) {
    throw StateError('Receipt preview is not on screen');
  }
  final ProviderContainer container = ProviderScope.containerOf(context);
  final ReceiptFooterSettings footer = container
      .read(settingsProvider)
      .receiptFooter;
  final MediaQueryData media = MediaQuery.of(context);
  final ThemeData theme = Theme.of(context);
  final ui.FlutterView view = View.of(context);
  const double maxLogicalHeight = 2400;
  final Size logicalSize = Size(logicalWidth, maxLogicalHeight);
  final double dpr = view.devicePixelRatio.clamp(1, 2);
  final Size physicalSize = logicalSize * dpr;

  final Widget wrapped = ReceiptPrintFooter(
    footer: footer,
    child: InheritedTheme.captureAll(
      context,
      MediaQuery(
        data: media.copyWith(size: logicalSize),
        child: Theme(
          data: theme,
          child: Directionality(
            textDirection: Directionality.of(context),
            child: DefaultTextStyle(
              style: const TextStyle(
                color: Color(0xFF211C1A),
                fontFamily: 'Roboto',
                decoration: TextDecoration.none,
              ),
              child: IconTheme(
                data: const IconThemeData(color: Color(0xFF211C1A)),
                child: child,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  final PipelineOwner pipelineOwner = PipelineOwner();
  final BuildOwner buildOwner = BuildOwner(focusManager: FocusManager());
  final RenderRepaintBoundary boundary = RenderRepaintBoundary();
  final RenderView renderView = RenderView(
    view: view,
    configuration: ViewConfiguration(
      logicalConstraints: BoxConstraints.tight(logicalSize),
      physicalConstraints: BoxConstraints.tight(physicalSize),
      devicePixelRatio: dpr,
    ),
    child: RenderPositionedBox(
      alignment: Alignment.topCenter,
      child: boundary,
    ),
  );
  pipelineOwner.rootNode = renderView;
  renderView.prepareInitialFrame();

  final RenderObjectToWidgetElement<RenderBox> root =
      RenderObjectToWidgetAdapter<RenderBox>(
        container: boundary,
        debugShortDescription: 'receipt capture',
        child: wrapped,
      ).attachToRenderTree(buildOwner);

  try {
    for (int pass = 0; pass < 6; pass++) {
      buildOwner.buildScope(root);
      pipelineOwner.flushLayout();
      pipelineOwner.flushCompositingBits();
      pipelineOwner.flushPaint();
      if (boundary.layer != null && boundary.hasSize && !boundary.size.isEmpty) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    buildOwner.buildScope(root);
    pipelineOwner
      ..flushLayout()
      ..flushCompositingBits()
      ..flushPaint();
    if (!boundary.hasSize || boundary.size.isEmpty || boundary.layer == null) {
      throw StateError('Receipt preview cannot be captured');
    }
    final double ratio = boundary.size.height * dpr > 4096
        ? (4096 / boundary.size.height).clamp(0.5, dpr)
        : dpr;
    ui.Image image;
    try {
      image = await boundary.toImage(pixelRatio: ratio);
    } catch (error, stack) {
      debugPrint('Receipt capture retry: $error\n$stack');
      pipelineOwner.flushPaint();
      image = await boundary.toImage(pixelRatio: 1);
    }
    try {
      final ByteData? bytes = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (bytes == null) {
        throw StateError('Receipt snapshot failed');
      }
      return bytes.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    pipelineOwner.rootNode = null;
    root.deactivate();
    root.unmount();
  }
}
