import 'package:flutter/material.dart';

class FuelNozzleGraphic extends StatelessWidget {
  const FuelNozzleGraphic({
    super.key,
    required this.isDispensing,
    required this.isOffline,
  });

  final bool isDispensing;
  final bool isOffline;

  static const double slotWidth = 44;
  static const double slotHeight = 160;

  static const ColorFilter _offlineFilter = ColorFilter.matrix(<double>[
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]);

  @override
  Widget build(BuildContext context) {
    final String asset = isDispensing
        ? 'assets/images/nozzle-dispensing.png'
        : 'assets/images/nozzle-idle.png';

    final Widget image = Image.asset(
      asset,
      width: slotWidth,
      height: slotHeight,
      fit: BoxFit.fitHeight,
      alignment: Alignment.bottomLeft,
      filterQuality: FilterQuality.medium,
    );

    Widget nozzle = isOffline
        ? ColorFiltered(
            colorFilter: _offlineFilter,
            child: Opacity(opacity: 0.35, child: image),
          )
        : image;

    if (isDispensing && !isOffline) {
      nozzle = Transform.translate(offset: const Offset(3, -8), child: nozzle);
    }

    return SizedBox(width: slotWidth, height: slotHeight, child: nozzle);
  }
}
