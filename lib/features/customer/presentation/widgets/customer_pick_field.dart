import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/dispensr_theme.dart';

/// Circular customer-ID badge plus name, matching the sale confirm sheet.
class CustomerPickField extends StatelessWidget {
  const CustomerPickField({
    super.key,
    required this.idController,
    required this.nameController,
    this.onSubmitted,
    this.onTap,
  });

  final TextEditingController idController;
  final TextEditingController nameController;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;

  static const double fieldHeight = 36;
  static const double controlRadius = 10;
  static const double idBadgeSize = 28;

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final String name = nameController.text;
    return Container(
      height: fieldHeight,
      padding: const EdgeInsets.fromLTRB(4, 0, 10, 0),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(controlRadius),
        border: Border.all(color: tokens.line),
      ),
      child: Row(
        children: <Widget>[
          _CustomerIdBadge(
            tokens: tokens,
            controller: idController,
            onTap: onTap,
            onSubmitted: onSubmitted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  name.isEmpty ? 'Customer name' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: name.isEmpty
                        ? tokens.inkMuted.withValues(alpha: 0.72)
                        : tokens.ink,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerIdBadge extends StatelessWidget {
  const _CustomerIdBadge({
    required this.tokens,
    required this.controller,
    required this.onTap,
    required this.onSubmitted,
  });

  final DispensrTokens tokens;
  final TextEditingController controller;
  final VoidCallback? onTap;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: CustomerPickField.idBadgeSize,
      height: CustomerPickField.idBadgeSize,
      child: Material(
        color: tokens.ink,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: Align(
          alignment: Alignment.center,
          child: TextField(
            controller: controller,
            onTap: onTap,
            maxLength: 4,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            textAlign: TextAlign.center,
            textAlignVertical: TextAlignVertical.center,
            textInputAction: TextInputAction.done,
            onSubmitted: onSubmitted,
            scrollPadding: EdgeInsets.zero,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w700,
              fontSize: 11,
              height: 1,
              leadingDistribution: TextLeadingDistribution.even,
              color: tokens.card,
            ),
            strutStyle: const StrutStyle(
              fontFamily: 'Roboto',
              fontSize: 11,
              height: 1,
              forceStrutHeight: true,
              leadingDistribution: TextLeadingDistribution.even,
            ),
            cursorColor: tokens.card,
            decoration: InputDecoration(
              isCollapsed: true,
              isDense: true,
              filled: false,
              counterText: '',
              hintText: 'ID',
              hintStyle: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w600,
                fontSize: 9,
                height: 1,
                leadingDistribution: TextLeadingDistribution.even,
                color: tokens.card.withValues(alpha: 0.55),
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ),
    );
  }
}
