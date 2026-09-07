import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/dispensr_theme.dart';
import '../../core/widgets/app_screen_header.dart';
import '../../core/widgets/fuel_point_stat_card.dart';
import '../../features/customer/data/customer_directory_pdf.dart';
import '../../features/customer/domain/customer_models.dart';
import '../../features/customer/presentation/customer_providers.dart';
import '../../features/station/domain/money_format.dart';
import '../../features/station/presentation/workspace_refresh.dart';
import 'Widgets/add_customer_dialog.dart';
import 'Widgets/settle_bill_dialog.dart';
import 'Widgets/settlement_receipt_dialog.dart';

class CustomerScreen extends ConsumerStatefulWidget {
  const CustomerScreen({super.key});

  @override
  ConsumerState<CustomerScreen> createState() => _CustomerScreenState();
}

class _CustomerScreenState extends ConsumerState<CustomerScreen> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(refreshCustomersFromDatabase(ref));
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  String _nextCustomerId() {
    int max = 0;
    for (final CustomerAccount account in ref.read(customerAccountsProvider)) {
      final int? parsed = int.tryParse(account.profile.id);
      if (parsed != null && parsed > max) {
        max = parsed;
      }
    }
    return formatCustomerId(max + 1);
  }

  Future<void> _addCustomer() async {
    final AddCustomerResult? draft = await showAddCustomerDialog(
      context,
      nextId: _nextCustomerId(),
    );
    if (draft == null || !mounted) {
      return;
    }
    try {
      await ref
          .read(customerWorkspaceProvider.notifier)
          .addCustomer(name: draft.name, phone: draft.phone);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not add customer. $error')));
    }
  }

  Future<void> _exportPdf() async {
    try {
      final List<CustomerProfile> rows = ref
          .read(customerAccountsProvider)
          .map((CustomerAccount account) => account.profile)
          .toList();
      await CustomerDirectoryPdf.instance.export(rows);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not export directory. $error')),
      );
    }
  }

  Future<void> _settle(CustomerAccount account) async {
    if (account.outstanding <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This account has no outstanding balance'),
        ),
      );
      return;
    }
    final SettleBillDraft? draft = await showSettleBillDialog(
      context,
      account: account,
    );
    if (draft == null || !mounted) {
      return;
    }
    try {
      final CustomerSettlement settlement = await ref
          .read(customerWorkspaceProvider.notifier)
          .settleBill(
            customer: account.profile,
            amountPkr: draft.amountPkr,
            paymentMode: draft.paymentMode,
            notes: draft.notes,
          );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Settlement ${settlement.receiptNo} recorded. Opening receipt…',
          ),
        ),
      );
      await showSettlementReceiptDialog(context, settlement: settlement);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not settle bill. $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final CustomerKpis kpis = ref.watch(customerKpisProvider);
    final List<CustomerAccount> filtered = ref.watch(
      filteredCustomerAccountsProvider,
    );
    final CustomerAccount? selected = ref.watch(
      selectedCustomerAccountProvider,
    );

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          _searchFocus.requestFocus();
        },
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            _addCustomer,
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
                  title: 'Customers & Udhaar',
                  icon: Icons.handshake_outlined,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _KpiBar(kpis: kpis),
                      const SizedBox(height: 10),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            SizedBox(
                              width: 350,
                              child: _DirectoryPanel(
                                search: _search,
                                searchFocus: _searchFocus,
                                accounts: filtered,
                                selectedId: selected?.profile.id,
                                onSearch: (String value) {
                                  ref
                                      .read(customerWorkspaceProvider.notifier)
                                      .setSearch(value);
                                },
                                onSelect: (String id) {
                                  ref
                                      .read(customerWorkspaceProvider.notifier)
                                      .select(id);
                                },
                                onAdd: () {
                                  unawaited(_addCustomer());
                                },
                                onExport: () {
                                  unawaited(_exportPdf());
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: selected == null
                                  ? _EmptyWorkspace(onAdd: _addCustomer)
                                  : _CustomerWorkspace(
                                      account: selected,
                                      onSettle: () {
                                        unawaited(_settle(selected));
                                      },
                                    ),
                            ),
                          ],
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
  const _KpiBar({required this.kpis});

  final CustomerKpis kpis;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final CustomerAccount? highest = kpis.highestDebt;
    return Row(
      children: <Widget>[
        Expanded(
          child: FuelPointStatCard(
            title: 'Total Udhaar Outstanding',
            value: formatPkrStatement(kpis.totalOutstanding),
            subtitle: 'Unpaid across all accounts',
            icon: Icons.account_balance_wallet_outlined,
            badgeBackgroundColor: tokens.bad.withValues(alpha: 0.12),
            badgeIconColor: tokens.bad,
            borderColor: tokens.bad.withValues(alpha: 0.35),
            valueColor: tokens.bad,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FuelPointStatCard(
            title: 'Active Credit Accounts',
            value: '${kpis.activeCreditAccounts}',
            subtitle: 'Balance greater than zero',
            icon: Icons.groups_outlined,
            badgeBackgroundColor: tokens.warn.withValues(alpha: 0.12),
            badgeIconColor: tokens.warn,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FuelPointStatCard(
            title: 'Settled This Month',
            value: formatPkrStatement(kpis.settledThisMonth),
            subtitle: 'Cash recoveries this calendar month',
            icon: Icons.payments_outlined,
            badgeBackgroundColor: tokens.good.withValues(alpha: 0.12),
            badgeIconColor: tokens.good,
            valueColor: tokens.good,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FuelPointStatCard(
            title: 'Highest Debt Account',
            value: highest == null
                ? '—'
                : formatPkrStatement(highest.outstanding),
            subtitle: highest == null
                ? 'No outstanding debt'
                : highest.profile.name,
            icon: Icons.trending_up,
            badgeBackgroundColor: tokens.coral.withValues(alpha: 0.12),
            badgeIconColor: tokens.coral,
            borderColor: tokens.warn.withValues(alpha: 0.45),
            valueColor: tokens.warn,
          ),
        ),
      ],
    );
  }
}

class _DirectoryPanel extends StatelessWidget {
  const _DirectoryPanel({
    required this.search,
    required this.searchFocus,
    required this.accounts,
    required this.selectedId,
    required this.onSearch,
    required this.onSelect,
    required this.onAdd,
    required this.onExport,
  });

  final TextEditingController search;
  final FocusNode searchFocus;
  final List<CustomerAccount> accounts;
  final String? selectedId;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.radius20),
        border: Border.all(color: tokens.line),
        boxShadow: tokens.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'CUSTOMER DIRECTORY',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    letterSpacing: 1.0,
                    color: tokens.inkMuted,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: DsPillButton(
                        label: '+ Add Customer',
                        compact: true,
                        onPressed: onAdd,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: DsPillButton(
                        label: 'Export PDF',
                        icon: Icons.picture_as_pdf_outlined,
                        variant: DsPillVariant.outline,
                        compact: true,
                        onPressed: onExport,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: search,
                  focusNode: searchFocus,
                  onChanged: onSearch,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 13,
                    color: tokens.ink,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search ID (01) or name',
                    prefixIcon: Icon(
                      Icons.search,
                      size: 18,
                      color: tokens.inkMuted,
                    ),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: tokens.line),
          Expanded(
            child: accounts.isEmpty
                ? Center(
                    child: Text(
                      'No matching accounts',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        color: tokens.inkMuted,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                    itemCount: accounts.length,
                    separatorBuilder: (BuildContext context, int index) {
                      return const SizedBox(height: 6);
                    },
                    itemBuilder: (BuildContext context, int index) {
                      final CustomerAccount account = accounts[index];
                      final bool selected = account.profile.id == selectedId;
                      return _DirectoryTile(
                        account: account,
                        selected: selected,
                        onTap: () => onSelect(account.profile.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _DirectoryTile extends StatelessWidget {
  const _DirectoryTile({
    required this.account,
    required this.selected,
    required this.onTap,
  });

  final CustomerAccount account;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final bool owed = account.hasDebt;
    final Color pillFg = owed ? tokens.bad : tokens.good;
    final Color pillBg = owed
        ? tokens.bad.withValues(alpha: 0.12)
        : tokens.good.withValues(alpha: 0.12);
    return Material(
      color: selected
          ? tokens.coral.withValues(alpha: 0.10)
          : tokens.canvas.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(tokens.radius12),
      child: InkWell(
        onTap: onTap,
        hoverColor: tokens.ink.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(tokens.radius12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(tokens.radius12),
            border: Border.all(color: selected ? tokens.coral : tokens.line),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tokens.ink,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  account.profile.id,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: tokens.card,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  account.profile.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: tokens.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: pillBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: pillFg.withValues(alpha: 0.28)),
                ),
                child: Text(
                  owed ? formatPkr(account.outstanding) : formatPkr(0),
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    color: pillFg,
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

class _EmptyWorkspace extends StatelessWidget {
  const _EmptyWorkspace({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.radius20),
        border: Border.all(color: tokens.line),
        boxShadow: tokens.cardShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.handshake_outlined, size: 36, color: tokens.inkMuted),
          const SizedBox(height: 8),
          Text(
            'Select or add a customer',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: tokens.ink,
            ),
          ),
          const SizedBox(height: 12),
          DsPillButton(label: '+ Add Customer', onPressed: onAdd),
        ],
      ),
    );
  }
}

class _CustomerWorkspace extends StatelessWidget {
  const _CustomerWorkspace({required this.account, required this.onSettle});

  final CustomerAccount account;
  final VoidCallback onSettle;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final CustomerProfile profile = account.profile;
    return Container(
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.radius20),
        border: Border.all(color: tokens.line),
        boxShadow: tokens.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: <Widget>[
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tokens.ink,
                    borderRadius: BorderRadius.circular(tokens.radius12),
                  ),
                  child: Text(
                    profile.id,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: tokens.card,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        profile.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          color: tokens.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Phone  ${profile.phoneDisplay}',
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 12,
                          color: tokens.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      'OUTSTANDING',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.w700,
                        fontSize: 9,
                        letterSpacing: 0.8,
                        color: tokens.inkMuted,
                      ),
                    ),
                    Text(
                      formatPkrStatement(account.outstanding),
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.w700,
                        fontSize: 22,
                        color: account.hasDebt ? tokens.bad : tokens.good,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                DsPillButton(
                  label: 'Settle Bill',
                  icon: Icons.payments_outlined,
                  onPressed: account.hasDebt ? onSettle : null,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: tokens.line),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Text(
              'UNIFIED LEDGER',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w700,
                fontSize: 10,
                letterSpacing: 1.0,
                color: tokens.inkMuted,
              ),
            ),
          ),
          Expanded(child: _LedgerTable(lines: account.ledger)),
        ],
      ),
    );
  }
}

class _LedgerTable extends StatelessWidget {
  const _LedgerTable({required this.lines});

  final List<CustomerLedgerLine> lines;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    if (lines.isEmpty) {
      return Center(
        child: Text(
          'No udhaar purchases or recoveries yet',
          style: TextStyle(fontFamily: 'Roboto', color: tokens.inkMuted),
        ),
      );
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double minWidth = constraints.maxWidth < 1680
            ? 1680
            : constraints.maxWidth;
        return _TwoAxisScroll(
          minWidth: minWidth,
          child: DataTable(
            headingRowHeight: 32,
            dataRowMinHeight: 40,
            dataRowMaxHeight: 48,
            headingRowColor: WidgetStatePropertyAll<Color>(tokens.canvas),
            headingTextStyle: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w700,
              fontSize: 10,
              letterSpacing: 0.9,
              color: tokens.inkMuted,
            ),
            dataTextStyle: const TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w500,
              fontSize: 12,
            ),
            columns: const <DataColumn>[
              DataColumn(label: Text('PRIMARY KEY')),
              DataColumn(label: Text('TYPE')),
              DataColumn(label: Text('TKN')),
              DataColumn(label: Text('DATE & TIME')),
              DataColumn(label: Text('LITERS'), numeric: true),
              DataColumn(label: Text('RATE'), numeric: true),
              DataColumn(label: Text('AMOUNT'), numeric: true),
              DataColumn(label: Text('DESCRIPTION')),
              DataColumn(label: Text('VEHICLE')),
              DataColumn(label: Text('UDHAAR'), numeric: true),
              DataColumn(label: Text('PAID'), numeric: true),
              DataColumn(label: Text('REMAINING'), numeric: true),
            ],
            rows: <DataRow>[
              for (final CustomerLedgerLine line in lines)
                DataRow(
                  color: WidgetStatePropertyAll<Color>(
                    line.isSale
                        ? tokens.bad.withValues(alpha: 0.04)
                        : tokens.good.withValues(alpha: 0.06),
                  ),
                  cells: <DataCell>[
                    DataCell(
                      Text(
                        line.ledgerId,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: line.isSale
                              ? tokens.coralPressed
                              : tokens.good,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        line.isSale ? 'SALE' : 'SETTLEMENT',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: line.isSale ? tokens.bad : tokens.good,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        line.tokenLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: line.tokenNo == null
                              ? tokens.inkMuted
                              : tokens.ink,
                        ),
                      ),
                    ),
                    DataCell(Text(formatDateTime(line.at))),
                    DataCell(
                      Text(
                        line.volumeLiters == null
                            ? '—'
                            : line.volumeLiters!.toStringAsFixed(2),
                      ),
                    ),
                    DataCell(
                      Text(line.rate == null ? '—' : formatRate(line.rate!)),
                    ),
                    DataCell(
                      Text(
                        formatPkr(line.amountPkr),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    DataCell(
                      Text(
                        line.description,
                        style: TextStyle(
                          color: line.isSale ? tokens.bad : tokens.good,
                        ),
                      ),
                    ),
                    DataCell(Text(line.vehicleLabel)),
                    DataCell(
                      Text(
                        line.debitPkr > 0 ? formatPkr(line.debitPkr) : '—',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: line.isSale ? tokens.bad : tokens.inkMuted,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        line.creditPkr > 0 ? formatPkr(line.creditPkr) : '—',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: line.isSale ? tokens.inkMuted : tokens.good,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        formatPkr(line.runningBalance),
                        style: const TextStyle(fontWeight: FontWeight.w700),
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

/// Desktop-safe 2-axis scroller. Scrollbars share a controller with the
/// matching ScrollView so they do not attach to PrimaryScrollController.
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
