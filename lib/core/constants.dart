class AppBrand {
  static const String name = 'FuelPoint';
  static const String tagline = 'Station Control';
  static const String developer = 'RetroSoft';
  static const String version = '1.0.0.7';
  static const String versionLabel = 'v$version';

  static const List<String> releaseNotes = <String>[
    'Shift Management Cashier Issue & Workflow',
    'Timer for Auto Lock Owner Access',
    'LCD Font Size Increase',
    'Toggle Show/Hide 5th Unit in Settings',
    'Shift Wise Data Filter in Sale Ledger',
    'Sale Receipt Cashier Name Fix. And helper name.',
    'Remove Save as Draft from Purchase Screen',
    'Purchase Calculations fix',
    'Add Edit button in purchase Screen',
    'Remove Purchase Details from Reconciliation Sidebar and Amount should not be in decimal',
    'Remove Initial Dip',
    'Low Stock Threshold Notification Alert',
    'Owner Access Lock applies to all screens except Sale and Customers (Udhaar)',
    'Simulation demo removed from the release build',
  ];
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
