class ReleaseNoteUpdate {
  const ReleaseNoteUpdate({required this.version, required this.notes});

  /// Short label shown after "Update ", e.g. `1.0.8`.
  final String version;
  final List<String> notes;

  String get heading => 'Update $version';
}

class AppBrand {
  static const String name = 'FuelPoint';
  static const String tagline = 'Station Control';
  static const String developer = 'RetroSoft';
  static const String version = '1.0.0.13';
  static const String versionLabel = 'v$version';

  /// Newest update first. Each block is numbered from 1.
  static const List<ReleaseNoteUpdate> releaseNoteUpdates =
      <ReleaseNoteUpdate>[
        ReleaseNoteUpdate(
          version: '1.0.13',
          notes: <String>[
            'Direct Sale Card: manual liters and rate, Unit Direct, deducts stock only',
            'Vehicle number required before Confirm',
            'LCD amount without decimal point',
            'Test mode no longer saves two transactions for one fill',
            'Manual keypad unlock for 5 seconds on Dispenser Monitor',
            'Editable Urdu receipt footer in Settings',
            'Previous Udhaar entry and customer table PDF',
            'Shift Report PDF KPI and column cleanup',
          ],
        ),
        ReleaseNoteUpdate(
          version: '1.0.12',
          notes: <String>[
            'Test sales show in ledgers with Test tag; excluded from totals',
            'Audit meter chain includes test sales so they do not flag mismatch',
            'Compact Connect and Rescan icon buttons on unit cards',
            'Account confirm dialog: Cash and Account fields plus Print',
          ],
        ),
        ReleaseNoteUpdate(
          version: '1.0.11',
          notes: <String>[
            'Dynamic Cash / Account split on payment overlay',
            'Pending Account banner until bank transfer is confirmed',
            'ESP auto-reconnect; Connect and Rescan on Sale unit cards',
            'Helpers stay assigned after app resume',
            'Remove Rs. and Ltr from table cells',
            'Shift Report PDF with all sale columns; save PDF directly',
            'Test sale Token# increment and test toggle fix',
          ],
        ),
        ReleaseNoteUpdate(
          version: '1.0.9',
          notes: <String>[
            'Recover missing ESP sales from Token# log',
            'Auto-save sale on hang-up; Confirm updates payment',
            'Cash and Account split columns',
            'Token# pill on unit cards',
            'Test transaction toggle (not counted as sale)',
            'Shift volume and amount KPI on Sale Screen',
            'ESP Wi-Fi hold to stop flicker disconnects',
            'Release notes grouped by update with 5-line scroll',
          ],
        ),
        ReleaseNoteUpdate(
          version: '1.0.8',
          notes: <String>[
            'Tenda WiFi, ESP and FDX Board connection alerts',
            'No LIVE Shift lock on Sale Screen',
            'Shift Transaction Audit in Sale Ledger',
            'Rate change color bands in Sale Ledger',
            'Meter mismatch notice',
            'Toggle Show/Hide Receipt Preview in Settings',
            'Toggle Show/Hide Recent Sale Edit in Settings',
            'Customer ID auto-fill on payment',
            'Amounts shown as whole rupees',
          ],
        ),
        ReleaseNoteUpdate(
          version: '1.0.7',
          notes: <String>[
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
          ],
        ),
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
