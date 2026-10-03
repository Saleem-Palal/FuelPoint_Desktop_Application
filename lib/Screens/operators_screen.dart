import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/pin_hasher.dart';
import '../core/theme/dispensr_theme.dart';
import '../features/access/data/fingerprint_helper_client.dart';
import '../features/access/presentation/operator_fingerprint_enrollment_dialog.dart';
import '../core/widgets/app_screen_header.dart';
import '../core/widgets/fuel_point_stat_card.dart';
import '../core/widgets/responsive_layout.dart';
import '../features/station/presentation/workspace_refresh.dart';
import '../providers/operators_provider.dart';

class OperatorsScreen extends ConsumerStatefulWidget {
  const OperatorsScreen({super.key});

  @override
  ConsumerState<OperatorsScreen> createState() => _OperatorsScreenState();
}

class _OperatorsScreenState extends ConsumerState<OperatorsScreen> {
  final TextEditingController _search = TextEditingController();
  final TextEditingController _id = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _pin = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final FocusNode _nameFocus = FocusNode();
  bool _obscurePin = true;
  String? _boundSelectedId;
  bool _boundCreate = true;
  bool _didInitialFormSync = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(refreshOperatorsFromDatabase(ref));
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _id.dispose();
    _name.dispose();
    _pin.dispose();
    _searchFocus.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _syncForm(OperatorsState workspace) {
    if (workspace.isCreateMode) {
      if (_boundCreate && _boundSelectedId == null) {
        if (_id.text != workspace.nextId && _name.text.isEmpty) {
          _id.text = workspace.nextId;
        }
        return;
      }
      _boundCreate = true;
      _boundSelectedId = null;
      _id.text = workspace.nextId;
      _name.clear();
      _pin.clear();
      return;
    }
    final StationOperator? selected = workspace.selected;
    if (selected == null) {
      return;
    }
    if (_boundSelectedId == selected.id && !_boundCreate) {
      return;
    }
    _boundCreate = false;
    _boundSelectedId = selected.id;
    _id.text = selected.id;
    _name.text = selected.name;
    _pin.clear();
  }

  void _beginCreate() {
    ref.read(operatorsProvider.notifier).startCreate();
    final String nextId = ref.read(operatorsProvider).nextId;
    _boundCreate = true;
    _boundSelectedId = null;
    _id.text = nextId;
    _name.clear();
    _pin.clear();
    _nameFocus.requestFocus();
  }

  Future<void> _enrollFingerprint(StationOperator operator) async {
    final bool changed = await showOperatorFingerprintEnrollmentDialog(
      context,
      operatorId: operator.id,
      operatorName: operator.name,
      enrolled: operator.fingerprintEnrolled,
    );
    if (!mounted || !changed) {
      return;
    }
    await ref.read(operatorsProvider.notifier).reload();
  }

  Future<void> _save() async {
    final OperatorsNotifier notifier = ref.read(operatorsProvider.notifier);
    final OperatorMutationResult result = await notifier.save(
      operatorId: _id.text,
      operatorName: _name.text,
      pin: _pin.text,
    );
    if (!mounted) {
      return;
    }
    switch (result.outcome) {
      case OperatorMutationOutcome.created:
        _boundCreate = false;
        _boundSelectedId = _id.text.trim();
        _pin.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${result.operatorName} saved to directory')),
        );
      case OperatorMutationOutcome.updated:
        _pin.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${result.operatorName} updated')),
        );
      case OperatorMutationOutcome.openShiftBlocked:
        await _showOpenShiftLockDialog(result);
      case OperatorMutationOutcome.duplicateId:
      case OperatorMutationOutcome.invalidId:
      case OperatorMutationOutcome.invalidName:
      case OperatorMutationOutcome.invalidPin:
      case OperatorMutationOutcome.inUse:
      case OperatorMutationOutcome.notFound:
      case OperatorMutationOutcome.failed:
      case OperatorMutationOutcome.deleted:
        if (result.message.isNotEmpty) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(result.message)));
        }
    }
  }

  Future<void> _delete(StationOperator operator) async {
    if (operator.hasOpenShift) {
      await _showOpenShiftLockDialog(
        OperatorMutationResult(
          outcome: OperatorMutationOutcome.openShiftBlocked,
          operatorName: operator.name,
          shiftId: operator.openShiftId,
          message:
              '${operator.name} currently holds ${operator.statusLabel}. '
              'Close that OPEN shift before removing or inactivating this operator.',
        ),
      );
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        final DispensrTokens tokens = DispensrTokens.of(context);
        return AlertDialog(
          backgroundColor: tokens.card,
          surfaceTintColor: tokens.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radius20),
            side: BorderSide(color: tokens.line),
          ),
          title: Text(
            'Remove operator',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: tokens.ink,
            ),
          ),
          content: Text(
            'Delete ${operator.name} (${operator.id}) from the station directory? '
            'This cannot be undone.',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 13,
              height: 1.4,
              color: tokens.inkMuted,
            ),
          ),
          actions: <Widget>[
            DsPillButton(
              label: 'Cancel',
              variant: DsPillVariant.outline,
              compact: true,
              onPressed: () => Navigator.of(context).pop(false),
            ),
            DsPillButton(
              label: 'Delete',
              variant: DsPillVariant.danger,
              compact: true,
              icon: Icons.delete_outline,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final OperatorMutationResult result = await ref
        .read(operatorsProvider.notifier)
        .delete(operator.id);
    if (!mounted) {
      return;
    }
    if (result.isOpenShiftBlock) {
      await _showOpenShiftLockDialog(result);
      return;
    }
    if (result.outcome == OperatorMutationOutcome.deleted) {
      _boundCreate = true;
      _boundSelectedId = null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${result.operatorName} removed')));
      return;
    }
    if (result.message.isNotEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  Future<void> _showOpenShiftLockDialog(OperatorMutationResult result) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final int shiftId = result.shiftId ?? 0;
    final String name = result.operatorName.isEmpty
        ? 'This operator'
        : result.operatorName;
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: tokens.card,
          surfaceTintColor: tokens.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radius20),
            side: BorderSide(color: tokens.warn.withValues(alpha: 0.55)),
          ),
          title: Row(
            children: <Widget>[
              Icon(Icons.shield_outlined, color: tokens.warn, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Shift lock — action blocked',
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
          content: Text(
            result.message.isNotEmpty
                ? result.message
                : '$name currently holds Shift #$shiftId. '
                      'Close the OPEN shift before deleting or inactivating this operator.',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 13,
              height: 1.45,
              color: tokens.inkMuted,
            ),
          ),
          actions: <Widget>[
            DsPillButton(
              label: 'Understood',
              compact: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  void _onKeypadDigit(String digit) {
    if (_pin.text.length >= PinHasher.maxPinLength) {
      return;
    }
    setState(() {
      _pin.text = '${_pin.text}$digit';
      _pin.selection = TextSelection.collapsed(offset: _pin.text.length);
    });
  }

  void _onKeypadBackspace() {
    if (_pin.text.isEmpty) {
      return;
    }
    setState(() {
      _pin.text = _pin.text.substring(0, _pin.text.length - 1);
      _pin.selection = TextSelection.collapsed(offset: _pin.text.length);
    });
  }

  void _onKeypadClear() {
    setState(() {
      _pin.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final OperatorsState workspace = ref.watch(operatorsProvider);
    ref.listen<OperatorsState>(operatorsProvider, (
      OperatorsState? previous,
      OperatorsState next,
    ) {
      final bool selectionChanged = previous?.selectedId != next.selectedId;
      final bool createChanged =
          (previous?.isCreateMode ?? true) != next.isCreateMode;
      final bool nextIdChanged =
          next.isCreateMode &&
          previous?.nextId != next.nextId &&
          _name.text.isEmpty;
      if (!selectionChanged && !createChanged && !nextIdChanged) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _syncForm(next);
        }
      });
    });
    if (!_didInitialFormSync) {
      _didInitialFormSync = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _syncForm(ref.read(operatorsProvider));
        }
      });
    }
    final StationOperator? selected = workspace.selected;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          _searchFocus.requestFocus();
        },
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            _beginCreate,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          unawaited(_save());
        },
      },
      child: Focus(
        autofocus: true,
        child: ColoredBox(
          color: tokens.canvas,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: AppScreenHeader(
                  title: 'Operators',
                  icon: Icons.manage_accounts_outlined,
                  trailingAction: AppHeaderActionButton(
                    label: 'New Operator',
                    icon: Icons.person_add_alt_1_outlined,
                    onPressed: _beginCreate,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _KpiBar(workspace: workspace),
                      const SizedBox(height: 10),
                      Expanded(
                        child: LayoutBuilder(
                          builder:
                              (BuildContext context, BoxConstraints bounds) {
                                final bool stacked = bounds.maxWidth < 980;
                                final Widget directory = _DirectoryPane(
                                  search: _search,
                                  searchFocus: _searchFocus,
                                  workspace: workspace,
                                  onSearch: (String value) {
                                    ref
                                        .read(operatorsProvider.notifier)
                                        .setSearch(value);
                                  },
                                  onSelect: (String id) {
                                    ref
                                        .read(operatorsProvider.notifier)
                                        .select(id);
                                  },
                                  onCreate: _beginCreate,
                                );
                                final Widget form = _FormPane(
                                  isCreate: workspace.isCreateMode,
                                  busy: workspace.busy,
                                  selected: selected,
                                  idController: _id,
                                  nameController: _name,
                                  pinController: _pin,
                                  nameFocus: _nameFocus,
                                  obscurePin: _obscurePin,
                                  onToggleObscure: () {
                                    setState(() {
                                      _obscurePin = !_obscurePin;
                                    });
                                  },
                                  onKeypadDigit: _onKeypadDigit,
                                  onKeypadBackspace: _onKeypadBackspace,
                                  onKeypadClear: _onKeypadClear,
                                  onSave: () {
                                    unawaited(_save());
                                  },
                                  onDelete: selected == null
                                      ? null
                                      : () {
                                          unawaited(_delete(selected));
                                        },
                                  onEnrollFingerprint:
                                      selected == null ||
                                          !FingerprintHelperSession.isSupported
                                      ? null
                                      : () {
                                          unawaited(
                                            _enrollFingerprint(selected),
                                          );
                                        },
                                  onCancel: _beginCreate,
                                );
                                if (stacked) {
                                  return ListView(
                                    children: <Widget>[
                                      SizedBox(
                                        height: bounds.maxHeight > 360
                                            ? bounds.maxHeight
                                            : 360,
                                        child: directory,
                                      ),
                                      const SizedBox(height: 10),
                                      SizedBox(height: 640, child: form),
                                    ],
                                  );
                                }
                                return Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: <Widget>[
                                    Expanded(flex: 3, child: directory),
                                    const SizedBox(width: 10),
                                    Expanded(flex: 2, child: form),
                                  ],
                                );
                              },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KpiBar extends StatelessWidget {
  const _KpiBar({required this.workspace});

  final OperatorsState workspace;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return ExtentWrap(
      maxCrossAxisExtent: 320,
      children: <Widget>[
        FuelPointStatCard(
          title: 'Directory',
          value: '${workspace.operators.length}',
          subtitle: 'Station operator profiles',
          icon: Icons.groups_outlined,
          badgeBackgroundColor: tokens.coral.withValues(alpha: 0.12),
          badgeIconColor: tokens.coralPressed,
        ),
        FuelPointStatCard(
          title: 'On Open Shift',
          value: '${workspace.onShiftCount}',
          subtitle: 'Live OPEN shift holders',
          icon: Icons.play_circle_outline,
          badgeBackgroundColor: tokens.good.withValues(alpha: 0.12),
          badgeIconColor: tokens.good,
          borderColor: tokens.good.withValues(alpha: 0.35),
          valueColor: tokens.good,
        ),
        FuelPointStatCard(
          title: 'Idle',
          value: '${workspace.idleCount}',
          subtitle: 'No OPEN shift assigned',
          icon: Icons.pause_circle_outline,
          badgeBackgroundColor: tokens.inkMuted.withValues(alpha: 0.12),
          badgeIconColor: tokens.inkMuted,
        ),
      ],
    );
  }
}

class _DirectoryPane extends StatelessWidget {
  const _DirectoryPane({
    required this.search,
    required this.searchFocus,
    required this.workspace,
    required this.onSearch,
    required this.onSelect,
    required this.onCreate,
  });

  final TextEditingController search;
  final FocusNode searchFocus;
  final OperatorsState workspace;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onSelect;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final List<StationOperator> rows = workspace.filtered;
    return Container(
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.radius20),
        border: Border.all(color: tokens.line),
        boxShadow: tokens.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: <Widget>[
                Icon(Icons.badge_outlined, size: 18, color: tokens.coral),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Operator Directory',
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: tokens.ink,
                    ),
                  ),
                ),
                DsPillButton(
                  label: 'New',
                  compact: true,
                  icon: Icons.add,
                  onPressed: onCreate,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: TextField(
              controller: search,
              focusNode: searchFocus,
              onChanged: onSearch,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: tokens.ink,
              ),
              decoration: InputDecoration(
                hintText: 'Search by name or operator ID',
                prefixIcon: Icon(
                  Icons.search,
                  size: 18,
                  color: tokens.inkMuted,
                ),
                suffixIcon: search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          search.clear();
                          onSearch('');
                        },
                        icon: Icon(
                          Icons.close,
                          size: 16,
                          color: tokens.inkMuted,
                        ),
                      ),
              ),
            ),
          ),
          Divider(color: tokens.line, height: 1),
          Expanded(
            child: workspace.loading
                ? Center(child: CircularProgressIndicator(color: tokens.coral))
                : rows.isEmpty
                ? Center(
                    child: Text(
                      workspace.search.trim().isEmpty
                          ? 'No operators on file. Create the first profile.'
                          : 'No operators match that search.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        color: tokens.inkMuted,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (BuildContext context, int index) {
                      final StationOperator operator = rows[index];
                      return _OperatorCard(
                        operator: operator,
                        selected: operator.id == workspace.selectedId,
                        onTap: () => onSelect(operator.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _OperatorCard extends StatefulWidget {
  const _OperatorCard({
    required this.operator,
    required this.selected,
    required this.onTap,
  });

  final StationOperator operator;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_OperatorCard> createState() => _OperatorCardState();
}

class _OperatorCardState extends State<_OperatorCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final StationOperator operator = widget.operator;
    final bool onShift = operator.hasOpenShift;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color border = widget.selected
        ? tokens.coral
        : (_hovered ? tokens.coral.withValues(alpha: 0.45) : tokens.line);
    final Color fill = widget.selected
        ? tokens.coral.withValues(alpha: 0.08)
        : (_hovered ? tokens.canvas : tokens.card);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(tokens.radius12),
        child: InkWell(
          onTap: widget.onTap,
          hoverColor: tokens.ink.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(tokens.radius12),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(tokens.radius12),
              border: Border.all(
                color: border,
                width: widget.selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 22,
                  backgroundColor: onShift
                      ? tokens.good.withValues(alpha: 0.16)
                      : tokens.line,
                  child: Text(
                    operator.initials,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: onShift ? tokens.good : tokens.inkMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              operator.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Roboto',
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: colors.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          DsStatusPill(
                            label: operator.statusLabel,
                            foreground: onShift ? tokens.good : tokens.inkMuted,
                            background:
                                (onShift ? tokens.good : tokens.inkMuted)
                                    .withValues(alpha: 0.12),
                            border: (onShift ? tokens.good : tokens.inkMuted)
                                .withValues(alpha: 0.35),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        children: <Widget>[
                          _MetaChip(icon: Icons.tag, label: operator.id),
                          _MetaChip(
                            icon: Icons.lock_outline,
                            label: operator.maskedPin,
                          ),
                          if (operator.fingerprintEnrolled)
                            const _MetaChip(
                              icon: Icons.fingerprint,
                              label: 'Fingerprint',
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 13, color: tokens.inkMuted),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w600,
            fontSize: 12,
            letterSpacing: 0.4,
            color: tokens.inkMuted,
          ),
        ),
      ],
    );
  }
}

class _FormPane extends StatelessWidget {
  const _FormPane({
    required this.isCreate,
    required this.busy,
    required this.selected,
    required this.idController,
    required this.nameController,
    required this.pinController,
    required this.nameFocus,
    required this.obscurePin,
    required this.onToggleObscure,
    required this.onKeypadDigit,
    required this.onKeypadBackspace,
    required this.onKeypadClear,
    required this.onSave,
    required this.onCancel,
    this.onDelete,
    this.onEnrollFingerprint,
  });

  final bool isCreate;
  final bool busy;
  final StationOperator? selected;
  final TextEditingController idController;
  final TextEditingController nameController;
  final TextEditingController pinController;
  final FocusNode nameFocus;
  final bool obscurePin;
  final VoidCallback onToggleObscure;
  final ValueChanged<String> onKeypadDigit;
  final VoidCallback onKeypadBackspace;
  final VoidCallback onKeypadClear;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final VoidCallback? onDelete;
  final VoidCallback? onEnrollFingerprint;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final bool onShift = selected?.hasOpenShift ?? false;
    return Container(
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.radius20),
        border: Border.all(color: tokens.line),
        boxShadow: tokens.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: <Widget>[
                Icon(
                  isCreate
                      ? Icons.person_add_alt_1_outlined
                      : Icons.edit_outlined,
                  size: 18,
                  color: tokens.coral,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isCreate ? 'New Operator' : 'Edit Profile',
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: tokens.ink,
                    ),
                  ),
                ),
                if (onShift)
                  DsStatusPill(
                    label: selected?.statusLabel ?? 'Active',
                    foreground: tokens.good,
                    background: tokens.good.withValues(alpha: 0.12),
                    border: tokens.good.withValues(alpha: 0.35),
                  ),
              ],
            ),
          ),
          Divider(color: tokens.line, height: 1),
          Expanded(
            child: ScrollableConstrainedBody(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _FieldLabel(label: 'Operator ID'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: idController,
                    readOnly: !isCreate,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[A-Za-z0-9\-_]'),
                      ),
                    ],
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: tokens.ink,
                    ),
                    decoration: InputDecoration(
                      hintText: 'mgr-1',
                      prefixIcon: Icon(
                        Icons.tag,
                        size: 18,
                        color: tokens.inkMuted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _FieldLabel(label: 'Operator Full Name'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameController,
                    focusNode: nameFocus,
                    textCapitalization: TextCapitalization.words,
                    onSubmitted: (_) => onSave(),
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: tokens.ink,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'e.g. Ali Khan',
                      prefixIcon: Icon(Icons.person_outline, size: 18),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _FieldLabel(
                    label: isCreate
                        ? 'PIN (4–6 digits)'
                        : 'PIN (leave blank to keep current)',
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: pinController,
                    obscureText: obscurePin,
                    maxLength: PinHasher.maxPinLength,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(PinHasher.maxPinLength),
                    ],
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      letterSpacing: 4,
                      color: tokens.ink,
                    ),
                    decoration: InputDecoration(
                      hintText: isCreate ? '••••' : '••••  keep current',
                      counterText: '',
                      prefixIcon: Icon(
                        Icons.lock_outline,
                        size: 18,
                        color: tokens.inkMuted,
                      ),
                      suffixIcon: IconButton(
                        tooltip: obscurePin ? 'Show PIN' : 'Hide PIN',
                        onPressed: onToggleObscure,
                        icon: Icon(
                          obscurePin
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 18,
                          color: tokens.inkMuted,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Desktop keypad',
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                      letterSpacing: 0.6,
                      color: tokens.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 200,
                    child: _PinKeypad(
                      onDigit: onKeypadDigit,
                      onBackspace: onKeypadBackspace,
                      onClear: onKeypadClear,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (isCreate)
                    Text(
                      'Save this operator first, then enroll a fingerprint.',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 11,
                        height: 1.35,
                        color: tokens.inkMuted,
                      ),
                    )
                  else if (onEnrollFingerprint != null) ...<Widget>[
                    DsPillButton(
                      label: (selected?.fingerprintEnrolled ?? false)
                          ? 'Re-enroll fingerprint'
                          : 'Enroll fingerprint',
                      icon: Icons.fingerprint,
                      compact: true,
                      variant: DsPillVariant.outline,
                      onPressed: busy ? null : onEnrollFingerprint,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      (selected?.fingerprintEnrolled ?? false)
                          ? 'Fingerprint enrolled. It can unlock login and shift actions. PIN stays the backup.'
                          : 'Optional fingerprint for login and shift actions. PIN stays the backup.',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 11,
                        height: 1.35,
                        color: tokens.inkMuted,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      if (!isCreate) ...<Widget>[
                        Expanded(
                          child: DsPillButton(
                            label: 'Delete',
                            variant: DsPillVariant.danger,
                            icon: Icons.delete_outline,
                            compact: true,
                            onPressed: busy ? null : onDelete,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: DsPillButton(
                          label: isCreate ? 'Cancel' : 'New',
                          variant: DsPillVariant.outline,
                          compact: true,
                          onPressed: busy ? null : onCancel,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: DsPillButton(
                          label: busy
                              ? 'Saving…'
                              : (isCreate ? 'Create Operator' : 'Save Changes'),
                          icon: Icons.check,
                          compact: true,
                          onPressed: busy ? null : onSave,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontFamily: 'Roboto',
        fontWeight: FontWeight.w700,
        fontSize: 10,
        letterSpacing: 0.8,
        color: colors.onSurfaceVariant,
      ),
    );
  }
}

class _PinKeypad extends StatelessWidget {
  const _PinKeypad({
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  static const List<String> _keys = <String>[
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    'C',
    '0',
    '⌫',
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _keys.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: constraints.maxHeight <= 0
                ? 1.4
                : (constraints.maxWidth / 3) /
                      ((constraints.maxHeight - 16) / 4),
          ),
          itemBuilder: (BuildContext context, int index) {
            final String key = _keys[index];
            if (key == 'C') {
              return _KeypadKey(
                label: 'C',
                variant: _KeypadVariant.clear,
                onPressed: onClear,
              );
            }
            if (key == '⌫') {
              return _KeypadKey(
                label: '⌫',
                variant: _KeypadVariant.backspace,
                onPressed: onBackspace,
              );
            }
            return _KeypadKey(
              label: key,
              variant: _KeypadVariant.digit,
              onPressed: () => onDigit(key),
            );
          },
        );
      },
    );
  }
}

enum _KeypadVariant { digit, clear, backspace }

class _KeypadKey extends StatelessWidget {
  const _KeypadKey({
    required this.label,
    required this.variant,
    required this.onPressed,
  });

  final String label;
  final _KeypadVariant variant;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    late final Color background;
    late final Color foreground;
    late final Color border;
    switch (variant) {
      case _KeypadVariant.digit:
        background = tokens.canvas;
        foreground = tokens.ink;
        border = tokens.line;
      case _KeypadVariant.clear:
        background = tokens.warn.withValues(alpha: 0.12);
        foreground = tokens.warn;
        border = tokens.warn.withValues(alpha: 0.35);
      case _KeypadVariant.backspace:
        background = tokens.bad.withValues(alpha: 0.10);
        foreground = tokens.bad;
        border = tokens.bad.withValues(alpha: 0.30);
    }
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(tokens.radius12),
      child: InkWell(
        onTap: onPressed,
        hoverColor: tokens.ink.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(tokens.radius12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(tokens.radius12),
            border: Border.all(color: border),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w700,
                fontSize: 20,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
