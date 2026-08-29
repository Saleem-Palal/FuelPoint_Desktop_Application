/**
 * Standalone ESP32 sketch — FDX-ALPHA live monitor
 *
 * NOT part of the Flutter app. Open this file in Arduino IDE
 * (rename to .ino if needed) or PlatformIO (Arduino framework).
 *
 * Board: ESP32
 * USB Serial (monitor): 115200
 * UART2 TX only: GPIO 17 (RX unused)
 *
 * Wi-Fi STA  ->  SSID FDX-57608F
 * TCP client ->  192.168.5.1:9876
 *
 * Framing/decode matches the Flutter tester:
 *   - buffer bytes, extract <...> frames
 *   - strip < > spaces CR LF
 *   - route by payload length 33 / 37 / 29 / 36
 *   - Type-33 Java Mid map (1-based):
 *       status Mid(1,1), product Mid(4,1)
 *       amount Mid(5,8)/100, liters Mid(13,8)/100
 *       rate Mid(21,5)/100, meter Mid(26,8)/100
 */

#include <Arduino.h>
#include <WiFi.h>
#include <ctype.h>
#include <stdlib.h>
#include <string.h>

static const char *WIFI_SSID = "FDX-57608F";
static const char *WIFI_PASS = "123456789";
static const char *FDX_HOST = "192.168.5.1";
static const uint16_t FDX_PORT = 9876;

static const uint32_t SERIAL_BAUD = 115200;
static const int UART2_TX_PIN = 17;
static const int UART2_RX_PIN = -1;
static const uint32_t PRINT_EVERY_MS = 1000;
static const uint32_t WIFI_RETRY_MS = 4000;
static const uint32_t TCP_RETRY_MS = 3000;
static const size_t RX_MAX = 4096;

WiFiClient client;

String rxBuf;
bool haveLive = false;
bool timeFromRtc = false;

char productLabel[16] = "-";
char statusLabel[24] = "-";
char timeLabel[16] = "-";
char lastEvent[160] = "-";
double totalAmount = 0;
double volumeLiters = 0;
double unitRate = 0;
double totalMeter = 0;

uint32_t lastPrintMs = 0;
uint32_t lastWifiTryMs = 0;
uint32_t lastTcpTryMs = 0;

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

static bool javaMoney(const char *s, int start1, int len, double *out) {
  char slice[16];
  javaMid(s, start1, len, slice, sizeof(slice));
  if (slice[0] == '\0') {
    return false;
  }
  char *end = NULL;
  const double raw = strtod(slice, &end);
  if (end == slice) {
    return false;
  }
  *out = raw / 100.0;
  return true;
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
    case 'L':
    case 'l':
      strncpy(statusLabel, "Preset mode", sizeof(statusLabel) - 1);
      break;
    default:
      strncpy(statusLabel, "-", sizeof(statusLabel) - 1);
      break;
  }
}

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

static bool decodeType33(const String &payload) {
  if (payload.length() != 33) {
    return false;
  }
  const char *s = payload.c_str();
  double amount = 0, liters = 0, rate = 0, meter = 0;
  char product[4];
  char status[4];
  javaMid(s, 4, 1, product, sizeof(product));
  javaMid(s, 1, 1, status, sizeof(status));
  if (!javaMoney(s, 5, 8, &amount)) {
    return false;
  }
  if (!javaMoney(s, 13, 8, &liters)) {
    return false;
  }
  if (!javaMoney(s, 21, 5, &rate)) {
    return false;
  }
  if (!javaMoney(s, 26, 8, &meter)) {
    return false;
  }
  setProduct(product[0]);
  setStatus(status[0]);
  totalAmount = amount;
  volumeLiters = liters;
  unitRate = rate;
  totalMeter = meter;
  haveLive = true;
  if (!timeFromRtc) {
    const uint32_t ms = millis() / 1000;
    const uint32_t hh = (ms / 3600) % 24;
    const uint32_t mm = (ms / 60) % 60;
    const uint32_t ss = ms % 60;
    snprintf(timeLabel, sizeof(timeLabel), "%02lu:%02lu:%02lu",
             (unsigned long)hh, (unsigned long)mm, (unsigned long)ss);
  }
  return true;
}

static bool decodeType37(const String &payload) {
  if (payload.length() != 37) {
    return false;
  }
  const char *s = payload.c_str();
  char flag[4];
  javaMid(s, 1, 1, flag, sizeof(flag));
  if (flag[0] != '6' && flag[0] != '7') {
    return false;
  }
  double amount = 0, liters = 0, rate = 0;
  if (!javaMoney(s, 5, 8, &amount) || !javaMoney(s, 13, 8, &liters) ||
      !javaMoney(s, 21, 5, &rate)) {
    return false;
  }
  char year[4], month[4], day[4], hrs[4], min[4], sec[4];
  javaMid(s, 26, 2, year, sizeof(year));
  javaMid(s, 28, 2, month, sizeof(month));
  javaMid(s, 30, 2, day, sizeof(day));
  javaMid(s, 32, 2, hrs, sizeof(hrs));
  javaMid(s, 34, 2, min, sizeof(min));
  javaMid(s, 36, 2, sec, sizeof(sec));
  snprintf(timeLabel, sizeof(timeLabel), "%s:%s:%s", hrs, min, sec);
  timeFromRtc = true;
  totalAmount = amount;
  volumeLiters = liters;
  unitRate = rate;
  haveLive = true;
  if (flag[0] == '6') {
    snprintf(lastEvent, sizeof(lastEvent),
             "No sale at %s Hrs %s/%s/%s", timeLabel, day, month, year);
    strncpy(statusLabel, "Idle", sizeof(statusLabel) - 1);
  } else {
    snprintf(lastEvent, sizeof(lastEvent),
             "Sale closed: Rs %.2f  %.2f L  Rt %.2f at %s Hrs %s/%s/%s",
             amount, liters, rate, timeLabel, day, month, year);
    strncpy(statusLabel, "Idle", sizeof(statusLabel) - 1);
  }
  return true;
}

static bool decodeType29(const String &payload) {
  if (payload.length() != 29) {
    return false;
  }
  const char *s = payload.c_str();
  char flag[4];
  javaMid(s, 1, 1, flag, sizeof(flag));
  if (flag[0] != '4') {
    return false;
  }
  double total = 0, rate = 0;
  if (!javaMoney(s, 5, 8, &total) || !javaMoney(s, 24, 5, &rate)) {
    return false;
  }
  char year[4], month[4], day[4], hrs[4], min[4], sec[4];
  javaMid(s, 18, 2, year, sizeof(year));
  javaMid(s, 20, 2, month, sizeof(month));
  javaMid(s, 22, 2, day, sizeof(day));
  javaMid(s, 24, 2, hrs, sizeof(hrs));
  javaMid(s, 26, 2, min, sizeof(min));
  javaMid(s, 28, 2, sec, sizeof(sec));
  snprintf(lastEvent, sizeof(lastEvent),
           "Sale started: Rt %.2f  meter %.2f at %s:%s:%s Hrs %s/%s/%s",
           rate, total, hrs, min, sec, day, month, year);
  return true;
}

static bool decodeType36(const String &payload) {
  if (payload.length() != 36) {
    return false;
  }
  const char *s = payload.c_str();
  char flag[4];
  javaMid(s, 1, 1, flag, sizeof(flag));
  if (flag[0] != '2') {
    return false;
  }
  double amount = 0, liters = 0, rate = 0;
  if (!javaMoney(s, 4, 8, &amount) || !javaMoney(s, 12, 8, &liters) ||
      !javaMoney(s, 20, 5, &rate)) {
    return false;
  }
  char number[4], hrs[4], min[4], sec[4], day[4], month[4], year[4];
  javaMid(s, 2, 2, number, sizeof(number));
  javaMid(s, 31, 2, hrs, sizeof(hrs));
  javaMid(s, 33, 2, min, sizeof(min));
  javaMid(s, 35, 2, sec, sizeof(sec));
  javaMid(s, 29, 2, day, sizeof(day));
  javaMid(s, 27, 2, month, sizeof(month));
  javaMid(s, 25, 2, year, sizeof(year));
  snprintf(lastEvent, sizeof(lastEvent),
           "Log #%s %.2f Rs. %.2f Ltr. %.2f Rs/Ltr at %s:%s:%s %s/%s/%s",
           number, amount, liters, rate, hrs, min, sec, day, month, year);
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
    case 29:
      decodeType29(payload);
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

static void ensureWifi() {
  if (WiFi.status() == WL_CONNECTED) {
    return;
  }
  if (millis() - lastWifiTryMs < WIFI_RETRY_MS) {
    return;
  }
  lastWifiTryMs = millis();
  Serial.printf("[wifi] connecting to %s ...\n", WIFI_SSID);
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
}

static void ensureTcp() {
  if (WiFi.status() != WL_CONNECTED) {
    return;
  }
  if (client.connected()) {
    return;
  }
  if (millis() - lastTcpTryMs < TCP_RETRY_MS) {
    return;
  }
  lastTcpTryMs = millis();
  Serial.printf("[tcp] connecting to %s:%u ...\n", FDX_HOST, FDX_PORT);
  client.stop();
  if (client.connect(FDX_HOST, FDX_PORT)) {
    client.setNoDelay(true);
    rxBuf = "";
    Serial.println("[tcp] connected");
  } else {
    Serial.println("[tcp] connect failed — retrying");
  }
}

static void readSocket() {
  if (!client.connected()) {
    return;
  }
  while (client.available() > 0) {
    char tmp[256];
    const int n = client.read((uint8_t *)tmp, sizeof(tmp));
    if (n <= 0) {
      break;
    }
    ingestChunk(tmp, (size_t)n);
  }
}

static void emitLine(const char *line) {
  Serial.println(line);
  Serial2.println(line);
}

static void printSnapshot() {
  const uint32_t now = millis();
  if (now - lastPrintMs < PRINT_EVERY_MS) {
    return;
  }
  lastPrintMs = now;

  const uint32_t sec = now / 1000;
  const uint32_t hh = (sec / 3600) % 24;
  const uint32_t mm = (sec / 60) % 60;
  const uint32_t ss = sec % 60;

  char line[192];

  emitLine("---------- FDX-ALPHA ----------");
  snprintf(line, sizeof(line), "uptime      %02lu:%02lu:%02lu",
           (unsigned long)hh, (unsigned long)mm, (unsigned long)ss);
  emitLine(line);
  snprintf(line, sizeof(line), "wifi        %s",
           WiFi.status() == WL_CONNECTED ? WiFi.localIP().toString().c_str()
                                         : "offline");
  emitLine(line);
  snprintf(line, sizeof(line), "socket      %s",
           client.connected() ? "connected" : "down");
  emitLine(line);
  if (!haveLive) {
    emitLine("live        waiting for Type-33 frame...");
    emitLine("--------------------------------");
    return;
  }
  snprintf(line, sizeof(line), "product     %s", productLabel);
  emitLine(line);
  snprintf(line, sizeof(line), "pump        %s", statusLabel);
  emitLine(line);
  snprintf(line, sizeof(line), "amount      %.2f Rs", totalAmount);
  emitLine(line);
  snprintf(line, sizeof(line), "volume      %.2f L", volumeLiters);
  emitLine(line);
  snprintf(line, sizeof(line), "unit rate   %.2f Rs/L", unitRate);
  emitLine(line);
  snprintf(line, sizeof(line), "total meter %.2f", totalMeter);
  emitLine(line);
  snprintf(line, sizeof(line), "time        %s%s", timeLabel,
           timeFromRtc ? " (RTC)" : " (uptime)");
  emitLine(line);
  snprintf(line, sizeof(line), "event       %s", lastEvent);
  emitLine(line);
  emitLine("--------------------------------");

  snprintf(line, sizeof(line),
           "FDX,AMT:%.2f,VOL:%.2f,RATE:%.2f,MTR:%.2f,STS:%s,PRD:%s,TIME:%s",
           totalAmount, volumeLiters, unitRate, totalMeter, statusLabel,
           productLabel, timeLabel);
  Serial2.println(line);
}

void setup() {
  Serial.begin(SERIAL_BAUD);
  Serial2.begin(SERIAL_BAUD, SERIAL_8N1, UART2_RX_PIN, UART2_TX_PIN);
  delay(200);
  Serial.println();
  Serial.println("FDX-ALPHA ESP32 monitor");
  Serial.printf("UART2 TX on GPIO %d at %lu baud\n", UART2_TX_PIN,
                (unsigned long)SERIAL_BAUD);
  Serial2.println("FDX-ALPHA UART2 TX ready");
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  lastWifiTryMs = millis();
}

void loop() {
  ensureWifi();
  ensureTcp();
  readSocket();
  printSnapshot();
}
