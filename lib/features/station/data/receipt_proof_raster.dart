import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Decode a phone-receipt JPEG and scale it for 80mm (576px) or 58mm (384px).
class ReceiptProofRaster {
  ReceiptProofRaster._();

  static const int dots80mm = 576;
  static const int dots58mm = 384;
  static const int previewWidth = 300;

  /// Landscape overlay matching the webcam 16:9 sensor and a sideways phone.
  static const double guideWidth = 480;
  static const double guideHeight = 270;

  /// Rotate the cropped landscape still to portrait. Use `270` if text is upside down.
  static const int landscapeToPortraitDegrees = 90;

  static ({int width, int height, Uint8List rgba}) prepareRgba(
    Uint8List jpeg, {
    int maxWidth = dots80mm,
  }) {
    final img.Image? decoded = img.decodeImage(jpeg);
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      throw StateError('Could not decode receipt proof');
    }
    final img.Image rgba = _resizeToWidth(decoded, maxWidth);
    return (
      width: rgba.width,
      height: rgba.height,
      rgba: Uint8List.fromList(rgba.getBytes(order: img.ChannelOrder.rgba)),
    );
  }

  /// Resize a JPEG that is already cropped and dithered. Do not filter again.
  static ({int width, int height, Uint8List rgba}) preparePhotoThermal(
    Uint8List jpeg, {
    int maxWidth = dots80mm,
  }) {
    return prepareRgba(jpeg, maxWidth: maxWidth);
  }
}

/// Maps the centered framing guide onto a BoxFit.cover camera image.
({int x, int y, int width, int height}) coverCropRect({
  required int imageWidth,
  required int imageHeight,
  required double paneWidth,
  required double paneHeight,
  required double guideWidth,
  required double guideHeight,
}) {
  if (imageWidth <= 0 ||
      imageHeight <= 0 ||
      paneWidth <= 0 ||
      paneHeight <= 0) {
    return (x: 0, y: 0, width: imageWidth, height: imageHeight);
  }
  final double scale = math.max(
    paneWidth / imageWidth,
    paneHeight / imageHeight,
  );
  final double offsetX = (paneWidth - imageWidth * scale) / 2;
  final double offsetY = (paneHeight - imageHeight * scale) / 2;
  final double frameLeft = (paneWidth - guideWidth) / 2;
  final double frameTop = (paneHeight - guideHeight) / 2;
  int x = ((frameLeft - offsetX) / scale).floor();
  int y = ((frameTop - offsetY) / scale).floor();
  int width = (guideWidth / scale).ceil();
  int height = (guideHeight / scale).ceil();
  if (x < 0) {
    width += x;
    x = 0;
  }
  if (y < 0) {
    height += y;
    y = 0;
  }
  if (x + width > imageWidth) {
    width = imageWidth - x;
  }
  if (y + height > imageHeight) {
    height = imageHeight - y;
  }
  if (width < 1) {
    width = 1;
    x = x.clamp(0, imageWidth - 1);
  }
  if (height < 1) {
    height = 1;
    y = y.clamp(0, imageHeight - 1);
  }
  return (x: x, y: y, width: width, height: height);
}

/// Cashier knobs for the EasyPaisa / bank proof photo.
class ProofTune {
  const ProofTune({
    this.contrast = defaultContrast,
    this.gamma = defaultGamma,
    this.threshold = defaultThreshold,
  });

  static const double defaultContrast = 0.60;
  static const double defaultGamma = 1.45;
  static const double defaultThreshold = 255;
  static const double minContrast = 0.5;
  static const double maxContrast = 3.0;
  static const double minGamma = 0.5;
  static const double maxGamma = 2.5;
  static const double minThreshold = 0;
  static const double maxThreshold = 255;

  final double contrast;
  final double gamma;
  final double threshold;

  ProofTune clamp() {
    return ProofTune(
      contrast: contrast.clamp(minContrast, maxContrast).toDouble(),
      gamma: gamma.clamp(minGamma, maxGamma).toDouble(),
      threshold: threshold.clamp(minThreshold, maxThreshold).toDouble(),
    );
  }
}

Uint8List processProofCaptureJob(List<Object> args) {
  return processProofCapture(
    jpeg: args[0] as Uint8List,
    paneWidth: args[1] as double,
    paneHeight: args[2] as double,
    previewWidth: args[3] as double,
    previewHeight: args[4] as double,
    guideWidth: args.length > 5
        ? args[5] as double
        : ReceiptProofRaster.guideWidth,
    guideHeight: args.length > 6
        ? args[6] as double
        : ReceiptProofRaster.guideHeight,
  );
}

Uint8List rasterProofPhotoJob(List<Object> args) {
  return rasterProofPhoto(
    jpeg: args[0] as Uint8List,
    contrast: args[1] as double,
    gamma: args[2] as double,
    threshold: args[3] as double,
    maxWidth: args.length > 4
        ? (args[4] as double).round()
        : ReceiptProofRaster.dots80mm,
    dither: args.length <= 5 || (args[5] as double) != 0,
  );
}

Uint8List composeThermalPreviewJob(List<Object?> args) {
  return composeThermalPreviewPng(
    receiptPng: args[0]! as Uint8List,
    proofJpeg: args[1] as Uint8List?,
  );
}

/// Crop the landscape webcam JPEG to the guide, then rotate to portrait.
Uint8List processProofCapture({
  required Uint8List jpeg,
  required double paneWidth,
  required double paneHeight,
  required double previewWidth,
  required double previewHeight,
  double guideWidth = ReceiptProofRaster.guideWidth,
  double guideHeight = ReceiptProofRaster.guideHeight,
}) {
  final img.Image? decoded = img.decodeImage(jpeg);
  if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
    throw StateError('Could not decode webcam snapshot');
  }
  img.Image working = decoded;
  try {
    working = img.bakeOrientation(working);
  } catch (_) {}
  final ({double width, double height}) src = _previewMappedToImage(
    previewWidth: previewWidth,
    previewHeight: previewHeight,
    imageWidth: working.width,
    imageHeight: working.height,
  );
  final double srcW = src.width;
  final double srcH = src.height;
  final ({int x, int y, int width, int height}) previewCrop = coverCropRect(
    imageWidth: srcW.round(),
    imageHeight: srcH.round(),
    paneWidth: paneWidth,
    paneHeight: paneHeight,
    guideWidth: guideWidth,
    guideHeight: guideHeight,
  );
  final int x = (previewCrop.x * working.width / srcW).round();
  final int y = (previewCrop.y * working.height / srcH).round();
  final int width = (previewCrop.width * working.width / srcW).round();
  final int height = (previewCrop.height * working.height / srcH).round();
  final int cropX = x.clamp(0, working.width - 1);
  final int cropY = y.clamp(0, working.height - 1);
  final int cropW = width.clamp(1, working.width - cropX);
  final int cropH = height.clamp(1, working.height - cropY);
  img.Image cropped = img.copyCrop(
    working,
    x: cropX,
    y: cropY,
    width: cropW,
    height: cropH,
  );
  if (cropped.width > cropped.height) {
    cropped = img.copyRotate(
      cropped,
      angle: ReceiptProofRaster.landscapeToPortraitDegrees,
    );
  }
  return Uint8List.fromList(img.encodeJpg(cropped, quality: 92));
}

enum ThermalBitMode {
  /// Vector receipt UI: pack dark ink only. No error diffusion.
  text,

  /// Pre-processed proof JPEG: pack mid-gray dots, do not dither again.
  photo,
}

List<int> rgbaToThermalBits(
  Uint8List rgba,
  int width,
  int height, {
  ThermalBitMode mode = ThermalBitMode.text,
}) {
  switch (mode) {
    case ThermalBitMode.text:
      return thresholdRgbaToBits(rgba, width, height);
    case ThermalBitMode.photo:
      return thresholdRgbaToBits(rgba, width, height, threshold: 128);
  }
}

Float32List _lumaFromRgba(Uint8List rgba, int count) {
  final Float32List gray = Float32List(count);
  for (int i = 0, p = 0; i < count; i++, p += 4) {
    final int a = rgba[p + 3];
    if (a < 32) {
      gray[i] = 255;
      continue;
    }
    gray[i] = (rgba[p] * 0.299) + (rgba[p + 1] * 0.587) + (rgba[p + 2] * 0.114);
  }
  return gray;
}

/// Dark ink stays solid; paper stays white. No speckle from error diffusion.
List<int> thresholdRgbaToBits(
  Uint8List rgba,
  int width,
  int height, {
  double threshold = 168,
}) {
  final Float32List gray = _lumaFromRgba(rgba, width * height);
  final List<int> bits = List<int>.filled(gray.length, 0);
  for (int i = 0; i < gray.length; i++) {
    bits[i] = gray[i] < threshold ? 1 : 0;
  }
  return bits;
}

Uint8List rasterProofPhoto({
  required Uint8List jpeg,
  double contrast = ProofTune.defaultContrast,
  double gamma = ProofTune.defaultGamma,
  double threshold = ProofTune.defaultThreshold,
  int maxWidth = ReceiptProofRaster.dots80mm,
  bool dither = true,
}) {
  final img.Image? decoded = img.decodeImage(jpeg);
  if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
    throw StateError('Could not decode cropped proof');
  }
  final img.Image photo = optimizeProofPhoto(
    decoded,
    maxWidth: maxWidth,
    dither: dither,
    tune: ProofTune(
      contrast: contrast,
      gamma: gamma,
      threshold: threshold,
    ).clamp(),
  );
  if (dither) {
    return Uint8List.fromList(img.encodeJpg(photo, quality: 92));
  }
  return Uint8List.fromList(img.encodePng(photo));
}

/// Contrast/gamma/threshold. Optional Floyd–Steinberg (save/print only).
img.Image optimizeProofPhoto(
  img.Image src, {
  int maxWidth = 576,
  ProofTune tune = const ProofTune(),
  bool dither = true,
}) {
  img.Image work = src;
  try {
    work = img.bakeOrientation(work);
  } catch (_) {}
  work = img.grayscale(work);
  work = _resizeToWidth(work, maxWidth);
  work = img.adjustColor(work, contrast: tune.contrast, gamma: tune.gamma);
  final int cut = tune.threshold.round().clamp(0, 255);
  for (final img.Pixel pixel in work) {
    if (pixel.r >= cut) {
      pixel
        ..r = 255
        ..g = 255
        ..b = 255;
    }
  }
  if (!dither) {
    return work;
  }
  return img.ditherImage(work, kernel: img.DitherKernel.floydSteinberg);
}

/// Map the webcam preview size onto the JPEG when Windows swaps width/height.
({double width, double height}) _previewMappedToImage({
  required double previewWidth,
  required double previewHeight,
  required int imageWidth,
  required int imageHeight,
}) {
  double srcW = previewWidth > 0 ? previewWidth : imageWidth.toDouble();
  double srcH = previewHeight > 0 ? previewHeight : imageHeight.toDouble();
  if (srcW < 1 || srcH < 1 || imageWidth < 1 || imageHeight < 1) {
    return (width: imageWidth.toDouble(), height: imageHeight.toDouble());
  }
  final double previewAspect = srcW / srcH;
  final double imageAspect = imageWidth / imageHeight;
  final double swappedAspect = srcH / srcW;
  if ((swappedAspect - imageAspect).abs() + 0.02 <
      (previewAspect - imageAspect).abs()) {
    return (width: srcH, height: srcW);
  }
  return (width: srcW, height: srcH);
}

img.Image _resizeToWidth(img.Image source, int maxWidth) {
  img.Image fitted = source;
  if (source.width != maxWidth) {
    final int height = (source.height * maxWidth / source.width).round().clamp(
      1,
      8000,
    );
    fitted = img.copyResize(
      source,
      width: maxWidth,
      height: height,
      interpolation: img.Interpolation.cubic,
    );
  }
  return fitted.convert(numChannels: 4);
}

/// Stack a clean grayscale receipt PNG on top of the already-rastered proof.
Uint8List composeThermalPreviewPng({
  required Uint8List receiptPng,
  Uint8List? proofJpeg,
  int maxWidth = ReceiptProofRaster.dots80mm,
}) {
  img.Image? receipt = img.decodeImage(receiptPng);
  if (receipt == null || receipt.width <= 0) {
    throw StateError('Could not decode receipt preview');
  }
  img.Image canvas = img.grayscale(_resizeToWidth(receipt, maxWidth));

  return Uint8List.fromList(img.encodePng(canvas));
}
