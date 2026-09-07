import '../../customer/domain/customer_models.dart';
import 'dispenser_models.dart';

enum DashboardRangePreset { today, lastWeek, thisMonth }

extension DashboardRangePresetX on DashboardRangePreset {
  String get chipLabel {
    switch (this) {
      case DashboardRangePreset.today:
        return 'Today';
      case DashboardRangePreset.lastWeek:
        return 'Last Week';
      case DashboardRangePreset.thisMonth:
        return 'This Month';
    }
  }

  String get hint {
    switch (this) {
      case DashboardRangePreset.today:
        return 'Calendar day';
      case DashboardRangePreset.lastWeek:
        return 'Last 7 days';
      case DashboardRangePreset.thisMonth:
        return 'Calendar month';
    }
  }
}

class DashboardDateSpan {
  const DashboardDateSpan({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

DateTime startOfLocalDay(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

DashboardDateSpan spanForDashboardPreset(
  DashboardRangePreset preset, {
  required DateTime now,
}) {
  final DateTime today = startOfLocalDay(now);
  switch (preset) {
    case DashboardRangePreset.today:
      return DashboardDateSpan(start: today, end: today);
    case DashboardRangePreset.lastWeek:
      return DashboardDateSpan(
        start: today.subtract(const Duration(days: 6)),
        end: today,
      );
    case DashboardRangePreset.thisMonth:
      return DashboardDateSpan(
        start: DateTime(now.year, now.month),
        end: today,
      );
  }
}

bool isInDashboardRange(DateTime timestamp, DashboardDateSpan range) {
  final DateTime day = startOfLocalDay(timestamp);
  return !day.isBefore(startOfLocalDay(range.start)) &&
      !day.isAfter(startOfLocalDay(range.end));
}

bool _staffNamesMatch(String left, String right) {
  return left.trim().toUpperCase() == right.trim().toUpperCase();
}

bool isDieselSale(SaleTransaction row) {
  return row.fuelType.trim().toLowerCase() == kDieselFuelType.toLowerCase();
}

String formatBayLabel(int unitId) {
  return 'Bay ${unitId.toString().padLeft(2, '0')}';
}

String formatDashboardHour(int hour) {
  final int safe = hour % 24;
  final int display = safe % 12 == 0 ? 12 : safe % 12;
  final String period = safe >= 12 ? 'PM' : 'AM';
  return '${display.toString().padLeft(2, '0')}:00 $period';
}

String formatDashboardHourRange(int startHour, int endHourExclusive) {
  return '${formatDashboardHour(startHour)} – ${formatDashboardHour(endHourExclusive % 24)}';
}

class DashboardKpis {
  const DashboardKpis({
    required this.dieselSoldLiters24h,
    required this.dieselSoldTxnCount24h,
    required this.cashSalesPkrToday,
    required this.cashTxnCountToday,
    required this.udhaarExtendedPkrToday,
    required this.udhaarTxnCountToday,
    required this.totalOutstandingPkr,
    required this.activeDebtAccounts,
  });

  final double dieselSoldLiters24h;
  final int dieselSoldTxnCount24h;
  final double cashSalesPkrToday;
  final int cashTxnCountToday;
  final double udhaarExtendedPkrToday;
  final int udhaarTxnCountToday;
  final double totalOutstandingPkr;
  final int activeDebtAccounts;
}

class DashboardBayPerformance {
  const DashboardBayPerformance({
    required this.unitId,
    required this.volumeLiters,
    required this.revenuePkr,
    required this.txnCount,
    required this.shareOfPeak,
    required this.isPeakLane,
  });

  final int unitId;
  final double volumeLiters;
  final double revenuePkr;
  final int txnCount;
  final double shareOfPeak;
  final bool isPeakLane;

  String get label => formatBayLabel(unitId);
}

class DashboardStaffMember {
  const DashboardStaffMember({required this.id, required this.name});

  final String id;
  final String name;
}

class DashboardStaffPerformance {
  const DashboardStaffPerformance({
    required this.id,
    required this.name,
    required this.volumeLiters,
    required this.revenuePkr,
    required this.txnCount,
    required this.shareOfPeak,
  });

  final String id;
  final String name;
  final double volumeLiters;
  final double revenuePkr;
  final int txnCount;
  final double shareOfPeak;
}

class DashboardPeakWindow {
  const DashboardPeakWindow({
    required this.title,
    required this.daysLabel,
    required this.startHour,
    required this.endHourExclusive,
    required this.volumeLiters,
  });

  final String title;
  final String daysLabel;
  final int startHour;
  final int endHourExclusive;
  final double volumeLiters;

  String get rangeLabel =>
      formatDashboardHourRange(startHour, endHourExclusive);

  String get bannerLabel => '$title: $daysLabel $rangeLabel';
}

class DashboardHourlyBucket {
  const DashboardHourlyBucket({
    required this.hour,
    required this.volumeLiters,
    required this.txnCount,
    required this.intensity,
  });

  final int hour;
  final double volumeLiters;
  final int txnCount;

  /// 0–1 relative to the busiest hour in the week.
  final double intensity;

  String get hourLabel => formatDashboardHour(hour);
}

class DashboardWatchlistRow {
  const DashboardWatchlistRow({required this.account});

  final CustomerAccount account;

  String get customerName => account.profile.name;
  String get customerId => account.profile.id;
  double get outstandingPkr => account.outstanding;
}

class DashboardSnapshot {
  const DashboardSnapshot({
    required this.asOf,
    required this.kpis,
    required this.bays,
    required this.managers,
    required this.helpers,
    required this.morningPeak,
    required this.eveningPeak,
    required this.hourly,
    required this.watchlist,
    required this.watchlistTotal,
    required this.busiestHour,
  });

  final DateTime asOf;
  final DashboardKpis kpis;
  final List<DashboardBayPerformance> bays;
  final List<DashboardStaffPerformance> managers;
  final List<DashboardStaffPerformance> helpers;
  final DashboardPeakWindow morningPeak;
  final DashboardPeakWindow eveningPeak;
  final List<DashboardHourlyBucket> hourly;
  final List<DashboardWatchlistRow> watchlist;
  final int watchlistTotal;
  final DashboardHourlyBucket? busiestHour;
}

/// Aggregates `sales_history` + customer outstanding. No live telemetry.
DashboardSnapshot assembleDashboardSnapshot({
  required List<SaleTransaction> sales,
  required List<CustomerAccount> accounts,
  required DateTime now,
  DashboardRangePreset bayRange = DashboardRangePreset.today,
  DashboardRangePreset managerRange = DashboardRangePreset.today,
  DashboardRangePreset helperRange = DashboardRangePreset.today,
  List<DashboardStaffMember> managers = const <DashboardStaffMember>[],
  List<DashboardStaffMember> helpers = const <DashboardStaffMember>[],
  int watchlistLimit = 8,
}) {
  final DateTime todayStart = startOfLocalDay(now);
  final DateTime last24h = now.subtract(const Duration(hours: 24));
  final DateTime weekStart = todayStart.subtract(const Duration(days: 6));
  final DashboardDateSpan baySpan = spanForDashboardPreset(bayRange, now: now);
  final DashboardDateSpan managerSpan = spanForDashboardPreset(
    managerRange,
    now: now,
  );
  final DashboardDateSpan helperSpan = spanForDashboardPreset(
    helperRange,
    now: now,
  );

  double dieselLiters24h = 0;
  int dieselCount24h = 0;
  double cashPkrToday = 0;
  int cashCountToday = 0;
  double udhaarPkrToday = 0;
  int udhaarCountToday = 0;

  final Map<int, _MetricAcc> bayAcc = <int, _MetricAcc>{
    for (final int unitId in dispenserUnitIds) unitId: _MetricAcc(),
  };
  final List<double> hourlyLiters = List<double>.filled(24, 0);
  final List<int> hourlyCount = List<int>.filled(24, 0);
  final List<List<double>> weekdayHourLiters = List<List<double>>.generate(
    7,
    (_) => List<double>.filled(24, 0),
  );

  for (final SaleTransaction row in sales) {
    if (!isDieselSale(row)) {
      continue;
    }
    final bool in24h =
        !row.timestamp.isBefore(last24h) && !row.timestamp.isAfter(now);
    final bool inToday =
        !row.timestamp.isBefore(todayStart) && !row.timestamp.isAfter(now);
    final bool inWeek =
        !row.timestamp.isBefore(weekStart) && !row.timestamp.isAfter(now);

    if (in24h) {
      dieselLiters24h += row.volumeLiters;
      dieselCount24h += 1;
    }
    if (isInDashboardRange(row.timestamp, baySpan) &&
        !row.timestamp.isAfter(now)) {
      final _MetricAcc? bay = bayAcc[row.unitId];
      if (bay != null) {
        bay.volume += row.volumeLiters;
        bay.revenue += row.amountPkr;
        bay.count += 1;
      }
    }
    if (inToday) {
      if (row.payment == PaymentMethod.cash) {
        cashPkrToday += row.amountPkr;
        cashCountToday += 1;
      } else if (row.payment == PaymentMethod.udhaar) {
        udhaarPkrToday += row.amountPkr;
        udhaarCountToday += 1;
      }
    }
    if (inWeek) {
      final int hour = row.timestamp.hour;
      hourlyLiters[hour] += row.volumeLiters;
      hourlyCount[hour] += 1;
      weekdayHourLiters[row.timestamp.weekday - 1][hour] += row.volumeLiters;
    }
  }

  int peakUnitId = -1;
  double peakVolume = 0;
  double peakRevenue = 0;
  for (final int unitId in dispenserUnitIds) {
    final double volume = bayAcc[unitId]?.volume ?? 0;
    final double revenue = bayAcc[unitId]?.revenue ?? 0;
    if (volume <= 0) {
      continue;
    }
    final bool betterVolume = volume > peakVolume;
    final bool betterRevenue = volume == peakVolume && revenue > peakRevenue;
    final bool betterId =
        volume == peakVolume &&
        revenue == peakRevenue &&
        (peakUnitId < 0 || unitId < peakUnitId);
    if (betterVolume || betterRevenue || betterId) {
      peakUnitId = unitId;
      peakVolume = volume;
      peakRevenue = revenue;
    }
  }

  final List<DashboardBayPerformance> bays = <DashboardBayPerformance>[
    for (final int unitId in dispenserUnitIds)
      DashboardBayPerformance(
        unitId: unitId,
        volumeLiters: bayAcc[unitId]?.volume ?? 0,
        revenuePkr: bayAcc[unitId]?.revenue ?? 0,
        txnCount: bayAcc[unitId]?.count ?? 0,
        shareOfPeak: peakVolume <= 0
            ? 0
            : ((bayAcc[unitId]?.volume ?? 0) / peakVolume).clamp(0, 1),
        isPeakLane: unitId == peakUnitId,
      ),
  ];

  final List<DashboardStaffPerformance> managerCards = _assembleStaff(
    roster: managers,
    sales: sales,
    now: now,
    range: managerSpan,
    nameOf: (SaleTransaction row) => row.cashierName,
  );
  final List<DashboardStaffPerformance> helperCards = _assembleStaff(
    roster: helpers,
    sales: sales,
    now: now,
    range: helperSpan,
    nameOf: (SaleTransaction row) => row.helperName,
  );

  double maxHourly = 0;
  int busiestHour = 0;
  for (int hour = 0; hour < 24; hour++) {
    if (hourlyLiters[hour] > maxHourly) {
      maxHourly = hourlyLiters[hour];
      busiestHour = hour;
    }
  }

  final List<DashboardHourlyBucket> hourly = <DashboardHourlyBucket>[
    for (int hour = 0; hour < 24; hour++)
      DashboardHourlyBucket(
        hour: hour,
        volumeLiters: hourlyLiters[hour],
        txnCount: hourlyCount[hour],
        intensity: maxHourly <= 0 ? 0 : hourlyLiters[hour] / maxHourly,
      ),
  ];

  final DashboardPeakWindow morningPeak = _detectPeakWindow(
    title: 'Morning Peak',
    fallbackDays: 'Mon–Thu',
    fallbackStart: 6,
    fallbackEnd: 10,
    searchStart: 5,
    searchEndExclusive: 12,
    windowLength: 4,
    weekdayHourLiters: weekdayHourLiters,
  );
  final DashboardPeakWindow eveningPeak = _detectPeakWindow(
    title: 'Evening Rush',
    fallbackDays: 'Daily',
    fallbackStart: 17,
    fallbackEnd: 21,
    searchStart: 15,
    searchEndExclusive: 23,
    windowLength: 4,
    weekdayHourLiters: weekdayHourLiters,
  );

  double totalOutstanding = 0;
  int activeDebt = 0;
  final List<CustomerAccount> debtors = <CustomerAccount>[];
  for (final CustomerAccount account in accounts) {
    totalOutstanding += account.outstanding;
    if (account.hasDebt) {
      activeDebt += 1;
      debtors.add(account);
    }
  }
  debtors.sort(
    (CustomerAccount a, CustomerAccount b) =>
        b.outstanding.compareTo(a.outstanding),
  );
  final int limit = watchlistLimit < 1 ? 1 : watchlistLimit;
  final List<DashboardWatchlistRow> watchlist = debtors
      .take(limit)
      .map((CustomerAccount account) => DashboardWatchlistRow(account: account))
      .toList();

  return DashboardSnapshot(
    asOf: now,
    kpis: DashboardKpis(
      dieselSoldLiters24h: dieselLiters24h,
      dieselSoldTxnCount24h: dieselCount24h,
      cashSalesPkrToday: cashPkrToday,
      cashTxnCountToday: cashCountToday,
      udhaarExtendedPkrToday: udhaarPkrToday,
      udhaarTxnCountToday: udhaarCountToday,
      totalOutstandingPkr: totalOutstanding,
      activeDebtAccounts: activeDebt,
    ),
    bays: bays,
    managers: managerCards,
    helpers: helperCards,
    morningPeak: morningPeak,
    eveningPeak: eveningPeak,
    hourly: hourly,
    watchlist: watchlist,
    watchlistTotal: debtors.length,
    busiestHour: maxHourly <= 0 ? null : hourly[busiestHour],
  );
}

class _MetricAcc {
  double volume = 0;
  double revenue = 0;
  int count = 0;
}

List<DashboardStaffPerformance> _assembleStaff({
  required List<DashboardStaffMember> roster,
  required List<SaleTransaction> sales,
  required DateTime now,
  required DashboardDateSpan range,
  required String Function(SaleTransaction row) nameOf,
}) {
  if (roster.isEmpty) {
    return const <DashboardStaffPerformance>[];
  }
  final Map<String, _MetricAcc> byId = <String, _MetricAcc>{
    for (final DashboardStaffMember member in roster) member.id: _MetricAcc(),
  };
  for (final SaleTransaction row in sales) {
    if (!isDieselSale(row)) {
      continue;
    }
    if (!isInDashboardRange(row.timestamp, range) ||
        row.timestamp.isAfter(now)) {
      continue;
    }
    final String saleName = nameOf(row).trim();
    if (saleName.isEmpty) {
      continue;
    }
    for (final DashboardStaffMember member in roster) {
      if (!_staffNamesMatch(member.name, saleName)) {
        continue;
      }
      final _MetricAcc? acc = byId[member.id];
      if (acc == null) {
        break;
      }
      acc.volume += row.volumeLiters;
      acc.revenue += row.amountPkr;
      acc.count += 1;
      break;
    }
  }

  double peakVolume = 0;
  for (final DashboardStaffMember member in roster) {
    final double volume = byId[member.id]?.volume ?? 0;
    if (volume > peakVolume) {
      peakVolume = volume;
    }
  }

  return <DashboardStaffPerformance>[
    for (final DashboardStaffMember member in roster)
      DashboardStaffPerformance(
        id: member.id,
        name: member.name,
        volumeLiters: byId[member.id]?.volume ?? 0,
        revenuePkr: byId[member.id]?.revenue ?? 0,
        txnCount: byId[member.id]?.count ?? 0,
        shareOfPeak: peakVolume <= 0
            ? 0
            : ((byId[member.id]?.volume ?? 0) / peakVolume).clamp(0, 1),
      ),
  ];
}

DashboardPeakWindow _detectPeakWindow({
  required String title,
  required String fallbackDays,
  required int fallbackStart,
  required int fallbackEnd,
  required int searchStart,
  required int searchEndExclusive,
  required int windowLength,
  required List<List<double>> weekdayHourLiters,
}) {
  int bestStart = fallbackStart;
  double bestVolume = -1;
  final int lastStart = searchEndExclusive - windowLength;
  for (int start = searchStart; start <= lastStart; start++) {
    double volume = 0;
    for (int hour = start; hour < start + windowLength; hour++) {
      for (int weekday = 0; weekday < 7; weekday++) {
        volume += weekdayHourLiters[weekday][hour];
      }
    }
    if (volume > bestVolume) {
      bestVolume = volume;
      bestStart = start;
    }
  }

  final int end = bestStart + windowLength;
  if (bestVolume <= 0) {
    return DashboardPeakWindow(
      title: title,
      daysLabel: fallbackDays,
      startHour: fallbackStart,
      endHourExclusive: fallbackEnd,
      volumeLiters: 0,
    );
  }

  final List<double> byWeekday = List<double>.filled(7, 0);
  double maxWeekday = 0;
  for (int weekday = 0; weekday < 7; weekday++) {
    double sum = 0;
    for (int hour = bestStart; hour < end; hour++) {
      sum += weekdayHourLiters[weekday][hour];
    }
    byWeekday[weekday] = sum;
    if (sum > maxWeekday) {
      maxWeekday = sum;
    }
  }

  final List<int> busy = <int>[];
  final double threshold = maxWeekday * 0.55;
  for (int weekday = 0; weekday < 7; weekday++) {
    if (byWeekday[weekday] >= threshold && byWeekday[weekday] > 0) {
      busy.add(weekday + 1);
    }
  }

  return DashboardPeakWindow(
    title: title,
    daysLabel: _formatBusyDays(busy, fallbackDays),
    startHour: bestStart,
    endHourExclusive: end,
    volumeLiters: bestVolume,
  );
}

String _formatBusyDays(List<int> weekdays, String fallback) {
  if (weekdays.isEmpty) {
    return fallback;
  }
  if (weekdays.length >= 6) {
    return 'Daily';
  }
  const List<String> names = <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
  final List<int> sorted = List<int>.from(weekdays)..sort();
  if (_isContiguous(sorted)) {
    if (sorted.length == 1) {
      return names[sorted.first - 1];
    }
    return '${names[sorted.first - 1]}–${names[sorted.last - 1]}';
  }
  return sorted.map((int day) => names[day - 1]).join(', ');
}

bool _isContiguous(List<int> sorted) {
  if (sorted.length <= 1) {
    return true;
  }
  for (int i = 1; i < sorted.length; i++) {
    if (sorted[i] != sorted[i - 1] + 1) {
      return false;
    }
  }
  return true;
}
