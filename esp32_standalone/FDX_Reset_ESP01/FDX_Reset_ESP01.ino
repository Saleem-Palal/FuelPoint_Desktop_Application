/**
 * FDX board hardware reset — ESP-01 / ESP-01S web pulse.
 *
 * Board: Generic ESP8266 Module (ESP-01 or ESP-01S)
 * Core: Arduino ESP8266
 * USB serial (via external USB-UART adapter): 115200
 *
 * Power pins:
 *   ESP-01 VCC   -> regulated 3.3 V DC only. Never put 5 V on VCC.
 *   ESP-01 GND   -> common DC ground.
 *   CH_PD (EN)   -> 3.3 V through a 10 kΩ pull-up, or a direct jumper to 3.3 V.
 *   RST          -> leave floating, or pull to 3.3 V through a 10 kΩ resistor.
 *   Relay VCC    -> relay-module supply (5 V or 3.3 V, whichever the module is rated for).
 *   Relay GND    -> common DC ground.
 *
 * Relay IN pin:
 *   Relay IN     -> GPIO0. This is the default control pin on ESP-01 1-channel relay shields.
 *   Active LOW.  GPIO0 LOW  energizes the relay and closes COM-NO across the FDX reset button.
 *                GPIO0 HIGH releases the relay and opens COM-NO.
 *   Relay COM and NO wire straight across the tactile reset button on the FDX processor board.
 *
 * Boot: GPIO0 must be HIGH while the ESP8266 bootloader runs. setup() drives it HIGH
 * before Wi-Fi or the web server start, so a power-up or ESP reboot cannot hold the
 * FDX processor in reset.
 *
 * Wi-Fi AP: SSID FDX_Reset_AP  password Password123  http://192.168.4.1/
 */

#include <ESP8266WiFi.h>
#include <ESP8266WebServer.h>

static const int RELAY_PIN = 0;
static const uint32_t RESET_PULSE_MS = 500;
static const uint32_t USB_BAUD = 115200;

static const char *AP_SSID = "FDX_Reset_AP";
static const char *AP_PASS = "Password123";
static const IPAddress AP_IP(192, 168, 4, 1);
static const IPAddress AP_GATEWAY(192, 168, 4, 1);
static const IPAddress AP_SUBNET(255, 255, 255, 0);

ESP8266WebServer server(80);

static const char INDEX_HTML[] PROGMEM = R"rawliteral(
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<title>FDX Hardware Reset</title>
<style>
  :root {
    --bg: #121212;
    --card: #1E1E1E;
    --ink: #F5F5F5;
    --muted: #A0A0A0;
    --ready: #3DDC97;
    --warn: #FFB300;
    --hot: #FF3B30;
    --ring: #2A2A2A;
  }
  * { box-sizing: border-box; }
  html, body {
    margin: 0;
    min-height: 100%;
    background: var(--bg);
    color: var(--ink);
    font-family: "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  }
  body {
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 24px 16px;
    -webkit-user-select: none;
    user-select: none;
    -webkit-touch-callout: none;
  }
  .card {
    width: min(440px, 100%);
    background: var(--card);
    border-radius: 28px;
    padding: 28px 22px 32px;
    text-align: center;
    box-shadow: 0 18px 50px rgba(0, 0, 0, 0.45);
  }
  .kicker {
    margin: 0 0 8px;
    letter-spacing: 0.22em;
    font-size: 12px;
    font-weight: 700;
    color: var(--muted);
  }
  h1 {
    margin: 0;
    font-size: 26px;
    line-height: 1.15;
    font-weight: 800;
    letter-spacing: 0.02em;
  }
  .status {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    margin-top: 16px;
    padding: 8px 14px;
    border-radius: 999px;
    background: #161616;
    font-size: 13px;
    font-weight: 800;
    letter-spacing: 0.08em;
  }
  .dot {
    width: 10px;
    height: 10px;
    border-radius: 50%;
    background: var(--ready);
    box-shadow: 0 0 10px var(--ready);
  }
  .status.warn .dot { background: var(--warn); box-shadow: 0 0 10px var(--warn); }
  .status.hot .dot { background: var(--hot); box-shadow: 0 0 10px var(--hot); }
  .hold {
    position: relative;
    width: 240px;
    height: 240px;
    margin: 28px auto 8px;
    touch-action: none;
  }
  svg.ring {
    position: absolute;
    inset: 0;
    width: 240px;
    height: 240px;
    transform: rotate(-90deg);
  }
  circle.track {
    fill: none;
    stroke: var(--ring);
    stroke-width: 12;
  }
  circle.fill {
    fill: none;
    stroke: var(--hot);
    stroke-width: 12;
    stroke-linecap: round;
    stroke-dasharray: 628.32;
    stroke-dashoffset: 628.32;
  }
  button.reset {
    position: absolute;
    left: 22px;
    top: 22px;
    width: 196px;
    height: 196px;
    border: 0;
    border-radius: 50%;
    background: radial-gradient(circle at 50% 40%, #3a3a3a, #141414 72%);
    color: var(--ink);
    font-size: 22px;
    font-weight: 800;
    letter-spacing: 0.12em;
    cursor: pointer;
    box-shadow: inset 0 0 0 2px #333, 0 10px 24px rgba(0, 0, 0, 0.35);
  }
  button.reset:active { background: radial-gradient(circle at 50% 40%, #4a201c, #1a0c0b 72%); }
  button.reset:disabled { cursor: default; opacity: 0.85; }
  .caption {
    min-height: 3.2em;
    margin: 12px 8px 0;
    font-size: 18px;
    font-weight: 800;
    letter-spacing: 0.03em;
    line-height: 1.3;
  }
  .warn {
    margin: 10px 0 0;
    min-height: 1.2em;
    color: var(--warn);
    font-size: 14px;
    font-weight: 700;
    opacity: 0;
    transition: opacity 0.15s linear;
  }
  .warn.show { opacity: 1; }
</style>
</head>
<body>
  <main class="card">
    <p class="kicker">FDX PROCESSOR</p>
    <h1>FDX BOARD HARDWARE RESET</h1>
    <div class="status" id="status"><span class="dot"></span><span id="statusText">SYSTEM READY</span></div>
    <div class="hold" id="hold">
      <svg class="ring" viewBox="0 0 240 240" aria-hidden="true">
        <circle class="track" cx="120" cy="120" r="100"></circle>
        <circle class="fill" id="ring" cx="120" cy="120" r="100"></circle>
      </svg>
      <button class="reset" id="resetBtn" type="button">RESET</button>
    </div>
    <p class="caption" id="caption">HOLD FOR 3 SECONDS TO RESET FDX</p>
    <p class="warn" id="warn">Reset Cancelled</p>
  </main>
<script>
(function () {
  var HOLD_MS = 3000;
  var CIRC = 2 * Math.PI * 100;
  var hold = document.getElementById('hold');
  var ring = document.getElementById('ring');
  var caption = document.getElementById('caption');
  var warn = document.getElementById('warn');
  var status = document.getElementById('status');
  var statusText = document.getElementById('statusText');
  var button = document.getElementById('resetBtn');
  var holding = false;
  var busy = false;
  var ignoreMouse = false;
  var started = 0;
  var raf = 0;
  var warnTimer = 0;

  ring.style.strokeDasharray = String(CIRC);
  ring.style.strokeDashoffset = String(CIRC);

  function setRing(progress) {
    var clamped = progress < 0 ? 0 : (progress > 1 ? 1 : progress);
    ring.style.strokeDashoffset = String(CIRC * (1 - clamped));
  }

  function setReady() {
    busy = false;
    button.disabled = false;
    status.className = 'status';
    statusText.textContent = 'SYSTEM READY';
    caption.textContent = 'HOLD FOR 3 SECONDS TO RESET FDX';
    setRing(0);
  }

  function flashCancelled() {
    warn.textContent = 'Reset Cancelled';
    warn.className = 'warn show';
    clearTimeout(warnTimer);
    warnTimer = setTimeout(function () {
      warn.className = 'warn';
    }, 1200);
  }

  function tick() {
    if (!holding) return;
    var elapsed = performance.now() - started;
    var progress = elapsed / HOLD_MS;
    if (progress >= 1) {
      holding = false;
      setRing(1);
      trigger();
      return;
    }
    setRing(progress);
    var left = Math.ceil((HOLD_MS - elapsed) / 1000);
    caption.textContent = 'KEEP HOLDING... (' + left + 's)';
    raf = requestAnimationFrame(tick);
  }

  function onDown(event) {
    if (busy || holding) return;
    if (event.type === 'mousedown' && (ignoreMouse || event.button !== 0)) return;
    if (event.cancelable) event.preventDefault();
    if (event.type === 'touchstart') ignoreMouse = true;
    holding = true;
    started = performance.now();
    warn.className = 'warn';
    status.className = 'status hot';
    statusText.textContent = 'HOLDING';
    tick();
  }

  function onUp(event) {
    if (event && event.type && event.type.indexOf('touch') === 0) {
      setTimeout(function () { ignoreMouse = false; }, 400);
    }
    if (!holding) return;
    if (event && event.cancelable) event.preventDefault();
    holding = false;
    cancelAnimationFrame(raf);
    setRing(0);
    status.className = 'status';
    statusText.textContent = 'SYSTEM READY';
    caption.textContent = 'HOLD FOR 3 SECONDS TO RESET FDX';
    flashCancelled();
  }

  function trigger() {
    busy = true;
    button.disabled = true;
    status.className = 'status hot';
    statusText.textContent = 'PULSE SENT';
    caption.textContent = 'RESTARTING FDX BOARD...';
    fetch('/api/reset', { method: 'POST' })
      .then(function (response) {
        if (!response.ok) throw new Error('reset failed');
        return response.json();
      })
      .then(function () {
        setTimeout(setReady, 2000);
      })
      .catch(function () {
        caption.textContent = 'RESET REQUEST FAILED';
        warn.textContent = 'No response from ESP-01';
        warn.className = 'warn show';
        clearTimeout(warnTimer);
        warnTimer = setTimeout(function () {
          warn.textContent = 'Reset Cancelled';
          warn.className = 'warn';
        }, 1600);
        setTimeout(setReady, 1600);
      });
  }

  hold.addEventListener('touchstart', onDown, { passive: false });
  hold.addEventListener('touchend', onUp, { passive: false });
  hold.addEventListener('touchcancel', onUp, { passive: false });
  hold.addEventListener('touchmove', function (event) {
    if (holding && event.cancelable) event.preventDefault();
  }, { passive: false });
  hold.addEventListener('mousedown', onDown);
  window.addEventListener('mouseup', onUp);
  hold.addEventListener('contextmenu', function (event) { event.preventDefault(); });
})();
</script>
</body>
</html>
)rawliteral";

void releaseRelay() {
  digitalWrite(RELAY_PIN, HIGH);
}

void handleRoot() {
  server.sendHeader("Cache-Control", "no-store");
  server.send_P(200, "text/html", INDEX_HTML);
}

void handleReset() {
  digitalWrite(RELAY_PIN, LOW);
  delay(RESET_PULSE_MS);
  releaseRelay();
  server.send(200, "application/json",
              "{\"status\":\"success\",\"message\":\"FDX Hardware Reset Pulse Executed\"}");
  Serial.println("FDX reset pulse complete");
}

void handleNotFound() {
  server.send(404, "text/plain", "Not found");
}

void setup() {
  pinMode(0, OUTPUT);
  digitalWrite(0, HIGH);

  Serial.begin(USB_BAUD);
  Serial.println();
  Serial.println("FDX reset ESP-01");
  Serial.println("GPIO0 HIGH — relay off");

  WiFi.persistent(false);
  WiFi.mode(WIFI_AP);
  WiFi.softAPConfig(AP_IP, AP_GATEWAY, AP_SUBNET);
  if (!WiFi.softAP(AP_SSID, AP_PASS)) {
    Serial.println("softAP failed");
  }

  server.on("/", HTTP_GET, handleRoot);
  server.on("/api/reset", HTTP_POST, handleReset);
  server.onNotFound(handleNotFound);
  server.begin();

  Serial.print("AP ");
  Serial.print(AP_SSID);
  Serial.print("  http://");
  Serial.println(WiFi.softAPIP());
}

void loop() {
  server.handleClient();
  // The 500 ms pulse finishes inside the POST handler before loop resumes.
  // Re-assert GPIO0 HIGH so a missed release cannot hold the FDX reset line.
  releaseRelay();
}
