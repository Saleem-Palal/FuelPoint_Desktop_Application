import 'package:flutter/services.dart';

/// Uppercase plate text. Keeps letters, digits, spaces, and hyphens.
String formatVehicleRegistration(String raw) {
  final StringBuffer out = StringBuffer();
  bool lastSpace = false;
  for (final int unit in raw.toUpperCase().codeUnits) {
    final bool letter = unit >= 65 && unit <= 90;
    final bool digit = unit >= 48 && unit <= 57;
    final bool hyphen = unit == 45;
    final bool space = unit == 32;
    if (!letter && !digit && !hyphen && !space) {
      continue;
    }
    if (space) {
      if (out.isEmpty || lastSpace) {
        continue;
      }
      lastSpace = true;
      out.writeCharCode(unit);
      continue;
    }
    lastSpace = false;
    out.writeCharCode(unit);
  }
  return out.toString().trim();
}

/// True when the field has at least one letter and one digit (any order).
bool isVehicleRegistrationValid(String raw) {
  final String compact = formatVehicleRegistration(
    raw,
  ).replaceAll(RegExp(r'[\s-]'), '');
  if (compact.isEmpty) {
    return false;
  }
  final bool hasLetter = RegExp(r'[A-Z]').hasMatch(compact);
  final bool hasDigit = RegExp(r'[0-9]').hasMatch(compact);
  return hasLetter && hasDigit;
}

String persistVehicleNo(String raw) {
  if (!isVehicleRegistrationValid(raw)) {
    return '';
  }
  return formatVehicleRegistration(raw);
}

class VehicleRegistrationFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final String next = formatVehicleRegistration(newValue.text);
    return TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }
}
