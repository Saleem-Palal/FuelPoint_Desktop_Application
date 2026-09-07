import 'package:flutter/material.dart';

class FuelNozzleGraphic extends StatelessWidget {
  const FuelNozzleGraphic({
    super.key,
    required this.isDispensing,
    required this.isOffline,
  });

  final bool isDispensing;
  final bool isOffline;

  // --- Tweak these ---
  static const double width = 40;
  static const double height = 160;

  /// Increase to move the nozzle in that direction (pixels).
  static const double up = 0;
  static const double down = 0;
  static const double left = 2;
  static const double right = 0;
  // -------------------

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

    Widget image = Image.asset(
      asset,
      width: width,
      height: height,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
    );

    if (isOffline) {
      image = ColorFiltered(
        colorFilter: _offlineFilter,
        child: Opacity(opacity: 0.35, child: image),
      );
    }

    return image;
  }
}
