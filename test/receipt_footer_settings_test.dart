import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fuel_dispenser/features/station/domain/receipt_footer_settings.dart';

void main() {
  test('default footer stays within the per-line character cap', () {
    final ReceiptFooterSettings footer = ReceiptFooterSettings.defaults
        .sanitized();
    for (final String line in footer.lines) {
      expect(
        ReceiptFooterSettings.graphemeCount(line),
        lessThanOrEqualTo(ReceiptFooterSettings.maxCharsPerLine),
      );
    }
  });

  test('sanitize drops empty lines and keeps every non-empty line', () {
    final List<String> lines = ReceiptFooterSettings.sanitizeLines(<String>[
      '  one  ',
      '',
      'two',
      'three',
      'four',
      'five',
      'six',
      'seven',
    ]);
    expect(lines, <String>[
      'one',
      'two',
      'three',
      'four',
      'five',
      'six',
      'seven',
    ]);
  });

  test('truncateGraphemes cuts by character not UTF-16 code unit', () {
    final String urdu = 'شکایت' * 20;
    final String cut = ReceiptFooterSettings.truncateGraphemes(
      urdu,
      ReceiptFooterSettings.maxCharsPerLine,
    );
    expect(
      ReceiptFooterSettings.graphemeCount(cut),
      ReceiptFooterSettings.maxCharsPerLine,
    );
  });

  test('fromStorage falls back to defaults when text is empty', () {
    final ReceiptFooterSettings footer = ReceiptFooterSettings.fromStorage(
      text: '   ',
      fontSizeRaw: '99',
      lineHeightRaw: '0.2',
    );
    expect(footer.lines, ReceiptFooterSettings.defaultLines);
    expect(footer.fontSize, ReceiptFooterSettings.maxFontSize);
    expect(footer.lineHeight, ReceiptFooterSettings.minLineHeight);
  });

  test('input formatter allows more lines and clips a long line', () {
    const ReceiptFooterInputFormatter formatter = ReceiptFooterInputFormatter();
    final String six = List<String>.filled(6, 'ok').join('\n');
    final TextEditingValue allowed = formatter.formatEditUpdate(
      TextEditingValue(text: six),
      TextEditingValue(text: '$six\nextra'),
    );
    expect(allowed.text.split('\n').length, 7);

    final String tooLong = 'a' * (ReceiptFooterSettings.maxCharsPerLine + 8);
    final TextEditingValue trimmed = formatter.formatEditUpdate(
      TextEditingValue.empty,
      TextEditingValue(text: tooLong),
    );
    expect(trimmed.text.length, ReceiptFooterSettings.maxCharsPerLine);
  });

  test('latin phone lines are detected for LTR rendering', () {
    expect(ReceiptFooterSettings.isLatinLine('0334 3706655'), isTrue);
    expect(
      ReceiptFooterSettings.isLatinLine('کسی بھی قسم کی شکایت'),
      isFalse,
    );
  });
}
