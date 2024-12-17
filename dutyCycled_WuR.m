% Virtual WuR-enabled BLE heart rate implant and central communication Simulation

% Simulated WuR Device State
isDeviceAwake = false; % Initial state: Device is in low-power sleep mode
isReconnectionRequired = false; % To simulate random reconnection events
disp('BLE device is in sleep mode.');

% Cache for discovered data (services, characteristics, and descriptors)
cache = struct('services', [], 'characteristics', [], 'descriptors', []);
isCacheInitialized = false; % Keeps track of whether cache is initialized

% Emergency heart rate notification threshold
heartRateThreshold = 140;

% Seed the random number generator based on the current time
rng('shuffle');

% Wake-up interval (in seconds)
wakeUpInterval = 5;

% Initialize the simulation time
currentTime = 0;

% Initialize the array to store pcapPackets
pcapPackets = cell(1, 11); 
count = 1;

% Open a log file to write state transitions
logFile = fopen('state_log.txt', 'w');

% Simulation time limit (in seconds)
simulationTimeLimit = 20 * 60; % 20 minutes in seconds

% Start the simulation time tracking
simulationStartTime = tic; % Start a timer to track the simulation duration

% Continuous simulation loop with wake-up radio logic
while true
    % Check if the simulation has exceeded the time limit
    elapsedTime = toc(simulationStartTime); % Get the elapsed time in seconds
    if elapsedTime >= simulationTimeLimit
        disp('Simulation time limit reached. Ending simulation.');
        break; % Exit the simulation loop
    end
    
    % Increment the current time by 1 second
    currentTime = currentTime + 1;
    
    % Randomly trigger reconnection events to mimic connection loss
    if ~isReconnectionRequired && rand() > 0.999 % Randomly initiate reconnection
        isReconnectionRequired = true;
        disp('Random reconnection event triggered.');
    end
    
    % Determine if the current time is within the wake-up interval
    if mod(currentTime, wakeUpInterval) == 1 || isReconnectionRequired
        if isReconnectionRequired
            fprintf(logFile, 'Time %ds: Wake-up radio is awake and checking for a signal.\n', currentTime);
            currentTime = currentTime + 1;
            pause(1);
            disp(['Time ' num2str(currentTime) 's: Reconnection required.']);
            fprintf(logFile, 'Time %ds: Device forgotten, reconnection required.\n', currentTime);
        else
            % Wake-up radio is checking for a signal
            disp(['Time ' num2str(currentTime) 's: Wake-up radio is awake and checking for a signal.']);
            fprintf(logFile, 'Time %ds: Wake-up radio is awake and checking for a signal.\n', currentTime);
        end

        % Initialize signalDetected to false for this interval
        signalDetected = false;

        % Check for a signal during the wake-up interval or reconnection event
        for t = 1:wakeUpInterval
            % Generate a random number between 0 and 1 for detection chance
            detectionChance = rand();
            
            % Random threshold for detection chance between 0.9 and 1
            threshold = 0.83 + (1 - 0.83) * rand();
            
            % Determine if the WuR device wakes up based on detection chance or reconnection
            if detectionChance > threshold || isReconnectionRequired
                isDeviceAwake = true;
                signalDetected = true;
                
                % WuR is now active, processing the wake-up signal or reconnection
                disp(['Time ' num2str(currentTime) 's: Wake-up signal detected. WuR is active and processing the signal.']);
                fprintf(logFile, 'Time %ds: Wake-up signal detected. WuR is active and processing the wake-up signal.\n', currentTime);
                
                % Pause for 1 second to simulate the WuR being active while processing the wake-up signal
                pause(1);
                
                % BLE device wakes up and begins communication
                currentTime = currentTime + 1;
                disp(['Time ' num2str(currentTime) 's: BLE device is now awake and communicating.']);
                fprintf(logFile, 'Time %ds: BLE device is now awake and communicating.\n', currentTime);
                
                % Only perform full discovery if cache is not initialized or reconnection occurs
                if ~isCacheInitialized || isReconnectionRequired
                    % Perform service, characteristic, and descriptor discovery
                    fprintf("Generated Advertisement Indication PDU by GATT server.\n");
                    fprintf(logFile, 'Time %ds: Implant (GATT Server) is transmitting advertising indication.\n', currentTime); 
                    
                    % Generate the BLE LL advertising channel PDU
                    serverAdvPDU = bleLLAdvertisingChannelPDUConfig;
                    serverAdvPDU.AdvertisingData = '0201060841494442'; 

                    % Generate the Bluetooth LE LL advertising channel PDU
                    advLLpdu = bleLLAdvertisingChannelPDU(serverAdvPDU);
                    serverAdvPDU

                    pcapPackets{count} = advLLpdu;
                    count = count + 1;

                    currentTime = currentTime + 1;
                    pause(1);

                    % Log or export the PDU for further analysis
                    fprintf("Generated Connection Indication PDU for Advertising Channel.\n");
                    fprintf(logFile, 'Time %ds: Implant (GATT Server) is receiving connection indication.\n', currentTime);

                    % Handle client PDU creation and connection
                    clientAdvPDU = bleLLAdvertisingChannelPDUConfig('PDUType', 'Connection indication');
                    clientAdvPDU.ConnectionInterval = 6; 
                    clientAdvPDU.UsedChannels = [3 5 12 17 19 30 32]; 

                    % Generate the connection indication PDU
                    advLLpdu = bleLLAdvertisingChannelPDU(clientAdvPDU);
                    clientAdvPDU

                    pcapPackets{count} = advLLpdu;
                    count = count + 1;

                    currentTime = currentTime + 1;
                    pause(1);
                    % ------------------ Begin GATT Communication ------------------
                    
                    % --- Service Discovery ---
                    fprintf(logFile, 'Time %ds: Implant (GATT Server) is receiving service discovery request.\n', currentTime);
                    
                     % Create GATT client to discover services available at the server
                    gattServer = helperBLEGATTServer;
                    gattClient = helperBLEGATTClient;
                    gattClient.SubProcedure = 'Discover all primary services';

                    % Generate service discovery request PDU (central device action)
                    serviceDiscReqPDU = generateATTPDU(gattClient);
                    
                    % Transmit the service discovery request to the server
                    [bleWaveform, pcapPackets{count}] = helperBLETransmitData(serviceDiscReqPDU);
                    count = count + 1;
                    
                    currentTime = currentTime + 1;
                    pause(1);
                    
                    % GATT Server: Implant responds to the service discovery
                    fprintf(logFile, 'Time %ds: Implant (GATT Server) is transmitting service discovery.\n', currentTime);
                    
                    % Decode and store the discovered services in cache
                    receivedPDU = helperBLEDecodeData(bleWaveform);
                    [attServerRespPDU, serviceDiscReqCfg, gattServer] = receiveData(gattServer, receivedPDU);
                    cache.services = serviceDiscReqCfg; % Store in cache
                    isCacheInitialized = true; % Mark cache as initialized

                    % Generate the response PDU (server response)
                    [attServerRespPDU, serviceDiscReqCfg, gattServer] = receiveData(gattServer, receivedPDU);

                    serviceDiscReqCfg

                    % Transmit the service discovery response
                    [bleWaveform, pcapPackets{count}] = helperBLETransmitData(attServerRespPDU);
                    count = count + 1;

                    currentTime = currentTime + 1;
                    pause(1);

                    % Decode the received BLE waveform
                    receivedPDU = helperBLEDecodeData(bleWaveform);

                    % Decode the received ATT PDU and handle the response
                    [~, serviceDiscRespCfg] = receiveData(gattClient, receivedPDU);
                    gattClient.StartHandle = serviceDiscRespCfg.StartHandle;
                    gattClient.EndHandle = serviceDiscRespCfg.EndHandle;

                    % Log the service discovery response
                    if strcmp(serviceDiscRespCfg.Opcode, 'Error response')
                        fprintf(logFile, 'Received error response at the client:\n');
                        serviceDiscRespCfg
                    else
                        fprintf("Received service discovery response at the client:\n")
                        serviceDiscRespCfg
                        service = helperBluetoothID.getBluetoothName(serviceDiscRespCfg.AttributeValue);
                        serviceDiscRespMsg = ['Service discovery response(''' service ''')'];
                    end

                    currentTime = currentTime + 1;
                    pause(1);

                    % --- Characteristic Discovery ---
                    % GATT Client: Central Device initiates characteristic discovery
                    fprintf(logFile, 'Time %ds: Implant (GATT Server) is receiving characteristic discovery request.\n', currentTime);

                    % Configure the GATT client to discover all characteristics
                    gattClient.SubProcedure = 'Discover all characteristics of service';
                    chrsticDiscReqPDU = generateATTPDU(gattClient);

                    % Transmit the characteristic discovery request
                    [bleWaveform, pcapPackets{count}] = helperBLETransmitData(chrsticDiscReqPDU);
                    count = count + 1;

                    currentTime = currentTime + 1;
                    pause(1);

                    % GATT Server: Implant responds to characteristic discovery
                    fprintf(logFile, 'Time %ds: Implant (GATT Server) is transmitting characteristic discovery.\n', currentTime);

                    % Decode the received BLE waveform
                    receivedPDU = helperBLEDecodeData(bleWaveform);

                    % Generate the characteristic discovery response PDU (server response)
                    [chrsticDiscRespPDU, chrsticDiscReqCfg, gattServer] = receiveData(gattServer, receivedPDU);
                    chrsticDiscReqCfg


                    % Transmit the characteristic discovery response
                    [bleWaveform, pcapPackets{count}] = helperBLETransmitData(chrsticDiscRespPDU);
                    count = count + 1;

                    currentTime = currentTime + 1;
                    pause(1);

                    % Decode the received BLE waveform
                    receivedPDU = helperBLEDecodeData(bleWaveform);

                    % Decode the received ATT PDU and handle the response
                    [~, chrsticDiscRespCfg] = receiveData(gattClient, receivedPDU);

                    % Log the characteristic discovery response
                    if strcmp(chrsticDiscRespCfg.Opcode, 'Error response')
                        fprintf(logFile, 'Received error response at the client:\n');
                        chrsticDiscRespCfg
                    else
                        fprintf("Received characteristic discovery response at the client:\n")
                        attributeValueCfg = helperBLEDecodeAttributeValue(...
                        chrsticDiscRespCfg.AttributeValue, 'Characteristic');
                        attributeValueCfg
                        chrsticDescRespMsg = ['Characteristic discovery response(''' attributeValueCfg.CharacteristicType ''')'];
                    end

                    currentTime = currentTime + 1;
                    pause(1);

                    % GATT Client: Central Device discovers all available
                    % characteristic descriptors at server.
                    fprintf(logFile, 'Time %ds: Implant (GATT Server) is receiving all available characteristic descriptors request.\n', currentTime);

                    gattClient.SubProcedure = 'Discover all descriptors';
                    gattClient.StartHandle = dec2hex(hex2dec(chrsticDiscRespCfg.AttributeHandle)+1, 4);
                    chrsticDescDiscReqPDU = generateATTPDU(gattClient);

                    % Transmit the application data (|chrsticDescDiscReqPDU|) to the client
                    % through PHY.
                    [bleWaveform, pcapPackets{count}] = helperBLETransmitData(chrsticDescDiscReqPDU);
                    count = count+1;

                    currentTime = currentTime + 1;
                    pause(1);

                    % GATT Server: Implant receives and responds to
                    % characteristic descriptor request
                    fprintf(logFile, 'Time %ds: Implant (GATT Server) is transmitting characteristic descriptor discovery.\n', currentTime);

                    % Decode the received BLE waveform and retrieve the application data.
                    receivedPDU = helperBLEDecodeData(bleWaveform);

                    % Decode received ATT PDU and generate response PDU, if applicable.
                    [chrsticDescDiscRespPDU, chrsticDescDiscReqCfg, gattServer] = receiveData(gattServer, receivedPDU);

                    fprintf("Received characteristic descriptor discovery request at the server:\n")
                    chrsticDescDiscReqCfg

                    % Transmit the application response data (|chrsticDescDiscRespPDU|) to the
                    % client through PHY.
                    [bleWaveform, pcapPackets{count}] = helperBLETransmitData(chrsticDescDiscRespPDU);
                    count = count+1;

                    % Decode the received BLE waveform and retrieve the application data.
                    receivedPDU = helperBLEDecodeData(bleWaveform);

                    % Decode received ATT PDU and generate response PDU, if applicable.
                    [~, chrsticDescDiscRespCfg] = receiveData(gattClient, receivedPDU);

                    % Expected response from the server: |'Information response'| or |'Error
                    % response'|.
                    if strcmp(chrsticDescDiscRespCfg.Opcode, 'Error response')
                        fprintf("Received error response at the client:\n")
                        chrsticDescDiscRespCfg
                        chrsticDescDiscRespMsg = ['Error response(''' chrsticDescDiscRespCfg.ErrorMessage ''')'];
                    else
                        fprintf("Received characteristic descriptor discovery response at the client:\n")
                        chrsticDescDiscRespCfg
                        descriptor = helperBluetoothID.getBluetoothName(chrsticDescDiscRespCfg.AttributeType);
                        chrsticDescDiscRespMsg = ['Characteristic descriptor discovery response(''' descriptor ''')'];
                    end

                    currentTime = currentTime + 1;
                    pause(1);

                    % --- Enable Notifications for Heart Rate Measurement ---
                    % GATT Client: Central Device enables notifications for heart rate
                    fprintf(logFile, 'Time %ds: Implant (GATT Server) is receiving enable notification request .\n', currentTime);

                    gattClient.SubProcedure = 'Write characteristic value';
                    gattClient.AttributeHandle = chrsticDescDiscRespCfg.AttributeHandle;
                    gattClient.AttributeValue = '0100';
                    enableNotificationReqPDU = generateATTPDU(gattClient);

                    % Transmit the enable notification request
                    [bleWaveform, pcapPackets{count}] = helperBLETransmitData(enableNotificationReqPDU);
                    count = count + 1;

                    currentTime = currentTime + 1;
                    pause(1);

                    % GATT Server: Implant acknowledges notification enablement
                    fprintf(logFile, 'Time %ds: Implant (GATT Server) is transmitting enable notifications response.\n', currentTime);

                    % Receive the BLE waveform
                    receivedPDU = helperBLEDecodeData(bleWaveform);

                    % Decode received ATT PDU and generate response PDU, if applicable.
                    [enableNotificationRespPDU, enableNotificationReqCfg, gattServer] = receiveData(gattServer, receivedPDU);

                    fprintf("Received enable notification request at the server:\n")
                    enableNotificationReqCfg

                    % Transmit the enable notification response
                    [bleWaveform, pcapPackets{count}] = helperBLETransmitData(enableNotificationRespPDU);
                    count = count + 1;

                    currentTime = currentTime + 1;
                    pause(1);

                    % Decode the received BLE waveform and retrieve the application data.
                    receivedPDU = helperBLEDecodeData(bleWaveform);

                    % Decode received ATT PDU and generate response PDU, if applicable.
                    [~, enableNotificationRespCfg] = receiveData(gattClient, receivedPDU);

                    % Expected response from the server: |'Write response'| or |'Error
                    % response'|.
                    if strcmp(enableNotificationRespCfg.Opcode, 'Error response')
                        fprintf("Received error response at the client:\n")
                        enableNotificationRespCfg
                        enableNotificRespMsg = ['Error response(''' enableNotificationRespCfg.ErrorMessage ''')'];
                    else
                        fprintf("Received enable notification response at the client:\n")
                        enableNotificationRespCfg
                        enableNotificRespMsg = 'Notifications enabled(''Heart rate measurement '')';
                    end

                    % Reset the random number generator seed.
                    rng('shuffle')
                    
                    % Reset the reconnection flag after full discovery
                    isReconnectionRequired = false;
                else
                    fprintf(logFile, 'Time %ds: Using cached discovery data (services, characteristics, descriptors).\n', currentTime);
                end

                fprintf(logFile, 'Time %ds: Implant (GATT Server) is transmitting heart rate measurement notification.\n', currentTime);

                % Randomly simulate a high heart rate event to trigger an emergency transmission
                heartRateMeasurementValue = randi([60 180]); % Simulate heart rate
                
                if heartRateMeasurementValue < heartRateThreshold
                    disp (['Normal Heart rate of ' num2str(heartRateMeasurementValue) ' bpm detected. Sending notification...']);
                    [gattServer, notificationPDU] = notifyHeartRateMeasurement(gattServer, heartRateMeasurementValue);
                    [bleWaveform, pcapPackets{count}] = helperBLETransmitData(notificationPDU);
                    count = count + 1;
                end
                    
                if heartRateMeasurementValue > heartRateThreshold
                    disp(['Emergency! Heart rate of ' num2str(heartRateMeasurementValue) ' bpm detected. Sending notification...']);
                    
                    % Notify heart rate measurement immediately (bypassing WuR)
                    [gattServer, notificationPDU] = notifyHeartRateMeasurement(gattServer, heartRateMeasurementValue);
                    [bleWaveform, pcapPackets{count}] = helperBLETransmitData(notificationPDU);
                    count = count + 1;
                end
                
                % Decode the received BLE waveform
                receivedPDU = helperBLEDecodeData(bleWaveform);
                
                % Decode the received heart rate measurement
                [~, notificationCfg] = receiveData(gattClient, receivedPDU);
                
                % Decode the received heart rate measurement characteristic value.
                heartRateCharacteristicValue = helperBLEDecodeAttributeValue(notificationCfg.AttributeValue, 'Heart rate measurement');
                
                heartRateMeasurementValue = heartRateCharacteristicValue.HeartRateValue;
                heartRateCharacteristicValue

                % Check and export to PCAP, but only if pcapPackets are valid
                validPackets = ~cellfun('isempty', pcapPackets);  % Check if any packet is empty
                if all(validPackets)
                    helperBLEExportToPCAP(pcapPackets, 'HeartRateImplant.pcap');
                    fprintf("Open generated pcap file 'HeartRateImplant.pcap' in a protocol analyzer to view the generated frames.\n");
                else
                    warning('Some PDUs are empty, skipping those in PCAP export.');
                    helperBLEExportToPCAP(pcapPackets(validPackets), 'HeartRateImplant.pcap');
                    fprintf("Open generated pcap file 'HeartRateImplant.pcap' in a protocol analyzer to view the generated frames.\n");
                end
                
                currentTime = currentTime + 1;
                pause(1);
                
                % Close the communication loop and reset WuR
                disp(['Time ' num2str(currentTime) 's: Putting BLE device back to sleep...']);
                fprintf(logFile, 'Time %ds: Putting BLE device back to sleep...\n', currentTime);
                isDeviceAwake = false;
                break;
            else
                disp(['Time ' num2str(currentTime) 's: No wake-up signal detected.']);
                fprintf(logFile, 'Time %ds: No wake-up signal detected.\n', currentTime);
            end
            
            % Increment the current time by 1 second
            currentTime = currentTime + 1;
            
            pause(1); % Pause for 1 second to simulate real-time
        end
        
        if ~signalDetected
            disp('Wake-up radio is going back to sleep.');
            fprintf(logFile, 'Time %ds: Wake-up radio is going back to sleep.\n', currentTime);
        end
        
        % Pause for the wake-up interval before the next check
        pause(wakeUpInterval); % Pause for 10 seconds
        
        % Increment the current time by the remaining wake-up interval to reflect the sleep period
        currentTime = currentTime + 1;
        
        % Re-seed the random number generator to ensure unpredictability
        rng('shuffle');
    end
end

% Close the log file
fclose(logFile);
