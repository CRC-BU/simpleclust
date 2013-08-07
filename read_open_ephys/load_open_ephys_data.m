function [data, timestamps, info] = load_open_ephys_data(filename)

%
% [data, timestamps, info] = load_open_ephys_data(filename)
%
%   Loads continuous or event data files into Matlab.
%
%   Inputs:
%     
%     filename: path to file
%
%
%   Outputs:
%
%     data: either an array continuous samples, a matrix of spike waveforms,
%           or an array of event channels
%
%     timestamps: sample number
%
%     info: structure with header and other information
%
%
%
%   DISCLAIMER:
%   
%   Both the Open Ephys data format and this m-file are works in progress.
%   There's no guarantee that they will preserve the integrity of your 
%   data. They will both be updated rather frequently, so try to use the
%   most recent version of this file, if possible.
%  
%

% 
%     ------------------------------------------------------------------
% 
%     Copyright (C) 2013 Open Ephys
% 
%     ------------------------------------------------------------------
% 
%     This program is free software: you can redistribute it and/or modify
%     it under the terms of the GNU General Public License as published by
%     the Free Software Foundation, either version 3 of the License, or
%     (at your option) any later version.
% 
%     This program is distributed in the hope that it will be useful,
%     but WITHOUT ANY WARRANTY; without even the implied warranty of
%     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%     GNU General Public License for more details.
% 
%     You should have received a copy of the GNU General Public License
%     along with this program.  If not, see <http://www.gnu.org/licenses/>.
% 

filetype = filename(max(strfind(filename,'.'))+1:end); % parse filetype

fid = fopen(filename);
filesize = getfilesize(fid);

% constants
NUM_HEADER_BYTES = 1024;
SAMPLES_PER_RECORD = 1024;
RECORD_SIZE = 8 + 16 + SAMPLES_PER_RECORD*2 + 10; % size of each continuous record in bytes
RECORD_MARKER = [0 1 2 3 4 5 6 7 8 255]';

% constants for pre-allocating matrices:
MAX_NUMBER_OF_SPIKES = 1e6; 
MAX_NUMBER_OF_RECORDS = 1e4;
MAX_NUMBER_OF_CONTINUOUS_SAMPLES = 10e6;
MAX_NUMBER_OF_EVENTS = 1e5;

%-----------------------------------------------------------------------
%------------------------- EVENT DATA ----------------------------------
%-----------------------------------------------------------------------

if strcmp(filetype, 'events')
    
    disp(['Loading events file...']);
    
    index = 0;
    
    hdr = fread(fid, NUM_HEADER_BYTES, 'char*1');
    eval(char(hdr'));
    info.header = header;
    
    % pre-allocate space for event data
    data = zeros(MAX_NUMBER_OF_EVENTS, 1);
    timestamps = zeros(MAX_NUMBER_OF_EVENTS, 1);
    info.sampleNum = zeros(MAX_NUMBER_OF_EVENTS, 1);
    info.nodeId = zeros(MAX_NUMBER_OF_EVENTS, 1);
    info.eventType = zeros(MAX_NUMBER_OF_EVENTS, 1);
    info.eventId = zeros(MAX_NUMBER_OF_EVENTS, 1);
    
    while ftell(fid) + 22 < filesize % at least one record remains
        
        index = index + 1;
        
        timestamps(index) = fread(fid, 1, 'uint64', 0, 'l');
        
        info.sampleNum(index) = fread(fid, 1, 'int16'); % implemented after 11/16/12
        info.eventType(index) = fread(fid, 1, 'uint8');
        info.nodeId(index) = fread(fid, 1, 'uint8');
        info.eventId(index) = fread(fid, 1, 'uint8');
        data(index) = fread(fid, 1, 'uint8'); % save event channel as 'data' (maybe not the best thing to do)
        
    end
    
    % crop the arrays to the correct size
    data(index+1:end) = [ ];
    timestamps(index+1:end) = [ ];
    info.sampleNum(index+1:end) = [ ];
    info.nodeId(index+1:end) = [ ];
    info.eventType(index+1:end) = [ ];
    info.eventId(index+1:end) = [ ];    
    
%-----------------------------------------------------------------------
%---------------------- CONTINUOUS DATA --------------------------------
%-----------------------------------------------------------------------
    
elseif strcmp(filetype, 'continuous')
    
    disp(['Loading ' filename '...']);
    
    index = 0;
    
    hdr = fread(fid, NUM_HEADER_BYTES, 'char*1');
    eval(char(hdr'));
    info.header = header;
    
    % pre-allocate space for continuous data
    data = zeros(MAX_NUMBER_OF_CONTINUOUS_SAMPLES, 1);
    info.ts = zeros(1, MAX_NUMBER_OF_RECORDS);
    info.nsamples = zeros(1, MAX_NUMBER_OF_RECORDS);

    current_sample = 0;
    
    while ftell(fid) + RECORD_SIZE < filesize % at least one record remains
     
        go_back_to_start_of_loop = 0;
        
        index = index + 1;
        
        timestamp = fread(fid, 1, 'uint64', 0, 'l');
        nsamples = fread(fid, 1, 'int16',0,'l');
        
        if nsamples ~= SAMPLES_PER_RECORD
            
            disp(['  Found corrupted record...searching for record marker.']);
 
             % switch to searching for record markers
            
             last_ten_bytes = zeros(size(RECORD_MARKER));

             for bytenum = 1:RECORD_SIZE*5
                 
                 byte = fread(fid, 1, 'uint8');
                 
                 last_ten_bytes = circshift(last_ten_bytes,-1);
                 
                 last_ten_bytes(10) = double(byte);
                 
                 if last_ten_bytes(10) == RECORD_MARKER(end);
                    
                     sq_err = sum((last_ten_bytes - RECORD_MARKER).^2);
                     
                     if (sq_err == 0)
                         disp(['   Found a record marker after ' int2str(bytenum) ' bytes!']);
                         go_back_to_start_of_loop = 1;
                         break; % from 'for' loop
                     end
                 end
             end
             
             % if we made it through the approximate length of 5 records without
             % finding a marker, abandon ship.
             if bytenum == RECORD_SIZE*5
                            
                  disp(['Loading failed at block number ' int2str(index) '. Found ' ...
                   int2str(nsamples) ' samples.'])
              
                 break; % from 'while' loop
                 
             end
             
             
        end
        
        if ~go_back_to_start_of_loop
        
            block = fread(fid, nsamples, 'int16', 0, 'b'); % read in data
 
            fread(fid, 10, 'char*1'); % read in record marker and discard

            data(current_sample+1:current_sample+nsamples) = block;

            current_sample = current_sample + nsamples;

            info.ts(index) = timestamp;
            info.nsamples(index) = nsamples;
        
        end
        
    end
    
    % crop data to the correct size
    data(current_sample+1:end) = [ ];
    info.ts(index+1:end) = [ ];
    info.nsamples(index+1:end) = [ ];
    
    timestamps = nan(size(data));
    
    current_sample = 0;
    
    for record = 1:length(info.ts)-1
       
        ts_interp = linspace(info.ts(record),info.ts(record+1),info.nsamples(record)+1);
        
        timestamps(current_sample+1:current_sample+info.nsamples(record)) = ts_interp(1:end-1);
        
        current_sample = current_sample + info.nsamples(record);
    end
    
    % NOTE: the timestamps for the last record will not be interpolated
   
    
%-----------------------------------------------------------------------
%--------------------------- SPIKE DATA --------------------------------
%-----------------------------------------------------------------------
    
elseif strcmp(filetype, 'spikes')
        
    disp(['Loading spikes file...']);
    
    index = 0;
    
    hdr = fread(fid, NUM_HEADER_BYTES, 'char*1');
    eval(char(hdr'));
    info.header = header;
    
    num_channels = info.header.num_channels;
    %num_samples = **NOT CURRENTLY WRITTEN TO HEADER**
    
    % pre-allocate space for spike data
    %data = zeros(MAX_NUMBER_OF_SPIKES, num_samples, num_channels);
    timestamps = zeros(1, MAX_NUMBER_OF_SPIKES);
    info.source = zeros(1, MAX_NUMBER_OF_SPIKES);
    
    current_spike = 0;
    
    while ftell(fid) + 512 < filesize % at least one record remains
     
        current_spike = current_spike + 1;
     
        idx = 0;
        
        event_type = fread(fid, 1, 'uint8'); % always equal to 4; ignore
        
        idx = idx + 1;
        
        timestamps(current_spike) = fread(fid, 1, 'uint64', 0, 'l');
        
        idx = idx + 8;
        
        info.source(current_spike) = fread(fid, 1, 'uint16', 0, 'l');
        
        idx = idx + 2;
        
        num_channels = fread(fid, 1, 'uint16', 0, 'l');
        num_samples = fread(fid, 1, 'uint16', 0, 'l');
        
        idx = idx + 4;
        
        if num_samples < 1 || num_samples > 10000
            disp(['Loading failed at block number ' int2str(current_spike) '. Found ' ...
                  int2str(num_samples) ' samples.'])
              break;
        end
        
        waveforms = fread(fid, num_channels*num_samples, 'uint16', 0, 'l');
        
        idx = idx + num_channels*num_samples*2;
        
        wv = reshape(waveforms, num_samples, num_channels);
        
        channel_gains = fread(fid, num_channels, 'uint16', 0, 'l');
        
        gain = double(repmat(channel_gains', num_samples, 1))/1000;
        
        channel_thresholds = fread(fid, num_channels, 'uint16', 0, 'l');
        
        idx = idx + num_channels*2*2;
        
        data(current_spike, :, :) = double(wv-32768)./gain;

    end
    
    %data(current_spike+1:end,:,:) = [ ];
    timestamps(current_spike+1:end) = [ ];
    info.source(current_spike+1:end) = [ ];
    
else
    
    error('File extension not recognized. Please use a ''.continuous'', ''.spikes'', or ''.events'' file.');
    
end

fclose(fid); % close the file

end


function filesize = getfilesize(fid)

fseek(fid,0,'eof');
filesize = ftell(fid);
fseek(fid,0,'bof');

end