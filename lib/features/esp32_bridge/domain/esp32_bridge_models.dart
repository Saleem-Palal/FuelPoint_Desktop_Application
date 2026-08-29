class Esp32BridgeSnapshot {
  const Esp32BridgeSnapshot({
    this.amount,
    this.volume,
    this.rate,
    this.meter,
    this.status,
    this.product,
    this.time,
    this.uartLive = false,
    this.uartWaiting = true,
    this.uartLineCount = 0,
    this.lastUartLine,
    this.bridgeIp,
    this.haveFdx = false,
    this.dispenserWifi,
    this.dispenserSocket,
    this.dispenserLive,
    this.waitingType33 = false,
    this.relayState,
    this.relaySource,
  });

  final double? amount;
  final double? volume;
  final double? rate;
  final double? meter;
  final String? status;
  final String? product;
  final String? time;
  final bool uartLive;
  final bool uartWaiting;
  final int uartLineCount;
  final String? lastUartLine;
  final String? bridgeIp;
  final bool haveFdx;
  final String? dispenserWifi;
  final String? dispenserSocket;
  final String? dispenserLive;
  final bool waitingType33;
  final String? relayState;
  final String? relaySource;

  static const Esp32BridgeSnapshot empty = Esp32BridgeSnapshot();

  Esp32BridgeSnapshot copyWith({
    double? amount,
    double? volume,
    double? rate,
    double? meter,
    String? status,
    String? product,
    String? time,
    bool? uartLive,
    bool? uartWaiting,
    int? uartLineCount,
    String? lastUartLine,
    String? bridgeIp,
    bool? haveFdx,
    String? dispenserWifi,
    String? dispenserSocket,
    String? dispenserLive,
    bool? waitingType33,
    String? relayState,
    String? relaySource,
  }) {
    return Esp32BridgeSnapshot(
      amount: amount ?? this.amount,
      volume: volume ?? this.volume,
      rate: rate ?? this.rate,
      meter: meter ?? this.meter,
      status: status ?? this.status,
      product: product ?? this.product,
      time: time ?? this.time,
      uartLive: uartLive ?? this.uartLive,
      uartWaiting: uartWaiting ?? this.uartWaiting,
      uartLineCount: uartLineCount ?? this.uartLineCount,
      lastUartLine: lastUartLine ?? this.lastUartLine,
      bridgeIp: bridgeIp ?? this.bridgeIp,
      haveFdx: haveFdx ?? this.haveFdx,
      dispenserWifi: dispenserWifi ?? this.dispenserWifi,
      dispenserSocket: dispenserSocket ?? this.dispenserSocket,
      dispenserLive: dispenserLive ?? this.dispenserLive,
      waitingType33: waitingType33 ?? this.waitingType33,
      relayState: relayState ?? this.relayState,
      relaySource: relaySource ?? this.relaySource,
    );
  }
}
