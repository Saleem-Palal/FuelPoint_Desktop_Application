import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/dispensr_theme.dart';
import '../../../utils/fuel_formatter.dart';

class InitialDipResult {
  const InitialDipResult({
    required this.liters,
    required this.rate,
    required this.description,
  });

  final double liters;
  final double rate;
  final String description;
}

Future<InitialDipResult?> showInitialDipModal(BuildContext context) {
  return showDialog<InitialDipResult>(
    context: context,
    builder: (BuildContext context) {
      return const InitialDipModalDialog();
    },
  );
}

class InitialDipModalDialog extends StatefulWidget {
  const InitialDipModalDialog({super.key});

  @override
  State<InitialDipModalDialog> createState() => _InitialDipModalDialogState();
}

class _InitialDipModalDialogState extends State<InitialDipModalDialog> {
  static final TextInputFormatter _wholeFormatter =
      FilteringTextInputFormatter.digitsOnly;
  static final FilteringTextInputFormatter _rateFormatter =
      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,8}'));

  static const String _defaultNote =
      'Initial tank calibration upon app setup';

  final TextEditingController _litersController = TextEditingController();
  final TextEditingController _rateController = TextEditingController();
  final TextEditingController _noteController = TextEditingController(
    text: _defaultNote,
  );

  @override
  void initState() {
    super.initState();
    _litersController.addListener(_onChanged);
    _rateController.addListener(_onChanged);
  }

  @override
  void dispose() {
    _litersController.removeListener(_onChanged);
    _rateController.removeListener(_onChanged);
    _litersController.dispose();
    _rateController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  double _parse(TextEditingController controller) {
    return double.tryParse(controller.text.trim()) ?? 0;
  }

  double get _liters => _parse(_litersController);
  double get _rate => _parse(_rateController);
  double get _amount => _liters * _rate;

  bool get _canSave => _liters > 0 && _rate > 0;

  void _save() {
    if (!_canSave) {
      return;
    }
    final String note = _noteController.text.trim();
    Navigator.of(context).pop(
      InitialDipResult(
        liters: _liters,
        rate: _rate,
        description: note.isEmpty ? _defaultNote : note,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);

    return AlertDialog(
      backgroundColor: tokens.card,
      surfaceTintColor: tokens.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius20),
        side: BorderSide(color: tokens.line),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Row(
        children: <Widget>[
          Icon(Icons.water_drop_outlined, size: 20, color: tokens.coral),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Initial Dip Setup',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: tokens.ink,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Calibrate the tank from a measured dip. This becomes the available stock baseline.',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w400,
                fontSize: 12,
                height: 1.4,
                color: tokens.inkMuted,
              ),
            ),
            const SizedBox(height: 14),
            _DipField(
              label: 'Measured Physical Liters',
              controller: _litersController,
              hint: '0',
              suffix: 'Ltr',
              formatter: _wholeFormatter,
              autofocus: true,
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
            ),
            const SizedBox(height: 12),
            _DipField(
              label: 'Rate Per Liter (PKR)',
              controller: _rateController,
              hint: '0',
              suffix: 'Rs / Ltr',
              formatter: _rateFormatter,
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
            ),
            const SizedBox(height: 12),
            _DipAmountPreview(amount: _amount),
            const SizedBox(height: 12),
            _DipField(
              label: 'Description / Note',
              controller: _noteController,
              hint: _defaultNote,
              maxLines: 3,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: DsPillButton(
                label: 'Cancel',
                variant: DsPillVariant.outline,
                compact: true,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DsPillButton(
                label: 'Save Calibration',
                variant: DsPillVariant.coral,
                compact: true,
                icon: Icons.check,
                onPressed: _canSave ? _save : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DipAmountPreview extends StatelessWidget {
  const _DipAmountPreview({required this.amount});

  final double amount;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Total Amount (PKR)',
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w600,
            fontSize: 12,
            color: tokens.inkMuted,
          ),
        ),
        const SizedBox(height: 6),
        InputDecorator(
          decoration: InputDecoration(
            filled: true,
            fillColor: tokens.line.withValues(alpha: 0.35),
            suffixText: 'Rs',
            suffixStyle: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w500,
              fontSize: 12,
              color: tokens.inkMuted,
            ),
          ),
          child: Text(
            FuelFormatter.formatCurrency(amount),
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: tokens.inkMuted,
            ),
          ),
        ),
      ],
    );
  }
}

class _DipField extends StatelessWidget {
  const _DipField({
    required this.label,
    required this.controller,
    required this.hint,
    this.suffix,
    this.formatter,
    this.maxLines = 1,
    this.autofocus = false,
    this.textInputAction,
    this.onFieldSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final String? suffix;
  final TextInputFormatter? formatter;
  final int maxLines;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;

  List<TextInputFormatter>? get _formatters {
    final TextInputFormatter? active = formatter;
    if (active == null) {
      return null;
    }
    return <TextInputFormatter>[active];
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w600,
            fontSize: 12,
            color: tokens.inkMuted,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          autofocus: autofocus,
          maxLines: maxLines,
          keyboardType: maxLines == 1
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.multiline,
          inputFormatters: _formatters,
          textInputAction: textInputAction,
          onFieldSubmitted: onFieldSubmitted,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: tokens.ink,
          ),
          decoration: InputDecoration(
            isDense: false,
            hintText: hint,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 16,
              horizontal: 16,
            ),
            suffixText: suffix,
            suffixStyle: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w500,
              fontSize: 12,
              color: tokens.inkMuted,
            ),
          ),
        ),
      ],
    );
  }
}
