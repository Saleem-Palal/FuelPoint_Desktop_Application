import 'package:flutter/material.dart';

import '../../../core/theme/dispensr_theme.dart';
import '../../../features/shift/domain/shift_models.dart';
import '../../../features/station/domain/dashboard_models.dart';
import '../../../features/station/domain/dispenser_models.dart';

/// Per-bay helper picker. Shows who is already on each unit so a manager
/// can keep or reassign duty before a shift starts or hands over.
class HelperUnitAssignmentPanel extends StatelessWidget {
  const HelperUnitAssignmentPanel({
    super.key,
    required this.helpers,
    required this.assignments,
    required this.originalAssignments,
    required this.onChanged,
  });

  final List<HelperProfile> helpers;
  final Map<int, String?> assignments;
  final Map<int, String?> originalAssignments;
  final ValueChanged<Map<int, String?>> onChanged;

  String _helperName(String? helperId) {
    if (helperId == null || helperId.isEmpty) {
      return 'Unassigned';
    }
    final HelperProfile? helper = helperById(helpers, helperId);
    return helper?.name ?? 'Unassigned';
  }

  String _menuLabel(HelperProfile helper) {
    final List<int> units = <int>[
      for (final int unitId in dispenserUnitIds)
        if (assignments[unitId] == helper.id) unitId,
    ];
    if (units.isEmpty) {
      return helper.name;
    }
    final String tags = units.map((int id) => 'U$id').join(' · ');
    return '${helper.name} · $tags';
  }

  void _assign(int unitId, String? helperId) {
    onChanged(<int, String?>{...assignments, unitId: helperId});
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    if (helpers.isEmpty) {
      return Center(
        child: Text(
          'No helpers on file. Add helpers on the Helper tab, or start with all units unassigned.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 13,
            height: 1.4,
            color: tokens.inkMuted,
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: dispenserUnitIds.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) {
        final int unitId = dispenserUnitIds[index];
        final String rawId = assignments[unitId] ?? '';
        final bool known =
            rawId.isEmpty || helpers.any((HelperProfile h) => h.id == rawId);
        final String selectedId = known ? rawId : '';
        final String originalId = originalAssignments[unitId] ?? '';
        final bool changed = selectedId != originalId;
        return _UnitAssignmentRow(
          unitId: unitId,
          selectedId: selectedId,
          currentLabel: _helperName(originalId.isEmpty ? null : originalId),
          changed: changed,
          helpers: helpers,
          menuLabel: _menuLabel,
          onChanged: (String? helperId) => _assign(unitId, helperId),
        );
      },
    );
  }
}

class _UnitAssignmentRow extends StatelessWidget {
  const _UnitAssignmentRow({
    required this.unitId,
    required this.selectedId,
    required this.currentLabel,
    required this.changed,
    required this.helpers,
    required this.menuLabel,
    required this.onChanged,
  });

  final int unitId;
  final String selectedId;
  final String currentLabel;
  final bool changed;
  final List<HelperProfile> helpers;
  final String Function(HelperProfile helper) menuLabel;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: tokens.canvas,
        borderRadius: BorderRadius.circular(tokens.radius12),
        border: Border.all(
          color: changed ? tokens.coral.withValues(alpha: 0.55) : tokens.line,
        ),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 72,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  formatBayLabel(unitId),
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: tokens.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  changed ? 'Was $currentLabel' : 'Now $currentLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w500,
                    fontSize: 10,
                    color: changed ? tokens.coral : tokens.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedId,
                isDense: true,
                isExpanded: true,
                borderRadius: BorderRadius.circular(tokens.radius12),
                dropdownColor: tokens.card,
                items: <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(
                    value: '',
                    child: Text(
                      'Unassigned',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                        color: tokens.inkMuted,
                      ),
                    ),
                  ),
                  for (final HelperProfile helper in helpers)
                    DropdownMenuItem<String>(
                      value: helper.id,
                      child: Text(
                        menuLabel(helper),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: tokens.ink,
                        ),
                      ),
                    ),
                ],
                onChanged: (String? value) {
                  if (value == null || value.isEmpty) {
                    onChanged(null);
                    return;
                  }
                  onChanged(value);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
