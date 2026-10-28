import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/dispensr_theme.dart';
import '../../../features/station/data/receipt_proof_raster.dart';
import '../../../features/station/data/receipt_proof_storage.dart';
import '../../../features/station/data/webcam_windows.dart';
import '../../../features/station/domain/dispenser_models.dart';
import '../../../features/station/domain/money_format.dart';
import '../../../features/station/presentation/station_providers.dart';
import 'Services/receipt_preview_widget.dart';

Future<SaleTransaction?> showProofCaptureDialog({
  required BuildContext context,
  required SaleTransaction txn,
}) {
  return showDialog<SaleTransaction>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return ProofCaptureDialog(txn: txn);
    },
  );
}

Future<String?> showProofImageCaptureDialog({
  required BuildContext context,
  required String title,
  required int fileTokenNo,
  ScreenshotCopyFacts? facts,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return ProofCaptureDialog(
        title: title,
        fileTokenNo: fileTokenNo,
        facts: facts,
      );
    },
  );
}

Future<SaleTransaction> maybeCaptureAccountProof({
  required BuildContext context,
  required SaleTransaction txn,
}) async {
  if (!txn.needsAccountProof) {
    return txn;
  }
  final SaleTransaction? withProof = await showProofCaptureDialog(
    context: context,
    txn: txn,
  );
  return withProof ?? txn;
}

class ProofCaptureDialog extends ConsumerStatefulWidget {
  const ProofCaptureDialog({
    super.key,
    this.txn,
    this.title,
    this.fileTokenNo,
    this.facts,
  });

  final SaleTransaction? txn;
  final String? title;
  final int? fileTokenNo;
  final ScreenshotCopyFacts? facts;

  @override
  ConsumerState<ProofCaptureDialog> createState() => _ProofCaptureDialogState();
}

class _ProofCaptureDialogState extends ConsumerState<ProofCaptureDialog> {
  final ReceiptProofStorage _storage = ReceiptProofStorage();
  final ValueNotifier<Uint8List?> _stillPreview = ValueNotifier<Uint8List?>(
    null,
  );
  final ValueNotifier<bool> _thermalMode = ValueNotifier<bool>(true);
  CameraController? _camera;
  Uint8List? _croppedColor;
  Uint8List? _printProof;
  String? _cameraError;
  bool _starting = true;
  bool _busy = false;
  bool _previewBusy = false;
  bool _previewQueued = false;
  bool _fullBusy = false;
  bool _fullQueued = false;
  ProofTune _tune = const ProofTune();
  Size _paneSize = const Size(520, 420);
  final GlobalKey _previewPaneKey = GlobalKey();
  final GlobalKey _frameKey = GlobalKey();
  Timer? _previewDebounce;
  int _previewGen = 0;
  int _fullGen = 0;
  bool _closed = false;

  SaleTransaction? get _txn => widget.txn;

  int get _fileTokenNo => widget.fileTokenNo ?? widget.txn?.tokenNo ?? 0;

  ScreenshotCopyFacts get _facts {
    final ScreenshotCopyFacts? custom = widget.facts;
    if (custom != null) {
      return custom;
    }
    final SaleTransaction? sale = _txn;
    if (sale != null) {
      return ScreenshotCopyFacts.fromSale(sale);
    }
    return ScreenshotCopyFacts(
      tokenLabel: formatTokenNo(_fileTokenNo),
      customerName: 'Walk-in',
      accountAmountPkr: 0,
      operatorName: 'Operator',
      dateLabel: formatDateOnly(DateTime.now()),
      timeLabel: formatClock(DateTime.now()),
    );
  }

  String get _title {
    final String? custom = widget.title?.trim();
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }
    return 'Capture transfer proof · ${formatTokenNo(_fileTokenNo)}';
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadTune());
    unawaited(_startCamera());
  }

  @override
  void dispose() {
    _closed = true;
    _previewDebounce?.cancel();
    _previewDebounce = null;
    _previewGen++;
    _fullGen++;
    final CameraController? camera = _camera;
    _camera = null;
    _stillPreview.dispose();
    _thermalMode.dispose();
    unawaited(camera?.dispose());
    super.dispose();
  }

  bool get _canUpdate => mounted && !_closed;

  void _safeSetState(VoidCallback fn) {
    if (!_canUpdate) {
      return;
    }
    setState(fn);
  }

  Future<void> _loadTune() async {
    final ProofTune tune = await _storage.loadTune();
    if (!_canUpdate) {
      return;
    }
    _safeSetState(() {
      _tune = tune;
    });
  }

  Future<void> _persistTune() async {
    await _storage.saveTune(_tune);
  }

  Future<void> _startCamera() async {
    if (!_canUpdate) {
      return;
    }
    _safeSetState(() {
      _starting = true;
      _cameraError = null;
    });
    final CameraController? previous = _camera;
    _camera = null;
    if (previous != null) {
      await previous.dispose();
    }
    if (!_canUpdate) {
      return;
    }
    try {
      ensureWindowsCameraPlugin();
      final List<CameraDescription> cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('No webcam is connected');
      }
      CameraDescription selected = cameras.first;
      for (final CameraDescription camera in cameras) {
        if (camera.lensDirection == CameraLensDirection.external) {
          selected = camera;
          break;
        }
      }
      final CameraController controller = CameraController(
        selected,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!_canUpdate) {
        await controller.dispose();
        return;
      }
      _safeSetState(() {
        _camera = controller;
        _starting = false;
      });
    } catch (error, stack) {
      debugPrint('Webcam init failed: $error\n$stack');
      if (!_canUpdate) {
        return;
      }
      _safeSetState(() {
        _starting = false;
        _cameraError = friendlyWebcamError(error);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No webcam available. You can continue without a transfer proof.',
          ),
        ),
      );
    }
  }

  ({double paneW, double paneH, double guideW, double guideH}) _guideMetrics() {
    double paneW = _paneSize.width;
    double paneH = _paneSize.height;
    double guideW = ReceiptProofRaster.guideWidth;
    double guideH = ReceiptProofRaster.guideHeight;
    final RenderBox? paneBox =
        _previewPaneKey.currentContext?.findRenderObject() as RenderBox?;
    final RenderBox? frameBox =
        _frameKey.currentContext?.findRenderObject() as RenderBox?;
    if (paneBox != null &&
        frameBox != null &&
        paneBox.hasSize &&
        frameBox.hasSize) {
      paneW = paneBox.size.width;
      paneH = paneBox.size.height;
      guideW = frameBox.size.width;
      guideH = frameBox.size.height;
    }
    return (paneW: paneW, paneH: paneH, guideW: guideW, guideH: guideH);
  }

  List<Object> _cropJobArgs(Uint8List raw, Size preview) {
    final ({double paneW, double paneH, double guideW, double guideH}) metrics =
        _guideMetrics();
    return <Object>[
      Uint8List.fromList(raw),
      metrics.paneW,
      metrics.paneH,
      preview.width,
      preview.height,
      metrics.guideW,
      metrics.guideH,
    ];
  }

  List<Object> _rasterJobArgs(
    Uint8List cropped, {
    required double maxWidth,
    required bool dither,
  }) {
    return <Object>[
      Uint8List.fromList(cropped),
      _tune.contrast,
      _tune.gamma,
      _tune.threshold,
      maxWidth,
      dither ? 1.0 : 0.0,
    ];
  }

  Future<void> _runPreviewRaster() async {
    final Uint8List? cropped = _croppedColor;
    if (cropped == null) {
      return;
    }
    if (_previewBusy) {
      _previewQueued = true;
      return;
    }
    _previewBusy = true;
    try {
      do {
        _previewQueued = false;
        final int gen = ++_previewGen;
        final ProofTune tune = _tune;
        final Uint8List bytes = await compute(rasterProofPhotoJob, <Object>[
          Uint8List.fromList(cropped),
          tune.contrast,
          tune.gamma,
          tune.threshold,
          ReceiptProofRaster.previewWidth.toDouble(),
          0.0,
        ]);
        if (!_canUpdate) {
          break;
        }
        if (gen != _previewGen) {
          continue;
        }
        _stillPreview.value = bytes;
      } while (_previewQueued && _canUpdate);
    } catch (error, stack) {
      debugPrint('Proof preview raster failed: $error\n$stack');
    } finally {
      _previewBusy = false;
    }
  }

  Future<void> _runFullRaster() async {
    final Uint8List? cropped = _croppedColor;
    if (cropped == null) {
      return;
    }
    if (_fullBusy) {
      _fullQueued = true;
      return;
    }
    _fullBusy = true;
    try {
      do {
        _fullQueued = false;
        final int gen = ++_fullGen;
        final Uint8List bytes = await compute(
          rasterProofPhotoJob,
          _rasterJobArgs(
            cropped,
            maxWidth: ReceiptProofRaster.dots80mm.toDouble(),
            dither: true,
          ),
        );
        if (!_canUpdate) {
          break;
        }
        if (gen != _fullGen) {
          continue;
        }
        _printProof = bytes;
        _safeSetState(() {});
      } while (_fullQueued && _canUpdate);
    } catch (error, stack) {
      debugPrint('Proof print raster failed: $error\n$stack');
    } finally {
      _fullBusy = false;
    }
  }

  void _onTuneChanged(ProofTune next) {
    _tune = next.clamp();
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 100), () {
      if (!_canUpdate) {
        return;
      }
      unawaited(_runPreviewRaster());
    });
  }

  void _onTuneChangeEnd(ProofTune next) {
    _tune = next.clamp();
    _previewDebounce?.cancel();
    unawaited(_runPreviewRaster());
    unawaited(_runFullRaster());
    unawaited(_persistTune());
  }

  Future<void> _snap() async {
    final CameraController? camera = _camera;
    if (camera == null || !camera.value.isInitialized || _busy) {
      return;
    }
    _safeSetState(() {
      _busy = true;
    });
    try {
      final XFile file = await camera.takePicture();
      final Uint8List raw = await file.readAsBytes();
      final Size preview = camera.value.previewSize ?? const Size(640, 480);
      final Uint8List cropped = await compute(
        processProofCaptureJob,
        _cropJobArgs(raw, preview),
      );
      if (!_canUpdate) {
        return;
      }
      _safeSetState(() {
        _croppedColor = cropped;
        _printProof = null;
      });
      _thermalMode.value = true;
      _stillPreview.value = cropped;
      await _runPreviewRaster();
      unawaited(_runFullRaster());
    } catch (error, stack) {
      debugPrint('Webcam snap failed: $error\n$stack');
      if (!_canUpdate) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not snap receipt. $error')));
    } finally {
      _safeSetState(() {
        _busy = false;
      });
    }
  }

  void _retake() {
    if (!_canUpdate) {
      return;
    }
    _previewDebounce?.cancel();
    _previewGen++;
    _fullGen++;
    _stillPreview.value = null;
    _safeSetState(() {
      _croppedColor = null;
      _printProof = null;
    });
  }

  Future<void> _confirmSave() async {
    while (_fullBusy && _canUpdate) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    if (!_canUpdate) {
      return;
    }
    if (_txn != null && _croppedColor != null && _printProof == null) {
      await _runFullRaster();
    }
    final Uint8List? bytes = _txn == null
        ? (_croppedColor ?? _printProof)
        : (_printProof ?? _croppedColor);
    if (bytes == null || _busy) {
      return;
    }
    _safeSetState(() {
      _busy = true;
    });
    try {
      await _storage.saveTune(_tune);
      final String path = await _storage.saveJpeg(
        tokenNo: _fileTokenNo,
        bytes: bytes,
      );
      final SaleTransaction? sale = _txn;
      if (sale == null) {
        if (!mounted) {
          return;
        }
        Navigator.of(context).pop(path);
        return;
      }
      final SaleTransaction? updated = await ref
          .read(stationControllerProvider.notifier)
          .saveAccountProofImage(tokenNo: sale.tokenNo, path: path);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(updated ?? sale.copyWith(proofImagePath: path));
    } catch (error, stack) {
      debugPrint('Proof save failed: $error\n$stack');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save proof. $error')));
    } finally {
      _safeSetState(() {
        _busy = false;
      });
    }
  }

  Future<void> _bypass() async {
    if (_busy) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Saved without transfer proof. Path left empty.'),
      ),
    );
    Navigator.of(context).pop(_txn);
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = DispensrTokens.of(context);
    final bool hasSnap = _croppedColor != null;
    return Dialog(
      backgroundColor: tokens.card,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius20),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080, maxHeight: 780),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            children: <Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _title,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: tokens.ink,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(flex: 11, child: _capturePane(tokens)),
                    const SizedBox(width: 12),
                    Expanded(flex: 9, child: _printPreviewPane(tokens)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  TextButton(
                    onPressed: _busy ? null : _bypass,
                    child: const Text('Continue without proof'),
                  ),
                  const Spacer(),
                  if (!hasSnap)
                    FilledButton.icon(
                      onPressed: _busy || _camera == null ? null : _snap,
                      icon: const Icon(Icons.camera_alt_outlined, size: 18),
                      label: Text(_busy ? 'Snapping…' : 'Snap Receipt'),
                    )
                  else ...<Widget>[
                    TextButton(
                      onPressed: _busy ? null : _retake,
                      child: const Text('Retake'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _busy ? null : _confirmSave,
                      child: Text(_busy ? 'Saving…' : 'Confirm & Save'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _printPreviewPane(DispensrTokens tokens) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.radius20),
        border: Border.all(color: tokens.line),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(tokens.radius20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Text(
                'Print preview · Screenshot copy',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: tokens.ink,
                ),
              ),
            ),
            Expanded(
              child: ColoredBox(
                color: const Color(0xFFFFFFFF),
                child: ValueListenableBuilder<bool>(
                  valueListenable: _thermalMode,
                  builder: (BuildContext context, bool thermal, _) {
                    return ValueListenableBuilder<Uint8List?>(
                      valueListenable: _stillPreview,
                      builder: (BuildContext context, Uint8List? preview, _) {
                        final Uint8List? bytes =
                            _printProof ?? preview ?? _croppedColor;
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                          child: FittedBox(
                            fit: BoxFit.contain,
                            alignment: Alignment.topCenter,
                            child: screenshotCopyReceipt(
                              facts: _facts,
                              proofImage: bytes == null
                                  ? null
                                  : MemoryImage(bytes),
                              forPrint: true,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _capturePane(DispensrTokens tokens) {
    final bool hasSnap = _croppedColor != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.canvas,
        borderRadius: BorderRadius.circular(tokens.radius20),
        border: Border.all(color: tokens.line),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(tokens.radius20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: hasSnap
                  ? _ProofStillView(
                      thermalMode: _thermalMode,
                      previewBytes: _stillPreview,
                      colorBytes: _croppedColor,
                    )
                  : _livePreview(tokens),
            ),
            if (hasSnap)
              _ProofTuneControls(
                tokens: tokens,
                initial: _tune,
                thermalMode: _thermalMode,
                onChanged: _onTuneChanged,
                onChangeEnd: _onTuneChangeEnd,
              ),
          ],
        ),
      ),
    );
  }

  Widget _livePreview(DispensrTokens tokens) {
    if (_starting) {
      return const Center(child: CircularProgressIndicator());
    }
    final CameraController? camera = _camera;
    if (_cameraError != null || camera == null || !camera.value.isInitialized) {
      return Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.videocam_off_outlined, size: 36, color: tokens.bad),
            const SizedBox(height: 10),
            Text(
              'Webcam is not available.\n${_cameraError ?? 'Connect a USB camera and try again.'}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 13,
                height: 1.4,
                color: tokens.ink,
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _startCamera,
              child: const Text('Retry camera'),
            ),
          ],
        ),
      );
    }
    final Size preview = camera.value.previewSize ?? const Size(640, 480);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _paneSize = Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          key: _previewPaneKey,
          fit: StackFit.expand,
          children: <Widget>[
            ColoredBox(
              color: const Color(0xFF111111),
              child: ClipRect(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: preview.width,
                    height: preview.height,
                    child: CameraPreview(camera),
                  ),
                ),
              ),
            ),
            IgnorePointer(
              child: Center(
                child: Container(
                  key: _frameKey,
                  width: ReceiptProofRaster.guideWidth,
                  height: ReceiptProofRaster.guideHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: tokens.coral, width: 2),
                  ),
                ),
              ),
            ),
            Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'Hold the phone sideways (landscape) so the receipt fills the frame.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: tokens.card,
                        shadows: const <Shadow>[
                          Shadow(blurRadius: 8, color: Color(0xCC000000)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'فون کو لیٹا کر رسید فریم کے اندر رکھیں۔',
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontFamily: 'NotoNastaliqUrdu',
                        fontWeight: FontWeight.w400,
                        fontSize: 12,
                        height: 1.8,
                        color: tokens.card,
                        shadows: const <Shadow>[
                          Shadow(blurRadius: 8, color: Color(0xCC000000)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ProofStillView extends StatelessWidget {
  const _ProofStillView({
    required this.thermalMode,
    required this.previewBytes,
    required this.colorBytes,
  });

  final ValueNotifier<bool> thermalMode;
  final ValueNotifier<Uint8List?> previewBytes;
  final Uint8List? colorBytes;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF111111),
      child: ValueListenableBuilder<bool>(
        valueListenable: thermalMode,
        builder: (BuildContext context, bool thermal, _) {
          return ValueListenableBuilder<Uint8List?>(
            valueListenable: previewBytes,
            builder: (BuildContext context, Uint8List? preview, _) {
              final Uint8List? bytes = thermal
                  ? (preview ?? colorBytes)
                  : colorBytes;
              if (bytes == null) {
                return const Center(child: CircularProgressIndicator());
              }
              return Image.memory(
                bytes,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
              );
            },
          );
        },
      ),
    );
  }
}

class _ProofTuneControls extends StatefulWidget {
  const _ProofTuneControls({
    required this.tokens,
    required this.initial,
    required this.thermalMode,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final DispensrTokens tokens;
  final ProofTune initial;
  final ValueNotifier<bool> thermalMode;
  final ValueChanged<ProofTune> onChanged;
  final ValueChanged<ProofTune> onChangeEnd;

  @override
  State<_ProofTuneControls> createState() => _ProofTuneControlsState();
}

class _ProofTuneControlsState extends State<_ProofTuneControls> {
  late ProofTune _tune;
  bool _open = true;

  @override
  void initState() {
    super.initState();
    _tune = widget.initial.clamp();
  }

  void _emit(ProofTune next, {required bool ended}) {
    if (!mounted) {
      return;
    }
    final ProofTune clamped = next.clamp();
    setState(() {
      _tune = clamped;
    });
    if (ended) {
      widget.onChangeEnd(clamped);
    } else {
      widget.onChanged(clamped);
    }
  }

  @override
  Widget build(BuildContext context) {
    final DispensrTokens tokens = widget.tokens;
    return Material(
      color: tokens.card,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          InkWell(
            onTap: () {
              if (!mounted) {
                return;
              }
              setState(() {
                _open = !_open;
              });
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Thermal look',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: tokens.ink,
                      ),
                    ),
                  ),
                  Icon(
                    _open ? Icons.expand_more : Icons.expand_less,
                    color: tokens.inkMuted,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_open) ...<Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 8, 4),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Thermal B&W raster mode',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 12,
                        color: tokens.ink,
                      ),
                    ),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: widget.thermalMode,
                    builder: (BuildContext context, bool on, _) {
                      return Switch.adaptive(
                        value: on,
                        onChanged: (bool value) {
                          widget.thermalMode.value = value;
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
            _slider(
              tokens: tokens,
              label: 'Contrast',
              value: _tune.contrast,
              min: ProofTune.minContrast,
              max: ProofTune.maxContrast,
              display: _tune.contrast.toStringAsFixed(2),
              onChanged: (double v) {
                _emit(
                  ProofTune(
                    contrast: v,
                    gamma: _tune.gamma,
                    threshold: _tune.threshold,
                  ),
                  ended: false,
                );
              },
              onChangeEnd: (double v) {
                _emit(
                  ProofTune(
                    contrast: v,
                    gamma: _tune.gamma,
                    threshold: _tune.threshold,
                  ),
                  ended: true,
                );
              },
            ),
            _slider(
              tokens: tokens,
              label: 'Gamma',
              value: _tune.gamma,
              min: ProofTune.minGamma,
              max: ProofTune.maxGamma,
              display: _tune.gamma.toStringAsFixed(2),
              onChanged: (double v) {
                _emit(
                  ProofTune(
                    contrast: _tune.contrast,
                    gamma: v,
                    threshold: _tune.threshold,
                  ),
                  ended: false,
                );
              },
              onChangeEnd: (double v) {
                _emit(
                  ProofTune(
                    contrast: _tune.contrast,
                    gamma: v,
                    threshold: _tune.threshold,
                  ),
                  ended: true,
                );
              },
            ),
            _slider(
              tokens: tokens,
              label: 'Threshold',
              value: _tune.threshold,
              min: ProofTune.minThreshold,
              max: ProofTune.maxThreshold,
              divisions: 255,
              display: _tune.threshold.round().toString(),
              onChanged: (double v) {
                _emit(
                  ProofTune(
                    contrast: _tune.contrast,
                    gamma: _tune.gamma,
                    threshold: v,
                  ),
                  ended: false,
                );
              },
              onChangeEnd: (double v) {
                _emit(
                  ProofTune(
                    contrast: _tune.contrast,
                    gamma: _tune.gamma,
                    threshold: v,
                  ),
                  ended: true,
                );
              },
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  Widget _slider({
    required DispensrTokens tokens,
    required String label,
    required double value,
    required double min,
    required double max,
    required String display,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
    int? divisions,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 11,
                color: tokens.inkMuted,
              ),
            ),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              divisions: divisions,
              label: display,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              display,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 11,
                color: tokens.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
