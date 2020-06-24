% realstretch.m
% Realtime stretch plugin version 0.03
% Last updated: 8 June 2020
%
%
% NOTES:
% - Added stretch parameter controls. Does not seem to need smoothing since
% there is the two layers of overlap add
%
% TODO:
% - Currently changing window size while running the plugin does not work
% since it messes with matrix sizes. This is addressable, but need to
% figure out how to implement it.
% - Plugin validation is failing because of a size mismatch on what seems
% to be the dsp.asyncbuffer write function. Need to figure out what's going
% on there in order to validate and generate plugin.
% - Based on the way vector conditionals work in Matlab and general desire
% for a better envelope detector, I want to revamp the way it is working.
% Dan recommended a max-decay filter for it. The scheme is basically this,
% if newPeak > peak, then peak = newPeak. Else, peak = peak * decay
% constant. This allows for a very quick attack, but a controlled release.
% - Implement wet/dry controls. Also create option to delay the dry signal
% so that it is output at the same time that the stretched version starts
% (delay by window size).
%
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
%         tWindowSize = 8192;
        
        % Threshold in volts
        % TODO: convert to dB
        tThreshold = 0.05;
        % release
        tRelease = 0.005;
        
    end
    
    %----------------------------------------------------------------------
    % INTERFACE
    %----------------------------------------------------------------------
    properties (Constant)
        PluginInterface = audioPluginInterface( ...
            audioPluginParameter('tStretch',...
            'DisplayName','Stretch','Label','x',...
            'Mapping',{'lin',1.5,20}...
            ),...
            audioPluginParameter('tThreshold',...
            'DisplayName','Threshold',...
            'Mapping',{'log', 0.01, 0.5}...
            ),...
            audioPluginParameter('tRelease',...
            'DisplayName','Release',...
            'Mapping',{'lin',0.00001,0.01}),...
            audioPluginParameter('tWindowSize',...
            'DisplayName','Window Size',...
            'Mapping',{'enum','256','512','1024','2048','4096','6144',...
            '8192','12288','16384','24576','32768','49152','65536'}))
    end
    
    %----------------------------------------------------------------------
    % PRIVATE PROPERTIES
    %----------------------------------------------------------------------
    properties (Access=private)
        % Buffer for incoming audio prior to sending it to the analysis
        % buffer
        pStretchBuffer;
        % Read and write pointers for the stretch buffer
        pWritePointer = 1;
        pReadPointer = 1;
        % State variable to indicated stretch buffer write status
        % 0 = not writing; 1 = writing
        pIsWriting = 0;
        pStretchCounter = 0;
        
        % Peak level for next process block
        pOldPeak = [0 0];
        % Alpha value for peak level detector
        pAlpha = 0.01;
        % Peak level
        pLevel = [0 0];
        % Ramp in coefficients and pointer
        pRamp = linspace(0,1,32);
        pRampPointer = 1;
        pRampLength = 32;
        
        pAnalysisBuffer;
        pSynthesisBuffer;
        pHann;
        pPaulWindow;
        
        pWindowSize = 4096;
        
        pPrevWindow = zeros(48000,2);
        pPrevWinPointer = 1;
        
        % TODO: Do I need this?
        pInLength;
    end
    
    methods
        %------------------------------------------------------------------
        % MAIN PROCESSING BLOCK
        %------------------------------------------------------------------
        function out = process(p,in)
            % init output to zero
            out = zeros(size(in));
            
            % init stored variables
            threshold = p.tThreshold;
            readPointer = p.pReadPointer;
            writePointer = p.pWritePointer;
            rampPointer = p.pRampPointer;
            rampLength = p.pRampLength;
            peak = p.pOldPeak;
%             alpha = p.pAlpha;
            alpha = p.tRelease;
            isWriting = p.pIsWriting;
            stretch = p.tStretch;
            stretchCounter = p.pStretchCounter;
            window = p.pPaulWindow;
%             window = p.pHann;
            windowSize = p.pWindowSize;
            halfWindowSize = windowSize / 2;
            hopSize = floor(halfWindowSize / stretch);
            overlap = windowSize - hopSize;
            p.pInLength = length(in);
            
            prevWinPointer = p.pPrevWinPointer;
            
            for i = 1:length(in)
                % Envelope follower
                peak = maxPeak(p,in(i,:),peak,alpha);
                
                % Check pIsWriting status. 0 = not writing, 1 = writing
                if isWriting == 1
                    % Currently writing to stretch buffer
                    
                    if rampPointer < rampLength
                        input = in(i,:).*p.pRamp(rampPointer);
                    else
                        input = in(i,:);
                    end
                    rampPointer = rampPointer + 1;
                    
                    % Non-destructively write to the stretch buffer
                    p.pStretchBuffer(writePointer,:) = ...
                        p.pStretchBuffer(writePointer,:) + input;
                    
                    % If the peak level dips below threshold, set isWriting
                    % to 0 so that it stop writing on the next iteration.
                    if peak < threshold
                        isWriting = 0;
                    end                    
                else % isWriting == 0 (implied)
                    % Not currently writing to stretch buffer
                    
                    % If we're not currently writing, continue to not write
                    % unless the peak level goes above threshold.
                    
                    % If the peak level goes above the threshold, set
                    % writePointer = readPointer, set isWriting = 1, and
                    % start writing
                    if peak >= threshold
                        % Set isWriting status to true
                        isWriting = 1;
                        % Update writePointer to match the readPointer
                        writePointer = readPointer;
                        % Set ramp in pointer to 1
                        % TODO: Technically, I could remove this since when
                        % the ramp pointer is 1, the ramp value is 0. Thus
                        % we could just set the ramp pointer to 2, not
                        % iterate, and then let it get taken care of in the
                        % front half of this if statement. I'll leave it
                        % for now though.
                        rampPointer = 1;
                        input = in(i,:).*p.pRamp(rampPointer);
                        % Non-desctructively write to stretch buffer
                        p.pStretchBuffer(writePointer,1:2) = ...
                            p.pStretchBuffer(writePointer,1:2) + input;
                        
                        rampPointer = rampPointer+1;
                    end
                end
                
                % Iterate the write pointer. isWriting status doesn't
                % matter. If 0, then it'll get updated when writing
                % resumes. If 1, then we need to iterate.
                writePointer = writePointer + 1;
                % If writePointer goes beyond the bounds of the buffer,
                % reset it to 1.
                if writePointer > length(p.pStretchBuffer)
                    writePointer = 1;
                end
                
                % TODO: I need to come up with a system for calculating
                % when it is time to copy from the stretch buffer to the
                % analysis buffer. It needs to occur at a rate of
                % 1/stretch. So if you're stretching by a factor of 2, you
                % iterate the read pointer every other frame. So I need to
                % calculate the stretch time. I can create a
                % pStretchCounter that can keep track of the fractional
                % sample place that it's at. I.E., if stretching by a
                % factor of 4, then increment it by 0.25 each frame. Then
                % when pStretchCounter >= 1, write a sample to the buffer
                % and decrement it by 1.
                
                % TODO: clean this up!!!
                % Note I moved the write function from inside the for loop
                % to outside, writing the whole block at once instead of
                % sample by sample. I'm not a huge fan of creating a
                % temporary buffer, but it works and doesn't throw and
                % error. It's not the end of the world.
                % TODO: Clean this up!!
                % Check to see if stretchCounter > 1. If so, write a sample
                % to the analysis buffer
                numIterations = floor(stretchCounter);
%                 write(p.pAnalysisBuffer, p.pStretchBuffer(readPointer:readPointer+numIterations-1,:));
                tempBuffer = zeros(numIterations,2);
                for j = 1:numIterations % while stretchCounter >= 1.0
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
                write (p.pAnalysisBuffer, tempBuffer);
                
                % Increment stretchCounter by 1/stretch.
                stretchCounter = stretchCounter + 1/stretch;
                
                
            end
            
            % Check if the number of unread samples on the analysis
            % buffer >= windowSize.
            % TODO: Figure out how this relates to changing the window
            % size. Right now, as you change the window size, it is
            % affecting this process, but I'm not sure if that's a problem
            % or not.
            numIterations = floor(p.pAnalysisBuffer.NumUnreadSamples / windowSize);
            for j = 1:numIterations % while p.pAnalysisBuffer.NumUnreadSamples >= windowSize
                % Read a windowSize worth of sample from the analysis
                % buffer with a half window size overlap setting.
                
                analysisBuffer = read(p.pAnalysisBuffer, ...
                    windowSize, overlap);
                
                winFFTOut = randomizePhase(p,analysisBuffer,window);
                
                % TODO: Need to accumulate the audio in temp buffer like
                % before so that no errors are thrown, but so that we can
                % also iterate through the samples.
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
                
                nextWindow = zeros(halfWindowSize,2);
                for k = 1:halfWindowSize
                    nextWindow(k,:) = winFFTOut(k+halfWindowSize,:);
                end
                
                % TODO: Convert this to a function for cleanliness of code.
                % TODO: Modify this so that it will continue to work when
                % changing the window size.
                % Sum the front half of winStretchOut and the back half
                % of the last window (overlap-add)
                write(p.pSynthesisBuffer, synthBuff);
                % Store the back half of winStretchOut for the next
                % iteration.
                
                for k = 1:halfWindowSize
                    p.pPrevWindow(k,:) = nextWindow(k,:);
                end
%                 p.pPrevWindow(prevWinPointer+halfWindowSize+1:...
%                     prevWinPointer+2*halfWindowSize,:) = ...
%                     winFFTOut(halfWindowSize+1:windowSize,:);
            end
            
            % Read from synthesis buffer and send to output
            if p.pSynthesisBuffer.NumUnreadSamples >= length(in)
                out = read(p.pSynthesisBuffer,length(in));
                out = clamp(p,out);
            end
            
            p.pReadPointer = readPointer;
            p.pWritePointer = writePointer;
            p.pRampPointer = rampPointer;
            p.pOldPeak = peak;
            p.pIsWriting = isWriting;
            p.pStretchCounter = stretchCounter;
        end
        
        %------------------------------------------------------------------
        % RESET FUNCTION
        %------------------------------------------------------------------
        function reset(p)
            % TODO: Fill this in with anything that my be needed...
            % initialize the input buffer to ten seconds
            p.pStretchBuffer = zeros(getSampleRate(p)*10,2);
            reset(p.pAnalysisBuffer);
            reset(p.pSynthesisBuffer);
            write(p.pAnalysisBuffer,[0 0; 0 0]);
            write(p.pSynthesisBuffer,[0 0; 0 0]);
            read(p.pAnalysisBuffer,2);
            read(p.pSynthesisBuffer,2);
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
            % TODO: Determine if this is necessary
            samplerate = getSampleRate(p);
            tenSeconds = 1920000;
            % initialize the input buffer to ten seconds
            p.pStretchBuffer = zeros(tenSeconds,2);
            % Initialize the FFT analysis/synthesis buffers, initialize
            % them with sample input and then clear those samples
            p.pAnalysisBuffer = dsp.AsyncBuffer;
            p.pSynthesisBuffer = dsp.AsyncBuffer;
            write(p.pAnalysisBuffer,[0 0; 0 0]);
            write(p.pSynthesisBuffer,[0 0; 0 0]);
            read(p.pAnalysisBuffer,2);
            read(p.pSynthesisBuffer,2);
            % Initialize the Hanning window
            p.pHann = hann(p.pWindowSize,'periodic');
            index = linspace(-1,1,p.pWindowSize);
            win = power(1 - power(index',2),1.25);
            p.pPaulWindow = [win win];
            
        end
        
        %------------------------------------------------------------------
        % GETTERS AND SETTERS
        %------------------------------------------------------------------
        function set.tStretch(p,val)
            p.tStretch = val;
        end
        
        function set.tThreshold(p,val)
            p.tThreshold = val;
        end
        
        function set.tRelease(p,val)
            p.tRelease = val;
        end
        
        function set.tWindowSize(p,val)
            validatestring(val, {'256','512','1024','2048','4096',...
                '6144','8192','12288','16384','24576','32768','49152',...
                '65536'},'set.tWindowSize', 'tWindowSize');
            
            windowSize = real(str2double(val));
            
            p.pWindowSize = windowSize;
            resetPaulWindow(p,windowSize);
            
            % Reset buffers, etc
            reset(p.pAnalysisBuffer);
            reset(p.pSynthesisBuffer);
            write(p.pAnalysisBuffer,[0 0; 0 0]);
            write(p.pSynthesisBuffer,[0 0; 0 0]);
            read(p.pAnalysisBuffer,2);
            read(p.pSynthesisBuffer,2);
            p.pPrevWindow = zeros(48000,2);
            
            p.tWindowSize = val;
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


% Notes:
% - It may be worthwhile later to use four states for writing to the
% buffer: startingWriting, isWriting, stoppingWriting, notWriting. The idea
% would be that during the startingWriting phase it would implement the
% ramp up (ramp length may need to depend on threshold setting). Similarly
% it would implement the ramp down during stoppingWriting. isWriting would
% write to the buffer at full gain and notWriting would do nothing.