clear; clc; clear arduinoObj;
port = "COM3";
baudrate = 115200;   
try
    arduinoObj = serialport(port, baudrate);
    configureTerminator(arduinoObj, "CR/LF"); 
    flush(arduinoObj); 
catch
    disp('아두이노 연결 실패');
    return;
end

% UI창 띄우기
f = figure('Name', 'Enhanced Piezo Control & Dashboard', 'Color', 'w');
f.Position = [100, 100, 1000, 650];

set(f, 'CloseRequestFcn', @(src, event) stopSystem(src, arduinoObj));

% 중앙 전광판
sysMsgBox = annotation('textbox', [0.08, 0.92, 0.9, 0.06], 'String', '아두이노 연결 성공! 시스템 초기화 중...', ...
    'FontSize', 14, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', ...
    'BackgroundColor', '#ffffcc', 'EdgeColor', 'k');
sub1 = subplot(2, 1, 1);
sub1.Position = [0.08, 0.52, 0.65, 0.35]; 
hLine1_Raw = animatedline('Color', 'r', 'LineWidth', 1.5);
hLine2_Raw = animatedline('Color', 'b', 'LineWidth', 1.5);
title('Filtered Signal (Zero-Centered)'); grid on; 
ylim([-400, 400]); 
legend('Film 1 (Red)', 'Film 2 (Blue)', 'Location', 'northwest');
sub2 = subplot(2, 1, 2);
sub2.Position = [0.08, 0.08, 0.65, 0.35];
hLine1_Int = animatedline('Color', 'r', 'LineWidth', 2);
hLine2_Int = animatedline('Color', 'b', 'LineWidth', 2);
title('Integrated Bending Estimation'); grid on; 
ylim([-3000, 3000]); 
legend('Int Film 1', 'Int Film 2', 'Location', 'northwest');
dashBox1 = annotation('textbox', [0.76, 0.52, 0.22, 0.35], 'String', 'Sensor 1\nWait...', ...
    'FontSize', 12, 'BackgroundColor', '#fff0f0', 'EdgeColor', 'r', 'LineWidth', 1.5, 'Margin', 10);
dashBox2 = annotation('textbox', [0.76, 0.08, 0.22, 0.35], 'String', 'Sensor 2\nWait...', ...
    'FontSize', 12, 'BackgroundColor', '#f0f0ff', 'EdgeColor', 'b', 'LineWidth', 1.5, 'Margin', 10);

% 초기 영점 측정
set(sysMsgBox, 'String', '3초간 초기 영점(2.5V)을 측정합니다. 센서를 가만히 두세요!', 'BackgroundColor', '#ffeb99');
drawnow;
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
init_offset1 = base1_sum / calib_samples;
init_offset2 = base2_sum / calib_samples;

% 영점 측정 완료 알림
set(sysMsgBox, 'String', sprintf(' 영점 측정 완료! (더블 탭으로 언제든 재설정 가능)'), 'BackgroundColor', '#ccffcc');
drawnow;
pause(1);

alpha = 0.1;          % 필터값은 여기에서 조정
gain1 = 10.0;         
gain2 = 25.0;         
sensitivity = 10.0;   
deadZone = 3.0;       
medWindowSize = 5;    

% 급발진 방지 필터 수치
maxSpeed = 1000;      % 낮을수록 노이즈 더 많이 잡음
prevRaw1 = init_offset1;
prevRaw2 = init_offset2;
rawBuf1 = ones(1, medWindowSize) * init_offset1;
rawBuf2 = ones(1, medWindowSize) * init_offset2;
rawBufIdx = 1;
filtVal1 = init_offset1; filtVal2 = init_offset2; 
offset1 = init_offset1;  offset2 = init_offset2;   
integral1 = 0; integral2 = 0; 
prevTime = 0;       

threshold1 = 150;     
threshold2 = 150;  
bendLimit = 150;      
bufferLen = 50;          
buf1 = ones(1, bufferLen) * init_offset1; 
buf2 = ones(1, bufferLen) * init_offset2;
bufIdx = 1;

tapThreshold = 80;     
tapCount = 0;          
lastTapTime = 0;       
tapWindow = 1.0;       
tapCooldown = 0.3;     
tapDirection = 0;      
startTimer = tic;        
x = 0;                   
updateInterval = 3;      
lastSentCmd = "0"; 

% 기본 상태로 복구
set(sysMsgBox, 'String', ' 정상 작동 중... (센서 2를 더블 탭하여 영점 초기화 가능)', 'BackgroundColor', '#ffffff');

while ishandle(f)
    dataLine = readline(arduinoObj);
    
    if ~isempty(dataLine)
        dataNumbers = str2double(split(dataLine, ',')); 
        
        if length(dataNumbers) == 2 && ~any(isnan(dataNumbers))
            raw1 = dataNumbers(1); 
            raw2 = dataNumbers(2); 
            
            % 급발진 방지 필터(수치 조정은 위에 코드)
            if abs(raw1 - prevRaw1) > maxSpeed
                raw1 = prevRaw1; 
            else
                prevRaw1 = raw1; 
            end
            if abs(raw2 - prevRaw2) > maxSpeed
                raw2 = prevRaw2; 
            else
                prevRaw2 = raw2;
            end
            
            % 미디언 필터
            rawBuf1(rawBufIdx) = raw1;
            rawBuf2(rawBufIdx) = raw2;
            
            rawBufIdx = rawBufIdx + 1;
            if rawBufIdx > medWindowSize
                rawBufIdx = 1; 
            end
            
            med1 = median(rawBuf1);
            med2 = median(rawBuf2);
            
            % 저주파 필터
            filtVal1 = (alpha * med1) + ((1 - alpha) * filtVal1);
            filtVal2 = (alpha * med2) + ((1 - alpha) * filtVal2);
            
            buf1(bufIdx) = filtVal1; buf2(bufIdx) = filtVal2;
            bufIdx = bufIdx + 1;
            if bufIdx > bufferLen, bufIdx = 1; end
            
            curTime = toc(startTimer);
            if prevTime == 0, prevTime = curTime; end
            dt = curTime - prevTime; 
            prevTime = curTime;
            
            % 데드존 설정
            raw_diff1 = filtVal1 - offset1;
            raw_diff2 = filtVal2 - offset2;
            
            if abs(raw_diff1) < deadZone, raw_diff1 = 0; end
            if abs(raw_diff2) < deadZone, raw_diff2 = 0; end
            
            val1 = raw_diff1 * gain1;
            val2 = raw_diff2 * gain2;
            
            integral1 = integral1 + (val1 * dt * sensitivity);
            integral2 = integral2 + (val2 * dt * sensitivity);
            
            statusMsg = "READY"; 
            
            % 더블탭 코드
            isPeak = abs(val2) > tapThreshold; 
            
            if isPeak && (curTime - lastTapTime > tapCooldown)
                if tapCount == 0
                    tapCount = 1;
                    lastTapTime = curTime;
                    tapDirection = sign(val2);
                    statusMsg = "TAP 1!";
                    set(sysMsgBox, 'String', ' 손목(센서 2) 꺾임 감지! ', 'BackgroundColor', '#ffe6cc');
                elseif tapCount == 1 && (curTime - lastTapTime <= tapWindow)
                    if sign(val2) == tapDirection % 두 번째 방향이 첫 번째와 같을 때만 인정
                        offset1 = mean(buf1); 
                        offset2 = mean(buf2);
                        integral1 = 0; 
                        integral2 = 0;
                        tapCount = 0; 
                        lastTapTime = curTime;
                        statusMsg = "RESET!";
                        set(sysMsgBox, 'String', ' 영점 재측정 및 초기화 완료! ', 'BackgroundColor', '#ccffcc');
                    else
                        % 방향이 다르면 반동이므로 무시
                        disp('오작동 방지: 다른 방향의 탭이 감지되어 무시합니다.');
                    end
                end
            end
            
            if tapCount == 1 && (curTime - lastTapTime > tapWindow)
                tapCount = 0;
                set(sysMsgBox, 'String', ' 정상 작동 중... (더블 탭 취소됨)', 'BackgroundColor', '#ffffff');
            end
            
            if tapCount == 1
                timerMsg = sprintf("Wait 2nd Tap... (%.1fs)", tapWindow - (curTime - lastTapTime));
            else
                timerMsg = "Normal";
            end
            
            if abs(val1) > 0, moveState1 = '〰️ 꺾이는 중 (Moving)'; else, moveState1 = ' 가만히 있음 (Stable)'; end
            if integral1 > bendLimit, bendState1 = ' 위로 구부러짐 (+)'; elseif integral1 < -bendLimit, bendState1 = ' 아래로 구부러짐 (-)'; else, bendState1 = ' 평형 상태 (0)'; end
            
            if abs(val2) > 0, moveState2 = '〰️ 꺾이는 중 (Moving)'; else, moveState2 = ' 가만히 있음 (Stable)'; end
            if integral2 > bendLimit, bendState2 = ' 위로 구부러짐 (+)'; elseif integral2 < -bendLimit, bendState2 = ' 아래로 구부러짐 (-)'; else, bendState2 = ' 평형 상태 (0)'; end
            
            % 두 센서 모두 150을 넘어야 모터 작동
            if integral1 > threshold1 && integral2 > threshold2
                targetCmd = "1";
            else
                targetCmd = "0";
            end
            
            if targetCmd ~= lastSentCmd
                write(arduinoObj, targetCmd, "char");
                lastSentCmd = targetCmd; 
                
                if targetCmd == "1"
                    set(sysMsgBox, 'String', ' 모터 작동 (1)', 'BackgroundColor', '#ffb3b3');
                else
                    set(sysMsgBox, 'String', ' 모터 원상 (0)', 'BackgroundColor', '#cce6ff');
                end
            end
            
            x = x + 1;
            
            if mod(x, 30) == 0
                flush(arduinoObj, "input");
            end
            
            if mod(x, updateInterval) == 0
                addpoints(hLine1_Raw, curTime, val1); 
                addpoints(hLine2_Raw, curTime, val2);
                addpoints(hLine1_Int, curTime, integral1); 
                addpoints(hLine2_Int, curTime, integral2);
                
                if curTime > 15
                    xlim(sub1, [curTime-15, curTime]); 
                    xlim(sub2, [curTime-15, curTime]);
                end
                
                title(sub1, sprintf('Filtered Signal | System Status: [%s] %s', statusMsg, timerMsg));
                
                dashText1 = sprintf(' [ 센서 1 상태 ]\n\n동작: %s\n형태: %s\n\n적분값: %.0f', ...
                    moveState1, bendState1, integral1);
                set(dashBox1, 'String', dashText1);
                
                dashText2 = sprintf(' [ 센서 2 상태 ]\n\n동작: %s\n형태: %s\n\n적분값: %.0f', ...
                    moveState2, bendState2, integral2);
                set(dashBox2, 'String', dashText2);
                drawnow limitrate; 
            end 
        end     
    end         
end

% 시스템 종료
function stopSystem(fig, arduino)
    disp('시스템 종료 요청 감지. 안전 종료 절차를 시작합니다...');
    try
        write(arduino, "0", "char");
        pause(0.5);
    catch
        disp('모터 복귀 명령 전송 실패');
    end
    delete(arduino);
    delete(fig);
end