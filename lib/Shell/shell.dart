import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../Screens/Customer Screen/customer_screen.dart';
import '../Screens/Dashboard/dashboard_screen.dart';
import '../Screens/Dispenser Screen/dispenser_screen.dart';
import '../Screens/Ledger Screen/ledger_screen.dart';
import '../Screens/Purchase Screen/purchase_screen.dart';
import '../Screens/Sale Screen/sale_screen.dart';
import '../Screens/Settings Screen/settings_screen.dart';
import '../Screens/Shift Screen/shift_management_screen.dart';
import '../Screens/Shift Screen/Widgets/shift_close_actions.dart';
import '../Screens/Shift Screen/Widgets/shift_handover_dialog.dart';
import '../features/shift/presentation/shift_providers.dart';
import '../providers/auth_provider.dart';
import '../providers/shift_provider.dart';
import '../services/window_lifecycle_service.dart';
import '../Screens/managers_screen.dart';
import '../core/constants.dart';
import '../core/theme/dispensr_theme.dart';
import '../core/widgets/app_screen_header.dart';
import '../features/access/domain/access_policy.dart';
import '../features/access/presentation/access_controller.dart';
import '../features/access/presentation/owner_access_gate.dart';
import '../features/access/presentation/owner_pin_verification_modal.dart';
import '../features/station/domain/dispenser_models.dart';
import '../features/station/presentation/station_providers.dart';
import 'shell_navigation.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _NavDestination {
  const _NavDestination({
    required this.icon,
    required this.label,
    required this.index,
  });

  final IconData icon;
  final String label;
  final int index;
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _sidebarCollapsed = true;
  bool _unverifiedPrompted = false;
  final FocusNode _shellFocus = FocusNode();
  WindowLifecycleService? _lifecycle;

  static const List<_NavDestination> _menu = <_NavDestination>[
    _NavDestination(
      icon: Icons.grid_view_outlined,
      label: 'Dashboard',
      index: 0,
    ),
    _NavDestination(
      icon: Icons.local_gas_station_outlined,
      label: 'Sale',
      index: 1,
    ),
    _NavDestination(
      icon: Icons.shopping_cart_outlined,
      label: 'Purchase',
      index: 2,
    ),
    _NavDestination(icon: Icons.menu_book_outlined, label: 'Ledger', index: 3),
    _NavDestination(
      icon: Icons.handshake_outlined,
      label: 'Customers',
      index: 8,
    ),
    _NavDestination(
      icon: Icons.manage_accounts_outlined,
      label: 'Managers',
      index: 9,
    ),
    _NavDestination(icon: Icons.badge_outlined, label: 'Shifts', index: 5),
  ];

  static const List<_NavDestination> _system = <_NavDestination>[
    _NavDestination(
      icon: Icons.speed_outlined,
      label: 'Dispenser Monitor',
      index: 6,
    ),
    _NavDestination(icon: Icons.settings_outlined, label: 'Settings', index: 7),
  ];

  String _titleFor(int selectedIndex) {
    for (final _NavDestination item in <_NavDestination>[
      ..._menu,
      ..._system,
    ]) {
      if (item.index == selectedIndex) {
        return item.label;
      }
    }
    return AppBrand.name;
  }

  IconData _titleIconFor(int selectedIndex) {
    for (final _NavDestination item in <_NavDestination>[
      ..._menu,
      ..._system,
    ]) {
      if (item.index == selectedIndex) {
        return item.icon;
      }
    }
    return Icons.grid_view_outlined;
  }

  Widget _workspace(int selectedIndex, {required bool ownerElevated}) {
    if (AccessPolicy.destinationRequiresOwner(selectedIndex) &&
        !ownerElevated) {
      return const OwnerAccessGate(
        title: 'Owner access required',
        message:
            'Only Sales and Customers are available during a manager shift. '
            'Enter the Owner Master PIN to open this screen.',
      );
    }
    switch (selectedIndex) {
      case 0:
        return const DashboardScreen();
      case 1:
        return const SaleScreen();
      case 2:
        return const PurchaseScreen();
      case 3:
        return const LedgerScreen();
      case 5:
        return const ShiftManagementScreen();
      case 8:
        return const CustomerScreen();
      case 9:
        return const ManagersScreen();
      case 6:
        return const DispenserScreen();
      case 7:
        return const SettingsScreen();
      default:
        return _PlaceholderPage(
          title: _titleFor(selectedIndex),
          icon: _titleIconFor(selectedIndex),
        );
    }
  }

  Future<void> _select(int index) async {
    final bool elevated = ref.read(accessControllerProvider).isOwnerElevated;
    if (AccessPolicy.destinationRequiresOwner(index) && !elevated) {
      final bool unlocked = await showOwnerPinVerificationModal(context);
      if (!unlocked || !mounted) {
        return;
      }
    }
    ref.read(shellDestinationProvider.notifier).state = index;
  }

  void _lockOwnerAccess() {
    ref.read(accessControllerProvider.notifier).lockOwnerAccess();
    ref.read(shellDestinationProvider.notifier).state = ShellDestinations.sale;
  }

  static String _initialsOf(String name) {
    final List<String> parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((String part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return '?';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  void _toggleSidebar() {
    setState(() {
      _sidebarCollapsed = !_sidebarCollapsed;
    });
  }

  bool _saleTextEditing = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleSaleKeys);
    FocusManager.instance.addListener(_onFocusChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _lifecycle = WindowLifecycleService(
        hasActiveShift: () => ref.read(shiftProvider).hasActiveShift,
        activeManagerName: () => ref.read(shiftProvider).liveManagerName,
        onProceedToEndShift: () => promptManualEndShift(context, ref),
        onForceClose: () => promptForceCloseShift(context, ref),
      );
      unawaited(_lifecycle!.attach());
    });
  }

  @override
  void dispose() {
    _lifecycle?.detach();
    FocusManager.instance.removeListener(_onFocusChange);
    HardwareKeyboard.instance.removeHandler(_handleSaleKeys);
    _shellFocus.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    final bool editing = _editableTextHasFocus();
    if (editing == _saleTextEditing) {
      return;
    }
    _saleTextEditing = editing;
    if (mounted) {
      setState(() {});
    }
  }

  bool _editableTextHasFocus() {
    final BuildContext? focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) {
      return false;
    }
    if (focused.widget is EditableText) {
      return true;
    }
    return focused.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _handleSaleKeys(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return false;
    }
    if (ref.read(shellDestinationProvider) != ShellDestinations.sale ||
        !mounted) {
      return false;
    }
    if (Navigator.of(context).canPop()) {
      return false;
    }
    if (_editableTextHasFocus()) {
      return false;
    }

    final LogicalKeyboardKey key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowLeft) {
      nudgeSelectedUnit(ref, -1);
      return true;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      nudgeSelectedUnit(ref, 1);
      return true;
    }
    return false;
  }

  void _selectUnit(int unitId) {
    if (ref.read(shellDestinationProvider) != ShellDestinations.sale) {
      return;
    }
    if (_editableTextHasFocus()) {
      return;
    }
    ref.read(selectedDispenserIndexProvider.notifier).state = unitId;
  }

  void _confirmSelectedUnit() {
    if (ref.read(shellDestinationProvider) != ShellDestinations.sale) {
      return;
    }
    if (_editableTextHasFocus()) {
      return;
    }
    final int unitId = ref.read(selectedDispenserIndexProvider);
    final DispenserBay bay = ref.read(stationControllerProvider).bay(unitId);
    if (!bay.canConfirmPayment) {
      return;
    }
    openPaymentSheet(ref, unitId);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ShiftWorkspaceState>(shiftWorkspaceProvider, (
      ShiftWorkspaceState? previous,
      ShiftWorkspaceState next,
    ) {
      if (!next.isUnverifiedSession) {
        return;
      }
      final AuthState auth = ref.read(authProvider);
      final bool alreadyUnlocked =
          auth.isAuthenticated &&
          auth.activeManagerId == next.activeShift?.managerId;
      if (alreadyUnlocked || shouldBypassLogin) {
        Future<void>(() {
          if (!mounted) {
            return;
          }
          ref.read(shiftWorkspaceProvider.notifier).markSessionVerified();
        });
        return;
      }
      if (_unverifiedPrompted) {
        return;
      }
      _unverifiedPrompted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(promptUnverifiedShift(context, ref));
        }
      });
    });
    final DispensrTokens tokens = DispensrTokens.of(context);
    final int selectedIndex = ref.watch(shellDestinationProvider);
    final AuthState auth = ref.watch(authProvider);
    final AccessState access = ref.watch(accessControllerProvider);
    final bool ownerElevated = access.isOwnerElevated;
    final ShiftProvider shift = ref.watch(shiftProvider);
    final bool shiftLive = shift.activeShift?.isOpen == true;
    final String liveManagerName = shift.activeShift?.managerName.trim() ?? '';
    final String loggedInName = auth.activeManagerName.trim();
    final String operatorName = shiftLive && liveManagerName.isNotEmpty
        ? liveManagerName
        : (auth.isAuthenticated && loggedInName.isNotEmpty
              ? loggedInName
              : 'Station Owner');
    final String operatorRole = !auth.isAuthenticated
        ? 'Setup'
        : (shiftLive ? 'On Shift' : 'No Shift');
    final String operatorInitials = _initialsOf(operatorName);

    final Map<ShortcutActivator, VoidCallback> bindings =
        <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.digit1, control: true): () {
            unawaited(_select(1));
          },
          const SingleActivator(LogicalKeyboardKey.backslash, control: true):
              _toggleSidebar,
        };
    if (selectedIndex == ShellDestinations.sale && !_saleTextEditing) {
      bindings.addAll(<ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.digit1): () => _selectUnit(1),
        const SingleActivator(LogicalKeyboardKey.digit2): () => _selectUnit(2),
        const SingleActivator(LogicalKeyboardKey.digit3): () => _selectUnit(3),
        const SingleActivator(LogicalKeyboardKey.digit4): () => _selectUnit(4),
        const SingleActivator(LogicalKeyboardKey.digit5): () => _selectUnit(5),
        const SingleActivator(LogicalKeyboardKey.numpad1): () => _selectUnit(1),
        const SingleActivator(LogicalKeyboardKey.numpad2): () => _selectUnit(2),
        const SingleActivator(LogicalKeyboardKey.numpad3): () => _selectUnit(3),
        const SingleActivator(LogicalKeyboardKey.numpad4): () => _selectUnit(4),
        const SingleActivator(LogicalKeyboardKey.numpad5): () => _selectUnit(5),
        const SingleActivator(LogicalKeyboardKey.enter): _confirmSelectedUnit,
        const SingleActivator(LogicalKeyboardKey.numpadEnter):
            _confirmSelectedUnit,
      });
    }

    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(
        autofocus: true,
        focusNode: _shellFocus,
        child: Scaffold(
          backgroundColor: tokens.canvas,
          body: Row(
            children: <Widget>[
              _Sidebar(
                selectedIndex: selectedIndex,
                collapsed: _sidebarCollapsed,
                menu: _menu,
                system: _system,
                onSelect: (int index) {
                  unawaited(_select(index));
                },
                onToggleCollapsed: _toggleSidebar,
                operatorName: operatorName,
                operatorRole: operatorRole,
                operatorInitials: operatorInitials,
                shiftLive: shiftLive,
                ownerElevated: ownerElevated,
                onLockOwnerAccess: _lockOwnerAccess,
              ),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    _workspace(selectedIndex, ownerElevated: ownerElevated),
                    const ShiftReconciliationOverlay(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.selectedIndex,
    required this.collapsed,
    required this.menu,
    required this.system,
    required this.onSelect,
    required this.onToggleCollapsed,
    required this.onLockOwnerAccess,
    required this.operatorName,
    required this.operatorRole,
    required this.operatorInitials,
    required this.shiftLive,
    required this.ownerElevated,
  });

  static const double _expandedWidth = 256;
  static const double _collapsedWidth = 76;

  final int selectedIndex;
  final bool collapsed;
  final List<_NavDestination> menu;
  final List<_NavDestination> system;
  final ValueChanged<int> onSelect;
  final VoidCallback onToggleCollapsed;
  final VoidCallback onLockOwnerAccess;
  final String operatorName;
  final String operatorRole;
  final String operatorInitials;
  final bool shiftLive;
  final bool ownerElevated;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);

    return Material(
      color: tokens.card,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: collapsed ? _collapsedWidth : _expandedWidth,
        decoration: BoxDecoration(
          color: tokens.card,
          border: Border(right: BorderSide(color: tokens.line)),
        ),
        clipBehavior: Clip.hardEdge,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool showLabels = constraints.maxWidth >= 168;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    showLabels ? 16 : 10,
                    16,
                    showLabels ? 8 : 10,
                    8,
                  ),
                  child: showLabels
                      ? Row(
                          children: <Widget>[
                            _BrandMark(
                              tokens: tokens,
                              size: 44,
                              collapsed: collapsed,
                              onPressed: onToggleCollapsed,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    AppBrand.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'Roboto',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 18,
                                      height: 1.1,
                                      color: tokens.ink,
                                    ),
                                  ),
                                  Text(
                                    AppBrand.tagline,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'Roboto',
                                      fontWeight: FontWeight.w500,
                                      fontSize: 12,
                                      color: tokens.inkMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _CollapseToggle(
                              collapsed: collapsed,
                              onPressed: onToggleCollapsed,
                            ),
                          ],
                        )
                      : Center(
                          child: _BrandMark(
                            tokens: tokens,
                            size: 40,
                            collapsed: collapsed,
                            onPressed: onToggleCollapsed,
                          ),
                        ),
                ),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      showLabels ? 12 : 8,
                      8,
                      showLabels ? 12 : 8,
                      12,
                    ),
                    children: <Widget>[
                      _SectionLabel(text: 'Menu', collapsed: !showLabels),
                      const SizedBox(height: 6),
                      for (final _NavDestination item in menu)
                        _NavTile(
                          item: item,
                          selected: selectedIndex == item.index,
                          collapsed: !showLabels,
                          locked:
                              AccessPolicy.destinationRequiresOwner(
                                item.index,
                              ) &&
                              !ownerElevated,
                          onTap: () => onSelect(item.index),
                        ),
                      const SizedBox(height: 18),
                      _SectionLabel(text: 'System', collapsed: !showLabels),
                      const SizedBox(height: 6),
                      for (final _NavDestination item in system)
                        _NavTile(
                          item: item,
                          selected: selectedIndex == item.index,
                          collapsed: !showLabels,
                          locked:
                              AccessPolicy.destinationRequiresOwner(
                                item.index,
                              ) &&
                              !ownerElevated,
                          onTap: () => onSelect(item.index),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    showLabels ? 16 : 8,
                    8,
                    showLabels ? 16 : 8,
                    16,
                  ),
                  child: Column(
                    children: <Widget>[
                      if (!showLabels)
                        Tooltip(
                          message: '$operatorName · $operatorRole',
                          child: _OperatorAvatar(
                            initials: operatorInitials,
                            shiftLive: shiftLive,
                          ),
                        )
                      else
                        Row(
                          children: <Widget>[
                            _OperatorAvatar(
                              initials: operatorInitials,
                              shiftLive: shiftLive,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    operatorName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'Roboto',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: tokens.ink,
                                    ),
                                  ),
                                  Text(
                                    operatorRole,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'Roboto',
                                      fontWeight: FontWeight.w400,
                                      fontSize: 11,
                                      color: shiftLive
                                          ? tokens.good
                                          : tokens.inkMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      if (ownerElevated && showLabels) ...<Widget>[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: IntrinsicWidth(
                            child: DsPillButton(
                              label: 'Lock Owner Access',
                              icon: Icons.lock_outline,
                              variant: DsPillVariant.danger,
                              onPressed: onLockOwnerAccess,
                              compact: true,
                            ),
                          ),
                        ),
                      ] else if (ownerElevated) ...<Widget>[
                        const SizedBox(height: 10),
                        IconButton(
                          onPressed: onLockOwnerAccess,
                          tooltip: 'Lock Owner Access',
                          icon: Icon(
                            Icons.lock_outline,
                            size: 18,
                            color: tokens.bad,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      _SidebarVersion(collapsed: !showLabels),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _OperatorAvatar extends StatelessWidget {
  const _OperatorAvatar({required this.initials, required this.shiftLive});

  final String initials;
  final bool shiftLive;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final Color accent = shiftLive ? tokens.good : tokens.inkMuted;
    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: accent.withValues(alpha: shiftLive ? 0.9 : 0.45),
                  width: shiftLive ? 2 : 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: CircleAvatar(
                  backgroundColor: tokens.line,
                  child: Text(
                    initials,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      color: tokens.inkMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
                border: Border.all(color: tokens.card, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarVersion extends StatelessWidget {
  const _SidebarVersion({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final TextStyle style = TextStyle(
      fontFamily: 'Roboto',
      fontWeight: FontWeight.w500,
      fontSize: collapsed ? 9 : 11,
      letterSpacing: collapsed ? 0.2 : 0.3,
      height: 1.2,
      color: tokens.inkMuted.withValues(alpha: 0.8),
    );

    return Align(
      alignment: Alignment.centerLeft,
      child: Tooltip(
        message: '${AppBrand.name} ${AppBrand.versionLabel}',
        child: Padding(
          padding: EdgeInsets.only(left: collapsed ? 6 : 2, bottom: 2),
          child: Text(
            AppBrand.versionLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({
    required this.tokens,
    required this.size,
    required this.collapsed,
    required this.onPressed,
  });

  final DispensrTokens tokens;
  final double size;
  final bool collapsed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: collapsed
          ? 'Expand navigation (Ctrl+\\)'
          : 'Collapse navigation (Ctrl+\\)',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          hoverColor: tokens.card.withValues(alpha: 0.16),
          child: Ink(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: tokens.coralShadow,
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/icons/app_logo.png',
                width: size,
                height: size,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CollapseToggle extends StatelessWidget {
  const _CollapseToggle({required this.collapsed, required this.onPressed});

  final bool collapsed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Tooltip(
      message: collapsed
          ? 'Expand navigation (Ctrl+\\)'
          : 'Collapse navigation (Ctrl+\\)',
      child: IconButton(
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        icon: Icon(
          collapsed ? Icons.chevron_right : Icons.chevron_left,
          color: tokens.inkMuted,
          size: 22,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text, required this.collapsed});

  final String text;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Divider(color: tokens.line, height: 1),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 2),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontFamily: 'Roboto',
          fontWeight: FontWeight.w700,
          fontSize: 10,
          letterSpacing: 1.4,
          color: tokens.inkMuted.withValues(alpha: 0.75),
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.item,
    required this.selected,
    required this.collapsed,
    required this.onTap,
    this.locked = false,
  });

  final _NavDestination item;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final Color fg = selected ? tokens.coralPressed : tokens.inkMuted;
    final Color iconColor = selected ? tokens.coralPressed : tokens.inkMuted;

    final Widget tile = Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected
            ? tokens.coral.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(tokens.radius12),
        child: InkWell(
          onTap: onTap,
          hoverColor: tokens.canvas,
          borderRadius: BorderRadius.circular(tokens.radius12),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 0 : 12,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(tokens.radius12),
              border: selected
                  ? Border(
                      left: collapsed
                          ? BorderSide.none
                          : BorderSide(color: tokens.coral, width: 3),
                    )
                  : null,
            ),
            child: collapsed
                ? Center(
                    child: Icon(
                      locked ? Icons.lock_outline : item.icon,
                      size: 20,
                      color: iconColor,
                    ),
                  )
                : Row(
                    children: <Widget>[
                      Icon(item.icon, size: 18, color: iconColor),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            fontSize: 13,
                            color: fg,
                          ),
                        ),
                      ),
                      if (locked)
                        Icon(Icons.lock_outline, size: 14, color: iconColor),
                    ],
                  ),
          ),
        ),
      ),
    );

    if (!collapsed) {
      return tile;
    }
    return Tooltip(
      message: locked ? '${item.label} (Owner PIN required)' : item.label,
      waitDuration: Duration.zero,
      child: tile,
    );
  }
}

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return ColoredBox(
      color: tokens.canvas,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AppScreenHeader(title: title, icon: icon),
            Expanded(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 24,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.card,
                    borderRadius: BorderRadius.circular(tokens.radius20),
                    border: Border.all(color: tokens.line),
                    boxShadow: tokens.cardShadow,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        title,
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                          color: tokens.ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'This screen is not wired yet.',
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          color: tokens.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
