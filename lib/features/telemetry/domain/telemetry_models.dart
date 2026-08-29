enum ProductType { petrol, diesel, hobc, kerosene, unknown }

enum PumpStatus { unknown, idle, nozzleActive, rupeesPreset, litersPreset }

enum SaleEventKind { noSale, saleClosed, saleStarted, logRecord }

class SaleEvent {
  const SaleEvent({
    required this.kind,
    required this.message,
    required this.logLine,
  });

  final SaleEventKind kind;
  final String message;
  final String logLine;
}

class Type33Frame {
  const Type33Frame({
    required this.product,
    required this.pumpStatus,
    required this.totalAmount,
    required this.volumeLiters,
    required this.unitRate,
    required this.totalMeter,
  });

  final ProductType product;
  final PumpStatus pumpStatus;
  final double totalAmount;
  final double volumeLiters;
  final double unitRate;
  final double totalMeter;
}

class Type37Result {
  const Type37Result({
    required this.noSale,
    required this.amount,
    required this.volumeLiters,
    required this.unitRate,
    required this.timeLabel,
    required this.dateLabel,
    required this.event,
  });

  final bool noSale;
  final double amount;
  final double volumeLiters;
  final double unitRate;
  final String timeLabel;
  final String dateLabel;
  final SaleEvent event;
}

class IngestOutcome {
  const IngestOutcome({
    required this.snapshot,
    this.logLines = const <String>[],
  });

  final TelemetrySnapshot snapshot;
  final List<String> logLines;
}

class TelemetrySnapshot {
  const TelemetrySnapshot({
    this.volumeLiters,
    this.totalAmount,
    this.unitRate,
    this.totalMeter,
    this.pumpStatus = PumpStatus.unknown,
    this.product = ProductType.unknown,
    this.timeLabel,
    this.timeFromRtc = false,
    this.lastEvent,
    this.events = const <SaleEvent>[],
    this.rxBytes = 0,
  });

  final double? volumeLiters;
  final double? totalAmount;
  final double? unitRate;
  final double? totalMeter;
  final PumpStatus pumpStatus;
  final ProductType product;
  final String? timeLabel;
  final bool timeFromRtc;
  final SaleEvent? lastEvent;
  final List<SaleEvent> events;
  final int rxBytes;

  static const TelemetrySnapshot empty = TelemetrySnapshot();

  String get productLabel => product.label;
  String get statusLabel => pumpStatus.label;

  TelemetrySnapshot copyWith({
    double? volumeLiters,
    double? totalAmount,
    double? unitRate,
    double? totalMeter,
    PumpStatus? pumpStatus,
    ProductType? product,
    String? timeLabel,
    bool? timeFromRtc,
    SaleEvent? lastEvent,
    List<SaleEvent>? events,
    int? rxBytes,
  }) {
    return TelemetrySnapshot(
      volumeLiters: volumeLiters ?? this.volumeLiters,
      totalAmount: totalAmount ?? this.totalAmount,
      unitRate: unitRate ?? this.unitRate,
      totalMeter: totalMeter ?? this.totalMeter,
      pumpStatus: pumpStatus ?? this.pumpStatus,
      product: product ?? this.product,
      timeLabel: timeLabel ?? this.timeLabel,
      timeFromRtc: timeFromRtc ?? this.timeFromRtc,
      lastEvent: lastEvent ?? this.lastEvent,
      events: events ?? this.events,
      rxBytes: rxBytes ?? this.rxBytes,
    );
  }

  TelemetrySnapshot mergeType33(Type33Frame frame) {
    return copyWith(
      totalAmount: frame.totalAmount,
      volumeLiters: frame.volumeLiters,
      unitRate: frame.unitRate,
      totalMeter: frame.totalMeter,
      pumpStatus: frame.pumpStatus,
      product: frame.product,
      timeLabel: timeFromRtc ? timeLabel : _systemClock(),
      timeFromRtc: timeFromRtc,
    );
  }

  TelemetrySnapshot mergeType37(Type37Result result) {
    return _withEvent(result.event).copyWith(
      volumeLiters: result.volumeLiters,
      totalAmount: result.amount,
      unitRate: result.unitRate,
      timeLabel: result.timeLabel,
      timeFromRtc: true,
      pumpStatus: PumpStatus.idle,
    );
  }

  TelemetrySnapshot addEvent(SaleEvent event) {
    return _withEvent(event);
  }

  TelemetrySnapshot _withEvent(SaleEvent event) {
    final List<SaleEvent> next = <SaleEvent>[...events, event];
    if (next.length > 80) {
      next.removeRange(0, next.length - 80);
    }
    return copyWith(lastEvent: event, events: next);
  }
}

String _systemClock() {
  final DateTime now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
}

extension ProductTypeLabel on ProductType {
  String get label {
    switch (this) {
      case ProductType.petrol:
        return 'Petrol';
      case ProductType.diesel:
        return 'Diesel';
      case ProductType.hobc:
        return 'HOBC';
      case ProductType.kerosene:
        return 'Kerosene';
      case ProductType.unknown:
        return '—';
    }
  }
}

extension PumpStatusLabel on PumpStatus {
  String get label {
    switch (this) {
      case PumpStatus.nozzleActive:
        return 'Active / Pumping';
      case PumpStatus.rupeesPreset:
      case PumpStatus.litersPreset:
        return 'Preset mode';
      case PumpStatus.idle:
        return 'Idle';
      case PumpStatus.unknown:
        return '—';
    }
  }
}
