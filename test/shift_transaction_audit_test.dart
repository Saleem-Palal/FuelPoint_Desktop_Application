import 'package:flutter_test/flutter_test.dart';

import 'package:fuel_dispenser/features/shift/domain/shift_models.dart';
import 'package:fuel_dispenser/features/station/domain/dispenser_models.dart';
import 'package:fuel_dispenser/features/station/domain/ledger_rate_bands.dart';
import 'package:fuel_dispenser/features/station/domain/shift_ledger_models.dart';
import 'package:fuel_dispenser/features/station/domain/shift_transaction_audit.dart';

SaleTransaction _sale({
  required int tokenNo,
  required double liters,
  required double opening,
  required double closing,
  int unitId = 1,
  DateTime? timestamp,
  double rate = 256.32,
  bool isTest = false,
}) {
  return SaleTransaction(
    tokenNo: tokenNo,
    unitId: unitId,
    fuelType: kDieselFuelType,
    amountPkr: 100,
    volumeLiters: liters,
    rate: rate,
    meterCount: closing.truncate(),
    timestamp: timestamp ?? DateTime(2026, 9, 8, 10),
    shiftId: 'SHF-1',
    openingMeter: opening,
    closingMeter: closing,
    isTest: isTest,
  );
}

ShiftLedgerSummary _summary({
  required OperatorShiftStatus status,
  Map<int, double> openingMeters = const <int, double>{1: 80},
  Map<int, double> closingMeters = const <int, double>{1: 120},
}) {
  return ShiftLedgerSummary(
    shiftId: 'SHF-1',
    operatorId: 'mgr-1',
    operatorName: 'Saleem',
    role: OperatorRole.operator,
    startTime: DateTime(2026, 9, 8, 8),
    endTime: status == OperatorShiftStatus.open
        ? null
        : DateTime(2026, 9, 8, 20),
    status: status,
    totalTransactions: 4,
    totalShiftPkr: 400,
    totalShiftLiters: 40,
    openingMeters: openingMeters,
    closingMeters: closingMeters,
  );
}

void main() {
  group('shift transaction audit', () {
    test('passes a clean chronological chain', () {
      final ShiftTransactionAudit audit = auditShiftTransactions(
        summary: _summary(status: OperatorShiftStatus.closed),
        rows: <SaleTransaction>[
          _sale(
            tokenNo: 4,
            liters: 10,
            opening: 110,
            closing: 120,
            timestamp: DateTime(2026, 9, 8, 13),
          ),
          _sale(
            tokenNo: 3,
            liters: 10,
            opening: 100,
            closing: 110,
            timestamp: DateTime(2026, 9, 8, 12),
          ),
          _sale(
            tokenNo: 2,
            liters: 10,
            opening: 90,
            closing: 100,
            timestamp: DateTime(2026, 9, 8, 11),
          ),
          _sale(
            tokenNo: 1,
            liters: 10,
            opening: 80,
            closing: 90,
            timestamp: DateTime(2026, 9, 8, 10),
          ),
        ],
      );

      expect(audit.ok, isTrue);
      expect(audit.units.single.saleLiters, 40);
      expect(audit.units.single.shiftVolumeLiters, 40);
    });

    test('flags liters that do not match closing minus opening', () {
      final ShiftTransactionAudit audit = auditShiftTransactions(
        summary: _summary(
          status: OperatorShiftStatus.closed,
          openingMeters: const <int, double>{1: 80},
          closingMeters: const <int, double>{1: 90},
        ),
        rows: <SaleTransaction>[
          _sale(tokenNo: 1, liters: 5, opening: 80, closing: 90),
        ],
      );

      expect(audit.ok, isFalse);
      expect(
        audit.units.single.findings.map((ShiftAuditFinding row) => row.kind),
        contains(ShiftAuditKind.litersVsMeter),
      );
    });

    test('flags a chain gap between consecutive sales', () {
      final ShiftTransactionAudit audit = auditShiftTransactions(
        summary: _summary(
          status: OperatorShiftStatus.closed,
          openingMeters: const <int, double>{1: 80},
          closingMeters: const <int, double>{1: 110},
        ),
        rows: <SaleTransaction>[
          _sale(
            tokenNo: 1,
            liters: 10,
            opening: 80,
            closing: 90,
            timestamp: DateTime(2026, 9, 8, 10),
          ),
          _sale(
            tokenNo: 2,
            liters: 10,
            opening: 90,
            closing: 100,
            timestamp: DateTime(2026, 9, 8, 11),
          ),
          _sale(
            tokenNo: 3,
            liters: 10,
            opening: 100,
            closing: 110,
            timestamp: DateTime(2026, 9, 8, 12),
          ),
          _sale(
            tokenNo: 4,
            liters: 10,
            opening: 111,
            closing: 121,
            timestamp: DateTime(2026, 9, 8, 13),
          ),
        ],
      );

      expect(
        audit.units.single.findings
            .where(
              (ShiftAuditFinding row) => row.kind == ShiftAuditKind.chainGap,
            )
            .length,
        1,
      );
      expect(
        audit.units.single.findings
            .firstWhere(
              (ShiftAuditFinding row) => row.kind == ShiftAuditKind.chainGap,
            )
            .tokenNo,
        4,
      );
    });

    test('does not compare shift volume while the shift is live', () {
      final ShiftLedgerSummary live = _summary(
        status: OperatorShiftStatus.open,
        closingMeters: const <int, double>{},
      );
      expect(shiftVolumeLitersFor(summary: live, unitId: 1), isNull);

      final ShiftTransactionAudit audit = auditShiftTransactions(
        summary: live,
        rows: <SaleTransaction>[
          _sale(tokenNo: 1, liters: 10, opening: 80, closing: 90),
        ],
      );
      expect(
        audit.units.single.findings.map((ShiftAuditFinding row) => row.kind),
        isNot(contains(ShiftAuditKind.shiftVolume)),
      );
      expect(
        audit.units.single.findings.map((ShiftAuditFinding row) => row.kind),
        isNot(contains(ShiftAuditKind.lastClosing)),
      );
    });

    test(
      'live closing uses the latest sale meter and still marks continued',
      () {
        final ShiftLedgerSummary live = _summary(
          status: OperatorShiftStatus.open,
          closingMeters: const <int, double>{},
        );
        final List<SaleTransaction> sales = <SaleTransaction>[
          _sale(
            tokenNo: 1,
            liters: 10,
            opening: 80,
            closing: 90,
            timestamp: DateTime(2026, 9, 8, 10),
          ),
          _sale(
            tokenNo: 2,
            liters: 10,
            opening: 90,
            closing: 100,
            timestamp: DateTime(2026, 9, 8, 11),
          ),
        ];
        expect(
          resolvedShiftClosingMeter(summary: live, unitId: 1, sales: sales),
          100,
        );
        expect(
          shiftVolumeLitersFor(summary: live, unitId: 1, closingMeter: 100),
          20,
        );
        expect(shiftVolumeRemark(shiftVolume: 20, saleLiters: 20), 'Match');
        expect(shiftVolumeRemark(shiftVolume: 20, saleLiters: 15), 'Mismatch');
      },
    );

    test('keeps unit chains separate', () {
      final ShiftTransactionAudit audit = auditShiftTransactions(
        summary: _summary(
          status: OperatorShiftStatus.closed,
          openingMeters: const <int, double>{1: 80, 2: 200},
          closingMeters: const <int, double>{1: 90, 2: 210},
        ),
        rows: <SaleTransaction>[
          _sale(tokenNo: 1, liters: 10, opening: 80, closing: 90, unitId: 1),
          _sale(tokenNo: 2, liters: 10, opening: 200, closing: 210, unitId: 2),
        ],
      );

      expect(audit.ok, isTrue);
      expect(audit.units.length, 2);
    });

    test(
      'counts test opening/closing in the chain and does not false-mismatch',
      () {
        final ShiftTransactionAudit audit = auditShiftTransactions(
          summary: _summary(
            status: OperatorShiftStatus.closed,
            openingMeters: const <int, double>{1: 80},
            closingMeters: const <int, double>{1: 105},
          ),
          rows: <SaleTransaction>[
            _sale(
              tokenNo: 1,
              liters: 10,
              opening: 80,
              closing: 90,
              timestamp: DateTime(2026, 9, 8, 10),
            ),
            _sale(
              tokenNo: 2,
              liters: 5,
              opening: 90,
              closing: 95,
              timestamp: DateTime(2026, 9, 8, 11),
              isTest: true,
            ),
            _sale(
              tokenNo: 3,
              liters: 10,
              opening: 95,
              closing: 105,
              timestamp: DateTime(2026, 9, 8, 12),
            ),
          ],
        );

        expect(audit.ok, isTrue);
        expect(audit.units.single.testFillCount, 1);
        expect(audit.units.single.saleLiters, 20);
        expect(audit.units.single.testLiters, 5);
        expect(audit.units.single.shiftVolumeLiters, 25);
        expect(
          shiftVolumeRemark(shiftVolume: 25, saleLiters: 20, testLiters: 5),
          'Match',
        );
        expect(shiftVolumeRemark(shiftVolume: 25, saleLiters: 20), 'Mismatch');
      },
    );

    test('live closing follows the latest test fill', () {
      final ShiftLedgerSummary live = _summary(
        status: OperatorShiftStatus.open,
        closingMeters: const <int, double>{},
      );
      final List<SaleTransaction> sales = <SaleTransaction>[
        _sale(
          tokenNo: 1,
          liters: 10,
          opening: 80,
          closing: 90,
          timestamp: DateTime(2026, 9, 8, 10),
        ),
        _sale(
          tokenNo: 2,
          liters: 5,
          opening: 90,
          closing: 95,
          timestamp: DateTime(2026, 9, 8, 11),
          isTest: true,
        ),
      ];
      expect(
        resolvedShiftClosingMeter(summary: live, unitId: 1, sales: sales),
        95,
      );
      expect(
        shiftVolumeLitersFor(summary: live, unitId: 1, closingMeter: 95),
        15,
      );
      expect(
        shiftVolumeRemark(shiftVolume: 15, saleLiters: 10, testLiters: 5),
        'Match',
      );
    });
  });

  group('rate bands', () {
    test('assigns no bands when every displayed rate matches', () {
      final Map<String, int> bands = rateBandIndexes(<SaleTransaction>[
        _sale(tokenNo: 1, liters: 1, opening: 1, closing: 2, rate: 256.329),
        _sale(tokenNo: 2, liters: 1, opening: 2, closing: 3, rate: 256.321),
      ]);
      expect(bands, isEmpty);
    });

    test(
      'gives distinct rates different indexes and shares truncated keys',
      () {
        final Map<String, int> bands = rateBandIndexes(<SaleTransaction>[
          _sale(tokenNo: 1, liters: 1, opening: 1, closing: 2, rate: 256.32),
          _sale(tokenNo: 2, liters: 1, opening: 2, closing: 3, rate: 260.10),
          _sale(tokenNo: 3, liters: 1, opening: 3, closing: 4, rate: 256.329),
        ]);
        expect(bands.length, 2);
        expect(
          bands[displayedRateKey(256.32)],
          bands[displayedRateKey(256.329)],
        );
        expect(
          bands[displayedRateKey(256.32)],
          isNot(bands[displayedRateKey(260.10)]),
        );
      },
    );
  });
}
