import 'dart:io';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:camera_windows/camera_windows.dart';
import 'package:flutter/foundation.dart';

/// `camera` 0.11 does not endorse Windows, so the Dart host must register
/// `camera_windows` or Pigeon calls fail with channel-error.
void ensureWindowsCameraPlugin() {
  if (kIsWeb || !Platform.isWindows) {
    return;
  }
  if (CameraPlatform.instance is CameraWindows) {
    return;
  }
  CameraWindows.registerWith();
}

String friendlyWebcamError(Object error) {
  final String raw = '$error';
  if (raw.contains('channel-error') || raw.contains('getAvailableCameras')) {
    return 'Webcam plugin did not load. Fully quit the app and run it again '
        '(hot reload cannot attach the camera).';
  }
  if (raw.contains('No webcam')) {
    return 'No USB webcam was found. Plug one in and retry.';
  }
  return 'Could not open the webcam. Make sure it is plugged in and not used '
      'by another app.';
}
