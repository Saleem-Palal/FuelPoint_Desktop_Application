import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:fuel_dispenser/features/station/data/receipt_proof_raster.dart';
import 'package:fuel_dispenser/features/station/data/receipt_proof_storage.dart';
import 'package:fuel_dispenser/features/station/data/windows_escpos_spooler.dart';
import 'package:fuel_dispenser/features/station/domain/dispenser_models.dart';
import 'package:fuel_dispenser/features/station/domain/money_format.dart';

void main() {
  test('proof file names use token and timestamp', () {
    expect(
      ReceiptProofStorage.fileName(
        tokenNo: 100001,
        at: DateTime(2026, 10, 22, 18, 5, 9),
      ),
      'proof_100001_20261022_180509.jpg',
    );
  });

  test('confirmed digital sales still need a proof until a path is stored', () {
    final SaleTransaction txn = SaleTransaction(
      tokenNo: 200002,
      unitId: 1,
      fuelType: kDieselFuelType,
      amountPkr: 1000,
      volumeLiters: 4,
      rate: 250,
      meterCount: 1,
      timestamp: DateTime(2026, 10, 22),
      payment: PaymentMethod.easyPaisa,
      accountAmount: 1000,
    );
    expect(txn.needsAccountProof, isTrue);
    expect(
      txn
          .copyWith(proofImagePath: r'C:\FuelPointData\receipt_proofs\a.jpg')
          .needsAccountProof,
      isFalse,
    );
  });

  test('JPEG proof is resized to 80mm width and packed as GS v 0', () {
    final img.Image source = img.Image(width: 800, height: 200);
    img.fill(source, color: img.ColorRgb8(32, 32, 32));
    final Uint8List jpeg = Uint8List.fromList(
      img.encodeJpg(source, quality: 80),
    );
    final ({int width, int height, Uint8List rgba}) prepared =
        ReceiptProofRaster.prepareRgba(
          jpeg,
          maxWidth: ReceiptProofRaster.dots80mm,
        );
    expect(prepared.width, ReceiptProofRaster.dots80mm);
    expect(prepared.height, 144);
    final Uint8List raster = packProofJpegRaster(jpeg);
    expect(raster[0], 0x1D);
    expect(raster[1], 0x76);
    expect(raster[2], 0x30);

    final Uint8List slip = mergeEscPosSlip(
      receiptBody: raster,
      proofBody: raster,
      feedLines: 3,
    );
    expect(slip[0], 0x1B);
    expect(slip[1], 0x40);
    expect(slip.sublist(slip.length - 4), <int>[0x1D, 0x56, 0x41, 0x10]);
    expect(slip.where((int b) => b == 0x1B).length, greaterThan(1));
  });

  test('cover crop maps the centered guide onto a cover-fitted image', () {
    final ({int x, int y, int width, int height}) crop = coverCropRect(
      imageWidth: 1000,
      imageHeight: 1000,
      paneWidth: 500,
      paneHeight: 500,
      guideWidth: 250,
      guideHeight: 250,
    );
    expect(crop.width, 500);
    expect(crop.height, 500);
    expect(crop.x, 250);
    expect(crop.y, 250);
  });

  test('proof capture crops landscape then rotates to portrait', () {
    final img.Image source = img.Image(width: 160, height: 90);
    img.fill(source, color: img.ColorRgb8(0, 0, 0));
    for (int y = 0; y < 90; y++) {
      for (int x = 0; x < 24; x++) {
        source.setPixelRgb(x, y, 255, 0, 0);
      }
    }
    final Uint8List jpeg = Uint8List.fromList(
      img.encodeJpg(source, quality: 100),
    );
    final Uint8List out = processProofCapture(
      jpeg: jpeg,
      paneWidth: 160,
      paneHeight: 90,
      previewWidth: 160,
      previewHeight: 90,
      guideWidth: 160,
      guideHeight: 90,
    );
    final img.Image decoded = img.decodeImage(out)!;
    expect(decoded.width, 90);
    expect(decoded.height, 160);
  });

  test('proof capture crops to the guide without flipping', () {
    final img.Image source = img.Image(width: 100, height: 100);
    img.fill(source, color: img.ColorRgb8(0, 0, 0));
    for (int y = 0; y < 100; y++) {
      for (int x = 0; x < 20; x++) {
        source.setPixelRgb(x, y, 255, 0, 0);
      }
    }
    final Uint8List jpeg = Uint8List.fromList(
      img.encodeJpg(source, quality: 100),
    );
    final Uint8List out = processProofCapture(
      jpeg: jpeg,
      paneWidth: 100,
      paneHeight: 100,
      previewWidth: 100,
      previewHeight: 100,
      guideWidth: 100,
      guideHeight: 100,
    );
    final img.Image decoded = img.decodeImage(out)!;
    expect(decoded.width, 100);
    expect(decoded.height, 100);
    final img.Pixel left = decoded.getPixel(8, 50);
    final img.Pixel right = decoded.getPixel(91, 50);
    expect(left.r > right.r, isTrue);
  });

  test('text threshold keeps solid dark ink without speckle', () {
    final img.Image block = img.Image(width: 32, height: 32, numChannels: 4);
    img.fill(block, color: img.ColorRgba8(20, 20, 20, 255));
    final Uint8List rgba = Uint8List.fromList(
      block.getBytes(order: img.ChannelOrder.rgba),
    );
    final List<int> bits = thresholdRgbaToBits(rgba, 32, 32);
    expect(bits.every((int b) => b == 1), isTrue);
  });

  test('photo optimizer lifts a light screen and dithers midtones', () {
    final img.Image gray = img.Image(width: 48, height: 48, numChannels: 4);
    for (int y = 0; y < 48; y++) {
      for (int x = 0; x < 48; x++) {
        final int v = (x * 255 / 47).round();
        gray.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    final img.Image out = optimizeProofPhoto(
      gray,
      maxWidth: 48,
      tune: const ProofTune(contrast: 1.5, gamma: 1.4, threshold: 128),
    );
    expect(out.width, 48);
    bool sawInk = false;
    bool sawPaper = false;
    for (final img.Pixel pixel in out) {
      if (pixel.r < 40) {
        sawInk = true;
      }
      if (pixel.r > 220) {
        sawPaper = true;
      }
    }
    expect(sawInk, isTrue);
    expect(sawPaper, isTrue);
  });

  test('phone screen gray does not crush to a black field', () {
    final img.Image screen = img.Image(width: 64, height: 64, numChannels: 4);
    img.fill(screen, color: img.ColorRgb8(150, 150, 150));
    for (int y = 20; y < 25; y++) {
      for (int x = 8; x < 56; x++) {
        screen.setPixelRgba(x, y, 28, 28, 28, 255);
      }
    }
    final img.Image out = optimizeProofPhoto(
      screen,
      maxWidth: 64,
      tune: const ProofTune(contrast: 1.5, gamma: 1.4, threshold: 128),
    );
    int ink = 0;
    int paper = 0;
    for (final img.Pixel pixel in out) {
      if (pixel.r < 40) {
        ink++;
      } else if (pixel.r > 200) {
        paper++;
      }
    }
    expect(paper, greaterThan(ink));
  });

  test('rasterProofPhoto uses live contrast gamma and threshold', () {
    final img.Image screen = img.Image(width: 32, height: 32, numChannels: 4);
    img.fill(screen, color: img.ColorRgb8(160, 160, 160));
    final Uint8List jpeg = Uint8List.fromList(img.encodePng(screen));
    final Uint8List out = rasterProofPhoto(
      jpeg: jpeg,
      contrast: 1.5,
      gamma: 1.4,
      threshold: 128,
      maxWidth: 32,
    );
    final img.Image decoded = img.decodeImage(out)!;
    int paper = 0;
    for (final img.Pixel pixel in decoded) {
      if (pixel.r > 200) {
        paper++;
      }
    }
    expect(paper, greaterThan(32 * 32 ~/ 2));
  });

  test('thermal preview keeps grayscale receipt without stacking proof', () {
    final img.Image receipt = img.Image(width: 200, height: 80);
    img.fill(receipt, color: img.ColorRgb8(180, 40, 40));
    final img.Image proof = img.Image(width: 200, height: 40);
    img.fill(proof, color: img.ColorRgb8(40, 40, 180));
    final Uint8List png = composeThermalPreviewPng(
      receiptPng: Uint8List.fromList(img.encodePng(receipt)),
      proofJpeg: Uint8List.fromList(img.encodeJpg(proof, quality: 80)),
    );
    final img.Image preview = img.decodeImage(png)!;
    expect(preview.width, ReceiptProofRaster.dots80mm);
    expect(preview.height, lessThan(250));
    final img.Pixel receiptPx = preview.getPixel(10, 10);
    expect(receiptPx.r, receiptPx.g);
    expect(receiptPx.r == 0 || receiptPx.r == 255, isFalse);
  });

  test('screenshot copy facts use pending account amount', () {
    final SaleTransaction txn = SaleTransaction(
      tokenNo: 200010,
      unitId: 1,
      fuelType: kDieselFuelType,
      amountPkr: 1000,
      volumeLiters: 4,
      rate: 250,
      meterCount: 1,
      timestamp: DateTime(2026, 10, 23),
      payment: PaymentMethod.udhaar,
      customerName: 'Ali',
      cashierName: 'Amir',
      cashAmount: 200,
      pendingAccountAmount: 300,
    );
    final ScreenshotCopyFacts facts = ScreenshotCopyFacts.fromSale(txn);
    expect(facts.tokenLabel, formatLedgerToken(txn.tokenNo));
    expect(facts.customerName, 'Ali');
    expect(facts.accountAmountPkr, 300);
    expect(facts.operatorName, 'Amir');
  });

  test('bank and EasyPaisa print a third screenshot slip when proof exists', () {
    final SaleTransaction digital = SaleTransaction(
      tokenNo: 200003,
      unitId: 1,
      fuelType: kDieselFuelType,
      amountPkr: 1000,
      volumeLiters: 4,
      rate: 250,
      meterCount: 1,
      timestamp: DateTime(2026, 10, 22),
      payment: PaymentMethod.easyPaisa,
      accountAmount: 1000,
      proofImagePath: r'C:\FuelPointData\receipt_proofs\a.jpg',
    );
    expect(digital.thermalSlipCount, 3);
    expect(digital.copyWith(proofImagePath: '').thermalSlipCount, 2);
    expect(PaymentMethod.udhaar.printsScreenshotCopy, isTrue);
  });

  test('fromMap keeps proof_image_path', () {
    final SaleTransaction txn = SaleTransaction.fromMap(<String, Object?>{
      'TOKEN': 'T-100001',
      'DATE_TIME': '2026-10-22T18:00:00.000',
      'UNIT_NO': 1,
      'AMOUNT': 1000,
      'LITERS': 4,
      'RATE': 250,
      'OPENING_READING': 0,
      'CLOSING_READING': 4,
      'PAYMENT_METHOD': 'EasyPaisa',
      'ACCOUNT_AMOUNT': 1000,
      'PROOF_IMAGE_PATH': r'C:\FuelPointData\receipt_proofs\proof_100001.jpg',
    });
    expect(txn.proofImagePath, contains('receipt_proofs'));
    expect(txn.toMap()['PROOF_IMAGE_PATH'], txn.proofImagePath);
  });
}
