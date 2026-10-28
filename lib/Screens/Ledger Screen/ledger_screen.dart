import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/pdf_file_export.dart';
import '../../core/theme/dispensr_theme.dart';
import '../../core/widgets/app_screen_header.dart';
import '../../core/widgets/proof_story_popup.dart';
import '../../core/widgets/date_range_selector.dart';
import '../../features/customer/domain/customer_models.dart';
import '../../features/customer/presentation/customer_providers.dart';
import '../../features/station/domain/fuel_precision.dart';
import '../../features/station/domain/sale_fulfillment.dart';
import '../Sale Screen/Widgets/Services/sale_tender_panel.dart';
import '../../features/shift/data/shift_summary_export.dart';
import '../../features/shift/presentation/shift_providers.dart';
import '../../features/station/data/ledger_pdf_export.dart';
import '../../features/station/data/transaction_store.dart';
import '../../features/station/domain/dispenser_models.dart';
import '../../providers/settings_provider.dart';
import '../../features/station/domain/ledger_rate_bands.dart';
import '../../features/station/domain/money_format.dart';
import '../../features/station/domain/shift_ledger_models.dart';
import '../../features/station/data/sales_ledger_repository.dart';
import '../../features/station/domain/rate_change_summary.dart';
import '../../features/station/domain/sales_ledger_window.dart';
import '../../features/station/presentation/ledger_providers.dart';
import '../../features/station/presentation/station_providers.dart';
import '../Sale Screen/Widgets/Services/generate_receipt.dart';
import '../Sale Screen/Widgets/Services/receipt_preview_widget.dart';
import 'Widgets/edit_purchase_dialog.dart';
import 'Widgets/shift_transaction_audit_dialog.dart';
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
    final bool windowedSales =
        query.tab == LedgerTab.sales &&
        query.salesMode != SalesLedgerMode.shiftWise;
    final List<ShiftLedgerSummary> shifts = shiftWiseSales
        ? (ref.watch(shiftWisePagerProvider).valueOrNull ??
              const <ShiftLedgerSummary>[])
        : const <ShiftLedgerSummary>[];
    final AllTransactionsPage? txnPage = windowedSales
        ? ref.watch(allTransactionsLedgerProvider).valueOrNull
        : null;
    final bool shiftPagerActive = shiftWiseSales && !_searchFocus.hasFocus;
    final bool txnPagerActive =
        windowedSales &&
        !_searchFocus.hasFocus &&
        txnPage != null &&
        txnPage.window.isDefault;

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
        if (txnPage != null &&
            txnPagerActive) ...<ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
            if (txnPage.pageIndex <= 0) {
              return;
            }
            ref
                .read(ledgerQueryProvider.notifier)
                .setSalesPage(txnPage.pageIndex - 1);
          },
          const SingleActivator(LogicalKeyboardKey.arrowRight): () {
            if (txnPage.pageIndex >= txnPage.pageCount - 1) {
              return;
            }
            ref
                .read(ledgerQueryProvider.notifier)
                .setSalesPage(txnPage.pageIndex + 1);
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
    final bool shiftWise = query.salesMode == SalesLedgerMode.shiftWise;
    final bool rateWise = query.salesMode == SalesLedgerMode.rateWise;
    final AsyncValue<AllTransactionsPage>? txnAsync = shiftWise
        ? null
        : ref.watch(allTransactionsLedgerProvider);
    final AllTransactionsPage? txnPage = txnAsync?.valueOrNull;
    final SalesLedgerSnapshot slice = shiftWise
        ? ref.watch(salesLedgerSliceProvider)
        : (txnPage?.snapshot ?? SalesLedgerSnapshot.empty);
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
          transactionsPage: txnPage,
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
                            ? ShiftLedgerTableHeader(
                                summary: selectedShift,
                                unitId: query.unitId,
                                saleLiters: slice.totalVolumeLiters,
                                sales: slice.meterRows,
                              )
                            : Text(
                                rateWise ? 'Rate-Wise' : 'Sales History',
                                style: TextStyle(
                                  fontFamily: 'Roboto',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: tokens.ink,
                                ),
                              ),
                      ),
                      if (shiftWise) ...<Widget>[
                        DsPillButton(
                          label: 'Audit',
                          icon: Icons.fact_check_outlined,
                          compact: true,
                          variant: DsPillVariant.outline,
                          onPressed: selectedShift == null
                              ? null
                              : () {
                                  unawaited(
                                    showShiftTransactionAuditDialog(
                                      context,
                                      summary: selectedShift,
                                      rows: slice.meterRows,
                                      unitId: query.unitId,
                                    ),
                                  );
                                },
                        ),
                        const SizedBox(width: 8),
                        ShiftLedgerPager(shifts: shifts),
                      ] else if (txnPage != null && txnPage.window.isDefault)
                        LedgerPagerControls(
                          page: txnPage.pageIndex + 1,
                          pageCount: txnPage.pageCount,
                          previousTooltip: 'Previous page',
                          nextTooltip: 'Next page',
                          onPrevious: () {
                            ref
                                .read(ledgerQueryProvider.notifier)
                                .setSalesPage(txnPage.pageIndex - 1);
                          },
                          onNext: () {
                            ref
                                .read(ledgerQueryProvider.notifier)
                                .setSalesPage(txnPage.pageIndex + 1);
                          },
                        ),
                    ],
                  ),
                ),
                Divider(color: tokens.line, height: 1),
                Expanded(
                  child: rateWise
                      ? _rateTableBody(ref, txnAsync)
                      : _salesTableBody(ref, shiftsAsync, txnAsync: txnAsync),
                ),
                Divider(color: tokens.line, height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _salesFooterLabel(
                        shiftWise: shiftWise,
                        rateWise: rateWise,
                        slice: slice,
                        page: txnPage,
                        countLabel: countLabel,
                      ),
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
    AsyncValue<List<ShiftLedgerSummary>> shiftsAsync, {
    AsyncValue<AllTransactionsPage>? txnAsync,
  }) {
    final LedgerQuery query = ref.watch(ledgerQueryProvider);
    final bool shiftWise = query.salesMode == SalesLedgerMode.shiftWise;
    final bool filtered =
        query.salesRange != null ||
        query.unitId != null ||
        query.search.trim().isNotEmpty;

    if (shiftWise) {
      final SalesLedgerSnapshot slice = ref.watch(salesLedgerSliceProvider);
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

    final AsyncValue<AllTransactionsPage>? pageAsync = txnAsync;
    if (pageAsync == null) {
      return const _EmptyHint(message: 'No sales yet.');
    }
    return pageAsync.when(
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace stack) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _EmptyHint(message: 'Could not load sales. $error'),
              const SizedBox(height: 12),
              DsPillButton(
                label: 'Retry',
                compact: true,
                onPressed: () {
                  ref.invalidate(allTransactionsLedgerProvider);
                },
              ),
            ],
          ),
        );
      },
      data: (AllTransactionsPage page) {
        if (page.snapshot.rows.isEmpty) {
          return _EmptyHint(
            message: filtered
                ? 'No sales match this filter.'
                : page.pageIndex == 0 && page.window.isDefault
                ? 'No sales in the last 30 days.'
                : 'No sales in this 30-day period.',
          );
        }
        return _SalesDataTable(rows: page.snapshot.rows);
      },
    );
  }

  Widget _rateTableBody(
    WidgetRef ref,
    AsyncValue<AllTransactionsPage>? txnAsync,
  ) {
    final LedgerQuery query = ref.watch(ledgerQueryProvider);
    final bool filtered = query.salesRange != null || query.unitId != null;
    if (txnAsync == null) {
      return const _EmptyHint(message: 'No sales yet.');
    }
    return txnAsync.when(
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace stack) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _EmptyHint(message: 'Could not load sales. $error'),
              const SizedBox(height: 12),
              DsPillButton(
                label: 'Retry',
                compact: true,
                onPressed: () {
                  ref.invalidate(allTransactionsLedgerProvider);
                },
              ),
            ],
          ),
        );
      },
      data: (AllTransactionsPage page) {
        if (page.rateChanges.stretches.isEmpty) {
          return _EmptyHint(
            message: filtered
                ? 'No sales match this filter.'
                : page.pageIndex == 0 && page.window.isDefault
                ? 'No sales in the last 30 days.'
                : 'No sales in this 30-day period.',
          );
        }
        return _RateChangeTable(summary: page.rateChanges);
      },
    );
  }
}

String _salesFooterLabel({
  required bool shiftWise,
  required bool rateWise,
  required SalesLedgerSnapshot slice,
  required AllTransactionsPage? page,
  required String countLabel,
}) {
  if (shiftWise || page == null) {
    return '${slice.totalCount} $countLabel';
  }
  final String dates = _windowDates(page.window);
  if (rateWise) {
    final int total = page.rateChanges.stretches.length;
    final String rows = total == 1 ? 'rate row' : 'rate rows';
    return '$total $rows · $dates';
  }
  final int total = page.windowRowCount;
  if (total <= 0) {
    return '0 $countLabel · $dates';
  }
  return '$total $countLabel · $dates';
}

String _windowDates(SalesLedgerWindow window) {
  String day(DateTime time) {
    final String d = time.day.toString().padLeft(2, '0');
    final String month = time.month.toString().padLeft(2, '0');
    return '$d-$month-${time.year}';
  }

  return '${day(window.from)} → ${day(window.to)}';
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
          const SizedBox(width: 4),
          _SalesModeChip(
            label: 'Rate-Wise',
            selected: mode == SalesLedgerMode.rateWise,
            onTap: () => onChanged(SalesLedgerMode.rateWise),
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
                              transactionCount: slice.rows.length,
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

const List<int> _rateColFlex = <int>[3, 2, 4, 4, 3, 2, 3, 3];
const double _rateTableMinWidth = 980;

class _RateChangeTable extends StatefulWidget {
  const _RateChangeTable({required this.summary});

  final RateChangeSummary summary;

  @override
  State<_RateChangeTable> createState() => _RateChangeTableState();
}

class _RateChangeTableState extends State<_RateChangeTable> {
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
    final List<RateChangeStretch> stretches = widget.summary.stretches;
    final Map<String, int> bands = _ratePeriodBands(stretches);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 240;
        final double width = constraints.maxWidth < _rateTableMinWidth
            ? _rateTableMinWidth
            : constraints.maxWidth;
        return Scrollbar(
          controller: _horizontal,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _horizontal,
            primary: false,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              height: height,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _rateHeader(tokens),
                  Divider(color: tokens.line, height: 1),
                  Expanded(
                    child: Scrollbar(
                      controller: _vertical,
                      thumbVisibility: true,
                      child: ListView.builder(
                        controller: _vertical,
                        primary: false,
                        itemCount: stretches.length,
                        itemBuilder: (BuildContext context, int index) {
                          final RateChangeStretch row = stretches[index];
                          final String key = displayedRateKey(row.rate);
                          final bool newGroup =
                              index > 0 &&
                              displayedRateKey(stretches[index - 1].rate) !=
                                  key;
                          return _rateDataRow(
                            tokens,
                            row,
                            fill: _rateBandFill(tokens, bands[key]),
                            gapBefore: newGroup,
                          );
                        },
                      ),
                    ),
                  ),
                  Divider(color: tokens.line, height: 1),
                  _rateTotalRow(tokens, widget.summary),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

Map<String, int> _ratePeriodBands(List<RateChangeStretch> stretches) {
  final Map<String, int> indexes = <String, int>{};
  int next = 0;
  for (final RateChangeStretch row in stretches) {
    indexes.putIfAbsent(displayedRateKey(row.rate), () => next++);
  }
  if (indexes.length < 2) {
    return const <String, int>{};
  }
  return indexes;
}

Widget _rateHeader(DispensrTokens tokens) {
  const List<String> labels = <String>[
    'UNIT',
    'RATE',
    'CLOSING',
    'OPENING',
    'DISPENSED',
    'TEST',
    'NET',
    'AMOUNT',
  ];
  const List<bool> numeric = <bool>[
    false,
    true,
    true,
    true,
    true,
    true,
    true,
    true,
  ];
  final TextStyle style = TextStyle(
    fontFamily: 'Roboto',
    fontWeight: FontWeight.w700,
    fontSize: 10,
    letterSpacing: 0.9,
    color: tokens.inkMuted,
  );
  return SizedBox(
    height: 32,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < labels.length; i++)
            Expanded(
              flex: _rateColFlex[i],
              child: Align(
                alignment: numeric[i]
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Text(
                  labels[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

Widget _rateDataRow(
  DispensrTokens tokens,
  RateChangeStretch row, {
  required Color? fill,
  required bool gapBefore,
}) {
  final TextStyle data = TextStyle(
    fontFamily: 'Roboto',
    fontWeight: FontWeight.w500,
    fontSize: 12,
    color: tokens.ink,
  );
  final List<String> values = <String>[
    formatUnitLabel(row.unitId),
    formatTableRate(row.rate),
    formatMeterReading(row.closingMeter),
    formatMeterReading(row.openingMeter),
    formatTableLiters(row.dispensedLiters),
    formatTableLiters(row.testLiters),
    formatTableLiters(row.netLiters),
    formatTablePkr(row.amountPkr.toDouble()),
  ];
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      if (gapBefore) const SizedBox(height: 14),
      DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          border: Border(bottom: BorderSide(color: tokens.line)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: <Widget>[
              for (int i = 0; i < values.length; i++)
                Expanded(
                  flex: _rateColFlex[i],
                  child: Align(
                    alignment: i == 0
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    child: Text(
                      values[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: i == values.length - 1
                          ? data.copyWith(fontWeight: FontWeight.w700)
                          : data,
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

Widget _rateTotalRow(DispensrTokens tokens, RateChangeSummary summary) {
  final TextStyle total = TextStyle(
    fontFamily: 'Roboto',
    fontWeight: FontWeight.w700,
    fontSize: 12,
    color: tokens.ink,
  );
  final List<String> values = <String>[
    'Total',
    '',
    '',
    '',
    formatTableLiters(summary.dispensedLiters),
    formatTableLiters(summary.testLiters),
    formatTableLiters(summary.netLiters),
    formatTablePkr(summary.amountPkr.toDouble()),
  ];
  return ColoredBox(
    color: tokens.canvas,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < values.length; i++)
            Expanded(
              flex: _rateColFlex[i],
              child: Align(
                alignment: i == 0
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: Text(
                  values[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: total,
                ),
              ),
            ),
        ],
      ),
    ),
  );
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
              value: formatTablePkr(slice.totalAmountPkr),
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
              value: formatTableLiters(slice.physicalVolumeLiters),
              hint:
                  'Real volume: ${formatTableLiters(slice.totalVolumeLiters)} | Test volume: ${formatTableLiters(slice.testVolumeLiters)}',
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
              value: formatTablePkr(slice.udhaarAmountPkr),
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
              label: 'Total Account Amount',
              value: formatTablePkr(slice.totalAccountAmountPkr),
              hint: 'Bank / account',
              icon: Icons.account_balance_outlined,
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
              value: formatTablePkr(slice.totalAmountPkr),
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
              value: formatTableLiters(slice.totalVolumeLiters),
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
              value: formatTableRate(slice.averageRate),
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
              value: formatTableLiters(slice.largestDeliveryLiters),
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
                SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      spec.hint,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.w500,
                        fontSize: 11,
                        color: tokens.inkMuted,
                      ),
                    ),
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
    required this.transactionsPage,
  });

  final TextEditingController search;
  final FocusNode searchFocus;
  final LedgerQuery query;
  final SalesLedgerSnapshot slice;
  final ShiftLedgerSummary? selectedShift;
  final AllTransactionsPage? transactionsPage;

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
                  const SizedBox(width: 6),
                  _UnitChip(
                    label: formatUnitLabel(kDirectSaleUnitId),
                    selected: query.unitId == kDirectSaleUnitId,
                    onTap: () {
                      ref
                          .read(ledgerQueryProvider.notifier)
                          .setUnit(kDirectSaleUnitId);
                    },
                  ),
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
            emptyLabel: query.salesMode == SalesLedgerMode.shiftWise
                ? 'All dates'
                : 'Last 30 days',
            onChanged: (DateTimeRange? range) {
              ref.read(ledgerQueryProvider.notifier).setSalesRange(range);
            },
          ),
          const SizedBox(width: 8),
          _GeneratePdfButton(
            onPressed: () {
              final bool windowedSales =
                  query.salesMode != SalesLedgerMode.shiftWise;
              final AllTransactionsPage? page = transactionsPage;
              unawaited(
                _exportLedgerPdf(
                  context,
                  empty: query.salesMode == SalesLedgerMode.shiftWise
                      ? selectedShift == null
                      : (page?.windowRowCount ?? 0) == 0,
                  transactionCount: query.salesMode == SalesLedgerMode.shiftWise
                      ? selectedShift?.totalTransactions ?? 0
                      : windowedSales
                      ? (page?.windowRowCount ?? 0)
                      : slice.rows.length,
                  export: () async {
                    if (query.salesMode == SalesLedgerMode.shiftWise) {
                      final ShiftLedgerSummary shift = selectedShift!;
                      return ShiftSummaryExport.instance.savePdf(
                        shiftSummaryForLedger(
                          workspace: ref.read(shiftWorkspaceProvider),
                          selected: shift,
                        ),
                        open: true,
                        showUnit5: ref.read(settingsProvider).showUnit5,
                        unitId: query.unitId,
                      );
                    }
                    final AllTransactionsPage loaded =
                        page ??
                        await ref
                            .read(salesLedgerRepositoryProvider)
                            .loadAllTransactionsPage(
                              unitId: query.unitId,
                              search: query.search,
                              salesFrom: query.salesFrom,
                              salesTo: query.salesTo,
                              pageIndex: query.salesPage,
                            );
                    return LedgerPdfExport.instance.exportSales(
                      slice: loaded.snapshot,
                      unitId: query.unitId,
                      range: DateTimeRange(
                        start: loaded.window.from,
                        end: loaded.window.to,
                      ),
                      search: query.search,
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
  required Future<File> Function() export,
  int transactionCount = 0,
}) async {
  if (empty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Nothing to export for this filter.')),
    );
    return;
  }
  await runPdfExport(
    context,
    export: export,
    transactionCount: transactionCount,
  );
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
  _SalesCol('CASH', 80, numeric: true),
  _SalesCol('ACCOUNT', 80, numeric: true),
  _SalesCol('CUSTOMER NAME', 130),
  _SalesCol('VEHICLE NO', 96),
  _SalesCol('HELPER', 90),
  _SalesCol('OPERATOR', 90),
  _SalesCol('SCREENSHOT', 56),
  _SalesCol('ACTIONS', 86),
];

const double _salesTableMinWidth = 1940;
const double _salesHeaderHeight = 32;
const double _salesRowExtent = 52;

Color? _rateBandFill(DispensrTokens tokens, int? index) {
  if (index == null) {
    return null;
  }
  const double alpha = 0.10;
  final List<Color> palette = <Color>[
    tokens.blush,
    tokens.coral,
    tokens.good,
    tokens.warn,
    tokens.inkMuted,
  ];
  return palette[index % palette.length].withValues(alpha: alpha);
}

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
    final Map<String, int> bands = rateBandIndexes(widget.rows);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : _salesHeaderHeight + _salesRowExtent;
        return Scrollbar(
          controller: _horizontal,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _horizontal,
            primary: false,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: widget.minWidth,
              height: height,
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
                          final SaleTransaction row = widget.rows[index];
                          return _salesDataRow(
                            context,
                            tokens,
                            row,
                            rateTint: _rateBandFill(
                              tokens,
                              bands[displayedRateKey(row.rate)],
                            ),
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
    SaleTransaction row, {
    Color? rateTint,
  }) {
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
            : (rateTint ?? Colors.transparent),
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
                  if (row.isTest) ...<Widget>[
                    const SizedBox(width: 6),
                    Text(
                      'Test',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                        color: tokens.warn,
                      ),
                    ),
                  ],
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
                formatTablePkr(row.amountPkr),
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
                formatTableLiters(row.volumeLiters),
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
                formatTableRate(row.rate),
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
              child: row.isTest
                  ? _PaymentPill(method: row.payment, isTest: true)
                  : _PaymentPill(
                      method: row.payment,
                      settled: row.udhaarSettled,
                      pending: row.isAccountPending,
                    ),
            ),
            const SizedBox(width: 14),
            _salesCell(
              width: _salesCols[9].width,
              numeric: true,
              child: Text(
                formatTableTenderPkr(row.cashAmount),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: dataStyle,
              ),
            ),
            const SizedBox(width: 14),
            _salesCell(
              width: _salesCols[10].width,
              numeric: true,
              child: Text(
                formatTableTenderPkr(row.receiptAccountAmount),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: dataStyle,
              ),
            ),
            const SizedBox(width: 14),
            _salesCell(
              width: _salesCols[11].width,
              child: _CustomerCell(name: row.customerName, notes: row.notes),
            ),
            const SizedBox(width: 14),
            _salesCell(
              width: _salesCols[12].width,
              child: Text(
                displayVehicleNo(row.vehicleNo),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: dataStyle,
              ),
            ),
            const SizedBox(width: 14),
            _salesCell(
              width: _salesCols[13].width,
              child: Text(
                row.helperName.trim().isEmpty ? '—' : row.helperName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: dataStyle.copyWith(color: tokens.inkMuted),
              ),
            ),
            const SizedBox(width: 14),
            _salesCell(
              width: _salesCols[14].width,
              child: Text(
                row.cashierName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: dataStyle.copyWith(color: tokens.inkMuted),
              ),
            ),
            const SizedBox(width: 14),
            _salesCell(
              width: _salesCols[15].width,
              child: LedgerProofThumb(imagePath: row.proofImagePath),
            ),
            const SizedBox(width: 14),
            _salesCell(
              width: _salesCols[16].width,
              child: row.isTest
                  ? Text('—', style: dataStyle.copyWith(color: tokens.inkMuted))
                  : _RowActions(
                      onPrint: () {
                        unawaited(_reprint(context, ref, row));
                      },
                      onEdit: row.isAccountPending
                          ? null
                          : () {
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
                    DataCell(Text(formatTableLiters(row.netLiters))),
                    DataCell(Text(formatTruncatedDecimal(row.ratePerLiter))),
                    DataCell(
                      Text(
                        formatTablePkr(row.totalAmount),
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
  final VoidCallback? onEdit;

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
        if (onEdit != null)
          _ActionIcon(
            tooltip: 'Edit',
            icon: Icons.edit_outlined,
            color: tokens.inkMuted,
            onPressed: onEdit ?? () {},
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
  const _PaymentPill({
    required this.method,
    this.settled = false,
    this.isTest = false,
    this.pending = false,
  });

  final PaymentMethod method;
  final bool settled;
  final bool isTest;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    if (isTest) {
      return DsStatusPill(
        label: 'TEST',
        foreground: tokens.warn,
        background: tokens.warn.withValues(alpha: 0.12),
        border: tokens.warn.withValues(alpha: 0.35),
        dot: false,
      );
    }
    late final Color fg;
    late final Color bg;
    if (pending) {
      fg = tokens.warn;
      bg = tokens.warn.withValues(alpha: 0.12);
    } else {
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
    }
    return DsStatusPill(
      label: pending
          ? '${method.ledgerPill} · PENDING'
          : method == PaymentMethod.udhaar && settled
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
  try {
    await presentSaleReceipt(
      context: context,
      txn: row,
      kind: ReceiptPrintKind.secondCopy,
    );
  } catch (error, stack) {
    debugPrint('Reprint failed: $error\n$stack');
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Could not print receipt. $error')));
  }
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
  if (row.isAccountPending) {
    return;
  }
  final bool? saved = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return EditSaleDialog(txn: row);
    },
  );
  if (!context.mounted || saved != true) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('${formatLedgerToken(row.tokenNo)} updated')),
  );
}

class EditSaleDialog extends ConsumerStatefulWidget {
  const EditSaleDialog({super.key, required this.txn});

  final SaleTransaction txn;

  @override
  ConsumerState<EditSaleDialog> createState() => _EditSaleDialogState();
}

class _EditSaleDialogState extends ConsumerState<EditSaleDialog> {
  late final TextEditingController _customerId;
  late final TextEditingController _customer;
  late final TextEditingController _cashNow;
  late final TextEditingController _accountNow;
  late final TextEditingController _vehicle;
  late SaleTenderPill _pill;
  late SaleAccountRail _rail;
  bool _saving = false;
  bool _syncingSplit = false;

  @override
  void initState() {
    super.initState();
    _customerId = TextEditingController();
    _customer = TextEditingController();
    _seedCustomerFromTxn();
    _customerId.addListener(_onCustomerIdChanged);
    _cashNow = TextEditingController();
    _accountNow = TextEditingController();
    _vehicle = TextEditingController(text: widget.txn.vehicleNo);
    _vehicle.addListener(_onVehicleChanged);
    switch (widget.txn.payment) {
      case PaymentMethod.cash:
        _pill = SaleTenderPill.cash;
        _rail = SaleAccountRail.bank;
      case PaymentMethod.udhaar:
        _pill = SaleTenderPill.udhaar;
        _rail = SaleAccountRail.bank;
      case PaymentMethod.bankAccount:
        _pill = SaleTenderPill.account;
        _rail = SaleAccountRail.bank;
      case PaymentMethod.easyPaisa:
        _pill = SaleTenderPill.account;
        _rail = SaleAccountRail.easyPaisa;
    }
    if (_pill != SaleTenderPill.cash) {
      final int cash = roundRupees(widget.txn.cashAmount);
      final int account = roundRupees(widget.txn.receiptAccountAmount);
      if (cash > 0) {
        _cashNow.text = '$cash';
      }
      if (account > 0) {
        _accountNow.text = '$account';
      }
    }
  }

  void _seedCustomerFromTxn() {
    final String name = widget.txn.customerName.trim();
    if (name.isEmpty || name.toLowerCase() == 'walk-in') {
      return;
    }
    final Map<String, CustomerProfile> cache = ref.read(
      customerIdCacheProvider,
    );
    for (final CustomerProfile profile in cache.values) {
      if (profile.name.trim().toLowerCase() == name.toLowerCase()) {
        _customerId.text = profile.id;
        _customer.text = profile.name;
        return;
      }
    }
    _customer.text = name;
  }

  CustomerProfile? _matchedCustomer() {
    final String key = normalizeCustomerIdQuery(_customerId.text);
    if (key.isEmpty) {
      return null;
    }
    return ref.read(customerIdCacheProvider)[key];
  }

  void _onCustomerIdChanged() {
    final CustomerProfile? match = _matchedCustomer();
    if (match != null) {
      if (_customer.text != match.name) {
        _customer.value = TextEditingValue(
          text: match.name,
          selection: TextSelection.collapsed(offset: match.name.length),
        );
      }
    } else if (_customer.text.isNotEmpty) {
      _customer.clear();
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _onVehicleChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  String get _resolvedCustomerName {
    if (_pill != SaleTenderPill.udhaar) {
      return 'Walk-in';
    }
    return _matchedCustomer()?.name ?? 'Walk-in';
  }

  @override
  void dispose() {
    _customerId
      ..removeListener(_onCustomerIdChanged)
      ..dispose();
    _customer.dispose();
    _cashNow.dispose();
    _accountNow.dispose();
    _vehicle
      ..removeListener(_onVehicleChanged)
      ..dispose();
    super.dispose();
  }

  PaymentMethod get _payment {
    switch (_pill) {
      case SaleTenderPill.cash:
        return PaymentMethod.cash;
      case SaleTenderPill.udhaar:
        return PaymentMethod.udhaar;
      case SaleTenderPill.account:
        return _rail == SaleAccountRail.easyPaisa
            ? PaymentMethod.easyPaisa
            : PaymentMethod.bankAccount;
    }
  }

  int get _saleRupees => roundRupees(widget.txn.amountPkr);

  int get _cashRupees => readTenderRupees(_cashNow.text);

  int get _accountRupees => readTenderRupees(_accountNow.text);

  bool get _vehicleValid => isVehicleRegistrationValid(_vehicle.text);

  bool get _canCommit {
    return !_saving &&
        _vehicleValid &&
        saleTenderReady(
          pill: _pill,
          saleRupees: _saleRupees,
          cash: _cashRupees,
          account: _accountRupees,
          customerMatched: _matchedCustomer() != null,
        );
  }

  void _applyPill(SaleTenderPill next) {
    seedSaleTenderPill(
      next: next,
      saleRupees: _saleRupees,
      cash: _cashNow,
      account: _accountNow,
      setSyncing: (bool value) {
        _syncingSplit = value;
      },
    );
    _pill = next;
  }

  void _onSplitChanged(String _) {
    if (_syncingSplit) {
      setState(() {});
      return;
    }
    if (saleTenderUdhaarOverflow(
      pill: _pill,
      saleRupees: _saleRupees,
      cash: _cashRupees,
      account: _accountRupees,
    )) {
      setState(() {
        _pill = SaleTenderPill.account;
      });
      return;
    }
    setState(() {});
  }

  Future<void> _save() async {
    if (_saving || !_canCommit) {
      if (_pill == SaleTenderPill.udhaar && _matchedCustomer() == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid customer ID for Udhaar')),
        );
      }
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
            customerName: _resolvedCustomerName,
            vehicleNo: persistVehicleNo(_vehicle.text),
            payment: _payment,
            cashNow: _cashRupees.toDouble(),
            accountNow: _accountRupees.toDouble(),
            saleAmount: widget.txn.amountPkr,
            creditCustomerId: _pill == SaleTenderPill.udhaar
                ? (_matchedCustomer()?.id ?? '')
                : '',
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

  Future<void> _printEdited() async {
    if (!_canCommit) {
      return;
    }
    final ({PaymentMethod payment, double cashAmount, double accountAmount})
    split = resolveAccountSplit(
      payment: _payment,
      saleAmount: widget.txn.amountPkr,
      cashNow: _cashRupees.toDouble(),
      accountNow: _accountRupees.toDouble(),
    );
    final SaleTransaction preview = widget.txn.copyWith(
      customerName: _resolvedCustomerName,
      vehicleNo: persistVehicleNo(_vehicle.text),
      payment: split.payment,
      cashAmount: split.cashAmount,
      accountAmount: split.accountAmount,
    );
    try {
      await presentSaleReceipt(
        context: context,
        txn: preview,
        kind: ReceiptPrintKind.editedCopy,
      );
    } catch (error, stack) {
      debugPrint('Edited copy print failed: $error\n$stack');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not print. $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    ref.watch(customerIdCacheProvider);
    return Dialog(
      backgroundColor: tokens.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius20),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 440,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: SingleChildScrollView(
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
                SaleTenderPanel(
                  pill: _pill,
                  rail: _rail,
                  saleRupees: _saleRupees,
                  customerId: _customerId,
                  customerName: _customer,
                  cash: _cashNow,
                  account: _accountNow,
                  vehicle: _vehicle,
                  showVehicleHint: !_vehicleValid,
                  onSplitChanged: _onSplitChanged,
                  onSubmitted: (_) => unawaited(_save()),
                  onPill: (SaleTenderPill next) {
                    setState(() {
                      _applyPill(next);
                    });
                  },
                  onRail: (SaleAccountRail next) {
                    setState(() {
                      _rail = next;
                    });
                  },
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
                        label: 'Print',
                        variant: DsPillVariant.ink,
                        onPressed: _saving
                            ? null
                            : () => unawaited(_printEdited()),
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
      ),
    );
  }
}
