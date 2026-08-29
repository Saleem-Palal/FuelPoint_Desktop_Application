import '../domain/telemetry_models.dart';
import 'java_mid.dart';

/// Live Type-33. Slices match the Java Mid(start, length) map (1-based).
///
/// Amount  Mid(5, 8)  → rupees / 100
/// Liters  Mid(13, 8) → liters / 100
/// Rate    Mid(21, 5) → Rs/L / 100
/// Meter   Mid(26, 8) → total meter / 100  (not a clock)
Type33Frame? decodeType33(String payload) {
  if (payload.length != 33) {
    return null;
  }
  try {
    return Type33Frame(
      product: _product(javaMid(payload, 4, 1)),
      pumpStatus: _status(javaMid(payload, 1, 1)),
      totalAmount: javaMoney(payload, 5, 8),
      volumeLiters: javaMoney(payload, 13, 8),
      unitRate: javaMoney(payload, 21, 5),
      totalMeter: javaMoney(payload, 26, 8),
    );
  } catch (_) {
    return null;
  }
}

ProductType _product(String code) {
  switch (code) {
    case '0':
      return ProductType.petrol;
    case '1':
      return ProductType.diesel;
    case '2':
      return ProductType.hobc;
    case '3':
      return ProductType.kerosene;
    default:
      return ProductType.unknown;
  }
}

PumpStatus _status(String code) {
  switch (code) {
    case '5':
      return PumpStatus.nozzleActive;
    case '0':
      return PumpStatus.idle;
    case 'P':
    case 'p':
      return PumpStatus.rupeesPreset;
    case 'L':
    case 'l':
      return PumpStatus.litersPreset;
    default:
      return PumpStatus.unknown;
  }
}
