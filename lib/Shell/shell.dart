import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../Screens/Ledger Screen/ledger_screen.dart';
import '../Screens/Purchase Screen/purchase_screen.dart';
import '../Screens/Sale Screen/sale_screen.dart';
import '../core/constants.dart';
import '../core/theme/dispensr_theme.dart';
import '../core/widgets/app_screen_header.dart';
import '../features/station/domain/dispenser_models.dart';
import '../features/station/presentation/station_providers.dart';

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
  int _selectedIndex = 1;
  bool _sidebarCollapsed = true;
  final FocusNode _shellFocus = FocusNode();

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
    _NavDestination(icon: Icons.show_chart, label: 'Reports', index: 4),
    _NavDestination(icon: Icons.people_outline, label: 'Users', index: 5),
  ];

  static const List<_NavDestination> _system = <_NavDestination>[
    _NavDestination(
      icon: Icons.speed_outlined,
      label: 'Dispenser Monitor',
      index: 6,
    ),
    _NavDestination(icon: Icons.settings_outlined, label: 'Settings', index: 7),
  ];

  String get _title {
    for (final _NavDestination item in <_NavDestination>[
      ..._menu,
      ..._system,
    ]) {
      if (item.index == _selectedIndex) {
        return item.label;
      }
    }
    return AppBrand.name;
  }

  IconData get _titleIcon {
    for (final _NavDestination item in <_NavDestination>[
      ..._menu,
      ..._system,
    ]) {
      if (item.index == _selectedIndex) {
        return item.icon;
      }
    }
    return Icons.grid_view_outlined;
  }

  Widget _workspace() {
    switch (_selectedIndex) {
      case 1:
        return const SaleScreen();
      case 2:
        return const PurchaseScreen();
      case 3:
        return const LedgerScreen();
      default:
        return _PlaceholderPage(title: _title, icon: _titleIcon);
    }
  }

  void _select(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _toggleSidebar() {
    setState(() {
      _sidebarCollapsed = !_sidebarCollapsed;
    });
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleSaleKeys);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleSaleKeys);
    _shellFocus.dispose();
    super.dispose();
  }

  bool _handleSaleKeys(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return false;
    }
    if (_selectedIndex != 1 || !mounted) {
      return false;
    }
    if (Navigator.of(context).canPop()) {
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
    if (_selectedIndex != 1) {
      return;
    }
    ref.read(selectedDispenserIndexProvider.notifier).state = unitId;
  }

  void _confirmSelectedUnit() {
    if (_selectedIndex != 1) {
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
    final DispensrTokens tokens = DispensrTokens.of(context);

    final Map<ShortcutActivator, VoidCallback> bindings =
        <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.digit1, control: true): () =>
              _select(1),
          const SingleActivator(LogicalKeyboardKey.backslash, control: true):
              _toggleSidebar,
        };
    if (_selectedIndex == 1) {
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
                selectedIndex: _selectedIndex,
                collapsed: _sidebarCollapsed,
                menu: _menu,
                system: _system,
                onSelect: _select,
                onToggleCollapsed: _toggleSidebar,
                onLogout: () {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Logged out')));
                },
              ),
              Expanded(child: _workspace()),
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
    required this.onLogout,
  });

  static const double _expandedWidth = 256;
  static const double _collapsedWidth = 76;

  final int selectedIndex;
  final bool collapsed;
  final List<_NavDestination> menu;
  final List<_NavDestination> system;
  final ValueChanged<int> onSelect;
  final VoidCallback onToggleCollapsed;
  final VoidCallback onLogout;

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
                          message: 'Amir R. · Cashier',
                          child: CircleAvatar(
                            radius: 16,
                            backgroundColor: tokens.line,
                            child: Text(
                              'AR',
                              style: TextStyle(
                                fontFamily: 'Roboto',
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                                color: tokens.inkMuted,
                              ),
                            ),
                          ),
                        )
                      else
                        Row(
                          children: <Widget>[
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: tokens.line,
                              child: Text(
                                'AR',
                                style: TextStyle(
                                  fontFamily: 'Roboto',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                  color: tokens.inkMuted,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    'Amir R.',
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
                                    'Cashier',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'Roboto',
                                      fontWeight: FontWeight.w400,
                                      fontSize: 11,
                                      color: tokens.inkMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      if (showLabels) ...<Widget>[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: tokens.canvas,
                            borderRadius: BorderRadius.circular(
                              tokens.radius12,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'SHIFT',
                                style: TextStyle(
                                  fontFamily: 'Roboto',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 9,
                                  letterSpacing: 0.8,
                                  color: tokens.inkMuted,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Morning · 08:00 AM–04:00 PM',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Roboto',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  color: tokens.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        DsPillButton(
                          label: 'Logout',
                          icon: Icons.logout,
                          variant: DsPillVariant.outline,
                          onPressed: onLogout,
                          compact: true,
                        ),
                      ] else ...<Widget>[
                        const SizedBox(height: 10),
                        IconButton(
                          onPressed: onLogout,
                          tooltip: 'Logout',
                          icon: Icon(
                            Icons.logout,
                            size: 18,
                            color: tokens.inkMuted,
                          ),
                        ),
                      ],
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
              color: tokens.coral,
              shape: BoxShape.circle,
              boxShadow: tokens.coralShadow,
            ),
            child: Icon(Icons.water_drop, color: tokens.card, size: 18),
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
  });

  final _NavDestination item;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

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
                ? Center(child: Icon(item.icon, size: 20, color: iconColor))
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
      message: item.label,
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
