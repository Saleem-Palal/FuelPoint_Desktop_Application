import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/dispensr_theme.dart';
import '../../core/widgets/app_screen_header.dart';
import '../../core/widgets/date_range_selector.dart';
import '../../features/station/data/ledger_pdf_export.dart';
import '../../features/station/data/transaction_store.dart';
import '../../features/station/domain/dispenser_models.dart';
import '../../features/station/domain/money_format.dart';
import '../../features/station/domain/shift_ledger_models.dart';
import '../../features/station/presentation/ledger_providers.dart';
import '../../features/station/presentation/station_providers.dart';
import '../Sale Screen/Widgets/Services/generate_receipt.dart';
import '../Sale Screen/Widgets/Services/receipt_preview_widget.dart';
import 'Widgets/edit_purchase_dialog.dart';
import 'Widgets/shift_wise_ledger_view.dart';

class LedgerScreen extends ConsumerStatefulWidget {
  const LedgerScreen({super.key});

  @override
  ConsumerState<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends ConsumerState<LedgerScreen> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(_onSearchFocusChange);
  }

  void _onSearchFocusChange() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _searchFocus.removeListener(_onSearchFocusChange);
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final LedgerQuery query = ref.watch(ledgerQueryProvider);

    final bool shiftWiseSales =
        query.tab == LedgerTab.sales &&
        query.salesMode == SalesLedgerMode.shiftWise;
    final List<ShiftLedgerSummary> shifts = shiftWiseSales
        ? (ref.watch(shiftWisePagerProvider).valueOrNull ??
              const <ShiftLedgerSummary>[])
        : const <ShiftLedgerSummary>[];
    final bool shiftPagerActive = shiftWiseSales && !_searchFocus.hasFocus;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          _searchFocus.requestFocus();
        },
        if (shiftPagerActive) ...<ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
            ref.read(ledgerQueryProvider.notifier).stepShift(-1, shifts);
          },
          const SingleActivator(LogicalKeyboardKey.arrowRight): () {
            ref.read(ledgerQueryProvider.notifier).stepShift(1, shifts);
          },
        },
      },
      child: Focus(
        autofocus: true,
        child: ColoredBox(
          color: tokens.canvas,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: AppScreenHeader(
                  title: 'Ledger Screen',
                  icon: Icons.menu_book_outlined,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _TabToggle(
                        tab: query.tab,
                        onChanged: (LedgerTab tab) {
                          ref.read(ledgerQueryProvider.notifier).setTab(tab);
                        },
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: query.tab == LedgerTab.sales
                            ? _SalesLedgerView(
                                search: _search,
                                searchFocus: _searchFocus,
                              )
                            : const _PurchaseLedgerView(),
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

class _TabToggle extends StatelessWidget {
  const _TabToggle({required this.tab, required this.onChanged});

  final LedgerTab tab;
  final ValueChanged<LedgerTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.radius20),
        border: Border.all(color: tokens.line),
        boxShadow: tokens.cardShadow,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _TabChip(
              label: 'Sales Ledger',
              icon: Icons.point_of_sale_outlined,
              selected: tab == LedgerTab.sales,
              onTap: () => onChanged(LedgerTab.sales),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _TabChip(
              label: 'Purchase Ledger',
              icon: Icons.local_shipping_outlined,
              selected: tab == LedgerTab.purchases,
              onTap: () => onChanged(LedgerTab.purchases),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final Color fg = selected ? tokens.coralPressed : tokens.inkMuted;
    final Color bg = selected
        ? tokens.coral.withValues(alpha: 0.14)
        : Colors.transparent;
    final Color border = selected ? tokens.coral : Colors.transparent;

    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius12),
        side: BorderSide(color: border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radius12),
        hoverColor: tokens.ink.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SalesLedgerView extends ConsumerWidget {
  const _SalesLedgerView({required this.search, required this.searchFocus});

  final TextEditingController search;
  final FocusNode searchFocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final LedgerQuery query = ref.watch(ledgerQueryProvider);
    final SalesLedgerSnapshot slice = ref.watch(salesLedgerSliceProvider);
    final bool shiftWise = query.salesMode == SalesLedgerMode.shiftWise;
    final AsyncValue<List<ShiftLedgerSummary>> shiftsAsync = shiftWise
        ? ref.watch(shiftWisePagerProvider)
        : const AsyncValue<List<ShiftLedgerSummary>>.data(
            <ShiftLedgerSummary>[],
          );
    final ShiftLedgerSummary? selectedShift = shiftWise
        ? ref.watch(selectedShiftSummaryProvider)
        : null;
    final String countLabel = slice.totalCount == 1
        ? 'transaction'
        : 'transactions';
    final List<ShiftLedgerSummary> shifts =
        shiftsAsync.valueOrNull ?? const <ShiftLedgerSummary>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SalesKpiBar(slice: slice),
        const SizedBox(height: 10),
        _SalesToolbar(
          search: search,
          searchFocus: searchFocus,
          query: query,
          slice: slice,
          selectedShift: selectedShift,
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _TableCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 12, 8),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: shiftWise
                            ? ShiftLedgerTableHeader(summary: selectedShift)
                            : Text(
                                'Sales History',
                                style: TextStyle(
                                  fontFamily: 'Roboto',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: tokens.ink,
                                ),
                              ),
                      ),
                      if (shiftWise) ShiftLedgerPager(shifts: shifts),
                    ],
                  ),
                ),
                Divider(color: tokens.line, height: 1),
                Expanded(child: _salesTableBody(ref, shiftsAsync)),
                Divider(color: tokens.line, height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${slice.totalCount} $countLabel',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                        color: tokens.inkMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _salesTableBody(
    WidgetRef ref,
    AsyncValue<List<ShiftLedgerSummary>> shiftsAsync,
  ) {
    final LedgerQuery query = ref.watch(ledgerQueryProvider);
    final SalesLedgerSnapshot slice = ref.watch(salesLedgerSliceProvider);
    final bool shiftWise = query.salesMode == SalesLedgerMode.shiftWise;
    final bool filtered =
        query.salesRange != null ||
        query.unitId != null ||
        query.search.trim().isNotEmpty;

    if (shiftWise) {
      return shiftsAsync.when(
        skipLoadingOnReload: true,
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _EmptyHint(message: 'Could not load shift ledger. $error'),
                const SizedBox(height: 12),
                DsPillButton(
                  label: 'Retry',
                  compact: true,
                  onPressed: () {
                    ref.invalidate(shiftLedgerSummariesProvider);
                  },
                ),
              ],
            ),
          );
        },
        data: (List<ShiftLedgerSummary> shifts) {
          if (shifts.isEmpty) {
            return _EmptyHint(
              message: query.salesRange != null
                  ? 'No shifts match this date range.'
                  : 'No shifts recorded yet.',
            );
          }
          if (slice.rows.isEmpty) {
            return _EmptyHint(
              message: filtered
                  ? 'No sales match this filter.'
                  : 'No sales in this shift.',
            );
          }
          return _SalesDataTable(rows: slice.rows);
        },
      );
    }

    if (slice.rows.isEmpty) {
      return _EmptyHint(
        message: filtered ? 'No sales match this filter.' : 'No sales yet.',
      );
    }
    return _SalesDataTable(rows: slice.rows);
  }
}

class _SalesModeToggle extends StatelessWidget {
  const _SalesModeToggle({required this.mode, required this.onChanged});

  final SalesLedgerMode mode;
  final ValueChanged<SalesLedgerMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: tokens.canvas,
        borderRadius: BorderRadius.circular(tokens.radius12),
        border: Border.all(color: tokens.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _SalesModeChip(
            label: 'All Transactions',
            selected: mode == SalesLedgerMode.allTransactions,
            onTap: () => onChanged(SalesLedgerMode.allTransactions),
          ),
          const SizedBox(width: 4),
          _SalesModeChip(
            label: 'Shift-Wise',
            selected: mode == SalesLedgerMode.shiftWise,
            onTap: () => onChanged(SalesLedgerMode.shiftWise),
          ),
        ],
      ),
    );
  }
}

class _SalesModeChip extends StatelessWidget {
  const _SalesModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Material(
      color: selected
          ? tokens.coral.withValues(alpha: 0.14)
          : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: selected ? tokens.coral : Colors.transparent),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        hoverColor: tokens.ink.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: selected ? tokens.coralPressed : tokens.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _PurchaseLedgerView extends ConsumerWidget {
  const _PurchaseLedgerView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final LedgerQuery query = ref.watch(ledgerQueryProvider);
    final PurchaseLedgerSnapshot slice = ref.watch(purchaseLedgerSliceProvider);
    final bool filtered = query.purchaseRange != null;
    final String entryLabel = slice.totalCount == 1 ? 'Entry' : 'Entries';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _PurchaseKpiBar(slice: slice),
        const SizedBox(height: 10),
        Expanded(
          child: _TableCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 12, 8),
                  child: Row(
                    children: <Widget>[
                      Text(
                        'Purchase History',
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: tokens.ink,
                        ),
                      ),
                      const Spacer(),
                      DateRangeFilterButton(
                        range: query.purchaseRange,
                        onChanged: (DateTimeRange? range) {
                          ref
                              .read(ledgerQueryProvider.notifier)
                              .setPurchaseRange(range);
                        },
                      ),
                      const SizedBox(width: 8),
                      _GeneratePdfButton(
                        onPressed: () {
                          unawaited(
                            _exportLedgerPdf(
                              context,
                              empty: slice.rows.isEmpty,
                              export: () {
                                return LedgerPdfExport.instance.exportPurchases(
                                  slice: slice,
                                  range: query.purchaseRange,
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                Divider(color: tokens.line, height: 1),
                Expanded(
                  child: slice.rows.isEmpty
                      ? _EmptyHint(
                          message: filtered
                              ? 'No purchases match this date range.'
                              : 'No purchases yet.',
                        )
                      : _PurchaseDataTable(
                          rows: slice.rows,
                          onEdit: (PurchaseTransaction row) {
                            unawaited(_editPurchase(context, row));
                          },
                        ),
                ),
                Divider(color: tokens.line, height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${slice.totalCount} $entryLabel',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                        color: tokens.inkMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SalesKpiBar extends StatelessWidget {
  const _SalesKpiBar({required this.slice});

  final SalesLedgerSnapshot slice;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: _KpiCard(
            spec: _KpiSpec(
              label: 'Total Sales Amount',
              value: formatPkr(slice.totalAmountPkr),
              hint: '${slice.totalCount} rows',
              icon: Icons.trending_up,
              tint: tokens.good,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            spec: _KpiSpec(
              label: 'Total Volume Dispensed',
              value: formatLiters(slice.totalVolumeLiters),
              hint: 'Filtered view',
              icon: Icons.water_drop_outlined,
              tint: tokens.coral,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            spec: _KpiSpec(
              label: 'Total Udhaar Amount',
              value: formatPkr(slice.udhaarAmountPkr),
              hint: 'Credit sales',
              icon: Icons.handshake_outlined,
              tint: tokens.warn,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            spec: _KpiSpec(
              label: 'Total Udhaar Transactions',
              value: '${slice.udhaarCount}',
              hint: slice.udhaarCount == 1 ? 'entry' : 'entries',
              icon: Icons.receipt_long_outlined,
              tint: tokens.bad,
            ),
          ),
        ),
      ],
    );
  }
}

class _PurchaseKpiBar extends StatelessWidget {
  const _PurchaseKpiBar({required this.slice});

  final PurchaseLedgerSnapshot slice;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: _KpiCard(
            spec: _KpiSpec(
              label: 'Total Purchase Amount',
              value: formatPkr(slice.totalAmountPkr),
              hint: '${slice.totalCount} loads',
              icon: Icons.account_balance_wallet_outlined,
              tint: tokens.good,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            spec: _KpiSpec(
              label: 'Total Net Volume Purchased',
              value: formatLiters(slice.totalVolumeLiters),
              hint: 'Into storage tanks',
              icon: Icons.opacity_outlined,
              tint: tokens.coral,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            spec: _KpiSpec(
              label: 'Average Purchase Rate',
              value: formatAverageRateValue(slice.averageRate),
              hint: 'PKR / L',
              icon: Icons.speed_outlined,
              tint: tokens.warn,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            spec: _KpiSpec(
              label: 'Largest Delivery Volume',
              value: formatLiters(slice.largestDeliveryLiters),
              hint: 'Single load',
              icon: Icons.local_shipping_outlined,
              tint: tokens.inkMuted,
            ),
          ),
        ),
      ],
    );
  }
}

class _KpiSpec {
  const _KpiSpec({
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
    required this.tint,
  });

  final String label;
  final String value;
  final String hint;
  final IconData icon;
  final Color tint;
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.spec});

  final _KpiSpec spec;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.radius20),
        border: Border.all(color: tokens.line),
        boxShadow: tokens.cardShadow,
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: spec.tint.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(spec.icon, color: spec.tint, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  spec.label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
                  spec.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: tokens.ink,
                  ),
                ),
                Text(
                  spec.hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w500,
                    fontSize: 11,
                    color: tokens.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SalesToolbar extends ConsumerWidget {
  const _SalesToolbar({
    required this.search,
    required this.searchFocus,
    required this.query,
    required this.slice,
    required this.selectedShift,
  });

  final TextEditingController search;
  final FocusNode searchFocus;
  final LedgerQuery query;
  final SalesLedgerSnapshot slice;
  final ShiftLedgerSummary? selectedShift;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.radius20),
        border: Border.all(color: tokens.line),
        boxShadow: tokens.cardShadow,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              primary: false,
              child: Row(
                children: <Widget>[
                  _UnitChip(
                    label: 'All Units',
                    selected: query.unitId == null,
                    onTap: () {
                      ref.read(ledgerQueryProvider.notifier).setUnit(null);
                    },
                  ),
                  for (final int id in dispenserUnitIds) ...<Widget>[
                    const SizedBox(width: 6),
                    _UnitChip(
                      label: formatUnitLabel(id),
                      selected: query.unitId == id,
                      onTap: () {
                        ref.read(ledgerQueryProvider.notifier).setUnit(id);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _SalesModeToggle(
            mode: query.salesMode,
            onChanged: (SalesLedgerMode mode) {
              ref.read(ledgerQueryProvider.notifier).setSalesMode(mode);
            },
          ),
          const SizedBox(width: 8),
          DateRangeFilterButton(
            range: query.salesRange,
            onChanged: (DateTimeRange? range) {
              ref.read(ledgerQueryProvider.notifier).setSalesRange(range);
            },
          ),
          const SizedBox(width: 8),
          _GeneratePdfButton(
            onPressed: () {
              unawaited(
                _exportLedgerPdf(
                  context,
                  empty: slice.rows.isEmpty,
                  export: () {
                    return LedgerPdfExport.instance.exportSales(
                      slice: slice,
                      unitId: query.unitId,
                      range: query.salesRange,
                      search: query.search,
                      shiftLabel: query.salesMode == SalesLedgerMode.shiftWise
                          ? _shiftPdfLabel(selectedShift)
                          : null,
                    );
                  },
                ),
              );
            },
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 220,
            child: TextField(
              controller: search,
              focusNode: searchFocus,
              onChanged: (String value) {
                ref.read(ledgerQueryProvider.notifier).setSearch(value);
              },
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w500,
                fontSize: 13,
                color: tokens.ink,
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Token, customer, or vehicle',
                prefixIcon: Icon(
                  Icons.search,
                  size: 18,
                  color: tokens.inkMuted,
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String? _shiftPdfLabel(ShiftLedgerSummary? shift) {
  if (shift == null) {
    return null;
  }
  return '${shift.shiftId} · ${shift.managerBadgeLabel}';
}

class _UnitChip extends StatelessWidget {
  const _UnitChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final Color fg = selected ? tokens.coralPressed : tokens.inkMuted;
    final Color bg = selected
        ? tokens.coral.withValues(alpha: 0.14)
        : tokens.canvas;
    final Color border = selected ? tokens.coral : tokens.line;
    return Material(
      color: bg,
      shape: StadiumBorder(side: BorderSide(color: border)),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        hoverColor: tokens.ink.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}

class _GeneratePdfButton extends StatelessWidget {
  const _GeneratePdfButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DsPillButton(
      label: 'Generate PDF',
      icon: Icons.picture_as_pdf_outlined,
      compact: true,
      onPressed: onPressed,
    );
  }
}

Future<void> _exportLedgerPdf(
  BuildContext context, {
  required bool empty,
  required Future<void> Function() export,
}) async {
  if (empty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Nothing to export for this filter.')),
    );
    return;
  }
  try {
    await export();
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Could not generate PDF: $error')));
  }
}

class _TableCard extends StatelessWidget {
  const _TableCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.radius20),
        border: Border.all(color: tokens.line),
        boxShadow: tokens.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Center(
      child: Text(
        message,
        style: TextStyle(fontFamily: 'Roboto', color: tokens.inkMuted),
      ),
    );
  }
}

/// Desktop-safe 2-axis scroller. Scrollbars must share a controller with the
/// matching ScrollView; otherwise they attach to PrimaryScrollController and
/// throw on Windows.
class _TwoAxisScroll extends StatefulWidget {
  const _TwoAxisScroll({required this.minWidth, required this.child});

  final double minWidth;
  final Widget child;

  @override
  State<_TwoAxisScroll> createState() => _TwoAxisScrollState();
}

class _TwoAxisScrollState extends State<_TwoAxisScroll> {
  final ScrollController _vertical = ScrollController();
  final ScrollController _horizontal = ScrollController();

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _vertical,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _vertical,
        primary: false,
        child: Scrollbar(
          controller: _horizontal,
          thumbVisibility: true,
          notificationPredicate: (ScrollNotification notification) {
            return notification.depth == 0;
          },
          child: SingleChildScrollView(
            controller: _horizontal,
            primary: false,
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: widget.minWidth),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class _SalesCol {
  const _SalesCol(this.label, this.width, {this.numeric = false});

  final String label;
  final double width;
  final bool numeric;
}

const List<_SalesCol> _salesCols = <_SalesCol>[
  _SalesCol('TOKEN', 88),
  _SalesCol('DATE & TIME', 140),
  _SalesCol('UNIT NO', 70),
  _SalesCol('AMOUNT', 86, numeric: true),
  _SalesCol('LITERS', 76, numeric: true),
  _SalesCol('RATE', 68, numeric: true),
  _SalesCol('OPENING READING', 110, numeric: true),
  _SalesCol('CLOSING READING', 110, numeric: true),
  _SalesCol('PAYMENT METHOD', 130),
  _SalesCol('CUSTOMER NAME', 130),
  _SalesCol('VEHICLE NO', 96),
  _SalesCol('HELPER', 90),
  _SalesCol('CASHIER', 90),
  _SalesCol('ACTIONS', 86),
];

const double _salesTableMinWidth = 1680;
const double _salesHeaderHeight = 32;
const double _salesRowExtent = 52;

class _SalesDataTable extends StatelessWidget {
  const _SalesDataTable({required this.rows});

  final List<SaleTransaction> rows;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double minWidth = constraints.maxWidth < _salesTableMinWidth
            ? _salesTableMinWidth
            : constraints.maxWidth;
        return _VirtualSalesTable(minWidth: minWidth, rows: rows);
      },
    );
  }
}

class _VirtualSalesTable extends ConsumerStatefulWidget {
  const _VirtualSalesTable({required this.minWidth, required this.rows});

  final double minWidth;
  final List<SaleTransaction> rows;

  @override
  ConsumerState<_VirtualSalesTable> createState() => _VirtualSalesTableState();
}

class _VirtualSalesTableState extends ConsumerState<_VirtualSalesTable> {
  final ScrollController _vertical = ScrollController();
  final ScrollController _horizontal = ScrollController();

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Scrollbar(
          controller: _horizontal,
          thumbVisibility: true,
          notificationPredicate: (ScrollNotification notification) {
            return notification.depth == 0;
          },
          child: SingleChildScrollView(
            controller: _horizontal,
            primary: false,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: widget.minWidth,
              height: constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : _salesHeaderHeight + _salesRowExtent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(
                    height: _salesHeaderHeight,
                    child: _salesHeaderRow(tokens),
                  ),
                  Divider(color: tokens.line, height: 1),
                  Expanded(
                    child: Scrollbar(
                      controller: _vertical,
                      thumbVisibility: true,
                      child: ListView.builder(
                        controller: _vertical,
                        primary: false,
                        itemExtent: _salesRowExtent,
                        itemCount: widget.rows.length,
                        itemBuilder: (BuildContext context, int index) {
                          return _salesDataRow(
                            context,
                            tokens,
                            widget.rows[index],
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _salesHeaderRow(DispensrTokens tokens) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < _salesCols.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 14),
            _salesCell(
              width: _salesCols[i].width,
              numeric: _salesCols[i].numeric,
              child: Text(
                _salesCols[i].label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  letterSpacing: 0.9,
                  color: tokens.inkMuted,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _salesDataRow(
    BuildContext context,
    DispensrTokens tokens,
    SaleTransaction row,
  ) {
    final TextStyle dataStyle = TextStyle(
      fontFamily: 'Roboto',
      fontWeight: FontWeight.w500,
      fontSize: 12,
      color: tokens.ink,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: row.isUnsettledUdhaar
            ? tokens.bad.withValues(alpha: 0.10)
            : Colors.transparent,
        border: Border(bottom: BorderSide(color: tokens.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: <Widget>[
            _salesCell(
              width: _salesCols[0].width,
              child: Row(
                children: <Widget>[
                  if (row.isUnsettledUdhaar) ...<Widget>[
                    Container(
                      width: 4,
                      height: 18,
                      decoration: BoxDecoration(
                        color: tokens.bad,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      formatLedgerToken(row.tokenNo),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: row.isUnsettledUdhaar
                            ? tokens.bad
                            : tokens.coralPressed,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            _salesCell(
              width: _salesCols[1].width,
              child: Text(
                formatDateTime(row.timestamp),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: dataStyle.copyWith(color: tokens.inkMuted),
              ),
            ),
            const SizedBox(width: 14),
            _salesCell(
              width: _salesCols[2].width,
              child: Text(
                formatUnitLabel(row.unitId),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: dataStyle,
              ),
            ),
            const SizedBox(width: 14),
            _salesCell(
              width: _salesCols[3].width,
              numeric: true,
              child: Text(
                formatPkr(row.amountPkr),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: dataStyle.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 14),
            _salesCell(
              width: _salesCols[4].width,
              numeric: true,
              child: Text(
                formatLiters(row.volumeLiters),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: dataStyle,
              ),
            ),
            const SizedBox(width: 14),
            _salesCell(
              width: _salesCols[5].width,
              numeric: true,
              child: Text(
                formatRate(row.rate),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: dataStyle,
              ),
            ),
            const SizedBox(width: 14),
            _salesCell(
              width: _salesCols[6].width,
              numeric: true,
              child: Text(
                formatMeterReading(row.openingMeter),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: dataStyle,
              ),
            ),
            const SizedBox(width: 14),
            _salesCell(
              width: _salesCols[7].width,
              numeric: true,
              child: Text(
                formatMeterReading(row.closingMeter),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: dataStyle,
              ),
            ),
            const SizedBox(width: 14),
            _salesCell(
              width: _salesCols[8].width,
              child: _PaymentPill(
                method: row.payment,
                settled: row.udhaarSettled,
              ),
            ),
            const SizedBox(width: 14),
            _salesCell(
              width: _salesCols[9].width,
              child: _CustomerCell(name: row.customerName, notes: row.notes),
            ),
            const SizedBox(width: 14),
            _salesCell(
              width: _salesCols[10].width,
              child: Text(
                displayVehicleNo(row.vehicleNo),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: dataStyle,
              ),
            ),
            const SizedBox(width: 14),
            _salesCell(
              width: _salesCols[11].width,
              child: Text(
                row.helperName.trim().isEmpty ? '—' : row.helperName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: dataStyle.copyWith(color: tokens.inkMuted),
              ),
            ),
            const SizedBox(width: 14),
            _salesCell(
              width: _salesCols[12].width,
              child: Text(
                row.cashierName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: dataStyle.copyWith(color: tokens.inkMuted),
              ),
            ),
            const SizedBox(width: 14),
            _salesCell(
              width: _salesCols[13].width,
              child: _RowActions(
                onPrint: () {
                  unawaited(_reprint(context, ref, row));
                },
                onEdit: () {
                  unawaited(_editSale(context, ref, row));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _salesCell({
    required double width,
    required Widget child,
    bool numeric = false,
  }) {
    return SizedBox(
      width: width,
      child: numeric
          ? Align(alignment: Alignment.centerRight, child: child)
          : child,
    );
  }
}

class _PurchaseDataTable extends StatelessWidget {
  const _PurchaseDataTable({required this.rows, required this.onEdit});

  final List<PurchaseTransaction> rows;
  final ValueChanged<PurchaseTransaction> onEdit;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return _TwoAxisScroll(
          minWidth: constraints.maxWidth < 1080 ? 1080 : constraints.maxWidth,
          child: DataTable(
            headingRowHeight: 32,
            dataRowMinHeight: 38,
            dataRowMaxHeight: 42,
            horizontalMargin: 14,
            columnSpacing: 20,
            headingTextStyle: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w700,
              fontSize: 10,
              letterSpacing: 0.9,
              color: tokens.inkMuted,
            ),
            dataTextStyle: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w500,
              fontSize: 12,
              color: tokens.ink,
            ),
            columns: const <DataColumn>[
              DataColumn(label: Text('INV-NO')),
              DataColumn(label: Text('DATETIME')),
              DataColumn(label: Text('QUANTITY'), numeric: true),
              DataColumn(label: Text('RATE'), numeric: true),
              DataColumn(label: Text('AMOUNT'), numeric: true),
              DataColumn(label: Text('TAFSEEL')),
              DataColumn(label: Text('USERS')),
              DataColumn(label: Text('ACTIONS')),
            ],
            rows: <DataRow>[
              for (final PurchaseTransaction row in rows)
                DataRow(
                  cells: <DataCell>[
                    DataCell(
                      Text(
                        formatInvoiceNo(row.refNo),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: tokens.coralPressed,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        formatDateTime(row.timestamp),
                        style: TextStyle(color: tokens.inkMuted),
                      ),
                    ),
                    DataCell(Text(formatLiters(row.netLiters))),
                    DataCell(Text(formatTruncatedDecimal(row.ratePerLiter))),
                    DataCell(
                      Text(
                        formatPkr(row.totalAmount),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    DataCell(
                      SizedBox(
                        width: 200,
                        child: Text(
                          row.tafseelDisplay,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(row.user, style: TextStyle(color: tokens.inkMuted)),
                    ),
                    DataCell(
                      _ActionIcon(
                        tooltip: 'Edit',
                        icon: Icons.edit_outlined,
                        color: tokens.inkMuted,
                        onPressed: () => onEdit(row),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CustomerCell extends StatelessWidget {
  const _CustomerCell({required this.name, required this.notes});

  final String name;
  final String notes;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final String display = displayCustomerName(name);
    final String trimmedNotes = notes.trim();
    if (trimmedNotes.isEmpty) {
      return Text(display);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(display),
        Text(
          trimmedNotes,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w500,
            fontSize: 10,
            color: tokens.inkMuted,
          ),
        ),
      ],
    );
  }
}

class _RowActions extends StatelessWidget {
  const _RowActions({required this.onPrint, required this.onEdit});

  final VoidCallback onPrint;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _ActionIcon(
          tooltip: 'Print',
          icon: Icons.print_outlined,
          color: tokens.coralPressed,
          onPressed: onPrint,
        ),
        _ActionIcon(
          tooltip: 'Edit',
          icon: Icons.edit_outlined,
          color: tokens.inkMuted,
          onPressed: onEdit,
        ),
      ],
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      hoverColor: tokens.ink.withValues(alpha: 0.06),
      icon: Icon(icon, size: 18, color: color),
    );
  }
}

class _PaymentPill extends StatelessWidget {
  const _PaymentPill({required this.method, this.settled = false});

  final PaymentMethod method;
  final bool settled;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    late final Color fg;
    late final Color bg;
    switch (method) {
      case PaymentMethod.cash:
        fg = tokens.good;
        bg = tokens.good.withValues(alpha: 0.12);
      case PaymentMethod.udhaar:
        fg = settled ? tokens.good : tokens.bad;
        bg = (settled ? tokens.good : tokens.bad).withValues(alpha: 0.12);
      case PaymentMethod.bankAccount:
      case PaymentMethod.easyPaisa:
        fg = tokens.coralPressed;
        bg = tokens.coral.withValues(alpha: 0.14);
    }
    return DsStatusPill(
      label: method == PaymentMethod.udhaar && settled
          ? 'UDHAAR · SETTLED'
          : method.ledgerPill,
      foreground: fg,
      background: bg,
      border: fg.withValues(alpha: 0.35),
      dot: false,
    );
  }
}

Future<void> _reprint(
  BuildContext context,
  WidgetRef ref,
  SaleTransaction row,
) async {
  ref.read(stationControllerProvider.notifier).reprintReceipt(row);
  if (!context.mounted) {
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return _ReprintReceiptDialog(txn: row);
    },
  );
}

Future<void> _editPurchase(
  BuildContext context,
  PurchaseTransaction row,
) async {
  final bool saved = await showEditPurchaseDialogFromLedger(context, row);
  if (!context.mounted || !saved) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('${formatInvoiceNo(row.refNo)} updated')),
  );
}

Future<void> _editSale(
  BuildContext context,
  WidgetRef ref,
  SaleTransaction row,
) async {
  final bool? saved = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return _EditSaleDialog(txn: row);
    },
  );
  if (!context.mounted || saved != true) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('${formatLedgerToken(row.tokenNo)} updated')),
  );
}

class _ReprintReceiptDialog extends StatefulWidget {
  const _ReprintReceiptDialog({required this.txn, this.title});

  final SaleTransaction txn;
  final String? title;

  @override
  State<_ReprintReceiptDialog> createState() => _ReprintReceiptDialogState();
}

class _ReprintReceiptDialogState extends State<_ReprintReceiptDialog> {
  final GlobalKey _previewKey = GlobalKey();
  bool _busy = false;
  bool _stationCapture = false;
  bool _forPrint = false;

  ReceiptTicket get _ticket => ReceiptTicket.fromTransaction(widget.txn);

  bool get _twoCopies => widget.txn.payment.printsTwoCopies;

  Future<void> _print() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _forPrint = true;
    });
    try {
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
      final Uint8List customerPng = await ReceiptGenerator.instance
          .capturePreview(_previewKey);
      if (_twoCopies) {
        setState(() {
          _stationCapture = true;
        });
        await WidgetsBinding.instance.endOfFrame;
        await WidgetsBinding.instance.endOfFrame;
        final Uint8List stationPng = await ReceiptGenerator.instance
            .capturePreview(_previewKey);
        await ReceiptGenerator.instance.printDualCopies(
          customerPng: customerPng,
          stationPng: stationPng,
          ticket: _ticket,
        );
      } else {
        await ReceiptGenerator.instance.printCapturedPng(customerPng, _ticket);
      }
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _twoCopies
                ? 'Receipt ${formatLedgerToken(widget.txn.tokenNo)} — 2 copies sent to printer'
                : 'Receipt ${formatLedgerToken(widget.txn.tokenNo)} sent to printer',
          ),
        ),
      );
    } catch (error, stack) {
      debugPrint('Reprint failed: $error\n$stack');
      if (!mounted) {
        return;
      }
      setState(() {
        _forPrint = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not print receipt. $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Dialog(
      backgroundColor: tokens.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius20),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    widget.title ??
                        'Reprint ${formatLedgerToken(widget.txn.tokenNo)}',
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: tokens.ink,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Center(
                    child: ThermalReceiptCapture(
                      captureKey: _previewKey,
                      child: ThermalReceiptView(
                        ticket: _ticket,
                        forPrint: _forPrint,
                        copyBanner: ReceiptCopy.bannerFor(
                          payment: widget.txn.payment,
                          stationCopy: _stationCapture,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: DsPillButton(
                      label: 'Cancel',
                      variant: DsPillVariant.outline,
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DsPillButton(
                      label: _busy ? 'Printing…' : 'Print',
                      icon: Icons.print_outlined,
                      onPressed: _busy ? null : _print,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditSaleDialog extends ConsumerStatefulWidget {
  const _EditSaleDialog({required this.txn});

  final SaleTransaction txn;

  @override
  ConsumerState<_EditSaleDialog> createState() => _EditSaleDialogState();
}

enum _EditPill { cash, udhaar, account }

enum _EditRail { bank, easyPaisa }

class _EditSaleDialogState extends ConsumerState<_EditSaleDialog> {
  late final TextEditingController _customer;
  late final TextEditingController _vehicle;
  late _EditPill _pill;
  late _EditRail _rail;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final String customer = widget.txn.customerName.trim();
    _customer = TextEditingController(
      text: customer.toLowerCase() == 'walk-in' ? '' : customer,
    );
    _vehicle = TextEditingController(text: widget.txn.vehicleNo);
    switch (widget.txn.payment) {
      case PaymentMethod.cash:
        _pill = _EditPill.cash;
        _rail = _EditRail.bank;
      case PaymentMethod.udhaar:
        _pill = _EditPill.udhaar;
        _rail = _EditRail.bank;
      case PaymentMethod.bankAccount:
        _pill = _EditPill.account;
        _rail = _EditRail.bank;
      case PaymentMethod.easyPaisa:
        _pill = _EditPill.account;
        _rail = _EditRail.easyPaisa;
    }
  }

  @override
  void dispose() {
    _customer.dispose();
    _vehicle.dispose();
    super.dispose();
  }

  PaymentMethod get _payment {
    switch (_pill) {
      case _EditPill.cash:
        return PaymentMethod.cash;
      case _EditPill.udhaar:
        return PaymentMethod.udhaar;
      case _EditPill.account:
        return _rail == _EditRail.easyPaisa
            ? PaymentMethod.easyPaisa
            : PaymentMethod.bankAccount;
    }
  }

  bool get _udhaarRequiresName => _pill == _EditPill.udhaar;

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    if (_udhaarRequiresName && _customer.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Customer name is required for Udhaar')),
      );
      return;
    }
    setState(() {
      _saving = true;
    });
    try {
      final SaleTransaction? updated = await ref
          .read(stationControllerProvider.notifier)
          .updateSaleMetadata(
            tokenNo: widget.txn.tokenNo,
            customerName: _customer.text,
            vehicleNo: _vehicle.text,
            payment: _payment,
          );
      if (!mounted) {
        return;
      }
      if (updated == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update this sale')),
        );
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error, stack) {
      debugPrint('Sale edit failed: $error\n$stack');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save changes. $error')));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Dialog(
      backgroundColor: tokens.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius20),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Edit ${formatLedgerToken(widget.txn.tokenNo)}',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: tokens.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${formatUnitLabel(widget.txn.unitId)} · ${formatDateTime(widget.txn.timestamp)}',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 12,
                  color: tokens.inkMuted,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'PAYMENT METHOD',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w700,
                  fontSize: 8,
                  letterSpacing: 0.8,
                  color: tokens.inkMuted,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _EditMethodPill(
                      label: 'Cash',
                      selected: _pill == _EditPill.cash,
                      onTap: () {
                        setState(() {
                          _pill = _EditPill.cash;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _EditMethodPill(
                      label: 'Udhaar',
                      selected: _pill == _EditPill.udhaar,
                      onTap: () {
                        setState(() {
                          _pill = _EditPill.udhaar;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _EditMethodPill(
                      label: 'Bank / Digital',
                      selected: _pill == _EditPill.account,
                      onTap: () {
                        setState(() {
                          _pill = _EditPill.account;
                        });
                      },
                    ),
                  ),
                ],
              ),
              if (_pill == _EditPill.account) ...<Widget>[
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _EditMethodPill(
                        label: 'Bank',
                        selected: _rail == _EditRail.bank,
                        compact: true,
                        onTap: () {
                          setState(() {
                            _rail = _EditRail.bank;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _EditMethodPill(
                        label: 'EasyPaisa',
                        selected: _rail == _EditRail.easyPaisa,
                        compact: true,
                        onTap: () {
                          setState(() {
                            _rail = _EditRail.easyPaisa;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _customer,
                textInputAction: TextInputAction.next,
                style: const TextStyle(fontFamily: 'Roboto', fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Customer Name',
                  hintText: 'Walk-in if empty',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _vehicle,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => unawaited(_save()),
                style: const TextStyle(fontFamily: 'Roboto', fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Vehicle No',
                  hintText: 'Optional',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: DsPillButton(
                      label: 'Cancel',
                      variant: DsPillVariant.outline,
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DsPillButton(
                      label: _saving ? 'Saving…' : 'Save',
                      onPressed: _saving ? null : () => unawaited(_save()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditMethodPill extends StatelessWidget {
  const _EditMethodPill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final Color fg = selected ? tokens.coralPressed : tokens.inkMuted;
    final Color bg = selected
        ? tokens.coral.withValues(alpha: 0.14)
        : tokens.card;
    final Color border = selected ? tokens.coral : tokens.line;
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 4 : 8),
        side: BorderSide(color: border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(compact ? 4 : 8),
        hoverColor: tokens.ink.withValues(alpha: 0.05),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 8,
            vertical: compact ? 6 : 8,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w600,
              fontSize: compact ? 11 : 12,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}
