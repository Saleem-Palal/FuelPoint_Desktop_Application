import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Editable receipt block under the dashed rule (preview and thermal print).
@immutable
class ReceiptFooterSettings {
  const ReceiptFooterSettings({
    required this.lines,
    required this.fontSize,
    required this.lineHeight,
  });

  static const int maxCharsPerLine = 44;
  static const double minFontSize = 14;
  static const double maxFontSize = 24;
  static const double defaultFontSize = 13 * (456 / 272) * 0.95 * 1.04;
  static const double minLineHeight = 1.4;
  static const double maxLineHeight = 2.0;
  static const double defaultLineHeight = 1.7;

  static const List<String> defaultLines = <String>[
    'انڈسٹریل ایریا مین کوئٹہ روڈ ڈیرہ مراد جمالی',
    'پروپرائیٹر: حاجی عبدالحلیم عمرانی',
    'مینیجر: لطیف عمرانی',
    'کسی بھی قسم کی شکایت کے لیے رابطہ کریں',
    '0334 3706655',
    'آپ کا شکریہ — آپ کا بھروسہ ہماری اولین ترجیح۔',
  ];

  static const ReceiptFooterSettings defaults = ReceiptFooterSettings(
    lines: defaultLines,
    fontSize: defaultFontSize,
    lineHeight: defaultLineHeight,
  );

  final List<String> lines;
  final double fontSize;
  final double lineHeight;

  String get encodedText => lines.join('\n');

  ReceiptFooterSettings copyWith({
    List<String>? lines,
    double? fontSize,
    double? lineHeight,
  }) {
    return ReceiptFooterSettings(
      lines: lines ?? this.lines,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
    ).sanitized();
  }

  ReceiptFooterSettings sanitized() {
    return ReceiptFooterSettings(
      lines: sanitizeLines(lines),
      fontSize: clampFontSize(fontSize),
      lineHeight: clampLineHeight(lineHeight),
    );
  }

  static ReceiptFooterSettings fromStorage({
    String? text,
    String? fontSizeRaw,
    String? lineHeightRaw,
  }) {
    final String raw = (text ?? '').trim();
    return ReceiptFooterSettings(
      lines: raw.isEmpty ? defaultLines : sanitizeLines(raw.split('\n')),
      fontSize: clampFontSize(
        double.tryParse((fontSizeRaw ?? '').trim()) ?? defaultFontSize,
      ),
      lineHeight: clampLineHeight(
        double.tryParse((lineHeightRaw ?? '').trim()) ?? defaultLineHeight,
      ),
    );
  }

  static List<String> sanitizeLines(Iterable<String> raw) {
    final List<String> out = <String>[];
    for (final String line in raw) {
      final String trimmed = truncateGraphemes(line.trim(), maxCharsPerLine);
      if (trimmed.isEmpty) {
        continue;
      }
      out.add(trimmed);
    }
    return out;
  }

  /// Keeps in-progress spaces and a trailing newline while typing.
  /// Each line is clipped so the slip cannot grow sideways.
  static String clampTyping(String raw) {
    return raw
        .split('\n')
        .map((String line) => truncateGraphemes(line, maxCharsPerLine))
        .join('\n');
  }

  static String truncateGraphemes(String input, int max) {
    if (max <= 0) {
      return '';
    }
    final Characters chars = input.characters;
    if (chars.length <= max) {
      return input;
    }
    return chars.take(max).toString();
  }

  static int graphemeCount(String input) => input.characters.length;

  static double clampFontSize(double value) {
    if (!value.isFinite) {
      return defaultFontSize;
    }
    return value.clamp(minFontSize, maxFontSize).toDouble();
  }

  static double clampLineHeight(double value) {
    if (!value.isFinite) {
      return defaultLineHeight;
    }
    return value.clamp(minLineHeight, maxLineHeight).toDouble();
  }

  static bool isLatinLine(String text) {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    return trimmed.codeUnits.every((int unit) => unit < 128);
  }

  @override
  bool operator ==(Object other) {
    return other is ReceiptFooterSettings &&
        listEquals(other.lines, lines) &&
        other.fontSize == fontSize &&
        other.lineHeight == lineHeight;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(lines), fontSize, lineHeight);
}

/// Blocks extra characters on a line so the thermal footer cannot overflow sideways.
class ReceiptFooterInputFormatter extends TextInputFormatter {
  const ReceiptFooterInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final String next = ReceiptFooterSettings.clampTyping(newValue.text);
    if (next == newValue.text) {
      return newValue;
    }
    final int offset = newValue.selection.baseOffset;
    final int safeOffset = offset < 0
        ? next.length
        : offset.clamp(0, next.length);
    return TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: safeOffset),
    );
  }
}
