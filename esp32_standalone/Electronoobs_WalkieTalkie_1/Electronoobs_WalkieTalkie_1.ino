/*  Electronoobs ESP32 Walkie Talkie V1.1 (05/10/2025)
  Check tutorial on: https://electronoobs.com/eng_arduino_tut202.php
  Download PCB and schematic from the same page
  Make changes as you want!
  Consider supporting me on PATREON: https://www.patreon.com/electronoobs */

//Include libraries
#include <WiFi.h>
#include <esp_now.h>
#include <driver/i2s.h>
#include <SPI.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <Adafruit_NeoPixel.h>


//Define OLED screen
#define OLED_RESET     -1 // Reset pin # (or -1 if sharing Arduino reset pin)
#define SCREEN_ADDRESS 0x3C ///< See datasheet for Address; 0x3D for 128x64, 0x3C for 128x32
Adafruit_SSD1306 display(128, 32, &Wire, OLED_RESET);

//Inputs and outputs
#define I2S_WS      19  // L/R clock for INMP441 i2s microphone module
#define I2S_SCK     18  // BCLK for INMP441 i2s microphone module
#define I2S_SD      21  // Data out from INMP441 i2s microphone module
#define I2S_DOUT    5   // Data out pin for the MAX98357A i2s amplifier
#define LeftBut     4   // Left push button on the electronoobs PCB
#define MiddleBut   2   // Middle push button on the electronoobs PCB
#define RightBut    15  // Right push button on the electronoobs PCB
#define Vibrate     14  // Pin connected to vibrate driver on electronoobs PCB
#define Batery      34  // ADC pin to measure battery level (divider values R5=3.3K and R6=1K)
#define i2cSCL      25  // Defined pin for SCL of i2c port for OLED display
#define i2cSDA      26  // Defined pin for SDA of i2c port for OLED display
#define RBGLED      12  // WS2812B RBG LED connected on this pin

//Define WS2812B RGB LED settings
Adafruit_NeoPixel pixels(1, RBGLED, NEO_GRB + NEO_KHZ800);


//Code EDITABLE Varaiables
bool broadcast_mode = true;  //If broadcast mode is on, all the devices on the network will receive the message
//To get the ESP32 MAC run this line: Serial.println(WiFi.macAddress());
uint8_t BroadcastMac[] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};  // Receiver MAC address (replace with your receiver's MAC)
//uint8_t receiverMac[] = {0x78, 0x42, 0x1C, 0x6C, 0xCD, 0x18}; // Receiver MAC address (replace with your receiver's MAC)
//uint8_t receiverMac[] = {0x3C, 0x8A, 0x1F, 0x5E, 0xA1, 0x35}; // ESP on breadboard for tests
uint8_t receiverMac[] = {0xB4, 0xE6, 0x2D, 0xB7, 0x49, 0x1D};	  // ESP second PCB
const int GAIN = 5; // Software microphone gain multiplier (values 1-20 recommended)
const i2s_port_t I2S_SPEAKER_PORT = I2S_NUM_0;  //I2S channel 0 for the speaker amplifier
const i2s_port_t I2S_MIC_PORT = I2S_NUM_1;      //I2S channel 1 for the microphone


//Code CONSTANT Variables
bool LeftButState = true;   //Start with buttons state to high since it has pullup 
bool MiddleButState = true; //Start with buttons state to high since it has pullup 
bool RightButState = true;  //Start with buttons state to high since it has pullup 
bool sending = false;       //We start with sending mode off till we push the button
esp_err_t err;              //Variable to store the i2s errors in case we have one...


/////////////////////////////////////////////////////////////////
///////////////////SETUP THE MICROPGONE I2S//////////////////////
void setupI2SMic() {
  const i2s_config_t i2s_config_mic = {
    .mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_RX),
    .sample_rate = 16000,
    .bits_per_sample = I2S_BITS_PER_SAMPLE_16BIT,
    .channel_format = I2S_CHANNEL_FMT_ONLY_LEFT,
    .communication_format = I2S_COMM_FORMAT_I2S_MSB,
    .intr_alloc_flags = ESP_INTR_FLAG_LEVEL1,
    .dma_buf_count = 4,
    .dma_buf_len = 128,
    .use_apll = false,
    .tx_desc_auto_clear = false,
    .fixed_mclk = 0
  };

  const i2s_pin_config_t pin_config_mic = {
    .bck_io_num = I2S_SCK,
    .ws_io_num = I2S_WS,
    .data_out_num = I2S_PIN_NO_CHANGE,
    .data_in_num = I2S_SD
  };
  err = i2s_driver_install(I2S_MIC_PORT, &i2s_config_mic, 0, NULL);
  if (err != ESP_OK) {
    Serial.printf("Failed installing Microphone driver: %d\n", err);    
  }  
  err = i2s_set_pin(I2S_MIC_PORT, &pin_config_mic);
  if (err != ESP_OK) {
    Serial.printf("Failed setting microphone pins: %d\n", err);
  }
  i2s_zero_dma_buffer(I2S_MIC_PORT);
}
/////////////////////////////////////////////////////////////////


/////////////////////////////////////////////////////////////////
////////////////////SETUP THE AMPLIFIER I2S//////////////////////
void setupI2SAmplifier() {
  const i2s_config_t i2s_config_speaker = {
    .mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_TX),
    .sample_rate = 16000,
    .bits_per_sample = I2S_BITS_PER_SAMPLE_16BIT,
    .channel_format = I2S_CHANNEL_FMT_ONLY_LEFT,
    .communication_format = I2S_COMM_FORMAT_I2S_MSB,
    .intr_alloc_flags = 0,
    .dma_buf_count = 8,
    .dma_buf_len = 64,
    .use_apll = false,
    .tx_desc_auto_clear = true,
    .fixed_mclk = 0
  };

  const i2s_pin_config_t pin_config_speaker = {
    .bck_io_num = I2S_SCK,
    .ws_io_num = I2S_WS,
    .data_out_num = I2S_DOUT,
    .data_in_num = I2S_PIN_NO_CHANGE
  };
  err = i2s_driver_install(I2S_SPEAKER_PORT, &i2s_config_speaker, 0, NULL);
  if (err != ESP_OK) {
    Serial.printf("Failed installing Amplifier driver: %d\n", err);    
  }  
  err = i2s_set_pin(I2S_SPEAKER_PORT, &pin_config_speaker);
  if (err != ESP_OK) {
    Serial.printf("Failed setting speaker pins: %d\n", err);
  }
  i2s_zero_dma_buffer(I2S_SPEAKER_PORT);
}
/////////////////////////////////////////////////////////////////


/////////////////////////////////////////////////////////////////
/////////////////////SETUP OTHER RECEIVERS///////////////////////
void setPeer (){
  esp_now_peer_info_t peerInfo = {};     
  memcpy(peerInfo.peer_addr, receiverMac, 6);  
  peerInfo.channel = 0;
  peerInfo.encrypt = false;

  if (esp_now_add_peer(&peerInfo) != ESP_OK) {
    Serial.println("Failed to add peer");
    return;
  }
}
/////////////////////////////////////////////////////////////////


/////////////////////////////////////////////////////////////////
//////////WHAT HAPPENS WHEN WE RECEIVE DATA WITH ESPNOW//////////
void OnDataRecv(const uint8_t *info, const uint8_t *data, int len) {
  if (len > 0 && len <= 512 && len % 2 == 0) {
    size_t bytes_written;
    Serial.println("Received");
    if(!sending){
      i2s_write(I2S_SPEAKER_PORT, data, len, &bytes_written, portMAX_DELAY);
    }
  }
}
/////////////////////////////////////////////////////////////////


/////////////////////////////////////////////////////////////////
////////////WHAT HAPPENS WHEN WE SEND DATA WITH ESPNOW///////////
void OnDataSent(const uint8_t *mac_addr, esp_now_send_status_t status){
  Serial.println(status == ESP_NOW_SEND_SUCCESS ? "Delivery Success" : "Delivery Fail");
}
/////////////////////////////////////////////////////////////////




void setup() {  
  if(broadcast_mode){
    for(int i=0; i<6; i++){
      receiverMac[i] = BroadcastMac[i];
    }
  }
  

  pinMode(LeftBut, INPUT);                  //Define the left button on the PCB as input (1K pullup on PCB)
  pinMode(MiddleBut, INPUT);                //Define the middle button on the PCB as input (1K pullup on PCB)
  pinMode(RightBut, INPUT);                 //Define the right button on the PCB as input (1K pullup on PCB)
  pinMode(RBGLED, OUTPUT);                  //Define the pin connected to the LED as output
  digitalWrite(RBGLED, LOW);                //Start with LED pin in low
  pinMode(Vibrate, OUTPUT);                 //Define the pin connected to the BJT for vibration motor as output
  digitalWrite(Vibrate, LOW);               //Start the BJT for vibration motor in low
  
  Serial.begin(115200);                     //Start serial monitor for debug
  WiFi.mode(WIFI_STA);                      //Start wifi mode
  //setupI2SMic();                          //Setup the i2c microphone with given settings
  setupI2SAmplifier();                      //Setup the i2c MAX98357A audio amplifier

  if (esp_now_init() != ESP_OK) {           //Start ESP NOW
    Serial.println("ESP-NOW Init Failed");  
    return;
  }

  setPeer();                                //Set the receiver peer (only 1 for now, multiple channels in the future)

  esp_now_register_recv_cb(OnDataRecv);     //Start in receiver mode

  Wire.setPins(i2cSDA,i2cSCL);
  // SSD1306_SWITCHCAPVCC = generate display voltage from 3.3V internally
  if(!display.begin(SSD1306_SWITCHCAPVCC, SCREEN_ADDRESS)) {
    Serial.println(F("SSD1306 allocation failed"));
    for(;;); // Don't proceed, loop forever
  }

  String myMACaddr = WiFi.macAddress();
  display.clearDisplay();               // Clear Display
  display.setTextSize(1);               // Normal 1:1 pixel scale
  display.setTextColor(SSD1306_WHITE);  // Draw white text
  display.setCursor(0,0);               // Start at top-left corner
  display.println("MAC ADDRESS:");      //
  display.println(myMACaddr);           // Print my MAC address
  display.display();                    // Send data to the display

  pixels.begin(); // INITIALIZE NeoPixel strip object (REQUIRED)

  tone(Vibrate, 2000, 100);
  pixels.clear(); // Set all pixel colors to 'off'
  pixels.setPixelColor(0, pixels.Color(0, 150, 0));
  pixels.show();   // Send the updated pixel colors to the hardware.
  delay(300);
  pixels.clear(); // Set all pixel colors to 'off'
  pixels.show();   // Send the updated pixel colors to the hardware.
  tone(Vibrate, 2000, 100);
  Serial.println("ELECTRONOOBS Walkie Talkie All Set");
}




void loop() {
  /////////////////////////////////////////////////////////////////
  ////////////WHEN WE PRESS THE RIGHT BUTTON WE SEND AUDIO//////////
  if(!digitalRead(RightBut) && RightButState){
    RightButState = false;        
    //esp_now_register_recv_cb(NULL);         //Start in receiver mode         
    setupI2SMic();                            //Setup the i2c microphone with given settings
    esp_now_register_send_cb(OnDataSent); 
    //setPeer(); 
    sending = true;       
  }

  if(digitalRead(RightBut) && !RightButState){    
    setupI2SAmplifier();                      //Setup the i2c MAX98357A audio amplifier
    esp_now_register_recv_cb(OnDataRecv);
    RightButState = true;
    sending = false;  
  }//End of Right button push
  

  /////////////////////////////////////////////////////////////////////
  //WHEN "SENDING" VARIABLE IS 1 WE READ MICROPHONE AND SEND THE DATA//
  if(sending){
    const int samples = 100;  // 100 samples x 2 bytes = 200 bytes
    int16_t buffer[samples];
    size_t bytesRead;

    // Read I2S data from mic
    i2s_read(I2S_MIC_PORT, &buffer, sizeof(buffer), &bytesRead, portMAX_DELAY);

    if (bytesRead > 0) {
      // Apply software gain safely
      for (int i = 0; i < samples; i++) {
        int32_t amplified = buffer[i] * GAIN;        
        // Clamp to int16_t range to prevent overflow
        if (amplified > 32767) amplified = 32767;
        if (amplified < -32768) amplified = -32768;
        buffer[i] = (int16_t)amplified;
      
      }
      // Send audio buffer over ESP-NOW
      esp_err_t result = esp_now_send(receiverMac, (uint8_t*)buffer, bytesRead);
      //Serial.println(result == ESP_OK ? "Voice sent!" : "Send failed");
    }
    delay(2);  // Light throttle for stability
  }//End of "sending"
}//End of void loop

















