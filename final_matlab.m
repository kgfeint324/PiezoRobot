% ==========================================
% 피에조 & 모터 제어 (Y축 범위 넉넉하게 조정)
% ==========================================
clear; clc; clear arduinoObj;

% --- 1. 통신 설정 ---
port = "COM3";       % ★ 본인의 포트 번호로 수정!
baudrate = 115200;   
try
    arduinoObj = serialport(port, baudrate);
    configureTerminator(arduinoObj, "CR/LF"); 
    flush(arduinoObj); 
catch
    disp('아두이노 연결 실패. 포트 번호를 확인하세요.');
    return;
end

% --- 2. 초기 0점(Baseline) 정밀 측정 ---
disp('⚠️ 손을 움직이지 말고 가만히 계세요! 3초간 초기 영점(2.5V)을 측정합니다...');
pause(1);

calib_samples = 50; 
base1_sum = 0; base2_sum = 0;
valid_counts = 0;

while valid_counts < calib_samples
    rawData = readline(arduinoObj);
    if ~isempty(rawData)
        sensorValues = str2double(split(rawData, ","));
        if length(sensorValues) == 2 && ~any(isnan(sensorValues))
            base1_sum = base1_sum + sensorValues(1);
            base2_sum = base2_sum + sensorValues(2);
            valid_counts = valid_counts + 1;
        end
    end
end
% 완벽한 평균 영점 계산
init_offset1 = base1_sum / calib_samples;
init_offset2 = base2_sum / calib_samples;
fprintf('✅ 영점 측정 완료! -> 필름1: %.1f | 필름2: %.1f\n', init_offset1, init_offset2);

% --- 3. 그래프 창 설정 ---
f = figure('Name', 'Enhanced Piezo Control', 'Color', 'w');

sub1 = subplot(2, 1, 1);
hLine1_Raw = animatedline('Color', 'r', 'LineWidth', 1.5);
hLine2_Raw = animatedline('Color', 'b', 'LineWidth', 1.5);
title('Filtered Signal (Zero-Centered)'); grid on; 
ylim([-400, 400]); % ★ Y축 범위를 넉넉하게 넓힘 (-400 ~ 400)
legend('Film 1 (Red)', 'Film 2 (Blue)');

sub2 = subplot(2, 1, 2);
hLine1_Int = animatedline('Color', 'r', 'LineWidth', 2);
hLine2_Int = animatedline('Color', 'b', 'LineWidth', 2);
title('Integrated Bending Estimation'); grid on; 
ylim([-3000, 3000]); % ★ 적분값 범위도 넉넉하게 넓힘 (-3000 ~ 3000)
legend('Int Film 1', 'Int Film 2');

% --- 4. 핵심 변수 및 파라미터 ---
alpha = 0.1;          
gain = 10.0;          % 신호 증폭률 (10배)
sensitivity = 10.0;   % 적분 감도
deadZone = 3.0;       % 증폭 전 순수 데이터의 데드존

filtVal1 = init_offset1; filtVal2 = init_offset2; 
offset1 = init_offset1;  offset2 = init_offset2;   
integral1 = 0; integral2 = 0; 
prevTime = 0;       

% ★★★ 모터 작동 임계값 ★★★
% 적분 범위가 늘어났으니 기준값도 직접 꺾어보시고 적절히 조절하세요!
threshold1 = 1000; 
threshold2 = 1000; 

% 자동 영점 조절 로직 변수
stdThreshold = 10.0;     
hasActionHistory = false;
stableStartTime = [];    
lastZeroTime = -999;     
zeroDelay = 3.0;         
cooldownDuration = 5.0;  
bufferLen = 50;          
buf1 = ones(1, bufferLen) * init_offset1; 
buf2 = ones(1, bufferLen) * init_offset2;
bufIdx = 1;

startTimer = tic;        
x = 0;                   
updateInterval = 3;      

disp('시스템 시작! 움직임을 감지합니다... (그래프 창을 확인하세요)');

% --- 5. 메인 실시간 루프 ---
while true
    dataLine = readline(arduinoObj);
    
    if ~isempty(dataLine)
        dataNumbers = str2double(split(dataLine, ',')); 
        
        if length(dataNumbers) == 2 && ~any(isnan(dataNumbers))
            raw1 = dataNumbers(1); 
            raw2 = dataNumbers(2); 
            
            % 필터링
            filtVal1 = (alpha * raw1) + ((1 - alpha) * filtVal1);
            filtVal2 = (alpha * raw2) + ((1 - alpha) * filtVal2);
            
            buf1(bufIdx) = filtVal1; buf2(bufIdx) = filtVal2;
            bufIdx = bufIdx + 1;
            if bufIdx > bufferLen, bufIdx = 1; end
            
            curTime = toc(startTimer);
            if prevTime == 0, prevTime = curTime; end
            dt = curTime - prevTime; 
            prevTime = curTime;
            
            % 오프셋 제거 (순수 꺾임 양)
            raw_diff1 = filtVal1 - offset1;
            raw_diff2 = filtVal2 - offset2;
            
            % 데드존 적용
            if abs(raw_diff1) < deadZone, raw_diff1 = 0; end
            if abs(raw_diff2) < deadZone, raw_diff2 = 0; end
            
            % 신호 증폭
            val1 = raw_diff1 * gain;
            val2 = raw_diff2 * gain;
            
            % 적분
            integral1 = integral1 + (val1 * dt * sensitivity);
            integral2 = integral2 + (val2 * dt * sensitivity);
            
            % --- 인공지능급 영점 자동 조절 ---
            curStd1 = std(buf1); curStd2 = std(buf2); 
            isMoving = (curStd1 > stdThreshold) || (curStd2 > stdThreshold);
            
            statusMsg = "IDLE"; timerMsg = "0.0s";
            
            if (curTime - lastZeroTime) < cooldownDuration
                timeLeft = cooldownDuration - (curTime - lastZeroTime);
                statusMsg = "COOLDOWN";
                timerMsg = sprintf("Wait %.1fs", timeLeft);
                if isMoving, hasActionHistory = true; end
            else
                if isMoving
                    statusMsg = "MOVE";
                    hasActionHistory = true;
                    stableStartTime = [];
                else
                    statusMsg = "STABLE";
                    if hasActionHistory
                        if isempty(stableStartTime), stableStartTime = curTime; end
                        elapsedTime = curTime - stableStartTime;
                        timerMsg = sprintf("%.1f / %.1fs", elapsedTime, zeroDelay);
                        
                        if elapsedTime > zeroDelay
                            offset1 = mean(buf1); offset2 = mean(buf2); 
                            integral1 = 0; integral2 = 0;               
                            lastZeroTime = curTime; hasActionHistory = false; stableStartTime = [];
                            fprintf('✅ 안정 상태 감지: 0점 재설정 완료\n');
                        end
                    else
                        timerMsg = "Ready";
                    end
                end
            end
            
            % --- 모터 제어 명령 ---
            if integral1 > threshold1 && integral2 > threshold2
                write(arduinoObj, "1", "char");
            else
                write(arduinoObj, "0", "char");
            end

            x = x + 1;
            
            if mod(x, 30) == 0
                flush(arduinoObj, "input");
            end

            % --- 그래프 그리기 ---
            if mod(x, updateInterval) == 0
                addpoints(hLine1_Raw, curTime, val1); 
                addpoints(hLine2_Raw, curTime, val2);
                addpoints(hLine1_Int, curTime, integral1); 
                addpoints(hLine2_Int, curTime, integral2);
                
                if curTime > 15
                    xlim(sub1, [curTime-15, curTime]); 
                    xlim(sub2, [curTime-15, curTime]);
                end
                
                title(sub1, sprintf('Filtered Signal | Status: [%s] %s', statusMsg, timerMsg));
                drawnow limitrate; 
            end
        end
    end
end