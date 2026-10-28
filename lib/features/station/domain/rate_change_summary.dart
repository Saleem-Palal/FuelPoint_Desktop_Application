import 'package:decimal/decimal.dart';

import 'dispenser_models.dart';
import 'fuel_precision.dart';
import 'ledger_rate_bands.dart';

/// One unit at one constant displayed rate inside a ledger block.
class RateChangeStretch {
  const RateChangeStretch({
    required this.unitId,
    required this.rate,
    required this.openingMeter,
    required this.closingMeter,
    required this.dispensedLiters,
    required this.testLiters,
    required this.netLiters,
    required this.amountPkr,
  });

  final int unitId;
  final double rate;
  final double openingMeter;
  final double closingMeter;
  final double dispensedLiters;
  final double testLiters;
  final double netLiters;
  final int amountPkr;
}

/// Meter spans for the pumps in one 30-day block.
class RateChangeSummary {
  const RateChangeSummary({
    required this.stretches,
    required this.dispensedLiters,
    required this.testLiters,
    required this.netLiters,
    required this.amountPkr,
  });

  static const RateChangeSummary empty = RateChangeSummary(
    stretches: <RateChangeStretch>[],
    dispensedLiters: 0,
    testLiters: 0,
    netLiters: 0,
    amountPkr: 0,
  );

  final List<RateChangeStretch> stretches;
  final double dispensedLiters;
  final double testLiters;
  final double netLiters;
  final int amountPkr;
}

/// Per pump, closing of the newest row minus opening of the oldest row in
/// each constant-rate stretch. Lost tickets inside a stretch still count
/// because the meter moved. Direct sales are left out.
RateChangeSummary rateChangeSummary(List<SaleTransaction> rows) {
  final Map<int, List<SaleTransaction>> byUnit = <int, List<SaleTransaction>>{};
  for (final SaleTransaction row in rows) {
    if (isDirectSaleUnit(row.unitId)) {
      continue;
    }
    (byUnit[row.unitId] ??= <SaleTransaction>[]).add(row);
  }
  final List<int> unitIds = byUnit.keys.toList()..sort();
  final List<_DatedStretch> dated = <_DatedStretch>[];
  for (final int unitId in unitIds) {
    final List<SaleTransaction> chronological = List<SaleTransaction>.of(
      byUnit[unitId]!,
    );
    chronological.sort((SaleTransaction a, SaleTransaction b) {
      final int time = a.timestamp.compareTo(b.timestamp);
      if (time != 0) {
        return time;
      }
      return a.tokenNo.compareTo(b.tokenNo);
    });
    dated.addAll(_stretchesForUnit(unitId, chronological));
  }
  final List<RateChangeStretch> stretches = _groupByRatePeriod(dated);
  Decimal dispensed = Decimal.zero;
  Decimal test = Decimal.zero;
  Decimal net = Decimal.zero;
  int amount = 0;
  for (final RateChangeStretch stretch in stretches) {
    dispensed += parseDecimal(stretch.dispensedLiters);
    test += parseDecimal(stretch.testLiters);
    net += parseDecimal(stretch.netLiters);
    amount += stretch.amountPkr;
  }
  return RateChangeSummary(
    stretches: stretches,
    dispensedLiters: dispensed.toDouble(),
    testLiters: test.toDouble(),
    netLiters: net.toDouble(),
    amountPkr: amount,
  );
}

/// Rates change on every pump together, so rows are grouped by that shared
/// rate (oldest period first) and then by unit. A later return to an earlier
/// rate is its own group.
List<RateChangeStretch> _groupByRatePeriod(List<_DatedStretch> dated) {
  dated.sort((_DatedStretch a, _DatedStretch b) {
    final int time = a.startedAt.compareTo(b.startedAt);
    if (time != 0) {
      return time;
    }
    return a.stretch.unitId.compareTo(b.stretch.unitId);
  });
  final List<List<RateChangeStretch>> groups = <List<RateChangeStretch>>[];
  String? rateKey;
  for (final _DatedStretch item in dated) {
    final String key = displayedRateKey(item.stretch.rate);
    if (groups.isEmpty || key != rateKey) {
      groups.add(<RateChangeStretch>[]);
      rateKey = key;
    }
    groups.last.add(item.stretch);
  }
  final List<RateChangeStretch> ordered = <RateChangeStretch>[];
  for (final List<RateChangeStretch> group in groups) {
    group.sort(
      (RateChangeStretch a, RateChangeStretch b) =>
          a.unitId.compareTo(b.unitId),
    );
    ordered.addAll(group);
  }
  return ordered;
}

class _DatedStretch {
  const _DatedStretch({required this.startedAt, required this.stretch});

  final DateTime startedAt;
  final RateChangeStretch stretch;
}

List<_DatedStretch> _stretchesForUnit(int unitId, List<SaleTransaction> rows) {
  final List<_DatedStretch> result = <_DatedStretch>[];
  final List<SaleTransaction> leadingTests = <SaleTransaction>[];
  List<SaleTransaction> current = <SaleTransaction>[];
  String? rateKey;
  double? rate;

  void close() {
    if (current.isEmpty) {
      return;
    }
    result.add(
      _DatedStretch(
        startedAt: current.first.timestamp,
        stretch: _stretchFrom(unitId, rate ?? current.first.rate, current),
      ),
    );
    current = <SaleTransaction>[];
  }

  for (final SaleTransaction row in rows) {
    if (row.isTest) {
      if (rateKey == null) {
        leadingTests.add(row);
      } else {
        current.add(row);
      }
      continue;
    }
    final String key = displayedRateKey(row.rate);
    if (rateKey == null) {
      rateKey = key;
      rate = row.rate;
      current = <SaleTransaction>[...leadingTests, row];
      leadingTests.clear();
    } else if (key != rateKey) {
      close();
      rateKey = key;
      rate = row.rate;
      current = <SaleTransaction>[row];
    } else {
      current.add(row);
    }
  }
  close();
  if (leadingTests.isNotEmpty) {
    result.add(
      _DatedStretch(
        startedAt: leadingTests.first.timestamp,
        stretch: _stretchFrom(unitId, leadingTests.first.rate, leadingTests),
      ),
    );
  }
  return result;
}

RateChangeStretch _stretchFrom(
  int unitId,
  double rate,
  List<SaleTransaction> rows,
) {
  final Decimal dispensed = meterDeltaLiters(
    rows.first.openingMeter,
    rows.last.closingMeter,
  );
  Decimal test = Decimal.zero;
  for (final SaleTransaction row in rows) {
    if (row.isTest) {
      test += parseFuel(row.volumeLiters);
    }
  }
  final Decimal net = truncateFuel(dispensed - test);
  return RateChangeStretch(
    unitId: unitId,
    rate: rate,
    openingMeter: rows.first.openingMeter,
    closingMeter: rows.last.closingMeter,
    dispensedLiters: dispensed.toDouble(),
    testLiters: test.toDouble(),
    netLiters: net.toDouble(),
    amountPkr: roundRupees(net * parseDecimal(rate)),
  );
}
