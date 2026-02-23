#include <Servo.h>

Servo servo1;
Servo servo2;

// 핀 설정
const int sensorPin1 = A0;
const int sensorPin2 = A5;
const int servo1Pin = 3;
const int servo2Pin = 10;

bool isActivated = false; // 모터 작동 상태 기억

void setup() {
  Serial.begin(115200); 
  
  servo1.attach(servo1Pin);
  servo2.attach(servo2Pin);
  
  // FS90R 초기 정지 상태 (미세하게 돌면 90 주변 값으로 조정하세요)
  servo1.write(90);
  servo2.write(90);
}

void loop() {
  // 1. 센서 1 읽기 (더블 리딩: 앞의 쓰레기값 버리기)
  analogRead(sensorPin1); 
  delayMicroseconds(100);
  int raw1 = analogRead(sensorPin1);

  // 2. 센서 2 읽기 (더블 리딩)
  analogRead(sensorPin2);
  delayMicroseconds(100);
  int raw2 = analogRead(sensorPin2);

  // 3. MATLAB으로 전송
  Serial.print(raw1);
  Serial.print(",");
  Serial.println(raw2);

  // 4. MATLAB 명령에 따른 모터 제어
  if (Serial.available() > 0) {
    char cmd = Serial.read(); 
    
    if (cmd == '1' && !isActivated) {
      servo1.write(180); 
      servo2.write(180);
      delay(1000);       
      servo1.write(90);  
      servo2.write(90);
      isActivated = true; 
    } 
    else if (cmd == '0' && isActivated) {
      servo1.write(0);   
      servo2.write(0);
      delay(1000);       
      servo1.write(90);  
      servo2.write(90);
      isActivated = false; 
    }
  }
  
  delay(20); // 통신 안정화
}