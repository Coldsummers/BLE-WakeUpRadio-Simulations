% Virtual BLE heart rate implant and central communication Simulation

% Simulated BLE Device State
isDeviceAwake = false; % Initial state: Device is in low-power sleep mode
isReconnectionRequired = false; % To simulate random reconnection events
isFirstConnectionEstablished = false; % Flag to check if the first connection is made

% Cache for discovered data (services, characteristics, and descriptors)
cache = struct('services', [], 'characteristics', [], 'descriptors', []);
isCacheInitialized = false; % Keeps track of whether cache is initialized

% Emergency heart rate notification threshold
heartRateThreshold = 140;

% Seed the random number generator based on the current time
rng('shuffle');

% Initialize the simulation time
currentTime = 0;

% Initialize the array to store pcapPackets
pcapPackets = cell(1, 11); 
count = 1;

% Open a log file to write state transitions
logFile = fopen('dcbstate_log.txt', 'w');

% Set the BLE advertising interval (1285ms = 1.285 seconds)
advertisingInterval = 1.285; 
advertisingDuration = 10;  % Advertise for 10 seconds
sleepDuration = 10;        % Sleep for 10 seconds

% Start the duty-cycled BLE advertisement loop
% Simulation time limit (in seconds)
simulationTimeLimit = 20 * 60; % 20 minutes in seconds

% Start the simulation time tracking
simulationStartTime = tic; % Start a timer to track the simulation duration

while true
    % Check if the simulation has exceeded the time limit
    elapsedTime = toc(simulationStartTime); % Get the elapsed time in seconds
    if elapsedTime >= simulationTimeLimit
        disp('Simulation time limit reached. Ending simulation.');
        break; % Exit the simulation loop
    end
    
   % If first connection has been made, skip advertisement and connection
    if isFirstConnectionEstablished && ~isReconnectionRequired
        % Directly handle heart rate notifications after first connection
        fprintf(logFile, 'Time %ds: BLE device is waking up to send heart rate measurement notification.\n', currentTime);
        
        currentTime = currentTime + 1;
        pause(1);
        
        fprintf(logFile, 'Time %ds: Implant (GATT Server) is transmitting heart rate measurement notification.\n', currentTime);

        gattServer = helperBLEGATTServer;
        gattClient = helperBLEGATTClient;

        
        % Randomly simulate a heart rate event
        heartRateMeasurementValue = randi([60 180]); % Simulate heart rate

        if heartRateMeasurementValue < heartRateThreshold
            disp (['Normal Heart rate of ' num2str(heartRateMeasurementValue) ' bpm detected. Sending notification...']);

            [gattServer, notificationPDU] = notifyHeartRateMeasurement(gattServer, heartRateMeasurementValue);
            [bleWaveform, pcapPackets{count}] = helperBLETransmitData(notificationPDU);
            count = count + 1;
            helperBLEExportToPCAP(pcapPackets, 'HeartRateImplant(2).pcap');
        end

        if heartRateMeasurementValue > heartRateThreshold
            disp(['Emergency! Heart rate of ' num2str(heartRateMeasurementValue) ' bpm detected. Sending notification...']);

            % Notify heart rate measurement immediately (bypassing WuR)
            [gattServer, notificationPDU] = notifyHeartRateMeasurement(gattServer, heartRateMeasurementValue);
            [bleWaveform, pcapPackets{count}] = helperBLETransmitData(notificationPDU);
            count = count + 1;
            helperBLEExportToPCAP(pcapPackets, 'HeartRateImplant(2).pcap');
        end

        % Decode the received BLE waveform
        receivedPDU = helperBLEDecodeData(bleWaveform);

        % Decode the received heart rate measurement
        [~, notificationCfg] = receiveData(gattClient, receivedPDU);

        % Decode the received heart rate measurement characteristic value.
        heartRateCharacteristicValue = helperBLEDecodeAttributeValue(notificationCfg.AttributeValue, 'Heart rate measurement');

        heartRateMeasurementValue = heartRateCharacteristicValue.HeartRateValue;
        heartRateCharacteristicValue

        currentTime = currentTime + 1;
        pause(1);
        
        % Put device back to sleep after sending notification
        disp(['Time ' num2str(currentTime) 's: Putting BLE device back to sleep after notification.']);
        fprintf(logFile, 'Time %ds: Putting BLE device back to sleep after notification.\n', currentTime);
        pause(sleepDuration);
        currentTime = currentTime + sleepDuration;
        
        continue; % Skip the advertisement and connection handling
    end    

    % BLE device begins advertising
    if ~isFirstConnectionEstablished || isReconnectionRequired   
        
        fprintf(logFile, 'Time %ds: BLE device is waking up to send heart rate measurement notification.\n', currentTime);
        
        currentTime = currentTime + 1;
        pause(1);
        
        disp(['Time ' num2str(currentTime) 's: Implant (GATT Server) is transmitting advertisement indication.']);
    
        % Advertise for 10 seconds continuously
        advStartTime = tic;
        isConnected = false;
        while toc(advStartTime) < advertisingDuration && ~isConnected
            % Generate BLE LL advertising channel PDU
            fprintf(logFile, 'Time %ds: Implant (GATT Server) is transmitting advertisement indication.\n', currentTime);
            
            serverAdvPDU = bleLLAdvertisingChannelPDUConfig;
            serverAdvPDU.AdvertisingData = '0201060841494442';
            advLLpdu = bleLLAdvertisingChannelPDU(serverAdvPDU);
            serverAdvPDU
            pcapPackets{count} = advLLpdu;
            count = count + 1;
            
            % Pause for the advertising interval before sending the next packet
            pause(advertisingInterval);
        
            currentTime = currentTime + advertisingInterval;
        
            % Check if client connects (randomized for simulation)
            if rand() > 0.90
                isDeviceAwake = true;
                isConnected = true;

                % Simulate connection request
                disp(['Time ' num2str(currentTime) 's: Client is sending connection indication.']);
                fprintf(logFile, 'Time %ds: Implant (GATT Server) is receiving connection indication.\n', currentTime);

                % BLE device wakes up and begins communication
                clientAdvPDU = bleLLAdvertisingChannelPDUConfig('PDUType', 'Connection indication');
                clientAdvPDU.ConnectionInterval = 6; 
                clientAdvPDU.UsedChannels = [0 4 12 16 20 24 25]; 

                % Generate the connection indication PDU
                advLLpdu = bleLLAdvertisingChannelPDU(clientAdvPDU);
                clientAdvPDU

                pcapPackets{count} = advLLpdu;
                count = count + 1;

                currentTime = currentTime + 1;
                pause(1);
                
                %break;
            end
        end
        
        if ~isConnected
            continue;
        end
    end
                % ------------------ Begin GATT Communication ------------------

        % --- Service Discovery ---
        if ~isCacheInitialized || isReconnectionRequired            
            % GATT Client: Central Device initiates service discovery
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

            % Decode the received BLE waveform
            receivedPDU = helperBLEDecodeData(bleWaveform);

            % Generate the response PDU (server response)
            [attServerRespPDU, serviceDiscReqCfg, gattServer] = receiveData(gattServer, receivedPDU);
            cache.services = serviceDiscReqCfg; 
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
            cache.characteristics = chrsticDiscReqCfg;

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
            cache.descriptors = chrsticDescDiscReqCfg; 
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

            isFirstConnectionEstablished = true;
            isCacheInitialized = true;
             % Reset the reconnection flag after full discovery
            isReconnectionRequired = false;
        else
            fprintf(logFile, 'Time %ds: Using cached discovery data (services, characteristics, descriptors).\n', currentTime);
        end               
        % Randomly simulate a high heart rate event to trigger an emergency transmission
        heartRateMeasurementValue = randi([60 180]); % Simulate heart rate

        gattServer = helperBLEGATTServer;
        gattClient = helperBLEGATTClient;

        if heartRateMeasurementValue < heartRateThreshold
            fprintf(logFile, 'Time %ds: Implant (GATT Server) is transmitting heart rate measurement notification.\n', currentTime);
            disp (['Normal Heart rate of ' num2str(heartRateMeasurementValue) ' bpm detected. Sending notification...']);

            [gattServer, notificationPDU] = notifyHeartRateMeasurement(gattServer, heartRateMeasurementValue);
            [bleWaveform, pcapPackets{count}] = helperBLETransmitData(notificationPDU);
            count = count + 1;
        %end

        else heartRateMeasurementValue > heartRateThreshold
            fprintf(logFile, 'Time %ds: Implant (GATT Server) is transmitting heart rate measurement notification.\n', currentTime);
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
            helperBLEExportToPCAP(pcapPackets, 'HeartRateImplant(2).pcap');
            fprintf("Open generated pcap file 'HeartRateImplant(2).pcap' in a protocol analyzer to view the generated frames.\n");
        else
            warning('Some PDUs are empty, skipping those in PCAP export.');
            helperBLEExportToPCAP(pcapPackets(validPackets), 'HeartRateImplant(2).pcap');
            fprintf("Open generated pcap file 'HeartRateImplant(2).pcap' in a protocol analyzer to view the generated frames.\n");
        end

        currentTime = currentTime + 1;
        pause(1);

        % Close the communication loop and reset BLE
        isDeviceAwake = false;
        
        % BLE device goes to sleep for 15 seconds after advertising
        disp(['Time ' num2str(currentTime) 's: BLE device is going to sleep.']);
        fprintf(logFile, 'Time %ds: Putting BLE device back to sleep after notification.\n', currentTime);
        pause(sleepDuration);

        % Increment the current time by the sleep duration
        currentTime = currentTime + sleepDuration;
end

% Close the log file
fclose(logFile);
