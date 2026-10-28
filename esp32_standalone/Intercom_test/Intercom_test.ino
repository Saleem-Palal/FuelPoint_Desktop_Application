/*
  Intercom test — ESP32 access point, Flutter app is the other radio.
  Board: ESP32 Dev Module / 38-pin. Core 3.x. Library: WebSockets by Markus Sattler.

  Wi-Fi name:     WalkieTalkie
  Wi-Fi password: talk1234
  WebSocket:      ws://192.168.4.1:81/

  The sketch does not wait for USB. It opens the access point from setup().

  Power without the USB cable
  ----------------------------
  If the Wi-Fi name never appears on a 5 V supply after you unplug USB, the
  program is not running. A DevKit's CP2102 or CH340 is powered from the USB
  socket. When that chip loses power, the auto-reset transistors pull EN or
  GPIO0 and the ESP32 sits in reset or download mode. An access point and a
  station join both stay dark, because neither sketch is executing.

  The onboard LED (GPIO 2) flashes three times at boot, then blinks slowly
  until the app connects. No flashes at all means the chip never left reset:
  feed 5 V through the USB socket, or put 10 uF from EN to GND (positive on
  EN). Flashes that repeat forever mean the 5 V rail sagged when the radio
  started (brownout). Use a supply that can give 500 mA, short wires, and a
  common ground with the amplifier.

  Wiring
  ------
  INMP441  VDD 3.3V, GND, L/R to GND, SD GPIO 32, WS GPIO 25, SCK GPIO 33
  MAX98357A VIN 5V, GND, DIN GPIO 22, LRC GPIO 26, BCLK GPIO 27, 4 ohm speaker
  PTT GPIO 18 to GND (pressed = LOW)

  Audio is 16 kHz 16-bit mono PCM.
  Text: 1 / 0 push-to-talk, V speaker 0-200 (100 = full), G mic gain,
        N noise cut, C swap channel,
        M1 / M0 play the ESP mic on its own speaker.
*/

#include <WiFi.h>
#include <WebSocketsServer.h>
#include <ESP_I2S.h>
#include <esp_system.h>
#include "freertos/ringbuf.h"

static const int MIC_BCLK = 33;
static const int MIC_WS = 25;
static const int MIC_DIN = 32;
static const int AMP_BCLK = 27;
static const int AMP_WS = 26;
static const int AMP_DOUT = 22;
static const int PTT_PIN = 18;
static const int STATUS_LED = 2;

static const char *AP_SSID = "WalkieTalkie";
static const char *AP_PASS = "talk1234";
static const uint16_t SAMPLE_RATE = 16000;
static const int MIC_SHIFT = 16;
static const size_t CHUNK_FRAMES = 320;  // 20 ms at 16 kHz
static const size_t RING_BYTES = 8192;

static const uint16_t WS_PORT = 81;

I2SClass i2sMic;
I2SClass i2sAmp;
WebSocketsServer webSocket(WS_PORT);
RingbufHandle_t playRing = nullptr;

static bool apUp = false;
static int clientNum = -1;
static uint8_t pendingReady = 0;
static volatile uint8_t phonePtt = 0;
static volatile uint8_t micMonitor = 0;
static volatile uint8_t micUseRight = 0;
static volatile uint8_t espTalking = 0;
static volatile int micGain = 12;
static volatile int speakerVol = 80;  // 0..200, 100 = full level, same as the walkie page
static volatile int noiseCut = 20;
static volatile uint32_t lastPhoneAudioMs = 0;

static int32_t dcPrevX = 0;
static int32_t dcPrevY = 0;
static int32_t micRaw[CHUNK_FRAMES * 2];
static int16_t micPcm[CHUNK_FRAMES];
static int16_t phoneMono[CHUNK_FRAMES];
static int16_t spkStereo[CHUNK_FRAMES * 2];

static void queuePhoneAudio(const uint8_t *data, size_t len) {
  if (playRing == nullptr || data == nullptr || len < 2) {
    return;
  }
  len &= ~((size_t)1);
  if (xRingbufferSend(playRing, data, len, 0) == pdTRUE) {
    return;
  }
  size_t dropped = 0;
  void *old = xRingbufferReceiveUpTo(playRing, &dropped, 0, len);
  if (old != nullptr) {
    vRingbufferReturnItem(playRing, old);
  }
  xRingbufferSend(playRing, data, len, 0);
}

static void flushPhoneAudio() {
  if (playRing == nullptr) {
    return;
  }
  size_t got = 0;
  void *item = nullptr;
  while ((item = xRingbufferReceiveUpTo(playRing, &got, 0, 1024)) != nullptr) {
    vRingbufferReturnItem(playRing, item);
  }
}

static int32_t softenSample(int32_t sample, int cut) {
  int32_t mag = sample < 0 ? -sample : sample;
  if (mag < 180) {
    return 0;
  }
  if (cut <= 0) {
    return sample;
  }
  int32_t thresh = 400 + (cut * 176);
  if (mag >= thresh) {
    return sample;
  }
  int32_t pulled = (sample * mag) / thresh;
  int32_t pulledMag = pulled < 0 ? -pulled : pulled;
  return (pulled * pulledMag) / thresh;
}

static void applyNoiseCut(int16_t *samples, size_t count) {
  int cut = noiseCut;
  if (cut <= 0 || count == 0) {
    return;
  }
  if (cut > 100) {
    cut = 100;
  }
  int64_t levelSum = 0;
  int levelPeak = 0;
  for (size_t i = 0; i < count; i++) {
    int32_t y = softenSample(samples[i], cut);
    if (y > 32767) {
      y = 32767;
    } else if (y < -32768) {
      y = -32768;
    }
    samples[i] = (int16_t)y;
    int mag = y < 0 ? -(int)y : (int)y;
    levelSum += mag;
    if (mag > levelPeak) {
      levelPeak = mag;
    }
  }
  int mean = (int)(levelSum / (int64_t)count);
  if (mean >= 8000 && levelPeak >= 12000) {
    return;
  }
  int keep = 100 - ((cut * 92) / 100);
  if (keep < 8) {
    keep = 8;
  }
  if (keep >= 100) {
    return;
  }
  for (size_t i = 0; i < count; i++) {
    samples[i] = (int16_t)(((int32_t)samples[i] * keep) / 100);
  }
}

static int16_t scaleMicSample(int32_t rawWord) {
  int32_t x = rawWord >> MIC_SHIFT;
  int32_t y = x - dcPrevX + dcPrevY - (dcPrevY >> 8);
  dcPrevX = x;
  dcPrevY = y;
  int32_t scaled = y * micGain;
  if (scaled > 32767) {
    scaled = 32767;
  }
  if (scaled < -32768) {
    scaled = -32768;
  }
  return (int16_t)scaled;
}

static bool readMic(int16_t *dst, size_t *outCount) {
  *outCount = 0;
  if (i2sMic.rxChan() == nullptr) {
    return false;
  }
  size_t got = i2sMic.readBytes((char *)micRaw, CHUNK_FRAMES * 2 * sizeof(int32_t));
  if (got < 8) {
    return false;
  }
  size_t pairs = got / 8;
  uint8_t right = micUseRight;
  size_t count = 0;
  for (size_t i = 0; i < pairs && count < CHUNK_FRAMES; i++) {
    dst[count++] = scaleMicSample(micRaw[i * 2 + (right ? 1 : 0)]);
  }
  *outCount = count;
  if (count > 0) {
    applyNoiseCut(dst, count);
  }
  return count > 0;
}

static void writeSpeaker(const int16_t *mono, size_t count) {
  if (count == 0 || i2sAmp.txChan() == nullptr) {
    return;
  }
  if (count > CHUNK_FRAMES) {
    count = CHUNK_FRAMES;
  }
  int volume = speakerVol;
  for (size_t i = 0; i < count; i++) {
    int32_t sample = ((int32_t)mono[i] * volume) / 100;
    if (sample > 32767) {
      sample = 32767;
    }
    if (sample < -32768) {
      sample = -32768;
    }
    spkStereo[i * 2] = (int16_t)sample;
    spkStereo[i * 2 + 1] = (int16_t)sample;
  }
  i2sAmp.write((const uint8_t *)spkStereo, count * 4);
}

static bool playPhoneAudio() {
  if (playRing == nullptr) {
    return false;
  }
  size_t got = 0;
  uint8_t *item = (uint8_t *)xRingbufferReceiveUpTo(
      playRing, &got, 0, CHUNK_FRAMES * sizeof(int16_t));
  if (item == nullptr || got < 2) {
    if (item != nullptr) {
      vRingbufferReturnItem(playRing, item);
    }
    return false;
  }
  got &= ~((size_t)1);
  size_t count = got / sizeof(int16_t);
  if (count > CHUNK_FRAMES) {
    count = CHUNK_FRAMES;
  }
  memcpy(phoneMono, item, count * sizeof(int16_t));
  vRingbufferReturnItem(playRing, item);
  writeSpeaker(phoneMono, count);
  return true;
}

static bool wsSendText(const char *text) {
  if (clientNum < 0 || text == nullptr) {
    return false;
  }
  return webSocket.sendTXT((uint8_t)clientNum, text);
}

static bool wsSendPcm(const int16_t *pcm, size_t count) {
  if (clientNum < 0 || count == 0) {
    return false;
  }
  return webSocket.sendBIN(
    (uint8_t)clientNum,
    (uint8_t *)pcm,
    count * sizeof(int16_t));
}

static int clampNumber(int value, int low, int high) {
  if (value < low) {
    return low;
  }
  if (value > high) {
    return high;
  }
  return value;
}

static void onControlText(const char *text, size_t len) {
  if (text == nullptr || len == 0) {
    return;
  }
  if (text[0] == '1') {
    phonePtt = 1;
    lastPhoneAudioMs = millis();
    Serial.println("App PTT down");
    return;
  }
  if (text[0] == '0') {
    phonePtt = 0;
    Serial.println("App PTT up");
    return;
  }
  if (text[0] == 'M') {
    micMonitor = (len > 1 && text[1] == '1') ? 1 : 0;
    Serial.println(micMonitor ? "Mic test on" : "Mic test off");
    return;
  }
  if (text[0] == 'C') {
    micUseRight = micUseRight ? 0 : 1;
    dcPrevX = 0;
    dcPrevY = 0;
    Serial.println(micUseRight ? "Mic channel right" : "Mic channel left");
    return;
  }
  if ((text[0] == 'V' || text[0] == 'G' || text[0] == 'N') && len > 1) {
    int value = atoi(text + 1);
    if (text[0] == 'V') {
      speakerVol = clampNumber(value, 0, 200);
    } else if (text[0] == 'G') {
      micGain = clampNumber(value, 0, 40);
    } else {
      noiseCut = clampNumber(value, 0, 100);
    }
  }
}

static void onWsEvent(uint8_t num, WStype_t type, uint8_t *payload, size_t length) {
  switch (type) {
    case WStype_CONNECTED:
      clientNum = num;
      phonePtt = 0;
      micMonitor = 0;
      flushPhoneAudio();
      pendingReady = 1;
      Serial.printf("App connected, socket %u\n", (unsigned)num);
      break;
    case WStype_DISCONNECTED:
      if (clientNum == (int)num) {
        clientNum = -1;
        phonePtt = 0;
        micMonitor = 0;
        flushPhoneAudio();
        Serial.println("App disconnected");
      }
      break;
    case WStype_TEXT:
      onControlText((const char *)payload, length);
      break;
    case WStype_BIN:
      if (phonePtt && !espTalking && !micMonitor) {
        queuePhoneAudio(payload, length);
        lastPhoneAudioMs = millis();
      }
      break;
    default:
      break;
  }
}

static bool pttPressed() {
  static bool lastRaw = false;
  static bool stable = false;
  static uint32_t changedAt = 0;
  bool raw = digitalRead(PTT_PIN) == LOW;
  if (raw != lastRaw) {
    lastRaw = raw;
    changedAt = millis();
  }
  if (millis() - changedAt > 25) {
    stable = raw;
  }
  return stable;
}

static void updateLed() {
  if (STATUS_LED < 0) {
    return;
  }
  bool on = true;
  if (!apUp) {
    on = ((millis() / 120) % 2) == 0;
  } else if (clientNum < 0) {
    on = ((millis() / 400) % 2) == 0;
  } else if (espTalking || phonePtt || micMonitor) {
    on = ((millis() / 80) % 2) == 0;
  }
  digitalWrite(STATUS_LED, on ? HIGH : LOW);
}

static void bootBlink() {
  if (STATUS_LED < 0) {
    return;
  }
  pinMode(STATUS_LED, OUTPUT);
  for (int i = 0; i < 3; i++) {
    digitalWrite(STATUS_LED, HIGH);
    delay(90);
    digitalWrite(STATUS_LED, LOW);
    delay(90);
  }
}

static const char *resetName(esp_reset_reason_t reason) {
  switch (reason) {
    case ESP_RST_POWERON:
      return "power on";
    case ESP_RST_EXT:
      return "external reset";
    case ESP_RST_SW:
      return "software";
    case ESP_RST_PANIC:
      return "panic";
    case ESP_RST_INT_WDT:
      return "interrupt watchdog";
    case ESP_RST_TASK_WDT:
      return "task watchdog";
    case ESP_RST_WDT:
      return "watchdog";
    case ESP_RST_DEEPSLEEP:
      return "deep sleep";
    case ESP_RST_BROWNOUT:
      return "brownout";
    case ESP_RST_SDIO:
      return "sdio";
    default:
      return "other";
  }
}

static void startRadio() {
  // Drop the station profile saved by the dispenser sketch. A stored static
  // address must not come back and hide this access point.
  WiFi.persistent(false);
  WiFi.mode(WIFI_STA);
  WiFi.disconnect(true, true);
  delay(80);
  WiFi.mode(WIFI_OFF);
  delay(80);

  IPAddress ip(192, 168, 4, 1);
  IPAddress gateway(192, 168, 4, 1);
  IPAddress mask(255, 255, 255, 0);
  WiFi.mode(WIFI_AP);
  WiFi.setSleep(false);
  WiFi.softAPConfig(ip, gateway, mask);
  apUp = WiFi.softAP(AP_SSID, AP_PASS, 6, 0, 2);
  if (!apUp) {
    Serial.println("Wi-Fi access point failed");
    return;
  }
  WiFi.setSleep(false);
  Serial.print("Wi-Fi up at ");
  Serial.println(WiFi.softAPIP());
  Serial.printf("Join %s / %s  then ws://192.168.4.1:%u/\n", AP_SSID, AP_PASS,
                (unsigned)WS_PORT);
}

static void startAudio() {
  i2sAmp.setPins(AMP_BCLK, AMP_WS, AMP_DOUT, -1);
  if (!i2sAmp.begin(I2S_MODE_STD, SAMPLE_RATE, I2S_DATA_BIT_WIDTH_16BIT, I2S_SLOT_MODE_STEREO)) {
    Serial.println("Speaker I2S failed. Check GPIO 27, 26 and 22.");
  } else {
    Serial.println("Speaker I2S ready");
  }

  i2sMic.setPins(MIC_BCLK, MIC_WS, -1, MIC_DIN);
  if (!i2sMic.begin(I2S_MODE_STD, SAMPLE_RATE, I2S_DATA_BIT_WIDTH_32BIT, I2S_SLOT_MODE_STEREO)) {
    Serial.println("Microphone I2S failed. Check GPIO 33, 25 and 32.");
  } else {
    i2sMic.setTimeout(200);
    Serial.println("Microphone I2S ready");
  }

  playRing = xRingbufferCreate(RING_BYTES, RINGBUF_TYPE_BYTEBUF);
  if (playRing == nullptr) {
    Serial.println("Audio buffer allocation failed");
  }
}

void setup() {
  Serial.begin(115200);
  delay(50);
  bootBlink();
  Serial.println();
  Serial.println("Intercom test");
  Serial.printf("Reset: %s\n", resetName(esp_reset_reason()));
  pinMode(PTT_PIN, INPUT_PULLUP);
  startRadio();
  startAudio();
  if (apUp) {
    webSocket.begin();
    webSocket.onEvent(onWsEvent);
    Serial.println("WebSocket ready");
  }
}

void loop() {
  if (apUp) {
    webSocket.loop();
  }
  if (pendingReady && clientNum >= 0) {
    pendingReady = 0;
    wsSendText("READY");
  }
  updateLed();

  bool button = pttPressed();
  if (phonePtt && (millis() - lastPhoneAudioMs > 800)) {
    phonePtt = 0;
    flushPhoneAudio();
  }

  if (button) {
    flushPhoneAudio();
    if (!espTalking) {
      espTalking = 1;
      Serial.println("Box PTT down");
      wsSendText("1");
    }
    size_t count = 0;
    if (!readMic(micPcm, &count)) {
      delay(8);
      return;
    }
    if (clientNum >= 0) {
      wsSendPcm(micPcm, count);
    } else {
      writeSpeaker(micPcm, count);
    }
    return;
  }

  if (espTalking) {
    espTalking = 0;
    Serial.println("Box PTT up");
    wsSendText("0");
  }

  if (micMonitor) {
    flushPhoneAudio();
    size_t count = 0;
    if (!readMic(micPcm, &count)) {
      delay(8);
      return;
    }
    writeSpeaker(micPcm, count);
    return;
  }

  if (phonePtt) {
    if (!playPhoneAudio()) {
      delay(2);
    }
    return;
  }

  flushPhoneAudio();
  delay(8);
}
