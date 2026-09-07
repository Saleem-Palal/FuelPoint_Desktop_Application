import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../Screens/Shift Screen/Widgets/shift_close_warning_dialog.dart';
import '../features/shift/domain/shift_models.dart';

/// Root navigator used by [WindowLifecycleService] when the close event
/// fires outside a widget rebuild.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

typedef ActiveShiftReader = ManagerShiftRecord? Function();
typedef ActiveShiftFlag = bool Function();
typedef ShiftEndHandler = Future<void> Function();
typedef ForceCloseHandler = Future<bool> Function();

/// Intercepts native desktop close. An OPEN / pending shift blocks destroy
/// until the operator cancels, ends the shift, or force-closes with PIN.
class WindowLifecycleService with WindowListener {
  WindowLifecycleService({
    required this.hasActiveShift,
    required this.activeManagerName,
    required this.onProceedToEndShift,
    required this.onForceClose,
    GlobalKey<NavigatorState>? navigatorKey,
  }) : navigatorKey = navigatorKey ?? appNavigatorKey;

  final GlobalKey<NavigatorState> navigatorKey;
  final ActiveShiftFlag hasActiveShift;
  final String Function() activeManagerName;
  final ShiftEndHandler onProceedToEndShift;
  final ForceCloseHandler onForceClose;

  bool _attached = false;
  bool _dialogOpen = false;

  static bool get isDesktop {
    if (kIsWeb) {
      return false;
    }
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  static const Size defaultWindowSize = Size(1280, 800);
  static const Size minimumWindowSize = Size(1024, 720);

  /// Locks the native window so operators cannot shrink below a usable
  /// 1024×720 station layout. Call once from [main] before [runApp].
  static Future<void> configureDesktopWindow() async {
    if (!isDesktop) {
      return;
    }
    try {
      await windowManager.ensureInitialized();
      try {
        await windowManager.hide();
      } catch (_) {}
      const WindowOptions windowOptions = WindowOptions(
        size: defaultWindowSize,
        minimumSize: minimumWindowSize,
        center: true,
      );
      // Do not await show() before runApp — that paints an empty native
      // window (black freeze) while SQLite and the first Flutter frame lag.
      unawaited(
        windowManager.waitUntilReadyToShow(windowOptions, () async {
          await windowManager.setMinimumSize(minimumWindowSize);
          await windowManager.setSize(defaultWindowSize);
          await windowManager.show();
          await windowManager.focus();
        }),
      );
    } catch (error, stack) {
      debugPrint('configureDesktopWindow failed: $error\n$stack');
    }
  }

  Future<void> attach() async {
    if (!isDesktop || _attached) {
      return;
    }
    try {
      await windowManager.ensureInitialized();
      windowManager.addListener(this);
      await windowManager.setPreventClose(true);
      _attached = true;
    } catch (error, stack) {
      debugPrint('WindowLifecycleService.attach failed: $error\n$stack');
    }
  }

  void detach() {
    if (!_attached) {
      return;
    }
    windowManager.removeListener(this);
    _attached = false;
  }

  @override
  void onWindowClose() {
    unawaited(_handleClose());
  }

  Future<void> _handleClose() async {
    if (!isDesktop) {
      return;
    }
    if (!hasActiveShift()) {
      await windowManager.destroy();
      return;
    }
    final bool prevented = await windowManager.isPreventClose();
    if (!prevented) {
      await windowManager.destroy();
      return;
    }
    final BuildContext? context = navigatorKey.currentContext;
    if (context == null || !context.mounted || _dialogOpen) {
      return;
    }
    _dialogOpen = true;
    try {
      final ShiftCloseWarningAction? action = await showShiftCloseWarningDialog(
        context,
        managerName: activeManagerName(),
      );
      if (action == null || action == ShiftCloseWarningAction.stay) {
        return;
      }
      if (action == ShiftCloseWarningAction.proceedEndShift) {
        await onProceedToEndShift();
        return;
      }
      final bool closed = await onForceClose();
      if (closed) {
        await windowManager.destroy();
      }
    } finally {
      _dialogOpen = false;
    }
  }
}
