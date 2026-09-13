import 'dart:convert';

import '../domain/dispenser_models.dart';

class TelemetryParser {
  static const int minUnitId = 1;
  static const int maxUnitId = 5;

  DispenserTelemetry? tryParse(String chunk, {int fallbackUnit = 0}) {
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
      final Map<String, dynamic> tel = map['telemetry'] is Map
          ? Map<String, dynamic>.from(map['telemetry'] as Map)
          : map;
      final Map<String, dynamic> flags = map['status_flags'] is Map
          ? Map<String, dynamic>.from(map['status_flags'] as Map)
          : map;
      final Map<String, dynamic> system = map['system'] is Map
          ? Map<String, dynamic>.from(map['system'] as Map)
          : map;
      int unitId = _asInt(map['unit'] ?? map['unit_id']);
      if (unitId < minUnitId || unitId > maxUnitId) {
        unitId = fallbackUnit;
      }
      if (unitId < minUnitId || unitId > maxUnitId) {
        return null;
      }
      final Object? statusRaw = tel['status'] ?? map['status'];
      return DispenserTelemetry(
        unitId: unitId,
        amountPkr: _asHundredths(
          tel['amount'] ?? tel['amount_pkr'] ?? map['amount'],
          tel['amount_cents'] ?? map['amount_cents'],
        ),
        volumeLiters: _asHundredths(
          tel['liters'] ?? map['liters'],
          tel['liter_cents'] ?? map['liter_cents'],
        ),
        rate: _asHundredths(
          tel['rate'] ?? tel['rate_pkr'] ?? map['rate'],
          tel['rate_cents'] ?? map['rate_cents'],
        ),
        meterCount: _asHundredths(
          tel['meter'] ?? tel['total_meter'] ?? map['meter'],
          tel['meter_cents'] ?? map['meter_cents'],
        ),
        status: dispenserStatusFromWire(statusRaw?.toString()),
        keypadLocked:
            flags['keypad_locked'] == true || map['keypad_locked'] == true,
        rssiDbm: system.containsKey('wifi_rssi')
            ? _asInt(system['wifi_rssi'])
            : (map.containsKey('rssi') ? _asInt(map['rssi']) : null),
        txId: '${map['tx_id'] ?? ''}',
        cmd: '${map['cmd'] ?? ''}',
        espToBoardLink: flags['esp_to_board_link'] is bool
            ? flags['esp_to_board_link'] as bool
            : null,
        pendingTxCount: system.containsKey('pending_tx_count')
            ? _asInt(system['pending_tx_count'])
            : null,
        product: '${tel['product'] ?? ''}',
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

  /// Prefer integer hundredths from the ESP so 6618.50 never becomes 6619.
  double _asHundredths(Object? value, Object? cents) {
    if (cents is int) {
      return cents / 100.0;
    }
    if (cents is num) {
      return cents.toInt() / 100.0;
    }
    final int? parsedCents = int.tryParse('${cents ?? ''}'.trim());
    if (parsedCents != null) {
      return parsedCents / 100.0;
    }
    return _asDouble(value);
  }
}
