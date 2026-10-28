/**
 * Board: ESP32 Dev Module / 38-pin
 * USB Serial monitor: 115200 on UART0 (GPIO1 TX / GPIO3 RX on-chip — tied to CP2102).
 * Do NOT wire FDX to GPIO1/3: the USB bridge loads those pins; uart=STALL rx/s=0.
 *
 * --- Power rails (station harness) ---
 * Right rail: 5 V from LM2596 (MAX98357 VIN, etc.)
 * Left rail:  3.3 V (INMP441 VDD, relay VCC per notes below)
 * Ground rail: common GND for all modules and FDX.
 *
 * --- MAX98357A I2S amplifier (4 Ω 5 W speaker, +/− direct to amp outputs) ---
 * VIN  -> 5 V right rail (LM2596)
 * GND  -> ground rail
 * DIN  -> GPIO 22 (data)
 * LRC  -> GPIO 26 (word / LR clock)
 * BCLK -> GPIO 27 (bit clock)
 *
 * --- INMP441 MEMS microphone ---
 * VDD  -> 3.3 V left rail
 * GND  -> ground rail
 * L/R  -> ground rail (left channel)
 * SD   -> GPIO 32 (data)
 * WS   -> GPIO 25 (word select)
 * SCK  -> GPIO 33 (bit clock)
 *
 * --- Helper talk (PTT), half-duplex with intercom above ---
 * Leg 1 -> GPIO 18 (INPUT_PULLUP; pressed = LOW)
 * Leg 2 -> ground rail
 *
 * --- FDX telemetry / keypad (4800 8N1 on UART2 — see UART2_*_PIN below) ---
 * GPIO 14 (UART2 RX) <- FDX TX   (pump TX must land on ESP RX — swap = STALL / 0/0)
 * GPIO 15 (UART2 TX) -> FDX RX   (optional; live telemetry works RX-only)
 * GND                <-> FDX GND
 * Alternates if one GPIO is damaged: 16/17 (legacy harness), never 1/3 on USB DevKit.
 * ESP-01 style header labels are the ESP module pins, not the pump MCU pin names.
 *
 * --- Keypad lock relay ---
 * GPIO 4 -> relay IN (LOCK = LOW, UNLOCK = HIGH on active-LOW Songle-style modules).
 * Relay VCC from 3.3 V left rail, not 5 V, or the green IN LED may never turn off.
 *
 * --- Buzzer ---
 * GPIO 5 -> buzzer + ; buzzer − -> GND
 * (Chirp while waiting for Confirm; solid if live-shift comms lost.)
 *
 * --- FDX reset relay (optional; firmware GPIO 21) ---
 * Active-LOW hold: OUTPUT LOW ~3 s on reset command, then float INPUT.
 *
 * Wi-Fi: station SSID (see WIFI_SSID / prefs)
 * Flutter: ws://192.168.0.1x0:81/   (x = UNIT_ID)
 *
 * Arduino libraries: WebSockets by Markus Sattler, LittleFS
 */

#ifndef UNIT_ID
#define UNIT_ID 1
#endif

#include <Arduino.h>
#include <LittleFS.h>
#include <Preferences.h>
#include <WebSocketsServer.h>
#include <WiFi.h>
#include <ctype.h>
#include <esp_task_wdt.h>
#include <esp_wifi.h>
#include <ESP_I2S.h>
#include <freertos/FreeRTOS.h>
#include <freertos/ringbuf.h>
#include <stdlib.h>
#include <string.h>

static const char *WIFI_SSID = "Ufone_006";
static const char *WIFI_PASS = "sadam_palal";
static char wifiSsid[33];
static char wifiPass[65];
static bool wifiAnnouncePending = false;
static String usbWifiLine;
static bool wifiConsumeText(const String &raw);

static const uint32_t USB_BAUD = 115200;
static const uint32_t UART2_BAUD = 4800;
static const int UART2_RX_PIN = 14;  // FDX TX -> ESP RX (not 1/3 — USB-UART DevKit)
static const int UART2_TX_PIN = 15;  // ESP TX -> FDX RX
static const int RELAY_PIN = 4;
static const int BUZZER_PIN = 5;
static const int FDX_RESET_PIN = 21;
static const uint32_t FDX_RESET_HOLD_MS = 3000;
// true  = IN LOW  locks keypad (most Songle "low-level trigger" boards)
// false = IN HIGH locks keypad (jumper set to H)
static const bool RELAY_ACTIVE_LOW = true;
static const uint32_t BUZZER_CYCLE_MS = 850;

static const uint32_t HEARTBEAT_LOCK_MS = 3000;
static const uint32_t UART_STALE_MS = 5000;
static const uint32_t WIFI_RETRY_MS = 8000;
static const uint32_t TICK_MS = 1000;
static const uint32_t LIVE_SNAP_MS = 1000;
static const size_t RX_MAX = 4096;
static const long ZERO_VOLUME_CENTS = 1;  // 0.01 L
static const int WDT_TIMEOUT_S = 15;
static const int TOKEN_LOG_CAP = 10;
static const size_t UART_BYTES_PER_LOOP = 512;

WebSocketsServer webSocket(81);
Preferences prefs;

String rxBuf;
bool haveLive = false;
bool wasPumping = false;
bool keypadLocked = true;
bool saleAwaitingConfirm = false;
bool shiftLive = false;
bool hadAppSession = false;
bool operatorLock = false;
bool pumpingSnapshotDirty = false;
bool noSaleFromType37 = false;
long lastPumpingVolumeCents = 0;

char productLabel[16] = "-";
char statusLabel[24] = "-";
bool fdxResetActive = false;
uint32_t fdxResetStartedMs = 0;
char macId[18] = "ESP";
char lastTxId[48] = "";
double totalAmount = 0;
double volumeLiters = 0;
double unitRate = 0;
double totalMeter = 0;
long amountCents = 0;
long volumeCents = 0;
long rateCents = 0;
long meterCents = 0;

uint32_t lastValidFrameMs = 0;
uint32_t lastUartRxMs = 0;
uint32_t uartRxBytesWindow = 0;
uint32_t lastAppHbMs = 0;
uint32_t lastWifiOkMs = 0;
uint32_t lastWifiTryMs = 0;
uint32_t lastTickMs = 0;
uint32_t lastLiveSnapMs = 0;
uint32_t nextSequence = 1;
char appClockIso[40] = "";
int wsClients = 0;
bool wsListening = false;

static void javaMid(const char *s, int start1, int len, char *out, size_t outSize) {
  const int start = start1 - 1;
  const int n = (int)strlen(s);
  out[0] = '\0';
  if (start < 0 || len <= 0 || start + len > n || (size_t)len + 1 > outSize) {
    return;
  }
  memcpy(out, s + start, (size_t)len);
  out[len] = '\0';
}

static bool javaHundredths(const char *s, int start1, int len, long *out) {
  char slice[16];
  javaMid(s, start1, len, slice, sizeof(slice));
  if (slice[0] == '\0') {
    return false;
  }
  char *end = NULL;
  *out = strtol(slice, &end, 10);
  return end != slice;
}

static void formatHundredths(char *buf, size_t n, long cents) {
  const char *sign = "";
  long mag = cents;
  if (mag < 0) {
    sign = "-";
    mag = -mag;
  }
  snprintf(buf, n, "%s%ld.%02ld", sign, mag / 100, mag % 100);
}

static void setProduct(char code) {
  switch (code) {
    case '0':
      strncpy(productLabel, "Petrol", sizeof(productLabel) - 1);
      break;
    case '1':
      strncpy(productLabel, "Diesel", sizeof(productLabel) - 1);
      break;
    case '2':
      strncpy(productLabel, "HOBC", sizeof(productLabel) - 1);
      break;
    case '3':
      strncpy(productLabel, "Kerosene", sizeof(productLabel) - 1);
      break;
    default:
      strncpy(productLabel, "-", sizeof(productLabel) - 1);
      break;
  }
  productLabel[sizeof(productLabel) - 1] = '\0';
}

static void setStatus(char code) {
  switch (code) {
    case '5':
      strncpy(statusLabel, "Active / Pumping", sizeof(statusLabel) - 1);
      break;
    case '0':
      strncpy(statusLabel, "Idle", sizeof(statusLabel) - 1);
      break;
    case 'P':
    case 'p':
      strncpy(statusLabel, "Rupees preset", sizeof(statusLabel) - 1);
      break;
    case 'L':
    case 'l':
      strncpy(statusLabel, "Liters preset", sizeof(statusLabel) - 1);
      break;
    default:
      strncpy(statusLabel, "-", sizeof(statusLabel) - 1);
      break;
  }
  statusLabel[sizeof(statusLabel) - 1] = '\0';
}

static void writeRelay(bool locked) {
  pinMode(RELAY_PIN, OUTPUT);
  const bool pinHigh = RELAY_ACTIVE_LOW ? !locked : locked;
  digitalWrite(RELAY_PIN, pinHigh ? HIGH : LOW);
}

static void writeBuzzer(bool on) {
  digitalWrite(BUZZER_PIN, on ? HIGH : LOW);
}

static bool commsLive() {
  if (wsClients <= 0) {
    return false;
  }
  return (millis() - lastAppHbMs) <= HEARTBEAT_LOCK_MS;
}

static bool uartLinkLive() {
  const uint32_t now = millis();
  if (lastValidFrameMs != 0 && (now - lastValidFrameMs) <= UART_STALE_MS) {
    return true;
  }
  // Bytes on RX even if the payload is not a decoded Type-33 yet.
  return lastUartRxMs != 0 && (now - lastUartRxMs) <= UART_STALE_MS;
}

static bool keypadShouldLock() {
  if (!commsLive()) {
    return true;
  }
  if (!shiftLive) {
    return true;
  }
  if (saleAwaitingConfirm || operatorLock) {
    return true;
  }
  return false;
}

static const char *lockReason() {
  if (!commsLive()) {
    return "no-app";
  }
  if (!shiftLive) {
    return "shift-off";
  }
  if (saleAwaitingConfirm) {
    return "wait-confirm";
  }
  if (operatorLock) {
    return "operator";
  }
  return "unlocked";
}

static void setKeypadLocked(bool locked) {
  if (keypadLocked == locked) {
    return;
  }
  keypadLocked = locked;
  writeRelay(locked);
  Serial.printf("GPIO4 relay %s (%s) pin=%s\n", locked ? "LOCK" : "UNLOCK",
                lockReason(), digitalRead(RELAY_PIN) ? "HIGH" : "LOW");
}

static void applySessionLock() { setKeypadLocked(keypadShouldLock()); }

static void fdxResetRelease() {
  pinMode(FDX_RESET_PIN, INPUT);
  fdxResetActive = false;
}

static void fdxResetBegin() {
  if (fdxResetActive) {
    return;
  }
  pinMode(FDX_RESET_PIN, OUTPUT);
  digitalWrite(FDX_RESET_PIN, LOW);
  fdxResetActive = true;
  fdxResetStartedMs = millis();
  Serial.println("GPIO21 reset hold start");
}

static void serviceFdxReset() {
  if (!fdxResetActive) {
    pinMode(FDX_RESET_PIN, INPUT);
    return;
  }
  if ((millis() - fdxResetStartedMs) >= FDX_RESET_HOLD_MS) {
    fdxResetRelease();
    Serial.println("GPIO21 reset hold end");
  }
}

static void relaySelfTest() {
  Serial.println("GPIO4 relay self-test: LED should blink twice");
  keypadLocked = false;
  writeRelay(true);
  delay(350);
  writeRelay(false);
  delay(350);
  writeRelay(true);
  delay(350);
  writeRelay(false);
  delay(350);
}

/// Payment wait = chirp. Live-shift comms loss = solid ON. Else off.
static void serviceBuzzer() {
  if (!commsLive() && hadAppSession && shiftLive) {
    writeBuzzer(true);
    return;
  }
  if (saleAwaitingConfirm && commsLive()) {
    const uint32_t t = millis() % BUZZER_CYCLE_MS;
    const bool on = (t < 140) || (t >= 230 && t < 370);
    writeBuzzer(on);
    return;
  }
  writeBuzzer(false);
}

static bool appSessionLive() { return commsLive() && shiftLive; }

static void sanitize(String &inner) {
  String clean;
  clean.reserve(inner.length());
  for (size_t i = 0; i < inner.length(); i++) {
    const char c = inner[i];
    if (c == '<' || c == '>' || isspace((unsigned char)c)) {
      continue;
    }
    clean += c;
  }
  inner = clean;
}

static uint32_t tokenForSequence(uint32_t sequence) {
  return (uint32_t)UNIT_ID * 100000UL + sequence;
}

static bool tokenLogHas(uint32_t token) {
  if (!LittleFS.exists("/tokenlog.json")) {
    return false;
  }
  File f = LittleFS.open("/tokenlog.json", "r");
  if (!f) {
    return false;
  }
  char needle[40];
  snprintf(needle, sizeof(needle), "\"token\":%lu", (unsigned long)token);
  bool found = false;
  while (f.available()) {
    String line = f.readStringUntil('\n');
    if (line.indexOf(needle) >= 0) {
      found = true;
      break;
    }
  }
  f.close();
  return found;
}

static int tokenLogCount() {
  if (!LittleFS.exists("/tokenlog.json")) {
    return 0;
  }
  File f = LittleFS.open("/tokenlog.json", "r");
  if (!f) {
    return 0;
  }
  int n = 0;
  while (f.available()) {
    String line = f.readStringUntil('\n');
    line.trim();
    if (line.length() > 8) {
      n++;
    }
  }
  f.close();
  return n;
}

static void rewriteTokenLog(const String &kept) {
  File out = LittleFS.open("/tokenlog.json", "w");
  if (!out) {
    return;
  }
  out.print(kept);
  out.close();
}

static void appendTokenLogLine(const String &line) {
  String kept;
  int n = 0;
  if (LittleFS.exists("/tokenlog.json")) {
    File in = LittleFS.open("/tokenlog.json", "r");
    if (in) {
      while (in.available()) {
        String row = in.readStringUntil('\n');
        row.trim();
        if (row.length() > 8) {
          n++;
          kept += row;
          kept += '\n';
        }
      }
      in.close();
    }
  }
  while (n >= TOKEN_LOG_CAP) {
    const int nl = kept.indexOf('\n');
    if (nl < 0) {
      kept = "";
      n = 0;
      break;
    }
    kept = kept.substring(nl + 1);
    n--;
  }
  kept += line;
  kept += '\n';
  rewriteTokenLog(kept);
}

static void enqueueTokenSale() {
  const uint32_t token = tokenForSequence(nextSequence);
  if (tokenLogHas(token)) {
    snprintf(lastTxId, sizeof(lastTxId), "%lu", (unsigned long)token);
    return;
  }
  nextSequence += 1;
  prefs.putUInt("nextSeq", nextSequence);
  char amt[24], lit[24], rateBuf[24], meter[24];
  formatHundredths(amt, sizeof(amt), amountCents);
  formatHundredths(lit, sizeof(lit), lastPumpingVolumeCents > 0
                                         ? lastPumpingVolumeCents
                                         : volumeCents);
  formatHundredths(rateBuf, sizeof(rateBuf), rateCents);
  formatHundredths(meter, sizeof(meter), meterCents);
  const char *stamp = appClockIso[0] ? appClockIso : "";
  char line[512];
  snprintf(line, sizeof(line),
           "{\"token\":%lu,\"unit\":%d,\"at\":\"%s\",\"amount\":%s,"
           "\"liters\":%s,\"rate\":%s,\"meter\":%s,\"synced\":false}",
           (unsigned long)token, UNIT_ID, stamp, amt, lit, rateBuf, meter);
  appendTokenLogLine(String(line));
  snprintf(lastTxId, sizeof(lastTxId), "%lu", (unsigned long)token);
}

static void ackToken(uint32_t token) {
  if (!LittleFS.exists("/tokenlog.json")) {
    return;
  }
  File in = LittleFS.open("/tokenlog.json", "r");
  if (!in) {
    return;
  }
  String kept;
  char needle[40];
  snprintf(needle, sizeof(needle), "\"token\":%lu", (unsigned long)token);
  while (in.available()) {
    String line = in.readStringUntil('\n');
    line.trim();
    if (line.length() < 8) {
      continue;
    }
    if (line.indexOf(needle) >= 0) {
      line.replace("\"synced\":false", "\"synced\":true");
    }
    kept += line;
    kept += '\n';
  }
  in.close();
  rewriteTokenLog(kept);
}

static String buildSyncLogJson() {
  String body = "{\"cmd\":\"SYNC_LOG\",\"unit\":";
  body += String(UNIT_ID);
  body += ",\"rows\":[";
  bool first = true;
  if (LittleFS.exists("/tokenlog.json")) {
    File f = LittleFS.open("/tokenlog.json", "r");
    if (f) {
      while (f.available()) {
        String line = f.readStringUntil('\n');
        line.trim();
        if (line.length() <= 8) {
          continue;
        }
        if (!first) {
          body += ",";
        }
        first = false;
        body += line;
      }
      f.close();
    }
  }
  body += "]}";
  return body;
}

static void sendSyncLog(uint8_t client) {
  String json = buildSyncLogJson();
  webSocket.sendTXT(client, json.c_str());
}

static void broadcastSyncLog() {
  String json = buildSyncLogJson();
  webSocket.broadcastTXT(json.c_str());
}

static void writeLiveSnapshot() {
  File f = LittleFS.open("/live.json", "w");
  if (!f) {
    return;
  }
  char amt[24], lit[24], rateBuf[24], meter[24];
  formatHundredths(amt, sizeof(amt), amountCents);
  formatHundredths(lit, sizeof(lit), volumeCents);
  formatHundredths(rateBuf, sizeof(rateBuf), rateCents);
  formatHundredths(meter, sizeof(meter), meterCents);
  char line[384];
  snprintf(line, sizeof(line),
           "{\"pumping\":true,\"amount\":%s,\"liters\":%s,\"rate\":%s,"
           "\"meter\":%s,\"amount_cents\":%ld,\"liter_cents\":%ld,"
           "\"rate_cents\":%ld,\"meter_cents\":%ld,\"product\":\"%s\"}",
           amt, lit, rateBuf, meter, amountCents, volumeCents, rateCents,
           meterCents, productLabel);
  f.print(line);
  f.close();
}

static void clearLiveSnapshot() { LittleFS.remove("/live.json"); }

static void recoverLiveSnapshot() {
  if (!LittleFS.exists("/live.json")) {
    return;
  }
  File f = LittleFS.open("/live.json", "r");
  if (!f) {
    return;
  }
  String raw = f.readString();
  f.close();
  if (raw.indexOf("\"pumping\":true") < 0) {
    LittleFS.remove("/live.json");
    return;
  }
  haveLive = true;
  wasPumping = true;
  const int litAt = raw.indexOf("\"liter_cents\":");
  if (litAt >= 0) {
    lastPumpingVolumeCents = strtol(raw.c_str() + litAt + 14, NULL, 10);
    volumeCents = lastPumpingVolumeCents;
  }
}

static String buildTelemetryJson(const char *cmd, const char *txId) {
  char amt[24], lit[24], rateBuf[24], meter[24];
  formatHundredths(amt, sizeof(amt), amountCents);
  formatHundredths(lit, sizeof(lit), volumeCents);
  formatHundredths(rateBuf, sizeof(rateBuf), rateCents);
  formatHundredths(meter, sizeof(meter), meterCents);
  char buf[768];
  snprintf(buf, sizeof(buf),
           "{\"unit\":%d,\"cmd\":\"%s\",\"tx_id\":\"%s\","
           "\"system\":{\"uptime_sec\":%lu,\"wifi_rssi\":%d,\"pending_tx_count\":%d},"
           "\"status_flags\":{\"esp_to_board_link\":%s,\"keypad_locked\":%s},"
           "\"telemetry\":{\"amount\":%s,\"liters\":%s,\"rate\":%s,"
           "\"meter\":%s,\"amount_cents\":%ld,\"liter_cents\":%ld,"
           "\"rate_cents\":%ld,\"meter_cents\":%ld,"
           "\"status\":\"%s\",\"product\":\"%s\"}}",
           UNIT_ID, cmd && cmd[0] ? cmd : "TELEMETRY", txId ? txId : "",
           (unsigned long)(millis() / 1000), WiFi.RSSI(), tokenLogCount(),
           uartLinkLive() ? "true" : "false",
           keypadLocked ? "true" : "false", amt, lit, rateBuf, meter,
           amountCents, volumeCents, rateCents, meterCents,
           statusLabel, productLabel);
  return String(buf);
}

static void broadcastJson(String json) {
  if (wsClients <= 0) {
    return;
  }
  webSocket.broadcastTXT(json.c_str());
}

static void sendHello(uint8_t client) {
  sendSyncLog(client);
  String hello = buildTelemetryJson("TELEMETRY", lastTxId);
  webSocket.sendTXT(client, hello.c_str());
}

static void onZeroHangup() {
  saleAwaitingConfirm = false;
  noSaleFromType37 = false;
  lastPumpingVolumeCents = 0;
  clearLiveSnapshot();
  applySessionLock();
  broadcastJson(buildTelemetryJson("NO_SALE", lastTxId));
  Serial.printf("hang-up 0 L (idle LCD last sale) — no lock/buzzer gpio4=%s\n",
                digitalRead(RELAY_PIN) ? "HIGH" : "LOW");
}

static void onPumpingIdleEdge() {
  // Idle Type-33 redisplays the last sale. Use last pumping liters, not LCD.
  const bool zeroHangup =
      noSaleFromType37 || lastPumpingVolumeCents < ZERO_VOLUME_CENTS;
  Serial.printf("pumping->idle lastPump=%ld idle=%ld %s\n", lastPumpingVolumeCents,
                volumeCents, zeroHangup ? "NO_SALE" : "SALE");
  if (zeroHangup) {
    onZeroHangup();
    return;
  }
  saleAwaitingConfirm = true;
  setKeypadLocked(true);
  enqueueTokenSale();
  clearLiveSnapshot();
  broadcastJson(buildTelemetryJson("SALE_COMPLETE", lastTxId));
}

static bool decodeType33(const String &payload) {
  if (payload.length() != 33) {
    return false;
  }
  const char *s = payload.c_str();
  long amount = 0, liters = 0, rate = 0, meter = 0;
  char product[4];
  char status[4];
  javaMid(s, 4, 1, product, sizeof(product));
  javaMid(s, 1, 1, status, sizeof(status));
  // Link is live: we already have a 33-char frame. Do not leave
  // esp_to_board_link false just because a field is non-numeric.
  lastValidFrameMs = millis();
  if (!javaHundredths(s, 5, 8, &amount) || !javaHundredths(s, 13, 8, &liters) ||
      !javaHundredths(s, 21, 5, &rate) || !javaHundredths(s, 26, 8, &meter)) {
    return false;
  }
  setProduct(product[0]);
  setStatus(status[0]);
  // Official FDX Remote Plus `_decode_33`: idle/pumping divide amount+liters
  // by 100. Status P and L put the keypad entry in Mid(5,8) with NO /100
  // and hide the liters LCD (`lbldisplayliter`).
  const char st = status[0];
  if (st == 'P' || st == 'p') {
    amountCents = amount * 100L;
    volumeCents = liters;
  } else if (st == 'L' || st == 'l') {
    amountCents = 0;
    volumeCents = amount * 100L;
  } else {
    amountCents = amount;
    volumeCents = liters;
  }
  rateCents = rate;
  meterCents = meter;
  totalAmount = amountCents / 100.0;
  volumeLiters = volumeCents / 100.0;
  unitRate = rate / 100.0;
  totalMeter = meter / 100.0;
  haveLive = true;
  lastValidFrameMs = millis();

  const bool pumpingNow = (status[0] == '5');
  if (pumpingNow) {
    if (!wasPumping) {
      lastPumpingVolumeCents = 0;
    }
    lastPumpingVolumeCents = volumeCents;
    pumpingSnapshotDirty = true;
  }
  if (wasPumping && !pumpingNow) {
    onPumpingIdleEdge();
  } else {
    broadcastJson(buildTelemetryJson("TELEMETRY", lastTxId));
  }
  wasPumping = pumpingNow;
  return true;
}

static bool decodeType37(const String &payload) {
  if (payload.length() != 37) {
    return false;
  }
  lastValidFrameMs = millis();
  char flag[4];
  javaMid(payload.c_str(), 1, 1, flag, sizeof(flag));
  if (flag[0] == '6') {
    noSaleFromType37 = true;
    if (wasPumping) {
      return true;
    }
    onZeroHangup();
  }
  return true;
}

static bool decodeType30(const String &payload) {
  if (payload.length() != 30) {
    return false;
  }
  lastValidFrameMs = millis();
  return true;
}

static bool decodeType36(const String &payload) {
  if (payload.length() != 36) {
    return false;
  }
  lastValidFrameMs = millis();
  return true;
}

static void routePayload(String payload) {
  sanitize(payload);
  // Any complete <...> frame means the FDX UART is talking. LCD decode
  // can still fail (spaces stripped, Type-29 vs 30, non-digits).
  lastValidFrameMs = millis();
  switch (payload.length()) {
    case 33:
      decodeType33(payload);
      break;
    case 37:
      decodeType37(payload);
      break;
    case 30:
      decodeType30(payload);
      break;
    case 36:
      decodeType36(payload);
      break;
    default: {
      static uint32_t lastLenLogMs = 0;
      if (millis() - lastLenLogMs >= 1000) {
        lastLenLogMs = millis();
        Serial.printf("uart frame len=%u (need 33/37/30/36)\n",
                      (unsigned)payload.length());
      }
      break;
    }
  }
}

static void ingestChunk(const char *data, size_t len) {
  for (size_t i = 0; i < len; i++) {
    rxBuf += data[i];
  }
  if (rxBuf.length() > RX_MAX) {
    const int lt = rxBuf.lastIndexOf('<');
    rxBuf = lt >= 0 ? rxBuf.substring(lt) : "";
  }
  while (true) {
    const int end = rxBuf.indexOf('>');
    if (end < 0) {
      break;
    }
    const String beforeEnd = rxBuf.substring(0, end);
    rxBuf = rxBuf.substring(end + 1);
    const int start = beforeEnd.lastIndexOf('<');
    if (start < 0) {
      continue;
    }
    routePayload(beforeEnd.substring(start + 1));
  }
}

static void readUart2() {
  size_t got = 0;
  while (Serial2.available() > 0 && got < UART_BYTES_PER_LOOP) {
    esp_task_wdt_reset();
    char tmp[256];
    const int n = Serial2.readBytes(tmp, sizeof(tmp));
    if (n <= 0) {
      break;
    }
    lastUartRxMs = millis();
    uartRxBytesWindow += (uint32_t)n;
    got += (size_t)n;
    ingestChunk(tmp, (size_t)n);
  }
}

static void handleCommand(const String &raw) {
  lastAppHbMs = millis();
  String t = raw;
  t.trim();
  if (!t.startsWith("{")) {
    return;
  }
  if (t.indexOf("ACK_TOKEN") >= 0 || t.indexOf("\"ack_token\"") >= 0) {
    const int tokAt = t.indexOf("\"token\"");
    if (tokAt >= 0) {
      const int colon = t.indexOf(':', tokAt);
      if (colon >= 0) {
        ackToken((uint32_t)strtoul(t.c_str() + colon + 1, NULL, 10));
      }
    }
    return;
  }
  if (t.indexOf("GET_SYNC_LOG") >= 0) {
    broadcastSyncLog();
    return;
  }
  if (t.indexOf("APP_HEARTBEAT") >= 0) {
    hadAppSession = true;
    const bool liveOn = t.indexOf("\"live\":true") >= 0 ||
                        t.indexOf("\"live\": true") >= 0;
    const bool liveOff = t.indexOf("\"live\":false") >= 0 ||
                         t.indexOf("\"live\": false") >= 0;
    if (liveOn) {
      shiftLive = true;
    } else if (liveOff) {
      shiftLive = false;
    }
    const int seqAt = t.indexOf("\"next_sequence\"");
    if (seqAt >= 0) {
      const int colon = t.indexOf(':', seqAt);
      if (colon >= 0) {
        const uint32_t seq = (uint32_t)strtoul(t.c_str() + colon + 1, NULL, 10);
        // Never rewind: an offline hang-up already stamped and incremented.
        if (seq >= 1 && seq > nextSequence) {
          nextSequence = seq;
          prefs.putUInt("nextSeq", nextSequence);
        }
      }
    }
    const int tokAt = t.indexOf("\"next_token\"");
    if (tokAt >= 0) {
      const int colon = t.indexOf(':', tokAt);
      if (colon >= 0) {
        const uint32_t token = (uint32_t)strtoul(t.c_str() + colon + 1, NULL, 10);
        const uint32_t seq = token >= ((uint32_t)UNIT_ID * 100000UL)
                                 ? token - ((uint32_t)UNIT_ID * 100000UL)
                                 : 0;
        if (seq >= 1 && seq > nextSequence) {
          nextSequence = seq;
          prefs.putUInt("nextSeq", nextSequence);
        }
      }
    }
    const int atKey = t.indexOf("\"at\"");
    if (atKey >= 0) {
      const int q1 = t.indexOf('"', t.indexOf(':', atKey) + 1);
      const int q2 = q1 >= 0 ? t.indexOf('"', q1 + 1) : -1;
      if (q1 >= 0 && q2 > q1) {
        String iso = t.substring(q1 + 1, q2);
        strncpy(appClockIso, iso.c_str(), sizeof(appClockIso) - 1);
        appClockIso[sizeof(appClockIso) - 1] = '\0';
      }
    }
    applySessionLock();
    return;
  }
  if (t.indexOf("\"cmd\":\"CONFIRM\"") >= 0 ||
      t.indexOf("\"cmd\": \"CONFIRM\"") >= 0) {
    saleAwaitingConfirm = false;
    operatorLock = false;
    shiftLive = true;
    const int tokAt = t.indexOf("\"token\"");
    if (tokAt >= 0) {
      const int colon = t.indexOf(':', tokAt);
      if (colon >= 0) {
        ackToken((uint32_t)strtoul(t.c_str() + colon + 1, NULL, 10));
      }
    }
    setKeypadLocked(false);
    applySessionLock();
    broadcastJson(buildTelemetryJson("TELEMETRY", lastTxId));
    return;
  }
  if (t.indexOf("SET_KEYPAD_LOCK") >= 0) {
    const bool lock = t.indexOf("\"lock\":true") >= 0 ||
                      t.indexOf("\"lock\": true") >= 0;
    operatorLock = lock;
    if (!lock) {
      shiftLive = true;
    }
    applySessionLock();
    broadcastJson(buildTelemetryJson("TELEMETRY", lastTxId));
    return;
  }
  if (t.indexOf("\"cmd\":\"FDX_RESET\"") >= 0 ||
      t.indexOf("\"cmd\": \"FDX_RESET\"") >= 0) {
    fdxResetBegin();
  }
}

// Half-duplex intercom. Speaker write matches the walkie-talkie:
// 16 kHz 16-bit stereo, sample * speaker / 100, 100 = full level.
// Operator PCM is not noise-gated. Frames stay 0xA1 out and 0xA2 in.
static const int IC_MIC_SD = 32;
static const int IC_MIC_WS = 25;
static const int IC_MIC_SCK = 33;
static const int IC_SPK_DIN = 22;
static const int IC_SPK_LRC = 26;
static const int IC_SPK_BCLK = 27;
static const int IC_PTT_PIN = 18;
static const int IC_MIC_SHIFT = 16;
static const uint32_t IC_RATE = 16000;
static const int IC_SAMPLES = 320;
static const size_t IC_PCM_BYTES = (size_t)IC_SAMPLES * 2;
static const size_t IC_FRAME_BYTES = 1 + IC_PCM_BYTES;
static const uint8_t IC_MAGIC_OPERATOR = 0xA1;
static const uint8_t IC_MAGIC_HELPER = 0xA2;
static const uint32_t IC_DEBOUNCE_MS = 20;
static const int IC_IDLE = 0;
static const int IC_OPERATOR = 1;
static const int IC_HELPER = 2;
static const size_t IC_RING_BYTES = 8192;

static I2SClass icMicPort;
static I2SClass icAmpPort;
static RingbufHandle_t icPlayRing = nullptr;
static int icMode = IC_IDLE;
static int icMicGain = 12;
static int icSpkGain = 80;
static int icNoiseCut = 20;
static bool icHwOk = false;
static bool icPttRaw = false;
static bool icHelperDown = false;
static uint32_t icPttChangeMs = 0;
static int32_t icDcPrevX = 0;
static int32_t icDcPrevY = 0;
static int32_t icMicRaw[IC_SAMPLES * 2];
static int16_t icMicPcm[IC_SAMPLES];
static int16_t icPhoneMono[IC_SAMPLES];
static int16_t icSpkStereo[IC_SAMPLES * 2];
static uint8_t icTxFrame[IC_FRAME_BYTES];

static int16_t icScaleMic(int32_t rawWord) {
  const int32_t x = rawWord >> IC_MIC_SHIFT;
  int32_t y = x - icDcPrevX + icDcPrevY - (icDcPrevY >> 8);
  icDcPrevX = x;
  icDcPrevY = y;
  int32_t scaled = y * icMicGain;
  if (scaled > 32767) {
    scaled = 32767;
  } else if (scaled < -32768) {
    scaled = -32768;
  }
  return (int16_t)scaled;
}

static bool icReadMic(int16_t *dst, size_t *outCount) {
  *outCount = 0;
  if (icMicPort.rxChan() == nullptr) {
    return false;
  }
  const size_t got = icMicPort.readBytes((char *)icMicRaw, IC_SAMPLES * 2 * sizeof(int32_t));
  if (got < 8) {
    return false;
  }
  const size_t pairs = got / 8;
  size_t count = 0;
  for (size_t i = 0; i < pairs && count < IC_SAMPLES; i++) {
    dst[count++] = icScaleMic(icMicRaw[i * 2]);
  }
  *outCount = count;
  return count > 0;
}

static void icWriteSpeaker(const int16_t *mono, size_t count) {
  if (count == 0 || icAmpPort.txChan() == nullptr) {
    return;
  }
  if (count > IC_SAMPLES) {
    count = IC_SAMPLES;
  }
  const int volume = icSpkGain;
  for (size_t i = 0; i < count; i++) {
    int32_t sample = ((int32_t)mono[i] * volume) / 100;
    if (sample > 32767) {
      sample = 32767;
    } else if (sample < -32768) {
      sample = -32768;
    }
    icSpkStereo[i * 2] = (int16_t)sample;
    icSpkStereo[i * 2 + 1] = (int16_t)sample;
  }
  icAmpPort.write((const uint8_t *)icSpkStereo, count * 4);
}

static void icQueuePcm(const uint8_t *data, size_t len) {
  if (icPlayRing == nullptr || len < 2) {
    return;
  }
  len &= ~((size_t)1);
  if (xRingbufferSend(icPlayRing, data, len, 0) == pdTRUE) {
    return;
  }
  size_t dropped = 0;
  void *old = xRingbufferReceiveUpTo(icPlayRing, &dropped, 0, len);
  if (old != nullptr) {
    vRingbufferReturnItem(icPlayRing, old);
  }
  xRingbufferSend(icPlayRing, data, len, 0);
}

static void icFlushPlay() {
  if (icPlayRing == nullptr) {
    return;
  }
  size_t got = 0;
  void *item = nullptr;
  while ((item = xRingbufferReceiveUpTo(icPlayRing, &got, 0, 1024)) != nullptr) {
    vRingbufferReturnItem(icPlayRing, item);
  }
}

static bool icPlayQueued() {
  if (icPlayRing == nullptr) {
    return false;
  }
  size_t got = 0;
  uint8_t *item = (uint8_t *)xRingbufferReceiveUpTo(
      icPlayRing, &got, 0, IC_SAMPLES * sizeof(int16_t));
  if (item == nullptr || got < 2) {
    if (item != nullptr) {
      vRingbufferReturnItem(icPlayRing, item);
    }
    return false;
  }
  got &= ~((size_t)1);
  size_t count = got / sizeof(int16_t);
  if (count > IC_SAMPLES) {
    count = IC_SAMPLES;
  }
  memcpy(icPhoneMono, item, count * sizeof(int16_t));
  vRingbufferReturnItem(icPlayRing, item);
  icWriteSpeaker(icPhoneMono, count);
  return true;
}

static void icSendHelper(const int16_t *pcm, size_t count) {
  if (wsClients <= 0 || count == 0) {
    return;
  }
  memset(icTxFrame, 0, sizeof(icTxFrame));
  icTxFrame[0] = IC_MAGIC_HELPER;
  if (count > IC_SAMPLES) {
    count = IC_SAMPLES;
  }
  memcpy(icTxFrame + 1, pcm, count * sizeof(int16_t));
  webSocket.broadcastBIN(icTxFrame, IC_FRAME_BYTES);
}

static void intercomNotifyHelper(bool down) {
  if (wsClients <= 0) {
    return;
  }
  char buf[80];
  snprintf(buf, sizeof(buf),
           "{\"cmd\":\"INTERCOM\",\"unit\":%d,\"who\":\"helper\",\"down\":%s}",
           UNIT_ID, down ? "true" : "false");
  webSocket.broadcastTXT(buf);
}

static int icParseBounded(const String &raw, const char *key, int fallback, int high) {
  const String token = String("\"") + key + "\":";
  const int at = raw.indexOf(token);
  if (at < 0) {
    return fallback;
  }
  int pos = at + (int)token.length();
  while (pos < (int)raw.length() && raw.charAt(pos) == ' ') {
    pos += 1;
  }
  int value = raw.substring(pos).toInt();
  if (value < 0) {
    value = 0;
  } else if (value > high) {
    value = high;
  }
  return value;
}

static int icParsePercent(const String &raw, const char *key, int fallback) {
  return icParseBounded(raw, key, fallback, 100);
}

static bool intercomConsumeText(const String &raw) {
  if (raw.indexOf("INTERCOM_CFG") >= 0) {
    lastAppHbMs = millis();
    icSpkGain = icParseBounded(raw, "spk", icSpkGain, 200);
    const int micPercent = icParsePercent(raw, "mic", (icMicGain * 100) / 12);
    int gain = (micPercent * 12) / 100;
    if (micPercent > 0 && gain < 1) {
      gain = 1;
    }
    icMicGain = gain;
    icNoiseCut = icParsePercent(raw, "gate", icNoiseCut);
    (void)icNoiseCut;
    return true;
  }
  const bool down = raw.indexOf("PTT_DOWN") >= 0;
  const bool up = raw.indexOf("PTT_UP") >= 0;
  if (!down && !up) {
    return false;
  }
  lastAppHbMs = millis();
  if (down) {
    if (!icHelperDown && icMode != IC_HELPER) {
      icFlushPlay();
      icMode = IC_OPERATOR;
    }
    return true;
  }
  if (icMode == IC_OPERATOR) {
    icFlushPlay();
    icMode = IC_IDLE;
  }
  return true;
}

static void intercomConsumeBinary(uint8_t *payload, size_t length) {
  if (payload == NULL || length < 3 || payload[0] != IC_MAGIC_OPERATOR) {
    return;
  }
  if (icMode != IC_OPERATOR) {
    return;
  }
  icQueuePcm(payload + 1, length - 1);
}

static void intercomBegin() {
  pinMode(IC_PTT_PIN, INPUT_PULLUP);
  icPttRaw = digitalRead(IC_PTT_PIN) == LOW;
  icHelperDown = false;
  icPttChangeMs = millis();
  icMode = IC_IDLE;
  icPlayRing = xRingbufferCreate(IC_RING_BYTES, RINGBUF_TYPE_BYTEBUF);

  icAmpPort.setPins(IC_SPK_BCLK, IC_SPK_LRC, IC_SPK_DIN, -1);
  const bool speakerOk = icAmpPort.begin(
      I2S_MODE_STD, IC_RATE, I2S_DATA_BIT_WIDTH_16BIT, I2S_SLOT_MODE_STEREO);
  icMicPort.setPins(IC_MIC_SCK, IC_MIC_WS, -1, IC_MIC_SD);
  const bool micOk = icMicPort.begin(
      I2S_MODE_STD, IC_RATE, I2S_DATA_BIT_WIDTH_32BIT, I2S_SLOT_MODE_STEREO);
  if (micOk) {
    icMicPort.setTimeout(200);
  }
  icHwOk = icPlayRing != nullptr && speakerOk && micOk;
  if (!icHwOk) {
    Serial.println("intercom I2S init failed");
    return;
  }
  Serial.println("intercom ready  mic 32/25/33  spk 22/26/27  ptt 18");
}

static void serviceIntercom() {
  const bool raw = digitalRead(IC_PTT_PIN) == LOW;
  const uint32_t now = millis();
  if (raw != icPttRaw) {
    icPttRaw = raw;
    icPttChangeMs = now;
  } else if ((now - icPttChangeMs) >= IC_DEBOUNCE_MS && raw != icHelperDown) {
    icHelperDown = raw;
    icFlushPlay();
    icDcPrevX = 0;
    icDcPrevY = 0;
    if (icHelperDown) {
      icMode = IC_HELPER;
      intercomNotifyHelper(true);
    } else {
      if (icMode == IC_HELPER) {
        icMode = IC_IDLE;
      }
      intercomNotifyHelper(false);
    }
  }

  if (!icHwOk) {
    return;
  }
  if (icMode == IC_HELPER) {
    size_t count = 0;
    if (!icReadMic(icMicPcm, &count)) {
      return;
    }
    icSendHelper(icMicPcm, count);
    return;
  }
  if (icMode == IC_OPERATOR) {
    // The dispenser loop also reads the pump, so keep two chunks ready.
    // writeSpeaker is the walkie-talkie path: sample * speaker / 100.
    icPlayQueued();
    icPlayQueued();
    return;
  }
  icFlushPlay();
}

void webSocketEvent(uint8_t num, WStype_t type, uint8_t *payload, size_t length) {
  switch (type) {
    case WStype_CONNECTED: {
      wsClients += 1;
      lastAppHbMs = millis();
      applySessionLock();
      sendHello(num);
      break;
    }
    case WStype_DISCONNECTED:
      if (wsClients > 0) {
        wsClients -= 1;
      }
      applySessionLock();
      break;
    case WStype_TEXT: {
      String msg;
      msg.reserve(length + 1);
      for (size_t i = 0; i < length; i++) {
        msg += (char)payload[i];
      }
      if (!wifiConsumeText(msg) && !intercomConsumeText(msg)) {
        handleCommand(msg);
      }
      break;
    }
    case WStype_BIN:
      intercomConsumeBinary(payload, length);
      break;
    default:
      break;
  }
}

static void beginUart2() {
  Serial2.setRxBufferSize(1024);
  Serial2.begin(UART2_BAUD, SERIAL_8N1, UART2_RX_PIN, UART2_TX_PIN);
  Serial2.setTimeout(2);
  rxBuf = "";
  Serial.printf(
      "UART2 FDX 4800 8N1  RX GPIO%d <- pump TX   TX GPIO%d -> pump RX\n",
      UART2_RX_PIN, UART2_TX_PIN);
  Serial.println(
      "Watch: uart=FDX rx/s>0 when linked. STALL + rx/s=0 = wiring/GND/pin, not app.");
}

static void fillMacId() {
  String mac = WiFi.macAddress();
  mac.replace(":", "");
  strncpy(macId, mac.c_str(), sizeof(macId) - 1);
  macId[sizeof(macId) - 1] = '\0';
}

static void startWebSocket() {
  if (wsListening) {
    return;
  }
  webSocket.begin();
  webSocket.onEvent(webSocketEvent);
  wsListening = true;
  Serial.printf("[WS] Server started on Port 81  %s  Unit-%d_ESP32\n",
                WiFi.localIP().toString().c_str(), UNIT_ID);
}

static void stopWebSocket() {
  if (!wsListening) {
    wsClients = 0;
    return;
  }
  webSocket.close();
  wsListening = false;
  wsClients = 0;
}

static bool wifiIsStation() {
  return strcmp(wifiSsid, WIFI_SSID) == 0;
}

static void loadWifiPrefs() {
  memset(wifiSsid, 0, sizeof(wifiSsid));
  memset(wifiPass, 0, sizeof(wifiPass));
  strncpy(wifiSsid, WIFI_SSID, sizeof(wifiSsid) - 1);
  strncpy(wifiPass, WIFI_PASS, sizeof(wifiPass) - 1);
  if (!prefs.isKey("wifiSsid")) {
    return;
  }
  const String savedSsid = prefs.getString("wifiSsid", "");
  const String savedPass = prefs.getString("wifiPass", "");
  if (savedSsid.length() < 1 || savedSsid.length() > 32 || savedPass.length() > 64) {
    return;
  }
  strncpy(wifiSsid, savedSsid.c_str(), sizeof(wifiSsid) - 1);
  strncpy(wifiPass, savedPass.c_str(), sizeof(wifiPass) - 1);
}

static void applyStaAddress() {
  if (wifiIsStation()) {
    IPAddress ip(192, 168, 1, 1 + (10 * UNIT_ID));
    IPAddress gw(192, 168, 1, 1);
    IPAddress mask(255, 255, 255, 0);
    WiFi.config(ip, gw, mask);
    return;
  }
  WiFi.config(IPAddress(), IPAddress(), IPAddress());
}

static String jsonQuoted(const String &raw, const char *key) {
  String token = String("\"") + key + "\":\"";
  int at = raw.indexOf(token);
  if (at < 0) {
    token = String("\"") + key + "\": \"";
    at = raw.indexOf(token);
  }
  if (at < 0) {
    return "";
  }
  String out;
  for (int i = at + (int)token.length(); i < (int)raw.length(); i++) {
    const char c = raw.charAt(i);
    if (c == '\\' && i + 1 < (int)raw.length()) {
      out += raw.charAt(i + 1);
      i += 1;
      continue;
    }
    if (c == '"') {
      break;
    }
    out += c;
  }
  return out;
}

static void announceWifi(const char *ip) {
  char buf[160];
  snprintf(buf, sizeof(buf),
           "{\"cmd\":\"WIFI_STATUS\",\"unit\":%d,\"ssid\":\"%s\",\"ip\":\"%s\",\"dhcp\":%s}",
           UNIT_ID, wifiSsid, ip, wifiIsStation() ? "false" : "true");
  Serial.println(buf);
  if (wsClients > 0) {
    webSocket.broadcastTXT(buf);
  }
}

static void joinWifiNow() {
  stopWebSocket();
  WiFi.disconnect(false, false);
  applyStaAddress();
  WiFi.setSleep(false);
  WiFi.setAutoReconnect(true);
  WiFi.begin(wifiSsid, wifiPass);
  lastWifiTryMs = millis();
}

static bool wifiConsumeText(const String &raw) {
  if (raw.indexOf("SET_WIFI") < 0) {
    return false;
  }
  String ssid = jsonQuoted(raw, "ssid");
  String pass = jsonQuoted(raw, "pass");
  ssid.trim();
  if (ssid.length() < 1 || ssid.length() > 32 || pass.length() > 64 ||
      ssid.indexOf('"') >= 0 || ssid.indexOf('\\') >= 0) {
    Serial.println("{\"cmd\":\"WIFI_STATUS\",\"unit\":0,\"ssid\":\"\",\"ip\":\"\",\"dhcp\":false}");
    return true;
  }
  memset(wifiSsid, 0, sizeof(wifiSsid));
  memset(wifiPass, 0, sizeof(wifiPass));
  strncpy(wifiSsid, ssid.c_str(), sizeof(wifiSsid) - 1);
  strncpy(wifiPass, pass.c_str(), sizeof(wifiPass) - 1);
  prefs.putString("wifiSsid", wifiSsid);
  prefs.putString("wifiPass", wifiPass);
  wifiAnnouncePending = true;
  joinWifiNow();
  announceWifi("0.0.0.0");
  return true;
}

static void serviceUsbWifi() {
  while (Serial.available() > 0) {
    const char c = (char)Serial.read();
    if (c == '\r') {
      continue;
    }
    if (c != '\n') {
      if (usbWifiLine.length() < 400) {
        usbWifiLine += c;
      }
      continue;
    }
    if (usbWifiLine.indexOf("SET_WIFI") >= 0) {
      wifiConsumeText(usbWifiLine);
    }
    usbWifiLine = "";
  }
}

static void startWifi() {
  WiFi.persistent(true);
  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.setAutoReconnect(true);
  char host[24];
  snprintf(host, sizeof(host), "Unit-%d_ESP32", UNIT_ID);
  WiFi.setHostname(host);
  applyStaAddress();
  WiFi.begin(wifiSsid, wifiPass);
  esp_wifi_set_max_tx_power(68);
  lastWifiTryMs = millis();
}

static void ensureWifi() {
  const wl_status_t st = WiFi.status();
  if (st == WL_CONNECTED) {
    lastWifiOkMs = millis();
    fillMacId();
    startWebSocket();
    if (wifiAnnouncePending) {
      wifiAnnouncePending = false;
      announceWifi(WiFi.localIP().toString().c_str());
    }
    return;
  }
  stopWebSocket();
  const uint32_t now = millis();
  // Still associating — do not kick STA. If it hangs, begin() again below.
  if (st == WL_IDLE_STATUS && (now - lastWifiTryMs) < WIFI_RETRY_MS) {
    return;
  }
  if (now - lastWifiTryMs < WIFI_RETRY_MS) {
    return;
  }
  lastWifiTryMs = now;
  Serial.printf("[wifi] status=%d join %s\n", (int)st, wifiSsid);
  WiFi.setSleep(false);
  WiFi.setAutoReconnect(true);
  WiFi.disconnect(false, false);
  applyStaAddress();
  WiFi.begin(wifiSsid, wifiPass);
}

void setup() {
  pinMode(FDX_RESET_PIN, INPUT);
  pinMode(RELAY_PIN, OUTPUT);
  pinMode(BUZZER_PIN, OUTPUT);
  writeBuzzer(false);
  intercomBegin();

  Serial.begin(USB_BAUD);
  delay(200);
  Serial.printf("FuelPoint ESP32 unit %d  WS :81  IP 192.168.0.%d\n", UNIT_ID,
                100 + (10 * UNIT_ID));
  Serial.println("Relay VCC must be 3.3V. Green IN LED ON = locked (GPIO4 LOW).");
  relaySelfTest();
  keypadLocked = false;
  setKeypadLocked(true);

  beginUart2();
  LittleFS.begin(true);
  prefs.begin("fp", false);
  loadWifiPrefs();
  nextSequence = prefs.getUInt("nextSeq", 1);
  if (nextSequence < 1) {
    nextSequence = 1;
  }
  recoverLiveSnapshot();

  startWifi();
  fillMacId();
  Serial.println("Waiting for Tenda IP before WebSocket :81");

#if defined(ESP_ARDUINO_VERSION_MAJOR) && ESP_ARDUINO_VERSION_MAJOR >= 3
  {
    esp_task_wdt_config_t wdtCfg = {
        .timeout_ms = (uint32_t)WDT_TIMEOUT_S * 1000,
        .idle_core_mask = 0,
        .trigger_panic = true,
    };
    esp_task_wdt_reconfigure(&wdtCfg);
    esp_task_wdt_add(NULL);
  }
#else
  esp_task_wdt_init(WDT_TIMEOUT_S, true);
  esp_task_wdt_add(NULL);
#endif
}

void loop() {



  esp_task_wdt_reset();
  readUart2();
  serviceFdxReset();
  if (wsListening) {
    webSocket.loop();
  }
  ensureWifi();
  serviceUsbWifi();
  applySessionLock();
  serviceBuzzer();
  serviceIntercom();
  readUart2();

  const uint32_t now = millis();
  if (pumpingSnapshotDirty && (now - lastLiveSnapMs) >= LIVE_SNAP_MS) {
    lastLiveSnapMs = now;
    pumpingSnapshotDirty = false;
    if (wasPumping) {
      writeLiveSnapshot();
    }
  }
  if (now - lastTickMs >= TICK_MS) {
    lastTickMs = now;
    if (WiFi.status() == WL_CONNECTED) {
      fillMacId();
    }
    broadcastJson(buildTelemetryJson("HEARTBEAT", lastTxId));
    const uint32_t rxThisSec = uartRxBytesWindow;
    uartRxBytesWindow = 0;
    Serial.printf("relay %s gpio4=%s uart=%s rx/s=%u\n", lockReason(),
                  digitalRead(RELAY_PIN) ? "HIGH" : "LOW",
                  uartLinkLive() ? "FDX" : "STALL",
                  (unsigned)rxThisSec);
  }
}
