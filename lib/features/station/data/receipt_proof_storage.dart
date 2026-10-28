import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/database_helper.dart';
import 'receipt_proof_raster.dart';

/// JPEG proofs next to the station DB (`C:\FuelPointData\receipt_proofs`).
class ReceiptProofStorage {
  ReceiptProofStorage({DatabaseHelper? db})
    : _db = db ?? DatabaseHelper.instance;

  final DatabaseHelper _db;

  static const String folderName = 'receipt_proofs';
  static const String _contrastKey = 'proof_tune_contrast_v2';
  static const String _gammaKey = 'proof_tune_gamma_v2';
  static const String _thresholdKey = 'proof_tune_threshold_v2';

  static String fileName({required int tokenNo, required DateTime at}) {
    final String stamp =
        '${at.year.toString().padLeft(4, '0')}'
        '${at.month.toString().padLeft(2, '0')}'
        '${at.day.toString().padLeft(2, '0')}_'
        '${at.hour.toString().padLeft(2, '0')}'
        '${at.minute.toString().padLeft(2, '0')}'
        '${at.second.toString().padLeft(2, '0')}';
    return 'proof_${tokenNo}_$stamp.jpg';
  }

  Future<ProofTune> loadTune() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return ProofTune(
      contrast: prefs.getDouble(_contrastKey) ?? ProofTune.defaultContrast,
      gamma: prefs.getDouble(_gammaKey) ?? ProofTune.defaultGamma,
      threshold: prefs.getDouble(_thresholdKey) ?? ProofTune.defaultThreshold,
    ).clamp();
  }

  Future<void> saveTune(ProofTune tune) async {
    final ProofTune clamped = tune.clamp();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_contrastKey, clamped.contrast);
    await prefs.setDouble(_gammaKey, clamped.gamma);
    await prefs.setDouble(_thresholdKey, clamped.threshold);
  }

  /// Writes [bytes] unchanged. Caller must pass a portrait, cropped JPEG.
  Future<String> saveJpeg({
    required int tokenNo,
    required Uint8List bytes,
    DateTime? at,
  }) async {
    final String root = await _db.dataDirectoryPath;
    final String dirPath = p.join(root, folderName);
    final String path = p.join(
      dirPath,
      fileName(tokenNo: tokenNo, at: at ?? DateTime.now()),
    );
    await Isolate.run(() {
      Directory(dirPath).createSync(recursive: true);
      File(path).writeAsBytesSync(bytes, flush: true);
    });
    return path;
  }
}
