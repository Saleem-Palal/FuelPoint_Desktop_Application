import '../../station/domain/dispenser_models.dart';

enum SettlementPaymentMode { cash, bankTransfer, easyPaisa }

extension SettlementPaymentModeX on SettlementPaymentMode {
  String get label {
    switch (this) {
      case SettlementPaymentMode.cash:
        return 'Cash';
      case SettlementPaymentMode.bankTransfer:
        return 'Bank';
      case SettlementPaymentMode.easyPaisa:
        return 'EasyPaisa';
    }
  }

  String get ledgerPill {
    switch (this) {
      case SettlementPaymentMode.cash:
        return 'CASH';
      case SettlementPaymentMode.bankTransfer:
        return 'BANK';
      case SettlementPaymentMode.easyPaisa:
        return 'EASYPAISA';
    }
  }

  bool get isAccount {
    return this == SettlementPaymentMode.bankTransfer ||
        this == SettlementPaymentMode.easyPaisa;
  }

  static SettlementPaymentMode parse(String? raw) {
    switch ((raw ?? '').trim().toUpperCase()) {
      case 'BANK':
      case 'BANK TRANSFER':
        return SettlementPaymentMode.bankTransfer;
      case 'EASYPAISA':
      case 'EASY PAISA':
        return SettlementPaymentMode.easyPaisa;
      default:
        return SettlementPaymentMode.cash;
    }
  }
}

class CustomerProfile {
  const CustomerProfile({
    required this.id,
    required this.name,
    this.phone = '',
    this.createdAt,
  });

  /// Zero-padded sequence (`01`, `02`, …).
  final String id;
  final String name;
  final String phone;
  final DateTime? createdAt;

  String get phoneDisplay {
    final String trimmed = phone.trim();
    return trimmed.isEmpty ? '—' : trimmed;
  }

  CustomerProfile copyWith({String? name, String? phone}) {
    return CustomerProfile(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      createdAt: createdAt,
    );
  }
}

class CustomerSettlement {
  const CustomerSettlement({
    required this.id,
    required this.receiptNo,
    required this.customerId,
    required this.customerName,
    required this.amountPkr,
    required this.paymentMode,
    required this.timestamp,
    required this.previousBalance,
    required this.remainingBalance,
    this.cashAmountPkr = 0,
    this.accountAmountPkr = 0,
    this.notes = '',
    this.cashierName = 'Amir R.',
    this.cashierId = 'AR',
    this.shiftId = '',
  });

  final int id;
  final String receiptNo;
  final String customerId;
  final String customerName;
  final double amountPkr;
  final SettlementPaymentMode paymentMode;
  final DateTime timestamp;
  final double previousBalance;
  final double remainingBalance;
  final double cashAmountPkr;
  final double accountAmountPkr;
  final String notes;
  final String cashierName;
  final String cashierId;
  final String shiftId;

  bool get isPartial => remainingBalance > 0.004;

  bool get hasAccountTender => accountAmountPkr > 0.004;

  String get tenderLabel {
    final bool cash = cashAmountPkr > 0.004;
    final bool account = accountAmountPkr > 0.004;
    if (cash && account) {
      return 'Cash + ${paymentMode.label}';
    }
    if (account) {
      return paymentMode.label;
    }
    return 'Cash';
  }

  String get receiptPaymentLabel {
    final String base = tenderLabel;
    return isPartial ? 'Partial · $base' : base;
  }
}

enum CustomerLedgerKind { sale, settlement }

class CustomerLedgerLine {
  const CustomerLedgerLine({
    required this.ledgerId,
    required this.at,
    required this.kind,
    required this.description,
    required this.amountPkr,
    required this.debitPkr,
    required this.creditPkr,
    required this.runningBalance,
    this.tokenNo,
    this.vehicleNo = '',
    this.volumeLiters,
    this.rate,
    this.sale,
    this.settlement,
  });

  /// Unified ledger primary key (`1026/01-03`).
  final String ledgerId;
  final DateTime at;
  final CustomerLedgerKind kind;
  final String description;
  final double amountPkr;
  final double debitPkr;
  final double creditPkr;
  final double runningBalance;
  final int? tokenNo;
  final String vehicleNo;
  final double? volumeLiters;
  final double? rate;
  final SaleTransaction? sale;
  final CustomerSettlement? settlement;

  bool get isSale => kind == CustomerLedgerKind.sale;

  String get tokenLabel {
    final int? token = tokenNo;
    if (token == null) {
      return '—';
    }
    return formatLedgerToken(token);
  }

  String get vehicleLabel => displayVehicleNo(vehicleNo);
}

class CustomerAccount {
  const CustomerAccount({
    required this.profile,
    required this.udhaarSalesTotal,
    required this.settlementsTotal,
    required this.outstanding,
    required this.ledger,
  });

  final CustomerProfile profile;
  final double udhaarSalesTotal;
  final double settlementsTotal;
  final double outstanding;
  final List<CustomerLedgerLine> ledger;

  bool get hasDebt => outstanding > 0;
}

class CustomerKpis {
  const CustomerKpis({
    required this.totalOutstanding,
    required this.activeCreditAccounts,
    required this.settledThisMonth,
    this.highestDebt,
  });

  final double totalOutstanding;
  final int activeCreditAccounts;
  final double settledThisMonth;
  final CustomerAccount? highestDebt;
}

bool customerNamesMatch(String left, String right) {
  return left.trim().toUpperCase() == right.trim().toUpperCase();
}

bool isWalkInCustomer(String name) {
  final String trimmed = name.trim();
  return trimmed.isEmpty || trimmed.toLowerCase() == 'walk-in';
}

String formatCustomerId(int sequence) {
  final int safe = sequence < 1 ? 1 : sequence;
  return safe.toString().padLeft(2, '0');
}

String normalizeCustomerIdQuery(String raw) {
  final String trimmed = raw.trim();
  if (trimmed.isEmpty || !RegExp(r'^\d+$').hasMatch(trimmed)) {
    return '';
  }
  final int? parsed = int.tryParse(trimmed);
  if (parsed == null || parsed < 1) {
    return '';
  }
  return formatCustomerId(parsed);
}

const String kUnknownShiftId = 'SHF-0000';

String udhaarShiftToken(String shiftId) {
  final String trimmed = shiftId.trim();
  if (trimmed.isEmpty) {
    return '0000';
  }
  return trimmed.replaceFirst(RegExp(r'^SHF-', caseSensitive: false), '');
}

String formatUdhaarLedgerId({
  required String shiftId,
  required Object customerId,
  required int recordSerial,
}) {
  final String shift = udhaarShiftToken(shiftId);
  final String customer = customerId.toString().padLeft(2, '0');
  final String serial = recordSerial.toString().padLeft(2, '0');
  return '$shift/$customer-$serial';
}

String shiftIdFromUdhaarPrimaryKey(String primaryKey) {
  final int slash = primaryKey.indexOf('/');
  if (slash <= 0) {
    return '';
  }
  return 'SHF-${primaryKey.substring(0, slash)}';
}

enum UnifiedUdhaarType { sale, settlement }

extension UnifiedUdhaarTypeX on UnifiedUdhaarType {
  String get storage {
    switch (this) {
      case UnifiedUdhaarType.sale:
        return 'SALE';
      case UnifiedUdhaarType.settlement:
        return 'SETTLEMENT';
    }
  }

  static UnifiedUdhaarType parse(String? raw) {
    if ((raw ?? '').trim().toUpperCase() == 'SETTLEMENT') {
      return UnifiedUdhaarType.settlement;
    }
    return UnifiedUdhaarType.sale;
  }
}

class UnifiedUdhaarRow {
  const UnifiedUdhaarRow({
    required this.primaryKey,
    required this.type,
    required this.at,
    required this.customerName,
    required this.customerId,
    required this.amountPkr,
    required this.remainingPkr,
    this.tokenLabel,
    this.liters = 0,
    this.rate = 0,
    this.description = '',
    this.vehicle = '',
    this.udhaarPkr = 0,
    this.paidPkr = 0,
    this.status = 'Unpaid',
  });

  final String primaryKey;
  final UnifiedUdhaarType type;
  final DateTime at;
  final String customerName;
  final String customerId;
  final double amountPkr;
  final double remainingPkr;
  final String? tokenLabel;
  final double liters;
  final double rate;
  final String description;
  final String vehicle;
  final double udhaarPkr;
  final double paidPkr;
  final String status;

  bool get isSale => type == UnifiedUdhaarType.sale;
}

String encodeSettlementDescription({
  required String receiptNo,
  required SettlementPaymentMode paymentMode,
  required double cashAmountPkr,
  required double accountAmountPkr,
  String notes = '',
}) {
  return <String>[
    receiptNo,
    paymentMode.ledgerPill,
    cashAmountPkr.toStringAsFixed(2),
    accountAmountPkr.toStringAsFixed(2),
    notes.trim(),
  ].join('|');
}

class SettlementTender {
  const SettlementTender({
    required this.receiptNo,
    required this.paymentMode,
    required this.cashAmountPkr,
    required this.accountAmountPkr,
    required this.notes,
  });

  final String receiptNo;
  final SettlementPaymentMode paymentMode;
  final double cashAmountPkr;
  final double accountAmountPkr;
  final String notes;
}

SettlementTender parseSettlementDescription(
  String raw, {
  required double paidPkr,
}) {
  final List<String> parts = raw.split('|');
  if (parts.length < 2) {
    return SettlementTender(
      receiptNo: '',
      paymentMode: SettlementPaymentMode.cash,
      cashAmountPkr: paidPkr,
      accountAmountPkr: 0,
      notes: raw.trim(),
    );
  }
  final SettlementPaymentMode mode = SettlementPaymentModeX.parse(parts[1]);
  final double? encodedCash = parts.length > 2
      ? double.tryParse(parts[2].trim())
      : null;
  final double? encodedAccount = parts.length > 3
      ? double.tryParse(parts[3].trim())
      : null;
  if (encodedCash != null && encodedAccount != null) {
    return SettlementTender(
      receiptNo: parts[0].trim(),
      paymentMode: mode,
      cashAmountPkr: encodedCash,
      accountAmountPkr: encodedAccount,
      notes: parts.length > 4 ? parts.sublist(4).join('|').trim() : '',
    );
  }
  final bool account = mode.isAccount;
  return SettlementTender(
    receiptNo: parts[0].trim(),
    paymentMode: mode,
    cashAmountPkr: account ? 0 : paidPkr,
    accountAmountPkr: account ? paidPkr : 0,
    notes: parts.length > 2 ? parts.sublist(2).join('|').trim() : '',
  );
}

class UdhaarRecoveryShiftTotals {
  const UdhaarRecoveryShiftTotals({
    this.cash = 0,
    this.account = 0,
    this.partialPaid = 0,
  });

  final double cash;
  final double account;
  final double partialPaid;
}

UdhaarRecoveryShiftTotals udhaarRecoveryTotalsFromRows(
  Iterable<UnifiedUdhaarRow> rows,
) {
  double cash = 0;
  double account = 0;
  double partial = 0;
  for (final UnifiedUdhaarRow row in rows) {
    if (row.type != UnifiedUdhaarType.settlement) {
      continue;
    }
    final SettlementTender tender = parseSettlementDescription(
      row.description,
      paidPkr: row.amountPkr,
    );
    cash += tender.cashAmountPkr;
    account += tender.accountAmountPkr;
    if (row.remainingPkr > 0.004) {
      partial += row.amountPkr;
    }
  }
  return UdhaarRecoveryShiftTotals(
    cash: cash,
    account: account,
    partialPaid: partial,
  );
}

String ledgerStatusFor({
  required double remainingPkr,
  required double paidToDatePkr,
}) {
  if (remainingPkr <= 0.004) {
    return 'Paid';
  }
  if (paidToDatePkr > 0.004) {
    return 'Partially Paid';
  }
  return 'Unpaid';
}

CustomerSettlement settlementFromLedgerRow(
  UnifiedUdhaarRow row, {
  int id = 0,
  String cashierName = 'Operator',
  String cashierId = '',
}) {
  final SettlementTender parsed = parseSettlementDescription(
    row.description,
    paidPkr: row.amountPkr,
  );
  return CustomerSettlement(
    id: id,
    receiptNo: parsed.receiptNo.isEmpty ? row.primaryKey : parsed.receiptNo,
    customerId: row.customerId,
    customerName: row.customerName,
    amountPkr: row.amountPkr,
    paymentMode: parsed.paymentMode,
    timestamp: row.at,
    previousBalance: row.remainingPkr + row.amountPkr,
    remainingBalance: row.remainingPkr,
    cashAmountPkr: parsed.cashAmountPkr,
    accountAmountPkr: parsed.accountAmountPkr,
    notes: parsed.notes,
    cashierName: cashierName,
    cashierId: cashierId,
    shiftId: shiftIdFromUdhaarPrimaryKey(row.primaryKey),
  );
}

String formatSettlementReceiptNo(int sequence) {
  return 'REC-${sequence.toString().padLeft(4, '0')}';
}

String settlementReceiptDisplay(String receiptNo) {
  final String digits = receiptNo.trim().replaceFirst(
    RegExp(r'^(RCP|REC)-', caseSensitive: false),
    '',
  );
  if (digits.isEmpty) {
    return 'Receipt';
  }
  return 'Receipt #$digits';
}

double cashInHandFromLedgers({
  required Iterable<SaleTransaction> sales,
  required Iterable<CustomerSettlement> settlements,
}) {
  double total = 0;
  for (final SaleTransaction sale in sales) {
    if (!sale.isTest && sale.payment == PaymentMethod.cash) {
      total += sale.amountPkr;
    }
  }
  for (final CustomerSettlement settlement in settlements) {
    if (settlement.cashAmountPkr > 0) {
      total += settlement.cashAmountPkr;
    }
  }
  return total;
}
