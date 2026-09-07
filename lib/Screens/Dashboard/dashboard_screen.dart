import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/dispensr_theme.dart';
import '../../core/widgets/app_screen_header.dart';
import '../../features/station/domain/dashboard_models.dart';
import '../../features/station/presentation/dashboard_providers.dart';
import '../../features/station/presentation/workspace_refresh.dart';
import 'Widgets/dashboard_bay_strip.dart';
import 'Widgets/dashboard_kpi_row.dart';
import 'Widgets/dashboard_peak_hours.dart';
import 'Widgets/dashboard_staff_strip.dart';
import 'Widgets/dashboard_udhaar_watchlist.dart';

/// Financial command center. Aggregates SQLite sales/credit only — no live
/// dispenser telemetry and no shift-management controls.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final ScrollController _pageScroll = ScrollController();
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_refreshFromDatabase(silent: true));
      }
    });
  }

  @override
  void dispose() {
    _pageScroll.dispose();
    super.dispose();
  }

  Future<void> _refreshFromDatabase({bool silent = false}) async {
    if (_refreshing) {
      return;
    }
    setState(() {
      _refreshing = true;
    });
    try {
      await refreshWorkspaceFromDatabase(ref);
    } catch (error) {
      if (!mounted || silent) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not refresh dashboard. $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final DashboardSnapshot snapshot = ref.watch(dashboardSnapshotProvider);

    return ColoredBox(
      color: tokens.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: AppScreenHeader(
              title: 'Dashboard',
              icon: Icons.grid_view_outlined,
              trailingAction: AppHeaderActionButton(
                label: 'Refresh',
                icon: Icons.refresh,
                busy: _refreshing,
                onPressed: () {
                  unawaited(_refreshFromDatabase());
                },
              ),
            ),
          ),
          if (_refreshing)
            LinearProgressIndicator(
              minHeight: 2,
              color: tokens.coral,
              backgroundColor: tokens.line,
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints viewport) {
                final bool wide = viewport.maxWidth >= 1080;
                return Scrollbar(
                  controller: _pageScroll,
                  child: SingleChildScrollView(
                    controller: _pageScroll,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: viewport.maxWidth),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          DashboardKpiRow(kpis: snapshot.kpis),
                          const SizedBox(height: 10),
                          DashboardBayStrip(
                            bays: snapshot.bays,
                            range: ref.watch(dashboardBayRangeProvider),
                            onRangeChanged: (DashboardRangePreset preset) {
                              ref
                                      .read(dashboardBayRangeProvider.notifier)
                                      .state =
                                  preset;
                            },
                          ),
                          const SizedBox(height: 10),
                          DashboardStaffStrip(
                            title: 'Manager sales',
                            emptyMessage: 'No managers on file.',
                            members: snapshot.managers,
                            range: ref.watch(dashboardManagerRangeProvider),
                            onRangeChanged: (DashboardRangePreset preset) {
                              ref
                                      .read(
                                        dashboardManagerRangeProvider.notifier,
                                      )
                                      .state =
                                  preset;
                            },
                          ),
                          const SizedBox(height: 10),
                          DashboardStaffStrip(
                            title: 'Helper sales',
                            emptyMessage: 'No helpers on file.',
                            members: snapshot.helpers,
                            range: ref.watch(dashboardHelperRangeProvider),
                            onRangeChanged: (DashboardRangePreset preset) {
                              ref
                                      .read(
                                        dashboardHelperRangeProvider.notifier,
                                      )
                                      .state =
                                  preset;
                            },
                          ),
                          const SizedBox(height: 10),
                          if (wide)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Expanded(
                                  flex: 3,
                                  child: DashboardPeakHours(snapshot: snapshot),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 2,
                                  child: DashboardUdhaarWatchlist(
                                    rows: snapshot.watchlist,
                                    totalDebtors: snapshot.watchlistTotal,
                                  ),
                                ),
                              ],
                            )
                          else ...<Widget>[
                            DashboardPeakHours(snapshot: snapshot),
                            const SizedBox(height: 10),
                            DashboardUdhaarWatchlist(
                              rows: snapshot.watchlist,
                              totalDebtors: snapshot.watchlistTotal,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
