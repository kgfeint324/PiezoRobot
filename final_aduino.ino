#include <Servo.h>

Servo servo1;

const int sensorPin1 = A0;
const int sensorPin2 = A5;
const int servo1Pin = 3;

const unsigned long rotateTime = 600; 
unsigned long motorStartTime = 0;     


int motorState = 0; 

char targetCmd = '0'; 

void setup() {
  Serial.begin(115200); 
  
  servo1.attach(servo1Pin);
  servo1.write(90);
}

void loop() {
  analogRead(sensorPin1); 
  delayMicroseconds(100);
  int raw1 = analogRead(sensorPin1);

  analogRead(sensorPin2);
  delayMicroseconds(100);
  int raw2 = analogRead(sensorPin2);

  Serial.print(raw1);
  Serial.print(",");
  Serial.println(raw2);

  if (Serial.available() > 0) {
    targetCmd = Serial.read(); 
  }
    
  if (targetCmd == '1' && motorState == 0) {
    servo1.write(0);                
    motorStartTime = millis();      
    motorState = 1;                 
  } 

  else if (targetCmd == '0' && motorState == 2) {
    servo1.write(180);              
    motorStartTime = millis();      
    motorState = 3;                 
  }
  

  unsigned long currentTime = millis(); 
  

  if (motorState == 1 && (currentTime - motorStartTime >= rotateTime)) {
    servo1.write(90);                 
    motorState = 2;                   
  }
 
  else if (motorState == 3 && (currentTime - motorStartTime >= rotateTime)) {
    servo1.write(90);                
    motorState = 0;                   
  }


  delay(20);
}