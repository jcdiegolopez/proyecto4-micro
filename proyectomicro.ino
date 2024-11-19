/******************************************************
* Universidad del Valle de Guatemala
* Facultad de Ingeniería
* Curso: Microprocesadores
* Proyecto: Integración MPU6050, Seonsor pulso cardiaco y Google Sheets
* 
* Modificado: Grup
* Fecha: 15 Noviembre 2024
*
* Descripción: Monitoreo de bpm y aceleracion con sensores MPU6050 y sensos de pulso cardiaco
*******************************************************/



#include <ESP8266WiFi.h>
#include <WiFiClientSecure.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>
#include <Wire.h>
#include <PulseSensorPlayground.h>     // Includes the PulseSensorPlayground Library
#include <ESP8266TimerInterrupt.h>

#define ON_Board_LED 2       // LED en la placa, utilizado como indicador

Adafruit_MPU6050 mpu; //I2C
                               
PulseSensorPlayground pulseSensor;  // crear objeto de sensor de pulso

const int PulseWire = 0;       // 'S' Signal conectado al pin analogo
int Threshold = 550;           // Determinar cual contar como beat

const char* ssid = "Error502"; 	// Nombre de la red WiFi
const char* password = "Toby+Nowy77"; // Contraseña de la red WiFi

const char* host = "script.google.com";
const int httpsPort = 443;

WiFiClientSecure client; 				// Crear un objeto WiFiClientSecure

String GAS_ID = "AKfycbzO72XqnV9AyDmntEkFULc1MQS0VIH5uihLd8bA_Iqeiaw5uNvy1xQ8f4JgHYq8zRmi"; // ID del script de Google Sheets

void setup() {
  Serial.begin(115200);
 
  

  WiFi.begin(ssid, password); 			// Conectar a la red WiFi
  Serial.println("");
  pinMode(ON_Board_LED, OUTPUT); 		// Configurar el LED como salida
  digitalWrite(ON_Board_LED, HIGH); 	// Apagar el LED
  // Esperar conexión WiFi
  Serial.print("Conectando");
  while (WiFi.status() != WL_CONNECTED) {
    Serial.print(".");
    digitalWrite(ON_Board_LED, LOW); 	// Parpadeo del LED durante la conexión
    delay(250);
    digitalWrite(ON_Board_LED, HIGH);
    delay(250);
  }


  digitalWrite(ON_Board_LED, HIGH); 	// Apagar el LED una vez conectado
  Serial.println("");
  Serial.print("Conectado a: ");
  Serial.println(ssid);
  Serial.print("IP address: ");
  Serial.println(WiFi.localIP());
  client.setInsecure(); 				// Deshabilitar la verificación de certificados (no recomendado para producción)

  

  // Configure the PulseSensor object, by assigning our variables to it
	pulseSensor.analogInput(PulseWire);   
	pulseSensor.blinkOnPulse(ON_Board_LED);       // Blink on-board LED with heartbeat
	pulseSensor.setThreshold(Threshold);   

	// Double-check the "pulseSensor" object was created and began seeing a signal
	if (pulseSensor.begin()) {
		Serial.println("PulseSensor object created!");
	}
  
  if (!mpu.begin()) {
		Serial.println("Error al buscar MPU6050 chip");
		while (1) {
		  delay(10);
		}
	}
  Serial.println("MPU6050 encontrado!");
  // Configurar acelerometro a +-8G
  mpu.setAccelerometerRange(MPU6050_RANGE_8_G);
	// Configurar frecuencia de ancho de banda
	mpu.setFilterBandwidth(MPU6050_BAND_21_HZ);
	delay(100);

}

void loop() {
     sensors_event_t a, g, temp;
    mpu.getEvent(&a, &g, &temp);

    // Verificar si los datos del acelerómetro son válidos
    if (isnan(a.acceleration.x) || isnan(a.acceleration.y)) {
      Serial.println("¡Fallo al leer los datos del MPU6050!");
      delay(500);
      return;
    }

    // Leer los BPM del sensor de pulso
    int bpm = pulseSensor.getBeatsPerMinute();

    if (pulseSensor.sawStartOfBeat()) {
      Serial.println("♥ Latido detectado!");
    } else if (bpm <= 0) {
      Serial.println("¡Fallo al leer los BPM!");
      delay(500);
      return;
    }

    // Imprimir los valores directamente en el loop
    Serial.println("===== Datos actuales =====");
    Serial.println("BPM: " + String(bpm));
    Serial.println("Aceleración X: " + String(a.acceleration.x) + " m/s^2");
    Serial.println("Aceleración Y: " + String(a.acceleration.y) + " m/s^2");
    Serial.println("==========================");

    // Enviar los datos a Google Sheets
    sendData(bpm, a.acceleration.x, a.acceleration.y);
    
    delay(3000); 
}

// Subrutina para enviar los datos a Google Sheets
void sendData(float bpm, float acx, float acy) {
  Serial.println("==========");
  Serial.print("Conectando a ");
  Serial.println(host);
  
  // Conectar a Google
  if (!client.connect(host, httpsPort)) {
    Serial.println("Fallo en la conexión");
    return;
  }

  // Procesar y enviar datos
  String string_bpm = String(bpm);
  String string_acelx = String(acx);
  String string_acely = String(acy);
  String url = "/macros/s/" + GAS_ID + "/exec?bpm=" + string_bpm + "&acelx=" + string_acelx +"&acely=" + string_acely ;
  Serial.print("Solicitando URL: ");
  Serial.println(url);

  client.print(String("GET ") + url + " HTTP/1.1\r\n" +
         "Host: " + host + "\r\n" +
         "User-Agent: BuildFailureDetectorESP8266\r\n" +
         "Connection: close\r\n\r\n");

  Serial.println("Solicitud enviada");

  // Comprobar si  los datos se enviaron correctamente
  while (client.connected()) {
    String line = client.readStringUntil('\n');
    if (line == "\r") {
      Serial.println("Encabezados recibidos");
      break;
    }
  }

  String line = client.readStringUntil('\n');
  if (line.startsWith("{\"state\":\"success\"")) {
    Serial.println("ESP8266/Arduino CI exitoso");
  } else {
    Serial.println("ESP8266/Arduino CI recibe encabezado HTTP");
  }

  Serial.print("Respuesta: ");
  Serial.println(line);
  Serial.println("Cerrando conexión");
  Serial.println("==========");
}
