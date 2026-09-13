/**
 * FuelPoint unit ESP32 — UART telemetry bridge to Flutter (WebSocket :81)
 *
 * Flash once per bay. Change UNIT_ID before each flash (1..4).
 *
 * Board: ESP32 Dev Module / 38-pin
 * USB Serial: 115200
 * UART2: GPIO 16 RX <- Board TX, GPIO 17 TX idle -> Board RX
 * Relay IN: GPIO 4  LOCK = LOW, UNLOCK = HIGH (active-LOW module).
 * Power relay VCC from 3.3 V, not 5 V, or the green IN LED never turns off.
 * Buzzer+: GPIO 5   Buzzer-: GND  (chirp while waiting for Confirm; solid if live-shift comms lost)
 *
 * Wi-Fi: SSID System
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
#include <stdlib.h>
#include <string.h>

static const char *WIFI_SSID = "System";
static const char *WIFI_PASS = "2658305@nadir";

static const uint32_t USB_BAUD = 115200;
static const uint32_t UART2_BAUD = 4800;
static const int UART2_RX_PIN = 16;
static const int UART2_TX_PIN = 17;
static const int RELAY_PIN = 4;
static const int BUZZER_PIN = 5;
// true  = IN LOW  locks keypad (most Songle "low-level trigger" boards)
// false = IN HIGH locks keypad (jumper set to H)
static const bool RELAY_ACTIVE_LOW = true;
static const uint32_t BUZZER_CYCLE_MS = 850;

static const uint32_t HEARTBEAT_LOCK_MS = 3000;
static const uint32_t UART_STALE_MS = 3000;
static const uint32_t WIFI_RETRY_MS = 15000;
static const uint32_t TICK_MS = 1000;
static const uint32_t LIVE_SNAP_MS = 1000;
static const size_t RX_MAX = 4096;
static const long ZERO_VOLUME_CENTS = 1;  // 0.01 L
static const int WDT_TIMEOUT_S = 15;
static const int QUEUE_CAP = 24;

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
uint32_t lastAppHbMs = 0;
uint32_t lastWifiOkMs = 0;
uint32_t lastWifiTryMs = 0;
uint32_t lastTickMs = 0;
uint32_t lastLiveSnapMs = 0;
uint32_t txSeq = 1;
int wsClients = 0;

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
  return lastValidFrameMs != 0 && (millis() - lastValidFrameMs) <= UART_STALE_MS;
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

static void makeTxId(char *out, size_t outSize) {
  snprintf(out, outSize, "%s-%lu", macId, (unsigned long)txSeq);
  txSeq += 1;
  prefs.putUInt("txSeq", txSeq);
}

static int queueCount() {
  if (!LittleFS.exists("/queue.json")) {
    return 0;
  }
  File f = LittleFS.open("/queue.json", "r");
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

static bool queueHasTx(const char *txId) {
  if (!LittleFS.exists("/queue.json")) {
    return false;
  }
  File f = LittleFS.open("/queue.json", "r");
  if (!f) {
    return false;
  }
  const String needle = String("\"tx_id\":\"") + txId + "\"";
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

static void appendQueueLine(const String &line) {
  File f = LittleFS.open("/queue.json", "a");
  if (!f) {
    return;
  }
  f.println(line);
  f.close();
}

static void enqueueSale(const char *kind, const char *txId) {
  if (queueHasTx(txId)) {
    return;
  }
  if (queueCount() >= QUEUE_CAP) {
    return;
  }
  char amt[24], lit[24], rateBuf[24], meter[24];
  formatHundredths(amt, sizeof(amt), amountCents);
  formatHundredths(lit, sizeof(lit), volumeCents);
  formatHundredths(rateBuf, sizeof(rateBuf), rateCents);
  formatHundredths(meter, sizeof(meter), meterCents);
  char line[512];
  snprintf(line, sizeof(line),
           "{\"cmd\":\"QUEUE_REPLAY\",\"tx_id\":\"%s\",\"status\":\"%s\","
           "\"kind\":\"%s\",\"unit\":%d,\"amount\":%s,\"liters\":%s,"
           "\"rate\":%s,\"meter\":%s,\"amount_cents\":%ld,\"liter_cents\":%ld,"
           "\"rate_cents\":%ld,\"meter_cents\":%ld,\"product\":\"%s\",\"created_at\":%lu}",
           txId, kind, kind, UNIT_ID, amt, lit, rateBuf, meter,
           amountCents, volumeCents, rateCents, meterCents, productLabel,
           (unsigned long)millis());
  appendQueueLine(String(line));
}

static void ackTx(const char *txId) {
  if (!LittleFS.exists("/queue.json")) {
    return;
  }
  File in = LittleFS.open("/queue.json", "r");
  if (!in) {
    return;
  }
  String kept;
  const String needle = String("\"tx_id\":\"") + txId + "\"";
  while (in.available()) {
    String line = in.readStringUntil('\n');
    line.trim();
    if (line.length() < 8) {
      continue;
    }
    if (line.indexOf(needle) >= 0) {
      continue;
    }
    kept += line;
    kept += '\n';
  }
  in.close();
  File out = LittleFS.open("/queue.json", "w");
  if (!out) {
    return;
  }
  out.print(kept);
  out.close();
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
  LittleFS.remove("/live.json");
  if (raw.indexOf("\"pumping\":true") < 0) {
    return;
  }
  haveLive = true;
  char txId[48];
  makeTxId(txId, sizeof(txId));
  strncpy(lastTxId, txId, sizeof(lastTxId) - 1);
  lastTxId[sizeof(lastTxId) - 1] = '\0';
  enqueueSale("Incomplete/PowerLost", txId);
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
           (unsigned long)(millis() / 1000), WiFi.RSSI(), queueCount(),
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
  webSocket.broadcastTXT(json);
}

static void replayQueue(uint8_t client) {
  if (!LittleFS.exists("/queue.json")) {
    return;
  }
  File f = LittleFS.open("/queue.json", "r");
  if (!f) {
    return;
  }
  while (f.available()) {
    String line = f.readStringUntil('\n');
    line.trim();
    if (line.length() > 8) {
      webSocket.sendTXT(client, line);
    }
  }
  f.close();
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
  char txId[48];
  makeTxId(txId, sizeof(txId));
  strncpy(lastTxId, txId, sizeof(lastTxId) - 1);
  lastTxId[sizeof(lastTxId) - 1] = '\0';
  enqueueSale("UNSYNCED", txId);
  clearLiveSnapshot();
  broadcastJson(buildTelemetryJson("SALE_COMPLETE", txId));
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
    default:
      break;
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
  while (Serial2.available() > 0) {
    char tmp[256];
    const int n = Serial2.readBytes(tmp, sizeof(tmp));
    if (n <= 0) {
      break;
    }
    ingestChunk(tmp, (size_t)n);
  }
}

static void handleCommand(const String &raw) {
  lastAppHbMs = millis();
  String t = raw;
  t.trim();
  if (t.startsWith("<ACK,") && t.endsWith(">")) {
    String id = t.substring(5, t.length() - 1);
    id.replace("TX_ID_", "");
    ackTx(id.c_str());
    return;
  }
  if (!t.startsWith("{")) {
    return;
  }
  const int ackAt = t.indexOf("\"ack_tx_id\"");
  if (ackAt >= 0) {
    const int q1 = t.indexOf('"', t.indexOf(':', ackAt) + 1);
    const int q2 = t.indexOf('"', q1 + 1);
    if (q1 >= 0 && q2 > q1) {
      ackTx(t.substring(q1 + 1, q2).c_str());
    }
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
    applySessionLock();
    return;
  }
  if (t.indexOf("\"cmd\":\"CONFIRM\"") >= 0 ||
      t.indexOf("\"cmd\": \"CONFIRM\"") >= 0) {
    saleAwaitingConfirm = false;
    operatorLock = false;
    shiftLive = true;
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
      saleAwaitingConfirm = false;
      shiftLive = true;
      setKeypadLocked(false);
    }
    applySessionLock();
    broadcastJson(buildTelemetryJson("TELEMETRY", lastTxId));
  }
}

void webSocketEvent(uint8_t num, WStype_t type, uint8_t *payload, size_t length) {
  switch (type) {
    case WStype_CONNECTED: {
      wsClients += 1;
      lastAppHbMs = millis();
      applySessionLock();
      replayQueue(num);
      String hello = buildTelemetryJson("TELEMETRY", lastTxId);
      webSocket.sendTXT(num, hello);
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
      handleCommand(msg);
      break;
    }
    default:
      break;
  }
}

static void beginUart2() {
  Serial2.setRxBufferSize(1024);
  Serial2.begin(UART2_BAUD, SERIAL_8N1, UART2_RX_PIN, UART2_TX_PIN);
  Serial2.setTimeout(2);
  rxBuf = "";
}

static void fillMacId() {
  String mac = WiFi.macAddress();
  mac.replace(":", "");
  strncpy(macId, mac.c_str(), sizeof(macId) - 1);
  macId[sizeof(macId) - 1] = '\0';
}

static void startWifi() {
  WiFi.persistent(false);
  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.setAutoReconnect(true);
  char host[24];
  snprintf(host, sizeof(host), "Unit-%d_ESP32", UNIT_ID);
  WiFi.setHostname(host);
  IPAddress ip(192, 168, 0, 100 + (10 * UNIT_ID));
  IPAddress gw(192, 168, 0, 1);
  IPAddress mask(255, 255, 255, 0);
  WiFi.config(ip, gw, mask);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  lastWifiTryMs = millis();
}

static void ensureWifi() {
  if (WiFi.status() == WL_CONNECTED) {
    lastWifiOkMs = millis();
    return;
  }
  const uint32_t now = millis();
  if (now - lastWifiTryMs < WIFI_RETRY_MS) {
    return;
  }
  lastWifiTryMs = now;
  WiFi.disconnect(false, false);
  delay(50);
  startWifi();
}

void setup() {
  pinMode(RELAY_PIN, OUTPUT);
  pinMode(BUZZER_PIN, OUTPUT);
  writeBuzzer(false);

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
  txSeq = prefs.getUInt("txSeq", 1);
  if (txSeq < 1) {
    txSeq = 1;
  }
  recoverLiveSnapshot();

  startWifi();
  fillMacId();
  webSocket.begin();
  webSocket.onEvent(webSocketEvent);

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
  webSocket.loop();
  ensureWifi();
  applySessionLock();
  serviceBuzzer();

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
    Serial.printf("relay %s gpio4=%s\n", lockReason(),
                  digitalRead(RELAY_PIN) ? "HIGH" : "LOW");
  }
}
