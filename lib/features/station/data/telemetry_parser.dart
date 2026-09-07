import 'dart:convert';

import '../domain/dispenser_models.dart';

class TelemetryParser {
  static const int minUnitId = 1;
  static const int maxUnitId = 5;

  DispenserTelemetry? tryParse(String chunk) {
    final String trimmed = chunk.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(trimmed);
      if (decoded is! Map) {
        return null;
      }
      final Map<String, dynamic> map = Map<String, dynamic>.from(decoded);
      final int unitId = _asInt(map['unit'] ?? map['unit_id']);
      if (unitId < minUnitId || unitId > maxUnitId) {
        return null;
      }
      return DispenserTelemetry(
        unitId: unitId,
        amountPkr: _asDouble(map['amount'] ?? map['amount_pkr']),
        volumeLiters: _asDouble(map['liters']),
        rate: _asDouble(map['rate'] ?? map['rate_pkr']),
        meterCount: _asInt(map['meter'] ?? map['total_meter']),
        status: dispenserStatusFromWire(map['status']?.toString()),
        keypadLocked: map['keypad_locked'] == true,
        rssiDbm: map.containsKey('rssi') ? _asInt(map['rssi']) : null,
        pulseCount: map.containsKey('pulses')
            ? _asInt(map['pulses'])
            : (map.containsKey('pulse') ? _asInt(map['pulse']) : null),
      );
    } catch (_) {
      return null;
    }
  }

  int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _asDouble(Object? value) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
