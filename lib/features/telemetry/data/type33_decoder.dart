import '../domain/telemetry_models.dart';
import 'java_mid.dart';

/// Live Type-33. Slices match FDX Remote Plus `_decode_33` (1-based Mid).
///
/// Idle / pumping (`0` / `5`): amount, liters, rate, meter all ÷ 100.
/// Rupees preset `P` and liters preset `L`: keypad value is Mid(5,8) with
/// no ÷ 100. Liters LCD is hidden in the official app.
Type33Frame? decodeType33(String payload) {
  if (payload.length != 33) {
    return null;
  }
  try {
    final PumpStatus pumpStatus = _status(javaMid(payload, 1, 1));
    final String amountRaw = javaMid(payload, 5, 8);
    final String volumeRaw = javaMid(payload, 13, 8);
    return Type33Frame(
      product: _product(javaMid(payload, 4, 1)),
      pumpStatus: pumpStatus,
      totalAmount: pumpStatus == PumpStatus.rupeesPreset
          ? double.parse(amountRaw)
          : pumpStatus == PumpStatus.litersPreset
          ? 0
          : double.parse(amountRaw) / 100.0,
      volumeLiters: pumpStatus == PumpStatus.litersPreset
          ? double.parse(amountRaw)
          : double.parse(volumeRaw) / 100.0,
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
