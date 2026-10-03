import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fuel_dispenser/features/station/data/dispenser_socket_manager.dart';
import 'package:fuel_dispenser/features/station/domain/dispenser_models.dart';
import 'package:fuel_dispenser/features/station/domain/esp_token_log.dart';

SaleTransaction _sale({
  required int tokenNo,
  required int unitId,
  required DateTime at,
  required double liters,
  String espTxId = '',
  int meterCount = 100,
}) {
  return SaleTransaction(
    tokenNo: tokenNo,
    unitId: unitId,
    fuelType: kDieselFuelType,
    amountPkr: 500,
    volumeLiters: liters,
    rate: 267,
    meterCount: meterCount,
    timestamp: at,
    espTxId: espTxId,
  );
}

EspTokenLogRow _espRow({
  required int token,
  required int unitId,
  required DateTime at,
  required double liters,
  double meter = 100,
}) {
  return EspTokenLogRow(
    token: token,
    unitId: unitId,
    amountPkr: 500,
    volumeLiters: liters,
    rate: 267,
    meterCount: meter,
    at: at,
  );
}

void main() {
  test('Token# is unit times 100000 plus sequence', () {
    expect(tokenIdFor(unitId: 1, sequence: 1), 100001);
    expect(tokenIdFor(unitId: 4, sequence: 12), 400012);
    expect(sequenceFromToken(200007, 2), 7);
  });

  test('Offline banner waits 4 seconds before marking the ESP down', () {
    expect(StationNetDefaults.offlineDebounce, const Duration(seconds: 4));
    expect(
      DispenserSocketManager.offlineDebounce,
      StationNetDefaults.offlineDebounce,
    );
  });

  test('WS retry backoff is 1s then doubles up to 30s', () {
    expect(unitWsRetryBackoff(1), const Duration(seconds: 1));
    expect(unitWsRetryBackoff(2), const Duration(seconds: 2));
    expect(unitWsRetryBackoff(5), const Duration(seconds: 16));
    expect(unitWsRetryBackoff(6), const Duration(seconds: 30));
    expect(unitWsRetryBackoff(9), const Duration(seconds: 30));
  });

  test('generation bump without clearing connecting blocks retry', () {
    expect(
      unitWsCanRetry(wanted: true, hasLiveSocket: false, connecting: true),
      isFalse,
    );
  });

  test('after closeSocket clears connecting, wanted retry is allowed', () {
    expect(
      unitWsCanRetry(wanted: true, hasLiveSocket: false, connecting: false),
      isTrue,
    );
  });

  test('live socket or unwanted unit does not auto-retry', () {
    expect(
      unitWsCanRetry(wanted: true, hasLiveSocket: true, connecting: false),
      isFalse,
    );
    expect(
      unitWsCanRetry(wanted: false, hasLiveSocket: false, connecting: false),
      isFalse,
    );
  });

  test('SYNC_LOG parses Token# rows for that unit', () {
    final String raw = jsonEncode(<String, Object>{
      'cmd': 'SYNC_LOG',
      'unit': 2,
      'rows': <Map<String, Object>>[
        <String, Object>{
          'token': 200003,
          'unit': 2,
          'at': '2026-09-14T22:01:00.000',
          'amount': 6619,
          'liters': 20.12,
          'rate': 330.95,
          'meter': 78.74,
          'synced': false,
        },
      ],
    });
    final List<EspTokenLogRow> rows = EspTokenLogRow.tryParseSyncLog(raw);
    expect(rows, hasLength(1));
    expect(rows.single.token, 200003);
    expect(rows.single.unitId, 2);
    expect(rows.single.volumeLiters, closeTo(20.12, 0.0001));
    expect(rows.single.amountPkr, 6619);
    expect(rows.single.meterCount, closeTo(78.74, 0.0001));
  });

  test('QUEUE_REPLAY leftover tx_id is not a Token# recover row', () {
    final String raw = jsonEncode(<String, Object>{
      'cmd': 'QUEUE_REPLAY',
      'tx_id': 'ECC9FFFD1370-4',
      'unit': 1,
      'kind': 'Incomplete/PowerLost',
      'telemetry': <String, Object>{
        'amount': 500,
        'liters': 1.87,
        'rate': 267,
        'meter': 560695.06,
      },
    });
    expect(EspTokenLogRow.tryParseSyncLog(raw), isEmpty);
    final PendingEspSale? sale = PendingEspSale.tryParse(raw);
    expect(sale, isNotNull);
    expect(sale!.txId, 'ECC9FFFD1370-4');
  });

  test('recovered saleType prints as a recovered sale', () {
    expect(
      SaleTransaction(
        tokenNo: 100099,
        unitId: 1,
        fuelType: kDieselFuelType,
        amountPkr: 500,
        volumeLiters: 1,
        rate: 267,
        meterCount: 10,
        timestamp: DateTime(2026, 9, 14, 22, 1),
        saleType: 'RECOVERED',
        notes: 'RECOVERED',
      ).isRecoveredSale,
      isTrue,
    );
  });

  group('missingEspTokenRows', () {
    final DateTime at = DateTime(2026, 9, 14, 22, 1);

    test('same Token# on a different second is still missing', () {
      final List<EspTokenLogRow> missing = missingEspTokenRows(
        espRows: <EspTokenLogRow>[
          _espRow(token: 100005, unitId: 1, at: at, liters: 12.5),
        ],
        appRows: <SaleTransaction>[
          _sale(
            tokenNo: 100005,
            unitId: 1,
            at: at.add(const Duration(seconds: 8)),
            liters: 12.5,
            espTxId: 'ECC9FFFD1370-9',
          ),
        ],
      );
      expect(missing.map((EspTokenLogRow row) => row.token), <int>[100005]);
    });

    test('same second with different liters is missing', () {
      final List<EspTokenLogRow> missing = missingEspTokenRows(
        espRows: <EspTokenLogRow>[
          _espRow(token: 100008, unitId: 1, at: at, liters: 12.5),
        ],
        appRows: <SaleTransaction>[
          _sale(
            tokenNo: 100007,
            unitId: 1,
            at: at,
            liters: 12.48,
          ),
        ],
      );
      expect(missing.map((EspTokenLogRow row) => row.token), <int>[100008]);
    });

    test(
      'toast lists only last-10 fills the unit ledger does not have',
      () {
        final DateTime older = at.subtract(const Duration(hours: 6));
        final List<EspTokenLogRow> espLastTen = <EspTokenLogRow>[
          for (int seq = 1; seq <= 10; seq += 1)
            _espRow(
              token: tokenIdFor(unitId: 1, sequence: seq),
              unitId: 1,
              at: older.add(Duration(minutes: seq)),
              liters: seq.toDouble(),
            ),
        ];
        final List<SaleTransaction> appRows = <SaleTransaction>[
          for (int seq = 1; seq <= 8; seq += 1)
            _sale(
              tokenNo: tokenIdFor(unitId: 1, sequence: seq),
              unitId: 1,
              at: older.add(Duration(minutes: seq)),
              liters: seq.toDouble(),
            ),
        ];
        final List<EspTokenLogRow> missing = missingEspTokenRows(
          espRows: espLastTen,
          appRows: appRows,
        );
        expect(missing.map((EspTokenLogRow row) => row.token).toList(), <int>[
          100009,
          100010,
        ]);
      },
    );

    test(
      'matching fill is on the ledger even when Token# and meter differ',
      () {
        final List<EspTokenLogRow> missing = missingEspTokenRows(
          espRows: <EspTokenLogRow>[
            _espRow(token: 100001, unitId: 1, at: at, liters: 9),
          ],
          appRows: <SaleTransaction>[
            _sale(
              tokenNo: 100099,
              unitId: 1,
              at: at,
              liters: 9,
            ),
          ],
        );
        expect(missing, isEmpty);
      },
    );

    test('missing hang-up is offered for recover insert', () {
      final EspTokenLogRow lost = _espRow(
        token: 300004,
        unitId: 3,
        at: at,
        liters: 8.25,
      );
      final List<EspTokenLogRow> missing = missingEspTokenRows(
        espRows: <EspTokenLogRow>[lost],
        appRows: <SaleTransaction>[
          _sale(
            tokenNo: 300003,
            unitId: 3,
            at: at.subtract(const Duration(minutes: 20)),
            liters: 4,
            espTxId: 'ECC9FFFD1370-4',
          ),
        ],
      );
      expect(missing, hasLength(1));
      expect(missing.single.token, 300004);
      expect(missing.single.volumeLiters, 8.25);
    });

    test(
      'different Token# with the same second, liters, rate, and rupees is not offered',
      () {
        final List<EspTokenLogRow> missing = missingEspTokenRows(
          espRows: <EspTokenLogRow>[
            _espRow(token: 200014, unitId: 2, at: at, liters: 12.5),
          ],
          appRows: <SaleTransaction>[
            _sale(tokenNo: 200001, unitId: 2, at: at, liters: 8),
            _sale(tokenNo: 200002, unitId: 2, at: at, liters: 12.5),
          ],
        );
        expect(missing, isEmpty);
      },
    );

    test(
      'meter hundredths do not keep a matching fill on the missing list',
      () {
        final List<EspTokenLogRow> missing = missingEspTokenRows(
          espRows: <EspTokenLogRow>[
            _espRow(
              token: 200014,
              unitId: 2,
              at: at,
              liters: 12.5,
              meter: 78.74,
            ),
          ],
          appRows: <SaleTransaction>[
            _sale(tokenNo: 200002, unitId: 2, at: at, liters: 8, meterCount: 60),
            _sale(
              tokenNo: 200003,
              unitId: 2,
              at: at,
              liters: 12.5,
              meterCount: 78,
            ),
          ],
        );
        expect(missing, isEmpty);
      },
    );

    test('leftover ESP_TX_ID on another sale does not hide a new Token#', () {
      final List<EspTokenLogRow> missing = missingEspTokenRows(
        espRows: <EspTokenLogRow>[
          _espRow(token: 100006, unitId: 1, at: at, liters: 9),
        ],
        appRows: <SaleTransaction>[
          _sale(
            tokenNo: 100005,
            unitId: 1,
            at: at.subtract(const Duration(minutes: 10)),
            liters: 3,
            espTxId: 'ECC9FFFD1370-4',
          ),
        ],
      );
      expect(missing.map((EspTokenLogRow row) => row.token), <int>[100006]);
    });
  });
}
