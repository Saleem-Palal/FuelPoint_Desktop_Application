import '../domain/esp32_bridge_models.dart';

final RegExp _fdxCompact = RegExp(
  r'FDX,AMT:(-?\d+(?:\.\d+)?),VOL:(-?\d+(?:\.\d+)?),RATE:(-?\d+(?:\.\d+)?),'
  r'MTR:(-?\d+(?:\.\d+)?),STS:([^,]*),PRD:([^,]*),TIME:(\S+)',
);

Esp32BridgeSnapshot applyEsp32BridgeLine(
  Esp32BridgeSnapshot current,
  String rawLine,
) {
  final String line = rawLine.trim();
  if (line.isEmpty) {
    return current;
  }

  Esp32BridgeSnapshot next = current;
  final String lower = line.toLowerCase();
  final bool fromEsp1 = lower.startsWith('esp32-2 uart');
  final String payload = fromEsp1
      ? line.substring(line.toLowerCase().indexOf('uart') + 4).trim()
      : line;
  final String payloadLower = payload.toLowerCase();

  final Match? fdx = _fdxCompact.firstMatch(line);
  if (fdx != null) {
    next = next.copyWith(
      haveFdx: true,
      waitingType33: false,
      amount: double.tryParse(fdx.group(1) ?? ''),
      volume: double.tryParse(fdx.group(2) ?? ''),
      rate: double.tryParse(fdx.group(3) ?? ''),
      meter: double.tryParse(fdx.group(4) ?? ''),
      status: fdx.group(5)?.trim(),
      product: fdx.group(6)?.trim(),
      time: fdx.group(7)?.trim(),
      lastUartLine: line,
    );
  }

  if (lower.contains('uart gpio') && lower.contains('live')) {
    next = next.copyWith(uartLive: true, uartWaiting: false);
  } else if (lower.contains('waiting for esp32-1')) {
    next = next.copyWith(uartLive: false, uartWaiting: true);
  }

  final Match? linesMatch = RegExp(
    r'lines\s+(\d+)',
    caseSensitive: false,
  ).firstMatch(line);
  if (linesMatch != null) {
    next = next.copyWith(
      uartLineCount:
          int.tryParse(linesMatch.group(1) ?? '') ?? next.uartLineCount,
    );
  }

  if (payloadLower.startsWith('wifi')) {
    if (fromEsp1) {
      next = next.copyWith(dispenserWifi: _valueAfterLabel(payload, 'wifi'));
    } else if (!payloadLower.contains('offline') &&
        !payloadLower.contains('connecting')) {
      final Match? ip = RegExp(r'(\d{1,3}(?:\.\d{1,3}){3})').firstMatch(payload);
      if (ip != null) {
        next = next.copyWith(bridgeIp: ip.group(1));
      }
    }
  }

  if (fromEsp1 && payloadLower.startsWith('socket')) {
    next = next.copyWith(dispenserSocket: _valueAfterLabel(payload, 'socket'));
  }

  if (fromEsp1 && payloadLower.startsWith('live')) {
    final String live = _valueAfterLabel(payload, 'live');
    next = next.copyWith(
      dispenserLive: live,
      waitingType33: live.toLowerCase().contains('type-33'),
    );
  }

  if (lower.contains('uart last')) {
    next = next.copyWith(lastUartLine: line);
  }

  final Match? relayCompact = RegExp(
    r'RELAY,STATE:(ON|OFF)(?:,SRC:([A-Za-z0-9]+))?',
    caseSensitive: false,
  ).firstMatch(line);
  if (relayCompact != null) {
    next = next.copyWith(
      relayState: relayCompact.group(1)?.toUpperCase(),
      relaySource: relayCompact.group(2),
    );
  } else if (!fromEsp1 && payloadLower.startsWith('relay')) {
    final String value = _valueAfterLabel(payload, 'relay');
    final Match? snap = RegExp(
      r'(ON|OFF)(?:\s+src\s+(\S+))?',
      caseSensitive: false,
    ).firstMatch(value);
    if (snap != null) {
      next = next.copyWith(
        relayState: snap.group(1)?.toUpperCase(),
        relaySource: snap.group(2),
      );
    }
  }

  return next;
}

String _valueAfterLabel(String line, String label) {
  final int i = line.toLowerCase().indexOf(label);
  if (i < 0) {
    return line.trim();
  }
  return line.substring(i + label.length).trim();
}
