class AppBrand {
  static const String name = 'FuelPoint';
  static const String tagline = 'Station Control';
  static const String developer = 'RetroSoft';
}

class FdxDefaults {
  static const String defaultIp = '192.168.5.1';
  static const int defaultPort = 9876;
  static const Duration connectTimeout = Duration(seconds: 5);
  static const Duration scanTimeout = Duration(milliseconds: 800);
  static const int maxLogLines = 400;

  static const List<int> scanPorts = <int>[
    9876,
    8080,
    23,
    8888,
    80,
    4001,
    5000,
    8000,
    9000,
    1883,
  ];

  static const String boardSsidPrefix = 'FDX-ALPHA';
}

/// Office-router bridge (ESP32-2). Separate from the dispenser AP defaults.
class Esp32BridgeDefaults {
  static const String defaultIp = '192.168.100.253';
  static const int defaultPort = 9877;
}
