% realstretch.m
% Realtime stretch plugin version 0.1.4
% Last updated: 9 August 2020
%
% Generation code:
% validateAudioPlugin realstretch
% generateAudioPlugin -au -outdir Plugins -output macos-realstretch realstretch
% generateAudioPlugin -vst -outdir Plugins -output macos-realstretch realstretch
%
%
% NOTES:
% - Added LP filter.
% - Cleaned up comments, code.
% - Updated smoothing coefficients to improve quality.
% - Added smoothing for the wet/dry parameter to prevent audio
% discontinuities.
% - Added a second threshold for deactivating the write system. This
% prevents the write pointer from jumping numerous time and causing high
% frequency noise due to the discontinuities when the input signal is very
% close to the activation threshold.
%
% TODO:
% - Move resetting the buffers, etc to their own function. Used in the
% reset function, maybe the init function, and the reset from changing the
% window size.
%
% IDEAS:
%






classdef realstretch < audioPlugin
    %----------------------------------------------------------------------
    % TUNABLE PROPERTIES
    %----------------------------------------------------------------------
    properties
        % Stretch multiplier
        tStretch = 4;
        % Analysis window size in samples
        tWindowSize = '4096';
        
        % Threshold in dB
        tThresholdDB = -30;
        % release
        tRelease = 0.005;
        
        % lowpass filter cutoff
        tCutoff = 20000;
        
        % wet/dry control for output
        tWet = 1;
        
    end
    
    %----------------------------------------------------------------------
    % INTERFACE
    %----------------------------------------------------------------------
    properties (Constant)
        PluginInterface = audioPluginInterface( ...
            audioPluginParameter('tStretch',...
            'DisplayName','Stretch','Label','x',...
            'Mapping',{'lin',1,20}...
            ),...
            audioPluginParameter('tThresholdDB',...
            'DisplayName','Threshold',...
            'Mapping',{'lin', -60, 0},...
            'Label','dB'...
            ),...
            audioPluginParameter('tRelease',...
            'DisplayName','Release',...
            'Mapping',{'log',0.000025,0.01}),...
            audioPluginParameter('tCutoff',...
            'DisplayName','LP Cutoff Frequency','Label','Hz',...
            'Mapping',{'log',100,20000}),...
            audioPluginParameter('tWindowSize',...
            'DisplayName','Window Size',...
            'Mapping',{'enum','256','512','1024','2048','4096','6144',...
            '8192','12288','16384','24576','32768','49152','65536'}),...
            audioPluginParameter('tWet',...
            'DisplayName', 'Wet/Dry Mix',...
            'Mapping',{'lin', 0, 1}),...
            ...
            'PluginName', 'Realstretch',...
            'VendorName', 'Colin Malloy',...
            'VendorVersion', '0.1.3',...
            'InputChannels', 2,...
            'OutputChannels', 2,...
            'BackgroundColor','w');
    end
    
    %----------------------------------------------------------------------
    % PRIVATE PROPERTIES
    %----------------------------------------------------------------------
    properties (Access=private)
        % Buffer for incoming audio
        pStretchBuffer;
        % Read and write pointers for the stretch buffer
        pWritePointer = 1;
        pReadPointer = 1;
        % State variable to indicated stretch buffer write status
        pIsWriting = 0;
        pStretchCounter = 0;
        
        % Threshold value
        pThreshold = 10.^(-3/2);
        
        % Peak level for next process block
        pOldPeak = [0 0];
        % Peak level
        pLevel = [0 0];
        % Ramp in
        pRamp = linspace(0,1,32);
        pRampPointer = 1;
        pRampLength = 32;
        
        pAnalysisBuffer;
        pSynthesisBuffer;
        pPaulWindow;
        pWindowSize = 4096;
        
        pPrevWindow = zeros(48000,2);
        pPrevWinPointer = 1;
        
        pWet = 0.5;
        pStretch = 4;
        
        % Lowpass filter
        %TODO
        pLP_state = 1;
        pxh_left = 0;
        pxh_right = 0;
        pCutoff;% = (tan(pi*0.0113/2)-1) / (tan(pi*0.0113/2)+1);
        pCutoff_smooth;
    end
    
    methods
        %------------------------------------------------------------------
        % MAIN PROCESSING BLOCK
        %------------------------------------------------------------------
        function out = process(p,in)
            % init output to zero
            out = zeros(size(in));
            
            % init stored variables
            threshold = p.pThreshold;
            threshOff = threshold * 0.7;
            readPointer = p.pReadPointer;
            writePointer = p.pWritePointer;
            ramp = p.pRamp;
            rampPointer = p.pRampPointer;
            rampLength = p.pRampLength;
            peak = p.pOldPeak;
            alpha = p.tRelease;
            isWriting = p.pIsWriting;
            stretch = p.tStretch - 0.9 * (p.tStretch - p.pStretch);
            stretchCounter = p.pStretchCounter;
            window = p.pPaulWindow;
            windowSize = p.pWindowSize;
            halfWindowSize = windowSize / 2;
            hopSize = floor(halfWindowSize / stretch);
            overlap = windowSize - hopSize;
            
            prevWinPointer = p.pPrevWinPointer;
            
            for i = 1:length(in)
                % Envelope follower
                peak = maxPeak(p,in(i,:),peak,alpha);
                
                % Check write status. 0 = not writing, 1 = writing
                if isWriting == 1
                    if rampPointer < rampLength
                        input = in(i,:) .* ramp(rampPointer);
                    else
                        input = in(i,:);
                    end
                    rampPointer = rampPointer + 1;
                    
                    % Non-destructively write to the stretch buffer
                    p.pStretchBuffer(writePointer,:) = ...
                        p.pStretchBuffer(writePointer,:) + input;
                    
                    % If the peak level dips below threshold, set isWriting
                    % to 0 so that it stops writing on the next iteration.
                    if peak < threshOff
                        isWriting = 0;
                    end                    
                else % isWriting == 0 (implied)
                    % Not currently writing to stretch buffer
                    
                    % If the peak level goes above the threshold, set
                    % writePointer = readPointer, set isWriting = 1, and
                    % start writing
                    if peak >= threshold
                        % Set isWriting status to true
                        isWriting = 1;
                        % Update writePointer to match the readPointer
                        writePointer = readPointer;
                        % Set ramp in pointer to 1
                        rampPointer = 1;
                        input = in(i,:).*ramp(rampPointer);
                        % Non-desctructively write to stretch buffer
                        p.pStretchBuffer(writePointer,:) = ...
                            p.pStretchBuffer(writePointer,:) + input;
                        
                        rampPointer = rampPointer+1;
                    end
                end
                
                % Iterate the write pointer.
                writePointer = writePointer + 1;
                if writePointer > length(p.pStretchBuffer)
                    writePointer = 1;
                end
                
                % Check to see if stretchCounter > 1. If so, write a sample
                % to the analysis buffer
                numIterations = floor(stretchCounter);
                % Intermediary buffer was necessary to pass plugin
                % validation.
                tempBuffer = zeros(numIterations,2); 
                for j = 1:numIterations
                    % Accumulate samples to write to the analysis buffer
                    % while still iterating through the stretch buffer.
                    tempBuffer(j,:) = p.pStretchBuffer(readPointer,:);
                    % Clear the stretch buffer sample after writing it to
                    % the analysis buffer
                    for k = 1:2
                        p.pStretchBuffer(readPointer,k) = 0;
                    end
                    % Increment read pointer
                    readPointer = readPointer + 1;
                    if readPointer > length(p.pStretchBuffer)
                        readPointer = 1;
                    end
                    % Decrement stretchCounter by 1 so that we retain only
                    % the fractional portion when the loop is done.
                    stretchCounter = stretchCounter - 1;
                end
                write(p.pAnalysisBuffer, tempBuffer);
                
                % Increment stretchCounter by 1/stretch.
                stretchCounter = stretchCounter + 1/stretch;
                
                
            end
            
            % Check if the number of unread samples on the analysis
            % buffer >= windowSize.
            numIterations = floor(p.pAnalysisBuffer.NumUnreadSamples / windowSize);
            for j = 1:numIterations
                % Read one window's worth of sample from the analysis
                % buffer with a half window size overlap setting.
                analysisBuffer = read(p.pAnalysisBuffer, ...
                    windowSize, overlap);
                
                winFFTOut = randomizePhase(p,analysisBuffer,window);
                
                if p.pLP_state
                    winFFTOut = lowpass(p,winFFTOut);
                end
                
                synthBuff = zeros(halfWindowSize,2);
                for k = 1:halfWindowSize
                    % Add the front half of the output window to the back
                    % half from the last window
                    synthBuff(k,:) = winFFTOut(k,:) + ...
                        p.pPrevWindow(prevWinPointer,:);
                    % Reset the previous window buffer after reading the
                    % sample.
                    p.pPrevWindow(prevWinPointer,:) = [0 0];
                    % Iterate previous window pointer
                    prevWinPointer = prevWinPointer + 1;
                end
                % Reset the pointer
                prevWinPointer = 1;
                
                
                % Store the back of the stretch output
                nextWindow = zeros(halfWindowSize,2);
                for k = 1:halfWindowSize
                    nextWindow(k,:) = winFFTOut(k+halfWindowSize,:);
                end
                for k = 1:halfWindowSize
                    p.pPrevWindow(k,:) = nextWindow(k,:);
                end
                
                write(p.pSynthesisBuffer, synthBuff);
                
            end
            
            % Update smoothed wet/dry value
            p.pWet = p.tWet - 0.95 * (p.tWet - p.pWet);
            % Read from synthesis buffer and send to output
            if p.pSynthesisBuffer.NumUnreadSamples >= length(in)
                out = read(p.pSynthesisBuffer,length(in)) * p.pWet + ...
                    in * (1 - p.pWet);
                out = clamp(p,out);
            end
            
            % Store values for next process block
            p.pReadPointer = readPointer;
            p.pWritePointer = writePointer;
            p.pRampPointer = rampPointer;
            p.pOldPeak = peak;
            p.pIsWriting = isWriting;
            p.pStretchCounter = stretchCounter;
            p.pStretch = stretch;
        end
        
        %------------------------------------------------------------------
        % RESET FUNCTION
        %------------------------------------------------------------------
        function reset(p)
            p.pStretchBuffer = zeros(getSampleRate(p)*10,2);
            reset(p.pAnalysisBuffer);
            reset(p.pSynthesisBuffer);
            write(p.pAnalysisBuffer,[0 0; 0 0]);
            write(p.pSynthesisBuffer,[0 0; 0 0]);
            read(p.pAnalysisBuffer,2);
            read(p.pSynthesisBuffer,2);
            
            p.pxh_left = 0;
            p.pxh_right = 0;
        end
    end
    
    %----------------------------------------------------------------------
    % PUBLIC METHODS
    %----------------------------------------------------------------------
    methods
        %------------------------------------------------------------------
        % INITIALIZATION FUNCTION
        %------------------------------------------------------------------
        function p = realstretch()
            tenSeconds = 1920000;
            % initialize the input buffer to ten seconds
            p.pStretchBuffer = zeros(tenSeconds,2);
            % Initialize the FFT analysis/synthesis buffers, initialize
            % them with sample input and then clear those samples
            % TODO: move this to its own function. It happens enough
            % times...
            p.pAnalysisBuffer = dsp.AsyncBuffer;
            p.pSynthesisBuffer = dsp.AsyncBuffer;
            write(p.pAnalysisBuffer,[0 0; 0 0]);
            write(p.pSynthesisBuffer,[0 0; 0 0]);
            read(p.pAnalysisBuffer,2);
            read(p.pSynthesisBuffer,2);
            index = linspace(-1,1,p.pWindowSize);
            win = power(1 - power(index',2),1.25);
            p.pPaulWindow = [win win];
            
            omega_c = 2 * 20000 / p.getSampleRate;
            cutoff = (tan(pi * omega_c/2)-1) / (tan(pi*omega_c/2)+1);
            p.pCutoff = cutoff;
            p.pCutoff_smooth = cutoff;
            
        end
        
        %------------------------------------------------------------------
        % GETTERS AND SETTERS
        %------------------------------------------------------------------
        function set.tStretch(p,val)
            p.tStretch = val;
        end
        
        function set.tThresholdDB(p,val)
            p.tThresholdDB = val;
            p.pThreshold = 10.^(val/20);
            
        end
        
        function set.tRelease(p,val)
            p.tRelease = val;
        end
        
        function set.tCutoff(p,val)
            p.tCutoff = val;
            omega_c = 2 * val / p.getSampleRate;
            p.pCutoff = (tan(pi * omega_c/2)-1) / (tan(pi*omega_c/2)+1);
        end
        
        function set.tWindowSize(p,val)
            validatestring(val, {'256','512','1024','2048','4096',...
                '6144','8192','12288','16384','24576','32768','49152',...
                '65536'},'set.tWindowSize', 'tWindowSize');
            
            windowSize = real(str2double(val));
            
            p.pWindowSize = windowSize;
            resetPaulWindow(p,windowSize);
            
            % Reset buffers, etc
            % TODO: move this to its own function; could also then be used
            % in the reset function
            reset(p.pAnalysisBuffer);
            reset(p.pSynthesisBuffer);
            write(p.pAnalysisBuffer,[0 0; 0 0]);
            write(p.pSynthesisBuffer,[0 0; 0 0]);
            read(p.pAnalysisBuffer,2);
            read(p.pSynthesisBuffer,2);
            p.pPrevWindow = zeros(48000,2);
            
            p.tWindowSize = val;
        end
        
        function set.tWet(p,val)
            p.tWet = val;
        end
        
        function resetPaulWindow(p,val)
            index = linspace(-1,1,val);
            win = power(1 - power(index',2),1.25);
            p.pPaulWindow = [win win];
        end
    end
    
    %----------------------------------------------------------------------
    % PRIVATE METHODS
    %----------------------------------------------------------------------
    methods (Access=private)
        function out = clamp(~,in)
            in(in > 1.0) = 1.0;
            in(in < -1.0) = -1.0;
            out = in;
        end
        
        % This is an envelope follower with a very fast attack and a
        % variable release time.
        function out = maxPeak(~,in,level,alpha)
            inLevel = abs(in);
            if inLevel > level
                out = inLevel;
            else
                out = (1 - alpha) * level + alpha * inLevel;
            end
        end
        
        function out = lowpass(p,in)
            out = zeros(size(in));
            
            cutoff = p.pCutoff;
            cutoff_smooth = p.pCutoff_smooth;
            
            xh_left = p.pxh_left;
            xh_right = p.pxh_right;
            
            for i = 1:length(in)
                cutoff_smooth = 0.001*cutoff + 0.999*cutoff_smooth;
                
                xh_left_new = in(i,1) - cutoff_smooth * xh_left;
                xh_right_new = in(i,2) - cutoff_smooth * xh_right;
                
                ap_y_left = cutoff_smooth * xh_left_new + xh_left;
                ap_y_right = cutoff_smooth * xh_right_new + xh_right;
                
                xh_left = xh_left_new;
                xh_right = xh_right_new;
                
                out(i,1) = 0.5 * (in(i,1) + ap_y_left);
                out(i,2) = 0.5 * (in(i,2) + ap_y_right);
            end
            
            p.pCutoff_smooth = cutoff_smooth;
            p.pxh_left = xh_left;
            p.pxh_right = xh_right;
            
        end
        
        %------------------------------------------------------------------
        % MAIN FFT PROCESSING FUNCTION
        %
        % This windows the input, performs FFT, randomizes phases
        % information, performs inverse FFT, and then windows again.
        %------------------------------------------------------------------
        function out = randomizePhase(~,in,window)
            windowIn = in .* window;
            freqs = abs(real(fft(windowIn)));
            phases = rand(length(freqs),2) .* 2*pi*1j;
            y = freqs .* exp(phases);
            fftOut = real(ifft(y));
            out = fftOut .* window;
        end
    end
end