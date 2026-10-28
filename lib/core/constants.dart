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
  static const String version = '1.0.0.29';
  static const String versionLabel = 'v$version';

  /// Newest update first. Each block is numbered from 1.
  static const List<ReleaseNoteUpdate> releaseNoteUpdates =
      <ReleaseNoteUpdate>[
        ReleaseNoteUpdate(
          version: '1.0.29',
          notes: <String>[
            'Print retries receipt capture so a blank snapshot does not fail',
            'Tall receipts scale down so they still print',
          ],
        ),
        ReleaseNoteUpdate(
          version: '1.0.28',
          notes: <String>[
            'Print captures receipts off-screen so the full slip prints',
            'Sale and Udhaar settlement slips no longer crash while printing',
            'Customer and station copies print as separate jobs',
          ],
        ),
        ReleaseNoteUpdate(
          version: '1.0.27',
          notes: <String>[
            'Webcam capture of Bank / EasyPaisa transfer proof after Confirm',
            'Add Proof on the pending Account banner',
            'Udhaar Settle Bill can attach transfer proof',
            'A screenshot slip prints when proof is attached',
            'Continue without a camera if no webcam is plugged in',
          ],
        ),
        ReleaseNoteUpdate(
          version: '1.0.26',
          notes: <String>[
            'Print and Confirm light up ready when fueling ends',
            'Tap stays off until vehicle number is filled',
            'Udhaar also needs a matched customer before Confirm',
            'Same Cash / Udhaar / Account tender panel on Sale and Ledger Edit',
            'Pump speaker slider can go above 100 for louder pump talk',
          ],
        ),
        ReleaseNoteUpdate(
          version: '1.0.25',
          notes: <String>[
            'Udhaar Confirm uses Cash Now plus remainder, like Account',
            'Expected cash includes Cash Now Account and Cash Now Udhaar',
            'Shift screens and Shift Report PDF show Cash Now Udhaar',
            'Cash only Sales excludes Account remainder and both Cash Now amounts',
            'Shift Audit treats a 0.1 L gap or less as a match',
          ],
        ),
        ReleaseNoteUpdate(
          version: '1.0.24',
          notes: <String>[
            'Intercom noise cut pulls hiss down without making it louder',
            'Office speaker ducks flat hiss and keeps spoken words',
            'Pump speaker tames loud peaks so talk is less harsh',
          ],
        ),
        ReleaseNoteUpdate(
          version: '1.0.23',
          notes: <String>[
            'Intercom Settings split into Pump and Office cards',
            'Pump has its own microphone, speaker, and noise cut',
            'Office has its own microphone, speaker, and noise cut',
          ],
        ),
        ReleaseNoteUpdate(
          version: '1.0.22',
          notes: <String>[
            'Intercom levels in Settings: pump speaker, station speaker, mic, and noise cut',
            'Speaker test plays a tone or WAV files on a chosen pump',
            'Udhaar Settle Bill: Cash or Account (Bank / EasyPaisa) with Cash Now split',
            'Settlement receipt shows Cash Now and Bank/EasyPaisa amounts',
            'Account overpay shows Baqaya Dene hain on confirm and pending transfer',
          ],
        ),
        ReleaseNoteUpdate(
          version: '1.0.21',
          notes: <String>[
            'Expected cash is Cash only Sales + Udhaar Recovery (Cash) + Cash Now',
            'Cash only Sales is Total Sale minus Udhaar Issued minus Account Payments',
            'Shift KPIs split Account Payments and Udhaar Recovery by cash and account',
            'Total Sale follows Readings Amount (net volume × rate)',
            'Shift Report PDF uses the same cash figures',
          ],
        ),
        ReleaseNoteUpdate(
          version: '1.0.20',
          notes: <String>[
            'Sales Ledger opens the last 30 days without crashing',
            'Page older All Transactions in 30-day blocks',
            'Rate-Wise table: unit, rate, meters, dispensed, test, net, amount',
            'Shift totals use meter net so lost tickets still count',
            'Older closed shifts show the correct Expected cash',
          ],
        ),
        ReleaseNoteUpdate(
          version: '1.0.19',
          notes: <String>[
            'Long ledger and shift PDFs no longer hang while generating',
            'Sales and Purchase ledger PDFs on A4 landscape',
            'Shift Report PDF paginates tables without a title on every page',
            'Customer directory and ledger PDFs use the same report layout',
          ],
        ),
        ReleaseNoteUpdate(
          version: '1.0.18',
          notes: <String>[
            'PDFs save under Documents/Exported_Reports and open without crash',
            'Owner can enroll up to 10 fingerprints',
            'Generate PDF on shift handover and shift summary',
            'Udhaar settlement no longer crashes before print',
          ],
        ),
        ReleaseNoteUpdate(
          version: '1.0.15',
          notes: <String>[
            'Receipt preview for unit slips, pending account, second copy, and Udhaar settlement',
            'Udhaar settlement thermal receipt (2 copies)',
            'Shift Report PDF: rate bands, test liters, and Direct Sales',
            'Confirm and Print highlight when a fill is ready',
            'Zero-volume abort notice on the unit card',
          ],
        ),
        ReleaseNoteUpdate(
          version: '1.0.14',
          notes: <String>[
            'Push-to-talk intercom on Sale unit cards',
            'ESP last-10 Token# recover dialog',
            'Fingerprint login and enrollment',
            'Per-unit ESP host and port from Sale screen',
          ],
        ),
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
