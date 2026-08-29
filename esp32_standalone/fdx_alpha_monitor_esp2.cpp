/**
 * Standalone ESP32-2 sketch — UART bridge onto office Wi-Fi
 *
 * NOT part of the Flutter app. Compile this file ALONE
 * (do not compile together with fdx_alpha_monitor.cpp).
 * Open in Arduino IDE (rename to .ino if needed) or PlatformIO.
 *
 * Board: ESP32  (this is ESP32-2)
 * USB Serial (monitor): 115200
 * UART2 RX only: GPIO 16  (match ESP32-1 TX GPIO 17)
 *
 * Wiring (3.3 V UART, common GND):
 *   ESP32-1 GPIO 17 (TX2)  ->  ESP32-2 GPIO 16 (RX2)
 *   ESP32-1 GND            ->  ESP32-2 GND
 *
 * Relay module (single channel, typically active-LOW IN):
 *   VCC  ->  3V3  (preferred on 30-pin ESP32; VIN 5 V + 3.3 V GPIO
 *            often keeps the relay stuck ON)
 *   GND  ->  GND
 *   IN   ->  GPIO 27  (open-drain so a 5 V module can still turn OFF)
 * Capacitive touch (finger on the metal pad — do not short to GND):
 *   GPIO 13 (T4)  ->  relay ON
 *   GPIO 14 (T6)  ->  relay OFF
 * App TCP commands:  RELAY ON   /   RELAY OFF
 * Status line:       RELAY,STATE:ON,SRC:APP|GPIO13|GPIO14
 *
 * Wi-Fi STA  ->  SSID FDX-MUXTRONICS
 * TCP server ->  this board's IP, port 9877
 *   (the router has no dispenser port; ESP32-2 listens so a laptop
 *    on the same SSID can connect later. Confirm Serial + TCP first.)
 *
 * Test without Flutter:
 *   1. Flash ESP32-1 (fdx_alpha_monitor.cpp) and ESP32-2 (this file).
 *   2. Wire TX2->RX2 and GND.
 *   3. Open ESP32-2 Serial Monitor at 115200 — look for [ESP32-2].
 *   4. Note the printed IP, then from a PC on FDX-MUXTRONICS:
 *        nc <ip> 9877
 *      or PuTTY raw TCP to that IP:9877
 */

#include <Arduino.h>
#include <WiFi.h>
#include <WiFiUdp.h>
#include <ctype.h>
#include <string.h>

static const char *kBoardTag = "ESP32-2";
static const char *kWifiSsid = "FDX-MUXTRONICS";
static const char *kWifiPass = "0614422322";

static const uint32_t kSerialBaud = 115200;
static const int kUart2RxPin = 16;
static const int kUart2TxPin = -1;
static const uint16_t kBridgePort = 9877;
static const int kRelayInPin = 27;
static const int kRelayOnPin = 13;
static const int kRelayOffPin = 14;
static const bool kRelayActiveLow = true;
static const uint32_t kTouchDebounceMs = 80;

static const uint32_t kPrintEveryMs = 1000;
static const uint32_t kWifiRetryMs = 10000;
static const uint32_t kWifiGiveUpMs = 15000;
static const uint32_t kUartStaleMs = 5000;
static const size_t kUartLineCap = 256;
static const size_t kTcpClientCap = 4;

WiFiServer server(kBridgePort);
WiFiClient clients[kTcpClientCap];
WiFiUDP udp;

String uartLine;
char lastUartLine[kUartLineCap] = "(none yet)";
uint32_t lastUartMs = 0;
uint32_t lastPrintMs = 0;
uint32_t lastWifiTryMs = 0;
uint32_t uartLineCount = 0;
bool udpReady = false;
bool tcpServerStarted = false;
uint8_t lastWifiStatus = 255;
bool relayOn = false;
char lastRelaySrc[12] = "BOOT";
String tcpCmdBuf[kTcpClientCap];
bool lastOnTouched = false;
bool lastOffTouched = false;
uint32_t lastOnTouchMs = 0;
uint32_t lastOffTouchMs = 0;
uint32_t touchOnBase = 70;
uint32_t touchOffBase = 70;
bool touchCalAfterWifi = false;

static void emitUsb(const char *line) {
  Serial.print("[");
  Serial.print(kBoardTag);
  Serial.print("] ");
  Serial.println(line);
}

static const char *wifiStatusName(wl_status_t status) {
  switch (status) {
    case WL_IDLE_STATUS:
      return "IDLE";
    case WL_NO_SSID_AVAIL:
      return "NO_SSID";
    case WL_SCAN_COMPLETED:
      return "SCAN_DONE";
    case WL_CONNECTED:
      return "CONNECTED";
    case WL_CONNECT_FAILED:
      return "CONNECT_FAILED";
    case WL_CONNECTION_LOST:
      return "CONNECTION_LOST";
    case WL_DISCONNECTED:
      return "DISCONNECTED";
    default:
      return "UNKNOWN";
  }
}

static void logWifiStatusIfChanged() {
  const uint8_t status = (uint8_t)WiFi.status();
  if (status == lastWifiStatus) {
    return;
  }
  lastWifiStatus = status;
  char msg[128];
  snprintf(msg, sizeof(msg), "Wi-Fi status changed: %u (%s)", (unsigned)status,
           wifiStatusName((wl_status_t)status));
  emitUsb(msg);
}

static void startWifiJoin() {
  emitUsb("Wi-Fi disconnect + begin (STA, sleep off)");
  WiFi.disconnect(true);
  delay(100);
  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.begin(kWifiSsid, kWifiPass);
  lastWifiTryMs = millis();
}

static bool wifiNeedsRetry(wl_status_t status) {
  return status == WL_DISCONNECTED || status == WL_CONNECT_FAILED ||
         status == WL_NO_SSID_AVAIL || status == WL_CONNECTION_LOST;
}

static void startTcpServerOnce() {
  if (tcpServerStarted) {
    return;
  }
  server.begin();
  server.setNoDelay(true);
  tcpServerStarted = true;
  char msg[96];
  snprintf(msg, sizeof(msg), "TCP server started on %s:%u",
           WiFi.localIP().toString().c_str(), (unsigned)kBridgePort);
  emitUsb(msg);
}

static int connectedClientCount() {
  int n = 0;
  for (size_t i = 0; i < kTcpClientCap; i++) {
    if (clients[i] && clients[i].connected()) {
      n++;
    }
  }
  return n;
}

static void acceptClients() {
  if (!tcpServerStarted || WiFi.status() != WL_CONNECTED) {
    return;
  }
  WiFiClient incoming = server.accept();
  if (!incoming) {
    return;
  }
  for (size_t i = 0; i < kTcpClientCap; i++) {
    if (!clients[i] || !clients[i].connected()) {
      clients[i].stop();
      clients[i] = incoming;
      clients[i].setNoDelay(true);
      char hello[96];
      snprintf(hello, sizeof(hello), "%s TCP ready  uart_lines=%lu", kBoardTag,
               (unsigned long)uartLineCount);
      clients[i].println(hello);
      snprintf(hello, sizeof(hello), "RELAY,STATE:%s,SRC:%s",
               relayOn ? "ON" : "OFF", lastRelaySrc);
      clients[i].println(hello);
      tcpCmdBuf[i] = "";
      emitUsb("TCP client connected");
      return;
    }
  }
  incoming.println("busy");
  incoming.stop();
  emitUsb("TCP client rejected (slots full)");
}

static void pruneClients() {
  for (size_t i = 0; i < kTcpClientCap; i++) {
    if (clients[i] && !clients[i].connected()) {
      clients[i].stop();
    }
  }
}

static void sendToTcp(const char *line) {
  for (size_t i = 0; i < kTcpClientCap; i++) {
    if (!clients[i] || !clients[i].connected()) {
      continue;
    }
    clients[i].println(line);
  }
}

static void sendToUdp(const char *line) {
  if (!udpReady || WiFi.status() != WL_CONNECTED) {
    return;
  }
  IPAddress bcast = WiFi.localIP();
  bcast[3] = 255;
  udp.beginPacket(bcast, kBridgePort);
  udp.print(line);
  udp.print("\n");
  udp.endPacket();
}

static void fanout(const char *line) {
  emitUsb(line);
  sendToTcp(line);
  sendToUdp(line);
}

static void writeRelayPin(bool on) {
  const bool levelHigh = kRelayActiveLow ? !on : on;
  digitalWrite(kRelayInPin, levelHigh ? HIGH : LOW);
}

static void applyRelay(bool on, const char *src) {
  relayOn = on;
  strncpy(lastRelaySrc, src, sizeof(lastRelaySrc) - 1);
  lastRelaySrc[sizeof(lastRelaySrc) - 1] = '\0';
  writeRelayPin(on);
  char line[96];
  snprintf(line, sizeof(line), "RELAY,STATE:%s,SRC:%s,PIN%d=%s", on ? "ON" : "OFF",
           src, kRelayInPin, digitalRead(kRelayInPin) ? "H" : "L");
  fanout(line);
}

static void handleCommand(const char *raw) {
  char cmd[48];
  size_t n = 0;
  for (size_t i = 0; raw[i] != '\0' && n + 1 < sizeof(cmd); i++) {
    const char c = raw[i];
    if (c == '\r' || c == '\n') {
      continue;
    }
    cmd[n++] = (char)toupper((unsigned char)c);
  }
  cmd[n] = '\0';
  if (strcmp(cmd, "RELAY ON") == 0 || strcmp(cmd, "RELAYON") == 0) {
    applyRelay(true, "APP");
  } else if (strcmp(cmd, "RELAY OFF") == 0 || strcmp(cmd, "RELAYOFF") == 0) {
    applyRelay(false, "APP");
  } else if (n > 0) {
    char msg[72];
    snprintf(msg, sizeof(msg), "CMD ignore: %s", cmd);
    emitUsb(msg);
  }
}

static uint32_t readTouchPad(int pin) {
  return (uint32_t)touchRead((uint8_t)pin);
}

static bool padTouched(uint32_t raw, uint32_t base) {
  if (base < 30) {
    return false;
  }
  return raw * 5 < base * 4;
}

static void calibrateTouchPads() {
  (void)readTouchPad(kRelayOnPin);
  (void)readTouchPad(kRelayOffPin);
  delay(40);
  uint32_t sumOn = 0;
  uint32_t sumOff = 0;
  for (int i = 0; i < 24; i++) {
    sumOn += readTouchPad(kRelayOnPin);
    sumOff += readTouchPad(kRelayOffPin);
    delay(8);
  }
  touchOnBase = sumOn / 24;
  touchOffBase = sumOff / 24;
  lastOnTouched = false;
  lastOffTouched = false;
}

static void pollRelayButtons() {
  const uint32_t now = millis();
  const uint32_t rawOn = readTouchPad(kRelayOnPin);
  const uint32_t rawOff = readTouchPad(kRelayOffPin);
  const bool onTouched = padTouched(rawOn, touchOnBase);
  const bool offTouched = padTouched(rawOff, touchOffBase);

  if (!onTouched) {
    touchOnBase = (touchOnBase * 7 + rawOn) / 8;
  }
  if (!offTouched) {
    touchOffBase = (touchOffBase * 7 + rawOff) / 8;
  }

  if (onTouched != lastOnTouched && (now - lastOnTouchMs) >= kTouchDebounceMs) {
    lastOnTouched = onTouched;
    lastOnTouchMs = now;
    if (onTouched) {
      applyRelay(true, "GPIO13");
    }
  }
  if (offTouched != lastOffTouched &&
      (now - lastOffTouchMs) >= kTouchDebounceMs) {
    lastOffTouched = offTouched;
    lastOffTouchMs = now;
    if (offTouched) {
      applyRelay(false, "GPIO14");
    }
  }
}

static void handleCmdByte(size_t slot, char c) {
  if (c == '\r') {
    return;
  }
  if (c == '\n') {
    if (tcpCmdBuf[slot].length() > 0) {
      handleCommand(tcpCmdBuf[slot].c_str());
      tcpCmdBuf[slot] = "";
    }
    return;
  }
  if (tcpCmdBuf[slot].length() >= 47) {
    tcpCmdBuf[slot] = "";
  }
  tcpCmdBuf[slot] += c;
}

static void readTcpCommands() {
  for (size_t i = 0; i < kTcpClientCap; i++) {
    if (!clients[i] || !clients[i].connected()) {
      continue;
    }
    while (clients[i].available() > 0) {
      handleCmdByte(i, (char)clients[i].read());
    }
  }
}

static void readUsbCommands() {
  while (Serial.available() > 0) {
    static String usbBuf;
    const char c = (char)Serial.read();
    if (c == '\r') {
      continue;
    }
    if (c == '\n') {
      if (usbBuf.length() > 0) {
        handleCommand(usbBuf.c_str());
        usbBuf = "";
      }
      continue;
    }
    if (usbBuf.length() >= 47) {
      usbBuf = "";
    }
    usbBuf += c;
  }
}

static void ensureWifi() {
  logWifiStatusIfChanged();
  const wl_status_t status = WiFi.status();

  if (status == WL_CONNECTED) {
    if (!udpReady) {
      udp.begin(kBridgePort);
      udpReady = true;
      char msg[128];
      snprintf(msg, sizeof(msg), "Wi-Fi connected  IP %s  RSSI %d  SSID %s",
               WiFi.localIP().toString().c_str(), WiFi.RSSI(), kWifiSsid);
      emitUsb(msg);
    }
    startTcpServerOnce();
    if (!touchCalAfterWifi) {
      calibrateTouchPads();
      touchCalAfterWifi = true;
      emitUsb("Touch pads recalibrated after Wi-Fi");
    }
    return;
  }

  udpReady = false;

  const uint32_t now = millis();
  const bool connecting =
      (status == WL_IDLE_STATUS || status == WL_SCAN_COMPLETED);
  if (connecting && (now - lastWifiTryMs) < kWifiGiveUpMs) {
    return;
  }
  if ((now - lastWifiTryMs) < kWifiRetryMs) {
    return;
  }
  if (!wifiNeedsRetry(status) && !connecting) {
    return;
  }

  char msg[128];
  snprintf(msg, sizeof(msg), "Wi-Fi retry (status=%u %s) SSID=%s",
           (unsigned)status, wifiStatusName(status), kWifiSsid);
  emitUsb(msg);
  startWifiJoin();
}

static void handleUartByte(char c) {
  if (c == '\r') {
    return;
  }
  if (c == '\n') {
    if (uartLine.length() == 0) {
      return;
    }
    uartLine.toCharArray(lastUartLine, sizeof(lastUartLine));
    lastUartMs = millis();
    uartLineCount++;

    char tagged[kUartLineCap + 24];
    snprintf(tagged, sizeof(tagged), "%s UART %s", kBoardTag, lastUartLine);
    fanout(tagged);

    uartLine = "";
    return;
  }
  if (uartLine.length() >= kUartLineCap - 1) {
    uartLine = "";
  }
  uartLine += c;
}

static void readUart() {
  while (Serial2.available() > 0) {
    handleUartByte((char)Serial2.read());
  }
}

static void printSnapshot() {
  const uint32_t now = millis();
  if (now - lastPrintMs < kPrintEveryMs) {
    return;
  }
  lastPrintMs = now;

  const uint32_t sec = now / 1000;
  const uint32_t hh = (sec / 3600) % 24;
  const uint32_t mm = (sec / 60) % 60;
  const uint32_t ss = sec % 60;
  const bool uartFresh =
      lastUartMs != 0 && (now - lastUartMs) < kUartStaleMs;

  char line[220];

  fanout("---------- ESP32-2 BRIDGE ----------");
  snprintf(line, sizeof(line), "uptime      %02lu:%02lu:%02lu",
           (unsigned long)hh, (unsigned long)mm, (unsigned long)ss);
  fanout(line);
  if (WiFi.status() == WL_CONNECTED) {
    snprintf(line, sizeof(line), "wifi        %s  TCP/UDP port %u",
             WiFi.localIP().toString().c_str(), (unsigned)kBridgePort);
  } else {
    const wl_status_t st = WiFi.status();
    snprintf(line, sizeof(line), "wifi        offline status=%u (%s) SSID %s",
             (unsigned)st, wifiStatusName(st), kWifiSsid);
  }
  fanout(line);
  snprintf(line, sizeof(line), "tcp clients %d", connectedClientCount());
  fanout(line);
  snprintf(line, sizeof(line), "uart gpio   RX %d  lines %lu  %s", kUart2RxPin,
           (unsigned long)uartLineCount, uartFresh ? "LIVE" : "waiting for ESP32-1");
  fanout(line);
  snprintf(line, sizeof(line), "uart last   %s", lastUartLine);
  fanout(line);
  snprintf(line, sizeof(line), "relay       %s  src %s  IN GPIO %d",
           relayOn ? "ON" : "OFF", lastRelaySrc, kRelayInPin);
  fanout(line);
  snprintf(line, sizeof(line), "touch       T4/13=%lu/%lu  T6/14=%lu/%lu",
           (unsigned long)readTouchPad(kRelayOnPin), (unsigned long)touchOnBase,
           (unsigned long)readTouchPad(kRelayOffPin),
           (unsigned long)touchOffBase);
  fanout(line);
  fanout("------------------------------------");
}

void setup() {
  Serial.begin(kSerialBaud);
  Serial2.begin(kSerialBaud, SERIAL_8N1, kUart2RxPin, kUart2TxPin);
  pinMode(kRelayInPin, OUTPUT_OPEN_DRAIN);
  writeRelayPin(false);
  delay(200);
  calibrateTouchPads();

  Serial.println();
  emitUsb("boot");
  emitUsb("This board is ESP32-2 (UART RX + office Wi-Fi bridge)");
  char pinMsg[72];
  snprintf(pinMsg, sizeof(pinMsg), "UART2 RX on GPIO %d at %lu baud",
           kUart2RxPin, (unsigned long)kSerialBaud);
  emitUsb(pinMsg);
  emitUsb("Wire ESP32-1 GPIO 17 TX -> this GPIO 16 RX, and share GND");
  char touchMsg[96];
  snprintf(touchMsg, sizeof(touchMsg),
           "Cap touch ON=GPIO13/T4 base %u  OFF=GPIO14/T6 base %u",
           (unsigned)touchOnBase, (unsigned)touchOffBase);
  emitUsb(touchMsg);
  emitUsb("Relay IN GPIO 27 (open-drain). Prefer VCC to 3V3, not VIN.");
  emitUsb("Relay click test ON 400ms — listen for the click");
  applyRelay(true, "BOOT");
  delay(400);
  applyRelay(false, "BOOT");

  WiFi.mode(WIFI_STA);
  WiFi.disconnect(true);
  delay(100);
  WiFi.setSleep(false);
  WiFi.begin(kWifiSsid, kWifiPass);
  lastWifiTryMs = millis();
  emitUsb("Wi-Fi STA join started; TCP server waits for IP");
}

void loop() {
  readUart();
  readUsbCommands();
  pollRelayButtons();
  ensureWifi();
  acceptClients();
  pruneClients();
  readTcpCommands();
  printSnapshot();
}
